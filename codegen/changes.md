Project 3 (Code Generation) — file-by-file change summary
==========================================================

The compiler now lowers each Delphi- source program into the textual
Java-assembly format accepted by the bundled `javaa` assembler. The
existing P2 lexer/parser/symbol-table were retained; semantic actions
were extended with calls into a new code-emission module (`codegen.[ch]`)
and the symbol table grew the bookkeeping needed to drive code-gen.

------------------------------------------------------------------------
makefile
------------------------------------------------------------------------
- New target shape `tests/<name>.{del,jasm,class}` driven by a single
  `file=` variable, so one command compiles, assembles, and runs:
      make file=tests/16_example run
- Added `codegen.o` build rule (compiles codegen.c).
- Added explicit `clean` target that also removes per-test
  `tests/*.jasm` / `tests/*.class` artifacts.
- Linker rule pulls in `symbols.o` + `codegen.o` alongside the
  bison output.

------------------------------------------------------------------------
delphi.lex
------------------------------------------------------------------------
- Identifier rule extended to allow underscores
  (`letter [a-zA-Z_]`) so test programs whose `program <name>;` matches
  their filename (e.g. `S01_globals`) are accepted.
- Introduced new tokens needed by code-gen-relevant statements:
  WRITE, WRITELN, READ, RETURN, REPEAT, UNTIL, FOR, TO, DOWNTO,
  ARRAY, OF, BOOL_CONST, REAL_CONST, STR_CONST.
- All keywords matched case-insensitively.
- `BEGIN` is returned as `KW_BEGIN` to avoid colliding with bison's
  built-in `BEGIN` macro for start-conditions.
- `(* ... *)`, `{ ... }` and `// ...` comments are recognized; the
  block-comment states report `unterminated comment` on EOF.
- String constants honour the doubled-quote escape (`""` -> `"`).
- Boolean literals `true` / `false` (any case) emit BOOL_CONST with
  ival = 1 / 0 so the parser can store them in `last_const` and the
  emitter can `iconst_0` / `iconst_1` them.

------------------------------------------------------------------------
parser.yacc
------------------------------------------------------------------------
- Each semantic action now (a) does its existing P2 type-check and
  (b) emits assembly via `gen_*` helpers.
- `program` opens/closes the class:
      gen_class_begin / gen_main_begin / gen_main_end / gen_class_end.
- `var_decl` emits `gen_field` (global) or `gen_local_store_init`
  (local with initializer) depending on `in_subprog`.
- `const_decl` does NOT emit a field (per spec §2.2.2); the value is
  stashed in `last_const` and copied into the SymEntry's `cval`. The
  literal is materialized at every use site via `gen_load_const_value`.
- `func_decl` / `proc_decl` emit `gen_method_begin` (with the right
  return type and formal types) and `gen_method_end` at body close.
  Locals are numbered starting at param_count via `sym_alloc_local`.
- Statements:
    * `id := expr;`             -> gen_store_var
    * `id[idx] := expr;`        -> gen_array_store, with compile-time
                                   bounds check when idx is constant
    * `write` / `writeln`       -> gen_print_begin / gen_print_end
    * `return [expr];`          -> gen_return_void / gen_return_value
- Control flow uses an explicit label stack (`if_lbl_stack`,
  `for_ctx`) instead of mid-rule attributes, so that the
  if-without-else, if-with-else, while, repeat-until, for-to and
  for-downto shapes all share consistent label generation.
- For-loop counter immutability (spec §2.5) is enforced via a stack
  of active counters checked in every `id := expr;` and `read id;`.
- Function calls in expression position (`ID '(' args ')'`) use the
  same `check_call` helper as statement-position calls; arity and
  per-arg type matching are verified before `gen_call`.

------------------------------------------------------------------------
symbols.h / symbols.c
------------------------------------------------------------------------
- SymEntry gained fields used by code-gen:
    * `local_num`     JVM slot number (-1 for globals/consts/funcs)
    * `scope_depth`   set on insertion so we can tell global from local
    * `cval`          ConstVal {ival, rval, sval, has_value} — used by
                      both S_CONST entries and S_VAR entries that have
                      an initializer
    * `param_types[]` and `param_count` for callable entries
    * `elem_type`, `array_lo`, `array_hi` for arrays
- Added a per-method local-slot allocator:
    * `sym_reset_locals()` called at every method entry
    * `sym_alloc_local()` returns the next slot and increments
- `sym_set_params` stores a copy of the formal-types vector on the
  SymEntry so call sites can verify arity + types without walking
  scopes.
- `sym_dump_current_scope` prints the new fields when `--dump` is set,
  for debugging.
- `type_name`, `kind_name` exposed for diagnostics.

------------------------------------------------------------------------
codegen.h / codegen.c   (new files; named to avoid clashing with the
                         `gen.c` already shipped under javaa/)
------------------------------------------------------------------------
Single FILE* sink opened with `gen_open(path)` (NULL = stdout). All
emitters print to that sink; everything else is small helpers.

- Class / method scaffolding: gen_class_begin/_end, gen_main_begin/_end,
  gen_method_begin/_end. `gen_method_end` always emits a defensive
  fallthrough return (with type-correct default value for functions)
  so `javaa` accepts methods even if the source body falls through.

- Fields and locals:
    gen_field             "field static <T> name [= v]"
    gen_local_store_init  literal load + Xstore <slot>

- Expression operands:
    gen_load_int / _real / _str / _bool literal-load helpers using
    iconst_<n>, sipush, ldc as appropriate.
    gen_load_var / gen_store_var pick iload/istore vs getstatic/
    putstatic based on `local_num`.
    gen_load_const_value materializes a constant from its SymEntry.

- Operators:
    gen_arith(t, op)   iadd/isub/imul/idiv/irem (prefix derived from t)
    gen_unary_neg(t)   ineg or fneg
    gen_logical(op)    iand / ior / "iconst_1; ixor" for not
    gen_relop(op, t)   isub (or fcmpl) followed by an ifcond, then
                       0/1 materialization through two labels — matches
                       the spec §2.3.1 template exactly.

- Arrays: gen_global_array_field, gen_local_array_alloc (with
  `newarray`), gen_load_array_addr, gen_array_load/_store.

- Control flow: gen_new_label + gen_label, gen_goto and the full
  family of gen_if* (eq/ne/lt/gt/le/ge). gen_isub, gen_iload_slot,
  gen_istore_slot are exposed for compiler-generated temporaries
  used in the for-loop lowering.

- I/O: gen_print_begin emits the `getstatic ... System.out`; the
  matching gen_print_end emits the `invokevirtual void
  java.io.PrintStream.print[ln](T)` with T derived from the operand
  type. gen_read is a placeholder (spec §2 is silent on read).

- Calls and return: gen_call emits `invokestatic <ret> <class>.<name>
  (<param-types>)` from the SymEntry; gen_return_value picks
  ireturn/freturn/areturn from the type prefix. gen_pop is used after
  function-call statements where the return value is discarded.

- gen_set_class_name / gen_class_name keep the active class name in a
  static buffer so getstatic/putstatic emit the correct qualifier.
