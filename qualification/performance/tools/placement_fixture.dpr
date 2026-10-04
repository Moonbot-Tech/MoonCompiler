program placement_fixture;

{ Fixture for check_placement_rules.py: ordinary Pascal loops, branches and
  tiny procedures, no source alignment directives.  The gate compiles it with
  the toolchain under test and checks the placement rules on the resulting
  executable. }

{$mode delphi}{$H+}{$Q-}{$R-}

uses
  SysUtils;

var
  Data: array[0..1023] of Integer;
  Words: array[0..255] of Word;
  Sink: Int64;

function TinyLeaf(A, B: Integer): Integer;
begin
  If A > B then
    Result := A - B
  else
    Result := B - A;
end;

function TinyLeaf2(A: Integer): Integer;
begin
  Result := A * 3 + 1;
end;

function ShortLoopSum(N: Integer): Int64;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
    Result := Result + Data[I and 1023];
end;

function ShortLoopCount(N: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
    If Words[I and 255] > 100 then
      Inc(Result);
end;

function LongLoopMix(N: Integer): Int64;
var
  I, V: Integer;
begin
  Result := 0;
  for I := 0 to N - 1 do
  begin
    V := Data[I and 1023];
    If V and 1 = 0 then
      Result := Result + V * 3
    else If V and 2 = 0 then
      Result := Result - V
    else If V and 4 = 0 then
      Result := Result xor V
    else If V > 1000 then
      Result := Result + 7
    else
      Result := Result + TinyLeaf2(V);
    If (I and 15) = 0 then
      Words[(I shr 4) and 255] := Word(Result);
  end;
end;

{ Hand-written assembler keeps its own alignment: the 16-byte constant
  after .balign 16 is loaded with movdqa, which faults when the placement
  drops the alignment (found by the mORMot AES-NI code in the chimera
  gate). }
function AsmAlignedConst(V: Cardinal): Cardinal; assembler; nostackframe;
asm
        { the argument register of the target ABI: rcx on Win64, rdi on SysV }
{$ifdef win64}
        movd     %ecx, %xmm0
{$else}
        movd     %edi, %xmm0
{$endif}
        pshufd   $0, %xmm0, %xmm0
        movdqa   .LConst(%rip), %xmm1
        pxor     %xmm1, %xmm0
        movd     %xmm0, %eax
        ret
        .balign  16
.LConst:
        .long    0x01234567, 0x89abcdef, 0x0f0f0f0f, 0xf0f0f0f0
end;

{ The shapes of the RTL cases that lost with the first rules 2/3/1: a six-instruction loop
  that runs one iteration per cycle, a loop just over one line with a call
  and a case inside, a big loop with many taken branches, and a small hot
  callee called from a tight loop. }
type
  THolder = class
    Values: array[0..255] of UInt64;
  end;

var
  Holder: THolder;
  Bytes: array[0..1023] of Byte;
  Out: array[0..4095] of Byte;

{ the incr_ref_many shape: a 44-byte loop after a 16-byte prologue, so
  that the jump target inside it sits on byte 55 of its natural line - a
  target pad wanted there once, and its prefixes behind the loop's
  forward jumps must go away with it (48 bytes of nops on the stand) }
procedure IncrRefLike(Data: PPointer; Count: SizeInt); noinline;
var
  I: SizeInt;
  P: Pointer;
begin
  for I := 0 to Count - 1 do
  begin
    P := Data[I];
    If Assigned(P) then
      If PLongint(P - 12)^ > 0 then
        AtomicIncrement(PLongint(P - 12)^);
  end;
end;

{ the managed-static-array shape: a 61-byte leaf whose last join label
  sits on byte 57 - a target pad there pushed the routine over the line }
type
  TStatic4 = array[0..3] of UnicodeString;

function TailJoinLeaf(const Values: TStatic4): UInt64; noinline;
begin
  Result := Length(Values[0]) + Length(Values[1]) + Length(Values[2]) + Length(Values[3]);
end;

function TinyLoopHot(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
      Result := Result + Holder.Values[J];
end;

function SumConst(const Values: array of const): UInt64; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Values) do
    case Values[I].VType of
      vtInteger:
        Result := Result + UInt32(Values[I].VInteger);
      vtInt64:
        Result := Result + UInt64(Values[I].VInt64^);
    end;
end;

function LoopOverLine(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 15 do
      Result := Result + SumConst([I, J, Int64(I) * J, 17]);
end;

function EncodeLike(N: Integer): Integer;
var
  I, O: Integer;
  V: Byte;
begin
  O := 0;
  for I := 0 to N - 1 do
  begin
    V := Bytes[I and 1023];
    If V < $80 then
    begin
      Out[O and 4095] := V;
      Inc(O);
    end
    else If V < $C0 then
    begin
      Out[O and 4095] := $C0 or (V shr 6);
      Out[(O + 1) and 4095] := $80 or (V and $3F);
      Inc(O, 2);
    end
    else If V < $E0 then
    begin
      Out[O and 4095] := $E0;
      Out[(O + 1) and 4095] := $80 or (V shr 4);
      Out[(O + 2) and 4095] := $80 or (V and $F);
      Inc(O, 3);
    end
    else If V = $FF then
      Inc(O, 7)
    else
    begin
      Out[O and 4095] := $F0;
      Out[(O + 1) and 4095] := V;
      Inc(O, 2);
    end;
  end;
  Result := O;
end;

function HotCallee(Base: THolder; Index: Integer): UInt64; noinline;
begin
  If Base = nil then
    Exit(0);
  If Index < 0 then
    Index := -Index;
  Result := Base.Values[Index and 255];
  If Result and 1 = 0 then
    Result := Result * 3 + 1
  else
    Result := Result shr 1;
  If Index and 4 = 0 then
    Result := Result + Base.Values[(Index + 1) and 255]
  else
    Result := Result xor Base.Values[(Index + 2) and 255];
  If Result > 1000000 then
    Result := Result mod 1000003;
end;

function CallLoop(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 255 do
      Result := Result + HotCallee(Holder, J);
end;

function BranchDense(A, B, C: Integer): Integer;
begin
  Result := 0;
  If A > B then Inc(Result);
  If B > C then Inc(Result, 2);
  If A = C then Inc(Result, 4);
  If A < 0 then Inc(Result, 8);
  If B < 0 then Inc(Result, 16);
  If C < 0 then Inc(Result, 32);
  If A + B > C then Inc(Result, 64);
  If A - B < C then Inc(Result, 128);
  If A * 2 > B then Inc(Result, 256);
  If B * 2 > C then Inc(Result, 512);
end;

{ The carry trick of a set test with ranges, "stc; je L; sub; cmp; L: jae": the label between the
  compare and the jump is a jump target, the assembler puts its (empty) target pad node there,
  and the walk that finds the fused pair used to stop at that node - the pair was judged as a
  lone jae and left across a boundary (TValue.AsSingle).  Sixteen such tests at sixteen
  offsets. }
type
  TSetKind = 0..31;
var
  SetSink: Integer;

function SetRangeTests(K: TSetKind): Integer; noinline;
begin
  Result := 0;
  If K in [TSetKind(1), TSetKind(18)..TSetKind(20)] then Inc(Result, 1);
  Inc(SetSink);
  If K in [TSetKind(2), TSetKind(19)..TSetKind(21)] then Inc(Result, 2);
  SetSink := SetSink xor 4;
  If K in [TSetKind(3), TSetKind(20)..TSetKind(22)] then Inc(Result, 4);
  If K in [TSetKind(4), TSetKind(21)..TSetKind(23)] then Inc(Result, 8);
  Inc(SetSink);
  If K in [TSetKind(5), TSetKind(22)..TSetKind(24)] then Inc(Result, 16);
  If K in [TSetKind(1), TSetKind(18)..TSetKind(20)] then Inc(Result, 32);
  SetSink := SetSink xor 8;
  If K in [TSetKind(2), TSetKind(19)..TSetKind(21)] then Inc(Result, 64);
  Inc(SetSink);
  If K in [TSetKind(3), TSetKind(20)..TSetKind(22)] then Inc(Result, 128);
  If K in [TSetKind(4), TSetKind(21)..TSetKind(23)] then Inc(Result, 256);
  If K in [TSetKind(5), TSetKind(22)..TSetKind(24)] then Inc(Result, 512);
  Inc(SetSink);
  SetSink := SetSink xor 12;
  If K in [TSetKind(1), TSetKind(18)..TSetKind(20)] then Inc(Result, 1024);
  If K in [TSetKind(2), TSetKind(19)..TSetKind(21)] then Inc(Result, 2048);
  If K in [TSetKind(3), TSetKind(20)..TSetKind(22)] then Inc(Result, 4096);
  Inc(SetSink);
  If K in [TSetKind(4), TSetKind(21)..TSetKind(23)] then Inc(Result, 8192);
  SetSink := SetSink xor 16;
  If K in [TSetKind(5), TSetKind(22)..TSetKind(24)] then Inc(Result, 16384);
  If K in [TSetKind(1), TSetKind(18)..TSetKind(20)] then Inc(Result, 32768);
  Inc(SetSink);
end;

{ The pair loop and the 16-bit tail loop of SysUtils.CompareText.  A target pad reaches through a
  forward jump into the block of that jump, and the jump's own pad - processed first in every
  pass, zero or not - set the prefixes of its block again and wiped the target pad's: the label
  fell back, the target pad asked for more in the next pass, until the block could not carry it
  and everything started over.  Thirteen layout passes, then the change limit froze the target
  pad with 3 of its 5 bytes and a target of the tail loop on byte 62 of its line (rule RT) - with
  every compiler up to the one that keeps the carriers of another pad out of a pad's window. }
function CompareTextLike(const S1, S2: UnicodeString): Integer; noinline;
var
  I, Count, Count1, Count2: SizeInt;
  Chr1, Chr2: Word;
  Pair1, Pair2: Cardinal;
  P1, P2: PWideChar;
begin
  If Pointer(S1) = Pointer(S2) then Exit(0);
  Count1 := Length(S1);
  Count2 := Length(S2);
  If Count1 > Count2 then Count := Count2 else Count := Count1;
  P1 := PWideChar(S1);
  P2 := PWideChar(S2);
  I := 0;
  while I + 1 < Count do
  begin
    Pair1 := PCardinal(@P1[I])^;
    Pair2 := PCardinal(@P2[I])^;
    If Pair1 <> Pair2 then
    begin
      Chr1 := Word(Pair1);
      Chr2 := Word(Pair2);
      If Chr1 <> Chr2 then
      begin
        If (Chr1 >= Ord('a')) and (Chr1 <= Ord('z')) then Dec(Chr1, 32);
        If (Chr2 >= Ord('a')) and (Chr2 <= Ord('z')) then Dec(Chr2, 32);
        If Chr1 <> Chr2 then Exit(Chr1 - Chr2);
      end;
      Chr1 := Pair1 shr 16;
      Chr2 := Pair2 shr 16;
      If Chr1 <> Chr2 then
      begin
        If (Chr1 >= Ord('a')) and (Chr1 <= Ord('z')) then Dec(Chr1, 32);
        If (Chr2 >= Ord('a')) and (Chr2 <= Ord('z')) then Dec(Chr2, 32);
        If Chr1 <> Chr2 then Exit(Chr1 - Chr2);
      end;
    end;
    Inc(I, 2);
  end;
  while I < Count do
  begin
    Chr1 := Word(P1[I]);
    Chr2 := Word(P2[I]);
    If Chr1 <> Chr2 then
    begin
      If (Chr1 >= Ord('a')) and (Chr1 <= Ord('z')) then Dec(Chr1, 32);
      If (Chr2 >= Ord('a')) and (Chr2 <= Ord('z')) then Dec(Chr2, 32);
      If Chr1 <> Chr2 then Exit(Chr1 - Chr2);
    end;
    Inc(I);
  end;
  Result := Count1 - Count2;
end;

var
  I: Integer;
  Slots: array[0..7] of Pointer;
  Texts: TStatic4;
  TextA, TextB: UnicodeString;
begin
  FillChar(Slots, SizeOf(Slots), 0);
  for I := 0 to High(Data) do
    Data[I] := I * 17 + 29;
  for I := 0 to High(Words) do
    Words[I] := Word(I * 7);
  Holder := THolder.Create;
  for I := 0 to High(Holder.Values) do
    Holder.Values[I] := UInt64(I) * 1103515245 + 12345;
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte(I * 37 + 11);
  IncrRefLike(@Slots[0], Length(Slots));
  Texts[0] := 'ab';
  Texts[2] := 'cde';
  Sink := TailJoinLeaf(Texts);
  Sink := ShortLoopSum(4096) + ShortLoopCount(4096) + LongLoopMix(4096) +
    BranchDense(1, 2, 3) + TinyLeaf(5, 9) + TinyLeaf2(4) + AsmAlignedConst(7) +
    TinyLoopHot(3) + LoopOverLine(3) + EncodeLike(1024) + CallLoop(3) +
    SetRangeTests(TSetKind(ParamCount + 1)) + SetRangeTests(TSetKind(ParamCount + 19));
  TextA := 'MoonCompiler placement';
  TextB := 'mooncompiler PLACEMENt';
  If (CompareTextLike(TextA, TextB) <> 0) or (CompareTextLike(TextA, TextB + 'x') >= 0) or
     (CompareTextLike('abd', 'ABC') <= 0) then
  begin
    WriteLn('PLACEMENT_FIXTURE_TEXT_FAIL');
    Halt(1);
  end;
  If (TinyLoopHot(1) <> 36018740757120) or (EncodeLike(1024) <> 1684) then
  begin
    WriteLn('PLACEMENT_FIXTURE_SHAPE_FAIL ', TinyLoopHot(1), ' ', EncodeLike(1024));
    Halt(1);
  end;
  Holder.Free;
  If AsmAlignedConst($ffffffff) <> $fedcba98 then
  begin
    WriteLn('PLACEMENT_FIXTURE_ASM_FAIL');
    Halt(1);
  end;
  If ParamCount > 5 then
    WriteLn(Sink);
  WriteLn('PLACEMENT_FIXTURE_OK');
end.
