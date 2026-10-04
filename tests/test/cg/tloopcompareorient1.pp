{ %CPU=x86_64 }
{ %OPT=-O3 }
program tloopcompareorient1;

{ A compare of two memory operands inside a loop loads the one which does not
  depend on a variable the loop writes and keeps the loop-dependent one as the
  memory operand of cmp; nf_swapped mirrors the condition (nx86add).  Every
  relation, signed and unsigned, at 8, 16, 32 and 64 bits, with values on
  both sides of the sign bit.  The expected counts come from an independent
  model; the assembler shape is checked by
  qualification/optimizer-core/loop-regvar. }

{$mode delphi}
{$R-}{$Q-}

type
  PNode = ^TNode;
  TNode = record
    Key: Integer;
    UKey: Cardinal;
    B: Byte;
    SB: ShortInt;
    W: Word;
    SW: SmallInt;
    Q: Int64;
    UQ: UInt64;
    Next: PNode;
  end;

const
  Keys: array[0..7] of Integer = (10, 20, 30, 40, 50, 60, 70, 80);
  UKeys: array[0..7] of Cardinal = (1, 50, $7FFFFFFF, $80000000, $FFFFFFFF, 49, 51, 0);
  Bytes: array[0..7] of Byte = (0, 1, 127, 128, 200, 255, 100, 50);
  ShortInts: array[0..7] of ShortInt = (-128, -1, 0, 1, 50, 127, -50, 49);
  Words: array[0..7] of Word = (0, 1, $7FFF, $8000, $FFFF, 1000, 999, 1001);
  SmallInts: array[0..7] of SmallInt = (-32768, -1, 0, 1, 1000, 32767, -1000, 999);
  Int64s: array[0..7] of Int64 = (Low(Int64), -1, 0, 1, 1000000000000,
    High(Int64), -1000000000000, 999999999999);
  UInt64s: array[0..7] of UInt64 = (0, 1, $7FFFFFFFFFFFFFFF, UInt64($8000000000000000),
    UInt64($FFFFFFFFFFFFFFFF), 1000000000000, 999999999999, 1000000000001);

var
  Nodes: array[0..7] of TNode;
  Target: TNode;
  Head: PNode;


procedure BuildList;
var
  I: Integer;
begin
  for I := 0 to 7 do
  begin
    Nodes[I].Key := Keys[I];
    Nodes[I].UKey := UKeys[I];
    Nodes[I].B := Bytes[I];
    Nodes[I].SB := ShortInts[I];
    Nodes[I].W := Words[I];
    Nodes[I].SW := SmallInts[I];
    Nodes[I].Q := Int64s[I];
    Nodes[I].UQ := UInt64s[I];
    if I < 7 then
      Nodes[I].Next := @Nodes[I + 1]
    else
      Nodes[I].Next := nil;
  end;
  Head := @Nodes[0];
  Target.Key := 50;
  Target.UKey := 50;
  Target.B := 100;
  Target.SB := 1;
  Target.W := 1000;
  Target.SW := 1;
  Target.Q := 1;
  Target.UQ := UInt64($8000000000000000);
  Target.Next := nil;
end;


function CountSignedLT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key < Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountSignedLE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key <= Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountSignedGT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key > Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountSignedGE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key >= Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountUnsignedLT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.UKey < Target^.UKey then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountUnsignedLE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.UKey <= Target^.UKey then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountUnsignedGT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.UKey > Target^.UKey then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountUnsignedGE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.UKey >= Target^.UKey then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountEqual(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key = Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountNotEqual(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Key <> Target^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountByteGT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.B > Target^.B then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountShortIntLT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.SB < Target^.SB then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountWordGE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.W >= Target^.W then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountSmallIntLE(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.SW <= Target^.SW then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountInt64LT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.Q < Target^.Q then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


function CountUInt64GT(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Current^.UQ > Target^.UQ then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


{ The invariant operand is already on the left: nothing to swap. }
function CountInvariantLeft(Target: PNode): Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while Current <> nil do
  begin
    if Target^.Key < Current^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


{ Both operands depend on the loop: the source order is kept. }
function CountAscendingPairs: Integer; noinline;
var
  Current: PNode;
begin
  Result := 0;
  Current := Head;
  while (Current <> nil) and (Current^.Next <> nil) do
  begin
    if Current^.Key < Current^.Next^.Key then
      Inc(Result);
    Current := Current^.Next;
  end;
end;


{ The sorted-insert loop of the linked-list workload: the compare is part of
  the loop condition. }
function InsertPosition(Node: PNode): Integer; noinline;
var
  Current: PNode;
  Pos: Integer;
begin
  Pos := 0;
  Current := Head;
  while (Current <> nil) and (Current^.Key < Node^.Key) do
  begin
    Inc(Pos);
    Current := Current^.Next;
  end;
  Result := Pos;
end;


begin
  BuildList;
  if CountSignedLT(@Target) <> 4 then
    Halt(1);
  if CountSignedLE(@Target) <> 5 then
    Halt(2);
  if CountSignedGT(@Target) <> 3 then
    Halt(3);
  if CountSignedGE(@Target) <> 4 then
    Halt(4);
  if CountUnsignedLT(@Target) <> 3 then
    Halt(5);
  if CountUnsignedLE(@Target) <> 4 then
    Halt(6);
  if CountUnsignedGT(@Target) <> 4 then
    Halt(7);
  if CountUnsignedGE(@Target) <> 5 then
    Halt(8);
  if CountEqual(@Target) <> 1 then
    Halt(9);
  if CountNotEqual(@Target) <> 7 then
    Halt(10);
  if CountByteGT(@Target) <> 4 then
    Halt(11);
  if CountShortIntLT(@Target) <> 4 then
    Halt(12);
  if CountWordGE(@Target) <> 5 then
    Halt(13);
  if CountSmallIntLE(@Target) <> 5 then
    Halt(14);
  if CountInt64LT(@Target) <> 4 then
    Halt(15);
  if CountUInt64GT(@Target) <> 1 then
    Halt(16);
  if CountInvariantLeft(@Target) <> 3 then
    Halt(17);
  if CountAscendingPairs <> 7 then
    Halt(18);
  Target.Key := 45;
  if InsertPosition(@Target) <> 4 then
    Halt(19);
  Target.Key := 5;
  if InsertPosition(@Target) <> 0 then
    Halt(20);
  Target.Key := 85;
  if InsertPosition(@Target) <> 8 then
    Halt(21);
end.
