program tdelphiqualifiedinteger1;

{$mode delphi}

type
  PSystemInteger = ^System.Integer;
  TSystemIntegerArray = array[0..2] of System.Integer;

procedure AssignQualified(Value: Word; var ByVar: System.Integer;
  out ByOut: System.Integer);
begin
  ByVar := System.Integer(Value);
  ByOut := Value;
end;

procedure CheckWord(Value: Word; ErrorCode: Byte);
var
  Bare: Integer;
  Qualified: System.Integer;
  ViaOut: System.Integer;
  QualifiedPointer: PSystemInteger;
  Values: TSystemIntegerArray;
begin
  Bare := Integer(Value);
  Qualified := System.Integer(Value);
  AssignQualified(Value, Qualified, ViaOut);
  QualifiedPointer := @Qualified;
  Values[0] := Value;
  Values[1] := System.Integer(Value);
  Values[2] := QualifiedPointer^;
  if (Qualified <> Bare) or
     (ViaOut <> Bare) or
     (Values[0] <> Bare) or
     (Values[1] <> Bare) or
     (Values[2] <> Bare) then
    Halt(ErrorCode);
end;

begin
  if SizeOf(System.Integer) <> 4 then
    Halt(1);
  if (Low(System.Integer) <> Low(Integer)) or
     (High(System.Integer) <> High(Integer)) then
    Halt(2);

  CheckWord(0, 10);
  CheckWord(32767, 11);
  CheckWord(32768, 12);
  CheckWord(65535, 13);

  if System.Integer(Byte(255)) <> 255 then
    Halt(20);
  if System.Integer(SmallInt(-1)) <> -1 then
    Halt(21);
  if System.Int64(Word(65535)) <> 65535 then
    Halt(22);
  if System.Cardinal(Word(65535)) <> 65535 then
    Halt(23);
  if SizeOf(System.NativeInt) <> SizeOf(Pointer) then
    Halt(24);
end.
