program fpc_unit_init_semantic;
{$mode delphi}
uses semtrack, semfpcinit;
begin
  Writeln('FPC_INIT ', Created, ' ', Destroyed);
  If (Created <> 1) or (Destroyed <> 1) then Halt(91);
  WriteLn('FPC_UNIT_INIT_PASS');
end.
