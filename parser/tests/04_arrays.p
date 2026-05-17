{ Lecture p3 array form: id<,...,id>: array [num,num] of type, inside a var. }
program arrays;
var a : array [1, 10] of integer;
var b : array [0, 5] of boolean;
var f : array [1, 100] of real;
var g, h : array [1, 4] of string;
begin
    a[1] := 5;
    b[0] := true;
    f[2] := 3.14;
    g[1] := "hello";
end arrays.
