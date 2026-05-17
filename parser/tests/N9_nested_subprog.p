{ §2.2.2: "No functions and procedures may be declared inside a function or procedure." }
program neg;
function outer : integer;
function inner : integer;
begin
    return 1;
end inner;
begin
    return 2;
end outer;
begin
end neg.
