{ §2.3.1 expression operator precedence and components.
  Spec precedence (highest→lowest): unary-, * / mod, + -, < <= = >= > <>, not, and, or. }
program exprs;
var i, j, k : integer;
var f : real;
var b : boolean;

function fn(x:integer): integer;
begin
    return x;
end fn;

begin
    i := 1 + 2 * 3;             { 7: * binds tighter than + }
    i := (1 + 2) * 3;           { parens override }
    i := 10 mod 3;              { mod = integer remainder }
    i := -i;                    { unary minus }
    i := - -i;                  { unary minus chain }
    i := - i * 2;               { unary minus tighter than * }
    f := 1.5 / 0.5;             { real / real }
    b := i < j;
    b := i <= j;
    b := i = j;
    b := i >= j;
    b := i > j;
    b := i <> j;
    b := not b;
    b := b and true;
    b := b or false;
    b := not b and (i < j) or (i = j);  { spec: not > and > or }
    i := fn(1) + fn(2);         { function calls in expression }
end exprs.
