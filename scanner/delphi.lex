%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE_LENG 256
#define TABLE_SIZE    211
#define MAX_ENTRIES   1000

#define LIST strcat(buf, yytext)
#define token(t)            { LIST; printf("<%s>\n", #t); after_operand = 0; }
#define tokenInteger(t, i)  { LIST; printf("<%s:%d>\n", #t, i); after_operand = 1; }
#define tokenString(t, s)   { LIST; printf("<%s:%s>\n", #t, s); after_operand = 1; }

int  linenum = 1;
char buf[MAX_LINE_LENG];
char strbuf[MAX_LINE_LENG];
int  after_operand = 0;

/* ── Symbol Table (chained hash, insertion-order dump) ── */

typedef struct Entry {
    char *name;
    struct Entry *next;
} Entry;

static Entry *table[TABLE_SIZE];
static char  *entries[MAX_ENTRIES];
static int    num_entries = 0;

static unsigned int hash(const char *s) {
    unsigned int h = 0;
    while (*s)
        h = h * 65599 + (unsigned char)*s++;
    return h % TABLE_SIZE;
}

void create() {
    for (int i = 0; i < TABLE_SIZE; i++)
        table[i] = NULL;
    num_entries = 0;
}

int lookup(const char *s) {
    unsigned int h = hash(s);
    Entry *e = table[h];
    while (e) {
        if (strcmp(e->name, s) == 0)
            return 1;
        e = e->next;
    }
    return -1;
}

int insert(const char *s) {
    unsigned int h = hash(s);
    Entry *e = (Entry *)malloc(sizeof(Entry));
    e->name = strdup(s);
    e->next = table[h];
    table[h] = e;
    entries[num_entries] = e->name;
    return num_entries++;
}

void dump() {
    for (int i = 0; i < num_entries; i++)
        printf("%s\n", entries[i]);
}
%}

%x COMMENT
%x BRACE_COMMENT

digit  [0-9]
letter [a-zA-Z]

%%
 /* ── Delphi-style comment (* ... *) ── */
"(*"                  { LIST; BEGIN(COMMENT); }
<COMMENT>"*)"         { LIST; BEGIN(INITIAL); }
<COMMENT>\n           {
                        LIST;
                        printf("%d: %s", linenum++, buf);
                        buf[0] = '\0';
                      }
<COMMENT>.            { LIST; }
<COMMENT><<EOF>>      {
                        if (buf[0] != '\0') {
                            printf("%d: %s\n", linenum, buf);
                            buf[0] = '\0';
                        }
                        printf("line %d: unterminated comment\n", linenum);
                        yyterminate();
                      }

 /* ── Brace-style comment { ... } ── */
"{"                        { LIST; BEGIN(BRACE_COMMENT); }
<BRACE_COMMENT>"}"         { LIST; BEGIN(INITIAL); }
<BRACE_COMMENT>\n          {
                             LIST;
                             printf("%d: %s", linenum++, buf);
                             buf[0] = '\0';
                           }
<BRACE_COMMENT>.           { LIST; }
<BRACE_COMMENT><<EOF>>     {
                             if (buf[0] != '\0') {
                                 printf("%d: %s\n", linenum, buf);
                                 buf[0] = '\0';
                             }
                             printf("line %d: unterminated comment\n", linenum);
                             yyterminate();
                           }

 /* ── C++-style comment // ... ── */
"//".*                { LIST; }

 /* ── Boolean constants (case-insensitive, preserve original text) ── */
[tT][rR][uU][eE]     { LIST; printf("<boolean:%s>\n", yytext); after_operand = 1; }
[fF][aA][lL][sS][eE] { LIST; printf("<boolean:%s>\n", yytext); after_operand = 1; }

 /* ── Keywords (case-insensitive) ── */
[aA][rR][rR][aA][yY]                         { token(ARRAY); }
[bB][eE][gG][iI][nN]                         { token(BEGIN); }
[bB][oO][oO][lL][eE][aA][nN]                 { token(BOOLEAN); }
[cC][aA][sS][eE]                             { token(CASE); }
[cC][oO][nN][sS][tT]                         { token(CONST); }
[cC][oO][nN][tT][iI][nN][uU][eE]             { token(CONTINUE); }
[dD][oO]                                     { token(DO); }
[dD][oO][wW][nN][tT][oO]                     { token(DOWNTO); }
[eE][lL][sS][eE]                             { token(ELSE); }
[eE][nN][dD]                                 { token(END); }
[eE][xX][iI][tT]                             { token(EXIT); }
[fF][oO][rR]                                 { token(FOR); }
[fF][uU][nN][cC][tT][iI][oO][nN]             { token(FUNCTION); }
[gG][oO][tT][oO]                             { token(GOTO); }
[iI][fF]                                     { token(IF); }
[iI][nN]                                     { token(IN); }
[iI][nN][tT][eE][gG][eE][rR]                 { token(INTEGER); }
[lL][oO][oO][pP]                             { token(LOOP); }
[oO][fF]                                     { token(OF); }
[pP][rR][oO][cC][eE][dD][uU][rR][eE]         { token(PROCEDURE); }
[pP][rR][oO][gG][rR][aA][mM]                 { token(PROGRAM); }
[rR][eE][pP][eE][aA][tT]                     { token(REPEAT); }
[rR][eE][tT][uU][rR][nN]                     { token(RETURN); }
[rR][eE][aA][lL]                             { token(REAL); }
[sS][tT][rR][iI][nN][gG]                     { token(STRING); }
[tT][hH][eE][nN]                             { token(THEN); }
[tT][oO]                                     { token(TO); }
[tT][yY][pP][eE]                             { token(TYPE); }
[uU][nN][tT][iI][lL]                         { token(UNTIL); }
[vV][aA][rR]                                 { token(VAR); }
[wW][hH][iI][lL][eE]                         { token(WHILE); }
[wW][rR][iI][tT][eE]                         { token(WRITE); }
[wW][rR][iI][tT][eE][lL][nN]                 { token(WRITELN); }

 /* ── Logical & remainder operators (case-insensitive) ── */
[mM][oO][dD]                                 { token(MOD); }
[aA][nN][dD]                                 { token(AND); }
[oO][rR]                                     { token(OR); }
[nN][oO][tT]                                 { token(NOT); }

 /* ── Identifiers ── */
{letter}({letter}|{digit})* {
    LIST;
    if (lookup(yytext) < 0)
        insert(yytext);
    printf("<id: %s>\n", yytext);
    after_operand = 1;
}

 /* ── String constants (valid) ── */
\"([^\"\n]|\"\")*\" {
    int i, j;
    LIST;
    for (i = 1, j = 0; i < yyleng - 1; i++, j++) {
        if (yytext[i] == '"' && yytext[i + 1] == '"')
            i++;
        strbuf[j] = yytext[i];
    }
    strbuf[j] = '\0';
    printf("<string:%s>\n", strbuf);
    after_operand = 1;
}

 /* ── Unterminated string ── */
\"[^\"\n]* {
    LIST;
    printf("line %d: unterminated string\n", linenum);
}

 /* ── Invalid numbers (multiple decimal points) ── */
{digit}+("."{digit}+){2,} {
    LIST;
    printf("line %d: invalid number '%s'\n", linenum, yytext);
}

 /* ── Real constants (sign is always a separate operator token) ── */
{digit}+"."{digit}+([eE][+-]?{digit}+)? {
    LIST;
    printf("<real:%s>\n", yytext);
    after_operand = 1;
}

 /* ── Integer constants ── */
{digit}+ {
    tokenInteger(integer, atoi(yytext));
}

 /* ── Multi-character operators (named tokens) ── */
":="  { token(ASSIGN); }
"<="  { token(LE); }
">="  { token(GE); }
"<>"  { token(NE); }

 /* ── Single-character delimiters ── */
","   { token(','); }
":"   { token(':'); }
"."   { token('.'); }
";"   { token(';'); }
"("   { token('('); }
")"   { token(')'); after_operand = 1; }
"["   { token('['); }
"]"   { token(']'); after_operand = 1; }

 /* ── Negative real constants (context-sensitive) ── */
"-"{digit}+"."{digit}+([eE][+-]?{digit}+)? {
    if (after_operand) {
        yyless(1);
        token('-');
    } else {
        LIST;
        printf("<real:%s>\n", yytext);
        after_operand = 1;
    }
}

 /* ── Negative integer constants (context-sensitive) ── */
"-"{digit}+ {
    if (after_operand) {
        yyless(1);
        token('-');
    } else {
        tokenInteger(integer, atoi(yytext));
    }
}

 /* ── Arithmetic operators ── */
"+"   { token('+'); }
"-"   { token('-'); }
"*"   { token('*'); }
"/"   { token('/'); }

 /* ── Relational operators (named tokens) ── */
"<"   { token(LT); }
">"   { token(GT); }
"="   { token(EQ); }

 /* ── Whitespace ── */
[ \t]+ { LIST; }

 /* ── Newline ── */
\n {
    LIST;
    printf("%d: %s", linenum++, buf);
    buf[0] = '\0';
}

 /* ── Illegal character (report and continue) ── */
. {
    LIST;
    printf("line %d: illegal character '%s'\n", linenum, yytext);
}

%%

int yywrap() {
    return 1;
}

int main(int argc, char *argv[]) {
    create();

    if (argc > 1) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            fprintf(stderr, "Cannot open file: %s\n", argv[1]);
            return 1;
        }
    }

    yylex();

    if (buf[0] != '\0')
        printf("%d: %s\n", linenum, buf);

    printf("\nSymbol Table:\n");
    dump();

    return 0;
}
