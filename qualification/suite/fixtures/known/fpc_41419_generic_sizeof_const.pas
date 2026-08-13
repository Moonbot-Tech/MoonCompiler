program Fpc41419GenericSizeofConst;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  generic TSizeInfo<T> = record
    const
      ByteSize = SizeOf(T);
      BitSizeIndirect = ByteSize * 8;
      BitSizeDirect = SizeOf(T) * 8;
  end;

  TUInt32Size = specialize TSizeInfo<UInt32>;

begin
  if (TUInt32Size.ByteSize <> 4) or
     (TUInt32Size.BitSizeIndirect <> 32) or
     (TUInt32Size.BitSizeDirect <> 32) then
    Halt(1);
end.
