program inline_var_element_actual;

{ An element of a static array as the actual of a var/out/constref parameter
  of an inlined routine.  The inliner substitutes the element expression as it
  stands when nothing in the body can move its address (frame or static
  array, constant or register-variable index) and takes the address into a
  temp in front of the body otherwise.  Every inlined routine here has a twin
  that is really called; both must leave the same memory behind - above all
  where the body changes the index before it writes the element: through a
  second var actual, through the function result, through a pointer, through
  a global and from a nested routine. }

{$mode delphiunicode}
{$Q-}{$R-}

type
  TSlots = array[0..15] of Integer;
  TNames = array[0..7] of AnsiString;
  TPointers = array[0..31] of Pointer;
  TBox = record
    Tag: Integer;
    Items: array[0..7] of Int64;
  end;
  TWide = record
    A, B, C: Integer;
  end;
  TWides = array[0..5] of TWide;

var
  RtZero: UInt64 = 0;
  GSlots, GSlotsRef: TSlots;
  GIndex, GIndexRef: Integer;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor RtZero);
end;

procedure Check(Condition: Boolean; const Name: AnsiString);
begin
  If not Condition then
  begin
    Writeln('FAIL ', Name);
    Halt(1);
  end;
end;

function SameSlots(const A, B: TSlots): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := Low(A) to High(A) do
    If A[I] <> B[I] then
      Result := False;
end;

{ ---- the plain case: the element is written after a call made by the body ---- }
function Source(V: Integer): Integer;
begin
  Result := Integer(OpaqueI(V)) * 3 + 1;
end;

procedure PutInl(out Slot: Integer; V: Integer); inline;
begin
  Slot := Source(V);
end;

procedure PutRef(out Slot: Integer; V: Integer);
begin
  Slot := Source(V);
end;

{ ---- the body moves the index through a second var actual ---- }
procedure PutNextInl(var Slot: Integer; var Index: Integer); inline;
begin
  Inc(Index);
  Slot := Slot + Index * 10;
end;

procedure PutNextRef(var Slot: Integer; var Index: Integer);
begin
  Inc(Index);
  Slot := Slot + Index * 10;
end;

{ ---- the body writes the function result, which the caller assigns to the index ---- }
function BumpInl(var Slot: Integer): Integer; inline;
begin
  Result := 7;
  Slot := Slot + Result;
  Result := Result + 2;
  Slot := Slot * 2;
end;

function BumpRef(var Slot: Integer): Integer;
begin
  Result := 7;
  Slot := Slot + Result;
  Result := Result + 2;
  Slot := Slot * 2;
end;

{ ---- the body moves the index through a pointer ---- }
procedure ViaPointerInl(var Slot: Integer; Index: PInteger); inline;
begin
  Index^ := Index^ + 2;
  Slot := 55 + Index^;
end;

procedure ViaPointerRef(var Slot: Integer; Index: PInteger);
begin
  Index^ := Index^ + 2;
  Slot := 55 + Index^;
end;

{ ---- the index is a global the body changes ---- }
procedure ViaGlobalInl(var Slot: Integer); inline;
begin
  Inc(GIndex);
  Slot := 900 + GIndex;
end;

procedure ViaGlobalRef(var Slot: Integer);
begin
  Inc(GIndexRef);
  Slot := 900 + GIndexRef;
end;

{ ---- read-only by reference, read more than once ---- }
function TwiceInl(constref Item: Int64; Salt: Integer): Int64; inline;
begin
  Result := Item + Source(Salt);
  Result := Result + Item;
end;

function TwiceRef(constref Item: Int64; Salt: Integer): Int64;
begin
  Result := Item + Source(Salt);
  Result := Result + Item;
end;

{ ---- a managed element ---- }
procedure NameInl(out S: AnsiString; N: Integer); inline;
begin
  S := 'n' + AnsiChar(Ord('0') + N);
end;

procedure NameRef(out S: AnsiString; N: Integer);
begin
  S := 'n' + AnsiChar(Ord('0') + N);
end;

{ ---- an element the addressing mode cannot scale ---- }
procedure WideInl(var W: TWide; V: Integer); inline;
begin
  W.A := Source(V);
  W.B := W.A + 1;
  W.C := W.B + W.A;
end;

procedure WideRef(var W: TWide; V: Integer);
begin
  W.A := Source(V);
  W.B := W.A + 1;
  W.C := W.B + W.A;
end;

procedure TestPlain;
var
  Inl, Ref: TSlots;
  J: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  for J := 0 to 15 do
  begin
    PutInl(Inl[J], J + 5);
    PutRef(Ref[J], J + 5);
  end;
  Check(SameSlots(Inl, Ref), 'plain');
  for J := 15 downto 0 do
  begin
    PutInl(GSlots[J], J * 7);
    PutRef(GSlotsRef[J], J * 7);
  end;
  Check(SameSlots(GSlots, GSlotsRef), 'plain-global-array');
  PutInl(Inl[3], 1000);
  PutRef(Ref[3], 1000);
  Check(SameSlots(Inl, Ref), 'plain-constant-index');
end;

procedure TestIndexAsSecondActual;
var
  Inl, Ref: TSlots;
  J, K, Round: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  J := Integer(OpaqueI(2));
  K := J;
  for Round := 1 to 5 do
  begin
    PutNextInl(Inl[J], J);
    PutNextRef(Ref[K], K);
  end;
  Check((J = K) and (J = 7), 'second-actual-index');
  Check(SameSlots(Inl, Ref) and (Inl[2] = 30) and (Inl[3] = 40), 'second-actual');
end;

procedure TestIndexAsResult;
var
  Inl, Ref: TSlots;
  J, K: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  J := Integer(OpaqueI(4));
  K := J;
  Inl[4] := 1; Ref[4] := 1;
  J := BumpInl(Inl[J]);
  K := BumpRef(Ref[K]);
  Check((J = K) and (J = 9), 'result-index');
  Check(SameSlots(Inl, Ref) and (Inl[4] = 16) and (Inl[7] = 0) and (Inl[9] = 0), 'result');
end;

procedure TestIndexThroughPointer;
var
  Inl, Ref: TSlots;
  J, K: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  J := Integer(OpaqueI(1));
  K := J;
  ViaPointerInl(Inl[J], @J);
  ViaPointerRef(Ref[K], @K);
  Check((J = K) and (J = 3), 'pointer-index');
  Check(SameSlots(Inl, Ref) and (Inl[1] = 58) and (Inl[3] = 0), 'pointer');
end;

procedure TestIndexGlobal;
begin
  FillChar(GSlots, SizeOf(GSlots), 0);
  FillChar(GSlotsRef, SizeOf(GSlotsRef), 0);
  GIndex := Integer(OpaqueI(5));
  GIndexRef := GIndex;
  ViaGlobalInl(GSlots[GIndex]);
  ViaGlobalRef(GSlotsRef[GIndexRef]);
  Check((GIndex = GIndexRef) and (GIndex = 6), 'global-index');
  Check(SameSlots(GSlots, GSlotsRef) and (GSlots[5] = 906) and (GSlots[6] = 0), 'global');
end;

procedure TestIndexFromNested;
var
  Inl, Ref: TSlots;
  J, K: Integer;

  procedure StepInl(var Slot: Integer); inline;
  begin
    Inc(J);
    Slot := 100 + J;
  end;

  procedure StepRef(var Slot: Integer);
  begin
    Inc(K);
    Slot := 100 + K;
  end;

begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  J := Integer(OpaqueI(1));
  K := J;
  StepInl(Inl[J]);
  StepRef(Ref[K]);
  Check((J = K) and (J = 2), 'nested-index');
  Check(SameSlots(Inl, Ref) and (Inl[1] = 102) and (Inl[2] = 0), 'nested');
end;

procedure TestRecordField;
var
  Box: TBox;
  J: Integer;
  Inl, Ref: Int64;
begin
  Box.Tag := 1;
  for J := 0 to 7 do
    Box.Items[J] := OpaqueI(J * 11 + 3);
  Inl := 0;
  Ref := 0;
  for J := 0 to 7 do
  begin
    Inl := Inl + TwiceInl(Box.Items[J], J);
    Ref := Ref + TwiceRef(Box.Items[J], J);
  end;
  Check((Inl = Ref) and (Inl <> 0), 'constref-record-field');
end;

procedure TestManaged;
var
  Inl, Ref: TNames;
  J: Integer;
begin
  for J := 0 to 7 do
  begin
    Inl[J] := 'old';
    Ref[J] := 'old';
  end;
  for J := 0 to 7 do
  begin
    NameInl(Inl[J], J);
    NameRef(Ref[J], J);
  end;
  for J := 0 to 7 do
    Check((Inl[J] = Ref[J]) and (Length(Inl[J]) = 2), 'managed');
end;

procedure TestWide;
var
  Inl, Ref: TWides;
  J: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  for J := 0 to 5 do
  begin
    WideInl(Inl[J], J);
    WideRef(Ref[J], J);
  end;
  for J := 0 to 5 do
    Check((Inl[J].A = Ref[J].A) and (Inl[J].B = Ref[J].B) and (Inl[J].C = Ref[J].C) and
      (Inl[J].C = 2 * Source(J) + 1), 'wide');
end;

{$R+}
procedure TestRangeChecked;
var
  Inl, Ref: TSlots;
  J: Integer;
begin
  FillChar(Inl, SizeOf(Inl), 0);
  FillChar(Ref, SizeOf(Ref), 0);
  for J := 0 to 15 do
  begin
    PutInl(Inl[J], J);
    PutRef(Ref[J], J);
  end;
  Check(SameSlots(Inl, Ref), 'range-checked');
end;
{$R-}

{ ---- the caller itself is inlined: its index is a temp of the outer routine ---- }
function FillInl(var Slots: TSlots; Base: Integer): Integer; inline;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to 15 do
  begin
    PutInl(Slots[J], Base + J);
    Result := Result + Slots[J];
  end;
end;

procedure TestNestedInline;
var
  Inl, Ref: TSlots;
  J, Sum, RefSum: Integer;
begin
  Sum := FillInl(Inl, 40);
  RefSum := 0;
  for J := 0 to 15 do
  begin
    PutRef(Ref[J], 40 + J);
    RefSum := RefSum + Ref[J];
  end;
  Check(SameSlots(Inl, Ref) and (Sum = RefSum), 'caller-inlined');
end;

{ ---- the allocation ring this was found on: the accumulator must survive both loops ---- }
function Ring(Size, Rounds: Integer): UInt64;
var
  I, J: Integer;
  Pointers: TPointers;
  P: PByte;
begin
  Result := 0;
  for I := 1 to Rounds do
  begin
    for J := 0 to High(Pointers) do
    begin
      GetMem(Pointers[J], Size);
      P := Pointers[J];
      P[0] := Byte(I + J);
    end;
    for J := High(Pointers) downto 0 do
    begin
      P := Pointers[J];
      Result := Result + P[0];
      FreeMem(Pointers[J]);
    end;
  end;
end;

procedure TestRing;
var
  I, J: Integer;
  Want: UInt64;
begin
  Want := 0;
  for I := 1 to 9 do
    for J := 0 to 31 do
      Want := Want + Byte(I + J);
  Check(Ring(Integer(OpaqueI(48)), 9) = Want, 'ring');
end;

begin
  TestPlain;
  TestIndexAsSecondActual;
  TestIndexAsResult;
  TestIndexThroughPointer;
  TestIndexGlobal;
  TestIndexFromNested;
  TestRecordField;
  TestManaged;
  TestWide;
  TestRangeChecked;
  TestNestedInline;
  TestRing;
  Writeln('INLINE_VAR_ELEMENT_ACTUAL_OK');
end.
