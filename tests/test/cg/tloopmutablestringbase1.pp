{ %OPT=-O3 }

program tloopmutablestringbase1;

{$mode delphi}
{$R-}{$Q-}

var
  U: UnicodeString;
  A: AnsiString;
  D: array of Byte;
  I: Integer;
  Sum: Integer;

begin
  U:='abcdefgh';
  Sum:=0;
  for I:=1 to 8 do
    begin
      Inc(Sum,Ord(U[I]));
      if I=3 then
        U:='ABCDEFGH';
    end;
  if Sum<>644 then
    Halt(1);

  A:='abcdefgh';
  Sum:=0;
  for I:=1 to 8 do
    begin
      Inc(Sum,Ord(A[I]));
      if I=3 then
        A:='ABCDEFGH';
    end;
  if Sum<>644 then
    Halt(2);

  SetLength(D,8);
  for I:=0 to High(D) do
    D[I]:=Byte(I+1);
  Sum:=0;
  for I:=0 to High(D) do
    begin
      Inc(Sum,D[I]);
      if I=2 then
        begin
          SetLength(D,12);
          D[3]:=40;
        end;
    end;
  if Sum<>72 then
    Halt(3);
end.
