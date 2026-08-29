program seh_regvar_codegen;

{$mode unleashed}
{$Q-}{$R-}

var
  Guard: Integer;

function ScanWithIrrelevantTry(const Data: RawByteString): QWord; noinline;
var
  I: Integer;
  Sum: QWord;
begin
  try
    If Guard < 0 then
      Guard := 0;
  except
    Guard := -1;
  end;
  Sum := 0;
  for I := 1 to Length(Data) do
    Inc(Sum, Byte(Data[I]));
  Result := Sum;
end;

var
  Data: RawByteString;
  I: Integer;
begin
  SetLength(Data, 4096);
  for I := 1 to Length(Data) do
    Data[I] := AnsiChar(I);
  WriteLn('SEHREGVAR-CODEGEN:', ScanWithIrrelevantTry(Data));
end.
