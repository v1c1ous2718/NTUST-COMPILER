{ undeclared identifier in various positions }
program neg;
var x : integer;
begin
    x := y;             { rhs undeclared }
    z := 1;             { lhs undeclared }
    read undeclared;    { read undeclared }
    nope();             { call undeclared }
end neg.
