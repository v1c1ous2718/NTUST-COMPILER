LEX    = flex
CC     = gcc
CFLAGS = -Wall -g
TARGET = scanner

all: $(TARGET)

$(TARGET): lex.yy.c
	$(CC) $(CFLAGS) -o $@ lex.yy.c

lex.yy.c: delphi.lex
	$(LEX) delphi.lex

clean:
	rm -f lex.yy.c $(TARGET)

.PHONY: all clean
