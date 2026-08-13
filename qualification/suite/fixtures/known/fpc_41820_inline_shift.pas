program fpc_41820_inline_shift;

function ShiftRight(Q: QWord): DWord; inline;
begin
  ShiftRight := DWord(Q shr 32);
end;

function ShiftLeft(Q: QWord): DWord; inline;
begin
  ShiftLeft := DWord(Q shl 32);
end;

begin
  if ShiftRight(1) <> 0 then
  begin
    WriteLn('FAIL fpc-41820 shr=', ShiftRight(1));
    Halt(1);
  end;
  if ShiftLeft(1) <> 0 then
  begin
    WriteLn('FAIL fpc-41820 shl=', ShiftLeft(1));
    Halt(2);
  end;
  WriteLn('PASS fpc-41820');
end.
