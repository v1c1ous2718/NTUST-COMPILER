{ §3: "The identifier after the end of program or procedure declaration must
       be the same identifiers as the name given at the beginning." }
program myprog;

function fn : integer;
begin
    return 1;
end otherFn;

procedure pr;
begin
    write 1;
end otherPr;

begin
end otherProg.
