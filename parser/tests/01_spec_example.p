{ §2.2.2 spec example — must parse with no errors. }
program example;
const a = 5;
var c : integer;

function add(a:integer, b:integer): integer;
begin
    return a+b;
end add;

begin
    c := add(a, 10);
    write c;
end example.
