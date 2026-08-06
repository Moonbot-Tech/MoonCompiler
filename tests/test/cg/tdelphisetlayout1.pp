{ %OPT=-O3 }
program tdelphisetlayout1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

type
  TSet0 = set of 0..0;
  TSet8 = set of 0..8;
  TSet16 = set of 0..16;
  TSet24 = set of 0..24;
  TSet32 = set of 0..32;
  TSet33 = set of 0..33;
  TSet63 = set of 0..63;
  TSet64 = set of 0..64;
  TSet127 = set of 0..127;
  TSet128 = set of 0..128;
  TSet1To32 = set of 1..32;
  TSet32To64 = set of 32..64;

  TRecord0 = record A: Byte; S: TSet0; Z: Byte; end;
  TRecord8 = record A: Byte; S: TSet8; Z: Byte; end;
  TRecord16 = record A: Byte; S: TSet16; Z: Byte; end;
  TRecord32 = record A: Byte; S: TSet32; Z: Byte; end;
  TRecord64 = record A: Byte; S: TSet64; Z: Byte; end;
  TRecord127 = record A: Byte; S: TSet127; Z: Byte; end;
  TRecord128 = record A: Byte; S: TSet128; Z: Byte; end;
  TPackedRecord32 = packed record A: Byte; S: TSet32; Z: Byte; end;
  TNestedRecord = record
    A: Byte;
    Sets: array[0..1] of TSet64;
    Z: Byte;
  end;
  TSetHolder = class
  public
    A: Byte;
    S: TSet64;
    Z: Byte;
  end;

var
  Source: TSet32;
  CopyValue: TSet32;
  I: Integer;
  R0: TRecord0;
  R8: TRecord8;
  R16: TRecord16;
  R32: TRecord32;
  R64: TRecord64;
  R127: TRecord127;
  R128: TRecord128;
  PR32: TPackedRecord32;
  NR: TNestedRecord;
  Holder: TSetHolder;

function CheckSetParameter(Value: TSet64): Boolean;
begin
  Result := (0 in Value) and (64 in Value) and not (1 in Value);
end;

begin
  If SizeOf(TSet0) <> 1 then Halt(1);
  If SizeOf(TSet8) <> 2 then Halt(2);
  If SizeOf(TSet16) <> 4 then Halt(3);
  If SizeOf(TSet24) <> 4 then Halt(4);
  If SizeOf(TSet32) <> 8 then Halt(5);
  If SizeOf(TSet33) <> 8 then Halt(6);
  If SizeOf(TSet63) <> 8 then Halt(7);
  If SizeOf(TSet64) <> 9 then Halt(8);
  If SizeOf(TSet127) <> 16 then Halt(9);
  If SizeOf(TSet128) <> 17 then Halt(10);
  If SizeOf(TSet1To32) <> 8 then Halt(11);
  If SizeOf(TSet32To64) <> 8 then Halt(12);

  Source := [];
  for I := 0 to 32 do
    If (I and 1) <> 0 then
      Include(Source, I);
  CopyValue := Source;
  for I := 0 to 32 do
    If ((I in CopyValue) <> ((I and 1) <> 0)) then Halt(13);

  If (SizeOf(R0) <> 3) or
     (NativeUInt(@R0.S) - NativeUInt(@R0) <> 1) or
     (NativeUInt(@R0.Z) - NativeUInt(@R0) <> 2) then Halt(20);
  If (SizeOf(R8) <> 4) or
     (NativeUInt(@R8.S) - NativeUInt(@R8) <> 1) or
     (NativeUInt(@R8.Z) - NativeUInt(@R8) <> 3) then Halt(21);
  If (SizeOf(R16) <> 6) or
     (NativeUInt(@R16.S) - NativeUInt(@R16) <> 1) or
     (NativeUInt(@R16.Z) - NativeUInt(@R16) <> 5) then Halt(22);
  If (SizeOf(R32) <> 10) or
     (NativeUInt(@R32.S) - NativeUInt(@R32) <> 1) or
     (NativeUInt(@R32.Z) - NativeUInt(@R32) <> 9) then Halt(23);
  If (SizeOf(R64) <> 11) or
     (NativeUInt(@R64.S) - NativeUInt(@R64) <> 1) or
     (NativeUInt(@R64.Z) - NativeUInt(@R64) <> 10) then Halt(24);
  If (SizeOf(R127) <> 18) or
     (NativeUInt(@R127.S) - NativeUInt(@R127) <> 1) or
     (NativeUInt(@R127.Z) - NativeUInt(@R127) <> 17) then Halt(25);
  If (SizeOf(R128) <> 19) or
     (NativeUInt(@R128.S) - NativeUInt(@R128) <> 1) or
     (NativeUInt(@R128.Z) - NativeUInt(@R128) <> 18) then Halt(26);
  If (SizeOf(PR32) <> 10) or
     (NativeUInt(@PR32.S) - NativeUInt(@PR32) <> 1) or
     (NativeUInt(@PR32.Z) - NativeUInt(@PR32) <> 9) then Halt(27);
  If (SizeOf(NR) <> 20) or
     (NativeUInt(@NR.Sets) - NativeUInt(@NR) <> 1) or
     (NativeUInt(@NR.Z) - NativeUInt(@NR) <> 19) then Halt(28);

  Holder := TSetHolder.Create;
  try
    If (NativeUInt(@Holder.S) - NativeUInt(@Holder.A) <> 1) or
       (NativeUInt(@Holder.Z) - NativeUInt(@Holder.S) <> SizeOf(TSet64)) then Halt(29);
  finally
    Holder.Free;
  end;

  If not CheckSetParameter([0, 64]) then Halt(30);
end.
