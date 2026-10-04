program sse_result_handler_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses SysUtils;
function Half(V: Double): Double; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := V * 0.5;
end;
function Bits(V: Double): UInt64; inline;
begin
  Move(V, Result, SizeOf(Result));
end;
function Work(P: PUInt64; V: Double; out Seen: UInt64): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var U: UInt64;
begin
  U := {$IFDEF FPC}UInt64(Half(V)){$ELSE}Bits(Half(V)){$ENDIF};
  try
    P^ := U;
    Seen := U;
    Result := 1;
  except
    on E: EAccessViolation do begin
      Seen := U;
      Result := 2;
    end;
  end;
end;
var Cell, Seen, Expected: UInt64; D: Double;
begin
  D := 5;
  Move(D, Expected, SizeOf(Expected));
  If Work(@Cell, 10, Seen) <> 1 then Halt(71);
  If (Seen <> Expected) or (Cell <> Expected) then Halt(72);
  Seen := 0;
  If Work(nil, 10, Seen) <> 2 then Halt(73);
  If Seen <> Expected then Halt(74);
  WriteLn('SSE_RESULT_HANDLER_PASS');
end.
