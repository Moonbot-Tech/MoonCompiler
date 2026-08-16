program system_move_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm;
  {$else FPC}
  System.SysUtils;
  {$endif FPC}

const
  BufferSize = 262400;
  GuardSize = 64;

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
      Fail('Move result or guard bytes differ');
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
  BiggerCounts: array[0..9] of NativeInt = (
    2047, 2048, 2049, 4095, 4096, 4097,
    65535, 65536, 131071, 131072);
var
  I, Count: NativeInt;
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
    CheckCase(65, 131200, Count);
    CheckCase(131200, 65, Count);
    CheckCase(1024, 1025, Count);
    CheckCase(1025, 1024, Count);
  end;
end;

begin
  CheckSmallAndAlignmentMatrix;
  CheckOverlapMatrix;
  CheckLargeBoundaries;
  WriteLn('SYSTEM_MOVE_SEMANTIC_OK');
end.
