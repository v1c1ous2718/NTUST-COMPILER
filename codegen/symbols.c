#include "symbols.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static Scope *top = NULL;
static int    depth = -1;     /* incremented on push, decremented on pop */
static int    next_local = 0; /* JVM slot counter, reset by sym_reset_locals */

void sym_init(void) { top = NULL; depth = -1; next_local = 0; }

void sym_push_scope(void) {
    Scope *s = (Scope *)calloc(1, sizeof(Scope));
    s->head = NULL;
    s->parent = top;
    top = s;
    depth++;
}

void sym_reset_locals(void) { next_local = 0; }
int  sym_alloc_local(void) { return next_local++; }
int  sym_current_depth(void) { return depth; }

static void free_entry(SymEntry *e) {
    free(e->name);
    if (e->param_types) {
        free(e->param_types);
    }
    if (e->cval.sval) free(e->cval.sval);
    free(e);
}

void sym_pop_scope(void) {
    if (!top) return;
    SymEntry *e = top->head;
    while (e) {
        SymEntry *n = e->next;
        free_entry(e);
        e = n;
    }
    Scope *s = top;
    top = top->parent;
    free(s);
    depth--;
}

SymEntry *sym_lookup_local(const char *name) {
    if (!top) return NULL;
    for (SymEntry *e = top->head; e; e = e->next)
        if (strcmp(e->name, name) == 0) return e;
    return NULL;
}

SymEntry *sym_lookup(const char *name) {
    for (Scope *s = top; s; s = s->parent)
        for (SymEntry *e = s->head; e; e = e->next)
            if (strcmp(e->name, name) == 0) return e;
    return NULL;
}

int sym_insert(SymEntry *e) {
    if (!top) return -1;
    if (sym_lookup_local(e->name)) {
        free_entry(e);
        return -1;
    }
    e->next = top->head;
    top->head = e;
    return 0;
}

SymEntry *sym_make(const char *name, SymKind kind, Type type) {
    SymEntry *e = (SymEntry *)calloc(1, sizeof(SymEntry));
    e->name = strdup(name);
    e->kind = kind;
    e->type = type;
    e->elem_type = T_UNKNOWN;
    e->array_lo = 0;
    e->array_hi = 0;
    e->param_types = NULL;
    e->param_count = 0;
    e->local_num = -1;
    e->scope_depth = depth < 0 ? 0 : depth;
    e->cval.ival = 0;
    e->cval.rval = 0;
    e->cval.sval = NULL;
    e->cval.has_value = 0;
    e->next = NULL;
    return e;
}

void sym_set_params(SymEntry *e, const Type *types, int count) {
    int i;
    if (!e) return;
    if (e->param_types) {
        free(e->param_types);
        e->param_types = NULL;
    }
    e->param_count = 0;
    if (count <= 0 || !types) return;
    e->param_types = (Type *)malloc(sizeof(Type) * (size_t)count);
    if (!e->param_types) return;
    for (i = 0; i < count; i++) e->param_types[i] = types[i];
    e->param_count = count;
}

void sym_dump_current_scope(void) {
    SymEntry *e;
    if (!top) {
        printf("[dump] empty scope\n");
        return;
    }
    printf("[dump] current scope symbols:\n");
    for (e = top->head; e; e = e->next) {
        printf("  name=%s kind=%s type=%s", e->name, kind_name(e->kind),
               type_name(e->type));
        if (e->type == T_ARRAY) {
            printf("[%d,%d] of %s", e->array_lo, e->array_hi,
                   type_name(e->elem_type));
        }
        if ((e->kind == S_FUNC || e->kind == S_PROC) && e->param_count >= 0) {
            int i;
            printf(" params(");
            for (i = 0; i < e->param_count; i++) {
                if (i) printf(",");
                printf("%s", type_name(e->param_types[i]));
            }
            printf(")");
        }
        printf("\n");
    }
}

const char *type_name(Type t) {
    switch (t) {
        case T_INT:
            return "integer";
        case T_REAL:
            return "real";
        case T_BOOL:
            return "boolean";
        case T_STR:
            return "string";
        case T_VOID:
            return "void";
        case T_ARRAY:
            return "array";
        default:
            return "unknown";
    }
}

const char *kind_name(SymKind k) {
    switch (k) {
        case S_CONST:
            return "const";
        case S_VAR:
            return "var";
        case S_PARAM:
            return "param";
        case S_FUNC:
            return "function";
        case S_PROC:
            return "procedure";
        case S_PROG:
            return "program";
        default:
            return "?";
    }
}
