{ §2.2.2 functions and procedures — formals optional, parens optional when no args. }
program subprogs;
var x : integer;

function fNoArgs : integer;
begin
    return 42;
end fNoArgs;

function fEmptyParens(): integer;
begin
    return 1;
end fEmptyParens;

function fOneArg(a:integer): integer;
begin
    return a;
end fOneArg;

function fMany(a:integer, b:real, c:string, d:boolean): integer;
var local : integer;
const k = 7;
begin
    local := a + k;
    return local;
end fMany;

procedure pNoArgs;
begin
    write 1;
end pNoArgs;

procedure pEmptyParens();
begin
    write 2;
end pEmptyParens;

procedure pWithArgs(a:integer, b:integer);
begin
    write a + b;
end pWithArgs;

begin
    x := fNoArgs;
    x := fEmptyParens();
    x := fOneArg(1);
    x := fMany(1, 2.0, "x", true);
    pNoArgs;
    pEmptyParens();
    pWithArgs(1, 2);
end subprogs.
