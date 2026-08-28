program sparse_case_tree_semantic;

{$APPTYPE CONSOLE}

uses
  SysUtils;

function JsonDelimiterClass(Value: Byte): Integer;
begin
  case Value of
    34:
      Result := 1;
    44, 58, 91, 93, 123, 125:
      Result := 2;
  else
    Result := 0;
  end;
end;

function JsonDelimiterOracle(Value: Byte): Integer;
begin
  If Value = 34 then
    Result := 1
  else If (Value = 44) or (Value = 58) or (Value = 91) or
      (Value = 93) or (Value = 123) or (Value = 125) then
    Result := 2
  else
    Result := 0;
end;

function SignedSparse(Value: Integer): Integer;
begin
  case Value of
    -1000:
      Result := 1;
    -257, -17:
      Result := 2;
    0:
      Result := 3;
    19, 511, 1001:
      Result := 4;
  else
    Result := 0;
  end;
end;

function SignedSparseOracle(Value: Integer): Integer;
begin
  If Value = -1000 then
    Result := 1
  else If (Value = -257) or (Value = -17) then
    Result := 2
  else If Value = 0 then
    Result := 3
  else If (Value = 19) or (Value = 511) or (Value = 1001) then
    Result := 4
  else
    Result := 0;
end;

var
  I: Integer;
begin
  for I := 0 to 255 do
    If JsonDelimiterClass(Byte(I)) <> JsonDelimiterOracle(Byte(I)) then
      raise Exception.CreateFmt('byte case mismatch at %d', [I]);

  for I := -1200 to 1200 do
    If SignedSparse(I) <> SignedSparseOracle(I) then
      raise Exception.CreateFmt('signed case mismatch at %d', [I]);

  WriteLn('SPARSE_CASE_TREE_PASS');
end.
