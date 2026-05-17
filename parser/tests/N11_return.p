{ §2.2.2: procedure cannot return value; function must return its declared type. }
program neg;

function f : integer;
begin
    return "wrong";    { wrong return type }
end f;

function g : integer;
begin
    return;            { missing value }
end g;

procedure p;
begin
    return 1;          { proc cannot return value }
end p;

begin
end neg.
