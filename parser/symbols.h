#ifndef SYMBOLS_H
#define SYMBOLS_H

typedef enum { T_INT, T_REAL, T_BOOL, T_STR, T_VOID, T_ARRAY, T_UNKNOWN } Type;

typedef enum { S_CONST, S_VAR, S_PARAM, S_FUNC, S_PROC, S_PROG } SymKind;

typedef struct SymEntry {
    char *name;
    SymKind kind;
    Type type;
    Type elem_type; /* array element type when type == T_ARRAY */
    int array_lo;
    int array_hi;
    Type *param_types;
    int param_count;
    struct SymEntry *next;
} SymEntry;

typedef struct Scope {
    SymEntry *head;
    struct Scope *parent;
} Scope;

void sym_init(void);
void sym_push_scope(void);
void sym_pop_scope(void);
int sym_insert(SymEntry *e); /* 0 ok; -1 duplicate in current scope */
SymEntry *sym_lookup(const char *name); /* walk outward */
SymEntry *sym_lookup_local(const char *name);

SymEntry *sym_make(const char *name, SymKind kind, Type type);
void sym_set_params(SymEntry *e, const Type *types, int count);
void sym_dump_current_scope(void);

const char *type_name(Type t);
const char *kind_name(SymKind k);

#endif