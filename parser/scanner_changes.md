# Scanner Changes (Phase 1 -> Phase 2)

`parser/delphi.lex` is derived from `scanner/delphi.lex`. The list below
enumerates every change that was required to make the scanner serve as
`yylex()` for the yacc-generated parser.

## 1. `#include "y.tab.h"`

Bison generates `y.tab.h` with the token numeric constants (for example
`INTEGER`, `ASSIGN`, `KW_BEGIN`, `ID`, ...) and the `yylval` union typedef.
The scanner needs both, so the prelude now starts with:

```c
#include "y.tab.h"
```

## 2. `token()` / `tokenInteger()` / `tokenString()` now return

In Phase 1 the scanner merely printed the token. Phase 2 requires the
token numeric code to be returned to `yyparse()`, and the semantic value
(if any) stored in `yylval`.

```c
#define token(t)            { LIST; printf("<%s>\n", #t); return (t); }
#define tokenChar(c)        { LIST; printf("<%s>\n", #c); return (c); }
```

`tokenInteger` / `tokenString` were removed because the integer, real,
string, boolean and identifier rules each need to set a different
`yylval` member and their `printf` format differs; inlining is clearer
than layered macros.

## 3. `BEGIN` keyword renamed to `KW_BEGIN`

`flex` reserves the identifier `BEGIN` for its start-condition macro
`BEGIN(state)`. Declaring `BEGIN` as a yacc token would produce
`#define BEGIN <n>` in `y.tab.h` and silently break every
`BEGIN(COMMENT)` inside the scanner. The Phase 2 grammar therefore uses
`KW_BEGIN` for the Delphi keyword, and the scanner returns it directly:

```c
[bB][eE][gG][iI][nN]  { LIST; printf("<BEGIN>\n"); return KW_BEGIN; }
```

## 4. `after_operand` heuristic removed

Phase 1 used an `after_operand` flag so that `-5` could be lexed as a
negative numeric literal versus a binary minus. A proper parser does
this correctly by its own precedence rules. The scanner now always
emits `-` as `'-'`, and the grammar has `%right UMINUS` plus
`'-' expr %prec UMINUS` for unary negation. The two "negative integer /
real" regexes were deleted.

## 5. `yylval` population

The rules that carry semantic value now fill `yylval` prior to `return`:

| Rule                              | `yylval`            | returned token |
|-----------------------------------|---------------------|----------------|
| `{digit}+`                        | `yylval.ival`       | `INT_CONST`    |
| `{digit}+"."{digit}+(...)`        | `yylval.dval`       | `REAL_CONST`   |
| `\"([^\"\n]\|\"\")*\"`            | `yylval.sval`       | `STR_CONST`    |
| `[tT][rR][uU][eE]` / `false`      | `yylval.ival` (0/1) | `BOOL_CONST`   |
| `{letter}({letter}\|{digit})*`    | `yylval.sval`       | `ID`           |

`strdup` is used for string values because `yytext` is overwritten by
the next call to `yylex()`.

## 6. `READ` keyword added

The Phase 2 grammar requires `read identifier ;`. The Phase 1 scanner
had no rule for `read`; it was added:

```c
[rR][eE][aA][dD]   { token(READ); }
```

## 7. Embedded symbol table removed

The hash-chained symbol table (`Entry`, `table`, `hash`, `lookup`,
`insert`, `dump`, `create`) was removed from `delphi.lex`. The scanner
only needed it to dump identifiers at the end of Phase 1. The real
symbol table lives in [`symbols.c`](symbols.c) / [`symbols.h`](symbols.h)
and is driven from the yacc actions in [`parser.y`](parser.y).

## 8. `main()` removed, `yywrap()` retained

`main()` is now provided by `parser.y` so it can call `sym_init` /
`yyparse`. `yywrap()` stays in the scanner (returns 1) so we do not
need `-lfl`. The Makefile still links `-lfl` out of habit; it is
harmless.

## 9. Delimiter / operator tokens

Single-character operators use `tokenChar(ch)` so the stringizer prints
the literal character inside the trace output and the returned value is
the character code, which the yacc grammar uses directly (for example
`'+'`, `';'`, `'('`). Multi-character relational operators become yacc
tokens (`LE`, `GE`, `NE`, `LT`, `GT`, `EQ`, `ASSIGN`) because single
character `<`, `>`, `=` on their own are still relational operators in
the grammar.
