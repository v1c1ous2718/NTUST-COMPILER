{ §2.2.2: "procedures with no return type can not be used in expressions." }
program neg;
var x : integer;

procedure p;
begin
    write 1;
end p;

begin
    x := p;
    x := p() + 1;
end neg.
