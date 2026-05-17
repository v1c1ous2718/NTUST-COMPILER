{ §2.3.1: array reference uses "integer expression" as the index. }
program neg;
var a : array [1, 5] of integer;
begin
    a[true] := 1;
    a[1] := "wrong";
end neg.
