program fpc_unit_final_throw_semantic;
{$mode delphi}
uses SysUtils, semtrack, semfpcfinal;
procedure FinalizeRunner; external name 'FPC_FINALIZEUNITS';
var Caught: Boolean;
begin
  try
    FinalizeRunner;
  except
    on E: Exception do begin
      If E.Message <> 'final callback' then raise;
      Caught := True;
      WriteLn('CAUGHT ', E.Message);
    end;
  end;
  WriteLn('AFTER_CALLBACK ', Created, ' ', Destroyed);
  If not Caught or (Created <> 1) or (Destroyed <> 1) then Halt(93);
  WriteLn('FPC_UNIT_FINAL_THROW_PASS');
end.
