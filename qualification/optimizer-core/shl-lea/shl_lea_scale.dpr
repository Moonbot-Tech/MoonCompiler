program shl_lea_scale;

{ x86-64 peephole: "shl $1,%r; lea (%r,%r,2),%r" (x*2*3) was merged into
  "lea (%r,%r,4),%r" (x*5) because the lea's base is the shifted register
  and the merged lea reads the unshifted one.  Same for "shl; add %r,%r".
  The loop keeps the value out of constant folding; -O2 and -O3 must print
  the same digest as the arithmetic oracle computed with a runtime factor. }

{$mode delphi}
{$Q-}
{$R-}

var
  Data: array[0..255] of Cardinal;

function TimesSix(N: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
  begin
    Result := Result + Data[I and 255];
    Result := Result shl 1;
    Result := Result * 3;
  end;
end;

function TimesFour(N: Integer): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
  begin
    Result := Result + Data[I and 255];
    Result := Result shl 1;
    Result := Result + Result;
  end;
end;

function Oracle(N: Integer; Factor: Cardinal): Cardinal;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
    Result := (Result + Data[I and 255]) * Factor;
end;

var
  I: Integer;
  Six, Four: Cardinal;
begin
  for I := 0 to 255 do
    Data[I] := Cardinal(I * 37 + 11);
  Six := Oracle(1000, Cardinal(ParamCount + 6));
  Four := Oracle(1000, Cardinal(ParamCount + 4));
  If (TimesSix(1000) <> Six) or (TimesFour(1000) <> Four) then
  begin
    WriteLn('FAIL six=', TimesSix(1000), ' expected=', Six,
      ' four=', TimesFour(1000), ' expected=', Four);
    Halt(1);
  end;
  WriteLn('SHL_LEA_SCALE_OK ', Six, ' ', Four);
end.
