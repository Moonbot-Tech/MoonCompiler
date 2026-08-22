{ %OPT=-O3 }
program tarraypointerindexoffset1;

{$mode delphi}

type
  TByteArray = array[0 .. 255] of Byte;
  PByteArray = ^TByteArray;
  TWordArray = array[0 .. 255] of Word;
  PWordArray = ^TWordArray;

function ByteAddress(P: Pointer): Pointer; inline;
begin
  Result := @PByteArray(P)[PByte(P + 1)^ + 2];
end;

function ByteAddressConstLeft(P: Pointer): Pointer; inline;
begin
  Result := @PByteArray(P)[2 + PByte(P + 1)^];
end;

function ByteAddressSubtract(P: Pointer): Pointer; inline;
begin
  Result := @PByteArray(P)[PByte(P + 1)^ - (-2)];
end;

function ByteAddressFromOffsetBase(P: Pointer): Pointer; inline;
begin
  Result := @PByteArray(P + 3)[PByte(P + 1)^ + 2];
end;

function WordAddress(P: Pointer): Pointer; inline;
begin
  Result := @PWordArray(P)[PByte(P + 1)^ + 2];
end;

{$push}{$Q-}
function CardinalAddress(Base: PtrUInt; Index: Cardinal): PtrUInt; noinline;
begin
  Inc(Index, 2);
  Result := Base + Index;
end;
{$pop}

function UInt64Address(Base: PtrUInt; Index: UInt64): PtrUInt; noinline;
begin
  Inc(Index, 2);
  Result := Base + Index;
end;

procedure CheckOffset(P, Actual: Pointer; Expected: PtrUInt; Code: Byte);
begin
  if PtrUInt(Actual) - PtrUInt(P) <> Expected then
    Halt(Code);
end;

var
  Buffer: array[0 .. 511] of Byte;
  I: Integer;
begin
  for I := 0 to 200 do
  begin
    Buffer[1] := I;
    CheckOffset(@Buffer, ByteAddress(@Buffer), PtrUInt(I + 2), 1);
    CheckOffset(@Buffer, ByteAddressConstLeft(@Buffer), PtrUInt(I + 2), 2);
    CheckOffset(@Buffer, ByteAddressSubtract(@Buffer), PtrUInt(I + 2), 3);
    CheckOffset(@Buffer, ByteAddressFromOffsetBase(@Buffer), PtrUInt(I + 5), 4);
    CheckOffset(@Buffer, WordAddress(@Buffer), PtrUInt((I + 2) * 2), 5);
  end;
  CheckOffset(@Buffer,
    Pointer(CardinalAddress(PtrUInt(@Buffer), High(Cardinal))), 1, 6);
  CheckOffset(@Buffer,
    Pointer(UInt64Address(PtrUInt(@Buffer), 40)), 42, 7);
end.
