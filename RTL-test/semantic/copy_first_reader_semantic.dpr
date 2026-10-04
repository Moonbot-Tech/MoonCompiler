program copy_first_reader_semantic;

{ The instruction right behind a copy of a register.  The x86 peephole gives
  the source of "mov %src,%copy" to the later readers of the copy and drops
  the move once the last reader it rewrote no longer needs the copy.  At -O3
  its search runs on across branches that meet again, and it starts behind
  the instruction right after the move: that one was never asked whether it
  reads the copy.  Two ways leave it a reader.

  A comparison of the copy with its source is not rewritten (it would turn
  into "cmp %src,%src"):

    Y := K;                    movq  %rdx,%rcx        dropped
    if Y < K then ...     ->   cmpq  %rcx,%rdx        %rcx holds anything
    ...                        ...
    Result := Y * 1000;        imulq $1000,%rdx,%rcx  rewritten to the source

  and the branch was taken by whatever %rcx held: every relation, 64 and 32
  bits, signed and unsigned, a copy made by an inlined routine, a copy
  compared and then stored.

  A reader that became the next instruction in the same pass, when a move
  between them went, is rewritten only on the next pass - after the move it
  needed was dropped.  mORMot compares values by RTTI so
  (_BC_Ord, _BC_Float: RTTI_ORD_COMPARE[Info^.RttiOrd](A, B, Info, ...)): the
  inlined method copies Info for Self, and the first byte of the type was
  read through a register nobody loaded.

  -O3 and -O4 on Win64 and Linux; -O1 and -O2 look one instruction ahead and
  never reach the rewritten reader.  The values are those of Delphi 12.2 and
  of -O1. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TRec = record
    A, B, C, D: Int64;
  end;

  TCompare = function(A, B: Pointer; Info: Pointer; out Compared: Integer): PtrInt;

  PInfo = ^TInfo;
  TInfo = object
    Kind: Byte;
    RawName: ShortString;
    function Ord: Byte; inline;
  end;

var
  Fails: Integer = 0;
  G: TRec;
  GY: Int64;
  S: SmallInt;
  Table: array[0..3] of TCompare;
  InfoBytes: array[0..31] of Byte;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

{ the routine of the generator (fz_mixed_44, F182) }
function Less(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Y * 1000 + X * 1000000 + K;
end;

function LessOrEqual(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y <= K then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Y * 1000 + X * 1000000 + K;
end;

function Greater(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if K > Y then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Y * 1000 + X * 1000000 + K;
end;

function Differs(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y <> K then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Y * 1000 + X * 1000000 + K;
end;

function LessUnsigned(P: PSmallInt; K: UInt64): Int64; noinline;
var
  X: Int64;
  Y: UInt64;
  N: Integer;
begin
  N := P^;
  Y := UInt64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Int64(Y) * 1000 + X * 1000000 + Int64(K);
end;

function Equal(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y = K then
    X := X + 10
  else
    X := X - 10;
  Result := Int64(N) + Y * 1000 + X * 1000000 + K;
end;

{ 32 bits: the reader behind the branch is 32-bit arithmetic (a widening
  there, Int64(Y), joins the first move and keeps it) }
function Less32(P: PSmallInt; K: Integer): Integer; noinline;
var
  X, Y, N: Integer;
begin
  N := P^;
  Y := N;
  X := G.A;
  N := P^;
  Y := K;
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  Result := N + Y * 1000 + X * 100000;
end;

function GreaterOrEqual32(P: PSmallInt; K: Integer): Integer; noinline;
var
  X, Y, N: Integer;
begin
  N := P^;
  Y := N;
  X := G.A;
  N := P^;
  Y := K;
  if Y >= K then
    X := X + 10
  else
    X := X - 10;
  Result := N + Y * 1000 + X * 100000;
end;

function LessUnsigned32(P: PSmallInt; K: Cardinal): Cardinal; noinline;
var
  X, Y: Cardinal;
  N: Integer;
begin
  N := P^;
  Y := Cardinal(N);
  X := Cardinal(G.A);
  N := P^;
  Y := K;
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  Result := Cardinal(N) + Y * 1000 + X * 100000;
end;

{ the copy made by an inlined routine }
function Same(V: Int64): Int64; inline;
begin
  Result := V;
end;

function LessInlined(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := N;
  X := G.D;
  N := P^;
  Y := Same(K);
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  Result := N + Y * 1000 + X * 1000000;
end;

{ the copy is stored behind the comparison: the move of the store is the
  reader which drops the first move }
function LessThenStore(P: PSmallInt; K: Int64): Int64; noinline;
var
  X, Y: Int64;
  N: Integer;
begin
  N := P^;
  Y := Int64(N);
  X := G.D;
  N := P^;
  Y := K;
  if Y < K then
    X := X + 10
  else
    X := X - 10;
  X := X + Y;
  GY := Y;
  Result := X + N;
end;

{ mORMot _BC_Ord: the type data behind a pointer parameter, read by an inlined
  method of an object, picks a routine from a table }
function TypeData(TypeInfo: Pointer): PByte; inline;
begin
  Result := @PByteArray(TypeInfo)[PByte(PAnsiChar(TypeInfo) + 1)^ + 2];
end;

function TInfo.Ord: Byte;
begin
  Result := PByteArray(TypeData(@Self))[8];
end;

function CompareBytes(A, B: Pointer; Info: Pointer; out Compared: Integer): PtrInt;
begin
  Compared := Ord(PByte(A)^ > PByte(B)^) - Ord(PByte(A)^ < PByte(B)^);
  Result := 1;
end;

function CompareWords(A, B: Pointer; Info: Pointer; out Compared: Integer): PtrInt;
begin
  Compared := Ord(PWord(A)^ > PWord(B)^) - Ord(PWord(A)^ < PWord(B)^);
  Result := 2;
end;

function ByKind(A, B: Pointer; Info: PInfo; out Compared: Integer): PtrInt; noinline;
begin
  Result := Table[Info^.Ord](A, B, Info, Compared);
end;

const
  Keys: array[0..4] of Int64 = (0, 1, 100, -7, 5000000000);
  Keys32: array[0..4] of Integer = (0, 1, 100, -7, 50000);

var
  K: Int64;
  K32: Integer;
  B1, B2: Byte;
  W1, W2: Word;
  C: Integer;
begin
  G.A := 135;
  G.D := 135;
  S := 17;
  for K in Keys do
  begin
    Check(Less(@S, K), 17 + K * 1001 + 125 * 1000000, 'a copy is less than its source');
    Check(LessOrEqual(@S, K), 17 + K * 1001 + 145 * 1000000, 'a copy is less than its source or equal');
    Check(Greater(@S, K), 17 + K * 1001 + 125 * 1000000, 'a source is greater than its copy');
    Check(Differs(@S, K), 17 + K * 1001 + 125 * 1000000, 'a copy differs from its source');
    Check(LessUnsigned(@S, UInt64(K)), 17 + K * 1001 + 125 * 1000000, 'an unsigned copy is less than its source');
    Check(Equal(@S, K), 17 + K * 1001 + 145 * 1000000, 'a copy equals its source');
    Check(LessInlined(@S, K), 17 + K * 1000 + 125 * 1000000, 'an inlined copy is less than its source');
    Check(LessThenStore(@S, K), 17 + K + 125, 'a copy compared and stored');
    Check(GY, K, 'a copy compared and stored, the store');
  end;
  for K32 in Keys32 do
  begin
    Check(Less32(@S, K32), 17 + K32 * 1000 + 125 * 100000, 'a 32-bit copy is less than its source');
    Check(GreaterOrEqual32(@S, K32), 17 + K32 * 1000 + 145 * 100000,
      'a 32-bit copy is greater than its source or equal');
    Check(LessUnsigned32(@S, Cardinal(K32)), Cardinal(17 + Cardinal(K32) * 1000 + 125 * 100000),
      'an unsigned 32-bit copy is less than its source');
  end;

  Table[0] := CompareBytes;
  Table[1] := CompareWords;
  InfoBytes[1] := 3;
  B1 := 200;
  B2 := 3;
  W1 := 1;
  W2 := 60000;
  InfoBytes[3 + 2 + 8] := 0;
  Check(ByKind(@B1, @B2, @InfoBytes, C), 1, 'a routine picked by the type data, bytes');
  Check(C, 1, 'a routine picked by the type data, bytes compared');
  InfoBytes[3 + 2 + 8] := 1;
  Check(ByKind(@W1, @W2, @InfoBytes, C), 2, 'a routine picked by the type data, words');
  Check(C, -1, 'a routine picked by the type data, words compared');

  if Fails = 0 then
    WriteLn('COPY_FIRST_READER_PASS')
  else
  begin
    WriteLn('COPY_FIRST_READER_FAIL ', Fails);
    Halt(1);
  end;
end.
