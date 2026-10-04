program memory_order_shapes;

{ Memory which is certainly not the memory that is read or written: the
  optimizations the peephole optimizer of x86 does across a write to memory
  stay where the write cannot reach what they read.  Every routine is counted
  in the -O3 object by run_memory_order_gate.py; the program checks the
  values it computes. }

{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$Q-}{$R-}
{$MINENUMSIZE 4}

type
  TRec = record
    A, B, C, D: Int64;
  end;
  PRec = ^TRec;
  TPair = record
    Lo, Hi: Int64;
  end;
  PPair = ^TPair;
  TKind = (kFirst, kSecond, kThird, kFourth);
  TItem = class
  public
    Value: Int64;
    function Size: Int64; virtual;
  end;
  THolder = class
  public
    Tag: Int64;
    Written: Int64;
    Items: array[TKind] of TItem;
    procedure Write(Target: TItem; Kind: TKind);
    procedure WriteIfNotEmpty(Target: TItem; Kind: TKind);
  end;
  TPairCompare = reference to function(const Left, Right: TPair): Integer;
  TSorter = class
  public
    Compare: TPairCompare;
    function Less(const Left, Right: TPair): Integer;
  end;
  TReader = record
    P: PByte;
    Last: PByte;
    function NextByte: Byte; inline;
  end;
  PReader = ^TReader;

var
  Failures: Integer;
  Cell: Int64;
  G: TRec;
  GPair: TPair;
  Bytes: array[0..15] of Byte;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

function TItem.Size: Int64;
begin
  Result := Value;
end;

procedure THolder.Write(Target: TItem; Kind: TKind);
begin
  Inc(Written, Target.Value + Ord(Kind));
end;

{ the element of an array field is read for the call and for its table of
  virtual methods; the index is a parameter of 32 bits, moved to the register
  of the index in front of each of the two reads: the same value twice, the
  second read is the register of the first }
procedure THolder.WriteIfNotEmpty(Target: TItem; Kind: TKind);
begin
  if Items[Kind].Size > 0 then
    Write(Target, Kind);
end;

{ a function reference which is a field is called.  Where two records of 16
  bytes come in registers (Linux) the routine puts them into its frame; it
  takes the address of no cell of the frame, so no pointer looks there: the
  reference is read from the object once }
function TSorter.Less(const Left, Right: TPair): Integer;
begin
  Result := Compare(Left, Right);
end;

{ another field behind the same pointer is written: the read of the first
  one goes down into the multiplication }
function ShapeOtherField(R: PRec): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;
begin
  X := R^.A;
  R^.B := R^.B + 5;
  Y := X * 1000;
  Result := Y + R^.B;
end;

{ another variable is written by its name }
function ShapeOtherName: Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  X, Y: Int64;
begin
  X := Cell;
  G.B := G.B + 5;
  Y := X * 1000;
  Result := Y + G.B;
end;

{ one assignment of a record of 16 bytes: a load and a store of 16 bytes }
procedure ShapeCopyRecord(Target: PPair); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Target^ := GPair;
end;

function TReader.NextByte: Byte;
begin
  Result := P^;
  Inc(P);
end;

{ a byte is read through a pointer which is a field, the pointer is stepped,
  the byte goes to a wide variable: the read and its extension are one
  instruction in front of the step }
function ShapeReadAndStep(R: PReader): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Data: NativeInt;
begin
  Data := R^.NextByte;
  if Data <= 127 then
    Result := Data * 3
  else
    Result := Data - 256;
end;

{ a number of seven bits a byte, the lowest bits first: the same read in a
  loop, where the byte and the wide variable have registers of their own }
function ShapeReadNumber(R: PReader): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  Shift: Byte;
  Data: NativeInt;
begin
  Data := R^.NextByte;
  if Data <= 127 then
  begin
    Result := Data;
    exit;
  end;
  Result := 0;
  Shift := 0;
  repeat
    Result := Result or ((Data and $7f) shl Shift);
    Inc(Shift, 7);
    if Data <= 127 then
      break;
    Data := R^.NextByte;
  until False;
end;

var
  Holder: THolder;
  Sorter: TSorter;
  Reader: TReader;
  K: TKind;
  Pair, Other: TPair;
  I: Integer;

begin
  Holder := THolder.Create;
  Holder.Tag := 77;
  for K := Low(TKind) to High(TKind) do
  begin
    Holder.Items[K] := TItem.Create;
    Holder.Items[K].Value := Ord(K);
  end;
  Holder.WriteIfNotEmpty(Holder.Items[kSecond], kFirst);
  Check('the first is empty', Holder.Written, 0);
  Holder.WriteIfNotEmpty(Holder.Items[kSecond], kThird);
  Check('the third is written', Holder.Written, 1 + 2);

  Sorter := TSorter.Create;
  Sorter.Compare :=
    function(const Left, Right: TPair): Integer
    begin
      if Left.Lo + Left.Hi < Right.Lo + Right.Hi then
        Result := -1
      else
        Result := Ord(Left.Lo + Left.Hi > Right.Lo + Right.Hi);
    end;
  Pair.Lo := 1; Pair.Hi := 2;
  Other.Lo := 2; Other.Hi := 2;
  Check('less', Sorter.Less(Pair, Other), -1);
  Check('greater', Sorter.Less(Other, Pair), 1);

  G.A := 7; G.B := 1;
  Check('other field', ShapeOtherField(@G), 7006);
  Cell := 7; G.B := 1;
  Check('other name', ShapeOtherName, 7006);

  GPair.Lo := 11; GPair.Hi := 22;
  Pair.Lo := 0; Pair.Hi := 0;
  ShapeCopyRecord(@Pair);
  Check('copy of a record', Pair.Lo * 100 + Pair.Hi, 1122);

  for I := 0 to 15 do
    Bytes[I] := 120 + I * 3;
  Reader.P := @Bytes[0];
  Reader.Last := @Bytes[15];
  Check('byte 0', ShapeReadAndStep(@Reader), 120 * 3);
  Check('byte 1', ShapeReadAndStep(@Reader), 123 * 3);
  Check('byte 2', ShapeReadAndStep(@Reader), 126 * 3);
  Check('byte 3', ShapeReadAndStep(@Reader), 129 - 256);
  Check('stepped', Int64(Reader.P - PByte(@Bytes[0])), 4);
  Bytes[4] := $85; Bytes[5] := $83; Bytes[6] := $02; Bytes[7] := $7f;
  Check('a number of three bytes', ShapeReadNumber(@Reader), 5 + (3 shl 7) + (2 shl 14));
  Check('a number of one byte', ShapeReadNumber(@Reader), $7f);
  Check('stepped over the numbers', Int64(Reader.P - PByte(@Bytes[0])), 8);

  for K := Low(TKind) to High(TKind) do
    Holder.Items[K].Free;
  Holder.Free;
  Sorter.Free;
  if Failures = 0 then
    WriteLn('MEMORY_ORDER_SHAPES_PASS')
  else
  begin
    WriteLn('MEMORY_ORDER_SHAPES_FAIL ', Failures);
    Halt(1);
  end;
end.
