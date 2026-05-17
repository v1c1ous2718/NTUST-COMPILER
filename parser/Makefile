LEX    = flex
YACC   = bison -y -d
CC     = gcc
CFLAGS = -Wall -g

TARGET = parser

all: $(TARGET)

$(TARGET): y.tab.c lex.yy.c y.tab.h symbols.o
	$(CC) $(CFLAGS) -o $@ y.tab.c symbols.o -lfl

y.tab.c y.tab.h: parser.y
	$(YACC) parser.y

lex.yy.c: delphi.lex y.tab.h
	$(LEX) delphi.lex

symbols.o: symbols.c symbols.h
	$(CC) $(CFLAGS) -c symbols.c

clean:
	rm -f $(TARGET) y.tab.c y.tab.h y.output lex.yy.c *.o

.PHONY: all clean
