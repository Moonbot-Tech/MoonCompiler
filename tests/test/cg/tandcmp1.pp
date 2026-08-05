{ %CPU=x86_64 }
{ %OPT=-O3 -OoNOAUTOINLINE }
program tandcmp1;

{$mode delphi}

type
  TTestRecord = record
    W1, W2, W3, W4: Word;
  end;

var
  TestRecord: TTestRecord;

function GetRecord: TTestRecord;
begin
  Result := TestRecord;
end;

function LowByteEquals255(Value: QWord): Boolean;
begin
  Result := (Value and $ff) = 255;
end;

function MaskedEqualsMinusOne(Value: Int64): Boolean;
begin
  Result := (Value and $ff) = -1;
end;

function LowByteAbove127(Value: QWord): Boolean;
begin
  Result := (Value and $ff) > 127;
end;

begin
  TestRecord.W2 := $ABE3;
  TestRecord.W3 := $2D57;
  if Byte(GetRecord.W2) <> $E3 then
    Halt(1);
  if Byte(GetRecord.W3) <> $57 then
    Halt(2);
  if not LowByteEquals255($1234FF) then
    Halt(3);
  if LowByteEquals255($1234FE) then
    Halt(4);
  if MaskedEqualsMinusOne(255) then
    Halt(5);
  if not LowByteAbove127(255) then
    Halt(6);
  if LowByteAbove127(127) then
    Halt(7);
end.
