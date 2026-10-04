program sub_memory_semantic;

{ A subtraction whose operands both lie in memory, the subtrahend behind more
  pointers than the minuend: the operands change their places for the
  evaluation, the address of the subtrahend is computed first.  The x86 code
  generator (tx86addnode.second_addordinal) loaded the subtrahend into a
  register of its own and left it to the peephole optimizer to fold the load
  back into the instruction; now the subtrahend is the memory operand of the
  instruction and the register takes the minuend.

  The forms: fields of a record of the routine around and of its object in a
  nested routine, parameters of the routine around which are passed by
  reference, two pointers in front of the subtrahend, an element of a dynamic
  array, operands of 8, 16, 32 and 64 bits, signed and unsigned, a difference
  which goes below zero, the operation with the overflow check.

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TPoint = record
    X, Y: LongInt;
  end;

  TEvent = record
    What: Word;
    Where: TPoint;
  end;

  TStream = record
    NextIn: PByte;
    AvailIn: Cardinal;
    TotalIn: UInt64;
  end;

  PInner = ^TInner;
  TInner = record
    Pad: Int64;
    B8: ShortInt;
    U8: Byte;
    B16: SmallInt;
    U16: Word;
    B32: LongInt;
    U32: Cardinal;
    B64: Int64;
    U64: UInt64;
  end;

  POuter = ^TOuter;
  TOuter = record
    Pad: array[0..2] of Int64;
    Inner: PInner;
  end;

  TPlain = record
    B8: ShortInt;
    U8: Byte;
    B16: SmallInt;
    U16: Word;
    B32: LongInt;
    U32: Cardinal;
    B64: Int64;
    U64: UInt64;
  end;
  PPlain = ^TPlain;

  TCell = record
    Key: Int64;
    Value: Int64;
  end;

  TView = class
    Origin: TPoint;
    Cells: array of TCell;
    Total: Int64;
    function Track(const AEvent: TEvent): Int64;
    function Rest(Index: Integer): Int64;
  end;

var
  Fails: Integer = 0;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

function TView.Track(const AEvent: TEvent): Int64;
var
  E: TEvent;
  Mouse: TPoint;

  procedure TrackMouse;
  begin
    Mouse.X := E.Where.X - Origin.X;
    Mouse.Y := E.Where.Y - Origin.Y;
  end;

begin
  E := AEvent;
  TrackMouse;
  Result := Int64(Mouse.X) * 1000 + Mouse.Y;
end;

function TView.Rest(Index: Integer): Int64; noinline;
begin
  Result := Total - Cells[Index].Value;
end;

function Blocks(var Z: TStream; Step: Integer): Int64; noinline;
var
  P: PByte;

  procedure Done;
  begin
    Inc(Z.TotalIn, NativeUInt(P) - NativeUInt(Z.NextIn));
    Z.NextIn := P;
  end;

begin
  P := Z.NextIn;
  Inc(P, Step);
  Done;
  Result := Z.TotalIn;
end;

function Sub8(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := ShortInt(A^.B8 - B^.Inner^.B8);
end;

function SubU8(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := Byte(A^.U8 - B^.Inner^.U8);
end;

function Sub16(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := SmallInt(A^.B16 - B^.Inner^.B16);
end;

function SubU16(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := Word(A^.U16 - B^.Inner^.U16);
end;

function Sub32(A: PPlain; B: POuter): Int64; noinline;
var
  R: LongInt;
begin
  R := A^.B32 - B^.Inner^.B32;
  Result := R;
end;

function SubU32(A: PPlain; B: POuter): Int64; noinline;
var
  R: Cardinal;
begin
  R := A^.U32 - B^.Inner^.U32;
  Result := R;
end;

function Sub64(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := A^.B64 - B^.Inner^.B64;
end;

function SubU64(A: PPlain; B: POuter): UInt64; noinline;
begin
  Result := A^.U64 - B^.Inner^.U64;
end;

function SubWide(A: PPlain; B: POuter): Int64; noinline;
begin
  { 32-bit operands, the difference counted in 64 bits }
  Result := Int64(A^.B32) - B^.Inner^.B32;
end;

function SubBelow(A: PPlain; B: POuter): Boolean; noinline;
begin
  Result := A^.B64 - B^.Inner^.B64 < 0;
end;

function SubStored(A: PPlain; B: POuter): Int64; noinline;
begin
  { the difference goes back into the memory the minuend was read from }
  A^.B64 := A^.B64 - B^.Inner^.B64;
  Result := A^.B64;
end;

function SubSubtrahendStored(A: PPlain; B: POuter): Int64; noinline;
begin
  { and into the memory of the subtrahend }
  B^.Inner^.B64 := A^.B64 - B^.Inner^.B64;
  Result := B^.Inner^.B64;
end;

function SubSame(B: POuter): Int64; noinline;
begin
  { both operands behind the same pointers }
  Result := B^.Inner^.B64 - B^.Inner^.Pad;
end;

{$Q+}
function SubChecked(A: PPlain; B: POuter): Int64; noinline;
begin
  Result := A^.B64 - B^.Inner^.B64;
end;

function SubChecked32(A: PPlain; B: POuter): LongInt; noinline;
begin
  Result := A^.B32 - B^.Inner^.B32;
end;
{$Q-}

function Raises(A: PPlain; B: POuter; Wide: Boolean): Integer;
begin
  Result := 0;
  try
    if Wide then
      SubChecked(A, B)
    else
      SubChecked32(A, B);
  except
    on EIntOverflow do
      Result := 1;
  end;
end;

var
  V: TView;
  Ev: TEvent;
  Z: TStream;
  Data: array[0..63] of Byte;
  Plain: TPlain;
  Inner: TInner;
  Outer: TOuter;
begin
  V := TView.Create;
  V.Origin.X := 10;
  V.Origin.Y := 27;
  Ev.What := 1;
  Ev.Where.X := 17;
  Ev.Where.Y := 4;
  Check(V.Track(Ev), 7 * 1000 - 23, 'fields of the record around and of the object');
  SetLength(V.Cells, 5);
  V.Cells[3].Key := 1;
  V.Cells[3].Value := 1000000000000;
  V.Total := 7;
  Check(V.Rest(3), 7 - 1000000000000, 'a field and an element of a dynamic array');

  Z.NextIn := @Data[8];
  Z.AvailIn := 0;
  Z.TotalIn := 100;
  Check(Blocks(Z, 5), 105, 'pointers of a parameter passed by reference, forward');
  Check(Blocks(Z, -3), 102, 'pointers of a parameter passed by reference, back');

  Outer.Inner := @Inner;
  Plain.B8 := -100;  Inner.B8 := 100;
  Plain.U8 := 3;     Inner.U8 := 250;
  Plain.B16 := -30000; Inner.B16 := 30000;
  Plain.U16 := 5;    Inner.U16 := 65000;
  Plain.B32 := -2000000000; Inner.B32 := 2000000000;
  Plain.U32 := 7;    Inner.U32 := 4000000000;
  Plain.B64 := -9000000000000000000; Inner.B64 := 5;
  Plain.U64 := 1;    Inner.U64 := 3;
  Inner.Pad := 11;
  Check(Sub8(@Plain, @Outer), 56, 'signed 8 bits');
  Check(SubU8(@Plain, @Outer), 9, 'unsigned 8 bits');
  Check(Sub16(@Plain, @Outer), 5536, 'signed 16 bits');
  Check(SubU16(@Plain, @Outer), 541, 'unsigned 16 bits');
  Check(Sub32(@Plain, @Outer), 294967296, 'signed 32 bits');
  Check(SubU32(@Plain, @Outer), 294967303, 'unsigned 32 bits');
  Check(Sub64(@Plain, @Outer), -9000000000000000005, 'signed 64 bits');
  Check(Int64(SubU64(@Plain, @Outer)), -2, 'unsigned 64 bits');
  Check(SubWide(@Plain, @Outer), -4000000000, '32-bit operands, 64-bit difference');
  Check(Ord(SubBelow(@Plain, @Outer)), 1, 'the difference is below zero');
  Check(SubSame(@Outer), -6, 'both operands behind the same pointers');
  Check(Raises(@Plain, @Outer, True), 0, 'the checked subtraction fits');
  Check(Raises(@Plain, @Outer, False), 1, 'the checked 32-bit subtraction overflows');
  Inner.B64 := 1000000000000000000;
  Check(Raises(@Plain, @Outer, True), 1, 'the checked subtraction overflows');
  Inner.B64 := 5;
  Check(SubStored(@Plain, @Outer), -9000000000000000005, 'the difference is stored into the minuend');
  Check(Plain.B64, -9000000000000000005, 'the minuend holds the difference');
  Check(SubSubtrahendStored(@Plain, @Outer), -9000000000000000010, 'the difference is stored into the subtrahend');
  Check(Inner.B64, -9000000000000000010, 'the subtrahend holds the difference');

  if Fails = 0 then
    WriteLn('SUB_MEMORY_PASS')
  else
  begin
    WriteLn('SUB_MEMORY_FAIL ', Fails);
    Halt(1);
  end;
end.
