program sse_result_store_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses SysUtils;
type TCells = array[0..3] of UInt64; PCells = ^TCells;
function Half(V: Double): Double; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := V * 0.5;
end;
function Bits(V: Double): UInt64; inline;
begin
  {$IFDEF FPC}Result := UInt64(V);{$ELSE}Move(V, Result, SizeOf(Result));{$ENDIF}
end;
function ThroughTry(P: PUInt64; V: Double): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var U: UInt64;
begin
  U := {$IFDEF FPC}UInt64(Half(V)){$ELSE}Bits(Half(V)){$ENDIF};
  try
    P^ := U;
    Result := 1;
  except
    on E: EAccessViolation do Result := 2;
  end;
end;
function Indexed(P: PCells; I: NativeInt; V: Double): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
var U: UInt64;
begin
  U := {$IFDEF FPC}UInt64(Half(V)){$ELSE}Bits(Half(V)){$ENDIF};
  Inc(I);
  P^[I] := U;
  Result := P^[I];
end;
var Cell, Expected: UInt64; D: Double; Cells: TCells;
begin
  D := 5;
  Move(D, Expected, SizeOf(Expected));
  If ThroughTry(@Cell, 10) <> 1 then Halt(71);
  If Cell <> Expected then begin WriteLn('BITS_NOT_VIEW ', Cell, ' ', Expected); Halt(72); end;
  If ThroughTry(nil, 10) <> 2 then Halt(73);
  If Indexed(@Cells, 1, 10) <> Expected then Halt(74);
  If (Cells[0] <> 0) or (Cells[1] <> 0) or (Cells[2] <> Expected) or (Cells[3] <> 0) then Halt(75);
  WriteLn('SSE_RESULT_STORE_PASS');
end.
