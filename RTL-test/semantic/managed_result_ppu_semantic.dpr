program managed_result_ppu_semantic;
{$mode delphi}
uses semtrack, semmopreload;
procedure Test;
var X: TManaged;
begin
  for var I := 0 to 15 do begin
    Store(X);
    If (X.Value <> 42) or (X.Token.Value <> 42) then Halt(71);
  end;
end;
begin
  Test;
  If Created <> Destroyed then Halt(72);
  WriteLn('RELOAD_OK ', Created, ' ', Destroyed);
  WriteLn('MANAGED_RESULT_PPU_PASS');
end.
