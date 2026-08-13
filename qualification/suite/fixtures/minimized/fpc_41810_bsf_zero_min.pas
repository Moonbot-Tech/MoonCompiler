program fpc_41810_bsf_zero_min;

var
  D: DWord;
  RD: LongWord;
  Bit: LongWord;
begin
  D := 1;
  RD := 0;
  for Bit := 0 to 32 do
  begin
    RD := BsfDWord(D);
    D := D shl 1;
  end;
  if RD <> $ff then
  begin
    WriteLn('FAIL fpc-41810 dword=', RD);
    Halt(1);
  end;
  WriteLn('PASS fpc-41810');
end.
