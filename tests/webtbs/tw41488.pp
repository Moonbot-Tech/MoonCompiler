{ %opt=-Sew -Cr }
{$MODE OBJFPC}
type
   TTest = 10..20;
var
   A: TTest;
   S: String;
begin
   A := 10;
   Inc(A);
   Str(Succ(A), S); // 12
   if S <> '12' then
     halt(1);
   Str(Pred(A), S); // 10
   if S <> '10' then
     halt(2);
   Dec(A);
end.
