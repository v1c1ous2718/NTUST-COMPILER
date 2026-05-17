#include "codegen.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static FILE *out = NULL;
static int enabled = 0;
static int next_label = 0;
static char class_name[256] = "Program";

/* indent state — every line emitted is prefixed with `indent_level` copies
 * of `indent_unit`, except labels which sit one notch shallower than the
 * surrounding instructions for visual separation. Manage depth through
 * `indent_push` / `indent_pop` so each begin/end emitter just records its
 * scope change rather than naming an absolute level. */
static int indent_level = 0;
static int at_line_start = 1;
static const char *indent_unit = "    ";
static void indent_push(void) { indent_level++; }
static void indent_pop(void)  { if (indent_level > 0) indent_level--; }

void gen_set_class_name(const char *name) {
    if (!name) return;
    strncpy(class_name, name, sizeof(class_name) - 1);
    class_name[sizeof(class_name) - 1] = '\0';
}
const char *gen_class_name(void) { return class_name; }

void gen_open(const char *path) {
    if (path) {
        out = fopen(path, "w");
        if (!out) {
            fprintf(stderr, "gen: cannot open %s for writing\n", path);
            out = stdout;
        }
    } else {
        out = stdout;
    }
    enabled = 1;
    next_label = 0;
    indent_level = 0;
    at_line_start = 1;
}

void gen_close(void) {
    if (out && out != stdout) fclose(out);
    out = NULL;
    enabled = 0;
}

int gen_enabled(void) { return enabled && out; }

/* Emit formatted text, prefixing each new line with the current indent.
 * The state machine reads the formatted buffer and tracks whether the
 * next non-newline character is the first of a line; if so it writes
 * `indent_level` copies of `indent_unit` before the character. */
static void emit(const char *fmt, ...) {
    if (!gen_enabled()) return;
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    for (const char *p = buf; *p; p++) {
        if (at_line_start && *p != '\n') {
            for (int i = 0; i < indent_level; i++) fputs(indent_unit, out);
            at_line_start = 0;
        }
        fputc(*p, out);
        if (*p == '\n') at_line_start = 1;
    }
}

/* ---- type helpers ---------------------------------------------------- */

static const char *jvm_type(Type t) {
    switch (t) {
        case T_INT:
            return "int";
        case T_REAL:
            return "float";
        case T_BOOL:
            return "boolean";
        case T_STR:
            return "java.lang.String";
        case T_VOID:
            return "void";
        default:
            return "int";
    }
}

static char prefix_for(Type t) {
    /* JVM opcode prefix: i = int/bool, f = real, a = reference (string/array)
     */
    switch (t) {
        case T_INT:
        case T_BOOL:
            return 'i';
        case T_REAL:
            return 'f';
        case T_STR:
        case T_ARRAY:
            return 'a';
        default:
            return 'i';
    }
}

/* ---- class / method scaffolding -------------------------------------- */

void gen_class_begin(const char *name) {
    gen_set_class_name(name);
    emit("class %s\n{\n", name);
    indent_push();          /* enter class body */
}

void gen_class_end(void) {
    indent_pop();           /* leave class body */
    emit("}\n");
}

void gen_method_begin(const char *name, Type ret, const Type *ptypes, int n) {
    emit("method public static %s %s(", jvm_type(ret), name);
    for (int i = 0; i < n; i++) {
        if (i) emit(", ");
        emit("%s", jvm_type(ptypes[i]));
    }
    emit(")\n");
    emit("max_stack 15\n");
    emit("max_locals 15\n");
    emit("{\n");
    indent_push();          /* enter method body */
    next_label = 0;
}

void gen_method_end(Type ret) {
    /* Always emit a terminating return so javaa is happy even when the
     * source falls through. For functions, emit a default zero. */
    if (ret == T_VOID) {
        emit("return\n");
    } else {
        switch (ret) {
            case T_REAL:
                emit("ldc 0.0f\nfreturn\n");
                break;
            case T_STR:
                emit("ldc \"\"\nareturn\n");
                break;
            default:
                emit("iconst_0\nireturn\n");
                break;
        }
    }
    indent_pop();           /* leave method body */
    emit("}\n");
}

void gen_main_begin(void) {
    emit("method public static void main(java.lang.String[])\n");
    emit("max_stack 15\n");
    emit("max_locals 15\n");
    emit("{\n");
    indent_push();          /* enter main body */
    next_label = 0;
}

void gen_main_end(void) {
    emit("return\n");
    indent_pop();           /* leave main body */
    emit("}\n");
}

/* ---- fields & local init -------------------------------------------- */

static const char *field_type(Type t) {
    switch (t) {
        case T_INT:
            return "int";
        case T_REAL:
            return "float";
        case T_BOOL:
            return "boolean";
        case T_STR:
            return "java.lang.String";
        default:
            return "int";
    }
}

void gen_field(const char *name, Type t, int has_init, long ival, double rval,
               const char *sval) {
    emit("field static %s %s", field_type(t), name);
    if (has_init) {
        switch (t) {
            case T_INT:
                emit(" = %ld", ival);
                break;
            case T_BOOL:
                emit(" = %ld", ival ? 1L : 0L);
                break;
            case T_REAL:
                emit(" = %ff", rval);
                break;
            case T_STR:
                /* javaa does not support string field initializers via ConstantValue */
                break;
            default:
                break;
        }
    }
    emit("\n");
}

static void emit_load_lit(Type t, long ival, double rval, const char *sval) {
    switch (t) {
        case T_INT:
            if (ival >= -1 && ival <= 5)
                emit("iconst_%ld\n", ival);
            else if (ival >= -32768 && ival <= 32767)
                emit("sipush %ld\n", ival);
            else
                emit("ldc %ld\n", ival);
            break;
        case T_BOOL:
            emit("iconst_%d\n", ival ? 1 : 0);
            break;
        case T_REAL:
            /* javaa parses unsuffixed reals as DOUBLECONSTANT; we need a
             * float literal because T_REAL maps to JVM `float`. */
            emit("ldc %gf\n", rval);
            break;
        case T_STR:
            emit("ldc \"%s\"\n", sval ? sval : "");
            break;
        default:
            emit("iconst_0\n");
            break;
    }
}

void gen_local_store_init(int slot, Type t, long ival, double rval,
                          const char *sval) {
    emit_load_lit(t, ival, rval, sval);
    char p = prefix_for(t);
    emit("%cstore %d\n", p, slot);
}

/* ---- expression operands -------------------------------------------- */

void gen_load_int(long v) { emit_load_lit(T_INT, v, 0, NULL); }
void gen_load_real(double v) { emit_load_lit(T_REAL, 0, v, NULL); }
void gen_load_str(const char *s) { emit_load_lit(T_STR, 0, 0, s); }
void gen_load_bool(int b) { emit_load_lit(T_BOOL, b ? 1 : 0, 0, NULL); }

void gen_load_var(const SymEntry *e) {
    if (!e) return;
    if (e->kind == S_CONST) {
        /* should be loaded via gen_load_const_value, but be defensive */
        return;
    }
    if (e->local_num >= 0) {
        char p = prefix_for(e->type == T_ARRAY ? T_ARRAY : e->type);
        emit("%cload %d\n", p, e->local_num);
    } else {
        const char *jt = (e->type == T_ARRAY)
                             ? (e->elem_type == T_REAL  ? "float[]"
                                : e->elem_type == T_STR ? "java.lang.String[]"
                                                        : "int[]")
                             : field_type(e->type);
        emit("getstatic %s %s.%s\n", jt, class_name, e->name);
    }
}

void gen_store_var(const SymEntry *e) {
    if (!e) return;
    if (e->local_num >= 0) {
        char p = prefix_for(e->type);
        emit("%cstore %d\n", p, e->local_num);
    } else {
        emit("putstatic %s %s.%s\n", field_type(e->type), class_name, e->name);
    }
}

void gen_load_const_value(const SymEntry *e) {
    if (!e || !e->cval.has_value) {
        emit("iconst_0\n");
        return;
    }
    emit_load_lit(e->type, e->cval.ival, e->cval.rval, e->cval.sval);
}

/* ---- operators ------------------------------------------------------- */

void gen_arith(Type t, int op) {
    char p = prefix_for(t);
    switch (op) {
        case '+':
            emit("%cadd\n", p);
            break;
        case '-':
            emit("%csub\n", p);
            break;
        case '*':
            emit("%cmul\n", p);
            break;
        case '/':
            emit("%cdiv\n", p);
            break;
        case 'm':
            emit("%crem\n", p);
            break;
        default:
            break;
    }
}

void gen_unary_neg(Type t) {
    char p = prefix_for(t);
    emit("%cneg\n", p);
}

void gen_logical(int op) {
    switch (op) {
        case 'a':
            emit("iand\n");
            break;
        case 'o':
            emit("ior\n");
            break;
        case 'n':
            /* not boolean: xor with 1 */
            emit("iconst_1\nixor\n");
            break;
        default:
            break;
    }
}

/* relop: 0=< 1=<= 2== 3<> 4>= 5> */
void gen_relop(int relop, Type t) {
    static const char *cond[] = {"iflt", "ifle", "ifeq",
                                 "ifne", "ifge", "ifgt"};
    if (t == T_REAL) {
        emit("fcmpl\n");
    } else {
        emit("isub\n");
    }
    int Ltrue = gen_new_label();
    int Lend = gen_new_label();
    emit("%s L%d\n", cond[relop], Ltrue);
    emit("iconst_0\n");
    emit("goto L%d\n", Lend);
    gen_label(Ltrue);
    emit("iconst_1\n");
    gen_label(Lend);
}

/* ---- arrays ---------------------------------------------------------- */

void gen_load_array_addr(const SymEntry *arr) {
    if (!arr) return;
    if (arr->local_num >= 0) {
        emit("aload %d\n", arr->local_num);
    } else {
        const char *et = (arr->elem_type == T_REAL  ? "float[]"
                          : arr->elem_type == T_STR ? "java.lang.String[]"
                                                    : "int[]");
        emit("getstatic %s %s.%s\n", et, class_name, arr->name);
    }
}

void gen_array_load(Type elem) {
    char p = prefix_for(elem);
    emit("%caload\n", p);
}
void gen_array_store(Type elem) {
    char p = prefix_for(elem);
    emit("%castore\n", p);
}

void gen_global_array_field(const char *name, const char *jvm_elem) {
    emit("field static %s[] %s\n", jvm_elem, name);
}

void gen_local_array_alloc(int slot, int size, const char *jvm_elem) {
    emit_load_lit(T_INT, size, 0, NULL);
    emit("newarray %s\n", jvm_elem);
    emit("astore %d\n", slot);
}

/* ---- control flow ---------------------------------------------------- */

int gen_new_label(void) { return next_label++; }
void gen_label(int id) {
    /* labels sit one notch shallower than instructions, e.g.
     *     iload 0
     *   L0:
     *     iconst_1                                            */
    indent_pop();
    emit("L%d:\n", id);
    indent_push();
}
void gen_goto(int id) { emit("goto L%d\n", id); }
void gen_ifeq(int id) { emit("ifeq L%d\n", id); }
void gen_ifne(int id) { emit("ifne L%d\n", id); }
void gen_iflt(int id) { emit("iflt L%d\n", id); }
void gen_ifgt(int id) { emit("ifgt L%d\n", id); }
void gen_ifle(int id) { emit("ifle L%d\n", id); }
void gen_ifge(int id) { emit("ifge L%d\n", id); }
void gen_isub(void) { emit("isub\n"); }

void gen_iload_slot(int slot) { emit("iload %d\n", slot); }
void gen_istore_slot(int slot) { emit("istore %d\n", slot); }

/* ---- I/O ------------------------------------------------------------- */

void gen_print_begin(void) {
    emit("getstatic java.io.PrintStream java.lang.System.out\n");
}
void gen_print_end(Type t, int newline) {
    const char *jt;
    switch (t) {
        case T_INT:
            jt = "int";
            break;
        case T_REAL:
            jt = "float";
            break;
        case T_BOOL:
            jt = "boolean";
            break;
        case T_STR:
            jt = "java.lang.String";
            break;
        default:
            jt = "int";
            break;
    }
    emit("invokevirtual void java.io.PrintStream.%s(%s)\n",
         newline ? "println" : "print", jt);
}

void gen_read(const SymEntry *e) {
    /* Simplified read: use BufferedReader/Scanner is heavy in raw bytecode;
     * spec is silent on read so we only emit a stub note. */
    if (!e) return;
    emit("/* read %s -- runtime read not implemented */\n", e->name);
}

/* ---- calls / return -------------------------------------------------- */

void gen_call(const SymEntry *f) {
    if (!f) return;
    emit("invokestatic %s %s.%s(",
         jvm_type(f->kind == S_PROC ? T_VOID : f->type), class_name, f->name);
    for (int i = 0; i < f->param_count; i++) {
        if (i) emit(", ");
        emit("%s", jvm_type(f->param_types[i]));
    }
    emit(")\n");
}

void gen_return_void(void) { emit("return\n"); }
void gen_return_value(Type t) {
    char p = prefix_for(t);
    emit("%creturn\n", p);
}
void gen_pop(void) { emit("pop\n"); }
