program l_min;
{$mode delphiunicode}{$H+}
{$Q-}{$R-}
uses SysUtils;
type
  TBox = record
    Fi32: Integer;
  end;
var
  Sink: UInt64;
function RawI32(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(V));
end;
procedure Probe;
var
  R: UInt64;
  Arr: array[0..3] of Integer;
  W: TBox;
begin
  R := High(UInt64) - 1;
  W.Fi32 := 1;
  Arr[1] := Integer(-1581716328);
  R := RawI32(Arr[1]);
  if W.Fi32 <> 1 then
    R := 0;
  WriteLn('decimal     = ', R);
  WriteLn('hex         = ', IntToHex(R, 16));
  WriteLn('eq-expected = ', R = UInt64($00000000A1B8EC98));
  WriteLn('hi32        = ', R shr 32);
  Sink := R;
end;
begin
  Probe;
  WriteLn('sink        = ', Sink);
end.
