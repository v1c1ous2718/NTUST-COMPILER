{ §3 scope rules similar to C — inner scope shadows outer. }
program scoping;
const k = 1;
var x : integer = 10;

function usesOuter : integer;
begin
    return x + k;
end usesOuter;

function shadows : integer;
var x : integer = 99;
begin
    return x;
end shadows;

procedure blockScope;
var x : integer;
begin
    x := 1;
    begin
        var x : integer;
        x := 2;
        write x;
    end;
    write x;
end blockScope;

begin
    write usesOuter;
    write shadows;
    blockScope;
end scoping.
