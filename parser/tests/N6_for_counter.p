{ §2.3.4: "The iteration variable counter cannot be modified within the loop." }
program neg;
var i, j : integer;
begin
    for i := 1 to 5 do
        i := i + 1;             { direct modification }
    for i := 1 to 5 do
        for j := 1 to 5 do
            i := j;             { modified from inner loop }
    for i := 1 to 5 do
        read i;                 { read also counts as modification }
end neg.
