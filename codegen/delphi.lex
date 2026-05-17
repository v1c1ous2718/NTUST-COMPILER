%{
#include "y.tab.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE_LENG 256

#define LIST                strcat(buf, yytext)
#define token(t)            { LIST; if (Opt_LexPrint) printf("<%s>\n", #t); return (t); }
#define tokenChar(c)        { LIST; if (Opt_LexPrint) printf("<%s>\n", #c); return (c); }

int  linenum = 1;
char buf[MAX_LINE_LENG];
char strbuf[MAX_LINE_LENG];
extern int Opt_LexPrint;
extern int Opt_CodePrint;
%}

%option noinput nounput

%x COMMENT
%x BRACE_COMMENT

digit  [0-9]
letter [a-zA-Z_]

%%
 /* Delphi-style comment (* ... *) */
"(*"                  { LIST; BEGIN(COMMENT); }
<COMMENT>"*)"         { LIST; BEGIN(INITIAL); }
<COMMENT>\n           {
                        LIST;
                        if (Opt_CodePrint) printf("%d: %s", linenum, buf);
                        linenum++;
                        buf[0] = '\0';
                      }
<COMMENT>.            { LIST; }
<COMMENT><<EOF>>      {
                        if (buf[0] != '\0') {
                            if (Opt_CodePrint) printf("%d: %s\n", linenum, buf);
                            buf[0] = '\0';
                        }
                        printf("line %d: unterminated comment\n", linenum);
                        yyterminate();
                      }

 /* Brace-style comment { ... } */
"{"                        { LIST; BEGIN(BRACE_COMMENT); }
<BRACE_COMMENT>"}"         { LIST; BEGIN(INITIAL); }
<BRACE_COMMENT>\n          {
                             LIST;
                             if (Opt_CodePrint) printf("%d: %s", linenum, buf);
                             linenum++;
                             buf[0] = '\0';
                           }
<BRACE_COMMENT>.           { LIST; }
<BRACE_COMMENT><<EOF>>     {
                             if (buf[0] != '\0') {
                                 if (Opt_CodePrint) printf("%d: %s\n", linenum, buf);
                                 buf[0] = '\0';
                             }
                             printf("line %d: unterminated comment\n", linenum);
                             yyterminate();
                           }

 /* C++-style comment // ... */
"//".*                { LIST; }

 /* Boolean constants (case-insensitive) */
[tT][rR][uU][eE]      {
                        LIST;
                        if (Opt_LexPrint) printf("<boolean:%s>\n", yytext);
                        yylval.ival = 1;
                        return BOOL_CONST;
                      }
[fF][aA][lL][sS][eE]  {
                        LIST;
                        if (Opt_LexPrint) printf("<boolean:%s>\n", yytext);
                        yylval.ival = 0;
                        return BOOL_CONST;
                      }

 /* Keywords (case-insensitive) */
[aA][rR][rR][aA][yY]                         { token(ARRAY); }
[bB][eE][gG][iI][nN]                         { LIST; if (Opt_LexPrint) printf("<BEGIN>\n"); return KW_BEGIN; }
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
[rR][eE][aA][dD]                             { token(READ); }
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

 /* Logical & remainder operators (case-insensitive) */
[mM][oO][dD]                                 { token(MOD); }
[aA][nN][dD]                                 { token(AND); }
[oO][rR]                                     { token(OR); }
[nN][oO][tT]                                 { token(NOT); }

 /* Identifiers */
{letter}({letter}|{digit})* {
    LIST;
    if (Opt_LexPrint) printf("<id: %s>\n", yytext);
    yylval.sval = strdup(yytext);
    return ID;
}

 /* String constants (valid) */
\"([^\"\n]|\"\")*\" {
    int i, j;
    LIST;
    for (i = 1, j = 0; i < yyleng - 1; i++, j++) {
        if (yytext[i] == '"' && yytext[i + 1] == '"')
            i++;
        strbuf[j] = yytext[i];
    }
    strbuf[j] = '\0';
    if (Opt_LexPrint) printf("<string:%s>\n", strbuf);
    yylval.sval = strdup(strbuf);
    return STR_CONST;
}

 /* Unterminated string */
\"[^\"\n]* {
    LIST;
    printf("line %d: unterminated string\n", linenum);
}

 /* Invalid numbers (multiple decimal points) */
{digit}+("."{digit}+){2,} {
    LIST;
    printf("line %d: invalid number '%s'\n", linenum, yytext);
}

 /* Real constants */
{digit}+"."{digit}+([eE][+-]?{digit}+)? {
    LIST;
    if (Opt_LexPrint) printf("<real:%s>\n", yytext);
    yylval.dval = atof(yytext);
    return REAL_CONST;
}

 /* Integer constants */
{digit}+ {
    LIST;
    int v = atoi(yytext);
    if (Opt_LexPrint) printf("<integer:%d>\n", v);
    yylval.ival = v;
    return INT_CONST;
}

 /* Multi-character operators */
":="  { token(ASSIGN); }
"<="  { token(LE); }
">="  { token(GE); }
"<>"  { token(NE); }

 /* Single-character delimiters & operators (return literal) */
","   { tokenChar(','); }
":"   { tokenChar(':'); }
"."   { tokenChar('.'); }
";"   { tokenChar(';'); }
"("   { tokenChar('('); }
")"   { tokenChar(')'); }
"["   { tokenChar('['); }
"]"   { tokenChar(']'); }

"+"   { tokenChar('+'); }
"-"   { tokenChar('-'); }
"*"   { tokenChar('*'); }
"/"   { tokenChar('/'); }

 /* Relational operators */
"<"   { token(LT); }
">"   { token(GT); }
"="   { token(EQ); }

 /* Whitespace */
[ \t]+ { LIST; }

 /* Newline */
\n {
    LIST;
    if (Opt_CodePrint) printf("%d: %s", linenum, buf);
    linenum++;
    buf[0] = '\0';
}

 /* Illegal character */
. {
    LIST;
    printf("line %d: illegal character '%s'\n", linenum, yytext);
}

%%

int yywrap() {
    return 1;
}
