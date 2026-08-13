program Fpc41766ConstrefAbsolute;

{$mode objfpc}

function FirstDWord(constref Value): UInt32;
var
  DWordValue: UInt32 absolute Value;
begin
  Result := DWordValue;
end;

function FirstByteAsDWord(constref Values): UInt32;
var
  Bytes: array[Byte] of Byte absolute Values;
begin
  Result := FirstDWord(Bytes[0]);
end;

begin
end.
