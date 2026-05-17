#ifndef GEN_H
#define GEN_H

#include "symbols.h"

/* Code emission for Project 3: translates Delphi- to Java assembly that the
 * bundled javaa assembler accepts. All emitters print to a single FILE*
 * opened with gen_open(). */

void gen_open(const char *out_path);   /* NULL => stdout */
void gen_close(void);
int  gen_enabled(void);

/* class / method scaffolding ------------------------------------------- */
void gen_class_begin(const char *name);
void gen_class_end(void);
void gen_main_begin(void);
void gen_main_end(void);
void gen_method_begin(const char *name, Type ret,
                      const Type *ptypes, int n_params);
void gen_method_end(Type ret);

/* fields & local-init -------------------------------------------------- */
/* has_init: 0 no initializer; otherwise the value is in (ival/rval/sval)
 * picked by `t`. */
void gen_field(const char *name, Type t,
               int has_init, long ival, double rval, const char *sval);

/* Emits load-of-literal + Xstore <slot>. */
void gen_local_store_init(int slot, Type t,
                          long ival, double rval, const char *sval);

/* expression emitters -------------------------------------------------- */
void gen_load_int(long v);
void gen_load_real(double v);
void gen_load_str(const char *s);
void gen_load_bool(int b);
void gen_load_var(const SymEntry *e);     /* iload/fload/aload or getstatic */
void gen_store_var(const SymEntry *e);    /* istore/fstore/astore or putstatic */
void gen_load_const_value(const SymEntry *e); /* S_CONST: emit literal */

void gen_arith(Type t, int op);   /* op: '+' '-' '*' '/' or 'm' (mod) */
void gen_unary_neg(Type t);
void gen_logical(int op);         /* 'a' and, 'o' or, 'n' not */

/* relop: 0=<  1=<= 2== 3<> 4>= 5> ; opnd_t is the operand type */
void gen_relop(int relop, Type opnd_t);

/* arrays: addr is "aload <slot>" or "getstatic ..." then index then value */
void gen_load_array_addr(const SymEntry *arr); /* push the array ref */
void gen_array_load(Type elem);
void gen_array_store(Type elem);
void gen_global_array_field(const char *name, const char *jvm_elem);
void gen_local_array_alloc(int slot, int size, const char *jvm_elem);

/* control flow --------------------------------------------------------- */
int  gen_new_label(void);
void gen_label(int id);
void gen_goto(int id);
void gen_ifeq(int id);            /* pop bool, jump if zero */
void gen_ifne(int id);            /* pop bool, jump if non-zero */
void gen_iflt(int id);
void gen_ifgt(int id);
void gen_ifle(int id);
void gen_ifge(int id);
void gen_isub(void);

/* raw slot access for compiler-generated temporaries (e.g. for-loop hi). */
void gen_iload_slot(int slot);
void gen_istore_slot(int slot);

/* I/O ------------------------------------------------------------------ */
void gen_print_begin(void);                /* getstatic System.out */
void gen_print_end(Type t, int newline);
void gen_read(const SymEntry *e);

/* calls / return ------------------------------------------------------- */
void gen_call(const SymEntry *func);
void gen_return_void(void);
void gen_return_value(Type t);
void gen_pop(void);

/* the class name is needed when emitting putstatic/getstatic */
void gen_set_class_name(const char *name);
const char *gen_class_name(void);

#endif
