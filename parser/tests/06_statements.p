{ §2.3 statements: assignment, array assignment, write/writeln/read,
  return, block, if/else, while, repeat-until, for-to, proc call. }
program statements;
var i : integer;
var s : string;
var arr : array [1, 5] of integer;
var b : boolean;

function retInt : integer;
begin
    return 0;
end retInt;

procedure noop;
begin
    write 0;
end noop;

begin
    i := 10;
    arr[1] := i + 1;
    write i;
    writeln "ok";
    read s;
    if (i > 0) then
        write i;
    if (i = 0) then
        write 0;
    else
        write i;
    while i > 0 do
        i := i - 1;
    repeat
        i := i + 1;
    until i = 5;
    for i := 1 to 3 do
        write i;
    begin
        var inner : integer;
        const k = 99;
        inner := k;
        write inner;
    end;
    noop;
    noop();
    i := retInt;
end statements.
