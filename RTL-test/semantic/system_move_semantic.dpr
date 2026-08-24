program system_move_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm
  {$ifdef UNIX},cthreads{$endif UNIX};
  {$else FPC}
  System.SysUtils;
  {$endif FPC}

const
  BufferSize = 2 * 1024 * 1024 + 4096;
  GuardSize = 64;
  VeryLargeSize = 32 * 1024 * 1024 + 257;

type
  TBuffer = array[0..BufferSize - 1] of Byte;

var
  Actual, Expected, Scratch: TBuffer;

procedure Fail(const MessageText: ShortString);
begin
  WriteLn('FAIL: ', MessageText);
  Halt(1);
end;

procedure InitializeBuffers(Limit: NativeInt);
var
  I: NativeInt;
  Value: Byte;
begin
  for I := 0 to Limit - 1 do
  begin
    Value := Byte((I * 37 + I shr 3 + 11) and $ff);
    Actual[I] := Value;
    Expected[I] := Value;
  end;
end;

procedure ReferenceMove(SourceOffset, DestOffset, Count: NativeInt);
var
  I: NativeInt;
begin
  If Count <= 0 then
    Exit;
  for I := 0 to Count - 1 do
    Scratch[I] := Expected[SourceOffset + I];
  for I := 0 to Count - 1 do
    Expected[DestOffset + I] := Scratch[I];
end;

procedure CheckCase(SourceOffset, DestOffset, Count: NativeInt);
var
  I, CheckEnd: NativeInt;
begin
  CheckEnd := SourceOffset;
  If DestOffset > CheckEnd then
    CheckEnd := DestOffset;
  If Count > 0 then
    Inc(CheckEnd, Count);
  Inc(CheckEnd, GuardSize);
  If CheckEnd > BufferSize then
    CheckEnd := BufferSize;
  InitializeBuffers(CheckEnd);
  ReferenceMove(SourceOffset, DestOffset, Count);
  Move(Actual[SourceOffset], Actual[DestOffset], Count);
  for I := 0 to CheckEnd - 1 do
    If Actual[I] <> Expected[I] then
    begin
      WriteLn('FAIL: source=', SourceOffset, ' dest=', DestOffset,
        ' count=', Count, ' byte=', I, ' actual=', Actual[I],
        ' expected=', Expected[I]);
      Halt(1);
    end;
end;

procedure CheckSmallAndAlignmentMatrix;
var
  Count, SourceAlignment, DestAlignment: NativeInt;
begin
  CheckCase(64, 512, -1);
  for Count := 0 to 96 do
    for SourceAlignment := 0 to 31 do
      for DestAlignment := 0 to 31 do
        CheckCase(64 + SourceAlignment, 512 + DestAlignment, Count);
end;

procedure CheckOverlapMatrix;
var
  Count, Distance: NativeInt;
begin
  for Count := 0 to 256 do
    for Distance := 0 to 64 do
    begin
      CheckCase(512, 512 + Distance, Count);
      CheckCase(512 + Distance, 512, Count);
    end;
end;

procedure CheckLargeBoundaries;
const
  Counts: array[0..19] of NativeInt = (
    63, 64, 65, 79, 80, 95, 96, 97,
    127, 128, 129, 191, 192, 193,
    511, 512, 513, 1535, 1536, 1537);
  BiggerCounts: array[0..17] of NativeInt = (
    2047, 2048, 2049, 4095, 4096, 4097,
    65535, 65536, 131071, 131072,
    262143, 262144, 262145,
    524287, 524288, 524289,
    1048575, 1048576);
  Alignments: array[0..5] of NativeInt = (0, 1, 15, 31, 32, 63);
  OverlapCounts: array[0..10] of NativeInt = (
    127, 128, 129, 255, 256, 257, 4095, 4096, 4097,
    262144, 1048576);
  OverlapDistances: array[0..7] of NativeInt = (1, 15, 16, 31, 32, 63, 64, 127);
var
  I, J, Count: NativeInt;
begin
  for I := Low(Counts) to High(Counts) do
  begin
    Count := Counts[I];
    CheckCase(65, 8192, Count);
    CheckCase(8192, 65, Count);
    CheckCase(1024, 1025, Count);
    CheckCase(1025, 1024, Count);
  end;
  for I := Low(BiggerCounts) to High(BiggerCounts) do
  begin
    Count := BiggerCounts[I];
    for J := Low(Alignments) to High(Alignments) do
    begin
      CheckCase(64 + Alignments[J], 1049000 + Alignments[High(Alignments) - J], Count);
      CheckCase(1049000 + Alignments[High(Alignments) - J], 64 + Alignments[J], Count);
    end;
  end;
  for I := Low(OverlapCounts) to High(OverlapCounts) do
  begin
    Count := OverlapCounts[I];
    for J := Low(OverlapDistances) to High(OverlapDistances) do
    begin
      CheckCase(1024, 1024 + OverlapDistances[J], Count);
      CheckCase(1024 + OverlapDistances[J], 1024, Count);
    end;
  end;
end;

function OffsetPointer(Base: PByte; Offset: NativeInt): PByte; inline;
begin
  Result := PByte(PtrInt(Base) + Offset);
end;

function LargePattern(Index: NativeInt; Salt: Byte): Byte; inline;
begin
  Result := Byte((NativeUInt(Index) * 37 + (NativeUInt(Index) shr 3) + Salt) and $ff);
end;

procedure CheckVeryLargeNonOverlap;
var
  SourceAllocation, DestAllocation: Pointer;
  SourcePointer, DestPointer: PByte;
  I: NativeInt;
begin
  GetMem(SourceAllocation, VeryLargeSize + GuardSize * 2 + 63);
  GetMem(DestAllocation, VeryLargeSize + GuardSize * 2 + 63);
  try
    SourcePointer := PByte((PtrUInt(SourceAllocation) + GuardSize + 63) and not PtrUInt(63));
    DestPointer := PByte((PtrUInt(DestAllocation) + GuardSize + 63) and not PtrUInt(63));
    for I := -GuardSize to VeryLargeSize + GuardSize - 1 do
    begin
      OffsetPointer(SourcePointer, I)^ := LargePattern(I, 11);
      OffsetPointer(DestPointer, I)^ := LargePattern(I, 173);
    end;
    Move(SourcePointer^, DestPointer^, VeryLargeSize);
    for I := 0 to VeryLargeSize - 1 do
      If (OffsetPointer(SourcePointer, I)^ <> LargePattern(I, 11)) or
        (OffsetPointer(DestPointer, I)^ <> LargePattern(I, 11)) then
        Fail('very large non-overlap payload differs');
    for I := -GuardSize to -1 do
      If (OffsetPointer(SourcePointer, I)^ <> LargePattern(I, 11)) or
        (OffsetPointer(DestPointer, I)^ <> LargePattern(I, 173)) then
        Fail('very large leading guard differs');
    for I := VeryLargeSize to VeryLargeSize + GuardSize - 1 do
      If (OffsetPointer(SourcePointer, I)^ <> LargePattern(I, 11)) or
        (OffsetPointer(DestPointer, I)^ <> LargePattern(I, 173)) then
        Fail('very large trailing guard differs');
  finally
    FreeMem(DestAllocation);
    FreeMem(SourceAllocation);
  end;
end;

begin
  CheckSmallAndAlignmentMatrix;
  CheckOverlapMatrix;
  CheckLargeBoundaries;
  CheckVeryLargeNonOverlap;
  WriteLn('SYSTEM_MOVE_SEMANTIC_OK');
end.
