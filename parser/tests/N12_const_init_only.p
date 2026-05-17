{ §2.1: const decl right-hand side and var initializer must be constant expressions. }
program neg;
var x : integer = 5;
const c1 = x;          { x is a variable, not a const }
var y : integer = c1 + 1;   { c1 + 1 is not a literal/signed/const }
begin
end neg.
