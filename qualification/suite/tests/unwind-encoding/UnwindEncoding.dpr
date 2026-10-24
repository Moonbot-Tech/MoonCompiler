program UnwindEncoding;
{$mode delphiunicode}
uses SysUtils, UnwindEncodingUnit;
var I, Caught: Integer;
begin
  for I := 1 to 1000 do
    try
      WithLSDA;
    except
      on E: Exception do begin
        If E.Message <> 'unwind' then Halt(11);
        Inc(Caught);
      end;
    end;
  If (Cleaned <> 1000) or (Caught <> 1000) or (Returned <> 0) then Halt(12);
  Halt(0);
end.
