{ This file should produce semantic errors covering each spec rule. }
program neg;
const c1 = 5;
var x, y : integer;
var a : array [1, 5] of integer;

function f(p:integer): integer;
begin
    return p;
end f;

procedure proc1;
begin
    write 1;
end proc1;

begin
    x := "hi";          { type mismatch on assignment }
    c1 := 10;           { cannot assign to const }
    a[true] := 1;       { non-int index }
    a[1] := "no";       { wrong elem type }
    read c1;            { read into const }
    read undeclared;    { read into undeclared }
    x := proc1;         { procedure used in expression }
    x := f;             { bare-fn call: arg-count mismatch caught }
    for x := 1 to 3 do
        x := x + 1;     { for-counter modified }
end neg.
