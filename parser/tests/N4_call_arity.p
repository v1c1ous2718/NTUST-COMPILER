{ §3: "The types of formal parameters must match the types of the actual parameters." }
program neg;
var x : integer;

function f(a:integer, b:real): integer;
begin
    return a;
end f;

begin
    x := f(1);              { wrong arity }
    x := f(1, 2, 3);        { wrong arity }
    x := f("hi", 1.0);      { wrong types }
end neg.
