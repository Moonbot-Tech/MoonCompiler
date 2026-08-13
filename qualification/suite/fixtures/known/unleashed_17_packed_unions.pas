program unleashed_17_packed_unions;

{$mode unleashed}

type
  TRegs = packed record
    union Flags: QWord; packed record C, Z: Boolean; end; end;
    union DataBank: LongWord; packed record DB: Byte; end; end;
    union ProgramCounter: Word; packed record PCL, PCH: Byte; end; end;
    Mode: Byte;
  end;

begin
  if SizeOf(TRegs) <> 15 then Halt(1);
  if OffsetOf(TRegs.Flags) <> 0 then Halt(2);
  if OffsetOf(TRegs.DataBank) <> 8 then Halt(3);
  if OffsetOf(TRegs.ProgramCounter) <> 12 then Halt(4);
  if OffsetOf(TRegs.Mode) <> 14 then Halt(5);
  WriteLn('PASS unleashed-17');
end.
