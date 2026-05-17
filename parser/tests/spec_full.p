program full;
const s = "Hey There";
const i = -25;
const f = 3.14;
const b = true;
var ss : string;
var ii : integer = 100;
var d : real;
var bb : boolean;
var arr1 : array [1, 10] of integer;
var arr2 : array [0, 5] of boolean;
var arr3 : array [1, 100] of real;

function add(x:integer, y:integer): integer;
begin
    return x+y;
end add;

procedure greet;
begin
    write "hi";
end greet;

begin
    ii := add(i, 10);
    write ii;
    if (bb) then
        writeln "true";
    else
        writeln "false";
    while ii > 0 do
    begin
        ii := ii - 1;
    end;
    repeat
        ii := ii + 1;
    until ii = 5;
    for ii := 1 to 10 do
        arr1[ii] := ii;
    greet;
end full.
