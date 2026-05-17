TARGET   = compiler
LEX      = flex
YACC     = bison
YACCFLAG = -y -d
CC       = gcc
CFLAGS   = -Wall -g
JAVAA    = ./javaa/javaa
JAVA     = java

# Usage: make file=tests/S16_example run
#    or: make file=tests/S16_example.del run   (.del extension is stripped)
name := $(file:.del=)

run: $(name).class
	@echo '--- $(notdir $(name)) ---'
	$(JAVA) -cp $(dir $(name)). $(notdir $(name))

$(name).class: $(name).jasm
	cd $(dir $(name)) && $(abspath $(JAVAA)) $(notdir $(name)).jasm

$(name).jasm: $(TARGET) $(name).del
	./$(TARGET) $(name).del

.PHONY: run clean

$(TARGET): lex.yy.c y.tab.c symbols.o codegen.o
	$(CC) y.tab.c symbols.o codegen.o -o $(TARGET) -lfl $(CFLAGS)

lex.yy.c: delphi.lex y.tab.h
	$(LEX) -o lex.yy.c delphi.lex

y.tab.c y.tab.h: parser.yacc
	$(YACC) $(YACCFLAG) parser.yacc -o y.tab.c

symbols.o: symbols.c symbols.h
	$(CC) $(CFLAGS) -c symbols.c -o symbols.o

codegen.o: codegen.c codegen.h symbols.h
	$(CC) $(CFLAGS) -c codegen.c -o codegen.o

clean:
	$(RM) $(TARGET) lex.yy.c y.tab.* *.o tests/*.jasm tests/*.class
