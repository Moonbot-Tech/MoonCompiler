program asm_block_routines_semantic;

{ The hand-written and hand-laid assembler routines of the x86-64 RTL against plain Pascal
  references: CompareByte, CompareWord, CompareDWord, IndexByte, IndexWord, IndexDWord,
  IndexQWord, FillChar, FillWord, FillDWord, FillQWord - every length up to 260 (150 for the
  index family, 300 for the fills) plus long ones, Move across every short size and the
  32/64/96/128/192/256/320/512 boundaries (separate, self and overlapping buffers), several
  alignments of both buffers, buffers
  that end exactly on a page boundary (the paths that may not read past it), every mismatch or
  hit position, both orders, a hit just behind the length, the unbounded (negative length)
  forms - and the string helpers fpc_ansistr_compare / _compare_equal,
  fpc_unicodestr_compare_equal and the two assign routines (contents, reference counts for
  nil, literal, shared, unique and self assignment) and Pos(char, string), the inlined
  length check around IndexByte / IndexWord; StrComp, the three RoundTo routines of Math,
  crc32c and xxHash32 of Generics.Hashes, the five varset routines and a threadvar access
  (SysRelocateThreadvar on Win64).  The
  routines are laid out by hand under
  doc/ASM_LAYOUT_RULES.md; a layout edit moves blocks and rewrites jumps, and this is the test
  that a block did not end up behind the wrong label. }

{$ifdef FPC}
  {$mode objfpc}{$H+}
{$endif}

uses
  Strings, Math, Generics.Hashes;

const
  PageSize = 4096;
  BufSize = 3 * PageSize;
var
  RawA, RawB: Pointer;
  A, B: PByte;   { both page aligned, BufSize bytes }
  Failures: Integer = 0;
  Checks: QWord = 0;

procedure Fail(const What: string; Len, OffA, OffB, P: Int64; Got, Want: Int64);
begin
  Inc(Failures);
  If Failures <= 12 then
    WriteLn('BAD ', What, ' len=', Len, ' offA=', OffA, ' offB=', OffB, ' p=', P, ' got=', Got, ' want=', Want);
end;

function Sign(V: Int64): Integer;
begin
  If V < 0 then Result := -1 else If V > 0 then Result := 1 else Result := 0;
end;

function RefCompareByte(P1, P2: PByte; Len: Int64): Integer;
var I: Int64;
begin
  Result := 0;
  for I := 0 to Len - 1 do
    If P1[I] <> P2[I] then begin
      If P1[I] < P2[I] then Result := -1 else Result := 1;
      Exit;
    end;
end;

procedure FillPattern;
var I: Integer;
begin
  for I := 0 to BufSize - 1 do begin
    A[I] := Byte(I * 31 + 7) or 1;    { never zero, so that an index search for 0 misses }
    B[I] := A[I];
  end;
end;

{ ---- Move ---- }
procedure RefMove(Source, Dest: PByte; Len: Int64);
var
  I: Int64;
begin
  If Len <= 0 then Exit;
  If (PtrUInt(Dest) > PtrUInt(Source)) and
     (PtrUInt(Dest) - PtrUInt(Source) < QWord(Len)) then
    for I := Len - 1 downto 0 do Dest[I] := Source[I]
  else
    for I := 0 to Len - 1 do Dest[I] := Source[I];
end;

procedure InitMoveBuffers(Count: Int64);
var
  I: Int64;
begin
  for I := 0 to Count - 1 do begin
    A[I] := Byte(I * 37 + 11);
    B[I] := Byte(I * 19 + 173);
  end;
end;

procedure CheckMoveBytes(const What: string; Actual, Expected: PByte;
  Count, Len, OffA, OffB: Int64);
var
  I: Int64;
begin
  for I := 0 to Count - 1 do begin
    Inc(Checks);
    If Actual[I] <> Expected[I] then begin
      Fail(What, Len, OffA, OffB, I, Actual[I], Expected[I]);
      Exit;
    end;
  end;
end;

procedure TestMoveSize(Len: Int64);
var
  OffA, OffB, I: Int64;
  PA, PB: PByte;
begin
  for OffA := 0 to 7 do begin
    OffB := (OffA * 5 + Len) and 15;
    InitMoveBuffers(BufSize);
    PA := A + PageSize + OffA;
    PB := B + PageSize + OffB;
    Move(PA^, PB^, Len);
    for I := 0 to Len - 1 do begin
      Inc(Checks);
      If PB[I] <> PA[I] then begin
        Fail('Move separate', Len, OffA, OffB, I, PB[I], PA[I]);
        Break;
      end;
    end;
    Inc(Checks);
    If PB[-1] <> Byte((PageSize + OffB - 1) * 19 + 173) then
      Fail('Move left guard', Len, OffA, OffB, -1, PB[-1],
        Byte((PageSize + OffB - 1) * 19 + 173));
    Inc(Checks);
    If PB[Len] <> Byte((PageSize + OffB + Len) * 19 + 173) then
      Fail('Move right guard', Len, OffA, OffB, Len, PB[Len],
        Byte((PageSize + OffB + Len) * 19 + 173));

    { A self-copy must leave every byte alone, including the >192 overlap dispatch. }
    for I := 0 to BufSize - 1 do B[I] := A[I];
    Move(PA^, PA^, Len);
    CheckMoveBytes('Move self', A, B, BufSize, Len, OffA, OffA);
  end;
end;

procedure TestMoveOverlapSize(Len, Distance: Int64);
const
  Guard = 32;
var
  I, Span: Int64;
  Actual, Expected: PByte;
begin
  Span := Len + Distance + Guard * 2;

  InitMoveBuffers(BufSize);
  for I := 0 to Span - 1 do B[PageSize - Guard + I] := A[PageSize - Guard + I];
  Actual := A + PageSize;
  Expected := B + PageSize;
  Move(Actual^, Actual[Distance], Len);
  RefMove(Expected, Expected + Distance, Len);
  CheckMoveBytes('Move overlap high', Actual - Guard, Expected - Guard,
    Span, Len, 0, Distance);

  InitMoveBuffers(BufSize);
  for I := 0 to Span - 1 do B[PageSize - Guard + I] := A[PageSize - Guard + I];
  Actual := A + PageSize;
  Expected := B + PageSize;
  Move(Actual[Distance], Actual^, Len);
  RefMove(Expected + Distance, Expected, Len);
  CheckMoveBytes('Move overlap low', Actual - Guard, Expected - Guard,
    Span, Len, Distance, 0);
end;

procedure TestMove;
const
  BoundarySizes: array[0..22] of Int64 =
    (31, 32, 33, 63, 64, 65, 79, 80, 81, 95, 96, 97, 127, 128, 129,
     159, 160, 191, 192, 193, 255, 256, 257);
  LongSizes: array[0..8] of Int64 =
    (320, 321, 511, 512, 513, 1024, 1536, 2048, 4096);
  Distances: array[0..5] of Int64 = (1, 16, 31, 32, 63, 128);
var
  I, J, Len: Int64;
begin
  for Len := 0 to 260 do TestMoveSize(Len);
  for I := Low(LongSizes) to High(LongSizes) do TestMoveSize(LongSizes[I]);
  for I := Low(BoundarySizes) to High(BoundarySizes) do
    for J := Low(Distances) to High(Distances) do
      If Distances[J] < BoundarySizes[I] then
        TestMoveOverlapSize(BoundarySizes[I], Distances[J]);
  for I := Low(LongSizes) to High(LongSizes) do
    for J := Low(Distances) to High(Distances) do
      If Distances[J] < LongSizes[I] then
        TestMoveOverlapSize(LongSizes[I], Distances[J]);
end;

{ ---- CompareByte ---- }
procedure TestCompareByteAt(PA, PB: PByte; Len: Int64; OffA, OffB: Int64);
var
  P, Step: Int64;
  Got: Int64;
  Save: Byte;
begin
  { same content for Len bytes, different bytes behind them (the over-read must ignore those) }
  P := 0;
  while P < Len do begin PB[P] := PA[P]; Inc(P); end;
  PB[Len] := Byte(PA[Len] + 2);
  Got := CompareByte(PA^, PB^, Len); Inc(Checks);
  If Got <> 0 then Fail('CompareByte equal', Len, OffA, OffB, -1, Got, 0);
  If Len <= 96 then Step := 1 else Step := 1 + Len div 61;
  P := 0;
  while P < Len do begin
    Save := PB[P];
    PB[P] := Byte(Save + 2);          { PA < PB at P (pattern bytes are odd, +2 stays odd and differs) }
    If PB[P] < Save then begin PB[P] := Save; Inc(P, Step); Continue; end;
    Got := CompareByte(PA^, PB^, Len); Inc(Checks);
    If Sign(Got) <> -1 then Fail('CompareByte less', Len, OffA, OffB, P, Got, -1);
    Got := CompareByte(PB^, PA^, Len); Inc(Checks);
    If Sign(Got) <> 1 then Fail('CompareByte greater', Len, OffA, OffB, P, Got, 1);
    PB[P] := Save;
    Inc(P, Step);
  end;
end;

procedure TestCompareByte;
var
  Len, OffA, OffB: Int64;
  Lens: array[0..7] of Int64 = (511, 512, 513, 1000, 1024, 2049, 4000, 4097);
  I: Integer;
  Got: Int64;
  Save: Byte;
begin
  for Len := 0 to 260 do
    for OffA := 0 to 9 do begin
      OffB := (OffA * 7 + Len) and 15;
      TestCompareByteAt(A + PageSize + OffA, B + PageSize + OffB, Len, OffA, OffB);
      { both buffers end exactly on a page boundary }
      If Len <= 64 then
        TestCompareByteAt(A + 2 * PageSize - Len, B + 2 * PageSize - Len, Len, -1, -1);
      { only one of them does }
      If Len <= 64 then
        TestCompareByteAt(A + 2 * PageSize - Len, B + PageSize + OffB, Len, -1, OffB);
    end;
  for I := 0 to High(Lens) do
    for OffA := 0 to 3 do
      TestCompareByteAt(A + 16 + OffA, B + 16 + (OffA * 5 and 15), Lens[I], OffA, OffA * 5 and 15);
  { same buffer }
  for Len := 0 to 200 do begin
    Got := CompareByte(A[5], A[5], Len); Inc(Checks);
    If Got <> 0 then Fail('CompareByte same', Len, 5, 5, -1, Got, 0);
  end;
  { unbounded form: negative length compares up to the first difference }
  FillPattern;
  for Len := 0 to 100 do begin
    Save := B[PageSize + Len];
    B[PageSize + Len] := Byte(Save + 2);
    If B[PageSize + Len] > Save then begin
      Got := CompareByte(A[PageSize], B[PageSize], -1); Inc(Checks);
      If Sign(Got) <> -1 then Fail('CompareByte unbounded', -1, 0, 0, Len, Got, -1);
      Got := CompareByte(B[PageSize], A[PageSize], -1); Inc(Checks);
      If Sign(Got) <> 1 then Fail('CompareByte unbounded', -1, 0, 0, Len, Got, 1);
    end;
    B[PageSize + Len] := Save;
  end;
end;

{ ---- CompareWord / CompareDWord ---- }
procedure TestCompareWide(ElemSize: Integer);
var
  Len, OffA, P, Step: Int64;
  PA, PB: PByte;
  Got, Want: Int64;
  Save: Byte;
  K: Integer;
begin
  for Len := 0 to 140 do
    for OffA := 0 to 5 do
      for K := 0 to 1 do begin
        If K = 0 then begin
          PA := A + PageSize + OffA * ElemSize + (OffA and 1);
          PB := B + PageSize + ((OffA * 3 + Len) and 7) * ElemSize;
        end else begin
          If Len > 40 then Continue;
          PA := A + 2 * PageSize - Len * ElemSize;
          PB := B + 2 * PageSize - Len * ElemSize;
        end;
        P := 0;
        while P < Len * ElemSize do begin PB[P] := PA[P]; Inc(P); end;
        PB[Len * ElemSize] := Byte(PA[Len * ElemSize] + 2);
        If ElemSize = 2 then Got := CompareWord(PA^, PB^, Len) else Got := CompareDWord(PA^, PB^, Len);
        Inc(Checks);
        If Got <> 0 then Fail('CompareWide equal', Len, OffA, ElemSize, -1, Got, 0);
        If Len <= 48 then Step := 1 else Step := 1 + Len div 23;
        P := 0;
        while P < Len do begin
          { change the high byte of element P, so that the element order is decided by it }
          Save := PB[P * ElemSize + ElemSize - 1];
          PB[P * ElemSize + ElemSize - 1] := Byte(Save + 2);
          If PB[P * ElemSize + ElemSize - 1] > Save then Want := -1 else Want := 1;
          If ElemSize = 2 then Got := CompareWord(PA^, PB^, Len) else Got := CompareDWord(PA^, PB^, Len);
          Inc(Checks);
          If Sign(Got) <> Want then Fail('CompareWide order', Len, OffA, ElemSize, P, Got, Want);
          If ElemSize = 2 then Got := CompareWord(PB^, PA^, Len) else Got := CompareDWord(PB^, PA^, Len);
          Inc(Checks);
          If Sign(Got) <> -Want then Fail('CompareWide order swapped', Len, OffA, ElemSize, P, Got, -Want);
          PB[P * ElemSize + ElemSize - 1] := Save;
          Inc(P, Step);
        end;
      end;
end;

{ ---- IndexByte / IndexWord / IndexDWord / IndexQWord ---- }
procedure TestIndex(ElemSize: Integer);
var
  Len, OffA, P, Step, Got: Int64;
  PA: PByte;
  K, J: Integer;
  SaveBytes: array[0..7] of Byte;

  function Call(L: Int64): Int64;
  begin
    case ElemSize of
      1: Result := IndexByte(PA^, L, 0);
      2: Result := IndexWord(PA^, L, 0);
      4: Result := IndexDWord(PA^, L, 0);
    else
      Result := IndexQWord(PA^, L, 0);
    end;
    Inc(Checks);
  end;

begin
  for Len := 0 to 150 do
    for OffA := 0 to 7 do
      for K := 0 to 1 do begin
        If K = 0 then
          PA := A + PageSize + OffA * ElemSize + (OffA and 1) * Ord(ElemSize > 1)
        else begin
          If Len > 40 then Continue;
          PA := A + 2 * PageSize - Len * ElemSize;
        end;
        Got := Call(Len);
        If Got <> -1 then Fail('Index miss', Len, OffA, ElemSize, -1, Got, -1);
        If Len <= 70 then Step := 1 else Step := 1 + Len div 29;
        P := 0;
        while P < Len do begin
          for J := 0 to ElemSize - 1 do begin
            SaveBytes[J] := PA[P * ElemSize + J];
            PA[P * ElemSize + J] := 0;
          end;
          Got := Call(Len);
          If Got <> P then Fail('Index hit', Len, OffA, ElemSize, P, Got, P);
          { a hit just behind the length must not be reported }
          If P > 0 then begin
            Got := Call(P);
            If Got <> -1 then Fail('Index hit behind len', P, OffA, ElemSize, P, Got, -1);
          end;
          { unbounded form }
          If (K = 0) and (ElemSize <= 2) then begin
            Got := Call(-1);
            If Got <> P then Fail('Index unbounded', -1, OffA, ElemSize, P, Got, P);
          end;
          for J := 0 to ElemSize - 1 do
            PA[P * ElemSize + J] := SaveBytes[J];
          Inc(P, Step);
        end;
      end;
end;

{ ---- FillChar / FillWord / FillDWord / FillQWord ---- }
procedure TestFill(ElemSize: Integer);
var
  Len, OffA, I: Int64;
  PA: PByte;
  Pattern: QWord;
  Ok: Boolean;
begin
  Pattern := QWord($A1B2C3D4E5F60718);
  for Len := 0 to 300 do
    for OffA := 0 to 9 do begin
      FillPattern;
      PA := A + PageSize + OffA;
      case ElemSize of
        1: FillChar(PA^, Len, Byte(Pattern));
        2: FillWord(PA^, Len, Word(Pattern));
        4: FillDWord(PA^, Len, DWord(Pattern));
      else
        FillQWord(PA^, Len, Pattern);
      end;
      Inc(Checks);
      Ok := True;
      for I := 0 to Len * ElemSize - 1 do
        If PA[I] <> Byte(Pattern shr (8 * (I mod ElemSize))) then Ok := False;
      { the bytes around must be untouched }
      for I := 1 to 64 do
        If (PA[-I] <> B[PageSize + OffA - I]) or (PA[Len * ElemSize + I - 1] <> B[PageSize + OffA + Len * ElemSize + I - 1]) then
          Ok := False;
      If not Ok then Fail('Fill', Len, OffA, ElemSize, -1, 0, 0);
    end;
  FillPattern;
end;

{ ---- string compare / equality / assign (fpc_ansistr_compare, _compare_equal, fpc_unicodestr_compare_equal, *_assign) ---- }
procedure TestStrings;
var
  L1, L2, P, I, Want: Integer;
  R0: SizeInt;
  S1, S2, Keep: RawByteString;
  U1, U2, UKeep: UnicodeString;

  function MakeA(Len, Seed: Integer): RawByteString;
  var K: Integer;
  begin
    SetLength(Result, Len);
    for K := 1 to Len do Result[K] := AnsiChar(((K * 7 + Seed) and 63) + 48);
  end;

  function MakeU(Len, Seed: Integer): UnicodeString;
  var K: Integer;
  begin
    SetLength(Result, Len);
    for K := 1 to Len do Result[K] := WideChar(((K * 7 + Seed) and 63) + $410);
  end;

  function RefA(const X, Y: RawByteString): Integer;
  var K, N: Integer;
  begin
    N := Length(X); if Length(Y) < N then N := Length(Y);
    for K := 1 to N do
      If X[K] <> Y[K] then begin if X[K] < Y[K] then Exit(-1) else Exit(1); end;
    Result := Sign(Length(X) - Length(Y));
  end;

begin
  for L1 := 0 to 80 do
    for L2 := 0 to 80 do begin
      If (L1 > 44) and (L2 > 44) and (L1 <> L2) and ((L1 + L2) and 3 <> 0) then Continue;
      S1 := MakeA(L1, 1); S2 := MakeA(L2, 1);
      Want := RefA(S1, S2); Inc(Checks);
      If (Ord(S1 < S2) - Ord(S1 > S2)) <> -Want then Fail('astr order', L1, L2, 0, -1, Ord(S1 < S2) - Ord(S1 > S2), -Want);
      If (S1 = S2) <> (Want = 0) then Fail('astr equal', L1, L2, 0, -1, Ord(S1 = S2), Ord(Want = 0));
      U1 := MakeU(L1, 1); U2 := MakeU(L2, 1); Inc(Checks);
      If (U1 = U2) <> (L1 = L2) then Fail('ustr equal', L1, L2, 0, -1, Ord(U1 = U2), Ord(L1 = L2));
      If L1 = L2 then begin
        P := 1;
        while P <= L1 do begin
          S2 := MakeA(L2, 1); S2[P] := AnsiChar(Ord(S2[P]) + 1);
          Inc(Checks);
          If not (S1 < S2) or (S1 = S2) or not (S2 > S1) then Fail('astr mismatch', L1, L2, 0, P, 0, 1);
          U2 := MakeU(L2, 1); U2[P] := WideChar(Ord(U2[P]) + 1);
          Inc(Checks);
          If (U1 = U2) or not (U1 <> U2) then Fail('ustr mismatch', L1, L2, 0, P, 1, 0);
          If L1 <= 40 then Inc(P) else Inc(P, 7);
        end;
      end;
    end;
  { assignment: nil, literal (refcount -1), shared, unique being released, self }
  for I := 1 to 20000 do begin
    Keep := MakeA(I and 31, I);
    R0 := StringRefCount(Keep);          { the function result temporary may hold a reference too }
    S1 := Keep;                          { shared: one more owner }
    If (Length(Keep) > 0) and (StringRefCount(Keep) <> R0 + 1) then Fail('astr refcount shared', I, 0, 0, -1, StringRefCount(Keep), R0 + 1);
    S2 := S1; S1 := '';                  { one owner in, one out }
    If (Length(Keep) > 0) and (StringRefCount(Keep) <> R0 + 1) then Fail('astr refcount after release', I, 0, 0, -1, StringRefCount(Keep), R0 + 1);
    S2 := 'literal';                     { constant string over a shared one }
    If (Length(Keep) > 0) and (StringRefCount(Keep) <> R0) then Fail('astr refcount literal', I, 0, 0, -1, StringRefCount(Keep), R0);
    If S2 <> 'literal' then Fail('astr literal content', I, 0, 0, -1, 0, 1);
    S1 := MakeA(9, I); S1 := Keep;       { a unique string is freed by the assignment }
    S1 := S1;
    If S1 <> Keep then Fail('astr content', I, 0, 0, -1, 0, 1);
    S1 := ''; R0 := StringRefCount(Keep); S1 := Keep;   { nil destination (the temporary was reused above: count again) }
    If (Length(Keep) > 0) and (StringRefCount(Keep) <> R0 + 1) then Fail('astr refcount nil dest', I, 0, 0, -1, StringRefCount(Keep), R0 + 1);
    S1 := '';
    UKeep := MakeU(I and 31, I);
    R0 := StringRefCount(UKeep);
    U1 := UKeep;
    If (Length(UKeep) > 0) and (StringRefCount(UKeep) <> R0 + 1) then Fail('ustr refcount shared', I, 0, 0, -1, StringRefCount(UKeep), R0 + 1);
    U2 := U1; U1 := '';
    U2 := 'literal';
    If (Length(UKeep) > 0) and (StringRefCount(UKeep) <> R0) then Fail('ustr refcount literal', I, 0, 0, -1, StringRefCount(UKeep), R0);
    If U2 <> 'literal' then Fail('ustr literal content', I, 0, 0, -1, 0, 1);
    U1 := MakeU(9, I); U1 := UKeep; U1 := U1;
    If U1 <> UKeep then Fail('ustr content', I, 0, 0, -1, 0, 1);
    U1 := ''; R0 := StringRefCount(UKeep); U1 := UKeep;
    If (Length(UKeep) > 0) and (StringRefCount(UKeep) <> R0 + 1) then Fail('ustr refcount nil dest', I, 0, 0, -1, StringRefCount(UKeep), R0 + 1);
    U1 := '';
    Inc(Checks, 8);
  end;
end;

{ ---- Pos(char, string): the inlined length check around IndexByte / IndexWord ---- }
procedure TestPosChar;
var
  Len, P, Offset, Want, Got: Integer;
  A8: RawByteString;
  U: UnicodeString;
begin
  for Len := 0 to 70 do
    for P := 0 to Len do          { P = 0: no hit }
    begin
      SetLength(A8, Len); SetLength(U, Len);
      for Offset := 1 to Len do
      begin
        A8[Offset] := AnsiChar(97 + Offset mod 23);
        U[Offset] := WideChar($430 + Offset mod 23);
      end;
      If P > 0 then
      begin
        A8[P] := '#'; U[P] := WideChar($2116);
      end;
      for Offset := -1 to Len + 2 do
      begin
        If (P > 0) and (Offset >= 1) and (Offset <= P) then Want := P else Want := 0;
        Got := Pos(AnsiChar('#'), A8, Offset); Inc(Checks);
        If Got <> Want then Fail('Pos(AnsiChar, RawByteString)', Len, P, Offset, -1, Got, Want);
        Got := Pos(WideChar($2116), U, Offset); Inc(Checks);
        If Got <> Want then Fail('Pos(WideChar, UnicodeString)', Len, P, Offset, -1, Got, Want);
      end;
      If (P > 0) and (Pos(AnsiChar('#'), A8) <> P) then Fail('Pos default offset', Len, P, 1, -1, Pos(AnsiChar('#'), A8), P);
      If Pos(AnsiChar('#'), UnicodeString(A8)) <> P then Fail('Pos(AnsiChar, UnicodeString)', Len, P, 1, -1, 0, P);
    end;
end;

{ ---- StrComp: the unrolled byte loop, every length, every mismatch position, both orders,
       strings that end on the last byte of a page ---- }
function RefStrComp(P1, P2: PAnsiChar): Integer;
begin
  while (P1^ = P2^) and (P1^ <> #0) do
  begin
    Inc(P1); Inc(P2);
  end;
  Result := Sign(Int64(Ord(P1^)) - Int64(Ord(P2^)));
end;

procedure TestStrComp;
var
  Len, P, OffA, OffB, I: Integer;
  SA, SB: PAnsiChar;
begin
  for Len := 0 to 70 do
    for OffA := 0 to 3 do
      for OffB := 0 to 2 do
      begin
        { both strings end (with their terminator) on the last byte of the second page }
        SA := PAnsiChar(A) + 2 * PageSize - Len - 1 - OffA * 16;
        SB := PAnsiChar(B) + 2 * PageSize - Len - 1 - OffB * 16;
        If OffA = 0 then SA := PAnsiChar(A) + 2 * PageSize - Len - 1;
        for I := 0 to Len - 1 do
        begin
          SA[I] := AnsiChar(65 + I mod 50);
          SB[I] := SA[I];
        end;
        SA[Len] := #0; SB[Len] := #0;
        Inc(Checks);
        If Sign(StrComp(SA, SB)) <> 0 then Fail('StrComp equal', Len, OffA, OffB, -1, StrComp(SA, SB), 0);
        for P := 0 to Len - 1 do
        begin
          SB[P] := AnsiChar(Ord(SA[P]) + 1);
          Inc(Checks, 2);
          If Sign(StrComp(SA, SB)) <> RefStrComp(SA, SB) then Fail('StrComp less', Len, OffA, OffB, P, StrComp(SA, SB), RefStrComp(SA, SB));
          If Sign(StrComp(SB, SA)) <> RefStrComp(SB, SA) then Fail('StrComp greater', Len, OffA, OffB, P, StrComp(SB, SA), RefStrComp(SB, SA));
          SB[P] := #200;   { the compare is unsigned }
          Inc(Checks);
          If Sign(StrComp(SA, SB)) <> RefStrComp(SA, SB) then Fail('StrComp unsigned', Len, OffA, OffB, P, StrComp(SA, SB), RefStrComp(SA, SB));
          SB[P] := #0;     { the shorter string }
          Inc(Checks);
          If Sign(StrComp(SA, SB)) <> RefStrComp(SA, SB) then Fail('StrComp shorter', Len, OffA, OffB, P, StrComp(SA, SB), RefStrComp(SA, SB));
          SB[P] := SA[P];
        end;
      end;
  FillPattern;
end;

{ ---- RoundTo: the three hand-written routines on each of their paths (scale down, scale up,
       to an integer, ties to even, values they hand to the exact routine, zero, infinity) ---- }
procedure TestRoundTo;

  procedure D(V: Double; Digits: Integer; Want: Double);
  var
    Got: Double;
  begin
    Got := RoundTo(V, Digits);
    Inc(Checks);
    If (Got <> Want) or ((Got = 0) and ((1 / V < 0) <> (1 / Got < 0)) and (V <> 0)) then
      Fail('RoundTo(Double)', Digits, 0, 0, -1, Round(Got * 1000), Round(Want * 1000));
  end;

  procedure S(V: Single; Digits: Integer; Want: Single);
  var
    Got: Single;
  begin
    Got := RoundTo(V, Digits);
    Inc(Checks);
    If Got <> Want then
      Fail('RoundTo(Single)', Digits, 0, 0, -1, Round(Got * 1000), Round(Want * 1000));
  end;

{$ifdef FPC_HAS_TYPE_EXTENDED}
  procedure E(V: Extended; Digits: Integer; Want: Extended);
  var
    Got: Extended;
  begin
    Got := RoundTo(V, Digits);
    Inc(Checks);
    If Got <> Want then
      Fail('RoundTo(Extended)', Digits, 0, 0, -1, Round(Got * 1000), Round(Want * 1000));
  end;
{$endif}

var
  Inf: Double;
begin
  D(1234.5678, -2, 1234.57);   D(-1234.5678, -2, -1234.57);  D(1234.5678, 2, 1200);
  D(1234.5678, 0, 1235);       D(2.5, 0, 2);                 D(3.5, 0, 4);
  D(-2.5, 0, -2);              D(0.125, -2, 0.12);           D(0.375, -2, 0.38);
  D(0, -2, 0);                 D(1e300, -2, 1e300);          D(123456789.125, -2, 123456789.12);
  D(0.4, 0, 0);                D(1e-320, -3, 0);             D(5e15, -1, 5e15);
  Inf := 1e300; Inf := Inf * Inf;
  D(Inf, -2, Inf);             D(-Inf, 3, -Inf);
  S(1234.5677, -2, 1234.57);   S(-1234.5677, -2, -1234.57);  S(1234.5677, 2, 1200);
  S(2.5, 0, 2);                S(3.5, 0, 4);                 S(0.125, -2, 0.12);
  S(0, -2, 0);                 S(1e30, -2, 1e30);            S(0.4, 0, 0);
{$ifdef FPC_HAS_TYPE_EXTENDED}
  {$if sizeof(extended)=10}
  E(1234.5678, -2, 1234.57);   E(-1234.5678, -2, -1234.57);  E(1234.5678, 2, 1200);
  E(2.5, 0, 2);                E(3.5, 0, 4);                 E(0.125, -2, 0.12);
  E(0, -2, 0);                 E(1e300, -2, 1e300);          E(0.4, 0, 0);
  {$endif}
{$endif}
end;

{ ---- crc32c of Generics.Hashes (the SSE4.2 routine where the CPU has it) against the bitwise
       definition: every length up to 70 from three alignments ---- }
function RefCrc32c(Crc: Cardinal; P: PByte; Len: Integer): Cardinal;
var
  I, K: Integer;
begin
  Crc := not Crc;
  for I := 0 to Len - 1 do
  begin
    Crc := Crc xor P[I];
    for K := 1 to 8 do
      If (Crc and 1) <> 0 then
        Crc := (Crc shr 1) xor $82F63B78
      else
        Crc := Crc shr 1;
  end;
  Result := not Crc;
end;

procedure TestCrc32c;
var
  Len, Off: Integer;
  Got, Want: Cardinal;
begin
  for Len := 1 to 70 do
    for Off := 0 to 2 do
    begin
      Got := crc32c($12345678, PAnsiChar(A) + Off * 5, Len);
      Want := RefCrc32c($12345678, A + Off * 5, Len);
      Inc(Checks);
      If Got <> Want then Fail('crc32c', Len, Off, 0, -1, Got, Want);
    end;
end;

{ ---- xxHash32 of Generics.Hashes (assembler on both systems, each in its own spelling) against
       the Pascal one: every length up to 70 - the 16-byte loop, the 4-byte loop and the byte
       loop - from three alignments and with three seeds ---- }
procedure TestXxHash32;
const
  Seeds: array[0..2] of Cardinal = (0, $12345678, $FFFFFFFF);
var
  Len, Off, Seed: Integer;
  Got, Want: Cardinal;
begin
  for Seed := 0 to High(Seeds) do
    for Len := 0 to 70 do
      for Off := 0 to 2 do
      begin
        Got := xxHash32(Seeds[Seed], A + Off * 5, Len);
        Want := xxHash32Pascal(Seeds[Seed], A + Off * 5, Len);
        Inc(Checks);
        If Got <> Want then Fail('xxHash32', Len, Off, Seed, -1, Got, Want);
      end;
end;

{ ---- the varset routines (sets of more than 32 elements) against element-wise references: a
       13-byte set (the byte loop), a 25-byte set (one 16-byte step and the overlapping tail) and
       a 32-byte set; every operation, also with the destination as one of the operands ---- }
type
  TS13 = set of 0..99;
  TS25 = set of 0..199;
  TS32 = set of Byte;

var
  SetSeed: Cardinal = 12345;

function Next: Cardinal;
begin
  SetSeed := SetSeed * 1664525 + 1013904223;
  Result := SetSeed shr 8;
end;

procedure BadSet(const What: string; Bits, Round: Integer);
begin
  Fail('varset ' + What, Bits, Round, 0, -1, 0, 0);
end;

{$macro on}
{$define TESTBODY:=
var
  A, B, R, W: TSet;
  I, Round: Integer;
  Sub: Boolean;
begin
  for Round := 1 to 200 do
  begin
    A := []; B := [];
    for I := 0 to HighBit do
    begin
      If Next and 3 = 0 then Include(A, I);
      If Next and 3 <> 1 then Include(B, I);
    end;
    If Round and 7 = 0 then B := A;
    If Round and 15 = 1 then A := [];
    R := A + B; W := [];
    for I := 0 to HighBit do If (I in A) or (I in B) then Include(W, I);
    Inc(Checks); If R <> W then BadSet('+', HighBit, Round);
    R := A * B; W := [];
    for I := 0 to HighBit do If (I in A) and (I in B) then Include(W, I);
    Inc(Checks); If R <> W then BadSet('*', HighBit, Round);
    R := A - B; W := [];
    for I := 0 to HighBit do If (I in A) and not (I in B) then Include(W, I);
    Inc(Checks); If R <> W then BadSet('-', HighBit, Round);
    R := A >< B; W := [];
    for I := 0 to HighBit do If (I in A) <> (I in B) then Include(W, I);
    Inc(Checks); If R <> W then BadSet('><', HighBit, Round);
    { in place: the destination is one of the operands }
    R := A; R := R + B; W := A + B;
    Inc(Checks); If R <> W then BadSet('+ in place', HighBit, Round);
    R := B; R := A - R; W := A - B;
    Inc(Checks); If R <> W then BadSet('- in place', HighBit, Round);
    R := B; R := A >< R; W := A >< B;
    Inc(Checks); If R <> W then BadSet('>< in place', HighBit, Round);
    Sub := True;
    for I := 0 to HighBit do If (I in A) and not (I in B) then Sub := False;
    Inc(Checks); If (A <= B) <> Sub then BadSet('<=', HighBit, Round);
    Inc(Checks); If not (A * B <= A) then BadSet('<= of a product', HighBit, Round);
  end;
end;}

{$define TSet:=TS13}{$define HighBit:=99}
procedure Test13;
TESTBODY

{$define TSet:=TS25}{$define HighBit:=199}
procedure Test25;
TESTBODY

{$define TSet:=TS32}{$define HighBit:=255}
procedure Test32;
TESTBODY

procedure TestVarSets;
begin
  Test13;
  Test25;
  Test32;
end;

{ ---- a threadvar: on Win64 every access goes through the hand-written SysRelocateThreadvar ---- }
threadvar
  ThreadCounter: Int64;

procedure TestThreadVar;
var
  I: Integer;
begin
  ThreadCounter := 0;
  for I := 1 to 1000 do
    ThreadCounter := ThreadCounter + I;
  Inc(Checks);
  If ThreadCounter <> 500500 then Fail('threadvar', 0, 0, 0, -1, ThreadCounter, 500500);
end;

begin
  RawA := GetMem(BufSize + PageSize);
  RawB := GetMem(BufSize + PageSize);
  A := PByte((PtrUInt(RawA) + PageSize - 1) and not PtrUInt(PageSize - 1));
  B := PByte((PtrUInt(RawB) + PageSize - 1) and not PtrUInt(PageSize - 1));
  TestMove;
  FillPattern;
  TestCompareByte;
  FillPattern;
  TestCompareWide(2);
  FillPattern;
  TestCompareWide(4);
  FillPattern;
  TestIndex(1);
  TestIndex(2);
  TestIndex(4);
  TestIndex(8);
  TestFill(1);
  TestFill(2);
  TestFill(4);
  TestFill(8);
  TestStrings;
  TestPosChar;
  TestStrComp;
  TestRoundTo;
  TestCrc32c;
  TestXxHash32;
  TestVarSets;
  TestThreadVar;
  If Failures <> 0 then begin
    WriteLn('ASM_BLOCK_ROUTINES_FAIL ', Failures, ' of ', Checks);
    Halt(1);
  end;
  WriteLn('ASM_BLOCK_ROUTINES_OK');
end.
