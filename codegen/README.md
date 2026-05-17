# Delphi- → Java assembly (Project 3)

Compiles a Delphi-like source program into the textual Java-assembly accepted
by the bundled `javaa` assembler, which in turn produces a `.class` file
runnable on a stock JVM.

## Prerequisites

- `flex`, `bison`, `gcc`, `make`
- `java` (any modern JDK)

The `javaa` assembler is included under [javaa/](javaa/) and is built
automatically when needed.

## Build

```bash
make
```

Produces `./compiler` at the project root. Intermediate artifacts:
`lex.yy.c`, `y.tab.c`, `y.tab.h`, `symbols.o`, `JavaByteCodeGen.o`.

`make clean` removes everything, including any generated `tests/*.jasm`
and `tests/*.class`.

## Run a single program

The makefile drives the full pipeline (`.del → .jasm → .class → java`)
through the `file=` variable:

```bash
make file=tests/example run
```

What that does:
1. `./compiler tests/S16_example.del` writes `tests/S16_example.jasm`
2. `javaa` assembles the `.jasm` into `tests/S16_example.class`
3. `java -cp tests/. S16_example` runs the program

The `program <Name>;` declaration in each test matches the file basename
exactly so that `java <basename>` finds the compiled class.

You can also invoke the compiler directly to inspect the generated
assembly without running it:

```bash
./compiler tests/S16_example.del
cat tests/S16_example.jasm
```

### Compiler flags

| flag             | effect                                                            |
|------------------|-------------------------------------------------------------------|
| `--lex-print`    | print one token per line as the lexer fires                        |
| `--code-print`   | print each source line as the lexer scans it                       |
| `--trace`        | print every grammar reduction                                      |
| `--yydebug`      | bison's full LALR shift/reduce trace                               |
| `--dump`         | dump the global symbol table at end of parse                       |
| `--warning`      | enable semantic warnings (default on)                              |
| `--error-exit`   | exit non-zero if any semantic error was reported                   |
| `--demo`         | shorthand for `--dump --trace --yydebug`                           |

## Sanity sweep

Run every test under `tests/` and check that success cases parse cleanly
and `F*` cases emit a `line N: ...` diagnostic:

```bash
tests/@run.sh
```

Filter by prefix:

```bash
tests/@run.sh S09 F05   # only S09_if.del and F05_for_counter_modify.del
```

The script exits non-zero if anything regresses.

## Test layout

| pattern               | meaning                                                |
|-----------------------|--------------------------------------------------------|
| `tests/SXX_NAME.del`  | success case — must parse cleanly                      |
| `tests/FXX_NAME.del`  | fail case — must emit at least one `line N: ...` error |

Every test starts with a comment naming the spec section it exercises.

## Project layout

```
compiler/codegen/
├── makefile          build rules (compiler + per-file run target)
├── delphi.lex        flex source — tokens
├── parser.yacc       bison source — grammar + semantic checks + codegen calls
├── symbols.h/.c      symbol table, scopes, JVM local-slot allocator
├── codegen.h/.c      Java-assembly emitter (new for P3)
├── tests/            .del programs + run.sh sanity sweep
├── javaa/            bundled Java-assembly assembler
└── pdf/              spec PDFs
```
