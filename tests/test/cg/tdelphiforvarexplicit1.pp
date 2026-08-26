program tdelphiforvarexplicit1;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

type
  PIntegerAlias = ^Integer;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  A,
  B,
  Count,
  Sum: Integer;
  Pointers: array[0..1] of PIntegerAlias;
  Words: array[0..1] of string;
begin
  A:=10;
  B:=20;
  Pointers[0]:=@A;
  Pointers[1]:=@B;
  Words[0]:='ab';
  Words[1]:='cde';

  Sum:=0;
  for var Item: PIntegerAlias in Pointers do
    Inc(Sum,Item^);
  Check(Sum=30,1);

  Count:=0;
  for var Word: string in Words do
    Inc(Count,Length(Word));
  Check(Count=5,2);

  Sum:=0;
  for var I: Integer:=0 to High(Pointers) do
    Inc(Sum,Pointers[I]^);
  Check(Sum=30,3);
end.
