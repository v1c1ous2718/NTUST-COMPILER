{ §2.3.3 / §2.3.4: if/while/repeat-until conditions must be boolean. }
program neg;
var i : integer;
var s : string;
begin
    if (i) then write 1;
    if (s) then write 1; else write 2;
    while i do write 1;
    repeat write 1; until s;
end neg.
