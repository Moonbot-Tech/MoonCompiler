program Fpc41554BitpackedRecordSize;

{$mode objfpc}

type
  TRec64A = bitpacked record
    Half1: 0..UInt64(1 shl 32) - 1;
    Half2: 0..UInt64(1 shl 32) - 1;
  end;

  TRec64B = bitpacked record
    LowBit: 0..UInt64(1 shl 1) - 1;
    HighBits: 0..UInt64(1 shl 63) - 1;
  end;

  TRec64C = bitpacked record
    LowBits: 0..UInt64(1 shl 16) - 1;
    HighBits: 0..UInt64(1 shl 48) - 1;
  end;

begin
  if (SizeOf(TRec64A) <> 8) or
     (SizeOf(TRec64B) <> 8) or
     (SizeOf(TRec64C) <> 8) then
    Halt(1);
end.
