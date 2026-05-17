%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "symbols.h"
#include "codegen.h"

/* ---- tracing control ---- */
int Opt_Trace = 0;
int Opt_LexPrint = 0;
int Opt_CodePrint = 0;
int Opt_Warning = 1;
int Opt_Dump = 0;
int Opt_ErrorExit = 0;
int Opt_Demo = 0;
#define Trace(t)    if (Opt_Trace) printf("%s\n", t)

/* ---- forward decls ---- */
int  yylex(void);
int  yyerror(const char *msg);
extern int   linenum;
extern FILE *yyin;
extern int yydebug;

static int semantic_errors = 0;
static void sem_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "line %d: ", linenum);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    semantic_errors++;
}
static void sem_warn(const char *fmt, ...) {
    va_list ap;
    if (!Opt_Warning) return;
    va_start(ap, fmt);
    fprintf(stderr, "line %d: warning: ", linenum);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}
/* strict type matching per spec: types of LHS and RHS of every
   assignment must match. T_UNKNOWN suppresses cascade errors. */
static int type_assignable(Type lhs, Type rhs) {
    if (lhs == T_UNKNOWN || rhs == T_UNKNOWN) return 1;
    return lhs == rhs;
}
static Type check_arith(Type a, Type b, const char *op) {
    if (a == T_UNKNOWN || b == T_UNKNOWN) return T_UNKNOWN;
    if (a == b && (a == T_INT || a == T_REAL)) return a;
    sem_error("type mismatch on '%s': %s vs %s", op, type_name(a), type_name(b));
    return T_UNKNOWN;
}
static Type check_mod(Type a, Type b) {
    if (a == T_UNKNOWN || b == T_UNKNOWN) return T_UNKNOWN;
    if (a == T_INT && b == T_INT) return T_INT;
    sem_error("'mod' requires integer operands (got %s and %s)",
              type_name(a), type_name(b));
    return T_UNKNOWN;
}
static void check_cmp(Type a, Type b, const char *op) {
    if (a == T_UNKNOWN || b == T_UNKNOWN) return;
    if (a != b)
        sem_error("type mismatch on '%s': %s vs %s", op, type_name(a), type_name(b));
}
static void check_bool_op(Type a, const char *op) {
    if (a == T_UNKNOWN) return;
    if (a != T_BOOL)
        sem_error("operand of '%s' must be boolean (got %s)", op, type_name(a));
}
static void check_cond(Type a, const char *where) {
    if (a == T_UNKNOWN) return;
    if (a != T_BOOL)
        sem_error("%s condition must be boolean (got %s)", where, type_name(a));
}

/* ---- pending-id buffer for var/const decls with id_list ---- */
#define PENDING_MAX 256
static char *pending_ids[PENDING_MAX];
static int   pending_count = 0;
static void  pending_reset(void) { pending_count = 0; }
static void  pending_add(char *n) {
    if (pending_count < PENDING_MAX) pending_ids[pending_count++] = n;
}

#define MAX_FORMALS 64
static Type formal_types[MAX_FORMALS];
static int formal_count = 0;
static SymEntry *current_subprog = NULL;
static void formal_reset(void) { formal_count = 0; }
static void formal_add(Type t) {
    if (formal_count < MAX_FORMALS) formal_types[formal_count++] = t;
}
static void formal_commit(void) {
    if (current_subprog) sym_set_params(current_subprog, formal_types, formal_count);
}

#define MAX_ARG_PACKS 256
#define MAX_ARGS_PER_CALL 64
typedef struct {
    Type types[MAX_ARGS_PER_CALL];
    int count;
} ArgPack;
static ArgPack argpacks[MAX_ARG_PACKS];
static int argpack_top = 0;
static int arg_new_empty(void) {
    int id = argpack_top++;
    if (id >= MAX_ARG_PACKS) return MAX_ARG_PACKS - 1;
    argpacks[id].count = 0;
    return id;
}
static int arg_single(Type t) {
    int id = arg_new_empty();
    if (argpacks[id].count < MAX_ARGS_PER_CALL) argpacks[id].types[argpacks[id].count++] = t;
    return id;
}
static int arg_append(int id, Type t) {
    if (id >= 0 && id < MAX_ARG_PACKS && argpacks[id].count < MAX_ARGS_PER_CALL)
        argpacks[id].types[argpacks[id].count++] = t;
    return id;
}
static Type check_call(const char *name, int arg_id, int in_expr) {
    int i;
    SymEntry *e = sym_lookup(name);
    if (!e) {
        sem_error("call to undeclared '%s'", name);
        return T_UNKNOWN;
    }
    if (in_expr && e->kind == S_PROC) {
        sem_error("procedure '%s' cannot be used in expression", name);
        return T_UNKNOWN;
    }
    if (!in_expr && e->kind == S_FUNC) {
        sem_warn("function '%s' called as statement (return value ignored)", name);
    }
    if (e->kind != S_FUNC && e->kind != S_PROC) {
        sem_error("'%s' is not callable", name);
        return T_UNKNOWN;
    }
    if (e->param_count != argpacks[arg_id].count) {
        sem_error("'%s' expects %d args but got %d", name, e->param_count, argpacks[arg_id].count);
        return e->type;
    }
    for (i = 0; i < e->param_count; i++) {
        if (!type_assignable(e->param_types[i], argpacks[arg_id].types[i])) {
            sem_error("arg %d of '%s' expects %s but got %s", i + 1, name,
                      type_name(e->param_types[i]), type_name(argpacks[arg_id].types[i]));
        }
    }
    return e->type;
}

/* end-identifier comparison helper */
static void check_end_id(const char *start, const char *end, const char *what) {
    if (strcmp(start, end) != 0) {
        fprintf(stderr,
                "line %d: %s '%s' does not match end identifier '%s'\n",
                linenum, what, start, end);
    }
}

/* ---- for-loop counter immutability ----
 * Spec §2.3.4: "The iteration variable counter cannot be modified within
 * the loop." We track the active counters as a stack so that nested for
 * loops still flag any assignment that targets one of them. */
#define FOR_STACK_MAX 64
static const char *for_counters[FOR_STACK_MAX];
static int for_top = 0;
static void for_push(const char *name) {
    if (for_top < FOR_STACK_MAX) for_counters[for_top++] = name;
}
static void for_pop(void) {
    if (for_top > 0) for_top--;
}
static int for_is_active(const char *name) {
    for (int i = 0; i < for_top; i++)
        if (strcmp(for_counters[i], name) == 0) return 1;
    return 0;
}

typedef struct {
    int Lbegin, Lexit;
    SymEntry *counter;
    int down;          /* 1 if downto, 0 if to */
} ForCtx;
static ForCtx for_ctx[FOR_STACK_MAX];
static int    for_ctx_top = 0;

/* if-stmt label tracking. The grammar shares a single if_stmt prefix and
 * a separate if_tail nonterminal, so we pass labels through this stack
 * rather than via $<ival> across optional alternatives. */
#define IF_STACK_MAX 64
static int if_lbl_stack[IF_STACK_MAX];
static int if_lbl_top = 0;
static void if_lbl_push(int x) { if (if_lbl_top < IF_STACK_MAX) if_lbl_stack[if_lbl_top++] = x; }
static int  if_lbl_pop(void)   { return if_lbl_top > 0 ? if_lbl_stack[--if_lbl_top] : 0; }

/* expression attribute: carries the type plus an optional constant-int
 * value so that array-index productions can fold a literal index and
 * verify it against the declared [lo,hi] bounds at compile time. */
typedef struct {
    int type;          /* Type */
    int is_const_int;  /* 1 if const_val holds a known integer */
    int const_val;
} ExprAttr;
static ExprAttr ea_type(Type t)        { ExprAttr e; e.type = t; e.is_const_int = 0; e.const_val = 0; return e; }
static ExprAttr ea_const_int(int v)    { ExprAttr e; e.type = T_INT; e.is_const_int = 1; e.const_val = v; return e; }

/* ---- code generation helpers ---- */
static int  in_subprog = 0;     /* 1 inside a func/proc body, 0 in global scope */

/* a const_expr's literal value gets stashed here so the enclosing
 * declaration can both pass type via $$ and recover the literal value. */
static ConstVal last_const = {0,0,NULL,0};
static void cset_int(long v)   { if (last_const.sval) free(last_const.sval); last_const.sval = NULL; last_const.ival = v; last_const.has_value = 1; }
static void cset_real(double v){ if (last_const.sval) free(last_const.sval); last_const.sval = NULL; last_const.rval = v; last_const.has_value = 1; }
static void cset_str(const char *s){ if (last_const.sval) free(last_const.sval); last_const.sval = s ? strdup(s) : NULL; last_const.has_value = 1; }
static void cset_copy(const ConstVal *src){
    if (last_const.sval) free(last_const.sval);
    last_const = *src;
    if (src->sval) last_const.sval = strdup(src->sval);
}
static void csave_to(SymEntry *e){
    if (!e) return;
    if (e->cval.sval) { free(e->cval.sval); e->cval.sval = NULL; }
    e->cval = last_const;
    if (last_const.sval) e->cval.sval = strdup(last_const.sval);
}
static void emit_const_load_from_last(Type t){
    /* helper for var-initializer emission: emit a literal-load for the
     * value currently stashed in last_const, treated as type t. */
    SymEntry tmp; memset(&tmp, 0, sizeof(tmp));
    tmp.type = t; tmp.cval = last_const; tmp.cval.has_value = 1;
    gen_load_const_value(&tmp);
}

static void check_array_index_bounds(SymEntry *arr, const char *name, ExprAttr idx) {
    if (!arr || arr->type != T_ARRAY) return;
    if (!idx.is_const_int) return;
    if (idx.const_val < arr->array_lo || idx.const_val > arr->array_hi)
        sem_error("array index %d for '%s' out of bounds [%d,%d]",
                  idx.const_val, name, arr->array_lo, arr->array_hi);
}
%}

%union {
    int      ival;
    double   dval;
    char    *sval;
    ExprAttr expr;
}

%token <sval> ID STR_CONST
%token <ival> INT_CONST BOOL_CONST
%token <dval> REAL_CONST

/* keywords */
%token KW_BEGIN END PROGRAM VAR CONST ARRAY OF
%token FUNCTION PROCEDURE RETURN
%token IF THEN ELSE WHILE DO REPEAT UNTIL FOR TO DOWNTO
%token WRITE WRITELN READ
%token INTEGER REAL BOOLEAN STRING
%token ASSIGN LE GE NE LT GT EQ
%token AND OR NOT MOD
%token IN GOTO CASE TYPE CONTINUE EXIT LOOP

%type <ival> scalar_type opt_init args expr_list const_expr array_dim
%type <expr> expr

/* precedence: lowest first */
%left  OR
%left  AND
%left  NOT
%left  LT LE EQ GE GT NE
%left  '+' '-'
%left  '*' '/' MOD
%right UMINUS
%nonassoc IF_THEN_ONLY
%nonassoc ELSE
%debug

%%

program
    : PROGRAM ID ';'
        {
            SymEntry *e = sym_make($2, S_PROG, T_VOID);
            if (sym_insert(e) < 0)
                fprintf(stderr, "line %d: duplicate program name '%s'\n",
                        linenum, $2);
            sym_push_scope();
            gen_class_begin($2);
        }
      decls subprogs
        { gen_main_begin(); sym_reset_locals(); in_subprog = 1; }
      KW_BEGIN opt_stmts END ID '.'
        {
            check_end_id($2, $11, "program");
            sym_pop_scope();
            gen_main_end();
            gen_class_end();
            in_subprog = 0;
            Trace("Reducing to program");
        }
    ;

opt_stmts
    : /* empty (program body may have zero statements per spec) */
    | stmts
    ;

/* ---- declarations at program / local level ---- */

decls
    : /* empty */
    | decls decl
    ;

decl
    : const_decl
    | var_decl
    ;

/* Each declaration line must start with its own `const` / `var` keyword
 * (per the lecture-slide clarification of spec §2.1). Multiple identifiers
 * sharing one type still group via id_list. */
const_decl
    : CONST ID EQ const_expr ';'
        {
            SymEntry *e = sym_make($2, S_CONST, (Type)$4);
            csave_to(e);
            if (sym_insert(e) < 0)
                fprintf(stderr, "line %d: duplicate declaration of '%s'\n",
                        linenum, $2);
            Trace("Reducing to const_decl");
        }
    ;

var_decl
    : VAR id_list ':' scalar_type opt_init ';'
        {
            Type vtype = (Type)$4;
            int has_init = ((Type)$5 != T_UNKNOWN);
            if (has_init) {
                for (int i = 0; i < pending_count; i++) {
                    if (!type_assignable(vtype, (Type)$5)) {
                        sem_error("cannot initialize '%s' (%s) with %s",
                                  pending_ids[i], type_name(vtype), type_name((Type)$5));
                    }
                }
            }
            for (int i = 0; i < pending_count; i++) {
                SymEntry *e = sym_make(pending_ids[i], S_VAR, vtype);
                if (in_subprog) e->local_num = sym_alloc_local();
                if (has_init) csave_to(e);
                if (sym_insert(e) < 0) {
                    fprintf(stderr, "line %d: duplicate declaration of '%s'\n",
                            linenum, pending_ids[i]);
                    continue;
                }
                if (in_subprog) {
                    if (has_init) {
                        emit_const_load_from_last(vtype);
                        gen_store_var(e);
                    }
                } else {
                    gen_field(e->name, vtype, has_init,
                              last_const.ival, last_const.rval, last_const.sval);
                }
            }
            pending_count = 0;
            Trace("Reducing to var_decl(scalar)");
        }
    | VAR id_list ':' ARRAY '[' array_dim ',' array_dim ']' OF scalar_type ';'
        {
            int lo = $6, hi = $8;
            Type elem = (Type)$11;
            if (lo > hi)
                sem_error("array bounds [%d,%d] invalid (lo > hi)", lo, hi);
            int size = hi - lo + 1;
            const char *jvm_elem = (elem == T_REAL ? "float" : "int");
            for (int i = 0; i < pending_count; i++) {
                SymEntry *e = sym_make(pending_ids[i], S_VAR, T_ARRAY);
                e->elem_type = elem;
                e->array_lo = lo;
                e->array_hi = hi;
                if (in_subprog) e->local_num = sym_alloc_local();
                if (sym_insert(e) < 0) {
                    fprintf(stderr, "line %d: duplicate declaration of '%s'\n",
                            linenum, pending_ids[i]);
                    continue;
                }
                if (in_subprog) {
                    gen_local_array_alloc(e->local_num, size, jvm_elem);
                } else {
                    gen_global_array_field(e->name, jvm_elem);
                }
            }
            pending_count = 0;
            Trace("Reducing to var_decl(array)");
        }
    ;

array_dim
    : INT_CONST          { $$ = $1; }
    | '-' INT_CONST      { $$ = -$2; }
    ;

id_list
    : ID                 { pending_reset(); pending_add($1); }
    | id_list ',' ID     { pending_add($3); }
    ;

/* spec only allows a constant expression as the initializer:
 * literal, signed literal, or a previously-declared const id. */
const_expr
    : INT_CONST                    { cset_int($1); $$ = T_INT; }
    | REAL_CONST                   { cset_real($1); $$ = T_REAL; }
    | STR_CONST                    { cset_str($1); $$ = T_STR; }
    | BOOL_CONST                   { cset_int($1); $$ = T_BOOL; }
    | '-' INT_CONST  %prec UMINUS  { cset_int(-$2); $$ = T_INT; }
    | '-' REAL_CONST %prec UMINUS  { cset_real(-$2); $$ = T_REAL; }
    | ID
        {
            SymEntry *e = sym_lookup($1);
            if (!e) { sem_error("undeclared '%s' in constant expression", $1); $$ = T_UNKNOWN; }
            else if (e->kind != S_CONST) { sem_error("'%s' is not a constant", $1); $$ = T_UNKNOWN; }
            else { cset_copy(&e->cval); $$ = e->type; }
        }
    ;

opt_init
    : /* empty */     { $$ = T_UNKNOWN; }
    | EQ  const_expr  { $$ = $2; }
    ;

scalar_type
    : INTEGER   { $$ = T_INT; }
    | REAL      { $$ = T_REAL; }
    | BOOLEAN   { $$ = T_BOOL; }
    | STRING    { $$ = T_STR; }
    ;

/* ---- subprograms ---- */

subprogs
    : /* empty */
    | subprogs subprog
    ;

subprog
    : func_decl
    | proc_decl
    ;

func_decl
    : FUNCTION ID
        {
            SymEntry *e = sym_make($2, S_FUNC, T_UNKNOWN);
            if (sym_insert(e) < 0)
                fprintf(stderr, "line %d: duplicate function '%s'\n",
                        linenum, $2);
            current_subprog = e;
            formal_reset();
            sym_push_scope();
            sym_reset_locals();
        }
      formals ':' scalar_type ';'
        {
            if (current_subprog) current_subprog->type = (Type)$6;
            formal_commit();
            gen_method_begin($2, (Type)$6, formal_types, formal_count);
            in_subprog = 1;
        }
      local_decls
      KW_BEGIN stmts END ID ';'
        {
            check_end_id($2, $13, "function");
            gen_method_end(current_subprog ? current_subprog->type : T_INT);
            current_subprog = NULL;
            in_subprog = 0;
            sym_pop_scope();
            Trace("Reducing to function");
        }
    ;

proc_decl
    : PROCEDURE ID
        {
            SymEntry *e = sym_make($2, S_PROC, T_VOID);
            if (sym_insert(e) < 0)
                fprintf(stderr, "line %d: duplicate procedure '%s'\n",
                        linenum, $2);
            current_subprog = e;
            formal_reset();
            sym_push_scope();
            sym_reset_locals();
        }
      formals ';'
        {
            formal_commit();
            gen_method_begin($2, T_VOID, formal_types, formal_count);
            in_subprog = 1;
        }
      local_decls
      KW_BEGIN stmts END ID ';'
        {
            check_end_id($2, $11, "procedure");
            gen_method_end(T_VOID);
            current_subprog = NULL;
            in_subprog = 0;
            sym_pop_scope();
            Trace("Reducing to procedure");
        }
    ;

formals
    : /* empty */
    | '(' ')'
    | '(' formal_list ')'
    ;

formal_list
    : formal
    | formal_list ',' formal
    ;

formal
    : ID ':' scalar_type
        {
            SymEntry *e = sym_make($1, S_PARAM, (Type)$3);
            e->local_num = sym_alloc_local();
            if (sym_insert(e) < 0)
                fprintf(stderr, "line %d: duplicate parameter '%s'\n",
                        linenum, $1);
            formal_add((Type)$3);
        }
    ;

local_decls
    : /* empty */
    | local_decls decl
    ;

/* ---- statements ---- */

stmts
    : stmt
    | stmts stmt
    ;

stmt
    : simple_stmt
    | block_stmt
    | if_stmt
    | while_stmt
    | repeat_stmt
    | for_stmt
    | call_stmt
    ;

simple_stmt
    : ID ASSIGN expr ';'
        {
            SymEntry *lhs = sym_lookup($1);
            if (!lhs) sem_error("assignment to undeclared '%s'", $1);
            else if (lhs->kind == S_CONST) sem_error("cannot assign to const '%s'", $1);
            else if (lhs->kind == S_FUNC || lhs->kind == S_PROC)
                sem_error("'%s' is not a variable", $1);
            else if (for_is_active($1))
                sem_error("for-loop counter '%s' cannot be modified inside its loop", $1);
            else if (!type_assignable(lhs->type, (Type)$3.type))
                sem_error("cannot assign %s to '%s' (%s)", type_name((Type)$3.type), $1, type_name(lhs->type));
            else gen_store_var(lhs);
            Trace("Reducing to assignment");
        }
    | ID '[' { SymEntry *a = sym_lookup($1); if (a) gen_load_array_addr(a); } expr ']' ASSIGN expr ';'
        {
            SymEntry *lhs = sym_lookup($1);
            if (!lhs) sem_error("assignment to undeclared '%s'", $1);
            else if (lhs->type != T_ARRAY) sem_error("'%s' is not array", $1);
            else {
                if ((Type)$4.type != T_INT)
                    sem_error("array index of '%s' must be integer (got %s)",
                              $1, type_name((Type)$4.type));
                else
                    check_array_index_bounds(lhs, $1, $4);
                if (!type_assignable(lhs->elem_type, (Type)$7.type))
                    sem_error("cannot assign %s to '%s' element (%s)",
                              type_name((Type)$7.type), $1, type_name(lhs->elem_type));
                else gen_array_store(lhs->elem_type);
            }
            Trace("Reducing to array assignment");
        }
    | WRITE { gen_print_begin(); } expr ';'
        { gen_print_end((Type)$3.type, 0); Trace("Reducing to write"); }
    | WRITELN { gen_print_begin(); } expr ';'
        { gen_print_end((Type)$3.type, 1); Trace("Reducing to writeln"); }
    | READ ID ';'
        {
            SymEntry *e = sym_lookup($2);
            if (!e) sem_error("read into undeclared '%s'", $2);
            else if (e->kind == S_CONST) sem_error("cannot read into const '%s'", $2);
            else if (e->kind == S_FUNC || e->kind == S_PROC)
                sem_error("'%s' is not a variable", $2);
            else if (for_is_active($2))
                sem_error("for-loop counter '%s' cannot be modified inside its loop", $2);
            else gen_read(e);
            Trace("Reducing to read");
        }
    | RETURN ';'
        {
            if (current_subprog && current_subprog->kind == S_FUNC)
                sem_error("function '%s' must return a value of type %s",
                          current_subprog->name, type_name(current_subprog->type));
            else gen_return_void();
            Trace("Reducing to return");
        }
    | RETURN expr ';'
        {
            if (current_subprog && current_subprog->kind == S_PROC)
                sem_error("procedure '%s' cannot return a value",
                          current_subprog->name);
            else if (current_subprog && current_subprog->kind == S_FUNC) {
                if (!type_assignable(current_subprog->type, (Type)$2.type))
                    sem_error("return type mismatch in '%s': expected %s, got %s",
                              current_subprog->name,
                              type_name(current_subprog->type),
                              type_name((Type)$2.type));
                else gen_return_value(current_subprog->type);
            } else {
                sem_error("'return' with value outside of function");
            }
            Trace("Reducing to return-expr");
        }
    ;

block_stmt
    : KW_BEGIN { sym_push_scope(); } local_decls stmts END ';'
        { sym_pop_scope(); Trace("Reducing to block"); }
    ;

if_stmt
    : IF '(' expr ')' THEN
        { check_cond((Type)$3.type, "if");
          int Lf = gen_new_label(); gen_ifeq(Lf); if_lbl_push(Lf); }
      stmt if_tail
        { Trace("Reducing to if"); }
    ;

if_tail
    : %prec IF_THEN_ONLY
        { gen_label(if_lbl_pop()); }
    | ELSE
        { int Le = gen_new_label(); gen_goto(Le);
          gen_label(if_lbl_pop()); if_lbl_push(Le); }
      stmt
        { gen_label(if_lbl_pop()); }
    ;

while_stmt
    : WHILE
        { int Lb = gen_new_label(); gen_label(Lb); $<ival>$ = Lb; }
      expr DO
        { check_cond((Type)$3.type, "while");
          int Lx = gen_new_label(); gen_ifeq(Lx); $<ival>$ = Lx; }
      stmt
        { gen_goto($<ival>2); gen_label($<ival>5); Trace("Reducing to while"); }
    ;

repeat_stmt
    : REPEAT
        { int Lb = gen_new_label(); gen_label(Lb); $<ival>$ = Lb; }
      stmts UNTIL expr ';'
        { check_cond((Type)$5.type, "repeat-until");
          /* repeat..until: keep looping while condition is FALSE */
          gen_ifeq($<ival>2); Trace("Reducing to repeat"); }
    ;

for_stmt
    : FOR ID ASSIGN expr TO expr DO
        {
            SymEntry *c = sym_lookup($2);
            if (!c) sem_error("for-counter '%s' undeclared", $2);
            else if (c->kind == S_CONST) sem_error("for-counter '%s' is const", $2);
            else if (c->type != T_INT) sem_error("for-counter '%s' must be integer", $2);
            if ((Type)$4.type != T_INT) sem_error("for-loop init expr must be integer (got %s)", type_name((Type)$4.type));
            if ((Type)$6.type != T_INT) sem_error("for-loop final expr must be integer (got %s)", type_name((Type)$6.type));
            for_push($2);

            int tmp = sym_alloc_local();
            int Lb = gen_new_label();
            int Lx = gen_new_label();
            gen_istore_slot(tmp);              /* save hi */
            if (c) gen_store_var(c);           /* save lo into counter */
            gen_label(Lb);
            if (c) gen_load_var(c);
            gen_iload_slot(tmp);
            gen_isub();
            gen_ifgt(Lx);                      /* counter > hi -> exit */
            if (for_ctx_top < FOR_STACK_MAX) {
                for_ctx[for_ctx_top].Lbegin = Lb;
                for_ctx[for_ctx_top].Lexit = Lx;
                for_ctx[for_ctx_top].counter = c;
                for_ctx[for_ctx_top].down = 0;
                for_ctx_top++;
            }
        }
      stmt
        {
            for_pop();
            if (for_ctx_top > 0) {
                ForCtx fc = for_ctx[--for_ctx_top];
                if (fc.counter) {
                    gen_load_var(fc.counter);
                    gen_load_int(1);
                    gen_arith(T_INT, '+');
                    gen_store_var(fc.counter);
                }
                gen_goto(fc.Lbegin);
                gen_label(fc.Lexit);
            }
            Trace("Reducing to for");
        }
    | FOR ID ASSIGN expr DOWNTO expr DO
        {
            SymEntry *c = sym_lookup($2);
            if (!c) sem_error("for-counter '%s' undeclared", $2);
            else if (c->kind == S_CONST) sem_error("for-counter '%s' is const", $2);
            else if (c->type != T_INT) sem_error("for-counter '%s' must be integer", $2);
            if ((Type)$4.type != T_INT) sem_error("for-loop init expr must be integer (got %s)", type_name((Type)$4.type));
            if ((Type)$6.type != T_INT) sem_error("for-loop final expr must be integer (got %s)", type_name((Type)$6.type));
            for_push($2);

            int tmp = sym_alloc_local();
            int Lb = gen_new_label();
            int Lx = gen_new_label();
            gen_istore_slot(tmp);              /* save hi (the lower bound for downto) */
            if (c) gen_store_var(c);
            gen_label(Lb);
            if (c) gen_load_var(c);
            gen_iload_slot(tmp);
            gen_isub();
            gen_iflt(Lx);                      /* counter < hi -> exit */
            if (for_ctx_top < FOR_STACK_MAX) {
                for_ctx[for_ctx_top].Lbegin = Lb;
                for_ctx[for_ctx_top].Lexit = Lx;
                for_ctx[for_ctx_top].counter = c;
                for_ctx[for_ctx_top].down = 1;
                for_ctx_top++;
            }
        }
      stmt
        {
            for_pop();
            if (for_ctx_top > 0) {
                ForCtx fc = for_ctx[--for_ctx_top];
                if (fc.counter) {
                    gen_load_var(fc.counter);
                    gen_load_int(1);
                    gen_arith(T_INT, fc.down ? '-' : '+');
                    gen_store_var(fc.counter);
                }
                gen_goto(fc.Lbegin);
                gen_label(fc.Lexit);
            }
            Trace("Reducing to for-downto");
        }
    ;

call_stmt
    : ID ';'
        {
            int aid = arg_new_empty();
            SymEntry *f = sym_lookup($1);
            (void)check_call($1, aid, 0);
            if (f && (f->kind == S_FUNC || f->kind == S_PROC)) {
                gen_call(f);
                if (f->kind == S_FUNC) gen_pop();
            }
            Trace("Reducing to proc-call");
        }
    | ID '(' args ')' ';'
        {
            SymEntry *f = sym_lookup($1);
            (void)check_call($1, $3, 0);
            if (f && (f->kind == S_FUNC || f->kind == S_PROC)) {
                gen_call(f);
                if (f->kind == S_FUNC) gen_pop();
            }
            Trace("Reducing to proc-call-with-args");
        }
    ;

/* ---- expressions ---- */

expr
    : expr OR expr
        { check_bool_op((Type)$1.type, "or"); check_bool_op((Type)$3.type, "or");
          gen_logical('o');
          $$ = ea_type(T_BOOL); Trace("  expr: or"); }
    | expr AND expr
        { check_bool_op((Type)$1.type, "and"); check_bool_op((Type)$3.type, "and");
          gen_logical('a');
          $$ = ea_type(T_BOOL); Trace("  expr: and"); }
    | NOT expr
        { check_bool_op((Type)$2.type, "not");
          gen_logical('n');
          $$ = ea_type(T_BOOL); Trace("  expr: not"); }
    | expr LT expr
        { check_cmp((Type)$1.type, (Type)$3.type, "<");  gen_relop(0, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: <"); }
    | expr LE expr
        { check_cmp((Type)$1.type, (Type)$3.type, "<="); gen_relop(1, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: <="); }
    | expr EQ expr
        { check_cmp((Type)$1.type, (Type)$3.type, "=");  gen_relop(2, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: ="); }
    | expr GE expr
        { check_cmp((Type)$1.type, (Type)$3.type, ">="); gen_relop(4, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: >="); }
    | expr GT expr
        { check_cmp((Type)$1.type, (Type)$3.type, ">");  gen_relop(5, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: >"); }
    | expr NE expr
        { check_cmp((Type)$1.type, (Type)$3.type, "<>"); gen_relop(3, (Type)$1.type); $$ = ea_type(T_BOOL); Trace("  expr: <>"); }
    | expr '+' expr
        { Type rt = check_arith((Type)$1.type, (Type)$3.type, "+"); gen_arith(rt, '+'); $$ = ea_type(rt); Trace("  expr: +"); }
    | expr '-' expr
        { Type rt = check_arith((Type)$1.type, (Type)$3.type, "-"); gen_arith(rt, '-'); $$ = ea_type(rt); Trace("  expr: -"); }
    | expr '*' expr
        { Type rt = check_arith((Type)$1.type, (Type)$3.type, "*"); gen_arith(rt, '*'); $$ = ea_type(rt); Trace("  expr: *"); }
    | expr '/' expr
        { Type rt = check_arith((Type)$1.type, (Type)$3.type, "/"); gen_arith(rt, '/'); $$ = ea_type(rt); Trace("  expr: /"); }
    | expr MOD expr
        { Type rt = check_mod((Type)$1.type, (Type)$3.type); gen_arith(rt, 'm'); $$ = ea_type(rt); Trace("  expr: mod"); }
    | '-' expr %prec UMINUS
        {
            if ((Type)$2.type != T_INT && (Type)$2.type != T_REAL && (Type)$2.type != T_UNKNOWN)
                sem_error("unary '-' requires numeric (got %s)", type_name((Type)$2.type));
            gen_unary_neg((Type)$2.type);
            $$ = $2;
            if ($$.is_const_int) $$.const_val = -$$.const_val;
            Trace("  expr: unary-");
        }
    | '(' expr ')'
        { $$ = $2; }
    | ID
        {
            SymEntry *e = sym_lookup($1);
            if (!e) { sem_error("use of undeclared '%s'", $1); $$ = ea_type(T_UNKNOWN); }
            else if (e->kind == S_PROC) {
                sem_error("procedure '%s' cannot be used in expression", $1);
                $$ = ea_type(T_UNKNOWN);
            }
            else if (e->kind == S_FUNC) {
                /* spec §2.3.1: function invocation may omit "()" when it
                 * takes no arguments — treat bare ID as a zero-arg call so
                 * arity is still verified. */
                int aid = arg_new_empty();
                Type rt = check_call($1, aid, 1);
                gen_call(e);
                $$ = ea_type(rt);
            }
            else if (e->kind == S_CONST) {
                gen_load_const_value(e);
                $$ = ea_type(e->type);
            }
            else { gen_load_var(e); $$ = ea_type(e->type); }
            Trace("  expr: id");
        }
    | ID '[' { SymEntry *a = sym_lookup($1); if (a) gen_load_array_addr(a); } expr ']'
        {
            SymEntry *e = sym_lookup($1);
            if (!e) { sem_error("array '%s' undeclared", $1); $$ = ea_type(T_UNKNOWN); }
            else if (e->type != T_ARRAY) { sem_error("'%s' is not array", $1); $$ = ea_type(T_UNKNOWN); }
            else {
                if ((Type)$4.type != T_INT)
                    sem_error("array index of '%s' must be integer (got %s)",
                              $1, type_name((Type)$4.type));
                else
                    check_array_index_bounds(e, $1, $4);
                gen_array_load(e->elem_type);
                $$ = ea_type(e->elem_type);
            }
            Trace("  expr: array-ref");
        }
    | ID '(' args ')'
        {
            SymEntry *f = sym_lookup($1);
            Type rt = check_call($1, $3, 1);
            if (f) gen_call(f);
            $$ = ea_type(rt);
            Trace("  expr: call");
        }
    | INT_CONST
        { gen_load_int($1); $$ = ea_const_int($1); Trace("  expr: int"); }
    | REAL_CONST
        { gen_load_real($1); $$ = ea_type(T_REAL); Trace("  expr: real"); }
    | STR_CONST
        { gen_load_str($1); $$ = ea_type(T_STR); Trace("  expr: str"); }
    | BOOL_CONST
        { gen_load_bool($1); $$ = ea_type(T_BOOL); Trace("  expr: bool"); }
    ;

args
    : /* empty */   { $$ = arg_new_empty(); }
    | expr_list     { $$ = $1; }
    ;

expr_list
    : expr                  { $$ = arg_single((Type)$1.type); }
    | expr_list ',' expr    { $$ = arg_append($1, (Type)$3.type); }
    ;

%%

#include "lex.yy.c"

int yyerror(const char *msg) {
    fprintf(stderr, "line %d: syntax error: %s\n", linenum, msg);
    return 0;
}

int main(int argc, char *argv[]) {
    int i;
    const char *input = NULL;
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--lex-print") == 0) Opt_LexPrint = 1;
        else if (strcmp(argv[i], "--code-print") == 0) Opt_CodePrint = 1;
        else if (strcmp(argv[i], "--yydebug") == 0) yydebug = 1;
        else if (strcmp(argv[i], "--trace") == 0) Opt_Trace = 1;
        else if (strcmp(argv[i], "--warning") == 0) Opt_Warning = 1;
        else if (strcmp(argv[i], "--dump") == 0) Opt_Dump = 1;
        else if (strcmp(argv[i], "--error-exit") == 0) Opt_ErrorExit = 1;
        else if (strcmp(argv[i], "--demo") == 0) {
            Opt_Demo = 1;
            Opt_Dump = 1;
            Opt_Trace = 1;
            yydebug = 1;
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "unknown option: %s\n", argv[i]);
            return 1;
        } else {
            input = argv[i];
        }
    }
    char outpath[1024] = {0};
    if (input) {
        yyin = fopen(input, "r");
        if (!yyin) {
            fprintf(stderr, "cannot open file: %s\n", input);
            return 1;
        }
        /* derive <basename>.jasm next to input */
        const char *slash = strrchr(input, '/');
        const char *base  = slash ? slash + 1 : input;
        size_t prefix_len = (size_t)(base - input);
        const char *dot   = strrchr(base, '.');
        size_t stem_len   = dot ? (size_t)(dot - base) : strlen(base);
        if (prefix_len + stem_len + 6 < sizeof(outpath)) {
            memcpy(outpath, input, prefix_len);
            memcpy(outpath + prefix_len, base, stem_len);
            memcpy(outpath + prefix_len + stem_len, ".jasm", 6);
        }
    }
    sym_init();
    sym_push_scope();       /* global scope */
    gen_open(outpath[0] ? outpath : NULL);
    int rc = yyparse();
    if (buf[0] != '\0')
        printf("%d: %s\n", linenum, buf);
    if (Opt_Dump) sym_dump_current_scope();
    sym_pop_scope();
    gen_close();
    if (Opt_ErrorExit && semantic_errors > 0) rc = 1;
    if (rc != 0) fprintf(stderr, "Parsing failed.\n");
    else         fprintf(stderr, "Parsing completed.\n");
    return rc;
}
