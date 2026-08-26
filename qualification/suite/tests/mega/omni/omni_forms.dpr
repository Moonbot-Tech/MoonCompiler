program omni_forms;

{ Deterministic hand-written code-FORM corpus. Companion to mega_test:
  mega_test fuzzes DATA through a fixed set of shapes; this file holds the
  SHAPES the optimizer actually keys on (casts in index position, set ops,
  case lowering, float conversions, Currency, record ABI, COW strings, ...).
  Every check has an independent oracle and a stable kebab-case name, so a
  failure survives minimization and re-verification after a compiler fix.
  Threaded forms use explicit completion barriers and order-independent oracles;
  scheduler-dependent stress already lives in mega_test.
  Compiles unchanged with FPC (-Mdelphi) and Delphi 12.2 Win64; the final
  digest must be identical for every compiler/option tuple. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}{$codepage utf8}
  {$modeswitch advancedrecords}
  {$if FPC_FULLVERSION >= 30301}
    {$modeswitch anonymousfunctions}
    {$modeswitch functionreferences}
    {$define HAS_ANON}
  {$ifend}
  { inline var needs the Unleashed modeswitch; pass -dHAS_INLINEVAR when the
    compiler is an Unleashed build (plain FPC has no INLINEVARS switch) }
  {$ifdef HAS_INLINEVAR}
    {$modeswitch INLINEVARS}
  {$endif}
  {$ifdef TRY_OLEVARIANT_UTF8}
    {$define HAS_OLEVARIANT_UTF8}
  {$endif}
  {$ifdef TRY_VARIANT_RESERVED_MEMBER}
    {$define HAS_VARIANT_RESERVED_MEMBER}
  {$endif}
  {$ifdef TRY_VARIANT_DISTINCT_ORDINAL}
    {$define HAS_VARIANT_DISTINCT_ORDINAL}
  {$endif}
  {$ifdef TRY_DELPHI_EQUALITY_COMPARER}
    {$define HAS_DELPHI_EQUALITY_COMPARER}
  {$endif}
{$else}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
  {$define HAS_OLEVARIANT_UTF8}
  {$define HAS_VARIANT_RESERVED_MEMBER}
  {$define HAS_VARIANT_DISTINCT_ORDINAL}
  {$define HAS_DELPHI_EQUALITY_COMPARER}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  fpmonitor,
{$endif}
  omni_generated_forms_unit,
  omni_generated_breadth_unit,
  omni_conditional_constants,
  omni_mode_delphi_transition,
  omni_moonbot_rtti_subject,
{$if MemoryDebug}
  omni_conditional_must_not_be_used,
{$ifend}
{$if not OmniUnresolvedConditional}
  omni_conditional_not_must_not_be_used,
{$ifend}
  SysUtils, Variants, Classes, Math, TypInfo, Rtti, Generics.Defaults,
  Generics.Collections;

const
  DefaultSeed = UInt64($6D6F6F6E626F7421);
  MaxFailures = 4096;

{ Two accumulators: "core" compiles on every tested compiler including the
  stable references; "modern" additionally needs Delphi-compatibility
  features (anonymous methods, inline var). Core digests must agree across
  ALL compilers; modern digests across the compilers that have the features
  - that comparison IS the fork-vs-Delphi compatibility verdict. }
var
  CoreChecks: Int64 = 0;
  ModernChecks: Int64 = 0;
  CoreDigest: UInt64 = UInt64($CBF29CE484222325);
  ModernDigest: UInt64 = UInt64($CBF29CE484222325);
  ModernMode: Boolean = False;
  RngState: UInt64;
  FailureNames: array[0..MaxFailures - 1] of AnsiString;
  FailureCount: Integer = 0;
  RtZero: UInt64 = 0;      { stays 0 at runtime; opaque to the compiler }

procedure Mix(V: UInt64);
begin
  if ModernMode then
    ModernDigest := (ModernDigest xor V) * UInt64($100000001B3)
  else
    CoreDigest := (CoreDigest xor V) * UInt64($100000001B3);
end;

procedure Check(Cond: Boolean; const Name: AnsiString);
var
  I: Integer;
begin
  if ModernMode then
    Inc(ModernChecks)
  else
    Inc(CoreChecks);
  if Cond then
    Exit;
  for I := 0 to FailureCount - 1 do
    if FailureNames[I] = Name then
      Exit;
  if FailureCount < MaxFailures then
  begin
    FailureNames[FailureCount] := Name;
    Inc(FailureCount);
    WriteLn(AnsiString('FORMS_FAILURE '), Name);
  end;
end;

function Rnd: UInt64;
begin
  RngState := RngState xor (RngState shr 12);
  RngState := RngState xor (RngState shl 25);
  RngState := RngState xor (RngState shr 27);
  Result := RngState * UInt64($2545F4914F6CDD1D);
end;

function OpaqueU(V: UInt64): UInt64;
begin
  Result := V xor RtZero;
end;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor RtZero);
end;

function OpaqueD(V: Double): Double;
var
  B: UInt64;
begin
  Move(V, B, SizeOf(B));
  B := B xor RtZero;
  Move(B, V, SizeOf(V));
  Result := V;
end;

function DoubleBits(D: Double): UInt64;
begin
  Move(D, Result, SizeOf(Result));
end;

function SingleBits(S: Single): UInt32;
begin
  Move(S, Result, SizeOf(Result));
end;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  Check(Actual = Expected, Name);
  Mix(Actual xor (Expected * UInt64($9E3779B97F4A7C15)));
end;

{ ---------------------------------------------------------------- }
{ 1. Narrow-cast / index-position forms.                            }
{ Bug class of SO 38535874 (Delphi XE4): the compiler folded an     }
{ explicit Byte() truncation of an index expression into 32-bit     }
{ address arithmetic and wrote outside the array. The cast IS the   }
{ semantics: it must wrap mod 2^N before indexing.                  }
{ ---------------------------------------------------------------- }

var
  CircS: array[Byte] of Single;
  CircB: array[Byte] of Byte;
  NegArr: array[-128..127] of Integer;
  BasedArr: array[100..355] of Integer;
  WordArr: array[Word] of Byte;

procedure RunNarrowIndexForms;
var
  Ptr, B, Head: Byte;
  I, K, Idx, Widx: Integer;
  W: Word;
begin
  { exact SO 38535874 shape }
  FillChar(CircS, SizeOf(CircS), 0);
  for Ptr := 0 to 10 do
    CircS[Byte(Ptr - 5)] := 1.0;
  for I := 0 to 255 do
  begin
    Idx := 0;
    for K := 0 to 10 do
      if ((K - 5) and 255) = I then
        Idx := 1;
    Check(CircS[I] = Idx * 1.0, 'nix-circular-byte-cast-write');
    Mix(UInt64(Trunc(CircS[I])));
  end;

  { circular buffer machine: every access index goes through Byte() }
  FillChar(CircB, SizeOf(CircB), 0);
  Head := 0;
  for I := 0 to 599 do
  begin
    K := Integer(Rnd mod 21) - 10;
    CircB[Byte(Head + K)] := Byte(I);
    Idx := (Integer(Head) + K) and 255;
    Check(CircB[Idx] = Byte(I), 'nix-circular-byte-cast-rw');
    Head := Byte(Head + Byte(K));
    Check(Integer(Head) >= 0, 'nix-head-domain');
    Mix(Head);
  end;

  { promotion in index position: Byte+Byte indexes past 255 }
  for I := 0 to 199 do
  begin
    B := Byte(Rnd);
    Ptr := Byte(Rnd);
    Widx := Integer(B) + Integer(Ptr);          { oracle: explicit Integer math }
    WordArr[B + Ptr] := Byte(Widx);             { form: promoted sum as index }
    Check(WordArr[Widx] = Byte(Widx), 'nix-promoted-sum-index');
    WordArr[B * Ptr] := Byte(I);
    Check(WordArr[Integer(B) * Integer(Ptr)] = Byte(I), 'nix-promoted-mul-index');
  end;

  { signed narrow index into negative-based array }
  for I := 0 to 255 do
  begin
    B := Byte(I);
    NegArr[ShortInt(B)] := I * 3 + 1;
    Idx := I;
    if Idx >= 128 then
      Idx := Idx - 256;
    Check(NegArr[Idx] = I * 3 + 1, 'nix-shortint-cast-index');
  end;

  { non-zero-based array: base offset folding }
  for I := 0 to 255 do
  begin
    B := Byte(I);
    BasedArr[100 + B] := I xor 77;
    Check(BasedArr[100 + I] = I xor 77, 'nix-based-array-byte-offset');
  end;

  { address-mode folding with logical ops in the index }
  for I := 0 to 199 do
  begin
    B := Byte(Rnd);
    CircB[B xor 3] := Byte(I + 1);
    Check(CircB[Integer(B) xor 3] = Byte(I + 1), 'nix-xor-index');
    CircB[B and $7F] := Byte(I + 2);
    Check(CircB[Integer(B) and $7F] = Byte(I + 2), 'nix-and-index');
    CircB[B shr 1] := Byte(I + 3);
    Check(CircB[Integer(B) shr 1] = Byte(I + 3), 'nix-shr-index');
  end;

  { Word truncation with scaling }
  for I := 0 to 299 do
  begin
    K := Integer(Rnd and $3FFFF);
    W := Word(K * 3 + 7);
    WordArr[Word(K * 3 + 7)] := Byte(K);
    Check(WordArr[(K * 3 + 7) and $FFFF] = Byte(K), 'nix-word-cast-scaled-index');
    Mix(W);
  end;

  { constant-folded cast vs runtime cast must land on the same slot }
  CircB[Byte(-5)] := 111;
  Check(CircB[Byte(OpaqueI(-5))] = 111, 'nix-const-vs-runtime-cast');
  CircB[Byte(300)] := 112;
  Check(CircB[(OpaqueI(300)) and 255] = 112, 'nix-const-cast-300');
  Check(Byte(-5) = 251, 'nix-const-byte-neg5');
  Check(Word(-1) = 65535, 'nix-const-word-neg1');
  Check(UInt32(-1) = $FFFFFFFF, 'nix-const-dword-neg1');
  Check(Byte(OpaqueI(-5)) = 251, 'nix-runtime-byte-neg5');
  Check(Word(OpaqueI(-1)) = 65535, 'nix-runtime-word-neg1');
end;

{ ---------------------------------------------------------------- }
{ 2. Set forms: 256-bit and 32-bit sets vs a boolean-array model.   }
{ ---------------------------------------------------------------- }

type
  TByteSet = set of Byte;
  TSmallSet = set of 0..31;

procedure RunSetForms;
var
  S, T, U: TByteSet;
  SS, ST: TSmallSet;
  Model, ModelT: array[0..255] of Boolean;
  SModel, SModelT: array[0..31] of Boolean;
  I, J, Op, A, B: Integer;
  V: Byte;
  InSet, InModel: Boolean;
begin
  S := [];
  FillChar(Model, SizeOf(Model), 0);
  for I := 0 to 999 do
  begin
    Op := Integer(Rnd mod 6);
    case Op of
      0:
        begin
          V := Byte(Rnd);
          Include(S, V);
          Model[V] := True;
        end;
      1:
        begin
          V := Byte(Rnd);
          Exclude(S, V);
          Model[V] := False;
        end;
      2:
        begin { union with runtime range }
          A := Integer(Rnd and 255);
          B := Integer(Rnd and 255);
          T := [A..B];
          FillChar(ModelT, SizeOf(ModelT), 0);
          for J := A to B do
            ModelT[J] := True;
          S := S + T;
          for J := 0 to 255 do
            Model[J] := Model[J] or ModelT[J];
        end;
      3:
        begin { difference with a computed set }
          T := [];
          FillChar(ModelT, SizeOf(ModelT), 0);
          for J := 0 to 15 do
          begin
            V := Byte(Rnd);
            Include(T, V);
            ModelT[V] := True;
          end;
          S := S - T;
          for J := 0 to 255 do
            Model[J] := Model[J] and not ModelT[J];
        end;
      4:
        begin { intersection }
          A := Integer(Rnd and 255);
          T := [A..255];
          S := S * T;
          for J := 0 to 255 do
            Model[J] := Model[J] and (J >= A);
        end;
      5:
        begin { symmetric difference without >< for Delphi portability }
          T := [];
          FillChar(ModelT, SizeOf(ModelT), 0);
          for J := 0 to 7 do
          begin
            V := Byte(Rnd);
            Include(T, V);
            ModelT[V] := True;
          end;
          U := (S + T) - (S * T);
          S := U;
          for J := 0 to 255 do
            Model[J] := Model[J] xor ModelT[J];
        end;
    end;

    for J := 0 to 7 do
    begin
      V := Byte(Rnd);
      InSet := V in S;
      InModel := Model[V];
      Check(InSet = InModel, 'set-in-probe');
    end;
    if (I and 63) = 0 then
      for J := 0 to 255 do
        Check((Byte(J) in S) = Model[J], 'set-full-sweep');
  end;

  { subset / equality operators against model-computed answers }
  T := S;
  Check(T = S, 'set-equality-self');
  Check(T <= S, 'set-subset-self');
  V := 0;
  while (V < 255) and Model[V] do
    Inc(V);
  if not Model[V] then
  begin
    Include(T, V);
    Check(T <> S, 'set-inequality-after-include');
    Check(S <= T, 'set-subset-proper');
    Check(not (T <= S), 'set-not-subset-reverse');
  end;

  { reversed runtime range must be empty }
  A := 200;
  B := 100;
  T := [A..B];
  Check(T = [], 'set-range-reversed-empty');

  { 32-bit set: register-sized codegen path }
  SS := [];
  FillChar(SModel, SizeOf(SModel), 0);
  for I := 0 to 499 do
  begin
    Op := Integer(Rnd mod 4);
    A := Integer(Rnd and 31);
    B := Integer(Rnd and 31);
    case Op of
      0:
        begin
          Include(SS, A);
          SModel[A] := True;
        end;
      1:
        begin
          Exclude(SS, A);
          SModel[A] := False;
        end;
      2:
        begin
          if A > B then
          begin
            J := A;
            A := B;
            B := J;
          end;
          ST := [A..B];
          FillChar(SModelT, SizeOf(SModelT), 0);
          for J := A to B do
            SModelT[J] := True;
          SS := SS + ST;
          for J := 0 to 31 do
            SModel[J] := SModel[J] or SModelT[J];
        end;
      3:
        begin
          ST := [A];
          SS := SS - ST;
          SModel[A] := False;
        end;
    end;
    for J := 0 to 31 do
      Check((J in SS) = SModel[J], 'set-small-sweep');
  end;
end;

{ ---------------------------------------------------------------- }
{ 3. Case-statement lowering: dense (jump table), sparse (compare   }
{ chains / binary search), ranges, Int64 selectors with 2^32 span,  }
{ and a narrowing cast in the selector.                             }
{ ---------------------------------------------------------------- }

function CaseDense(V: Integer): Integer;
begin
  case V of
    0: Result := 101;
    1: Result := 103;
    2: Result := 107;
    3: Result := 109;
    4: Result := 113;
    5: Result := 127;
    6: Result := 131;
    7: Result := 137;
    8: Result := 139;
    9: Result := 149;
    10: Result := 151;
    11: Result := 157;
    12: Result := 163;
    13: Result := 167;
    14: Result := 173;
    15: Result := 179;
  else
    Result := -1;
  end;
end;

function CaseDenseOracle(V: Integer): Integer;
const
  Primes: array[0..15] of Integer =
    (101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179);
begin
  if (V >= 0) and (V <= 15) then
    Result := Primes[V]
  else
    Result := -1;
end;

function CaseSparse(V: Integer): Integer;
begin
  case V of
    -1000: Result := 1;
    -700: Result := 2;
    -333: Result := 3;
    -1: Result := 4;
    0: Result := 5;
    1: Result := 6;
    17: Result := 7;
    100: Result := 8;
    255: Result := 9;
    256: Result := 10;
    999: Result := 11;
    1000: Result := 12;
  else
    Result := 0;
  end;
end;

function CaseSparseOracle(V: Integer): Integer;
begin
  if V = -1000 then Result := 1
  else if V = -700 then Result := 2
  else if V = -333 then Result := 3
  else if V = -1 then Result := 4
  else if V = 0 then Result := 5
  else if V = 1 then Result := 6
  else if V = 17 then Result := 7
  else if V = 100 then Result := 8
  else if V = 255 then Result := 9
  else if V = 256 then Result := 10
  else if V = 999 then Result := 11
  else if V = 1000 then Result := 12
  else Result := 0;
end;

function CaseRanges(V: Integer): Integer;
begin
  case V of
    -1050..-1000: Result := 21;
    -999..-100: Result := 22;
    -99..-1: Result := 23;
    0: Result := 24;
    1..9: Result := 25;
    10..99: Result := 26;
    100..999: Result := 27;
    1000..1049: Result := 28;
  else
    Result := 20;
  end;
end;

function CaseRangesOracle(V: Integer): Integer;
begin
  if (V >= -1050) and (V <= -1000) then Result := 21
  else if (V >= -999) and (V <= -100) then Result := 22
  else if (V >= -99) and (V <= -1) then Result := 23
  else if V = 0 then Result := 24
  else if (V >= 1) and (V <= 9) then Result := 25
  else if (V >= 10) and (V <= 99) then Result := 26
  else if (V >= 100) and (V <= 999) then Result := 27
  else if (V >= 1000) and (V <= 1049) then Result := 28
  else Result := 20;
end;

{ Delphi restricts case labels to 32-bit values, so the labels stay inside
  Integer range while the SELECTOR is a full Int64. A selector equal to a
  label plus k*2^32 must fall into else: truncating the selector to 32 bits
  before dispatch is exactly the bug this form hunts. }
function CaseInt64(V: Int64): Integer;
begin
  case V of
    -2147483648: Result := 31;
    -1000000: Result := 32;
    -1: Result := 33;
    0: Result := 34;
    1: Result := 35;
    1000000: Result := 36;
    2147483647: Result := 37;
  else
    Result := 30;
  end;
end;

function CaseInt64Oracle(V: Int64): Integer;
begin
  if V = -2147483648 then Result := 31
  else if V = -1000000 then Result := 32
  else if V = -1 then Result := 33
  else if V = 0 then Result := 34
  else if V = 1 then Result := 35
  else if V = 1000000 then Result := 36
  else if V = 2147483647 then Result := 37
  else Result := 30;
end;

function CaseNarrowSelector(V: Integer): Integer;
begin
  case Byte(V) of              { the cast is the semantics: mod 256 first }
    0..15: Result := 51;
    16..127: Result := 52;
    128..254: Result := 53;
  else
    Result := 54;
  end;
end;

function CaseNarrowSelectorOracle(V: Integer): Integer;
var
  B: Integer;
begin
  B := V and 255;
  if B <= 15 then Result := 51
  else if B <= 127 then Result := 52
  else if B <= 254 then Result := 53
  else Result := 54;
end;

procedure RunCaseForms;
const
  Int64Probes: array[0..15] of Int64 = (
    -2147483649, -2147483648, -2147483647, -1000000, -1, 0, 1, 1000000,
    2147483646, 2147483647, 2147483648,
    { 32-bit aliases of real labels: label + k*2^32 must miss }
    4294967296, 4294967297, 4295967296, -4294967297, 9000000000000000000);
var
  I, V: Integer;
  V64: Int64;
begin
  { boundary sweep +- around every label region plus random probes }
  for V := -1100 to 1100 do
  begin
    Check(CaseDense(V) = CaseDenseOracle(V), 'case-dense-jump-table');
    Check(CaseSparse(V) = CaseSparseOracle(V), 'case-sparse-chain');
    Check(CaseRanges(V) = CaseRangesOracle(V), 'case-range-lowering');
  end;
  for I := 0 to 499 do
  begin
    V := Integer(Rnd);
    Check(CaseSparse(V) = CaseSparseOracle(V), 'case-sparse-random');
    Check(CaseRanges(V) = CaseRangesOracle(V), 'case-range-random');
    Check(CaseNarrowSelector(V) = CaseNarrowSelectorOracle(V),
      'case-narrow-cast-selector');
    Mix(UInt64(UInt32(CaseSparse(V) * 31 + CaseRanges(V))));
  end;
  for I := 0 to High(Int64Probes) do
  begin
    V64 := Int64Probes[I];
    Check(CaseInt64(V64) = CaseInt64Oracle(V64), 'case-int64-span');
  end;
  for I := 0 to 299 do
  begin
    V64 := Int64(Rnd);
    Check(CaseInt64(V64) = CaseInt64Oracle(V64), 'case-int64-random');
  end;
end;

{ ---------------------------------------------------------------- }
{ 4. Float conversion forms. All operands are constructed by exact  }
{ Double arithmetic (doubling/halving chains); expectations are     }
{ either exact identities or precomputed IEEE-754 bit patterns.     }
{ ---------------------------------------------------------------- }

procedure RunFloatConvForms;
var
  Pow2: array[0..64] of Double;    { exact 2^k }
  D, E, X, Y, R, MinNormal, Den: Double;
  S: Single;
  Q: UInt64;
  V64: Int64;
  I: Integer;
begin
  Pow2[0] := 1.0;
  for I := 1 to 64 do
    Pow2[I] := Pow2[I - 1] * 2.0;

  { banker's rounding at exact halves }
  Check(Round(0.5) = 0, 'fconv-round-half-0');
  Check(Round(1.5) = 2, 'fconv-round-half-1');
  Check(Round(2.5) = 2, 'fconv-round-half-2');
  Check(Round(3.5) = 4, 'fconv-round-half-3');
  Check(Round(-0.5) = 0, 'fconv-round-half-neg0');
  Check(Round(-1.5) = -2, 'fconv-round-half-neg1');
  Check(Round(-2.5) = -2, 'fconv-round-half-neg2');
  Check(Round(OpaqueI(5) + 0.5) = 6, 'fconv-round-half-runtime');
  { largest double below 0.5 must round to 0 }
  Q := UInt64($3FDFFFFFFFFFFFFF);
  Move(Q, D, SizeOf(D));
  Check(Round(D) = 0, 'fconv-round-below-half');
  { 2^52 - 0.5 is representable; ties-to-even goes up to 2^52 }
  D := Pow2[52] - 0.5;
  Check(Round(D) = Int64(1) shl 52, 'fconv-round-2p52-half');
  Check(Trunc(D) = (Int64(1) shl 52) - 1, 'fconv-trunc-2p52-half');

  { Trunc toward zero }
  Check(Trunc(2.9) = 2, 'fconv-trunc-pos');
  Check(Trunc(-2.9) = -2, 'fconv-trunc-neg');
  Check(Int(2.5) = 2.0, 'fconv-int-pos');
  Check(Int(-2.5) = -2.0, 'fconv-int-neg');
  Check(Frac(2.5) = 0.5, 'fconv-frac-pos');
  Check(Frac(-2.5) = -0.5, 'fconv-frac-neg');
  Check(Frac(Pow2[51] + 0.5) = 0.5, 'fconv-frac-2p51');

  { Trunc at the top of the Int64 domain: 2^63 - 1024 is the largest
    representable double below High(Int64) }
  D := Pow2[63] - Pow2[10];
  Check(Trunc(D) = Int64($7FFFFFFFFFFFFC00), 'fconv-trunc-top-int64');
  D := -Pow2[63];
  Check(Trunc(D) = Low(Int64), 'fconv-trunc-low-int64');

  { Int64 -> Double rounding }
  V64 := (Int64(1) shl 53) + 1;
  D := V64;
  Check(DoubleBits(D) = DoubleBits(Pow2[53]), 'fconv-int64-to-double-2p53p1');
  V64 := (Int64(1) shl 53) + 3;
  D := V64;
  Check(DoubleBits(D) = DoubleBits(Pow2[53] + 4.0), 'fconv-int64-to-double-tie-even');
  V64 := High(Int64);
  D := V64;
  Check(DoubleBits(D) = DoubleBits(Pow2[63]), 'fconv-int64-to-double-high');
  V64 := Low(Int64);
  D := V64;
  Check(DoubleBits(D) = DoubleBits(-Pow2[63]), 'fconv-int64-to-double-low');

  { UInt64 -> Double: values above 2^63 exercise the compiler's unsigned
    fixup path (x86-64 has no unsigned convert before AVX-512) }
  Q := UInt64(1) shl 63;
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[63]), 'fconv-uint64-to-double-2p63');
  Q := (UInt64(1) shl 63) + 2048;
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[63] + 2048.0), 'fconv-uint64-to-double-exact');
  Q := (UInt64(1) shl 63) + 1024;
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[63]), 'fconv-uint64-to-double-tie-down');
  Q := (UInt64(1) shl 63) + 3072;
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[63] + 4096.0), 'fconv-uint64-to-double-tie-up');
  Q := UInt64($FFFFFFFFFFFFFFFF);
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[64]), 'fconv-uint64-to-double-max');
  Q := OpaqueU((UInt64(1) shl 63) + 1024);
  D := Q;
  Check(DoubleBits(D) = DoubleBits(Pow2[63]), 'fconv-uint64-to-double-runtime');

  { Single <-> Double }
  V64 := (Int64(1) shl 24) + 1;
  S := V64;
  Check(SingleBits(S) = $4B800000, 'fconv-int-to-single-2p24p1');
  D := 1.0 + Pow2[0] / Pow2[24];               { 1 + 2^-24, exact }
  S := D;
  Check(SingleBits(S) = $3F800000, 'fconv-double-to-single-tie-down');
  D := 1.0 + 3.0 / Pow2[24];                   { 1 + 3*2^-24, exact }
  S := D;
  Check(SingleBits(S) = $3F800002, 'fconv-double-to-single-tie-up');
  S := 1.5;
  D := S;
  Check(DoubleBits(D) = DoubleBits(1.5), 'fconv-single-to-double-exact');

  { negative zero }
  D := 0.0;
  E := -D;
  Check(DoubleBits(E) = UInt64($8000000000000000), 'fconv-negzero-bits');
  Check(E = 0.0, 'fconv-negzero-equals-zero');
  D := OpaqueI(0);
  E := -D;
  Check(DoubleBits(E) = UInt64($8000000000000000), 'fconv-negzero-runtime');

  { gradual underflow: denormals with default MXCSR }
  MinNormal := 1.0;
  for I := 1 to 1022 do
    MinNormal := MinNormal * 0.5;
  Check(DoubleBits(MinNormal) = UInt64($0010000000000000), 'fconv-min-normal-bits');
  Den := MinNormal * 0.5;
  Check(DoubleBits(Den) = UInt64($0008000000000000), 'fconv-denormal-half');
  Check(Den * 2.0 = MinNormal, 'fconv-denormal-double-back');
  Den := MinNormal;
  for I := 1 to 52 do
    Den := Den * 0.5;
  Check(DoubleBits(Den) = UInt64(1), 'fconv-smallest-denormal');
  Den := Den * 0.5;
  Check(DoubleBits(Den) = 0, 'fconv-underflow-to-zero');

  { FMA contraction sentinel: x*y rounds to exactly 1.0 without FMA }
  E := 1.0;
  for I := 1 to 29 do
    E := E * 0.5;
  X := 1.0 + E;
  Y := 2.0 - X;
  R := X * Y - 1.0;
  Check(R = 0.0, 'fconv-no-fma-contraction');

  { literal parsing vs constructed value }
  Check(DoubleBits(0.1) = UInt64($3FB999999999999A), 'fconv-literal-tenth-bits');
  Check(DoubleBits(1E308) = UInt64($7FE1CCF385EBC8A0), 'fconv-literal-1e308-bits');
  Mix(DoubleBits(MinNormal));
  Mix(DoubleBits(X));
end;

{ ---------------------------------------------------------------- }
{ 5. Currency forms: fixed-point Int64 scaled by 10000. The oracle  }
{ is explicit Int64 arithmetic on the scaled representation; only   }
{ remainder-free multiplications/divisions are used so the checks   }
{ are exact regardless of the compiler's rounding choice.           }
{ ---------------------------------------------------------------- }

function CurrencyRaw(const C: Currency): Int64;
begin
  Result := PInt64(@C)^;
end;

procedure RunCurrencyForms;
var
  A, B, C, Sum: Currency;
  ModelA, ModelB: Int64;
  I, K: Integer;
  Arr: array[0..99] of Currency;
begin
  { literal scaling }
  A := 0.0001;
  Check(CurrencyRaw(A) = 1, 'curr-literal-min-step');
  A := 1;
  Check(CurrencyRaw(A) = 10000, 'curr-int-assign-scale');
  A := 12345.6789;
  Check(CurrencyRaw(A) = 123456789, 'curr-literal-scale');
  A := -0.42;
  Check(CurrencyRaw(A) = -4200, 'curr-literal-negative');

  { the classic decimal-exactness loop: 10000 * 0.0001 = 1 exactly.
    If any op is silently lowered through binary floating point and back,
    exactness breaks. }
  Sum := 0;
  for I := 1 to 10000 do
    Sum := Sum + 0.0001;
  Check(CurrencyRaw(Sum) = 10000, 'curr-sum-min-step-exact');
  Check(Sum = 1, 'curr-sum-equals-one');

  { random add/sub/mul-by-int machine against a scaled Int64 model }
  A := 0;
  ModelA := 0;
  for I := 0 to 799 do
  begin
    K := Integer(Rnd mod 200001) - 100000;      { -10.0000 .. +10.0000 }
    B := K;
    ModelB := Int64(K) * 10000;
    B := B / 10000;                              { exact: raw K }
    ModelB := ModelB div 10000;
    Check(CurrencyRaw(B) = ModelB, 'curr-div-pow10-exact');
    case Rnd mod 3 of
      0:
        begin
          A := A + B;
          ModelA := ModelA + ModelB;
        end;
      1:
        begin
          A := A - B;
          ModelA := ModelA - ModelB;
        end;
      2:
        begin
          K := Integer(Rnd mod 21) - 10;
          A := A + B * K;
          ModelA := ModelA + ModelB * K;
        end;
    end;
    Check(CurrencyRaw(A) = ModelA, 'curr-machine-raw');
    Mix(UInt64(ModelA));
  end;

  { remainder-free Currency * Currency and division }
  A := 2.5;
  B := 4;
  C := A * B;
  Check(CurrencyRaw(C) = 100000, 'curr-mul-exact');
  C := A * A;
  Check(CurrencyRaw(C) = 62500, 'curr-mul-curr-exact');
  C := 7.5;
  B := C / 3;
  Check(CurrencyRaw(B) = 25000, 'curr-div-exact');
  A := 0.0002;
  C := A * 0.5;
  Check(CurrencyRaw(C) = 1, 'curr-mul-half-min');

  { comparisons and negation }
  A := 3.1415;
  B := 3.1416;
  Check(A < B, 'curr-compare-lt');
  Check(-A > -B, 'curr-compare-neg');
  Check(Abs(-A) = A, 'curr-abs');
  Check(Trunc(A) = 3, 'curr-trunc');
  Check(Trunc(-A) = -3, 'curr-trunc-neg');

  { array traversal }
  ModelA := 0;
  for I := 0 to 99 do
  begin
    K := Integer(Rnd mod 2000001) - 1000000;
    Arr[I] := K;
    Arr[I] := Arr[I] / 10000;
    ModelA := ModelA + K;
  end;
  Sum := 0;
  for I := 0 to 99 do
    Sum := Sum + Arr[I];
  Check(CurrencyRaw(Sum) = ModelA, 'curr-array-sum');
end;

{ ---------------------------------------------------------------- }
{ 6. Record ABI forms: by-value passing, by-value mutation          }
{ isolation, and record function results for odd sizes, plus mixed  }
{ float/int layouts and cdecl variants (SysV / MS x64 class paths). }
{ ---------------------------------------------------------------- }

type
  TRec01 = packed record B: array[0..0] of Byte; end;
  TRec03 = packed record B: array[0..2] of Byte; end;
  TRec05 = packed record B: array[0..4] of Byte; end;
  TRec07 = packed record B: array[0..6] of Byte; end;
  TRec08 = packed record B: array[0..7] of Byte; end;
  TRec09 = packed record B: array[0..8] of Byte; end;
  TRec12 = packed record B: array[0..11] of Byte; end;
  TRec16 = packed record B: array[0..15] of Byte; end;
  TRec17 = packed record B: array[0..16] of Byte; end;
  TRec24 = packed record B: array[0..23] of Byte; end;
  TRec32 = packed record B: array[0..31] of Byte; end;
  TRec33 = packed record B: array[0..32] of Byte; end;

  TTwoSingles = record A, B: Single; end;
  TSingleInt = record S: Single; I: Integer; end;
  TDoubleInt = record D: Double; I: Int64; end;
  TIntDouble = record I: Integer; D: Double; end;   { alignment hole }
  TFourSingles = record A, B, C, D: Single; end;

function SumByVal01(R: TRec01; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make01(Seed: Integer): TRec01;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal03(R: TRec03; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make03(Seed: Integer): TRec03;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal05(R: TRec05; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make05(Seed: Integer): TRec05;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal07(R: TRec07; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make07(Seed: Integer): TRec07;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal08(R: TRec08; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make08(Seed: Integer): TRec08;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal09(R: TRec09; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make09(Seed: Integer): TRec09;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal12(R: TRec12; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make12(Seed: Integer): TRec12;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal16(R: TRec16; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make16(Seed: Integer): TRec16;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal17(R: TRec17; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make17(Seed: Integer): TRec17;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal24(R: TRec24; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make24(Seed: Integer): TRec24;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal32(R: TRec32; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make32(Seed: Integer): TRec32;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function SumByVal33(R: TRec33; Salt: Integer): Integer;
var K: Integer;
begin
  Result := 0;
  for K := 0 to High(R.B) do Inc(Result, R.B[K] * (K + 1));
  for K := 0 to High(R.B) do R.B[K] := Byte(Salt);
end;

function Make33(Seed: Integer): TRec33;
var K: Integer;
begin
  for K := 0 to High(Result.B) do Result.B[K] := Byte(Seed * 13 + K * 11 + 1);
end;

function AddTwoSingles(P: TTwoSingles; Q: TTwoSingles): TTwoSingles;
begin
  Result.A := P.A + Q.A;
  Result.B := P.B + Q.B;
end;

function AddTwoSinglesC(P: TTwoSingles; Q: TTwoSingles): TTwoSingles; cdecl;
begin
  Result.A := P.A + Q.A;
  Result.B := P.B + Q.B;
end;

function MixSingleInt(R: TSingleInt): TSingleInt;
begin
  Result.S := R.S * 2.0;
  Result.I := R.I + 7;
end;

function MixDoubleInt(R: TDoubleInt): TDoubleInt; cdecl;
begin
  Result.D := R.D + 1.5;
  Result.I := R.I xor 255;
end;

function MixIntDouble(R: TIntDouble): TIntDouble;
begin
  Result.I := R.I - 3;
  Result.D := R.D * 0.5;
end;

function SumFourSingles(R: TFourSingles): Single; cdecl;
begin
  Result := R.A + R.B + R.C + R.D;
end;

function ByteOracleSum(Seed, Count: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 0 to Count - 1 do
    Inc(Result, Byte(Seed * 31 + K * 7 + 3) * (K + 1));
end;

procedure RunRecordAbiForms;
var
  R01: TRec01; R03: TRec03; R05: TRec05; R07: TRec07; R08: TRec08;
  R09: TRec09; R12: TRec12; R16: TRec16; R17: TRec17; R24: TRec24;
  R32: TRec32; R33: TRec33;
  TS, TT, TU: TTwoSingles;
  SI: TSingleInt;
  DI: TDoubleInt;
  ID: TIntDouble;
  FS: TFourSingles;
  Seed, K, Sum: Integer;

  procedure CheckMade(const B: array of Byte; Seed: Integer; const Name: AnsiString);
  var
    K: Integer;
  begin
    for K := 0 to High(B) do
      Check(B[K] = Byte(Seed * 13 + K * 11 + 1), Name);
  end;

  procedure FillPattern(var B: array of Byte; Seed: Integer);
  var
    K: Integer;
  begin
    for K := 0 to High(B) do
      B[K] := Byte(Seed * 31 + K * 7 + 3);
  end;

  procedure CheckIntact(const B: array of Byte; Seed: Integer; const Name: AnsiString);
  var
    K: Integer;
  begin
    for K := 0 to High(B) do
      Check(B[K] = Byte(Seed * 31 + K * 7 + 3), Name);
  end;

begin
  Seed := Integer(Rnd and $FFFF);

  FillPattern(R01.B, Seed);
  Sum := SumByVal01(R01, 90);
  Check(Sum = ByteOracleSum(Seed, 1), 'abi-byval-sum-01');
  CheckIntact(R01.B, Seed, 'abi-byval-intact-01');
  R01 := Make01(Seed);
  CheckMade(R01.B, Seed, 'abi-result-01');

  FillPattern(R03.B, Seed);
  Sum := SumByVal03(R03, 90);
  Check(Sum = ByteOracleSum(Seed, 3), 'abi-byval-sum-03');
  CheckIntact(R03.B, Seed, 'abi-byval-intact-03');
  R03 := Make03(Seed);
  CheckMade(R03.B, Seed, 'abi-result-03');

  FillPattern(R05.B, Seed);
  Sum := SumByVal05(R05, 90);
  Check(Sum = ByteOracleSum(Seed, 5), 'abi-byval-sum-05');
  CheckIntact(R05.B, Seed, 'abi-byval-intact-05');
  R05 := Make05(Seed);
  CheckMade(R05.B, Seed, 'abi-result-05');

  FillPattern(R07.B, Seed);
  Sum := SumByVal07(R07, 90);
  Check(Sum = ByteOracleSum(Seed, 7), 'abi-byval-sum-07');
  CheckIntact(R07.B, Seed, 'abi-byval-intact-07');
  R07 := Make07(Seed);
  CheckMade(R07.B, Seed, 'abi-result-07');

  FillPattern(R08.B, Seed);
  Sum := SumByVal08(R08, 90);
  Check(Sum = ByteOracleSum(Seed, 8), 'abi-byval-sum-08');
  CheckIntact(R08.B, Seed, 'abi-byval-intact-08');
  R08 := Make08(Seed);
  CheckMade(R08.B, Seed, 'abi-result-08');

  FillPattern(R09.B, Seed);
  Sum := SumByVal09(R09, 90);
  Check(Sum = ByteOracleSum(Seed, 9), 'abi-byval-sum-09');
  CheckIntact(R09.B, Seed, 'abi-byval-intact-09');
  R09 := Make09(Seed);
  CheckMade(R09.B, Seed, 'abi-result-09');

  FillPattern(R12.B, Seed);
  Sum := SumByVal12(R12, 90);
  Check(Sum = ByteOracleSum(Seed, 12), 'abi-byval-sum-12');
  CheckIntact(R12.B, Seed, 'abi-byval-intact-12');
  R12 := Make12(Seed);
  CheckMade(R12.B, Seed, 'abi-result-12');

  FillPattern(R16.B, Seed);
  Sum := SumByVal16(R16, 90);
  Check(Sum = ByteOracleSum(Seed, 16), 'abi-byval-sum-16');
  CheckIntact(R16.B, Seed, 'abi-byval-intact-16');
  R16 := Make16(Seed);
  CheckMade(R16.B, Seed, 'abi-result-16');

  FillPattern(R17.B, Seed);
  Sum := SumByVal17(R17, 90);
  Check(Sum = ByteOracleSum(Seed, 17), 'abi-byval-sum-17');
  CheckIntact(R17.B, Seed, 'abi-byval-intact-17');
  R17 := Make17(Seed);
  CheckMade(R17.B, Seed, 'abi-result-17');

  FillPattern(R24.B, Seed);
  Sum := SumByVal24(R24, 90);
  Check(Sum = ByteOracleSum(Seed, 24), 'abi-byval-sum-24');
  CheckIntact(R24.B, Seed, 'abi-byval-intact-24');
  R24 := Make24(Seed);
  CheckMade(R24.B, Seed, 'abi-result-24');

  FillPattern(R32.B, Seed);
  Sum := SumByVal32(R32, 90);
  Check(Sum = ByteOracleSum(Seed, 32), 'abi-byval-sum-32');
  CheckIntact(R32.B, Seed, 'abi-byval-intact-32');
  R32 := Make32(Seed);
  CheckMade(R32.B, Seed, 'abi-result-32');

  FillPattern(R33.B, Seed);
  Sum := SumByVal33(R33, 90);
  Check(Sum = ByteOracleSum(Seed, 33), 'abi-byval-sum-33');
  CheckIntact(R33.B, Seed, 'abi-byval-intact-33');
  R33 := Make33(Seed);
  CheckMade(R33.B, Seed, 'abi-result-33');

  { float / mixed layouts through register-classified paths }
  TS.A := 1.5; TS.B := -2.25;
  TT.A := 0.25; TT.B := 4.0;
  TU := AddTwoSingles(TS, TT);
  Check((TU.A = 1.75) and (TU.B = 1.75), 'abi-two-singles');
  TU := AddTwoSinglesC(TS, TT);
  Check((TU.A = 1.75) and (TU.B = 1.75), 'abi-two-singles-cdecl');

  SI.S := 3.5; SI.I := 41;
  SI := MixSingleInt(SI);
  Check((SI.S = 7.0) and (SI.I = 48), 'abi-single-int-mix');

  DI.D := 2.25; DI.I := $F0F0;
  DI := MixDoubleInt(DI);
  Check((DI.D = 3.75) and (DI.I = ($F0F0 xor 255)), 'abi-double-int64-cdecl');

  ID.I := 100; ID.D := 5.5;
  ID := MixIntDouble(ID);
  Check((ID.I = 97) and (ID.D = 2.75), 'abi-int-double-hole');

  FS.A := 1.0; FS.B := 2.0; FS.C := 3.0; FS.D := 4.5;
  Check(SumFourSingles(FS) = 10.5, 'abi-four-singles-cdecl');

  for K := 0 to 15 do
  begin
    R17 := Make17(K);
    CheckMade(R17.B, K, 'abi-result-17-sweep');
  end;
end;

{ ---------------------------------------------------------------- }
{ 7. Wide-op forms: variable shifts, full-range signed div/mod via  }
{ a binary long-division oracle, mul-low decomposition, and the     }
{ constant-vs-runtime divisor differential (magic-multiply path vs  }
{ idiv path must agree).                                            }
{ ---------------------------------------------------------------- }

procedure OracleDivMod64(V, D: Int64; out Q, R: Int64);
var
  MagV, MagD, QM, RM: UInt64;
  Shift: Integer;
begin
  if V < 0 then
    MagV := UInt64(-V)
  else
    MagV := UInt64(V);
  if D < 0 then
    MagD := UInt64(-D)
  else
    MagD := UInt64(D);
  QM := 0;
  RM := MagV;
  for Shift := 63 downto 0 do
    if (RM shr Shift) >= MagD then
    begin
      RM := RM - (MagD shl Shift);
      QM := QM or (UInt64(1) shl Shift);
    end;
  if (V < 0) xor (D < 0) then
    Q := -Int64(QM)
  else
    Q := Int64(QM);
  if V < 0 then
    R := -Int64(RM)
  else
    R := Int64(RM);
end;

function OracleMulLow(A, B: UInt64): UInt64;
var
  AL, AH, BL, BH: UInt64;
begin
  AL := A and $FFFFFFFF;
  AH := A shr 32;
  BL := B and $FFFFFFFF;
  BH := B shr 32;
  Result := AL * BL + ((AL * BH + AH * BL) shl 32);
end;

function ShlByDoubling(V: UInt64; Count: Integer): UInt64;
var
  K: Integer;
begin
  Result := V;
  for K := 1 to Count do
    Result := Result + Result;
end;

procedure RunWideOpForms;
const
  Divisors: array[0..13] of Int64 =
    (1, -1, 2, -2, 3, -3, 7, -7, 10, -10, 10000, -10000, 86400000, 1000000007);
var
  I, J, C: Integer;
  V, D, Q, R, OQ, ORem: Int64;
  U, HalfWalk, UQ, UR: UInt64;
begin
  { variable shift count vs doubling chain }
  for I := 0 to 49 do
  begin
    U := Rnd;
    for C := 0 to 63 do
    begin
      Check(U shl C = ShlByDoubling(U, C), 'wop-var-shl');
      HalfWalk := U;
      for J := 1 to C do
        HalfWalk := HalfWalk div 2;
      Check(U shr C = HalfWalk, 'wop-var-shr');
    end;
  end;

  { narrow shifts promote to Integer before shifting }
  for I := 0 to 199 do
  begin
    C := Integer(Rnd and 7);
    J := Integer(Rnd and $FF);
    Check(Byte(J) shl C = (J shl C), 'wop-byte-shl-promoted');
    Check(Byte(Byte(J) shl C) = ((J shl C) and $FF), 'wop-byte-shl-truncated');
  end;

  { full-range signed div/mod by runtime divisors }
  for I := 0 to 999 do
  begin
    V := Int64(Rnd);
    D := Divisors[Integer(Rnd mod UInt64(Length(Divisors)))];
    if (V = Low(Int64)) and (D = -1) then
      Continue;                                  { the one genuinely invalid pair }
    Q := V div OpaqueI(D);
    R := V mod OpaqueI(D);
    OracleDivMod64(V, D, OQ, ORem);
    Check(Q = OQ, 'wop-div-variable-oracle');
    Check(R = ORem, 'wop-mod-variable-oracle');
    Check(Q * D + R = V, 'wop-divmod-recomposition');

    { same divisor as a compile-time constant: magic-multiply path must
      agree with the idiv path and with the oracle }
    case D of
      10000:
        begin
          Check(V div 10000 = OQ, 'wop-div-const-10000');
          Check(V mod 10000 = ORem, 'wop-mod-const-10000');
        end;
      -10000:
        begin
          Check(V div -10000 = OQ, 'wop-div-const-neg10000');
          Check(V mod -10000 = ORem, 'wop-mod-const-neg10000');
        end;
      86400000:
        begin
          Check(V div 86400000 = OQ, 'wop-div-const-86400000');
          Check(V mod 86400000 = ORem, 'wop-mod-const-86400000');
        end;
      1000000007:
        begin
          Check(V div 1000000007 = OQ, 'wop-div-const-1000000007');
        end;
      3:
        Check(V div 3 = OQ, 'wop-div-const-3');
      -3:
        Check(V div -3 = OQ, 'wop-div-const-neg3');
      7:
        Check(V div 7 = OQ, 'wop-div-const-7');
      -7:
        Check(V div -7 = OQ, 'wop-div-const-neg7');
    end;
  end;

  { negative dividends over power-of-two constants: sar+adjust path }
  for I := 0 to 499 do
  begin
    V := Int64(Rnd);
    OracleDivMod64(V, 2, Q, R);
    Check(V div 2 = Q, 'wop-div-const-2');
    Check(V mod 2 = R, 'wop-mod-const-2');
    OracleDivMod64(V, 1024, Q, R);
    Check(V div 1024 = Q, 'wop-div-const-1024');
    Check(V mod 1024 = R, 'wop-mod-const-1024');
    OracleDivMod64(V, -4, Q, R);
    Check(V div -4 = Q, 'wop-div-const-neg4');
    Check(V mod -4 = R, 'wop-mod-const-neg4');
  end;

  { 64x64 multiply low half vs 32-bit decomposition }
  for I := 0 to 999 do
  begin
    V := Int64(Rnd);
    D := Int64(Rnd);
    Check(UInt64(V * D) = OracleMulLow(UInt64(V), UInt64(D)),
      'wop-mul-low-decomposition');
    Mix(UInt64(V * D));
  end;

  { unsigned division: recomposition plus the div-by-pow2 == shr identity
    (two different lowerings of the same value) }
  for I := 0 to 499 do
  begin
    U := Rnd;
    HalfWalk := (Rnd and $FFFFFFFF) + 1;
    Check((U div HalfWalk) * HalfWalk + (U mod HalfWalk) = U,
      'wop-udiv-recomposition');
    Check(U mod HalfWalk < HalfWalk, 'wop-umod-range');
    Check(U div 1024 = U shr 10, 'wop-udiv-pow2-shr');
    Check(U mod 1024 = (U and 1023), 'wop-umod-pow2-and');
    DivMod(U, HalfWalk, UQ, UR);
    Check(UQ = U div HalfWalk, 'wop-divmod-u64-quotient');
    Check(UR = U mod HalfWalk, 'wop-divmod-u64-remainder');
  end;
  DivMod(High(UInt64), UInt64(10), UQ, UR);
  Check(UQ = UInt64(1844674407370955161), 'wop-divmod-u64-high-quotient');
  Check(UR = 5, 'wop-divmod-u64-high-remainder');
end;

{ ---------------------------------------------------------------- }
{ 8. Managed-string copy-on-write and self-aliasing forms.          }
{ ---------------------------------------------------------------- }

var
  GlobalStr: AnsiString;

procedure WriteFirstChar(var S: AnsiString);
begin
  S[1] := '!';
  Check(GlobalStr[1] = '!', 'cow-var-param-alias-visible');
end;

procedure RunStringCowForms;
var
  A, B, C: AnsiString;
  UA, UB: UnicodeString;
  Short255: ShortString;
  Cap10: string[10];
  I: Integer;
begin
  { unshare on indexed write; the source must stay intact }
  B := 'abcdefgh';
  UniqueString(B);                               { B refcount 1, mutable }
  A := B;                                        { shared }
  A[3] := 'X';
  Check(A = 'abXdefgh', 'cow-write-target');
  Check(B = 'abcdefgh', 'cow-source-intact');

  { literal-backed source }
  A := 'constant';
  B := A;
  B[1] := 'K';
  Check(B = 'Konstant', 'cow-literal-target');
  Check(A = 'constant', 'cow-literal-intact');

  { indexed writes inside a loop: uniqueness must hold under hoisting }
  B := '0123456789';
  UniqueString(B);
  A := B;
  for I := 1 to Length(A) do
    A[I] := AnsiChar(Ord('a') + I - 1);
  Check(A = 'abcdefghij', 'cow-loop-writes-target');
  Check(B = '0123456789', 'cow-loop-writes-intact');

  { same for UnicodeString }
  UB := 'wide-string';
  UniqueString(UB);
  UA := UB;
  UA[1] := 'W';
  Check(UA = 'Wide-string', 'cow-wide-target');
  Check(UB = 'wide-string', 'cow-wide-intact');

  { var-param aliasing a global: writes must be visible through both names }
  GlobalStr := 'global-string';
  UniqueString(GlobalStr);
  WriteFirstChar(GlobalStr);
  Check(GlobalStr = '!lobal-string', 'cow-var-param-alias-after');

  { self-append and self-copy }
  A := 'xy';
  UniqueString(A);
  for I := 1 to 6 do
    A := A + A;
  Check(Length(A) = 128, 'cow-self-append-length');
  Check((A[1] = 'x') and (A[2] = 'y') and (A[127] = 'x') and (A[128] = 'y'),
    'cow-self-append-content');
  A := 'abcdef';
  A := Copy(A, 2, 4);
  Check(A = 'bcde', 'cow-self-copy');
  A := 'dup';
  A := A;
  Check(A = 'dup', 'cow-self-assign');

  { concat chain with empties }
  A := '';
  B := 'mid';
  C := A + '' + B + '' + A;
  Check(C = 'mid', 'cow-empty-concat-chain');

  { ShortString truncation at 255 }
  Short255 := '';
  for I := 1 to 30 do
    Short255 := Short255 + '0123456789';
  Check(Length(Short255) = 255, 'cow-shortstring-truncate-255');
  Check(Short255[255] = '4', 'cow-shortstring-tail');
  Check(Short255[1] = '0', 'cow-shortstring-head');

  { fixed-capacity string[10]: runtime assignment truncates }
  A := 'abcdefghijKLM';
  Cap10 := ShortString(A);
  Check(Length(Cap10) = 10, 'cow-capacity-truncate');
  Check(Cap10 = 'abcdefghij', 'cow-capacity-content');

  for I := 1 to Length(GlobalStr) do
    Mix(Ord(GlobalStr[I]));
end;

{ ---------------------------------------------------------------- }
{ 9. Dispatch forms: virtual/override/inherited chains, virtual     }
{ constructors through metaclasses, is/as, and method pointers.     }
{ ---------------------------------------------------------------- }

type
  TBase = class
  public
    Tag: Integer;
    constructor Create; virtual;
    function Calc(X: Integer): Integer; virtual;
    class function Kind: Integer; virtual;
  end;

  TMid = class(TBase)
  public
    constructor Create; override;
    function Calc(X: Integer): Integer; override;
    class function Kind: Integer; override;
  end;

  TTop = class(TMid)
  public
    constructor Create; override;
    function Calc(X: Integer): Integer; override;
    class function Kind: Integer; override;
  end;

  TBaseClass = class of TBase;
  TCalcFunc = function(X: Integer): Integer of object;

constructor TBase.Create;
begin
  inherited Create;
  Tag := 1;
end;

function TBase.Calc(X: Integer): Integer;
begin
  Result := X * 2 + 1;
end;

class function TBase.Kind: Integer;
begin
  Result := 10;
end;

constructor TMid.Create;
begin
  inherited Create;
  Tag := Tag + 10;
end;

function TMid.Calc(X: Integer): Integer;
begin
  Result := inherited Calc(X) * 3 - X;
end;

class function TMid.Kind: Integer;
begin
  Result := 20;
end;

constructor TTop.Create;
begin
  inherited Create;
  Tag := Tag + 100;
end;

function TTop.Calc(X: Integer): Integer;
begin
  Result := inherited Calc(X) + 1000;
end;

class function TTop.Kind: Integer;
begin
  Result := 30;
end;

function ModelCalc(Level, X: Integer): Integer;
begin
  Result := X * 2 + 1;                           { base }
  if Level >= 1 then
    Result := Result * 3 - X;                    { mid }
  if Level >= 2 then
    Result := Result + 1000;                     { top }
end;

procedure RunDispatchForms;
const
  Metas: array[0..2] of TBaseClass = (TBase, TMid, TTop);
  ModelTags: array[0..2] of Integer = (1, 11, 111);
  ModelKinds: array[0..2] of Integer = (10, 20, 30);
var
  Objs: array[0..11] of TBase;
  Levels: array[0..11] of Integer;
  I, X, MidCount: Integer;
  F: TCalcFunc;
  M: TMid;
begin
  for I := 0 to High(Objs) do
  begin
    Levels[I] := Integer(Rnd mod 3);
    Objs[I] := Metas[Levels[I]].Create;          { virtual ctor via metaclass }
  end;
  try
    for I := 0 to High(Objs) do
    begin
      Check(Objs[I].Tag = ModelTags[Levels[I]], 'disp-virtual-ctor-chain');
      Check(Objs[I].Kind = ModelKinds[Levels[I]], 'disp-class-function');
      for X := -5 to 5 do
        Check(Objs[I].Calc(X) = ModelCalc(Levels[I], X), 'disp-virtual-calc');
      Mix(UInt64(UInt32(Objs[I].Tag)));
    end;

    MidCount := 0;
    for I := 0 to High(Objs) do
      if Objs[I] is TMid then
        Inc(MidCount);
    X := 0;
    for I := 0 to High(Objs) do
      if Levels[I] >= 1 then
        Inc(X);
    Check(MidCount = X, 'disp-is-count');

    for I := 0 to High(Objs) do
      if Objs[I] is TMid then
      begin
        M := Objs[I] as TMid;
        Check(M.Calc(4) = ModelCalc(Levels[I], 4), 'disp-as-cast-calc');
      end;

    { method pointer taken from a virtual method dispatches by instance }
    for I := 0 to High(Objs) do
    begin
      F := Objs[I].Calc;
      Check(F(9) = ModelCalc(Levels[I], 9), 'disp-method-pointer');
    end;
  finally
    for I := 0 to High(Objs) do
      Objs[I].Free;
  end;
end;

{ ---------------------------------------------------------------- }
{ 10. Control-flow forms: loop bounds at type edges, Exit through   }
{ finally, goto, Break/Continue interaction with finally, and       }
{ short-circuit evaluation order.                                   }
{ ---------------------------------------------------------------- }

var
  SideEffects: Integer;

function SideTrue: Boolean;
begin
  Inc(SideEffects);
  Result := True;
end;

function SideFalse: Boolean;
begin
  Inc(SideEffects);
  Result := False;
end;

function ExitThroughFinally(var FinallyRuns: Integer): Integer;
begin
  Result := 0;
  try
    try
      Exit(5);
    finally
      Inc(FinallyRuns);
    end;
  finally
    Inc(FinallyRuns);
  end;
end;

function ExitFromExcept(var Marker: Integer): Integer;
begin
  Result := 0;
  try
    raise ERangeError.Create('expected');
  except
    on E: ERangeError do
    begin
      Inc(Marker);
      Exit(7);
    end;
  end;
end;

procedure RunFlowForms;
label
  Again, Skip;
var
  B, BFrom, BTo: Byte;
  W: Word;
  CountA, CountB, Sum, FinallyRuns, K, I: Integer;
  Sum64, I64: Int64;
begin
  { byte loop touching the top of the type: must terminate }
  CountA := 0;
  Sum := 0;
  for B := 250 to 255 do
  begin
    Inc(CountA);
    Inc(Sum, B);
  end;
  Check(CountA = 6, 'flow-byte-loop-top-count');
  Check(Sum = 1515, 'flow-byte-loop-top-sum');

  { full byte range with runtime bounds }
  BFrom := Byte(OpaqueI(0));
  BTo := Byte(OpaqueI(255));
  CountA := 0;
  for B := BFrom to BTo do
    Inc(CountA);
  Check(CountA = 256, 'flow-byte-loop-full-range');

  { empty loop when from > to }
  BFrom := 5;
  BTo := 4;
  CountA := 0;
  for B := BFrom to BTo do
    Inc(CountA);
  Check(CountA = 0, 'flow-byte-loop-empty');

  { word loop at the top of the type }
  CountA := 0;
  for W := 65530 to 65535 do
    Inc(CountA);
  Check(CountA = 6, 'flow-word-loop-top');

  { downto through zero on an unsigned counter }
  CountA := 0;
  Sum := 0;
  for B := 5 downto 0 do
  begin
    Inc(CountA);
    Inc(Sum, B);
  end;
  Check(CountA = 6, 'flow-byte-downto-zero');
  Check(Sum = 15, 'flow-byte-downto-sum');

  { Int64 counter adjacent to High(Int64): inc-then-compare would spin }
  CountA := 0;
  Sum64 := 0;
  for I64 := High(Int64) - 2 to High(Int64) do
  begin
    Inc(CountA);
    Sum64 := Sum64 xor I64;
  end;
  Check(CountA = 3, 'flow-int64-loop-high-count');
  Check(Sum64 = (High(Int64) xor (High(Int64) - 1) xor (High(Int64) - 2)),
    'flow-int64-loop-high-sum');
  { portable equivalent through a while loop }
  CountA := 0;
  Sum64 := High(Int64) - 2;
  while True do
  begin
    Inc(CountA);
    if Sum64 = High(Int64) then
      Break;
    Inc(Sum64);
  end;
  Check(CountA = 3, 'flow-int64-while-high-count');

  { Exit through nested finally }
  FinallyRuns := 0;
  K := ExitThroughFinally(FinallyRuns);
  Check(K = 5, 'flow-exit-finally-result');
  Check(FinallyRuns = 2, 'flow-exit-finally-both-run');

  FinallyRuns := 0;
  K := ExitFromExcept(FinallyRuns);
  Check(K = 7, 'flow-exit-except-result');
  Check(FinallyRuns = 1, 'flow-exit-except-marker');

  { goto: backward loop and forward skip }
  K := 0;
  Sum := 0;
Again:
  Inc(Sum, K);
  Inc(K);
  if K < 10 then
    goto Again;
  Check(Sum = 45, 'flow-goto-backward-loop');
  if OpaqueI(1) = 1 then
    goto Skip;
  Sum := Sum + 999999;
Skip:
  Check(Sum = 45, 'flow-goto-forward-skip');

  { Break / Continue inside try..finally in a for loop; finally must run on
    every entered iteration, including the ones leaving via Break/Continue }
  CountA := 0;
  CountB := 0;
  for I := 0 to 99 do
  begin
    try
      if (I and 3) = 1 then
        Continue;
      if I = 78 then
        Break;
      Inc(CountB);
    finally
      Inc(CountA);
    end;
  end;
  { iterations 0..78 entered; of 0..77, twenty are congruent 1 mod 4 }
  Check(CountA = 79, 'flow-finally-count-with-break-continue');
  Check(CountB = 58, 'flow-body-count-with-break-continue');

  { short-circuit evaluation order and call counts }
  SideEffects := 0;
  if SideTrue or SideFalse then
    Inc(Sum);
  Check(SideEffects = 1, 'flow-or-short-circuit');
  SideEffects := 0;
  if SideFalse and SideTrue then
    Inc(Sum);
  Check(SideEffects = 1, 'flow-and-short-circuit');
  SideEffects := 0;
  if SideFalse or (SideTrue and SideFalse) or SideTrue then
    Inc(Sum);
  Check(SideEffects = 4, 'flow-mixed-short-circuit');
  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 11. Old-school forms: variant records, with-statements, untyped   }
{ var parameters, array of const, defaults/overloads, plain         }
{ procedural types, properties (indexed + default).                 }
{ ---------------------------------------------------------------- }

type
  TOverlay = packed record
    case Byte of
      0: (Q: UInt64);
      1: (Lo, Hi: UInt32);
      2: (W4: array[0..3] of Word);
      3: (B8: array[0..7] of Byte);
      4: (D: Double);
  end;

  TPoint3 = record
    X, Y, Z: Integer;
  end;

  TIntFunc2 = function(X: Integer): Integer;

  TPropBox = class
  private
    FData: array[0..15] of Integer;
    FSets: Integer;
    function GetItem(I: Integer): Integer;
    procedure SetItem(I, V: Integer);
  public
    property Items[I: Integer]: Integer read GetItem write SetItem; default;
    property SetCount: Integer read FSets;
  end;

function TPropBox.GetItem(I: Integer): Integer;
begin
  Result := FData[I and 15];
end;

procedure TPropBox.SetItem(I, V: Integer);
begin
  FData[I and 15] := V;
  Inc(FSets);
end;

procedure FillUntyped(var Buf; Count: Integer; Seed: Byte);
var
  P: PByte;
  K: Integer;
begin
  P := @Buf;
  for K := 0 to Count - 1 do
  begin
    P^ := Byte(Seed + K * 3);
    Inc(P);
  end;
end;

function DescribeArgs(const A: array of const): AnsiString;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to High(A) do
    case A[K].VType of
      vtInteger:
        Result := Result + 'i' + AnsiString(IntToStr(A[K].VInteger));
      vtBoolean:
        if A[K].VBoolean then
          Result := Result + 'bT'
        else
          Result := Result + 'bF';
      vtInt64:
        Result := Result + 'l' + AnsiString(IntToStr(A[K].VInt64^));
      vtCurrency:
        Result := Result + 'c' + AnsiString(IntToStr(PInt64(A[K].VCurrency)^));
      vtAnsiString:
        Result := Result + 's' + AnsiString(A[K].VAnsiString);
      vtExtended:
        begin
          if A[K].VExtended^ = 2.5 then
            Result := Result + 'f+'
          else
            Result := Result + 'f?';
        end;
      vtPointer:
        if A[K].VPointer = nil then
          Result := Result + 'n'
        else
          Result := Result + 'p';
    else
      Result := Result + '?';
    end;
end;

function PickOvl(A: Integer): AnsiString; overload;
begin
  Result := 'int';
end;

function PickOvl(A: Double): AnsiString; overload;
begin
  Result := 'dbl';
end;

function DefSum(A: Integer; B: Integer = 40): Integer;
begin
  Result := A + B;
end;

function FnDoubleIt(X: Integer): Integer;
begin
  Result := X * 2;
end;

function FnInc3(X: Integer): Integer;
begin
  Result := X + 3;
end;

procedure RunOldSchoolForms;
var
  O: TOverlay;
  P1, P2: TPoint3;
  Buf: array[0..15] of Byte;
  F: TIntFunc2;
  PB: TPropBox;
  I, K: Integer;
  S: AnsiString;
  AVar: AnsiString;
  CurrV: Currency;
begin
  { variant record overlay: little-endian byte truth }
  O.Lo := $11223344;
  O.Hi := $AABBCCDD;
  Check(O.Q = UInt64($AABBCCDD11223344), 'old-union-lo-hi-q');
  Check((O.B8[0] = $44) and (O.B8[3] = $11) and (O.B8[7] = $AA),
    'old-union-bytes');
  Check((O.W4[0] = $3344) and (O.W4[3] = $AABB), 'old-union-words');
  for K := 0 to 7 do
    O.B8[K] := Byte(K * 17 + 1);
  for K := 0 to 3 do
    Check(O.W4[K] = (Byte(K * 34 + 1)) or (Byte(K * 34 + 18) shl 8),
      'old-union-byte-to-word');
  O.D := 1.5;
  Check(O.Q = UInt64($3FF8000000000000), 'old-union-double-bits');
  Mix(O.Q);

  { with statements: innermost scope wins }
  P1.X := 1; P1.Y := 2; P1.Z := 3;
  P2.X := 10; P2.Y := 20; P2.Z := 30;
  with P1 do
    with P2 do
    begin
      X := 99;
      Y := Y + 1;
    end;
  Check((P2.X = 99) and (P2.Y = 21), 'old-with-innermost-wins');
  Check((P1.X = 1) and (P1.Y = 2), 'old-with-outer-untouched');
  with P1 do
  begin
    Z := X + Y + Z;
  end;
  Check(P1.Z = 6, 'old-with-single');

  { untyped var parameter }
  FillUntyped(Buf, 16, 5);
  for K := 0 to 15 do
    Check(Buf[K] = Byte(5 + K * 3), 'old-untyped-var-fill');
  FillUntyped(O, 8, 200);
  for K := 0 to 7 do
    Check(O.B8[K] = Byte(200 + K * 3), 'old-untyped-var-record');

  { array of const with typed slots }
  AVar := 'zz';
  CurrV := 2.5;
  S := DescribeArgs([12, True, Int64(9000000000), CurrV, AVar, nil, 2.5, False]);
  Check(S = 'i12bTl9000000000c25000szznf+bF', 'old-array-of-const');

  { default parameters and overload resolution }
  Check(DefSum(2) = 42, 'old-default-param-used');
  Check(DefSum(2, 3) = 5, 'old-default-param-overridden');
  Check(PickOvl(5) = 'int', 'old-overload-int');
  Check(PickOvl(5.0) = 'dbl', 'old-overload-dbl');

  { plain procedural variables swapped at runtime }
  F := FnDoubleIt;
  K := F(21);
  F := FnInc3;
  K := K + F(K);
  Check(K = 87, 'old-procvar-swap');

  { properties: indexed, default, side-effect counter }
  PB := TPropBox.Create;
  try
    for I := 0 to 15 do
      PB[I] := I * 7;
    for I := 0 to 15 do
      Check(PB.Items[I] = I * 7, 'old-property-roundtrip');
    Check(PB[16] = 0 * 7, 'old-property-index-mask');
    Check(PB.SetCount = 16, 'old-property-side-count');
  finally
    PB.Free;
  end;
end;

{ ---------------------------------------------------------------- }
{ 12. Advanced-record forms: class operators, static class          }
{ functions, methods, for-in over containers.                       }
{ ---------------------------------------------------------------- }

type
  TFix = record
    Raw: Int64;                                  { scaled by 1000 }
    class function Make(Units, Milli: Integer): TFix; static;
    function Whole: Int64;
    class operator Add(const A, B: TFix): TFix;
    class operator Subtract(const A, B: TFix): TFix;
    class operator Multiply(const A: TFix; K: Integer): TFix;
    class operator Implicit(K: Integer): TFix;
    class operator Equal(const A, B: TFix): Boolean;
    class operator NotEqual(const A, B: TFix): Boolean;
    class operator LessThan(const A, B: TFix): Boolean;
  end;

class function TFix.Make(Units, Milli: Integer): TFix;
begin
  Result.Raw := Int64(Units) * 1000 + Milli;
end;

function TFix.Whole: Int64;
begin
  Result := Raw div 1000;
end;

class operator TFix.Add(const A, B: TFix): TFix;
begin
  Result.Raw := A.Raw + B.Raw;
end;

class operator TFix.Subtract(const A, B: TFix): TFix;
begin
  Result.Raw := A.Raw - B.Raw;
end;

class operator TFix.Multiply(const A: TFix; K: Integer): TFix;
begin
  Result.Raw := A.Raw * K;
end;

class operator TFix.Implicit(K: Integer): TFix;
begin
  Result.Raw := Int64(K) * 1000;
end;

class operator TFix.Equal(const A, B: TFix): Boolean;
begin
  Result := A.Raw = B.Raw;
end;

class operator TFix.NotEqual(const A, B: TFix): Boolean;
begin
  Result := A.Raw <> B.Raw;
end;

class operator TFix.LessThan(const A, B: TFix): Boolean;
begin
  Result := A.Raw < B.Raw;
end;

procedure RunAdvancedRecordForms;
var
  A, B, C: TFix;
  Model: Int64;
  Dyn: array of Int64;
  Stat: array[0..7] of Byte;
  BSet: set of Byte;
  V64, Sum64: Int64;
  BV: Byte;
  I, K: Integer;
  S: AnsiString;
  Ch: AnsiChar;
  Last: Integer;
begin
  { operator machine against a bare Int64 model }
  A := TFix.Make(2, 500);
  Model := 2500;
  Check(A.Raw = Model, 'arec-make');
  B := 3;                                        { Implicit }
  Check(B.Raw = 3000, 'arec-implicit-int');
  for I := 0 to 299 do
  begin
    K := Integer(Rnd mod 2001) - 1000;
    case Rnd mod 4 of
      0:
        begin
          A := A + TFix.Make(K, 0);
          Model := Model + Int64(K) * 1000;
        end;
      1:
        begin
          A := A - TFix.Make(0, K);
          Model := Model - K;
        end;
      2:
        begin
          A := A * 3;
          Model := Model * 3;
        end;
      3:
        begin
          B := K;
          A := A + B;
          Model := Model + Int64(K) * 1000;
        end;
    end;
    Check(A.Raw = Model, 'arec-operator-machine');
  end;
  C.Raw := Model;
  Check(A = C, 'arec-equal-operator');
  C.Raw := Model + 1;
  Check(A <> C, 'arec-notequal-operator');
  Check(A < C, 'arec-less-operator');
  Check(A.Whole = Model div 1000, 'arec-method');
  Mix(UInt64(Model));

  { for-in over dynamic array }
  SetLength(Dyn, 64);
  Model := 0;
  for I := 0 to 63 do
  begin
    Dyn[I] := Int64(Rnd and $FFFF) - 32768;
    Model := Model + Dyn[I];
  end;
  Sum64 := 0;
  for V64 in Dyn do
    Sum64 := Sum64 + V64;
  Check(Sum64 = Model, 'arec-forin-dynarray');

  { for-in over static array }
  Model := 0;
  for I := 0 to 7 do
  begin
    Stat[I] := Byte(I * 31 + 4);
    Model := Model + Stat[I];
  end;
  Sum64 := 0;
  for BV in Stat do
    Sum64 := Sum64 + BV;
  Check(Sum64 = Model, 'arec-forin-statarray');

  { for-in over a set walks ascending }
  BSet := [3, 250, 7, 128, 9];
  Last := -1;
  K := 0;
  for BV in BSet do
  begin
    Check(Integer(BV) > Last, 'arec-forin-set-ascending');
    Last := BV;
    Inc(K);
  end;
  Check(K = 5, 'arec-forin-set-count');
  Check(Last = 250, 'arec-forin-set-last');

  { for-in over an AnsiString }
  S := 'forms';
  K := 0;
  for Ch in S do
  begin
    Inc(K);
    Check(Ch = S[K], 'arec-forin-string-char');
  end;
  Check(K = 5, 'arec-forin-string-count');
end;

{ ---------------------------------------------------------------- }
{ 13. Variant forms: integer/boolean/currency transitions only (no  }
{ float-to-string locale traps).                                    }
{ ---------------------------------------------------------------- }

procedure RunVariantForms;
var
  V, W: Variant;
  K: Integer;
  L: Int64;
  C: Currency;
begin
  V := 42;
  V := V * 2 + 1;
  Check(V = 85, 'var-int-arith');
  K := V;
  Check(K = 85, 'var-to-int');
  W := V;
  Check(V = W, 'var-compare-same');
  W := 86;
  Check(V < W, 'var-compare-lt');
  V := Int64(1) shl 40;
  L := V;
  Check(L = Int64(1) shl 40, 'var-int64-roundtrip');
  V := True;
  Check(V, 'var-bool-true');
  V := not V;
  Check(not V, 'var-bool-not');
  C := 3.75;
  V := C;
  C := 0;
  C := V;
  Check(PInt64(@C)^ = 37500, 'var-currency-roundtrip');
  V := Null;
  Check(VarIsNull(V), 'var-null');
  V := '123';
  K := V;
  Check(K = 123, 'var-string-to-int');
end;

{ ---------------------------------------------------------------- }
{ 14. Freestyle: deliberately weird but valid combinations. This is }
{ the genre sample for FORMS_METHOD.md - any construct, any mix, as }
{ long as the program stays valid and every effect has an oracle.   }
{ ---------------------------------------------------------------- }

type
  TOverlay8 = packed record
    case Byte of
      0: (Q: UInt64);
      1: (B: array[0..7] of Byte);
      2: (C: Currency);
  end;

function WeirdRec(N: Integer; var Trail: AnsiString): Integer;
begin
  if N <= 0 then
  begin
    Trail := Trail + '.';
    Result := 0;
  end else if Odd(N) then
  begin
    Trail := Trail + 'o';
    Result := N + WeirdRec(N - 2, Trail);
  end else begin
    Trail := Trail + 'e';
    Result := WeirdRec(N - 1, Trail) - N;
  end;
end;

procedure RunFreestyleForms;
label
  Detour;
var
  Slots: array[0..15] of TOverlay8;
  ModelQ: array[0..15] of UInt64;
  Gate: set of 0..15;
  Fn: TIntFunc2;
  Acc, ModelAcc, Trail: AnsiString;
  I, K, Slot, Val, ModelVal, Boom, ModelBoom: Integer;
  Tmp: UInt64;
begin
  for I := 0 to 15 do
  begin
    Slots[I].Q := UInt64(I) * UInt64($0101010101010101);
    ModelQ[I] := UInt64(I) * UInt64($0101010101010101);
  end;
  Gate := [0, 3, 6, 9, 12, 15];
  Acc := '';
  ModelAcc := '';
  Boom := 0;
  ModelBoom := 0;
  Fn := FnDoubleIt;

  for I := 0 to 199 do
  begin
    Slot := Byte(I * 37 + Integer(Rnd and 31)) and 15;
    case (Rnd shr 5) and 3 of
      0: { calm xor through the union }
        begin
          with Slots[Slot] do
            Q := Q xor (UInt64(Slot + 1) shl ((I and 7) * 8));
          ModelQ[Slot] := ModelQ[Slot] xor
            (UInt64(Slot + 1) shl ((I and 7) * 8));
        end;
      1: { rotate the eight bytes left by three positions }
        begin
          Tmp := ModelQ[Slot];
          with Slots[Slot] do
          begin
            Q := (Q shr 24) or (Q shl 40);
          end;
          ModelQ[Slot] := (Tmp shr 24) or (Tmp shl 40);
        end;
      2: { drop a Currency through the overlay }
        begin
          Slots[Slot].C := Slot * 2 + 1;
          ModelQ[Slot] := UInt64(Int64(Slot * 2 + 1) * 10000);
        end;
      3: { boom: raise, catch, count }
        begin
          try
            if (I and 1) = 0 then
              raise EAbort.Create('boom');
            Slots[Slot].B[I and 7] := Byte(I);
            ModelQ[Slot] := (ModelQ[Slot] and
              not (UInt64($FF) shl ((I and 7) * 8))) or
              (UInt64(Byte(I)) shl ((I and 7) * 8));
          except
            on EAbort do
              Inc(Boom);
          end;
          if (I and 1) = 0 then
            Inc(ModelBoom);
        end;
    end;

    if Slot in Gate then
    begin
      Exclude(Gate, Slot);
      Fn := FnDoubleIt;
    end else begin
      Include(Gate, Slot);
      Fn := FnInc3;
    end;

    Val := Fn(Slot + (I and 15));
    if Slot in Gate then                        { just flipped to Inc3 }
      ModelVal := Slot + (I and 15) + 3
    else
      ModelVal := (Slot + (I and 15)) * 2;
    Check(Val = ModelVal, 'wild-procvar-gate');

    if I = 100 then
      goto Detour;                               { skip the letter, like the model }
    Acc := Acc + AnsiChar(Ord('a') + (Val mod 26));
    if Length(Acc) > 64 then
      Delete(Acc, 1, 1);
Detour:
    if I <> 100 then
    begin
      ModelAcc := ModelAcc + AnsiChar(Ord('a') + (ModelVal mod 26));
      if Length(ModelAcc) > 64 then
        Delete(ModelAcc, 1, 1);
    end;
  end;

  for I := 0 to 15 do
  begin
    Check(Slots[I].Q = ModelQ[I], 'wild-union-final-state');
    Mix(Slots[I].Q);
  end;
  Check(Acc = ModelAcc, 'wild-acc-string');
  Check(Boom = ModelBoom, 'wild-boom-count');

  { hand-verified recursion trace }
  Trail := '';
  K := WeirdRec(9, Trail);
  Check(K = 25, 'wild-recursion-odd');
  Check(Trail = 'ooooo.', 'wild-recursion-odd-trail');
  Trail := '';
  K := WeirdRec(10, Trail);
  Check(K = 15, 'wild-recursion-even');
  Check(Trail = 'eooooo.', 'wild-recursion-even-trail');
  for I := 1 to Length(Acc) do
    Mix(Ord(Acc[I]));
end;

{ ---------------------------------------------------------------- }
{ 17. Managed lifetime and control-flow forms, group 1.             }
{ pass. ByteBool/promotion oracles calibrated on Delphi 12.2 Win64  }
{ (probe3.dpr): logical ops on non-canonical typed bools normalize  }
{ to 0/1, Ord() returns the raw value sign-extended, Byte+Integer   }
{ wraps in Integer before widening to an Int64 target.              }
{ ---------------------------------------------------------------- }

type
  TGuard = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TIRec = record
    Intf: IInterface;
    Tag: Integer;
  end;

  TNameRec = record
    S: AnsiString;
    N: Integer;
  end;
  TNames = array[0..2] of TNameRec;

  TInt64Sink = procedure(X: Int64);

constructor TGuard.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TGuard.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

var
  SinkAcc: Int64 = 0;
  SinkVar: TInt64Sink;
  { globals on purpose: register-promoted LOCAL ByteBools lose their
    non-canonical raw value under Delphi O+ constant tracking (that grain
    is pinned separately as op1-bytebool-local-raw-optim) }
  GBB, GBB2: ByteBool;
  GLB: LongBool;

procedure SinkImpl(X: Int64);
begin
  SinkAcc := SinkAcc xor X;
end;

{$J+}
const
  WritableTC: Integer = 0;
{$J-}

var
  PlainCounter: Integer = 0;
  BumpVar: procedure;

procedure BumpBothImpl;
begin
  Inc(WritableTC);
  Inc(PlainCounter);
end;

var
  CseGlobal: Integer;

procedure MutateVar(var X: Integer; NewVal: Integer);
begin
  X := NewVal;
end;

function ResultEscapes: Integer;
begin
  Result := 100;
  MutateVar(Result, 150);
  Result := Result + 1;
end;

function Pressure(S: Int64): Int64;
var
  A, B, C, D, E, F, G, H, I, J, K, L: Int64;
begin
  A := S;
  B := S xor $FF;
  C := A + B;
  D := C xor A;
  E := D + B;
  F := E xor C;
  G := F + D;
  H := G xor E;
  I := H + F;
  J := I xor G;
  K := J + H;
  L := K xor I;
  SinkVar(J);
  Result := A xor B xor C xor D xor E xor F xor G xor H xor I xor J xor K xor L;
end;

function PressureClean(S: Int64): Int64;
var
  Vals: array[0..11] of Int64;
  K: Integer;
begin
  { independent oracle: the same recurrence driven from an array, no
    register pressure, no call in the middle. Chain: v2 = v1 + v0, then
    v[k] = v[k-1] (+ for even k / xor for odd k) v[k-3]. }
  Vals[0] := S;
  Vals[1] := S xor $FF;
  Vals[2] := Vals[1] + Vals[0];
  for K := 3 to 11 do
    if (K and 1) = 0 then
      Vals[K] := Vals[K - 1] + Vals[K - 3]
    else
      Vals[K] := Vals[K - 1] xor Vals[K - 3];
  Result := 0;
  for K := 0 to 11 do
    Result := Result xor Vals[K];
end;

function Nest4(A: Integer): Integer;
  function L1(B: Integer): Integer;
    function L2(C: Integer): Integer;
      function L3(D: Integer): Integer;
      begin
        Result := A * 1000 + B * 100 + C * 10 + D;
      end;
    begin
      Result := L3(C + 1);
    end;
  begin
    Result := L2(B + 1);
  end;
begin
  Result := L1(A + 1);
end;

function InnerSum(const X: array of Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 0 to High(X) do
    Result := Result + X[K];
end;

function MidSum(const X: array of Integer): Integer;
begin
  Result := InnerSum(X);
end;

function OuterSum(const X: array of Integer): Integer;
begin
  Result := MidSum(X);
end;

procedure BumpInlineVar(var X: Integer; N: Integer); inline;
begin
  X := X + N;
end;

function BuildStr: AnsiString;
begin
  Result := 'AB';
  try
    Result := Result + 'CD';
  finally
    Result := Result + 'EF';
  end;
end;

procedure ConsumeIRecByVal(R: TIRec);
begin
  R.Tag := 0;
end;

procedure MutateNamesByVal(A: TNames);
begin
  A[0].S := 'CHANGED';
  A[0].N := 999;
end;

procedure WillRaise(DoIt: Boolean);
var
  G: IInterface;
begin
  G := TGuard.Create;
  if DoIt then
    raise ERangeError.Create('op1-boom');
  G := nil;
end;

procedure ReplaceIntf(out I: IInterface);
begin
  I := TGuard.Create;
end;

procedure RunManagedLifetimeForms1;
var
  BB: ByteBool;
  U8: Byte;
  S8: ShortInt;
  UW: Word;
  SS: SmallInt;
  I, E1, E2, K: Integer;
  R64, Want: Int64;
  NegBase: array[-5..5] of Integer;
  WArr: array[0..3] of Word;
  QAbs: Int64 absolute WArr;
  IR: TIRec;
  Names: TNames;
  Intf: IInterface;
  S: AnsiString;
  Caught: Boolean;
begin
  { non-canonical typed booleans, written from OPAQUE runtime values so the
    O+ constant tracker cannot normalize the store. Logical ops normalize
    to 0/1 (calibrated on Delphi 12.2 Win64). }
  Byte(GBB) := Byte(OpaqueI($C8));
  Byte(GBB2) := Byte(OpaqueI($37));
  Check(ShortInt(GBB) = -56, 'op1-bytebool-raw-signed-cast');
  Check(Byte(GBB) = $C8, 'op1-bytebool-raw-byte-cast');
  Check(GBB, 'op1-bytebool-nonzero-true');
  Check(GBB = True, 'op1-bytebool-eq-true');
  Check(Byte(not GBB) = $00, 'op1-bytebool-not-normalizes');
  Check(Byte(GBB and GBB2) = $01, 'op1-bytebool-and-normalizes');
  Check(Byte(GBB or GBB2) = $01, 'op1-bytebool-or-normalizes');
  Check(Byte(GBB xor GBB2) = $00, 'op1-bytebool-xor-normalizes');
  Check(Byte(GBB) = $C8, 'op1-bytebool-raw-after-logic');
  UInt32(GLB) := UInt32(OpaqueI($C8C8C8C8));
  Check(GLB, 'op1-longbool-nonzero-true');
  Check(Byte(not GLB) = $00, 'op1-longbool-not-normalizes');
  { FINDING (Delphi 12.2 Win64, O+ only): writing a CONSTANT through
    Byte(BoolVar) := literal is tracked as canonical True by the optimizer,
    so the raw value is not observable afterwards. Passes on O- and with
    opaque runtime stores. Expected-fail on Delphi O+. }
  Byte(BB) := $C8;
  Check(Byte(BB) = $C8, 'op1-bytebool-const-write-optim');

  { writable typed constant must not be const-propagated }
  WritableTC := 0;
  PlainCounter := 0;
  BumpVar := BumpBothImpl;
  for I := 1 to 7 do
    BumpVar;
  Check(WritableTC = 7, 'op1-typed-const-writable');
  Check(WritableTC = PlainCounter, 'op1-typed-const-vs-plain');

  { CSE must die when the value escapes through a var param }
  CseGlobal := 10;
  E1 := CseGlobal * 3 + 1;
  MutateVar(CseGlobal, 77);
  E2 := CseGlobal * 3 + 1;
  Check(E1 = 31, 'op1-cse-before-alias');
  Check(E2 = 232, 'op1-cse-after-alias');

  { Result passed as var param: register copy must spill and reload }
  Check(ResultEscapes = 151, 'op1-result-var-escape');

  { mixed-width signed/unsigned comparisons widen to Integer }
  U8 := 200;
  S8 := ShortInt($C8);
  Check(U8 > S8, 'op1-byte-gt-shortint-samebits');
  U8 := 0;
  S8 := -1;
  Check(U8 > S8, 'op1-byte-gt-shortint-neg1');
  UW := 40000;
  SS := SmallInt($9C40);
  Check(UW > SS, 'op1-word-gt-smallint-samebits');

  { signed narrow multiply must sign-extend, not zero-extend }
  S8 := -100;
  Check(S8 * S8 = 10000, 'op1-shortint-mul-negneg');
  Check(Integer(S8) * Integer(S8) = 10000, 'op1-shortint-mul-reference');
  S8 := -1;
  Check(S8 * 127 = -127, 'op1-shortint-mul-neg1');

  { shr is logical for signed operands (calibrated on Delphi) }
  I := Integer(OpaqueI(-1));
  Check(UInt32(I shr 1) = $7FFFFFFF, 'op1-shr-int32-logical');
  I := Integer(OpaqueI(Low(Integer)));
  Check(I shr 31 = 1, 'op1-shr-int32-signbit');
  R64 := OpaqueI(-1);
  Check(UInt64(R64 shr 1) = UInt64($7FFFFFFFFFFFFFFF), 'op1-shr-int64-logical');
  R64 := OpaqueI(Low(Int64));
  Check(R64 shr 63 = 1, 'op1-shr-int64-signbit');

  { record with an interface field passed by value: refcount discipline }
  TGuard.Alive := 0;
  IR.Intf := TGuard.Create;
  IR.Tag := 42;
  Check(TGuard.Alive = 1, 'op1-irec-created');
  ConsumeIRecByVal(IR);
  Check(TGuard.Alive = 1, 'op1-irec-alive-after-byval');
  Check(IR.Tag = 42, 'op1-irec-caller-tag-intact');
  Check(Assigned(IR.Intf), 'op1-irec-intf-intact');
  IR.Intf := nil;
  Check(TGuard.Alive = 0, 'op1-irec-released');

  { by-value array of managed records: deep copy, caller untouched }
  Names[0].S := 'alpha';
  Names[0].N := 1;
  Names[1].S := 'beta';
  Names[1].N := 2;
  Names[2].S := 'gamma';
  Names[2].N := 3;
  MutateNamesByVal(Names);
  Check(Names[0].S = 'alpha', 'op1-names-byval-string-intact');
  Check(Names[0].N = 1, 'op1-names-byval-int-intact');

  { register pressure with an opaque call in the middle }
  SinkVar := SinkImpl;
  SinkAcc := 0;
  for I := 0 to 49 do
  begin
    R64 := Int64(Rnd);
    Want := PressureClean(R64);
    Check(Pressure(R64) = Want, 'op1-spill-pressure');
  end;
  Mix(UInt64(SinkAcc));

  { four-deep nested routines walking the parent-frame chain }
  Check(Nest4(5) = 5678, 'op1-nested-4deep');
  for I := 0 to 20 do
    Check(Nest4(I) = I * 1000 + (I + 1) * 100 + (I + 2) * 10 + (I + 3),
      'op1-nested-4deep-sweep');

  { open array forwarded twice keeps data pointer and High intact }
  Check(OuterSum([10, 20, 30, 40, 50]) = 150, 'op1-open-array-chain');
  Check(OuterSum([]) = 0, 'op1-open-array-chain-empty');
  Check(OuterSum([7]) = 7, 'op1-open-array-chain-single');

  { negative-based static array address lowering }
  for I := -5 to 5 do
    NegBase[I] := I * I + I;
  Check(NegBase[-5] = 20, 'op1-negbase-low');
  Check(NegBase[-1] = 0, 'op1-negbase-neg1');
  Check(NegBase[0] = 0, 'op1-negbase-zero');
  Check(NegBase[5] = 30, 'op1-negbase-high');

  { inlined procedure with a var parameter binds the real variable }
  K := 0;
  BumpInlineVar(K, 10);
  BumpInlineVar(K, 20);
  BumpInlineVar(K, 30);
  Check(K = 60, 'op1-inline-var-param');

  { managed Result modified inside finally }
  S := BuildStr;
  Check(Length(S) = 6, 'op1-finally-result-length');
  Check(S = 'ABCDEF', 'op1-finally-result-content');

  { absolute overlay: no enregistration across the alias }
  WArr[0] := $1111;
  WArr[1] := $2222;
  WArr[2] := $3333;
  WArr[3] := $4444;
  Check(QAbs = Int64($4444333322221111), 'op1-absolute-words-to-int64');
  QAbs := Int64($AABBCCDD11223344);
  Check(WArr[0] = $3344, 'op1-absolute-int64-to-word0');
  Check(WArr[3] = $AABB, 'op1-absolute-int64-to-word3');
  Mix(UInt64(QAbs));

  { exception unwind finalizes managed locals }
  TGuard.Alive := 0;
  Caught := False;
  try
    WillRaise(True);
  except
    on ERangeError do
      Caught := True;
  end;
  Check(Caught, 'op1-unwind-caught');
  Check(TGuard.Alive = 0, 'op1-unwind-finalized-local');

  { interface self-assign: AddRef before Release }
  TGuard.Alive := 0;
  Intf := TGuard.Create;
  Intf := Intf;
  Check(TGuard.Alive = 1, 'op1-intf-self-assign-alive');
  Intf := nil;
  Check(TGuard.Alive = 0, 'op1-intf-self-assign-released');

  { out parameter of a managed type releases the old value }
  TGuard.Alive := 0;
  Intf := TGuard.Create;
  ReplaceIntf(Intf);
  Check(TGuard.Alive = 1, 'op1-out-param-old-released');
  Intf := nil;
  Check(TGuard.Alive = 0, 'op1-out-param-new-released');

  { expression width follows operand rules, not the assignment target }
  U8 := Byte(OpaqueI(1));
  I := Integer(OpaqueI(2147483647));
  R64 := U8 + I;
  Check(R64 = Int64(Low(Integer)), 'op1-promotion-not-by-target');
end;

{ ---------------------------------------------------------------- }
{ 18. Managed lifetime and control-flow forms, group 2.             }
{ barriers plus 32/64 dialect seams. Mixed-width oracles calibrated }
{ on Delphi 12.2 Win64 (probe4.dpr): Int64/UInt64 compares are      }
{ mathematical, Cardinal arithmetic promotes to Int64 (no wrap).    }
{ ---------------------------------------------------------------- }

type
  IValInt = interface
    ['{2F8C1B62-90AF-4E1D-B7C4-5A93E20D6B11}']
    function Val: Integer;
  end;

  TValObj = class(TInterfacedObject, IValInt)
  private
    FVal: Integer;
  public
    class var Alive: Integer;
    constructor Create(AVal: Integer);
    destructor Destroy; override;
    function Val: Integer;
  end;

  TSRec = record
    S: AnsiString;
    N: Integer;
  end;

  TInnerRec = record
    S: AnsiString;
  end;

  TOuterRec = record
    I: TInnerRec;
    N: Integer;
  end;

  TStrArr = array of AnsiString;

procedure AtomicInc(var X: Integer);
begin
{$ifdef FPC}
  InterLockedIncrement(X);
{$else}
  AtomicIncrement(X);
{$endif}
end;

procedure AtomicDec(var X: Integer);
begin
{$ifdef FPC}
  InterLockedDecrement(X);
{$else}
  AtomicDecrement(X);
{$endif}
end;

constructor TValObj.Create(AVal: Integer);
begin
  inherited Create;
  FVal := AVal;
  AtomicInc(Alive);
end;

destructor TValObj.Destroy;
begin
  AtomicDec(Alive);
  inherited Destroy;
end;

function TValObj.Val: Integer;
begin
  Result := FVal;
end;

var
  GHold: IValInt;
  GUni: UnicodeString;

function ExtractByVal(B: IValInt): Integer;
begin
  { drop the only OTHER reference and allocate a fresh object into the
    hole: if the by-value B was not AddRef'ed, it reads the new object }
  GHold := nil;
  GHold := TValObj.Create(99);
  Result := B.Val;
end;

function MakeSRec: TSRec;
begin
  Result.S := 'alive';
  Result.N := 1;
end;

function ReadSRecByVal(R: TSRec): AnsiString;
begin
  Result := R.S;
end;

function BracketStr(const S: AnsiString): AnsiString;
begin
  Result := '[' + S + ']';
end;

function SelfAliasConcat: AnsiString;
begin
  Result := 'core';
  Result := BracketStr(Result);
end;

procedure PolluteStack;
var
  B: array[0..1023] of Byte;
begin
  FillChar(B, SizeOf(B), $FF);
  Mix(B[0]);
end;

function ManagedLocalInitialized: Integer;
var
  R: record
    S: AnsiString;
  end;
begin
  if Pointer(R.S) = nil then
    Result := 1
  else
    Result := 0;
end;

function DeadStoreFinalize: Integer;
var
  X: IInterface;
begin
  X := TGuard.Create;
  X := TGuard.Create;
  X := nil;
  Result := TGuard.Alive;
end;

function MakeStrArr: TStrArr;
begin
  SetLength(Result, 2);
  Result[0] := 'alpha';
  Result[1] := 'bravo';
end;

function WrapParens(const S: AnsiString): AnsiString;
begin
  Result := '(' + S + ')';
end;

function WideLenAndClear(const W: WideString): Integer;
begin
  GUni := '';
  Result := Length(W);
end;

function StrThroughExcept: AnsiString;
begin
  Result := 'a';
  try
    Result := Result + 'b';
    Result := Result + 'c';
    raise ERangeError.Create('op2');
  except
    on ERangeError do
      Result := Result + 'd';
  end;
end;

function IdentityIntf(X: IValInt): IValInt;
begin
  Result := X;
end;

function MakeVal(V: Integer): IValInt;
begin
  Result := TValObj.Create(V);
end;

function IdentityChainVal: Integer;
begin
  { hidden interface temps are finalized in THIS routine's epilogue
    (Delphi finalizes expression temps at routine exit, not statement end),
    so the caller can assert Alive = 0 after we return }
  Result := IdentityIntf(IdentityIntf(MakeVal(7))).Val;
end;

procedure RunManagedLifetimeForms2;
var
  R, I: Integer;
  A, B: AnsiString;
  SArr, SArrB: TStrArr;
  RecA, RecB: TSRec;
  OutA, OutB: TOuterRec;
  StatRecs: array[0..1] of TSRec;
  I64: Int64;
  U64: UInt64;
  C: Cardinal;
  IntA, IntB: Integer;
  R64: Int64;
  U8: Byte;
  S8: ShortInt;
begin
  { by-value interface parameter must own a reference }
  TValObj.Alive := 0;
  GHold := TValObj.Create(42);
  R := ExtractByVal(GHold);
  Check(R = 42, 'op2-intf-byval-addref');
  Check(TValObj.Alive = 1, 'op2-intf-byval-old-dead');
  GHold := nil;
  Check(TValObj.Alive = 0, 'op2-intf-byval-drained');

  { record result passed by value: string field survives the temp }
  A := ReadSRecByVal(MakeSRec);
  Check(A = 'alive', 'op2-srec-result-byval');

  { Result on both sides through a helper }
  Check(SelfAliasConcat = '[core]', 'op2-result-self-alias-concat');

  { managed locals are nil-initialized regardless of stack garbage }
  PolluteStack;
  Check(ManagedLocalInitialized = 1, 'op2-managed-local-init');

  { dead-store elimination must not elide interface releases }
  TGuard.Alive := 0;
  Check(DeadStoreFinalize = 0, 'op2-intf-dead-store-finalize');

  { Int64 vs UInt64 comparison is mathematical (calibrated on Delphi) }
  I64 := OpaqueI(-1);
  U64 := UInt64(OpaqueI(0)) or (UInt64(1) shl 63);
  Check(I64 < U64, 'op2-int64-lt-uint64');
  Check(U64 > I64, 'op2-uint64-gt-int64');
  I64 := OpaqueI(0);
  U64 := UInt64(OpaqueI(0));
  Check(not (I64 < U64), 'op2-int64-uint64-equal-zero');

  { dyn array of strings returned and indexed as a temp }
  Check(MakeStrArr[1] = 'bravo', 'op2-dynarray-temp-element');

  { three nested managed temps }
  Check(WrapParens(WrapParens(WrapParens('x'))) = '(((x)))',
    'op2-nested-string-temps');

  { UniqueString must invalidate any cached buffer pointer }
  A := AnsiString('hell') + AnsiString('o');   { heap string, refcount 1 }
  B := A;
  UniqueString(A);
  A[1] := 'H';
  Check(B = 'hello', 'op2-uniquestring-source-intact');
  Check(A = 'Hello', 'op2-uniquestring-target-changed');

  { Cardinal arithmetic promotes to Int64 (calibrated on Delphi) }
  C := Cardinal(OpaqueI($80000001));
  R64 := -C;
  Check(R64 = -2147483649, 'op2-cardinal-negate');
  C := Cardinal(OpaqueI(0));
  I := Integer(OpaqueI(1));
  R64 := C - I;
  Check(R64 = -1, 'op2-cardinal-minus-integer');
  { same-type Cardinal+Cardinal DOES wrap in 32 bits (unlike mixed pairs) }
  C := Cardinal(OpaqueI($FFFFFFFF));
  R64 := C + C;
  Check(R64 = 4294967294, 'op2-cardinal-plus-cardinal');

  { explicit Int64 cast widens BEFORE the multiply }
  IntA := Integer(OpaqueI(100000));
  IntB := Integer(OpaqueI(100000));
  R64 := Int64(IntA) * IntB;
  Check(R64 = 10000000000, 'op2-int64-cast-multiply');

  { UnicodeString -> WideString conversion at the call site }
  GUni := 'hello';
  Check(WideLenAndClear(GUni) = 5, 'op2-widestring-const-param');

  { string Result accumulated across an exception dispatch }
  Check(StrThroughExcept = 'abcd', 'op2-string-result-except');

  { whole-record assignment addrefs nested managed fields }
  OutA.I.S := 'deep';
  OutA.N := 1;
  OutB := OutA;
  OutA.I.S := 'changed';
  Check(OutB.I.S = 'deep', 'op2-nested-record-deep-copy');
  Check(OutB.N = 1, 'op2-nested-record-plain-field');

  { Copy of a string dyn array is independent }
  SetLength(SArr, 2);
  SArr[0] := 'original';
  SArr[1] := 'other';
  SArrB := Copy(SArr);
  SArrB[0] := 'modified';
  Check(SArr[0] = 'original', 'op2-dynarray-copy-independent');
  Check(SArrB[1] = 'other', 'op2-dynarray-copy-content');

  { static array element assignment with managed record }
  StatRecs[0].S := 'first';
  StatRecs[0].N := 1;
  StatRecs[1].S := 'second';
  StatRecs[1].N := 2;
  StatRecs[0] := StatRecs[1];
  Check(StatRecs[0].S = 'second', 'op2-static-array-record-assign');
  StatRecs[1].S := 'third';
  Check(StatRecs[0].S = 'second', 'op2-static-array-record-unshared');

  { narrow mixed-sign addition promotes with sign extension }
  U8 := Byte(OpaqueI(200));
  S8 := ShortInt(OpaqueI(-100));
  R := U8 + S8;
  Check(R = 100, 'op2-byte-shortint-add');

  { interface identity chain: temps survive both hops, then drain when the
    building routine returns }
  TValObj.Alive := 0;
  R := IdentityChainVal;
  Check(R = 7, 'op2-intf-identity-chain');
  Check(TValObj.Alive = 0, 'op2-intf-identity-drained');

  { record copies also drain cleanly }
  RecA.S := 'r1';
  RecA.N := 5;
  RecB := RecA;
  RecA.S := 'r2';
  Check(RecB.S = 'r1', 'op2-srec-assign-unshared');
  Mix(UInt64(UInt32(Length(RecB.S))));
end;

{ ---------------------------------------------------------------- }
{ 19. Thread forms: four workers run the same PURE kernel on their  }
{ own seeds and write only their own slots; the main thread then    }
{ recomputes every kernel single-threaded - results must be         }
{ bit-identical. No shared mutable state, no atomics needed in the  }
{ kernel; managed handoff (strings, one interface per worker) is    }
{ validated by main after WaitFor.                                  }
{ ---------------------------------------------------------------- }

type
  TKernelResult = record
    Digest: UInt64;
    Ok: Integer;
  end;

function ThreadKernel(Seed: UInt64): TKernelResult;
var
  State, D: UInt64;
  S: AnsiString;
  Model: array[0..255] of Byte;
  ModelLen, I, J, Op: Integer;
  Cur: Currency;
  CurModel: Int64;
  V, Dv, Q, R: Int64;

  function Next: UInt64;
  begin
    State := State xor (State shr 12);
    State := State xor (State shl 25);
    State := State xor (State shr 27);
    Result := State * UInt64($2545F4914F6CDD1D);
  end;

  procedure Fold(X: UInt64);
  begin
    D := (D xor X) * UInt64($100000001B3);
  end;

  procedure Ok(Cond: Boolean);
  begin
    if Cond then
      Inc(Result.Ok)
    else
      Fold(UInt64($DEAD));
  end;

begin
  State := Seed;
  if State = 0 then
    State := 1;
  D := UInt64($CBF29CE484222325);
  Result.Ok := 0;

  { string build/shrink with a byte model }
  S := '';
  ModelLen := 0;
  for I := 0 to 299 do
  begin
    Op := Integer(Next mod 3);
    if (Op <> 0) or (ModelLen = 0) then
    begin
      if ModelLen < 256 then
      begin
        J := Integer(Next and $3F) + 32;
        S := S + AnsiChar(J);
        Model[ModelLen] := Byte(J);
        Inc(ModelLen);
      end;
    end else begin
      Delete(S, Length(S), 1);
      Dec(ModelLen);
    end;
    Ok(Length(S) = ModelLen);
    if ModelLen > 0 then
      Ok(Byte(S[ModelLen]) = Model[ModelLen - 1]);
  end;
  for I := 1 to Length(S) do
    Fold(Byte(S[I]));

  { Currency accumulation against a scaled model }
  Cur := 0;
  CurModel := 0;
  for I := 0 to 199 do
  begin
    J := Integer(Next mod 100001) - 50000;
    Cur := Cur + J;
    CurModel := CurModel + Int64(J) * 10000;
    Cur := Cur - (J div 2);
    CurModel := CurModel - Int64(J div 2) * 10000;
  end;
  Ok(PInt64(@Cur)^ = CurModel);
  Fold(UInt64(CurModel));

  { div/mod checked purely through the language-spec identities }
  for I := 0 to 199 do
  begin
    V := Int64(Next);
    Dv := Int64(Next and $FFFF) + 2;
    if (Next and 1) = 1 then
      Dv := -Dv;
    Q := V div Dv;
    R := V mod Dv;
    Ok(Q * Dv + R = V);
    Ok(Abs(R) < Abs(Dv));
    Ok((R = 0) or ((R > 0) = (V > 0)));
    Fold(UInt64(Q) xor UInt64(R));
  end;

  Result.Digest := D;
end;

type
  TFormWorker = class(TThread)
  public
    Seed: UInt64;
    Res: TKernelResult;
    Handoff: AnsiString;
    HandIntf: IValInt;
    constructor Create(ASeed: UInt64);
    procedure Execute; override;
  end;

constructor TFormWorker.Create(ASeed: UInt64);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Seed := ASeed;
end;

procedure TFormWorker.Execute;
begin
  Res := ThreadKernel(Seed);
  Handoff := AnsiString('worker:') + AnsiString(IntToStr(Integer(Seed and $FF)));
  HandIntf := TValObj.Create(Integer(Seed and $FFFF));
end;

procedure RunThreadForms;
var
  Workers: array[0..3] of TFormWorker;
  Expected: array[0..3] of TKernelResult;
  Seeds: array[0..3] of UInt64;
  I: Integer;
begin
  { the golden-ratio constant goes through OpaqueU: FPC O3 loop unrolling
    const-folds UInt64(I+1)*CONST, hits the wrap and reports a COMPILE-TIME
    overflow error despite Q- being active - finding, see o3ovf.pas }
  for I := 0 to 3 do
    Seeds[I] := RngState xor (UInt64(I + 1) * OpaqueU($9E3779B97F4A7C15));

  { oracle first, single-threaded }
  for I := 0 to 3 do
    Expected[I] := ThreadKernel(Seeds[I]);

  TValObj.Alive := 0;
  for I := 0 to 3 do
    Workers[I] := TFormWorker.Create(Seeds[I]);
  for I := 0 to 3 do
    Workers[I].Start;
  for I := 0 to 3 do
    Workers[I].WaitFor;

  for I := 0 to 3 do
  begin
    Check(Workers[I].Res.Digest = Expected[I].Digest, 'thr-kernel-digest');
    Check(Workers[I].Res.Ok = Expected[I].Ok, 'thr-kernel-okcount');
    Check(Workers[I].Handoff =
      AnsiString('worker:') + AnsiString(IntToStr(Integer(Seeds[I] and $FF))),
      'thr-managed-string-handoff');
    Check(Assigned(Workers[I].HandIntf), 'thr-intf-handoff-assigned');
    Check(Workers[I].HandIntf.Val = Integer(Seeds[I] and $FFFF),
      'thr-intf-handoff-value');
    Mix(Workers[I].Res.Digest);
  end;
  Check(TValObj.Alive = 4, 'thr-intf-alive-count');
  for I := 0 to 3 do
    Workers[I].Free;
  Check(TValObj.Alive = 0, 'thr-intf-released-after-free');
end;

{ ---------------------------------------------------------------- }
{ 20. Wild round 2: the author's own random grab-bag - pointer      }
{ walks, matrices, char chains, embedded #0 strings, RTL string     }
{ edits at edge offsets, Val/Str extremes, overlapping Move, nil    }
{ is/as, subranges, enum round-trips.                               }
{ ---------------------------------------------------------------- }

type
  TWildEnum = (weZero, weOne, weTwo, weThree, weFour, weFive);
  TDigits = 1..100;

procedure RunWildRound2Forms;
var
  IntArr: array[0..63] of Integer;
  P: PInteger;
  PB: PByte;
  Matrix: array[0..7] of array[0..7] of Integer;
  I, J, K: Integer;
  A, B: AnsiString;
  Buf: array[0..31] of Byte;
  V64: Int64;
  U64: UInt64;
  SCode: Integer;
  Str1: AnsiString;
  E: TWildEnum;
  Dig: TDigits;
  Obj: TBase;
  ClsRef: TBaseClass;
  ProcV: TIntFunc2;
  Ch: AnsiChar;
begin
  { typed pointer arithmetic vs index math }
  for I := 0 to 63 do
    IntArr[I] := I * 37 - 100;
  P := @IntArr[0];
  Inc(P, 10);
  Check(P^ = 10 * 37 - 100, 'wild2-pinteger-inc');
  Inc(P, 20);
  Check(P^ = 30 * 37 - 100, 'wild2-pinteger-inc-again');
  Dec(P, 5);
  Check(P^ = 25 * 37 - 100, 'wild2-pinteger-dec');
  PB := PByte(@IntArr[0]);
  Inc(PB, 12 * SizeOf(Integer));
  Check(PInteger(PB)^ = IntArr[12], 'wild2-pbyte-scaled-walk');

  { matrix with both indices computed }
  for I := 0 to 7 do
    for J := 0 to 7 do
      Matrix[I][J] := I * 100 + J;
  for K := 0 to 199 do
  begin
    I := Integer(Rnd and 7);
    J := Integer((Rnd shr 8) and 7);
    Check(Matrix[(I + J) and 7][(I xor J) and 7] =
      ((I + J) and 7) * 100 + ((I xor J) and 7), 'wild2-matrix-computed');
  end;

  { char arithmetic chains, kept in the AnsiChar domain }
  Ch := 'A';
  for I := 0 to 25 do
    Check(AnsiChar(Ord(Ch) + I) = AnsiChar(Byte(Ord('A') + I)), 'wild2-char-chain');
  Check(Succ('A') = 'B', 'wild2-char-succ');
  Check(Pred('Z') = 'Y', 'wild2-char-pred');

  { embedded #0: relational operators are byte-wise, length-aware }
  SetLength(A, 3);
  A[1] := 'a';
  A[2] := #0;
  A[3] := 'b';
  SetLength(B, 3);
  B[1] := 'a';
  B[2] := #0;
  B[3] := 'c';
  Check(A < B, 'wild2-embedded-zero-compare');
  Check(Length(A) = 3, 'wild2-embedded-zero-length');
  Check(Pos(#0, A) = 2, 'wild2-embedded-zero-pos');
  B := A;
  Check(A = B, 'wild2-embedded-zero-equal');

  { Insert/Delete/Copy at edge offsets - all legal, defined results }
  Str1 := 'abcdef';
  Insert('XY', Str1, 1);
  Check(Str1 = 'XYabcdef', 'wild2-insert-front');
  Insert('Z', Str1, Length(Str1) + 1);
  Check(Str1 = 'XYabcdefZ', 'wild2-insert-past-end');
  Delete(Str1, 100, 5);
  Check(Str1 = 'XYabcdefZ', 'wild2-delete-beyond');
  Delete(Str1, 1, 2);
  Check(Str1 = 'abcdefZ', 'wild2-delete-front');
  Check(Copy(Str1, 100, 5) = '', 'wild2-copy-beyond');
  Check(Copy(Str1, 1, 1000) = 'abcdefZ', 'wild2-copy-overlong');
  Check(Pos('', Str1) = 0, 'wild2-pos-empty');

  { Val/Str round-trips at integer extremes }
  Str(Low(Int64), Str1);
  Check(Str1 = '-9223372036854775808', 'wild2-str-low-int64');
  Val(string(Str1), V64, SCode);
  Check((SCode = 0) and (V64 = Low(Int64)), 'wild2-val-low-int64');
  Str(High(UInt64), Str1);
  Check(Str1 = '18446744073709551615', 'wild2-str-high-uint64');
  Val(string(Str1), U64, SCode);
  Check((SCode = 0) and (U64 = High(UInt64)), 'wild2-val-high-uint64');
  Val('123xyz', V64, SCode);
  Check(SCode = 4, 'wild2-val-error-position');

  { overlapping Move in both directions vs a byte model }
  for I := 0 to 31 do
    Buf[I] := Byte(I);
  Move(Buf[0], Buf[8], 16);            { forward overlap }
  for I := 0 to 15 do
    Check(Buf[8 + I] = Byte(I), 'wild2-move-overlap-fwd');
  for I := 0 to 31 do
    Buf[I] := Byte(I);
  Move(Buf[8], Buf[0], 16);            { backward overlap }
  for I := 0 to 15 do
    Check(Buf[I] = Byte(8 + I), 'wild2-move-overlap-back');

  { nil through is/as; class references; Assigned on proc vars }
  Obj := nil;
  Check(not (Obj is TBase), 'wild2-nil-is');
  Check((Obj as TBase) = nil, 'wild2-nil-as');
  Obj := TMid.Create;
  try
    Check(Obj.ClassType = TMid, 'wild2-classtype-eq');
    ClsRef := TMid;
    Check(Obj.InheritsFrom(ClsRef), 'wild2-inheritsfrom-classref');
    Check(Obj.ClassParent = TBase, 'wild2-classparent');
  finally
    Obj.Free;
  end;
  ProcV := nil;
  Check(not Assigned(ProcV), 'wild2-procvar-nil');
  ProcV := FnInc3;
  Check(Assigned(ProcV), 'wild2-procvar-assigned');
  Check(ProcV(4) = 7, 'wild2-procvar-call');

  { subrange type arithmetic promotes to the base type }
  Dig := 100;
  I := Dig * Dig;
  Check(I = 10000, 'wild2-subrange-mul');
  Dig := TDigits((I - 9950) * 2);      { back in range: 100 }
  Check(Dig = 100, 'wild2-subrange-roundtrip');

  { enum ord round-trips and successor walks }
  E := weZero;
  K := 0;
  while E < weFive do
  begin
    E := Succ(E);
    Inc(K);
  end;
  Check(K = 5, 'wild2-enum-succ-walk');
  Check(Ord(weFive) = 5, 'wild2-enum-ord');
  Check(TWildEnum(3) = weThree, 'wild2-enum-cast');
  Check(Pred(weTwo) = weOne, 'wild2-enum-pred');
  for E := Low(TWildEnum) to High(TWildEnum) do
    Mix(UInt64(Ord(E)));
end;

{ ---------------------------------------------------------------- }
{ 21. Checked arithmetic, full boolean evaluation and Comp forms.   }
{ holey enums, NaN comparisons, generic rotation, pointer math,     }
{ shortstring chains, dynamic/message dispatch, precedence pairs,   }
{ Val dialect table. All gray oracles pinned on Delphi 12.2 Win64   }
{ via probe5.dpr (stable across O+/O-).                             }
{ ---------------------------------------------------------------- }

{$Q+}
function TryMulQ(A, B: Int64; var R: Int64): Boolean;
begin
  Result := True;
  try
    R := A * B;
  except
    on EIntOverflow do
      Result := False;
  end;
end;

function TryAbsLowQ: Boolean;
var
  V, R: Int64;
begin
  { no Mix in here: digest folds must never sit on a conditional path,
    or compilers that differ in raising split the digest (rc1 did) }
  Result := True;
  V := OpaqueI(Low(Int64));
  try
    R := Abs(V);
    if R = V then
      Result := True;
  except
    on EIntOverflow do
      Result := False;
  end;
end;
{$Q-}

function MatA(var X: Integer): Integer; inline;
begin
  Inc(X);
  Result := X xor 5;
end;

function MatB(var X: Integer): Integer; inline;
begin
  Result := MatA(X) + MatA(X);
end;

function MatC(var X: Integer): Integer; inline;
begin
  Result := MatB(X) * 3 - MatA(X);
end;

function MatA2(var X: Integer): Integer;
begin
  Inc(X);
  Result := X xor 5;
end;

function MatB2(var X: Integer): Integer;
begin
  Result := MatA2(X) + MatA2(X);
end;

function MatC2(var X: Integer): Integer;
begin
  Result := MatB2(X) * 3 - MatA2(X);
end;

var
  FbTrail: AnsiString;

function FbT(Tag: Integer; V: Boolean): Boolean;
begin
  FbTrail := FbTrail + AnsiChar(Ord('a') + Tag);
  Result := V;
end;

function ExitGiftShop: Integer;
begin
  Result := 1;
  try
    try
      Exit(7);
    finally
      Result := Result + 100;
    end;
  finally
    Inc(Result, 1000);
  end;
end;

type
  THoley = (hA = 1, hB = 5, hC = 200);

  TOdd5 = packed record
    B: array[0..4] of Byte;
  end;

  TRotBox<T> = record
    A, B, C: T;
    procedure Rot;
  end;

procedure TRotBox<T>.Rot;
var
  Tmp: T;
begin
  Tmp := A;
  A := B;
  B := C;
  C := Tmp;
end;

type
  TDynA = class
    procedure P(K: Integer); dynamic;
  end;
  TDynB = class(TDynA)
    procedure P(K: Integer); override;
  end;
  TDynC = class(TDynB)
  end;

procedure TDynA.P(K: Integer);
begin
  FbTrail := FbTrail + 'A' + AnsiString(IntToStr(K));
end;

procedure TDynB.P(K: Integer);
begin
  FbTrail := FbTrail + 'B' + AnsiString(IntToStr(K));
  inherited P(K + 1);
end;

type
  TMsgRec = packed record
    ID: Cardinal;
    Data: Integer;
    Res: Integer;
  end;

  TMsgThing = class
    procedure M100(var M: TMsgRec); message 100;
    procedure M413(var M: TMsgRec); message 413;
    procedure DefaultHandler(var Message); override;
  end;

procedure TMsgThing.M100(var M: TMsgRec);
begin
  M.Res := M.Data * 2;
end;

procedure TMsgThing.M413(var M: TMsgRec);
begin
  M.Res := M.Data - 7;
end;

procedure TMsgThing.DefaultHandler(var Message);
begin
  TMsgRec(Message).Res := -1;
end;

const
  FoldedTenthSq: Double = 0.1 * 0.1;

procedure FbTryVal(const S: string; const Name: AnsiString;
  ExpectV, ExpectCode: Integer);
var
  V, Code: Integer;
begin
  Val(S, V, Code);
  Check((V = ExpectV) and (Code = ExpectCode), Name);
end;

procedure RunArithmeticControlForms;
type
  TBoxByte = TRotBox<Byte>;
  TBoxI64 = TRotBox<Int64>;
  TBoxSet = TRotBox<TSmallSet>;
  TBoxOdd = TRotBox<TOdd5>;
label
  13;
var
  R64, V64: Int64;
  I, K, XA, XB, RA, RB, Pass, Hits, Acc: Integer;
  CompV: Comp;
  E: THoley;
  SubT: ShortInt;
  BByte: Byte;
  HiBound: Byte;
  NanU: record
    case Boolean of
      True: (U: UInt64);
      False: (D: Double);
  end;
  BoxB: TBoxByte;
  BoxI: TBoxI64;
  BoxS: TBoxSet;
  BoxO: TBoxOdd;
  WordArrLoc: array[0..63] of Word;
  P, Q: PWord;
  NDist: NativeInt;
  Str5: string[5];
  Str9: string[9];
  AnsiSrc: AnsiString;
  DynObjs: array[0..2] of TDynA;
  Thing: TMsgThing;
  MsgRec: TMsgRec;
  RtBits: UInt64;
  Foldbits: UInt64;
  XD: Double;
  MethA, MethB: TCalcFunc;
  Obj: TBase;
  BoolR: Boolean;
  Code: Integer;
begin
  { checked arithmetic truth map (pinned on Delphi via probe5) }
  Check(TryMulQ(3037000499, 3037000499, R64), 'fb1-qplus-mul-fits');
  Check(R64 = 9223372030926249001, 'fb1-qplus-mul-value');
  Check(UInt64(R64) = OracleMulLow(3037000499, 3037000499),
    'fb1-qplus-mul-oracle');
  Check(not TryMulQ(3037000500, 3037000500, R64), 'fb1-qplus-mul-overflows');
  Check(not TryMulQ(High(Int64) div 2, 3, R64), 'fb1-qplus-mul-high3');
  Check(TryMulQ(High(Int64) div 2, 2, R64), 'fb1-qplus-mul-high2');
  Check(not TryAbsLowQ, 'fb1-qplus-abs-low');

  { inline matryoshka vs no-inline twins }
  for I := 0 to 49 do
  begin
    XA := I;
    RA := MatC(XA);
    XB := I;
    RB := MatC2(XB);
    Check(RA = RB, 'fb1-inline-matryoshka-result');
    Check(XA = XB, 'fb1-inline-matryoshka-mutation');
  end;

  { full boolean evaluation trail (Delphi pin: 'ac' / 'abc') }
  Hits := 0;
  FbTrail := '';
  if FbT(0, False) and FbT(1, True) or not FbT(2, False) then
    Inc(Hits);
  Check(FbTrail = 'ac', 'fb1-bminus-shortcut-trail');
{$B+}
  FbTrail := '';
  if FbT(0, False) and FbT(1, True) or not FbT(2, False) then
    Inc(Hits);
{$B-}
  Check(FbTrail = 'abc', 'fb1-bplus-full-trail');
  Check(Hits = 2, 'fb1-bplus-hits');

  { Comp keeps integer precision beyond 2^53 (Delphi pin) }
  CompV := 1;
  for K := 1 to 60 do
    CompV := CompV + CompV;
  Check(Trunc(CompV) = Int64(1) shl 60, 'fb1-comp-2p60');
  CompV := CompV + 1;
  Check(Trunc(CompV) - (Int64(1) shl 60) = 1, 'fb1-comp-2p60-plus1');
  CompV := CompV - 1;
  Check(Trunc(CompV) = Int64(1) shl 60, 'fb1-comp-roundtrip');

  { Exit value modified by finally blocks (Delphi pin: 1107) }
  Check(ExitGiftShop = 1107, 'fb1-exit-gift-shop');

  { holey enum: representation arithmetic, not value-set logic }
  E := THoley(3);
  Check(Ord(E) = 3, 'fb1-holey-ord');
  Check(Ord(Succ(E)) = 4, 'fb1-holey-succ');
  Check(Ord(Pred(hB)) = 4, 'fb1-holey-pred');
  Check((E > hA) and (E < hB), 'fb1-holey-compare-in-gap');
  K := 0;
  for I := 0 to 255 do
    if THoley(I) >= hC then
      Inc(K);
  Check(K = 56, 'fb1-holey-range-sweep');

  { loops at the edges of narrow/subrange types }
  K := 0;
  for BByte := 0 to 255 do
  begin
    Inc(K);
    if K > 300 then
      Break;
  end;
  Check(K = 256, 'fb1-byte-loop-full');
  K := 0;
  for SubT := -3 to 124 do
  begin
    Inc(K);
    if K > 300 then
      Break;
  end;
  Check(K = 128, 'fb1-subrange-loop');
  { loop bound is captured once; mutating the variable inside is legal }
  HiBound := 10;
  K := 0;
  for BByte := 0 to HiBound do
  begin
    Inc(K);
    HiBound := 3;
  end;
  Check(K = 11, 'fb1-loop-bound-captured-once');

  { NaN comparison truth table: IEEE says not(lt) must be TRUE.
    FINDING candidate: Delphi 12.2 Win64 yields FALSE for the inverted
    form at both O+ and O- (probe5), contradicting lt=FALSE. }
  NanU.U := UInt64($7FF8000000000001);
  Check(not (NanU.D < 1.0), 'fb1-nan-not-lt');
  Check(not (NanU.D >= 1.0), 'fb1-nan-not-ge');
  Check(NanU.D <> NanU.D, 'fb1-nan-ne-self');
  Check(not (NanU.D = NanU.D), 'fb1-nan-not-eq-self');

  { generic rotation: rot^3 = identity, rot^7 = rot }
  BoxB.A := 11; BoxB.B := 22; BoxB.C := 33;
  for I := 1 to 7 do
    BoxB.Rot;
  Check((BoxB.A = 22) and (BoxB.B = 33) and (BoxB.C = 11), 'fb1-rotbox-byte');
  BoxI.A := Int64(1) shl 40; BoxI.B := -1; BoxI.C := 7;
  for I := 1 to 6 do
    BoxI.Rot;
  Check((BoxI.A = Int64(1) shl 40) and (BoxI.B = -1) and (BoxI.C = 7),
    'fb1-rotbox-int64-identity');
  BoxS.A := [1, 3]; BoxS.B := [5]; BoxS.C := [0, 31];
  BoxS.Rot;
  Check((BoxS.A = [5]) and (BoxS.B = [0, 31]) and (BoxS.C = [1, 3]),
    'fb1-rotbox-set');
  for K := 0 to 4 do
  begin
    BoxO.A.B[K] := Byte(K);
    BoxO.B.B[K] := Byte(K + 10);
    BoxO.C.B[K] := Byte(K + 20);
  end;
  BoxO.Rot;
  Check((BoxO.A.B[2] = 12) and (BoxO.B.B[2] = 22) and (BoxO.C.B[2] = 2),
    'fb1-rotbox-odd5');

  { pointer math with negative offsets and pointer difference }
{$POINTERMATH ON}
  for I := 0 to 63 do
    WordArrLoc[I] := Word(I * 7);
  P := @WordArrLoc[32];
  P[-5] := 111;
  Check(WordArrLoc[27] = 111, 'fb1-pmath-negative-index');
  Q := P + 9;
  Q^ := 222;
  Check(WordArrLoc[41] = 222, 'fb1-pmath-plus');
  Inc(P, -3);
  Dec(P, -8);
  P^ := 333;
  Check(WordArrLoc[37] = 333, 'fb1-pmath-inc-dec-negative');
  NDist := Q - P;
  Check(NDist = 4, 'fb1-pmath-difference-elements');
{$POINTERMATH OFF}

  { shortstring chains with truncation at every write }
  AnsiSrc := 'abcdefgh';
  Str5 := ShortString(AnsiSrc);
  Check(Str5 = 'abcde', 'fb1-shortstring-write-trunc');
  Str9 := Str5 + Str5;
  Check(Str9 = 'abcdeabcd', 'fb1-shortstring-concat-trunc');
  Str5 := Copy(Str9, 2, 7);
  Check(Str5 = 'bcdea', 'fb1-shortstring-copy-trunc');
  Str9 := Str9 + Str9[9];
  Check(Str9 = 'abcdeabcd', 'fb1-shortstring-append-at-cap');

  { dynamic dispatch with inherited and a DMT-inheriting leaf }
  DynObjs[0] := TDynA.Create;
  DynObjs[1] := TDynB.Create;
  DynObjs[2] := TDynC.Create;
  try
    FbTrail := '';
    for I := 0 to 2 do
      DynObjs[I].P(I);
    Check(FbTrail = 'A0B1A2B2A3', 'fb1-dynamic-dispatch-trail');
  finally
    for I := 0 to 2 do
      DynObjs[I].Free;
  end;

  { message dispatch incl. DefaultHandler }
  Thing := TMsgThing.Create;
  try
    Acc := 0;
    for I := 98 to 414 do
    begin
      MsgRec.ID := Cardinal(I);
      MsgRec.Data := I * 3;
      MsgRec.Res := 0;
      Thing.Dispatch(MsgRec);
      Inc(Acc, MsgRec.Res);
    end;
    { model: 100 -> 600, 413 -> 1232, other 315 ids -> -1 }
    Check(Acc = 600 + 1232 - 315, 'fb1-message-dispatch-acc');
  finally
    Thing.Free;
  end;

  { compile-time folded float vs runtime computation (Delphi: identical) }
  Move(FoldedTenthSq, Foldbits, 8);
  XD := 0.1;
  if OpaqueI(0) <> 0 then
    XD := 0.2;
  XD := XD * XD;
  Move(XD, RtBits, 8);
  Check(RtBits = Foldbits, 'fb1-double-rounding-fold');
  Check(Foldbits = UInt64($3F847AE147AE147C), 'fb1-fold-bits-pinned');

  { method pointers from virtual methods bind through the VMT }
  Obj := TMid.Create;
  try
    MethA := Obj.Calc;
    MethB := Obj.Calc;
    Check(MethA(4) = ModelCalc(1, 4), 'fb1-methptr-late-binding');
    Check((TMethod(MethA).Code = TMethod(MethB).Code) and
      (TMethod(MethA).Data = TMethod(MethB).Data), 'fb1-methptr-equal-fields');
    Check(Assigned(MethA), 'fb1-methptr-assigned');
  finally
    Obj.Free;
  end;

  { precedence pairs: bare expression vs fully parenthesized }
  K := -5 mod 3;
  Check(K = -(5 mod 3), 'fb1-precedence-unary-mod');
  Check(K = -2, 'fb1-precedence-unary-mod-value');
  BoolR := not False = False;
  Check(BoolR = ((not False) = False), 'fb1-precedence-not-eq');
  Check(not BoolR, 'fb1-precedence-not-eq-value');
  Check(3 - -2 = 5, 'fb1-precedence-double-minus');
  Pass := 0;
13:
  Inc(Pass);
  if Pass < 2 then
    goto 13;
  Check(Pass = 2, 'fb1-numeric-label-goto');

  { Val dialect table (every expectation pinned on Delphi via probe5) }
  FbTryVal('$1F', 'fb1-val-dollar', 31, 0);
  FbTryVal('0x1F', 'fb1-val-0x', 31, 0);
  FbTryVal('%101', 'fb1-val-percent', 0, 1);
  FbTryVal('&17', 'fb1-val-ampersand', 0, 1);
  FbTryVal(' 42', 'fb1-val-leading-space', 42, 0);
  FbTryVal('42 ', 'fb1-val-trailing-space', 42, 3);
  FbTryVal('+-3', 'fb1-val-plus-minus', 0, 2);
  FbTryVal('', 'fb1-val-empty', 0, 1);
  Val('9223372036854775808', V64, Code);
  Check((V64 = Low(Int64)) and (Code = 19), 'fb1-val-int64-overflow');
  Val('1e3', XD, Code);
  Check((Code = 0) and (XD = 1000.0), 'fb1-val-1e3');
  Val('.5', XD, Code);
  Check(Code = 0, 'fb1-val-dot5');
  Val('5.', XD, Code);
  Check(Code = 0, 'fb1-val-5dot');
  Mix(UInt64(UInt32(Acc)));
end;

{ ---------------------------------------------------------------- }
{ 22. Collection forms: classic TList/TStringList and generic       }
{ TList<T>/TDictionary machines against plain-array models.         }
{ Dictionary iteration order is implementation-defined and is       }
{ never folded into the digest - only lookup invariants are.        }
{ ---------------------------------------------------------------- }

procedure RunCollectionForms;
var
  SL: TStringList;
  L: TList;
  GL: TList<Integer>;
  RL: TList<TSRec>;
  Dict: TDictionary<Integer, AnsiString>;
  Collection: TCollection;
  CollectionItem: TCollectionItem;
  ModelInts: array[0..255] of Integer;
  ModelKeys: array[0..127] of Integer;
  ModelVals: array[0..127] of AnsiString;
  ModelCount, I, J, K, Op, Position: Integer;
  Rec: TSRec;
  S: AnsiString;
  Found: Boolean;
  ValS: AnsiString;
  SortValues: TArray<Integer>;
begin
  { TStringList machine: Add/Insert/Delete/IndexOf against a model }
  SL := TStringList.Create;
  try
    ModelCount := 0;
    for I := 0 to 399 do
    begin
      Op := Integer(Rnd mod 4);
      if ((Op <= 1) or (ModelCount = 0)) and (ModelCount < 200) then
      begin
        S := AnsiString('item') + AnsiString(IntToStr(Integer(Rnd and $FFF)));
        SL.Add(string(S));
        ModelInts[ModelCount] := Length(S);
        Inc(ModelCount);
      end else if Op = 2 then
      begin
        Position := Integer(Rnd mod UInt64(ModelCount));
        SL.Delete(Position);
        for J := Position to ModelCount - 2 do
          ModelInts[J] := ModelInts[J + 1];
        Dec(ModelCount);
      end else begin
        Position := Integer(Rnd mod UInt64(ModelCount + 1));
        SL.Insert(Position, 'ins');
        for J := ModelCount downto Position + 1 do
          ModelInts[J] := ModelInts[J - 1];
        ModelInts[Position] := 3;
        Inc(ModelCount);
      end;
      Check(SL.Count = ModelCount, 'coll-stringlist-count');
      if ModelCount > 0 then
      begin
        Position := (I * 13) mod ModelCount;
        Check(Length(SL[Position]) = ModelInts[Position],
          'coll-stringlist-element-length');
      end;
    end;
    SL.Clear;
    SL.Add('delta');
    SL.Add('alpha');
    SL.Add('charlie');
    SL.Add('bravo');
    SL.Sort;
    Check((SL[0] = 'alpha') and (SL[1] = 'bravo') and (SL[2] = 'charlie') and
      (SL[3] = 'delta'), 'coll-stringlist-sort');
    Check(SL.IndexOf('charlie') = 2, 'coll-stringlist-indexof');
    Check(SL.IndexOf('missing') = -1, 'coll-stringlist-indexof-missing');
  finally
    SL.Free;
  end;

  { classic TList holding integers disguised as pointers }
  L := TList.Create;
  try
    for I := 0 to 99 do
      L.Add(Pointer(NativeInt(I * 7 + 1)));
    Check(L.Count = 100, 'coll-tlist-count');
    L.Delete(50);
    Check(NativeInt(L[50]) = 51 * 7 + 1, 'coll-tlist-delete-shift');
    L.Insert(0, Pointer(NativeInt(-5)));
    Check(NativeInt(L[0]) = -5, 'coll-tlist-insert-front');
    Check(NativeInt(L[1]) = 1, 'coll-tlist-insert-shifted');
    Check(L.IndexOf(Pointer(NativeInt(30 * 7 + 1))) = 31, 'coll-tlist-indexof');
  finally
    L.Free;
  end;

  { ClearAndResetID is a Delphi RTL contract: Clear alone keeps the next
    collection item ID, while ClearAndResetID starts it again at zero. }
  Collection := TCollection.Create(TCollectionItem);
  try
    Check(Collection.Add.ID = 0, 'coll-clear-reset-first-id');
    Check(Collection.Add.ID = 1, 'coll-clear-reset-second-id');
    Collection.ClearAndResetID;
    CollectionItem := Collection.Add;
    Check((Collection.Count = 1) and (CollectionItem.ID = 0),
      'coll-clear-reset-restarts-id');
  finally
    Collection.Free;
  end;

  { generic TList<Integer> machine }
  GL := TList<Integer>.Create;
  try
    ModelCount := 0;
    for I := 0 to 499 do
    begin
      Op := Integer(Rnd mod 3);
      if ((Op <> 0) or (ModelCount = 0)) and (ModelCount < 256) then
      begin
        K := Integer(Rnd);
        GL.Add(K);
        ModelInts[ModelCount] := K;
        Inc(ModelCount);
      end else begin
        Position := Integer(Rnd mod UInt64(ModelCount));
        GL.Delete(Position);
        for J := Position to ModelCount - 2 do
          ModelInts[J] := ModelInts[J + 1];
        Dec(ModelCount);
      end;
      Check(GL.Count = ModelCount, 'coll-glist-count');
      if ModelCount > 0 then
      begin
        Position := (I * 17) mod ModelCount;
        Check(GL[Position] = ModelInts[Position], 'coll-glist-element');
      end;
    end;
    K := 0;
    for I in GL do
      Inc(K);
    Check(K = ModelCount, 'coll-glist-forin-count');

    { Delphi TList<T>.BinarySearch writes an Integer insertion index even on
      Win64. Keep both default/comparer overloads and the not-found position. }
    GL.Clear;
    GL.Add(1);
    GL.Add(3);
    GL.Add(5);
    Position := -1;
    Check(GL.BinarySearch(3, Position) and (Position = 1),
      'coll-generic-binarysearch-integer-default');
    Position := -1;
    Check(not GL.BinarySearch(4, Position, TComparer<Integer>.Default) and
      (Position = 2), 'coll-generic-binarysearch-integer-insert');
  finally
    GL.Free;
  end;

  { TList<record with managed field>: value semantics of items }
  RL := TList<TSRec>.Create;
  try
    for I := 0 to 49 do
    begin
      Rec.S := AnsiString('rec') + AnsiString(IntToStr(I));
      Rec.N := I * 11;
      RL.Add(Rec);
    end;
    Rec := RL[25];
    Check(Rec.S = 'rec25', 'coll-reclist-string');
    Check(Rec.N = 275, 'coll-reclist-int');
    Rec.S := 'mutated';
    Check(RL[25].S = 'rec25', 'coll-reclist-value-semantics');
    RL.Delete(0);
    Check(RL[24].S = 'rec25', 'coll-reclist-delete-shift');
  finally
    RL.Free;
  end;

  { TDictionary machine: lookup invariants only, no iteration order }
  Dict := TDictionary<Integer, AnsiString>.Create;
  try
    ModelCount := 0;
    for I := 0 to 299 do
    begin
      K := Integer(Rnd and $3FF);
      Found := False;
      for J := 0 to ModelCount - 1 do
        if ModelKeys[J] = K then
        begin
          Found := True;
          Position := J;
          Break;
        end;
      case Rnd mod 3 of
        0, 1:
          begin
            ValS := AnsiString('v') + AnsiString(IntToStr(K xor 555));
            Dict.AddOrSetValue(K, ValS);
            if Found then
              ModelVals[Position] := ValS
            else if ModelCount < 128 then
            begin
              ModelKeys[ModelCount] := K;
              ModelVals[ModelCount] := ValS;
              Inc(ModelCount);
            end else
              Dict.Remove(K);   { keep model bounded: undo the add }
          end;
        2:
          begin
            Check(Dict.ContainsKey(K) = Found, 'coll-dict-containskey');
            if Found then
            begin
              Check(Dict.TryGetValue(K, ValS), 'coll-dict-trygetvalue');
              Check(ValS = ModelVals[Position], 'coll-dict-value');
              Dict.Remove(K);
              for J := Position to ModelCount - 2 do
              begin
                ModelKeys[J] := ModelKeys[J + 1];
                ModelVals[J] := ModelVals[J + 1];
              end;
              Dec(ModelCount);
            end;
          end;
      end;
      Check(Dict.Count = ModelCount, 'coll-dict-count');
    end;
    for J := 0 to ModelCount - 1 do
    begin
      Check(Dict.TryGetValue(ModelKeys[J], ValS), 'coll-dict-final-sweep');
      Check(ValS = ModelVals[J], 'coll-dict-final-value');
    end;
    Mix(UInt64(UInt32(ModelCount)));
  finally
    Dict.Free;
  end;

  { Delphi static generic TArray.Sort facade: all three overload shapes. }
  SortValues := [9, 4, 3, 2, 8];
  TArray.Sort<Integer>(SortValues);
  Check((SortValues[0] = 2) and (SortValues[4] = 9),
    'coll-tarray-sort-default');

  SortValues := [5, 1, 4, 2, 3];
  TArray.Sort<Integer>(SortValues, TComparer<Integer>.Default);
  Check((SortValues[0] = 1) and (SortValues[4] = 5),
    'coll-tarray-sort-comparer');

  SortValues := [9, 4, 3, 2, 8];
  TArray.Sort<Integer>(SortValues, TComparer<Integer>.Default, 1, 3);
  Check((SortValues[0] = 9) and (SortValues[1] = 2) and
    (SortValues[2] = 3) and (SortValues[3] = 4) and
    (SortValues[4] = 8), 'coll-tarray-sort-range');
  for I := 0 to High(SortValues) do
    Mix(UInt64(UInt32(SortValues[I])));

end;

{ ---------------------------------------------------------------- }
{ 23. Interface delegation and related declaration forms.           }
{ method resolution clauses, equal-bit signed/unsigned compares,    }
{ const-param aliasing through a global. Pinned via probe7.dpr.     }
{ ---------------------------------------------------------------- }

type
  IThing = interface
    ['{B1E60C1A-2A9F-45D2-8E30-9C1D14A70001}']
    function ThingTag: Integer;
  end;

  TThingInner = class(TInterfacedObject, IThing)
    function ThingTag: Integer;
  end;

  TThingOuter = class(TInterfacedObject, IThing)
  private
    FInner: IThing;
  public
    constructor Create;
    property Inner: IThing read FInner implements IThing;
  end;

  TThingRenamed = class(TInterfacedObject, IThing)
    function MyName: Integer;
    function IThing.ThingTag = MyName;
  end;

function TThingInner.ThingTag: Integer;
begin
  Result := 777;
end;

constructor TThingOuter.Create;
begin
  inherited Create;
  FInner := TThingInner.Create;
end;

function TThingRenamed.MyName: Integer;
begin
  Result := 888;
end;

type
  TIntArr2 = array of Integer;

var
  AliasArr: TIntArr2;

procedure PokeAlias;
begin
  AliasArr[0] := AliasArr[0] + 7;
end;

function TwoReadsConst(const A: TIntArr2): Integer; inline;
begin
  Result := A[0];
  PokeAlias;
  Result := Result * 1000 + A[0];
end;

procedure RunDelegationForms;
var
  Outer, Ren: IThing;
  I64: Int64;
  U64: UInt64;
begin
  { delegation and resolution clauses route to the right bodies }
  Outer := TThingOuter.Create;
  Check(Outer.ThingTag = 777, 'fb2-implements-delegation');
  Ren := TThingRenamed.Create;
  Check(Ren.ThingTag = 888, 'fb2-method-resolution-clause');
  Outer := nil;
  Ren := nil;

  { equal bit patterns across the sign divide compare by VALUE on Delphi }
  I64 := OpaqueI(-1);
  U64 := OpaqueU(UInt64($FFFFFFFFFFFFFFFF));
  Check(not (I64 = U64), 'fb2-equal-bits-not-equal');
  Check(I64 < U64, 'fb2-equal-bits-lt');
  Check(not (I64 > U64), 'fb2-equal-bits-not-gt');
  I64 := OpaqueI(Low(Int64));
  U64 := OpaqueU(UInt64(1) shl 63);
  Check(not (I64 = U64), 'fb2-low-vs-2p63-not-equal');
  Check(I64 < U64, 'fb2-low-vs-2p63-lt');

  { const dyn-array param aliased via a global: the second read must see
    the mutation (Delphi pin: 42049) }
  SetLength(AliasArr, 1);
  AliasArr[0] := 42;
  Check(TwoReadsConst(AliasArr) = 42049, 'fb2-const-param-alias-reload');
  SetLength(AliasArr, 0);
end;


{ ---------------------------------------------------------------- }
{ 24. Loop & stack-frame forms: repeat/until machines, char/enum    }
{ counters, goto escaping nested loops, function-computed bounds    }
{ (must be evaluated exactly once), 40KB stack frames (large-offset }
{ addressing), and managed locals born and finalized on every call  }
{ of a nested routine driven from a loop.                           }
{ ---------------------------------------------------------------- }

var
  BoundCalls: Integer;

function LoopHigh: Integer;
begin
  Inc(BoundCalls);
  Result := 9;
end;

function BigFrameChecksum(Seed: Integer): Integer;
var
  Big: array[0..40959] of Byte;
  Tail: Integer;
  K: Integer;
begin
  Tail := Seed * 3;
  for K := 0 to High(Big) do
    Big[K] := Byte(Seed + K * 7);
  Result := 0;
  for K := 0 to High(Big) do
    if (K and 4095) = 0 then
      Inc(Result, Big[K]);
  Inc(Result, Tail);
end;

function BigFrameOracle(Seed: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 0 to 40959 do
    if (K and 4095) = 0 then
      Inc(Result, Byte(Seed + K * 7));
  Inc(Result, Seed * 3);
end;

type
  TManagedLocalRec = record
    S: AnsiString;
    Arr: array of Integer;
    Intf: IInterface;
  end;

procedure RunLoopStackForms;
label
  EscapeOut;
var
  I, J, K, Sum, Iter, WSum: Integer;
  Ch: AnsiChar;
  E: TWildEnum;

  procedure SpinManaged(N: Integer);
  var
    L: TManagedLocalRec;
  begin
    L.S := AnsiString('spin') + AnsiString(IntToStr(N));
    SetLength(L.Arr, (N and 7) + 1);
    L.Arr[0] := N;
    L.Intf := TGuard.Create;
    Check(Length(L.S) >= 5, 'loop-managed-local-live');
    Check(L.Arr[0] = N, 'loop-managed-local-array');
  end;

begin
  { repeat..until runs at least once }
  K := 0;
  repeat
    Inc(K);
  until K >= 0;
  Check(K = 1, 'loop-repeat-runs-once');

  { repeat vs while mirror }
  K := 100;
  Sum := 0;
  repeat
    Inc(Sum, K);
    Dec(K, 7);
  until K < 0;
  I := 100;
  WSum := 0;
  while I >= 0 do
  begin
    Inc(WSum, I);
    Dec(I, 7);
  end;
  Check(Sum = WSum, 'loop-repeat-vs-while');

  { Continue in repeat jumps to the CONDITION, not past it }
  K := 0;
  Iter := 0;
  repeat
    Inc(Iter);
    if (Iter and 1) = 1 then
      Continue;
    Inc(K);
  until Iter >= 10;
  Check((Iter = 10) and (K = 5), 'loop-repeat-continue');

  { Break out of an otherwise infinite repeat }
  Iter := 0;
  repeat
    Inc(Iter);
    if Iter = 4 then
      Break;
  until False;
  Check(Iter = 4, 'loop-repeat-break');

  { character counter }
  K := 0;
  Sum := 0;
  for Ch := 'a' to 'z' do
  begin
    Inc(K);
    Inc(Sum, Ord(Ch));
  end;
  Check(K = 26, 'loop-char-count');
  Check(Sum = (Ord('a') + Ord('z')) * 26 div 2, 'loop-char-sum');

  { enum counter with Continue/Break }
  K := 0;
  for E := Low(TWildEnum) to High(TWildEnum) do
  begin
    if E = weTwo then
      Continue;
    if E = weFive then
      Break;
    Inc(K);
  end;
  Check(K = 4, 'loop-enum-continue-break');

  { goto escaping a nested double loop }
  Sum := 0;
  for I := 1 to 10 do
    for J := 1 to 10 do
    begin
      Inc(Sum);
      if I * J = 12 then
        goto EscapeOut;
    end;
EscapeOut:
  { I=1 runs all ten, I=2 stops at J=6 }
  Check(Sum = 16, 'loop-goto-escape-nested');

  { loop bounds computed by a function: evaluated exactly once }
  BoundCalls := 0;
  Sum := 0;
  for I := 0 to LoopHigh do
    Inc(Sum, I);
  Check(Sum = 45, 'loop-func-bound-sum');
  Check(BoundCalls = 1, 'loop-func-bound-called-once');
  BoundCalls := 0;
  K := 0;
  for I := LoopHigh downto 0 do
    Inc(K);
  Check(K = 10, 'loop-func-bound-downto');
  Check(BoundCalls = 1, 'loop-func-bound-downto-once');

  { 40KB frame: large stack offsets past the array }
  for I := 0 to 4 do
    Check(BigFrameChecksum(I) = BigFrameOracle(I), 'loop-big-stack-frame');

  { managed locals initialized and finalized on every iteration }
  TGuard.Alive := 0;
  for I := 1 to 50 do
    SpinManaged(I);
  Check(TGuard.Alive = 0, 'loop-managed-local-fini');
end;

{ ---------------------------------------------------------------- }
{ 25. Delphi feature sweep: class/record/type helpers, the wider    }
{ class-operator set (In/Explicit/Bitwise/LogicalNot/Negative),     }
{ dyn-array Insert/Delete/Concat, resourcestring, Equals and        }
{ GetHashCode overrides, Default(T), writeable typed-const arrays.  }
{ ---------------------------------------------------------------- }

type
  TBaseHelper = class helper for TBase
    function CalcTwice(X: Integer): Integer;
  end;

  TFixHelper = record helper for TFix
    function DoubleRaw: Int64;
  end;

  TIntSqHelper = record helper for Integer
    function Sq: Integer;
  end;

  TFlags = record
    Bits: UInt32;
    class operator In(A: Integer; const F: TFlags): Boolean;
    class operator BitwiseAnd(const A, B: TFlags): TFlags;
    class operator BitwiseOr(const A, B: TFlags): TFlags;
    class operator LogicalNot(const A: TFlags): TFlags;
    class operator Explicit(V: UInt32): TFlags;
    class operator Explicit(const A: TFlags): UInt32;
    class operator Negative(const A: TFlags): TFlags;
    class operator Equal(const A, B: TFlags): Boolean;
    class operator NotEqual(const A, B: TFlags): Boolean;
  end;

function TBaseHelper.CalcTwice(X: Integer): Integer;
begin
  Result := Calc(X) * 2;                        { virtual through the helper }
end;

function TFixHelper.DoubleRaw: Int64;
begin
  Result := Raw * 2;
end;

function TIntSqHelper.Sq: Integer;
begin
  Result := Self * Self;
end;

class operator TFlags.In(A: Integer; const F: TFlags): Boolean;
begin
  Result := (F.Bits and (UInt32(1) shl (A and 31))) <> 0;
end;

class operator TFlags.BitwiseAnd(const A, B: TFlags): TFlags;
begin
  Result.Bits := A.Bits and B.Bits;
end;

class operator TFlags.BitwiseOr(const A, B: TFlags): TFlags;
begin
  Result.Bits := A.Bits or B.Bits;
end;

class operator TFlags.LogicalNot(const A: TFlags): TFlags;
begin
  Result.Bits := not A.Bits;
end;

class operator TFlags.Explicit(V: UInt32): TFlags;
begin
  Result.Bits := V;
end;

class operator TFlags.Explicit(const A: TFlags): UInt32;
begin
  Result := A.Bits;
end;

class operator TFlags.Negative(const A: TFlags): TFlags;
begin
  Result.Bits := (not A.Bits) + 1;
end;

class operator TFlags.Equal(const A, B: TFlags): Boolean;
begin
  Result := A.Bits = B.Bits;
end;

class operator TFlags.NotEqual(const A, B: TFlags): Boolean;
begin
  Result := A.Bits <> B.Bits;
end;

type
  TEqObj = class(TBase)
  public
    function Equals(Obj: TObject): Boolean; override;
    function GetHashCode: {$ifdef FPC}PtrInt{$else}Integer{$endif}; override;
  end;

function TEqObj.Equals(Obj: TObject): Boolean;
begin
  Result := (Obj is TEqObj) and (TEqObj(Obj).Tag = Tag);
end;

function TEqObj.GetHashCode: {$ifdef FPC}PtrInt{$else}Integer{$endif};
begin
  Result := Tag * 31 + 7;
end;

resourcestring
  RsMoon = 'moon-%d-%s';

type
  TResourceState = (resourceStateFirst, resourceStateSecond);

resourcestring
  RsFirstState = 'first %s';
  RsSecondState = 'second';

const
  ResourceStates: array[TResourceState] of string = (
    RsFirstState,
    RsSecondState);
  ResourceUnicode: UnicodeString = RsFirstState;
  ResourceAnsi: AnsiString = RsSecondState;
  ResourceWide: WideString = RsSecondState;

{$J+}
const
  WritableArr: array[0..2] of Integer = (10, 20, 30);
{$J-}

procedure RunDelphiFeatureForms;
var
  Obj: TBase;
  EqA, EqB, EqC: TEqObj;
  Fx: TFix;
  I, K: Integer;
  Arr, Arr2, ArrCat: TIntArr2;
  F1, F2, F3: TFlags;
  S: AnsiString;
  DefRec: TSRec;
  DefFix: TFix;
begin
  { class helper calling a virtual method keeps late binding }
  Obj := TMid.Create;
  try
    Check(Obj.CalcTwice(5) = ModelCalc(1, 5) * 2, 'dlf-class-helper-virtual');
  finally
    Obj.Free;
  end;

  { record helper and intrinsic-type helper }
  Fx := TFix.Make(3, 250);
  Check(Fx.DoubleRaw = 6500, 'dlf-record-helper');
  I := 12;
  Check(I.Sq = 144, 'dlf-type-helper-int');
  I := -9;
  Check(I.Sq = 81, 'dlf-type-helper-negative');

  { class operators: In / bitwise / not / explicit / negative }
  F1 := TFlags($0000000F);
  F2 := TFlags($000000F0);
  Check(3 in F1, 'dlf-op-in-true');
  Check(not (4 in F1), 'dlf-op-in-false');
  F3 := F1 or F2;
  Check(UInt32(F3) = $FF, 'dlf-op-bitor');
  F3 := F3 and F2;
  Check(UInt32(F3) = $F0, 'dlf-op-bitand');
  F3 := not F1;
  Check(UInt32(F3) = $FFFFFFF0, 'dlf-op-lognot');
  F3 := -F1;
  Check(UInt32(F3) = UInt32(-15), 'dlf-op-negative');
  Check(F1 <> F2, 'dlf-op-noteq');
  Check(F1 = TFlags($0000000F), 'dlf-op-eq');

  { dyn array Insert/Delete/Concat }
  SetLength(Arr, 3);
  Arr[0] := 1;
  Arr[1] := 2;
  Arr[2] := 3;
  Insert(99, Arr, 1);
  Check((Length(Arr) = 4) and (Arr[0] = 1) and (Arr[1] = 99) and
    (Arr[2] = 2) and (Arr[3] = 3), 'dlf-dynarray-insert');
  Delete(Arr, 0, 2);
  Check((Length(Arr) = 2) and (Arr[0] = 2) and (Arr[1] = 3),
    'dlf-dynarray-delete');
  SetLength(Arr2, 2);
  Arr2[0] := 7;
  Arr2[1] := 8;
  ArrCat := Concat(Arr, Arr2);
  Check((Length(ArrCat) = 4) and (ArrCat[0] = 2) and (ArrCat[3] = 8),
    'dlf-dynarray-concat');
  ArrCat[0] := 555;
  Check(Arr[0] = 2, 'dlf-dynarray-concat-unshared');

  { resourcestring through Format }
  S := AnsiString(Format(string(RsMoon), [7, 'bot']));
  Check(S = 'moon-7-bot', 'dlf-resourcestring-format');

  { resourcestring references materialized in typed string constants }
  Check(ResourceStates[resourceStateFirst] = 'first %s',
    'dlf-resourcestring-typed-array-first');
  Check(ResourceStates[resourceStateSecond] = 'second',
    'dlf-resourcestring-typed-array-second');
  Check(ResourceUnicode = 'first %s',
    'dlf-resourcestring-typed-unicode');
  Check(string(ResourceAnsi) = 'second',
    'dlf-resourcestring-typed-ansi');
  Check(string(ResourceWide) = 'second',
    'dlf-resourcestring-typed-wide');
  Check(Format(ResourceStates[resourceStateFirst], ['X']) = 'first X',
    'dlf-resourcestring-typed-format');

  { Equals / GetHashCode overrides }
  EqA := TEqObj.Create;
  EqB := TEqObj.Create;
  EqC := TEqObj.Create;
  try
    EqA.Tag := 42;
    EqB.Tag := 42;
    EqC.Tag := 43;
    Check(EqA.Equals(EqB), 'dlf-equals-same-tag');
    Check(not EqA.Equals(EqC), 'dlf-equals-diff-tag');
    Check(EqA.GetHashCode = EqB.GetHashCode, 'dlf-hashcode-stable');
    Check(EqA.GetHashCode = 42 * 31 + 7, 'dlf-hashcode-value');
  finally
    EqA.Free;
    EqB.Free;
    EqC.Free;
  end;

  { Default(T) zeroes everything including managed fields }
  K := 5;
  K := Default(Integer);
  Check(K = 0, 'dlf-default-int');
  DefRec.S := 'busy';
  DefRec.N := 9;
  DefRec := Default(TSRec);
  Check((DefRec.S = '') and (DefRec.N = 0), 'dlf-default-record');
  DefFix := Default(TFix);
  Check(DefFix.Raw = 0, 'dlf-default-operator-record');

  { writeable typed-const array }
  WritableArr[1] := WritableArr[1] + 5;
  Check(WritableArr[1] = 25, 'dlf-writable-const-array');
  Check(WritableArr[0] + WritableArr[2] = 40, 'dlf-writable-const-neighbors');
  WritableArr[1] := 20;                          { restore for reruns }
  Mix(UInt64(UInt32(F1.Bits)));
end;

{ ---------------------------------------------------------------- }
{ 26. Feature sweep 2: custom for-in enumerators, multi-index and   }
{ index-specifier properties, generic constraints and nested        }
{ specialization, variant arrays, TypInfo round-trips, re-raise.    }
{ ---------------------------------------------------------------- }

type
  TStepEnum = record
    FCur, FStop, FStep: Integer;
    function MoveNext: Boolean;
    property Current: Integer read FCur;
  end;

  TStepRange = record
    FFrom, FTo, FStep: Integer;
    function GetEnumerator: TStepEnum;
  end;

  TGrid = class
  private
    FCells: array[0..3, 0..3] of Integer;
    FPair: array[0..1] of Integer;
    function GetCell(R, C: Integer): Integer;
    procedure SetCell(R, C: Integer; V: Integer);
    function GetIndexed(Ix: Integer): Integer;
    procedure SetIndexed(Ix: Integer; V: Integer);
  public
    property Cell[R, C: Integer]: Integer read GetCell write SetCell; default;
    property First: Integer index 0 read GetIndexed write SetIndexed;
    property Second: Integer index 1 read GetIndexed write SetIndexed;
  end;

  TClassBox<T: TBase> = record
    Obj: T;
    function TagOf: Integer;
  end;

  TPairG<T> = record
    A, B: T;
  end;

function TStepEnum.MoveNext: Boolean;
begin
  Inc(FCur, FStep);
  Result := FCur <= FStop;
end;

function TStepRange.GetEnumerator: TStepEnum;
begin
  Result.FCur := FFrom - FStep;
  Result.FStop := FTo;
  Result.FStep := FStep;
end;

function StepRange(AFrom, ATo, AStep: Integer): TStepRange;
begin
  Result.FFrom := AFrom;
  Result.FTo := ATo;
  Result.FStep := AStep;
end;

function TGrid.GetCell(R, C: Integer): Integer;
begin
  Result := FCells[R and 3, C and 3];
end;

procedure TGrid.SetCell(R, C: Integer; V: Integer);
begin
  FCells[R and 3, C and 3] := V;
end;

function TGrid.GetIndexed(Ix: Integer): Integer;
begin
  Result := FPair[Ix];
end;

procedure TGrid.SetIndexed(Ix: Integer; V: Integer);
begin
  FPair[Ix] := V;
end;

function TClassBox<T>.TagOf: Integer;
begin
  Result := Obj.Tag;
end;

function ReRaiseDepth(Level: Integer): AnsiString;
begin
  Result := '';
  try
    try
      raise ERangeError.Create('deep-' + IntToStr(Level));
    except
      on E: ERangeError do
      begin
        Result := Result + 'inner:' + AnsiString(E.Message) + ';';
        raise;                                  { bare re-raise }
      end;
    end;
  except
    on E2: ERangeError do
      Result := Result + 'outer:' + AnsiString(E2.Message);
  end;
end;

procedure RunFeatureSweep2Forms;
var
  I, K, Sum: Integer;
  Grid: TGrid;
  MidObj: TMid;
  CBox: TClassBox<TMid>;
  PP: TPairG<TPairG<Integer>>;
  V: Variant;
  S: AnsiString;
begin
  { custom record enumerator drives for-in with a step }
  Sum := 0;
  K := 0;
  for I in StepRange(3, 21, 3) do
  begin
    Inc(Sum, I);
    Inc(K);
  end;
  Check(K = 7, 'dlf2-enumerator-count');
  Check(Sum = 3 + 6 + 9 + 12 + 15 + 18 + 21, 'dlf2-enumerator-sum');
  K := 0;
  for I in StepRange(10, 5, 1) do
    Inc(K);
  Check(K = 0, 'dlf2-enumerator-empty');

  { multi-index default property and index-specifier pair }
  Grid := TGrid.Create;
  try
    for I := 0 to 3 do
      for K := 0 to 3 do
        Grid[I, K] := I * 10 + K;
    Check(Grid[2, 3] = 23, 'dlf2-multiindex-property');
    Check(Grid.Cell[3, 1] = 31, 'dlf2-multiindex-named');
    Grid[5, 5] := 77;                            { masked to [1,1] }
    Check(Grid[1, 1] = 77, 'dlf2-multiindex-masked');
    Grid.First := 100;
    Grid.Second := 200;
    Check(Grid.First = 100, 'dlf2-index-specifier-first');
    Check(Grid.Second = 200, 'dlf2-index-specifier-second');
  finally
    Grid.Free;
  end;

  { generic constrained by a class type }
  MidObj := TMid.Create;
  try
    CBox.Obj := MidObj;
    Check(CBox.TagOf = 11, 'dlf2-generic-class-constraint');
  finally
    MidObj.Free;
  end;

  { nested generic specialization }
  PP.A.A := 1;
  PP.A.B := 2;
  PP.B.A := 30;
  PP.B.B := 40;
  Check(PP.A.A + PP.A.B + PP.B.A + PP.B.B = 73, 'dlf2-nested-generic');

  { variant arrays: 1D and element round-trips }
  V := VarArrayCreate([0, 4], varInteger);
  for I := 0 to 4 do
    V[I] := I * I;
  Check(V[3] = 9, 'dlf2-vararray-element');
  Check(VarArrayHighBound(V, 1) = 4, 'dlf2-vararray-highbound');
  Check(VarArrayLowBound(V, 1) = 0, 'dlf2-vararray-lowbound');
  Sum := 0;
  for I := 0 to 4 do
    Sum := Sum + Integer(V[I]);
  Check(Sum = 0 + 1 + 4 + 9 + 16, 'dlf2-vararray-sum');

  { TypInfo round-trips on enums }
  S := AnsiString(GetEnumName(TypeInfo(TWildEnum), 2));
  Check(S = 'weTwo', 'dlf2-typinfo-enumname');
  Check(GetEnumValue(TypeInfo(TWildEnum), 'weFour') = 4,
    'dlf2-typinfo-enumvalue');
  Check(GetEnumValue(TypeInfo(TWildEnum), 'weNope') = -1,
    'dlf2-typinfo-enumvalue-missing');

  { bare re-raise propagates the same exception object's message }
  S := ReRaiseDepth(3);
  Check(S = 'inner:deep-3;outer:deep-3', 'dlf2-reraise-message');
  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 27. Checked-mode forms: R+ sections where valid code must NOT     }
{ false-positive and genuine violations MUST raise ERangeError;     }
{ Q+ increments at the edges. Both directions are codegen paths.    }
{ ---------------------------------------------------------------- }

{$R+}
function RangeCleanSweep(Seed: Integer): Integer;
var
  Arr: array[0..15] of Integer;
  Sub: 1..100;
  EArr: array[TWildEnum] of Integer;
  E: TWildEnum;
  I, Idx: Integer;
begin
  Result := 0;
  for I := 0 to 15 do
    Arr[I] := Seed + I;
  for I := 0 to 63 do
  begin
    Idx := (Seed + I * 7) and 15;                { provably in range }
    Inc(Result, Arr[Idx]);
  end;
  Sub := (Seed and 63) + 1;                      { 1..64, in range }
  Inc(Result, Sub);
  Sub := Sub div 2 + 1;
  Inc(Result, Sub);
  for E := Low(TWildEnum) to High(TWildEnum) do
    EArr[E] := Ord(E) * Seed;
  Inc(Result, EArr[weThree]);
end;

function RangeViolationCaught(Kind: Integer; Bad: Integer): Boolean;
var
  Arr: array[0..4] of Integer;
  Dyn: array of Integer;
  Sub: 1..100;
  S: AnsiString;
  I: Integer;
begin
  Result := False;
  for I := 0 to 4 do
    Arr[I] := I;
  SetLength(Dyn, 3);
  S := 'abc';
  try
    case Kind of
      0: Mix(UInt64(UInt32(Arr[Bad])));          { static index out of range }
      1: Mix(UInt64(UInt32(Dyn[Bad])));          { dyn index out of range }
      2:
        begin
          Sub := Bad;                            { subrange assignment }
          Mix(UInt64(UInt32(Sub)));
        end;
      3: Mix(Ord(S[Bad]));                       { string index }
    end;
  except
    on ERangeError do
      Result := True;
  end;
end;
{$R-}

{$Q+}
function OverflowInc(Start: Integer): Boolean;
var
  V: Integer;
begin
  Result := False;
  V := Start;
  try
    Inc(V);
    if V = Low(Integer) then
      Result := False;
  except
    on EIntOverflow do
      Result := True;
  end;
end;
{$Q-}

procedure RunCheckedForms;
var
  I: Integer;
begin
  { valid computed indexing under R+ must never trip }
  for I := 0 to 19 do
    Check(RangeCleanSweep(I) = RangeCleanSweep(I), 'chk-rplus-deterministic');
  Check(RangeCleanSweep(0) > 0, 'chk-rplus-clean-runs');

  { genuine violations must raise, from runtime-opaque bad values }
  Check(RangeViolationCaught(0, Integer(OpaqueI(9))), 'chk-static-index-raises');
  Check(RangeViolationCaught(0, Integer(OpaqueI(-1))), 'chk-static-negative-raises');
  Check(RangeViolationCaught(1, Integer(OpaqueI(3))), 'chk-dyn-index-raises');
  Check(RangeViolationCaught(2, Integer(OpaqueI(200))), 'chk-subrange-raises');
  Check(RangeViolationCaught(2, Integer(OpaqueI(0))), 'chk-subrange-zero-raises');
  Check(not RangeViolationCaught(2, Integer(OpaqueI(55))), 'chk-subrange-valid-passes');
  Check(RangeViolationCaught(3, Integer(OpaqueI(9))), 'chk-string-index-raises');

  { Q+ increment at High(Integer) }
  Check(OverflowInc(Integer(OpaqueI(High(Integer)))), 'chk-qplus-inc-high');
  Check(not OverflowInc(Integer(OpaqueI(High(Integer) - 1))), 'chk-qplus-inc-ok');
end;

{ ---------------------------------------------------------------- }
{ 28. Published RTTI forms: M+ classes, GetPropInfo/GetOrdProp and  }
{ SetOrdProp round-trips on the portable TypInfo subset.            }
{ ---------------------------------------------------------------- }

type
{$M+}
  TRttiProbe = class
  private
    FCount: Integer;
    FName: AnsiString;
    FKind: TWildEnum;
  published
    property Count: Integer read FCount write FCount;
    property Kind: TWildEnum read FKind write FKind;
  public
    property NameStr: AnsiString read FName write FName;
  end;
{$M-}

procedure RunPublishedRttiForms;
var
  Obj: TRttiProbe;
  PI: PPropInfo;
begin
  Obj := TRttiProbe.Create;
  try
    Obj.Count := 4242;
    Obj.Kind := weFour;

    PI := GetPropInfo(Obj, 'Count');
    Check(PI <> nil, 'rtti-propinfo-found');
    Check(PI^.PropType^.Kind = tkInteger, 'rtti-propinfo-kind');
    Check(GetOrdProp(Obj, PI) = 4242, 'rtti-getordprop');
    SetOrdProp(Obj, PI, 1111);
    Check(Obj.Count = 1111, 'rtti-setordprop');

    PI := GetPropInfo(Obj, 'Kind');
    Check(PI <> nil, 'rtti-enum-propinfo');
    Check(PI^.PropType^.Kind = tkEnumeration, 'rtti-enum-kind');
    Check(GetOrdProp(Obj, PI) = Ord(weFour), 'rtti-enum-getord');
    SetOrdProp(Obj, PI, Ord(weOne));
    Check(Obj.Kind = weOne, 'rtti-enum-setord');

    Check(GetPropInfo(Obj, 'NameStr') = nil, 'rtti-public-not-published');
    Check(GetPropInfo(Obj, 'Missing') = nil, 'rtti-missing-prop');
  finally
    Obj.Free;
  end;
end;

{ ---------------------------------------------------------------- }
{ 29. Interface plumbing: cross-casting between two interfaces of   }
{ one object, COM identity through IUnknown, Supports(), lifetime   }
{ balance across the casts.                                         }
{ ---------------------------------------------------------------- }

type
  IAlpha = interface
    ['{7A1C0E10-11AA-4A80-9F10-C1D2E3F40A01}']
    function AVal: Integer;
  end;

  IBeta = interface
    ['{7A1C0E10-11AA-4A80-9F10-C1D2E3F40B02}']
    function BVal: Integer;
  end;

  TDual = class(TInterfacedObject, IAlpha, IBeta)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
    function AVal: Integer;
    function BVal: Integer;
  end;

constructor TDual.Create;
begin
  inherited Create;
  AtomicInc(Alive);
end;

destructor TDual.Destroy;
begin
  AtomicDec(Alive);
  inherited Destroy;
end;

function TDual.AVal: Integer;
begin
  Result := 10;
end;

function TDual.BVal: Integer;
begin
  Result := 20;
end;

procedure InterfacePlumbingBody;
var
  A: IAlpha;
  B, B2: IBeta;
  UA, UB: IInterface;
  Thing: IThing;
begin
  A := TDual.Create;
  Check(TDual.Alive = 1, 'intf-created');
  Check(A.AVal = 10, 'intf-direct-call');

  { cross-cast through QueryInterface }
  B := A as IBeta;
  Check(B.BVal = 20, 'intf-cross-cast');
  Check(TDual.Alive = 1, 'intf-cross-cast-same-object');

  { COM identity: both interfaces resolve to the same IUnknown }
  UA := A as IInterface;
  UB := B as IInterface;
  Check(UA = UB, 'intf-com-identity');

  { Supports: positive with an out var, negative leaves it nil }
  B2 := nil;
  Check(Supports(A, IBeta, B2), 'intf-supports-positive');
  Check(Assigned(B2) and (B2.BVal = 20), 'intf-supports-out');
  Thing := nil;
  Check(not Supports(A, IThing, Thing), 'intf-supports-negative');
  Check(not Assigned(Thing), 'intf-supports-negative-nil');
end;

procedure RunInterfacePlumbingForms;
begin
  { drain is asserted only after the body returns: hidden expression temps
    live until routine exit, and FPC holds them longer than Delphi within
    the same routine (dialect fact, mirrors the IdentityChainVal pattern) }
  TDual.Alive := 0;
  InterfacePlumbingBody;
  Check(TDual.Alive = 0, 'intf-fully-released');
end;

{ ---------------------------------------------------------------- }
{ 30. String-RTL edges and bit intrinsics: SetLength shrink/grow,   }
{ Copy with huge counts, StringOfChar, StringReplace, CompareStr,   }
{ Swap/Hi/Lo, Odd on negatives, Sqr wrap under Q-.                  }
{ ---------------------------------------------------------------- }

procedure RunStringEdgeForms;
var
  S, T: AnsiString;
  I, K: Integer;
  V: Integer;
  R64: Int64;
begin
  { shrink then grow: the kept prefix must survive, the tail is written
    explicitly before any read }
  S := 'abcdef';
  UniqueString(S);
  SetLength(S, 3);
  Check(S = 'abc', 'sre-shrink');
  SetLength(S, 6);
  Check(Length(S) = 6, 'sre-grow-length');
  Check((S[1] = 'a') and (S[2] = 'b') and (S[3] = 'c'), 'sre-grow-prefix');
  S[4] := 'X';
  S[5] := 'Y';
  S[6] := 'Z';
  Check(S = 'abcXYZ', 'sre-grow-filled');

  { Copy with a count far beyond the end }
  Check(Copy(S, 2, MaxInt) = 'bcXYZ', 'sre-copy-maxint');
  Check(Copy(S, 1, MaxInt) = S, 'sre-copy-maxint-full');

  { StringOfChar incl. zero count }
  T := StringOfChar(AnsiChar('q'), 5);
  Check(T = 'qqqqq', 'sre-stringofchar');
  T := StringOfChar(AnsiChar('q'), 0);
  Check(T = '', 'sre-stringofchar-zero');

  { StringReplace, pure ASCII }
  S := 'aXaXa';
  T := AnsiString(StringReplace(string(S), 'X', 'YY', [rfReplaceAll]));
  Check(T = 'aYYaYYa', 'sre-stringreplace-all');
  T := AnsiString(StringReplace(string(S), 'X', 'YY', []));
  Check(T = 'aYYaXa', 'sre-stringreplace-first');

  { CompareStr sign and SameText }
  Check(CompareStr('abc', 'abd') < 0, 'sre-comparestr-lt');
  Check(CompareStr('abd', 'abc') > 0, 'sre-comparestr-gt');
  Check(CompareStr('abc', 'abc') = 0, 'sre-comparestr-eq');
  Check(CompareStr('ab', 'abc') < 0, 'sre-comparestr-prefix');
  Check(SameText('AbC', 'aBc'), 'sre-sametext');
  Check(not SameText('AbC', 'aBd'), 'sre-sametext-diff');

  { Swap / Hi / Lo on the classic 16-bit semantics }
  Check(Swap(Word($1234)) = $3412, 'sre-swap-word');
  Check(Hi(Word($1234)) = $12, 'sre-hi-word');
  Check(Lo(Word($1234)) = $34, 'sre-lo-word');
  V := Integer(OpaqueI($12345678));
  Check(Hi(V) = $56, 'sre-hi-int-low-word');
  Check(Lo(V) = $78, 'sre-lo-int-low-word');

  { Odd on negatives and Int64 edges }
  Check(Odd(-3), 'sre-odd-neg3');
  Check(not Odd(-4), 'sre-odd-neg4');
  Check(Odd(OpaqueI(-1)), 'sre-odd-neg1-int64');
  Check(not Odd(OpaqueI(Low(Int64))), 'sre-odd-low-int64');
  Check(Odd(OpaqueI(High(Int64))), 'sre-odd-high-int64');

  { Sqr of Integer near the 32-bit edge under Q-: the result type is the
    operand type, so it wraps (dialect tripwire if a compiler widens) }
  V := Integer(OpaqueI(50000));
  R64 := Sqr(V);
  Check(R64 = Int64(Integer($9502F900)), 'sre-sqr-int-wraps');
  K := Sqr(V);
  Check(K = Integer($9502F900), 'sre-sqr-int-target-int');
  for I := 1 to Length(S) do
    Mix(Ord(S[I]));
end;

{ ---------------------------------------------------------------- }
{ 31. Parent-frame parameters, array-of-const forwarding, 64-bit    }
{ enum sets, Ord() arithmetic on comparisons, FreeAndNil.           }
{ ---------------------------------------------------------------- }

type
  TBigEnum = (
    be00, be01, be02, be03, be04, be05, be06, be07,
    be08, be09, be10, be11, be12, be13, be14, be15,
    be16, be17, be18, be19, be20, be21, be22, be23,
    be24, be25, be26, be27, be28, be29, be30, be31,
    be32, be33, be34, be35, be36, be37, be38, be39,
    be40, be41, be42, be43, be44, be45, be46, be47,
    be48, be49, be50, be51, be52, be53, be54, be55,
    be56, be57, be58, be59, be60, be61, be62, be63);
  TBigSet = set of TBigEnum;

function ParentParams(ByVal: Integer; var ByRef: Integer;
  const ByConst: Integer; out ByOut: Integer): Integer;

  function InnerMix(Salt: Integer): Integer;
  begin
    Inc(ByVal, Salt);                            { mutate parent's copy }
    ByRef := ByRef * 2 + Salt;                   { through the reference }
    Result := ByVal + ByRef + ByConst;
  end;

begin
  ByOut := InnerMix(3) + InnerMix(4);
  Result := ByVal;                               { after both mutations }
end;

function ForwardArgs(const A: array of const): AnsiString;
begin
  Result := DescribeArgs(A);                     { forwarded verbatim }
end;

procedure RunParentFrameForms;
var
  VRef, VOut, R, I, K: Integer;
  BS, BS2: TBigSet;
  E: TBigEnum;
  Obj: TBase;
  A64, B64F: Double;
begin
  { nested routine mutating every parameter kind of its parent }
  VRef := 10;
  R := ParentParams(100, VRef, 7, VOut);
  { call 1: ByVal 103, ByRef 23, sum 133; call 2: ByVal 107, ByRef 50,
    sum 164; out = 297, ByVal after = 107, VRef = 50 }
  Check(R = 107, 'pfp-nested-byval-mutation');
  Check(VRef = 50, 'pfp-nested-byref-mutation');
  Check(VOut = 297, 'pfp-nested-out-sum');

  { array of const forwarded through another open-const function }
  Check(ForwardArgs([5, False, Int64(6)]) = 'i5bFl6', 'pfp-aoc-forwarding');

  { 64-element enum set: 8-byte set codegen }
  BS := [be00, be31, be32, be63];
  Check((be00 in BS) and (be31 in BS) and (be32 in BS) and (be63 in BS),
    'pfp-bigset-members');
  Check(not (be01 in BS) and not (be62 in BS), 'pfp-bigset-nonmembers');
  BS2 := [be31..be33];
  BS := BS + BS2;
  K := 0;
  for E := Low(TBigEnum) to High(TBigEnum) do
    if E in BS then
      Inc(K);
  Check(K = 5, 'pfp-bigset-union-count');
  BS := BS - [be00..be32];
  Check(BS = [be33, be63], 'pfp-bigset-difference');

  { Ord() of comparisons as branch-free arithmetic }
  K := 0;
  for I := -5 to 5 do
    K := K + Ord(I > 0) - Ord(I < 0);
  Check(K = 0, 'pfp-ord-sign-balance');
  A64 := 2.5;
  B64F := 7.5;
  K := Ord(A64 < B64F) * 100 + Ord(A64 > B64F) * 10 + Ord(A64 = B64F);
  Check(K = 100, 'pfp-ord-float-compare');

  { FreeAndNil leaves nil behind, works on nil too }
  Obj := TBase.Create;
  FreeAndNil(Obj);
  Check(Obj = nil, 'pfp-freeandnil');
  FreeAndNil(Obj);
  Check(Obj = nil, 'pfp-freeandnil-idempotent');
  Check(not Assigned(Obj), 'pfp-assigned-nil');
end;

{ ---------------------------------------------------------------- }
{ 32. Class machinery: per-instantiation generic class vars, class  }
{ properties, class methods via instance and metaclass, class-of    }
{ hierarchy walks, IntToHex widths.                                 }
{ ---------------------------------------------------------------- }

type
  TGenCounter<T> = class
  public
    class var Bumps: Integer;
    class procedure Bump;
    class function Current: Integer;
  end;

  TStatBox = class
  private
    class var FStock: Integer;
    class function GetStock: Integer; static;
    class procedure SetStock(V: Integer); static;
  public
    class property Stock: Integer read GetStock write SetStock;
    class function Snap: Integer;
  end;

class procedure TGenCounter<T>.Bump;
begin
  Inc(Bumps);
end;

class function TGenCounter<T>.Current: Integer;
begin
  Result := Bumps;
end;

class function TStatBox.GetStock: Integer;
begin
  Result := FStock;
end;

class procedure TStatBox.SetStock(V: Integer);
begin
  FStock := V;
end;

class function TStatBox.Snap: Integer;
begin
  Result := FStock * 2;
end;

procedure RunClassMachineryForms;
var
  Inst: TStatBox;
  Cls: TBaseClass;
begin
  { generic class vars are one slot PER INSTANTIATION }
  TGenCounter<Integer>.Bumps := 0;
  TGenCounter<AnsiString>.Bumps := 0;
  TGenCounter<Integer>.Bump;
  TGenCounter<Integer>.Bump;
  TGenCounter<AnsiString>.Bump;
  Check(TGenCounter<Integer>.Current = 2, 'cls-genvar-int-instance');
  Check(TGenCounter<AnsiString>.Current = 1, 'cls-genvar-str-instance');

  { class property through getter/setter statics }
  TStatBox.Stock := 21;
  Check(TStatBox.Stock = 21, 'cls-class-property');
  Check(TStatBox.Snap = 42, 'cls-class-method');
  Inst := TStatBox.Create;
  try
    Check(Inst.Snap = 42, 'cls-class-method-via-instance');
    TStatBox.Stock := 10;
    Check(Inst.Snap = 20, 'cls-class-state-shared');
  finally
    Inst.Free;
  end;

  { metaclass hierarchy walk }
  Cls := TTop;
  Check(Cls.Kind = 30, 'cls-metaclass-virtual-classfunc');
  Cls := TBaseClass(Cls.ClassParent);
  Check(Cls = TMid, 'cls-classparent-walk');
  Check(Cls.Kind = 20, 'cls-classparent-kind');
  Check(TTop.InheritsFrom(TBase), 'cls-inheritsfrom-deep');
  Check(not TBase.InheritsFrom(TTop), 'cls-inheritsfrom-reverse');

  { IntToHex widths: padding, truncation-free, negative values }
  Check(IntToHex(255, 2) = 'FF', 'cls-inttohex-exact');
  Check(IntToHex(255, 6) = '0000FF', 'cls-inttohex-padded');
  Check(IntToHex(Integer(-1), 8) = 'FFFFFFFF', 'cls-inttohex-neg-int');
  Check(IntToHex(UInt64($ABC), 1) = 'ABC', 'cls-inttohex-min-width');
  Check(IntToStr(Low(Int64)) = '-9223372036854775808', 'cls-inttostr-low');
end;

{ ---------------------------------------------------------------- }
{ 33. Negative-zero folding, NaN boolean braids and related forms.  }
{ stored-vs-fresh branches, ord-mux inversion, Q+ widening point,   }
{ the 2^53 compare cliff, out/const aliasing, Copy clamp corners.   }
{ Pins from probe8.dpr (Delphi 12.2 Win64).                         }
{ ---------------------------------------------------------------- }

procedure OutConstAliasStr(out R: AnsiString; const Src: AnsiString);
begin
  R := Src + '!';
end;

{$Q+}
function QPlusWideningRaises(A, B: Integer; out V: Int64): Boolean;
begin
  Result := False;
  try
    V := A * B;
  except
    on EIntOverflow do
      Result := True;
  end;
end;
{$Q-}

procedure RunFloatBooleanForms;
var
  NanU: record
    case Boolean of
      True: (U: UInt64);
      False: (D: Double);
  end;
  NanV, MZ, PZ, A, B, M1, M2: Double;
  BStored: Boolean;
  P, Q, K: Integer;
  I64: Int64;
  D: Double;
  S, Src: AnsiString;

  function DB(V: Double): UInt64;
  begin
    Move(V, Result, 8);
  end;

begin
  NanU.U := UInt64($7FF8000000000001);
  NanV := NanU.D;
  NanU.U := UInt64($8000000000000000);
  MZ := NanU.D;
  PZ := 0.0;

  { FINDING #21: Delphi folds x + 0.0 -> x, so (-0)+(+0) keeps the sign
    bit; IEEE RN requires +0. The check states IEEE truth and is an
    expected failure on Delphi both O+/O-. }
  A := OpaqueD(MZ);
  Check(DB(A + 0.0) = 0, 'fb3-neg-zero-plus-zero');
  Check(DB(PZ - PZ) = 0, 'fb3-zero-minus-zero');
  Check(DB(OpaqueD(MZ) + OpaqueD(MZ)) = UInt64($8000000000000000),
    'fb3-negzero-plus-negzero');
  A := OpaqueD(PZ);
  Check(DB(-A) = UInt64($8000000000000000), 'fb3-negate-positive-zero');

  { hand-written selects keep the operand identity on signed zeros }
  A := PZ;
  B := MZ;
  if A < B then M1 := A else M1 := B;
  Check(DB(M1) = UInt64($8000000000000000), 'fb3-select-picks-b');
  if B <= A then M2 := B else M2 := A;
  Check(DB(M2) = UInt64($8000000000000000), 'fb3-select-le-picks-b');

  { Abs intrinsic clears the sign of -0, branch-abs must keep it }
  A := OpaqueD(MZ);
  Check(DB(Abs(A)) = 0, 'fb3-abs-negzero-intrinsic');
  A := OpaqueD(MZ);
  if A < 0 then
    A := -A;
  Check(DB(A) = UInt64($8000000000000000), 'fb3-abs-negzero-branch');

  { ord-mux: Ord(c) + Ord(not c) must be 1 even for NaN compares.
    Delphi O- yields 0 for the pair (third face of finding #13). }
  A := OpaqueD(NanV);
  B := 1.0;
  P := Ord(A < B) * 17 + Ord(not (A < B)) * 29;
  Check(P = 29, 'fb3-ord-mux-nan');
  Check(Ord(A < B) + Ord(not (A < B)) = 1, 'fb3-ord-complement-sum');
  Check(Ord(A > 0) - Ord(A < 0) = 0, 'fb3-ord-sign-nan');

  { boolean braids on unordered operands }
  Check(not ((A < B) xor (A >= B)), 'fb3-braid-xor');
  Check(not ((A < B) or (A >= B)), 'fb3-braid-or');
  Check(not ((A < B) and (A >= B)), 'fb3-braid-and');
  Check(not (not (A < B) and not (A >= B)) = False, 'fb3-braid-demorgan');

  { stored boolean must agree with a fresh branch on the same compare }
  BStored := A < B;
  P := 0;
  Q := 0;
  if BStored then
    Inc(P);
  if A < B then
    Inc(Q);
  Check(P = Q, 'fb3-stored-vs-fresh-branch');
  Check(Ord(BStored) + Ord(A < B) * 2 = 0, 'fb3-stored-fresh-mix');

  { Q+ checks the 32-bit product BEFORE widening (Delphi pin: raises) }
  Check(QPlusWideningRaises(Integer(OpaqueI(100000)),
    Integer(OpaqueI(50000)), I64), 'fb3-qplus-mul-before-widen');
  Check(not QPlusWideningRaises(Integer(OpaqueI(40000)),
    Integer(OpaqueI(50000)), I64), 'fb3-qplus-mul-fits');
  Check(I64 = 2000000000, 'fb3-qplus-mul-value');

  { the 2^53 cliff: Int64 converts to Double for the compare (Delphi pin) }
  I64 := OpaqueI(9007199254740993);
  D := OpaqueD(9007199254740992.0);
  Check(I64 = D, 'fb3-int64-double-eq-cliff');
  Check(not (I64 > D), 'fb3-int64-double-gt-cliff');

  { out parameter finalized before const-by-ref argument is read }
  Src := AnsiString('hello') + AnsiString(IntToStr(Integer(RtZero and 0)));
  S := Src;
  OutConstAliasStr(S, S);
  Check(S = '!', 'fb3-out-const-alias');
  { a temp made INSIDE the same call does not help: out is finalized
    before the other arguments are evaluated. Only a temp taken in a
    separate statement restores value semantics. }
  S := Src;
  Src := Copy(S, 1, MaxInt);
  OutConstAliasStr(S, Src);
  Check(S = 'hello0!', 'fb3-out-temp-copy');

  { Copy clamp corners (Delphi pins from probe8) }
  S := '0123456789';
  Check(Copy(S, 0, 3) = '012', 'fb3-copy-index0');
  Check(Copy(S, -2, 5) = '01234', 'fb3-copy-negative-index');
  Check(Copy(S, 3, -1) = '', 'fb3-copy-negative-count');
  Check(Copy(S, MaxInt, 1) = '', 'fb3-copy-maxint-index');
  for K := 1 to Length(S) do
    Mix(Ord(S[K]));
end;

{ ---------------------------------------------------------------- }
{ 34. Memory-manager and thin-boundary forms: canary-guarded        }
{ Move/FillChar at allocator-edge sizes, a GetMem/ReallocMem walk   }
{ across size boundaries with content preservation, one-char string }
{ growth across allocator blocks, one-element dyn-array growth,     }
{ object churn, plus probe9 pins (out-of-range in, big Currency,    }
{ same-length SetLength uniquification).                            }
{ ---------------------------------------------------------------- }

procedure RunMemoryBoundaryForms;
const
  EdgeSizes: array[0..11] of Integer = (0, 1, 7, 8, 9, 15, 16, 17, 31, 32, 63, 64);
var
  Canary: array[0..255] of Byte;    { [0..15] and [240..255] are guards }
  P: PByte;
  Blk: Pointer;
  BS: set of Byte;
  S1, S2: AnsiString;
  Arr: TIntArr2;
  C: Currency;
  R64: Int64;
  I, K, Sz, Prev: Integer;
  Obj: TBase;

  procedure ArmCanaries;
  var
    J: Integer;
  begin
    for J := 0 to 15 do
      Canary[J] := Byte($C0 + J);
    for J := 240 to 255 do
      Canary[J] := Byte($D0 + (J - 240));
  end;

  procedure CheckCanaries(const Name: AnsiString);
  var
    J: Integer;
  begin
    for J := 0 to 15 do
      Check(Canary[J] = Byte($C0 + J), Name);
    for J := 240 to 255 do
      Check(Canary[J] = Byte($D0 + (J - 240)), Name);
  end;

begin
  { Move/FillChar at allocator-edge sizes inside canary guards }
  for K := 0 to High(EdgeSizes) do
  begin
    Sz := EdgeSizes[K];
    ArmCanaries;
    FillChar(Canary[16], Sz, Byte($A5));
    CheckCanaries('mm-fillchar-canary');
    for I := 0 to Sz - 1 do
      Check(Canary[16 + I] = $A5, 'mm-fillchar-content');
    for I := 0 to 63 do
      Canary[16 + I] := Byte(I);
    Move(Canary[16], Canary[100], Sz);
    CheckCanaries('mm-move-canary');
    for I := 0 to Sz - 1 do
      Check(Canary[100 + I] = Byte(I), 'mm-move-content');
  end;

  { GetMem/ReallocMem walk across size boundaries, content preserved }
  Prev := 0;
  Blk := nil;
  for K := 0 to High(EdgeSizes) do
  begin
    Sz := EdgeSizes[K];
    if Sz = 0 then
      Continue;
    if Blk = nil then
      GetMem(Blk, Sz)
    else
      ReallocMem(Blk, Sz);
    P := PByte(Blk);
    for I := 0 to Prev - 1 do
      if I < Sz then
        Check(P[I] = Byte(I xor $5C), 'mm-realloc-preserved');
    for I := 0 to Sz - 1 do
      P[I] := Byte(I xor $5C);
    Prev := Sz;
  end;
  FreeMem(Blk);

  { one-char string growth across allocator blocks, then shrink by one }
  S1 := '';
  for I := 1 to 300 do
  begin
    S1 := S1 + AnsiChar(Ord('a') + (I mod 26));
    Check(Length(S1) = I, 'mm-string-grow-length');
    Check(S1[I] = AnsiChar(Ord('a') + (I mod 26)), 'mm-string-grow-tail');
    if (I and 63) = 0 then
      Check(S1[1] = AnsiChar(Ord('a') + 1), 'mm-string-grow-head');
  end;
  for I := 299 downto 1 do
  begin
    Delete(S1, Length(S1), 1);
    Check(Length(S1) = I, 'mm-string-shrink-length');
  end;
  Check(S1 = 'b', 'mm-string-shrink-final');

  { one-element dyn-array growth and full shrink }
  Arr := nil;
  for I := 0 to 64 do
  begin
    SetLength(Arr, I + 1);
    Arr[I] := I * 3;
    Check(Length(Arr) = I + 1, 'mm-dynarr-grow-len');
    Check(Arr[0] = 0, 'mm-dynarr-grow-head');
    Check(Arr[I] = I * 3, 'mm-dynarr-grow-tail');
  end;
  SetLength(Arr, 0);
  Check(Length(Arr) = 0, 'mm-dynarr-shrink-zero');
  Check(Pointer(Arr) = nil, 'mm-dynarr-nil-after-zero');

  { object churn: create/free waves, plus refcounted churn with balance }
  for I := 1 to 200 do
  begin
    Obj := TBase.Create;
    Obj.Tag := I;
    Check(Obj.Tag = I, 'mm-churn-field');
    Obj.Free;
  end;
  TValObj.Alive := 0;
  for I := 1 to 200 do
  begin
    GHold := TValObj.Create(I);
    Check(GHold.Val = I, 'mm-churn-intf-value');
    GHold := nil;
  end;
  Check(TValObj.Alive = 0, 'mm-churn-intf-balance');

  { probe9 pins: out-of-range in, big Currency, same-length SetLength }
  BS := [1, 5, 250];
  Check(not (Integer(OpaqueI(300)) in BS), 'mm-set-in-outrange-high');
  Check(not (Integer(OpaqueI(-5)) in BS), 'mm-set-in-outrange-neg');
  Check(not (Integer(OpaqueI(257)) in BS), 'mm-set-in-no-bit-alias');
  Check(Integer(OpaqueI(250)) in BS, 'mm-set-in-valid');
  C := 92233720368.5477;
  R64 := PInt64(@C)^;
  Check(R64 = 922337203685477, 'mm-currency-big-literal');
  C := C * 3;
  Check(PInt64(@C)^ = R64 * 3, 'mm-currency-big-mul-exact');
  S1 := AnsiString('abcdef') + AnsiString(IntToStr(Integer(RtZero and 0)));
  S2 := S1;
  SetLength(S2, Length(S2));
  S2[1] := 'Z';
  Check(S1[1] = 'a', 'mm-setlength-samelen-unique');
  Check(S2[1] = 'Z', 'mm-setlength-samelen-target');
  Mix(UInt64(UInt32(Length(S1))));
end;

{ ---------------------------------------------------------------- }
{ 35. Checked computed-index forms on a non-zero-based array.       }
{ zero-based padded field, case ranges with a huge negative base,   }
{ string relations at the 255/256 boundary, COW shrink on shared.   }
{ ---------------------------------------------------------------- }

type
  TPaddedRec = record
    Pad1: array[0..31] of Byte;
    A: array[3..9] of Integer;
    Pad2: array[0..31] of Byte;
  end;

{$R+}
function PaddedIndexRead(var R: TPaddedRec; Idx: Integer;
  out Caught: Boolean): Integer;
begin
  Result := 0;
  Caught := False;
  try
    Result := R.A[Idx];
  except
    on ERangeError do
      Caught := True;
  end;
end;
{$R-}

function CaseNegBase(V: Integer): Integer;
begin
  case V of
    -2000000000..-1999999998: Result := 1;
    -5..-3: Result := 2;
    0: Result := 3;
    1..2: Result := 4;
    100, 105, 110: Result := 5;
    1000000000..1000000002: Result := 6;
  else
    Result := 7;
  end;
end;

function CaseNegBaseOracle(V: Integer): Integer;
begin
  if (V >= -2000000000) and (V <= -1999999998) then Result := 1
  else if (V >= -5) and (V <= -3) then Result := 2
  else if V = 0 then Result := 3
  else if (V >= 1) and (V <= 2) then Result := 4
  else if (V = 100) or (V = 105) or (V = 110) then Result := 5
  else if (V >= 1000000000) and (V <= 1000000002) then Result := 6
  else Result := 7;
end;

procedure RunCheckedIndexForms;
const
  Probes: array[0..17] of Integer = (
    -2000000001, -2000000000, -1999999998, -1999999997, -6, -5, -3, -2,
    -1, 0, 1, 2, 3, 99, 100, 110, 1000000000, 1000000003);
var
  R: TPaddedRec;
  I, K, V: Integer;
  Caught: Boolean;
  SA, SB: AnsiString;
begin
  { R+ on a non-zero-based field surrounded by pads }
  FillChar(R, SizeOf(R), 0);
  for I := 3 to 9 do
    R.A[I] := I * 7;
  V := PaddedIndexRead(R, 3 + (Integer(OpaqueI(4)) mod 7), Caught);
  Check(not Caught, 'fbl-rplus-provable-clean');
  Check(V = 7 * 7, 'fbl-rplus-provable-value');
  V := PaddedIndexRead(R, Integer(OpaqueI(9)), Caught);
  Check(not Caught, 'fbl-rplus-edge-clean');
  Check(V = 63, 'fbl-rplus-edge-value');
  PaddedIndexRead(R, Integer(OpaqueI(10)), Caught);
  Check(Caught, 'fbl-rplus-above-raises');
  PaddedIndexRead(R, Integer(OpaqueI(2)), Caught);
  Check(Caught, 'fbl-rplus-below-raises');
  for I := 0 to 31 do
    Check((R.Pad1[I] = 0) and (R.Pad2[I] = 0), 'fbl-rplus-pads-intact');

  { negative-base case ranges vs the if-ladder }
  for I := 0 to High(Probes) do
    Check(CaseNegBase(Probes[I]) = CaseNegBaseOracle(Probes[I]),
      'fbl-case-negbase-probes');
  for I := 0 to 299 do
  begin
    V := Integer(Rnd);
    Check(CaseNegBase(V) = CaseNegBaseOracle(V), 'fbl-case-negbase-random');
  end;

  { string relations at the 255/256 boundary }
  for K := 254 to 257 do
  begin
    SA := StringOfChar(AnsiChar('m'), K);
    SB := SA;
    SB[K] := 'n';
    Check(SA < SB, 'fbl-str-boundary-lt');
    Check(not (SA = SB), 'fbl-str-boundary-ne');
    SB := SA + 'x';
    Check(SA < SB, 'fbl-str-boundary-prefix');
  end;

  { COW shrink while shared: the sibling keeps full content }
  SA := StringOfChar(AnsiChar('w'), 40) + AnsiString(IntToStr(Integer(RtZero and 0)));
  SB := SA;
  SetLength(SA, 5);
  Check(Length(SB) = 41, 'fbl-cow-shrink-sibling-len');
  Check(SB[41] = '0', 'fbl-cow-shrink-sibling-tail');
  Check(SA = 'wwwww', 'fbl-cow-shrink-target');
  Mix(UInt64(UInt32(Length(SB))));
end;

{ ---------------------------------------------------------------- }
{ 36. Finalization-order and lifetime forms: managed locals die in  }
{ reverse declaration order on both exits (probe10 pin), SetLength  }
{ shrink releases each dropped interface exactly once, Insert and   }
{ Delete keep managed elements sane around the gap, TList of        }
{ interfaces balances on Delete/Clear, explicit Finalize and        }
{ Initialize, threadvar managed strings.                            }
{ ---------------------------------------------------------------- }

type
  TTraceObj = class(TInterfacedObject)
  public
    FTag: AnsiChar;
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

  TIntfArr = array of IInterface;

constructor TTraceObj.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TTraceObj.Destroy;
begin
  FbTrail := FbTrail + FTag;
  inherited Destroy;
end;

procedure FinNormalExit;
var
  A, B, C: IInterface;
begin
  A := TTraceObj.Create('a');
  B := TTraceObj.Create('b');
  C := TTraceObj.Create('c');
  Check(Assigned(A) and Assigned(B) and Assigned(C), 'fin-locals-live');
end;

procedure FinExceptExit;
var
  A, B, C: IInterface;
begin
  A := TTraceObj.Create('x');
  B := TTraceObj.Create('y');
  C := TTraceObj.Create('z');
  raise ERangeError.Create('fin-boom');
end;

threadvar
  TvStr: AnsiString;

type
  TTvWorker = class(TThread)
  public
    SeenLen: Integer;
    procedure Execute; override;
  end;

procedure TTvWorker.Execute;
begin
  SeenLen := Length(TvStr);                     { fresh per thread: 0 }
  TvStr := StringOfChar(AnsiChar('t'), 64);
  SeenLen := SeenLen * 1000 + Length(TvStr);
end;

function ValOfIntf(const I: IInterface): Integer;
begin
  { the as-temp dies when THIS routine exits, not the caller }
  Result := (I as IValInt).Val;
end;

procedure RunFinalizationForms;
var
  Caught: Boolean;
  Arr: TIntfArr;
  SArr: TStrArr;
  L: TList<IInterface>;
  W: TTvWorker;
  I: Integer;
  Rec: TSRec;
begin
  { reverse declaration order on normal and exception exit (Delphi pin) }
  FbTrail := '';
  FinNormalExit;
  Check(FbTrail = 'cba', 'fin-normal-exit-reverse');
  FbTrail := '';
  Caught := False;
  try
    FinExceptExit;
  except
    on ERangeError do
      Caught := True;
  end;
  Check(Caught, 'fin-except-caught');
  Check(FbTrail = 'zyx', 'fin-except-exit-reverse');

  { SetLength shrink releases each dropped interface exactly once }
  TValObj.Alive := 0;
  SetLength(Arr, 8);
  for I := 0 to 7 do
    Arr[I] := TValObj.Create(I);
  Check(TValObj.Alive = 8, 'fin-intfarr-filled');
  SetLength(Arr, 3);
  Check(TValObj.Alive = 3, 'fin-intfarr-shrink-released');
  Check(ValOfIntf(Arr[0]) = 0, 'fin-intfarr-kept-head');
  SetLength(Arr, 0);
  Check(TValObj.Alive = 0, 'fin-intfarr-drained');

  { Insert/Delete on managed string arrays around the gap }
  SetLength(SArr, 3);
  SArr[0] := 'aa';
  SArr[1] := 'bb';
  SArr[2] := 'cc';
  Insert(AnsiString('mid'), SArr, 1);
  Check((Length(SArr) = 4) and (SArr[0] = 'aa') and (SArr[1] = 'mid') and
    (SArr[2] = 'bb') and (SArr[3] = 'cc'), 'fin-strarr-insert');
  Delete(SArr, 0, 2);
  Check((Length(SArr) = 2) and (SArr[0] = 'bb') and (SArr[1] = 'cc'),
    'fin-strarr-delete');

  { TList<IInterface> balances on Delete and Clear }
  TValObj.Alive := 0;
  L := TList<IInterface>.Create;
  try
    for I := 0 to 9 do
      L.Add(TValObj.Create(I));
    Check(TValObj.Alive = 10, 'fin-list-filled');
    L.Delete(5);
    Check(TValObj.Alive = 9, 'fin-list-delete-released');
    L.Clear;
    Check(TValObj.Alive = 0, 'fin-list-clear-drained');
  finally
    L.Free;
  end;

  { explicit Finalize clears managed fields only; Initialize re-arms }
  Rec.S := 'hello';
  Rec.N := 42;
  Finalize(Rec);
  Check(Pointer(Rec.S) = nil, 'fin-finalize-managed-nil');
  Check(Rec.N = 42, 'fin-finalize-plain-kept');
  Initialize(Rec);
  Check(Length(Rec.S) = 0, 'fin-initialize-empty');
  Rec.S := 'again';
  Check(Rec.S = 'again', 'fin-reinit-usable');

  { threadvar managed string: fresh per thread, main copy untouched }
  TvStr := 'main-owned';
  W := TTvWorker.Create;
  try
    W.FreeOnTerminate := False;
    W.WaitFor;
    Check(W.SeenLen = 64, 'fin-threadvar-fresh-in-thread');
  finally
    W.Free;
  end;
  Check(TvStr = 'main-owned', 'fin-threadvar-main-intact');
  Mix(UInt64(UInt32(Length(TvStr))));
end;

{ ---------------------------------------------------------------- }
{ 37. Structural lifetime pack: array-element vs object-field       }
{ object fields reverse on Delphi, forward on FPC) and the rest of  }
{ the same structural pack.                                         }
{ ---------------------------------------------------------------- }

type
  THolder3 = class
  public
    A, B, C: IInterface;
  end;

  TLeafRec = record
    Name: AnsiString;
  end;
  TTreeRec = record
    Leaves: array of TLeafRec;
  end;

  PManagedRec = ^TSRec;

  TBlock1K = array[0..255] of Integer;

procedure TakeOutManaged(out S: AnsiString; var G: AnsiString);
begin
  G := S;
  S := 'set';
end;

procedure MutateBlockByVal(B: TBlock1K);
begin
  B[0] := 999;
  B[127] := -1;
  B[255] := 888;
  Mix(UInt64(UInt32(B[0])));
end;

procedure ModifyOpenStr(var Arr: array of AnsiString);
begin
  Arr[0] := 'CHANGED';
  Arr[High(Arr)] := 'LAST';
end;

procedure OpenBoundsOf(const A: array of AnsiString; out L, H, C: Integer);
begin
  L := Low(A);
  H := High(A);
  C := Length(A);
end;

procedure RunStructuralLifetimeForms;
var
  Arr: TIntfArr;
  H3: THolder3;
  TreeA, TreeB: TTreeRec;
  P: PManagedRec;
  Blk: TBlock1K;
  SArr, SArrB: TStrArr;
  StatStr: array[5..8] of AnsiString;
  X, G, Msg: AnsiString;
  I, L, Hi, Cnt: Integer;
begin
  { array elements finalize FORWARD on every compiler (probe11) }
  FbTrail := '';
  SetLength(Arr, 4);
  for I := 0 to 3 do
    Arr[I] := TTraceObj.Create(AnsiChar(Ord('0') + I));
  Arr := nil;
  Check(FbTrail = '0123', 'op4-array-element-order-forward');

  { object fields finalize REVERSE on Delphi (pin); FPC goes forward }
  FbTrail := '';
  H3 := THolder3.Create;
  H3.A := TTraceObj.Create('A');
  H3.B := TTraceObj.Create('B');
  H3.C := TTraceObj.Create('C');
  H3.Free;
  Check(FbTrail = 'CBA', 'op4-field-order-reverse');

  { shrink-then-grow: regrown slots must be nil }
  TValObj.Alive := 0;
  SetLength(Arr, 4);
  for I := 0 to 3 do
    Arr[I] := TValObj.Create(I);
  SetLength(Arr, 2);
  Check(TValObj.Alive = 2, 'op4-shrink-released');
  SetLength(Arr, 6);
  Check(TValObj.Alive = 2, 'op4-regrow-no-resurrect');
  Check((Arr[2] = nil) and (Arr[5] = nil), 'op4-regrow-slots-nil');
  SetLength(Arr, 0);
  Check(TValObj.Alive = 0, 'op4-regrow-drained');

  { per-element nil release }
  TValObj.Alive := 0;
  SetLength(Arr, 3);
  for I := 0 to 2 do
    Arr[I] := TValObj.Create(I);
  Arr[1] := nil;
  Check(TValObj.Alive = 2, 'op4-elem-nil-releases');
  Arr[0] := nil;
  Check(TValObj.Alive = 1, 'op4-elem-nil-second');
  Arr := nil;
  Check(TValObj.Alive = 0, 'op4-elem-nil-final');

  { record containing dyn array of records with strings: alias vs COW }
  SetLength(TreeA.Leaves, 2);
  TreeA.Leaves[0].Name := 'oak';
  TreeA.Leaves[1].Name := 'elm';
  TreeB := TreeA;
  TreeB.Leaves[0].Name := 'pine';
  Check(TreeA.Leaves[0].Name = 'pine', 'op4-record-dynarr-alias');
  SetLength(TreeB.Leaves, Length(TreeB.Leaves));
  TreeB.Leaves[1].Name := 'birch';
  Check(TreeA.Leaves[1].Name = 'elm', 'op4-samelen-unshares');
  Check(TreeB.Leaves[0].Name = 'pine', 'op4-unshared-keeps');

  { raw memory + Initialize/Finalize cycle }
  GetMem(P, SizeOf(TSRec));
  Initialize(P^);
  P^.S := 'hello';
  P^.N := 5;
  Check((P^.S = 'hello') and (P^.N = 5), 'op4-raw-init-use');
  Finalize(P^);
  Initialize(P^);
  P^.S := 'world';
  Check(P^.S = 'world', 'op4-raw-reinit-use');
  Finalize(P^);
  FreeMem(P);

  { out-managed cleared at entry: callee reads empty }
  X := AnsiString('initial') + AnsiString(IntToStr(Integer(RtZero and 0)));
  G := 'unset';
  TakeOutManaged(X, G);
  Check(G = '', 'op4-out-cleared-at-entry');
  Check(X = 'set', 'op4-out-assigned');

  { var open array of strings: writes visible in the static array }
  StatStr[5] := 'first';
  StatStr[6] := 'mid';
  StatStr[7] := 'mid2';
  StatStr[8] := 'third';
  ModifyOpenStr(StatStr);
  Check(StatStr[5] = 'CHANGED', 'op4-var-openarray-head');
  Check(StatStr[8] = 'LAST', 'op4-var-openarray-tail');
  Check(StatStr[6] = 'mid', 'op4-var-openarray-middle');

  { open array is always rebased to 0..Count-1 }
  OpenBoundsOf(StatStr, L, Hi, Cnt);
  Check((L = 0) and (Hi = 3) and (Cnt = 4), 'op4-openarray-rebased');

  { 1KB static array by value: callee mutates only its copy }
  for I := 0 to 255 do
    Blk[I] := I;
  MutateBlockByVal(Blk);
  Check((Blk[0] = 0) and (Blk[127] = 127) and (Blk[255] = 255),
    'op4-byval-1kb-intact');

  { exception message survives the except block via string copy }
  Msg := '';
  try
    raise ERangeError.Create('payload');
  except
    on E: ERangeError do
      Msg := AnsiString(E.Message);
  end;
  Check(Msg = 'payload', 'op4-exc-message-survives');

  { shared string-array COW via SetLength }
  SetLength(SArr, 3);
  SArr[0] := 'one';
  SArr[1] := 'two';
  SArr[2] := 'three';
  SArrB := SArr;
  SetLength(SArrB, 4);
  SArrB[0] := 'ONE';
  SArrB[3] := 'four';
  Check((SArr[0] = 'one') and (Length(SArr) = 3), 'op4-shared-cow-source');
  Check((SArrB[0] = 'ONE') and (Length(SArrB) = 4), 'op4-shared-cow-target');
  SArrB := nil;
  Mix(UInt64(UInt32(Length(SArr))));
end;

{$ifdef HAS_ANON}
type
  TIntRef = reference to function(X: Integer): Integer;
  TGetRef = reference to function: Integer;
  TProcRef = reference to procedure;

function MakeAdder(Base: Integer): TIntRef;
begin
  Result := function(X: Integer): Integer
    begin
      Result := X + Base;
    end;
end;

function MakeCounter(Start: Integer): TGetRef;
var
  Current: Integer;
begin
  Current := Start;
  Result := function: Integer
    begin
      Inc(Current);
      Result := Current;
    end;
end;

procedure RunAnonymousForms;
var
  Add5, AddNeg, Fib: TIntRef;
  C1, C2, Grab: TGetRef;
  Grabbers: array[0..3] of TGetRef;
  Bump: TProcRef;
  Shared, I, K: Integer;
begin
  Add5 := MakeAdder(5);
  AddNeg := MakeAdder(-100);
  Check(Add5(10) = 15, 'anon-closure-basic');
  Check(AddNeg(10) = -90, 'anon-closure-independent');
  Check(Add5(Add5(0)) = 10, 'anon-closure-compose');

  { escaping closures keep private captured state }
  C1 := MakeCounter(100);
  C2 := MakeCounter(200);
  Check(C1() = 101, 'anon-counter-first');
  Check(C1() = 102, 'anon-counter-second');
  Check(C2() = 201, 'anon-counter-independent');
  Check(C1() = 103, 'anon-counter-continues');

  { two closures over one shared local }
  Shared := 0;
  Bump := procedure
    begin
      Inc(Shared, 3);
    end;
  Grab := function: Integer
    begin
      Result := Shared;
    end;
  Bump();
  Bump();
  Check(Shared = 6, 'anon-shared-writer');
  Bump();
  Check(Grab() = 9, 'anon-shared-reader');

  { one captured slot: every grabber sees the final value }
  for I := 0 to 3 do
  begin
    K := I * 11;
    Grabbers[I] := function: Integer
      begin
        Result := K;
      end;
  end;
  for I := 0 to 3 do
    Check(Grabbers[I]() = 33, 'anon-captured-slot-shared');

  { self-referencing closure through its own captured variable }
  Fib := function(X: Integer): Integer
    begin
      if X < 2 then
        Result := X
      else
        Result := Fib(X - 1) + Fib(X - 2);
    end;
  Check(Fib(10) = 55, 'anon-recursive-closure');
  Mix(UInt64(UInt32(Shared)));
end;

{$ifdef HAS_INLINEVAR}
type
  TAnonNewManaged = record
    Text: UnicodeString;
    Values: TArray<Integer>;
  end;
  PAnonNewManaged = ^TAnonNewManaged;
  PPAnonNewManaged = ^PAnonNewManaged;
  TAnonNewCarrier = record
    Value: PAnonNewManaged;
  end;
  TAnonNewFactory = reference to function: PAnonNewManaged;

procedure InvokeAnonNew(const Callback: TProcRef);
begin
  Callback();
end;

procedure RunAnonymousPointerNewForms;
var
  Callback: TProcRef;
  Factory: TAnonNewFactory;
  Value: PAnonNewManaged;
begin
  { Assignment context + inline local + managed pointed record: exact bug
    class. New must select its statement form and initialize managed fields. }
  Callback := procedure
    begin
      var P: PAnonNewManaged;
      New(P);
      Check((P^.Text = '') and (P^.Values = nil),
        'anon-new-assigned-inline-managed-init');
      P^.Text := 'assigned';
      P^.Values := [3, 5, 8];
      Check((P^.Text = 'assigned') and (P^.Values[2] = 8),
        'anon-new-assigned-inline-managed-use');
      Dispose(P);
    end;
  Callback();

  { Call-argument context used to leak a second parser flag into the body. }
  InvokeAnonNew(
    procedure
    begin
      var P: PInteger;
      New(P);
      P^ := Integer(OpaqueI(42));
      Check(P^ = 42, 'anon-new-argument-inline-scalar');
      Dispose(P);
    end);

  { The New operand need not be a bare local: indexed and record-field
    lvalues exercise the same statement lowering with different AST shapes. }
  Callback := procedure
    begin
      var Slots: array[0..1] of PAnonNewManaged;
      var Carrier: TAnonNewCarrier;
      var I: Integer;
      for I := Low(Slots) to High(Slots) do
      begin
        New(Slots[I]);
        Slots[I]^.Text := UnicodeString(IntToStr(I + 10));
      end;
      Check((Slots[0]^.Text = '10') and (Slots[1]^.Text = '11'),
        'anon-new-indexed-lvalue');
      for I := Low(Slots) to High(Slots) do
        Dispose(Slots[I]);
      New(Carrier.Value);
      Carrier.Value^.Values := [13, 21];
      Check(Carrier.Value^.Values[1] = 21, 'anon-new-record-field-lvalue');
      Dispose(Carrier.Value);
    end;
  Callback();

  { Pointer-to-pointer and a nested closure over the allocated pointer cross
    parser nesting, capture lowering and managed heap lifetime. }
  Callback := procedure
    begin
      var Holder: PPAnonNewManaged;
      var Reader: TProcRef;
      New(Holder);
      Holder^ := nil;
      New(Holder^);
      Holder^^.Text := 'nested';
      Reader := procedure
        begin
          Check(Holder^^.Text = 'nested', 'anon-new-nested-capture-read');
        end;
      Reader();
      Reader := nil;
      Dispose(Holder^);
      Dispose(Holder);
    end;
  Callback();

  { Anonymous function result: allocation happens in the nested body, while
    ownership of the pointer crosses back to the enclosing routine. }
  Factory := function: PAnonNewManaged
    begin
      var P: PAnonNewManaged;
      New(P);
      P^.Text := 'factory';
      P^.Values := [34, 55];
      Result := P;
    end;
  Value := Factory();
  Check((Value^.Text = 'factory') and (Value^.Values[0] = 34),
    'anon-new-function-result');
  Mix(UInt64(UInt32(Value^.Values[1])));
  Dispose(Value);
end;
{$endif}

{ A nested anonymous procedure passed from CreateAnonymousThread to
  TThread.Queue captures the method Self. The worker is joined before the main
  thread drains the queue, so the exact production form has a deterministic
  runtime oracle instead of being compile-only. }
type
  TQueueSelfProbe = class
  private
    FValue: Integer;
  public
    procedure Run;
  end;

procedure TQueueSelfProbe.Run;
var
  Worker: TThread;
begin
  FValue := 0;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Queue(nil,
        procedure
        begin
          Inc(FValue, 7);
        end);
    end);
  Worker.FreeOnTerminate := False;
  try
    Worker.Start;
    Worker.WaitFor;
    CheckSynchronize(0);
  finally
    Worker.Free;
  end;
  Check(FValue = 7, 'anon-thread-queue-nested-closure-self');
  Mix(UInt64(UInt32(FValue)));
end;

procedure RunQueueClosureForms;
var
  Probe: TQueueSelfProbe;
begin
  Probe := TQueueSelfProbe.Create;
  try
    Probe.Run;
  finally
    Probe.Free;
  end;
end;

type
  TClosureWorker = class(TThread)
  public
    Seed: Integer;
    Fn: TGetRef;
    constructor Create(ASeed: Integer);
    procedure Execute; override;
  end;

constructor TClosureWorker.Create(ASeed: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Seed := ASeed;
end;

procedure TClosureWorker.Execute;
var
  Local: Integer;
begin
  Local := Seed * 3 + 1;
  Fn := function: Integer
    begin
      Result := Local xor Seed;
    end;
end;

procedure RunComboModernForms;
var
  W: TClosureWorker;
  GL: TList<Integer>;
  Acc: TGetRef;
  PushTwice: TProcRef;
  I, Total: Integer;
begin
  { closure built inside a worker thread, invoked from the main thread
    after the join: the capture record crosses the thread boundary }
  W := TClosureWorker.Create(7);
  try
    W.Start;
    W.WaitFor;
    Check(Assigned(W.Fn), 'combo-thread-closure-assigned');
    Check(W.Fn() = ((7 * 3 + 1) xor 7), 'combo-thread-closure-value');
  finally
    W.Fn := nil;
    W.Free;
  end;

  { closure capturing a generic list and mutating it }
  GL := TList<Integer>.Create;
  try
    PushTwice := procedure
      begin
        GL.Add(GL.Count * 10);
        GL.Add(GL.Count * 10);
      end;
    Acc := function: Integer
      var
        V, Sum: Integer;
      begin
        Sum := 0;
        for V in GL do
          Inc(Sum, V);
        Result := Sum;
      end;
    for I := 1 to 3 do
      PushTwice();
    { adds: 0,10 / 20,30 / 40,50 -> sum 150, count 6 }
    Check(GL.Count = 6, 'combo-closure-list-count');
    Total := Acc();
    Check(Total = 150, 'combo-closure-list-sum');
    GL.Delete(0);
    Check(Acc() = 150, 'combo-closure-list-after-delete');
  finally
    PushTwice := nil;
    Acc := nil;
    GL.Free;
  end;
end;
{$endif}

{$ifdef HAS_INLINEVAR}
{ ---------------------------------------------------------------- }
{ 16. Inline-var forms (modern): inference, scoping, shadowing.     }
{ ---------------------------------------------------------------- }

type
  TInlineInitVariantType = class(TInvokeableVariantType)
  protected
{$ifndef FPC}
    function FixupIdent(const AText: string): string; override;
{$endif}
  public
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: Boolean); override;
    function GetProperty(var Dest: TVarData; const V: TVarData;
{$ifdef FPC}
      const Name: AnsiString): Boolean; override;
{$else}
      const Name: string): Boolean; override;
{$endif}
  end;

procedure TInlineInitVariantType.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TInlineInitVariantType.Copy(var Dest: TVarData;
  const Source: TVarData; const Indirect: Boolean);
begin
  if Indirect and VarDataIsByRef(Source) then
    VarDataCopyNoInd(Dest, Source)
  else
    Dest.VType := Source.VType;
end;

{$ifndef FPC}
function TInlineInitVariantType.FixupIdent(const AText: string): string;
begin
  Result := AText;
end;
{$endif}

function TInlineInitVariantType.GetProperty(var Dest: TVarData;
  const V: TVarData;
{$ifdef FPC}
  const Name: AnsiString): Boolean;
{$else}
  const Name: string): Boolean;
{$endif}
begin
  if SameText(string(Name), 'Author') then
  begin
    Result := True;
    Variant(Dest) := UnicodeString('Alice');
  end
  else if SameText(string(Name), 'type') then
  begin
    Result := True;
    Variant(Dest) := UnicodeString('spot');
  end
  else if SameText(string(Name), 'end') then
  begin
    Result := True;
    Variant(Dest) := 17;
  end
  else if SameText(string(Name), 'and') then
  begin
    Result := True;
    Variant(Dest) := True;
  end
  else
    Result := False;
end;

procedure RunInlineVarForms;
var
  Outer, Total, K: Integer;
  Arr: array[0..4] of Integer;
  DynamicValue: Variant;
  VariantType: TInlineInitVariantType;
begin
  var A := 41;
  Inc(A);
  Check(A = 42, 'ivar-basic');
  Check(SizeOf(A) = 4, 'ivar-integer-literal-inference');
  var B: Int64 := High(Int64);
  Check(B = High(Int64), 'ivar-typed-value');
  Check(SizeOf(B) = 8, 'ivar-typed-size');
  var S := IntToStr(12345);
  Check(Length(S) = 5, 'ivar-inferred-from-call');

  VariantType := TInlineInitVariantType.Create;
  try
    DynamicValue := Null;
    TVarData(DynamicValue).VType := VariantType.VarType;
    var Author: string := DynamicValue.Author;
    Check(Author = 'Alice', 'ivar-typed-variant-member');
    var InferredAuthor := DynamicValue.Author;
    Check(string(InferredAuthor) = 'Alice', 'ivar-inferred-variant-member');
{$ifdef HAS_VARIANT_RESERVED_MEMBER}
    Check(string(DynamicValue.type) = 'spot',
      'variant-reserved-member-type');
    Check(Integer(DynamicValue.end) = 17,
      'variant-reserved-member-end');
    Check(Boolean(DynamicValue.and),
      'variant-reserved-member-and');
{$endif}
  finally
    VarClear(DynamicValue);
    VariantType.Free;
  end;

  Outer := 7;
  if OpaqueI(1) = 1 then
  begin
    var Inner := 100;
    Inc(Inner);
    Check(Inner = 101, 'ivar-block-scoped');
  end;
  Check(Outer = 7, 'ivar-outer-intact');

  Total := 0;
  for var J := 1 to 5 do
    Inc(Total, J);
  Check(Total = 15, 'ivar-for-loop');

  for K := 0 to 4 do
    Arr[K] := K * K;
  Total := 0;
  for var E in Arr do
    Inc(Total, E);
  Check(Total = 30, 'ivar-for-in');

  var W := A * 2 + Integer(OpaqueI(0));
  Check(W = 84, 'ivar-expression-inference');
{$ifdef HAS_ANON}
  { closures over a block-scoped inline var in a loop body capture ONE
    slot, not one per iteration (Delphi pin via probe7: 33,33,33,33) }
  begin
    var Grabs: array[0..3] of TGetRef;
    for K := 0 to 3 do
    begin
      var Slot := K * 11;
      Grabs[K] := function: Integer
        begin
          Result := Slot;
        end;
    end;
    for K := 0 to 3 do
      Check(Grabs[K]() = 33, 'ivar-anon-loop-capture-single-slot');
  end;
{$endif}
  Mix(UInt64(UInt32(W)));
end;
{$endif}

{ ---------------------------------------------------------------- }


{ ================================================================ }
{ Rounds zoo-/zoo2-/zoo3-/zoo4-/zoo5-/zoo6- + f2f-/fty-/mem- (the   }
{ former zoo file, fully absorbed here). Gates below: Delphi-only   }
{ features, FPC probes via -dTRY_* flags.                           }
{$ifdef FPC}
  {$ifdef TRY_MREC}
    {$define HAS_MREC}
  {$endif}
  {$ifdef TRY_FUNCOBJ}
    {$modeswitch anonymousfunctions}
    {$modeswitch functionreferences}
    {$define HAS_FUNCOBJ}
  {$endif}
  {$ifdef TRY_HOPERS}
    {$define HAS_HOPERS}
  {$endif}
  {$ifdef TRY_MULTIDEF}
    {$define HAS_MULTIDEF}
  {$endif}
  {$ifdef TRY_RAREX}
    {$define HAS_RAREX}
  {$endif}
{$else}
  {$define HAS_MREC}
  {$define HAS_FUNCOBJ}
  {$define HAS_D12}
  {$define HAS_HOPERS}
  {$define HAS_MULTIDEF}
  {$define HAS_RAREX}
{$endif}

const
  FNVOfs = UInt64($CBF29CE484222325);
  FNVPrm = UInt64($100000001B3);

{ ---------------------------------------------------------------- }
{ 1. Slice() / open-array forms. Slice is completely unexercised in }
{ mega_forms: partial views of static arrays, runtime slice counts, }
{ open-array constructors with computed elements, var open arrays   }
{ writing through to static AND dynamic callers.                    }

type
  TIntDyn = array of Integer;

function SumOpen(const A: array of Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := Low(A) to High(A) do
    Result := Result + A[K];
end;

function LenOpen(const A: array of Integer): Integer;
begin
  Result := High(A) - Low(A) + 1;
end;

function PassThrough(const A: array of Integer): Integer;
begin
  Result := SumOpen(A);            { open array re-passed whole }
end;

procedure BumpOpen(var A: array of Integer; Delta: Integer);
var
  K: Integer;
begin
  for K := Low(A) to High(A) do
    A[K] := A[K] + Delta;
end;

function SumFirstRec(const A: array of Integer; N: Integer): Integer;
begin
  if N <= 0 then
    Result := 0
  else
    Result := SumFirstRec(A, N - 1) + A[N - 1];
end;

procedure RunSliceZooForms;
var
  St: array[0..9] of Integer;
  Dyn: TIntDyn;
  K: Integer;
begin
  for K := 0 to 9 do
    St[K] := K * K + 1;            { 1 2 5 10 17 26 37 50 65 82 }

  { Slice passes exactly the N leading elements }
  Check(SumOpen(Slice(St, 4)) = St[0] + St[1] + St[2] + St[3],
    'zoo-slice-first4');
  Check(LenOpen(Slice(St, 7)) = 7, 'zoo-slice-len');
  Check(SumOpen(Slice(St, 10)) = SumOpen(St), 'zoo-slice-full');

  { slice count is a runtime-opaque value; oracle = index recursion }
  K := Integer(OpaqueI(6));
  Check(SumOpen(Slice(St, K)) = SumFirstRec(St, 6), 'zoo-slice-opaque-n');
  Check(SumFirstRec(St, 6) = 61, 'zoo-slice-rec-pin');

  { open-array constructor with computed elements }
  Check(SumOpen([Integer(OpaqueI(5)), 6 * 7, Ord(St[0] = 1)]) = 48,
    'zoo-openarr-ctor');

  { var open array writes land in the caller's static array }
  BumpOpen(St, 100);
  Check(St[9] = 182, 'zoo-openarr-var-bump');
  Check(PassThrough(St) = 1295, 'zoo-openarr-passthrough');

  { dynamic array through the same open-array formals }
  SetLength(Dyn, 5);
  for K := 0 to 4 do
    Dyn[K] := K + 1;
  Check(SumOpen(Dyn) = 15, 'zoo-openarr-dyn');
  BumpOpen(Dyn, 10);
  Check(Dyn[4] = 15, 'zoo-openarr-dyn-var');

  Mix(UInt64(UInt32(SumOpen(St))));
  Mix(UInt64(UInt32(SumOpen(Dyn))));
end;

{ ---------------------------------------------------------------- }
{ 2. array-of-const normalization + forwarding. DescribeArgs in     }
{ mega_forms dodges bare literals (Delphi passes them as             }
{ vtUnicodeString/vtWideChar, FPC as vtAnsiString/vtChar). Here the }
{ walker NORMALIZES every char-ish and string-ish slot to the same  }
{ folded stream, so one digest must come out on both dialects, and  }
{ the same array is forwarded through a second array-of-const hop.  }
{ Oracle: the expected fold is authored by hand, slot by slot.      }

type
  TZooTag = class
  public
    Tag: Integer;
    constructor Create(ATag: Integer);
  end;

constructor TZooTag.Create(ATag: Integer);
begin
  inherited Create;
  Tag := ATag;
end;

function FStep(H, V: UInt64): UInt64;
begin
  Result := (H xor V) * FNVPrm;
end;

function NormFold(const A: array of const): UInt64;
var
  K, I: Integer;
  S: AnsiString;
begin
  Result := FNVOfs;
  for K := 0 to High(A) do
    case A[K].VType of
      vtInteger:
        Result := FStep(Result, UInt64(Int64(A[K].VInteger)));
      vtBoolean:
        Result := FStep(Result, UInt64(Ord(A[K].VBoolean)));
      vtInt64:
        Result := FStep(Result, UInt64(A[K].VInt64^));
      vtCurrency:
        Result := FStep(Result, UInt64(PInt64(A[K].VCurrency)^));
      vtExtended:
        Result := FStep(Result, DoubleBits(A[K].VExtended^));
      vtChar:
        begin
          Result := FStep(Result, $CC);
          Result := FStep(Result, UInt64(Ord(A[K].VChar)));
        end;
      vtWideChar:
        begin
          Result := FStep(Result, $CC);
          Result := FStep(Result, UInt64(Ord(A[K].VWideChar)));
        end;
      vtString:
        begin
          S := AnsiString(A[K].VString^);
          Result := FStep(Result, $55);
          Result := FStep(Result, UInt64(Length(S)));
          for I := 1 to Length(S) do
            Result := FStep(Result, UInt64(Ord(S[I])));
        end;
      vtAnsiString:
        begin
          S := AnsiString(A[K].VAnsiString);
          Result := FStep(Result, $55);
          Result := FStep(Result, UInt64(Length(S)));
          for I := 1 to Length(S) do
            Result := FStep(Result, UInt64(Ord(S[I])));
        end;
      vtUnicodeString:
        begin
          S := AnsiString(UnicodeString(A[K].VUnicodeString));
          Result := FStep(Result, $55);
          Result := FStep(Result, UInt64(Length(S)));
          for I := 1 to Length(S) do
            Result := FStep(Result, UInt64(Ord(S[I])));
        end;
      vtWideString:
        begin
          S := AnsiString(WideString(A[K].VWideString));
          Result := FStep(Result, $55);
          Result := FStep(Result, UInt64(Length(S)));
          for I := 1 to Length(S) do
            Result := FStep(Result, UInt64(Ord(S[I])));
        end;
      vtPointer:
        if A[K].VPointer = nil then
          Result := FStep(Result, $EE)
        else
          Result := FStep(Result, $EF);
      vtObject:
        if TObject(A[K].VObject) is TZooTag then
        begin
          Result := FStep(Result, $0B);
          Result := FStep(Result, UInt64(Int64(TZooTag(A[K].VObject).Tag)));
        end else
          Result := FStep(Result, $99);
      vtClass:
        begin
          S := AnsiString(A[K].VClass.ClassName);
          Result := FStep(Result, $0C);
          Result := FStep(Result, UInt64(Length(S)));
          for I := 1 to Length(S) do
            Result := FStep(Result, UInt64(Ord(S[I])));
        end;
    else
      Result := FStep(Result, $99);
    end;
end;

function FwdFold(const A: array of const): UInt64;
begin
  Result := NormFold(A);           { whole array-of-const forwarded }
end;

procedure RunVarRecZooForms;
var
  H1, H2, E: UInt64;
  Cur: Currency;
  SS: ShortString;
  Obj: TZooTag;
begin
  Cur := 1.5;
  H1 := NormFold([12, True, 'Z', AnsiString('zoo'), Int64(9000000000),
    Cur, 2.5, nil, False]);

  { hand-authored expected fold, slot by slot }
  E := FNVOfs;
  E := FStep(E, 12);
  E := FStep(E, 1);
  E := FStep(E, $CC);
  E := FStep(E, 90);                                   { 'Z' }
  E := FStep(E, $55);
  E := FStep(E, 3);
  E := FStep(E, 122);
  E := FStep(E, 111);
  E := FStep(E, 111);                                  { 'zoo' }
  E := FStep(E, UInt64(9000000000));
  E := FStep(E, 15000);                                { 1.5 as Currency }
  E := FStep(E, DoubleBits(2.5));
  E := FStep(E, $EE);
  E := FStep(E, 0);
  Check(H1 = E, 'zoo-varrec-norm');
  Check(FwdFold([12, True, 'Z', AnsiString('zoo'), Int64(9000000000),
    Cur, 2.5, nil, False]) = H1, 'zoo-varrec-forward');

  { the same payload through different slot representations must fold
    identically: bare literal vs AnsiString vs ShortString, and bare
    char literal vs AnsiChar cast }
  SS := 'abc';
  Check(NormFold(['abc']) = NormFold([AnsiString('abc')]),
    'zoo-varrec-literal-ansi');
  Check(NormFold([SS]) = NormFold([AnsiString('abc')]),
    'zoo-varrec-short-ansi');
  Check(NormFold(['Z']) = NormFold([AnsiChar('Z')]),
    'zoo-varrec-char-ansi');

  Check(NormFold([]) = FNVOfs, 'zoo-varrec-empty');

  { object and class-reference slots }
  Obj := TZooTag.Create(777);
  H2 := NormFold([Obj, TZooTag]);
  Obj.Free;
  E := FNVOfs;
  E := FStep(E, $0B);
  E := FStep(E, 777);
  E := FStep(E, $0C);
  E := FStep(E, 7);
  E := FStep(E, 84);                                   { 'TZooTag' }
  E := FStep(E, 90);
  E := FStep(E, 111);
  E := FStep(E, 111);
  E := FStep(E, 84);
  E := FStep(E, 97);
  E := FStep(E, 103);
  Check(H2 = E, 'zoo-varrec-obj-class');

  Mix(H1);
  Mix(H2);
end;

{ ---------------------------------------------------------------- }
{ 3. Generics beyond TBox: class-type constraint driving a VIRTUAL  }
{ constructor, nested specialization, managed payloads copied by    }
{ value, Default() on a specialized record.                         }

type
  TZBox<T> = record
    Val: T;
    Tag: Integer;
  end;

  TZPair<A, B> = record
    First: A;
    Second: B;
  end;

  TZooCounted = class
  public
    Num: Integer;                      { instance field BEFORE class var:
                                         a class-var block swallows every
                                         field declared after it }
    class var Made: Integer;
    constructor Create; virtual;
  end;

  TZooCountedKid = class(TZooCounted)
  public
    constructor Create; override;
  end;

  TZMaker<T: TZooCounted> = class
  public
    class function Bake: T;
  end;

  TZBoxI = TZBox<Integer>;
  TZBoxNested = TZBox<TZBoxI>;
  TZBoxStr = TZBox<AnsiString>;
  TZPairCB = TZPair<Currency, Byte>;

constructor TZooCounted.Create;
begin
  inherited Create;
  Inc(Made);
  Num := 11;
end;

constructor TZooCountedKid.Create;
begin
  inherited Create;
  Num := 55;
end;

class function TZMaker<T>.Bake: T;
begin
  Result := T.Create;              { virtual constructor via constraint }
end;

procedure RunGenericZooForms;
var
  Base: TZooCounted;
  Kid: TZooCountedKid;
  NB, NB2: TZBoxNested;
  SB, SB2: TZBoxStr;
  P, Q: TZPairCB;
  DP: TZPairCB;
  CT: Currency;
begin
  TZooCounted.Made := 0;
  Base := TZMaker<TZooCounted>.Bake;
  Kid := TZMaker<TZooCountedKid>.Bake;
  Check(Base.Num = 11, 'zoo-gen-bake-base');
  Check(Kid.Num = 55, 'zoo-gen-bake-virtual-ctor');
  Check(TZooCounted.Made = 2, 'zoo-gen-bake-count');
  Base.Free;
  Kid.Free;

  { nested specialization is a plain value type: deep copy on assign }
  NB.Val.Val := 11;
  NB.Val.Tag := 22;
  NB.Tag := 33;
  NB2 := NB;
  NB2.Val.Val := 99;
  Check(NB.Val.Val = 11, 'zoo-gen-nested-copy');
  Check((NB2.Val.Tag = 22) and (NB2.Tag = 33), 'zoo-gen-nested-fields');

  { managed payload: the string field must COW apart after copy }
  SB.Val := AnsiString('alpha');
  SB.Tag := 1;
  SB2 := SB;
  SB2.Val := SB2.Val + 'bet';
  Check(SB.Val = 'alpha', 'zoo-gen-managed-cow');
  Check(SB2.Val = 'alphabet', 'zoo-gen-managed-grown');

  { Currency payload survives record copy with 4-digit exactness }
  P.First := 0.0025;
  P.Second := 200;
  Q := P;
  Q.First := Q.First + 0.0001;
  CT := P.First;
  Check(CT = 0.0025, 'zoo-gen-curr-copy-intact');
  CT := Q.First;
  Check(CT = 0.0026, 'zoo-gen-curr-microstep');

  DP := Default(TZPairCB);
  CT := DP.First;
  Check((CT = 0) and (DP.Second = 0), 'zoo-gen-default');

  Mix(UInt64(UInt32(NB.Val.Val + NB2.Val.Val)));
  Mix(UInt64(Length(SB2.Val)));
end;

{ ---------------------------------------------------------------- }
{ 4. Interface GUID querying: Supports across interfaces of one     }
{ object, COM identity through IInterface, failed as-cast raising,  }
{ refcount driven purely by queries (object never Freed by hand).   }

type
  IZooFeed = interface
    ['{5B1A9C02-77D4-4E1B-9A63-2A0C51E3B901}']
    function Feed: Integer;
  end;

  IZooPet = interface
    ['{0C4E1F83-2B5A-4D77-8E90-6F1B2C3D4E5F}']
    function Pet: Integer;
  end;

  IZooWild = interface
    ['{7D2C3B14-9E80-4A56-B1C2-D3E4F5A6B7C8}']
    function Growl: Integer;
  end;

  TZooLlama = class(TInterfacedObject, IZooFeed, IZooPet)
  public
    Bites: Integer;                    { instance field before class var }
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
    function Feed: Integer;
    function Pet: Integer;
  end;

constructor TZooLlama.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TZooLlama.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TZooLlama.Feed: Integer;
begin
  Inc(Bites);
  Result := Bites;
end;

function TZooLlama.Pet: Integer;
begin
  Result := 100 + Bites;
end;

procedure RunIntfZooForms;
var
  F: IZooFeed;
  P: IZooPet;
  W: IZooWild;
  U1, U2: IInterface;
  Obj: TZooLlama;
  Raised: Integer;
begin
  TZooLlama.Alive := 0;
  F := TZooLlama.Create;
  Check(TZooLlama.Alive = 1, 'zoo-intf-alive-one');
  Check(F.Feed = 1, 'zoo-intf-feed-1');
  Check(F.Feed = 2, 'zoo-intf-feed-2');

  { cross-query via Supports shares the same instance state }
  Check(Supports(F, IZooPet, P), 'zoo-intf-supports-cross');
  Check(P.Pet = 102, 'zoo-intf-cross-state');

  { COM identity: IInterface from both views is the same pointer }
  U1 := F as IInterface;
  U2 := P as IInterface;
  Check(U1 = U2, 'zoo-intf-identity');

  { unimplemented interface: Supports says no and nils the out param }
  W := nil;
  Check(not Supports(F, IZooWild, W), 'zoo-intf-supports-missing');
  Check(W = nil, 'zoo-intf-supports-missing-nil');

  { as-cast to the unimplemented interface must raise }
  Raised := 0;
  try
    W := F as IZooWild;
    if W <> nil then
      Inc(Raised, 100);
  except
    Inc(Raised);
  end;
  Check(Raised = 1, 'zoo-intf-as-missing-raises');

  U1 := nil;
  U2 := nil;
  P := nil;
  W := nil;
  F := nil;
  Check(TZooLlama.Alive = 0, 'zoo-intf-refcount-zero');

  { querying an interface OUT of a plain object reference: the only
    ref is the query result; releasing it destroys the object }
  Obj := TZooLlama.Create;
  Check(Supports(Obj, IZooFeed, F), 'zoo-intf-object-supports');
  Check(F.Feed = 1, 'zoo-intf-object-feed');
  F := nil;
  Check(TZooLlama.Alive = 0, 'zoo-intf-object-released');

  Mix(UInt64(UInt32(TZooLlama.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 5. Enums with holes under $Z, subrange types, sets over a         }
{ subrange base. Succ/Pred and for-in are deliberately NOT applied  }
{ to the holey enum (FPC rejects them there); casts into holes are  }
{ legal ordinal math.                                               }

{$Z1}
type
  TGapE = (geOne = 1, geSeven = 7, geMid = 63, geTop = 200);
{$Z4}
type
  TGap4 = (g4A = 1, g4B = 300);
{$Z1}
type
  TNegSub = -100..100;
  THundo = 100..200;

procedure RunEnumHoleForms;
var
  V: TGapE;
  R: Integer;
begin
  Check(SizeOf(TGapE) = 1, 'zoo-enum-size1');
  Check(SizeOf(TGap4) = 4, 'zoo-enum-size4');
  Check(Ord(geTop) = 200, 'zoo-enum-ord');
  Check(geOne < geTop, 'zoo-enum-compare');
  Check(Ord(TGapE(100)) = 100, 'zoo-enum-hole-cast');

  V := TGapE(Integer(OpaqueI(63)));
  case V of
    geOne: R := 0;
    geMid: R := 1;
    geTop: R := 2;
  else
    R := 9;
  end;
  Check(R = 1, 'zoo-enum-case-hit');

  V := TGapE(Integer(OpaqueI(100)));         { lands in a hole }
  case V of
    geOne: R := 0;
    geSeven: R := 3;
    geMid: R := 1;
    geTop: R := 2;
  else
    R := 9;
  end;
  Check(R = 9, 'zoo-enum-case-hole');

  Mix(UInt64(UInt32(Ord(V))));
end;

procedure RunSubrangeForms;
var
  NA: array[TNegSub] of SmallInt;
  SH: set of THundo;
  ModelH: array[100..200] of Boolean;
  K, N: Integer;
  Sum: Integer;
  SV: TNegSub;
begin
  Check(SizeOf(TNegSub) = 1, 'zoo-subr-size-neg');
  Check(SizeOf(THundo) = 1, 'zoo-subr-size-mid');
  Check(SizeOf(NA) = 402, 'zoo-subr-arr-size');
  Check((Low(TNegSub) = -100) and (High(TNegSub) = 100), 'zoo-subr-bounds');

  for K := -100 to 100 do
    NA[K] := SmallInt(K * 3);
  Check(NA[Integer(OpaqueI(-100))] = -300, 'zoo-subr-neg-index');
  Sum := 0;
  for K := -100 to 100 do
    Sum := Sum + NA[K];
  Check(Sum = 0, 'zoo-subr-sum-zero');

  SV := TNegSub(Integer(OpaqueI(-1)));
  Check(Succ(SV) = 0, 'zoo-subr-succ');
  Check(Pred(SV) = -2, 'zoo-subr-pred');

  { set over a 100..200 subrange base vs a boolean-array model }
  SH := [];
  FillChar(ModelH, SizeOf(ModelH), 0);
  for K := 1 to 16 do
  begin
    N := 100 + Integer(Rnd mod 101);
    Include(SH, N);
    ModelH[N] := True;
  end;
  for K := 1 to 8 do
  begin
    N := 100 + Integer(Rnd mod 101);
    Exclude(SH, N);
    ModelH[N] := False;
  end;
  for K := 100 to 200 do
    Check((K in SH) = ModelH[K], 'zoo-subr-set-model');

  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 6. with-statement corners: with on a FUNCTION RESULT (expression  }
{ evaluated exactly once), field mutation through with, a field     }
{ shadowing a same-named local, with through a pointer deref, and   }
{ the two-clause form "with R, R.Inner".                            }

type
  TWInner = record
    A, B: Integer;
  end;
  TWRec = record
    X: Integer;
    Inner: TWInner;
    Arr: array[0..3] of Integer;
  end;

var
  WEvalCount: Integer = 0;

function MakeW(Seed: Integer): TWRec;
var
  K: Integer;
begin
  Inc(WEvalCount);
  Result.X := Seed * 2;
  Result.Inner.A := Seed + 1;
  Result.Inner.B := Seed * Seed;
  for K := 0 to 3 do
    Result.Arr[K] := Seed + K * 10;
end;

procedure RunWithZooForms;
var
  WR: TWRec;
  PW: ^TWRec;
  A, R: Integer;
begin
  WEvalCount := 0;
  with MakeW(5) do
    R := X * 1000000 + Inner.A * 1000 + Arr[2];
  Check(R = 10006025, 'zoo-with-func-fields');
  Check(WEvalCount = 1, 'zoo-with-func-single-eval');

  WR := MakeW(3);
  with WR.Inner do
    A := A + 40;                       { field A: 4 -> 44 }
  Check(WR.Inner.A = 44, 'zoo-with-mutate-through');

  A := -1;                             { local A }
  with WR.Inner do
    A := 77;                           { field wins over the local }
  Check(WR.Inner.A = 77, 'zoo-with-field-shadows-local');
  Check(A = -1, 'zoo-with-local-untouched');

  PW := @WR;
  with PW^ do
    X := X + 5;                        { 6 -> 11 }
  Check(WR.X = 11, 'zoo-with-ptr-deref');

  with WR, Inner do
    R := X + A;                        { 11 + 77 }
  Check(R = 88, 'zoo-with-nested-mixed');

  Mix(UInt64(UInt32(R)));
end;

{ ---------------------------------------------------------------- }
{ 7. The flagship freestyle combo straight from the brief: a        }
{ variant record overlaying Currency / Int64 / set of 0..63, read   }
{ inside a with, driven by a goto loop gated on set membership.     }
{ Oracles: explicit shr bit tests and scaled-integer Currency math. }

type
  TStoned = record
    Tag: Integer;
    case Byte of
      0: (Cur: Currency);
      1: (Bits: Int64);
      2: (Pack: set of 0..63);
  end;

procedure RunStonedForms;
label
  Chew, SkipTry;
const
  Step: Currency = 0.0001;             { typed: stays fixed-point Int64 math }
var
  SR: TStoned;
  SC: Currency;
  K, Steps, N: Integer;
  ModelSum, GotSum: Integer;
  StartBits: Int64;
begin
  { Currency literal lands as an exactly scaled Int64 }
  SC := 4097.0313;
  SR.Cur := SC;
  Check(SR.Bits = 40970313, 'zoo-stoned-cur-literal-scale');

  { goto loop gated by membership in the overlaid set }
  SR.Bits := Int64($0F00FF00F0F0AA55);
  ModelSum := 0;
  for K := 0 to 63 do
    if (SR.Bits shr K) and 1 = 1 then
      ModelSum := ModelSum + K;
  with SR do
  begin
    Tag := 0;
    K := 0;
Chew:
    if K in Pack then
      Tag := Tag + K;
    Inc(K);
    if K < 64 then
      goto Chew;
    GotSum := Tag;
  end;
  Check(GotSum = ModelSum, 'zoo-stoned-goto-gate-sum');

  { Currency microsteps via a TYPED Currency const move the overlaid
    Int64 by exactly 1 each, even at a magnitude where Double has no
    unit precision left (bits ~2^60) }
  StartBits := SR.Bits;
  N := 0;
  for K := 0 to 63 do
    if (StartBits shr K) and 1 = 1 then
      Inc(N);
  for K := 1 to N do
    SR.Cur := SR.Cur + Step;
  Check(SR.Bits - StartBits = N, 'zoo-stoned-cur-microstep');

  { deliberate seam probe: a BARE real literal drags the addition
    through the native float type. Delphi Win64 (Extended = Double,
    52-bit mantissa) lands 43 units off at exactly these bits; a
    compiler computing through 80-bit x87 or scaling the literal to
    Currency would give 1. Pinned to the Delphi value per corpus
    convention (op2 style: Delphi is the compatibility target). }
  SR.Bits := Int64($0F00FF00F0F0AA55);
  StartBits := SR.Bits;
  SR.Cur := SR.Cur + 0.0001;
  Check(SR.Bits - StartBits = 43, 'zoo-stoned-cur-litfloat');

  { goto jumping clean over a try..finally that never runs }
  Steps := 0;
  if OpaqueI(1) = 1 then
    goto SkipTry;
  try
    Inc(Steps, 100);
  finally
    Inc(Steps, 1000);
  end;
SkipTry:
  Inc(Steps);
  Check(Steps = 1, 'zoo-stoned-goto-over-try');

  Mix(UInt64(UInt32(GotSum)));
  Mix(UInt64(SR.Bits));
end;

{ ---------------------------------------------------------------- }
{ 8. Nested routines three levels deep: the innermost recurses      }
{ while writing locals of BOTH enclosing frames through the static  }
{ link, and the middle level recurses too. Oracle: the closed case  }
{ is small enough to trace by hand. Plus a nested binary-divide     }
{ summation over the outer routine's open-array parameter.          }

procedure RunNestedLinkForms;
var
  Depth: Integer;
  Trail: Int64;
  Sum: Integer;

  procedure L2(N: Integer);

    procedure L3(M: Integer);
    begin
      Trail := Trail * 10 + M;         { L1 frame }
      Sum := Sum + N * M;              { L2 param + L1 frame }
      if M > 1 then
        L3(M - 1);                     { depth-3 self-recursion }
    end;

  begin
    Inc(Depth);
    L3(N);
    if N > 1 then
      L2(N - 1);
  end;

  function OuterSum(const A: array of Integer): Integer;

    function Half(Lo, Hi: Integer): Integer;
    begin
      if Lo > Hi then
        Result := 0
      else if Lo = Hi then
        Result := A[Lo]                { outer's open array via static link }
      else
        Result := Half(Lo, (Lo + Hi) div 2) +
          Half((Lo + Hi) div 2 + 1, Hi);
    end;

  begin
    Result := Half(Low(A), High(A));
  end;

var
  Probe: array[0..7] of Integer;
  K: Integer;
begin
  Depth := 0;
  Trail := 0;
  Sum := 0;
  L2(3);
  { L2(3): L3 3,2,1 -> trail 321, sum 18; L2(2): 2,1 -> 32121, +6;
    L2(1): 1 -> 321211, +1 }
  Check(Trail = 321211, 'zoo-nest-trail');
  Check(Sum = 25, 'zoo-nest-sum');
  Check(Depth = 3, 'zoo-nest-depth');

  Probe[0] := 3; Probe[1] := 1; Probe[2] := 4; Probe[3] := 1;
  Probe[4] := 5; Probe[5] := 9; Probe[6] := 2; Probe[7] := 6;
  K := OuterSum(Probe);
  Check(K = SumOpen(Probe), 'zoo-nest-openarr-divide');
  Check(K = 31, 'zoo-nest-openarr-pin');

  Mix(UInt64(Trail));
  Mix(UInt64(UInt32(Sum + K)));
end;

{ ---------------------------------------------------------------- }
{ 9. Dynamic-array reference semantics: assignment shares, Copy     }
{ detaches (one level deep only), SetLength always re-uniquifies    }
{ even at the same length, a by-value parameter aliases until the   }
{ callee grows it, Copy clamps past the end.                        }

type
  TRagged = array of TIntDyn;
  TStrDyn = array of AnsiString;

procedure MutVal(D: TIntDyn);
begin
  D[0] := 111;                         { shared: hits the caller }
  SetLength(D, 100);                   { detach }
  D[1] := 222;                         { local only }
end;

procedure RunDynAliasForms;
var
  A, B, C: TIntDyn;
  RA, RB: TRagged;
  SA, SB: TStrDyn;
  K: Integer;
begin
  SetLength(A, 6);
  for K := 0 to 5 do
    A[K] := K * 3 + 1;                 { 1 4 7 10 13 16 }

  B := A;
  B[2] := 999;
  Check(A[2] = 999, 'zoo-dyn-share-write');

  C := Copy(A);
  C[0] := -5;
  Check(A[0] = 1, 'zoo-dyn-copy-detach');

  SetLength(B, 6);                     { same length: still must unshare }
  B[3] := -7;
  Check(A[3] = 10, 'zoo-dyn-setlength-unshares');
  Check(B[2] = 999, 'zoo-dyn-setlength-preserves');

  MutVal(A);
  Check(A[0] = 111, 'zoo-dyn-valparam-alias');
  Check(A[1] = 4, 'zoo-dyn-valparam-detach');
  Check(Length(A) = 6, 'zoo-dyn-valparam-len');

  C := Copy(A, 4, 100);                { clamps to the 2 real elements }
  Check(Length(C) = 2, 'zoo-dyn-copy-clamp');
  Check((C[0] = 13) and (C[1] = 16), 'zoo-dyn-copy-clamp-content');

  { Copy of a ragged array is one level deep: inner rows stay shared }
  SetLength(RA, 2);
  SetLength(RA[0], 2);
  RA[0][0] := 5;
  RB := Copy(RA);
  RB[0][0] := 42;
  Check(RA[0][0] = 42, 'zoo-dyn-copy-shallow');

  { managed elements: Copy shares the strings, COW splits them }
  SetLength(SA, 2);
  SA[0] := AnsiString('aa');
  SB := Copy(SA);
  SB[0] := SB[0] + 'x';
  Check(SA[0] = 'aa', 'zoo-dyn-copy-str-cow');

  Mix(UInt64(UInt32(A[0] + B[3] + C[1])));
end;

{ ---------------------------------------------------------------- }
{ 10. Metaclasses: virtual constructors dispatched through class    }
{ references, class-virtual functions, Self-as-metaclass in a       }
{ class method, is/as through the base, ClassParent chain.          }

type
  TBeast = class
  public
    Kind: Integer;
    constructor Create; virtual;
    function Voice: Integer; virtual;
    class function Family: Integer; virtual;
    class function Spawn: TBeast;
  end;
  TWolf = class(TBeast)
  public
    constructor Create; override;
    function Voice: Integer; override;
    class function Family: Integer; override;
  end;
  TPup = class(TWolf)
  public
    function Voice: Integer; override;
  end;
  CBeast = class of TBeast;

constructor TBeast.Create;
begin
  inherited Create;
  Kind := 1;
end;

function TBeast.Voice: Integer;
begin
  Result := Kind * 10;
end;

class function TBeast.Family: Integer;
begin
  Result := 1;
end;

class function TBeast.Spawn: TBeast;
begin
  Result := Create;                    { Self is the metaclass here }
end;

constructor TWolf.Create;
begin
  inherited Create;
  Kind := Kind + 10;
end;

function TWolf.Voice: Integer;
begin
  Result := Kind * 100;
end;

class function TWolf.Family: Integer;
begin
  Result := 2;
end;

function TPup.Voice: Integer;
begin
  Result := Kind * 1000 + 7;
end;

procedure RunMetaZooForms;
const
  Metas: array[0..2] of CBeast = (TBeast, TWolf, TPup);
var
  B, BB: TBeast;
  W: TWolf;
  K, VoiceSum, FamSum: Integer;
begin
  VoiceSum := 0;
  FamSum := 0;
  for K := 0 to 2 do
  begin
    B := Metas[K].Create;              { virtual ctor via metaclass }
    VoiceSum := VoiceSum + B.Voice;
    FamSum := FamSum + Metas[K].Family;
    B.Free;
  end;
  Check(VoiceSum = 10 + 1100 + 11007, 'zoo-meta-virtual-ctor-voice');
  Check(FamSum = 1 + 2 + 2, 'zoo-meta-class-virtual');

  Check(Metas[2].ClassParent = TWolf, 'zoo-meta-parent');
  Check(TPup.InheritsFrom(TBeast), 'zoo-meta-inherits');
  Check(AnsiString(Metas[1].ClassName) = 'TWolf', 'zoo-meta-classname');

  BB := Metas[2].Create;
  Check(BB is TWolf, 'zoo-meta-is-mid');
  Check(not (Metas[0].InheritsFrom(TWolf)), 'zoo-meta-not-inherits');
  W := BB as TWolf;
  Check(W.Voice = 11007, 'zoo-meta-as-virtual');
  BB.Free;

  B := TPup.Spawn;                     { Self-metaclass construction }
  Check(B.Voice = 11007, 'zoo-meta-self-spawn');
  B.Free;

  Mix(UInt64(UInt32(VoiceSum + FamSum)));
end;

{ ---------------------------------------------------------------- }
{ ROUND 2 (zoo2-): scoped enums, implicit/explicit conversion       }
{ chains, interface-constraint generics, deep copy of managed       }
{ record arrays, const-record ABI aliasing, exception handler       }
{ order, masked rotations, routine-local writable typed consts,     }
{ New/Dispose linked lists, AnsiChar case ranges.                   }
{ ---------------------------------------------------------------- }

{ 11. Scoped enums: qualification, Succ on a contiguous scoped      }
{ enum, sets of scoped enums iterated with for-in, case ranges.     }

{$SCOPEDENUMS ON}
type
  TZDir = (North, East, South, West);
{$SCOPEDENUMS OFF}

procedure RunScopedEnumForms;
var
  DirSet: set of TZDir;
  DV: TZDir;
  T: Int64;
  R: Integer;
begin
  Check(Ord(TZDir.South) = 2, 'zoo2-scoped-ord');
  Check(Succ(TZDir.North) = TZDir.East, 'zoo2-scoped-succ');
  Check(TZDir(Integer(OpaqueI(3))) = TZDir.West, 'zoo2-scoped-cast');

  DirSet := [TZDir.North, TZDir.West];
  Check((TZDir.North in DirSet) and not (TZDir.East in DirSet),
    'zoo2-scoped-set-members');
  T := 0;
  for DV in DirSet do
    T := T * 10 + (Ord(DV) + 1);         { must walk in ordinal order }
  Check(T = 14, 'zoo2-scoped-trail');

  DV := TZDir(Integer(OpaqueI(1)));      { East }
  case DV of
    TZDir.North..TZDir.East: R := 1;
    TZDir.South: R := 2;
  else
    R := 3;
  end;
  Check(R = 1, 'zoo2-scoped-case-range');

  Mix(UInt64(T));
end;

{ ---------------------------------------------------------------- }
{ 12. Implicit/Explicit conversion chains on an advanced record:    }
{ conversions fire in assignment, actual-parameter, Result and      }
{ mixed-operand positions. Millimeter store keeps every step exact. }

type
  TMeters = record
    Mm: Int64;
    class operator Implicit(V: Integer): TMeters;
    class operator Implicit(const M: TMeters): Double;
    class operator Explicit(const M: TMeters): Integer;
    class operator Add(const A, B: TMeters): TMeters;
    class operator LessThan(const A, B: TMeters): Boolean;
  end;

class operator TMeters.Implicit(V: Integer): TMeters;
begin
  Result.Mm := Int64(V) * 1000;
end;

class operator TMeters.Implicit(const M: TMeters): Double;
begin
  Result := M.Mm / 1000.0;               { exact for whole meters }
end;

class operator TMeters.Explicit(const M: TMeters): Integer;
begin
  Result := Integer(M.Mm div 1000);
end;

class operator TMeters.Add(const A, B: TMeters): TMeters;
begin
  Result.Mm := A.Mm + B.Mm;
end;

class operator TMeters.LessThan(const A, B: TMeters): Boolean;
begin
  Result := A.Mm < B.Mm;
end;

function TakeM(const M: TMeters): Int64;
begin
  Result := M.Mm;
end;

function GiveM(V: Integer): TMeters;
begin
  Result := V;                           { implicit in Result position }
end;

procedure RunConvChainForms;
var
  M, M2: TMeters;
  DD: Double;
begin
  M := 7;
  Check(M.Mm = 7000, 'zoo2-conv-implicit-int');
  DD := M;
  Check(DoubleBits(DD) = DoubleBits(7.0), 'zoo2-conv-to-double');
  M2 := M + 3;                           { 3 converts, then Add }
  Check(M2.Mm = 10000, 'zoo2-conv-add-mixed');
  Check(Integer(M2) = 10, 'zoo2-conv-explicit-trunc');
  Check(TakeM(4) = 4000, 'zoo2-conv-param-pos');
  Check(GiveM(6).Mm = 6000, 'zoo2-conv-result-pos');
  Check(M < M2, 'zoo2-conv-lt');

  Mix(UInt64(M.Mm + M2.Mm));
end;

{ ---------------------------------------------------------------- }
{ 13. Interface-constraint generic: the class function calls a      }
{ method THROUGH the constrained type param, refcount stays sane.   }

type
  TFeeder<T: IZooFeed> = class
  public
    class function FeedTwice(const X: T): Integer;
  end;

  TGenericSiblingInference = class
  public
    class function ToInt<T>(const Value: T): Integer; static;
    class function Twice<T>(const Value: T): Integer; static;
  end;

class function TFeeder<T>.FeedTwice(const X: T): Integer;
begin
  Result := X.Feed;
  Result := Result * 100 + X.Feed;
end;

class function TGenericSiblingInference.ToInt<T>(const Value: T): Integer;
begin
  Result := 0;
  Move(Value, Result, SizeOf(Value));
end;

class function TGenericSiblingInference.Twice<T>(const Value: T): Integer;
begin
  Result := ToInt(Value) * 2;
end;

procedure RunGenIntfForms;
var
  LF: IZooFeed;
begin
  TZooLlama.Alive := 0;
  LF := TZooLlama.Create;
  Check(TFeeder<IZooFeed>.FeedTwice(LF) = 102, 'zoo2-genintf-feedtwice');
  Check(TGenericSiblingInference.Twice<Byte>(21) = 42,
    'zoo2-generic-sibling-inference');
  LF := nil;
  Check(TZooLlama.Alive = 0, 'zoo2-genintf-alive');

  Mix(UInt64(UInt32(TZooLlama.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 14. Deep copy of a STATIC array of records with managed fields:   }
{ assignment copies elements, string fields COW apart, dyn-array    }
{ fields stay SHARED until SetLength splits them.                   }

type
  TCell = record
    S: AnsiString;
    D: TIntDyn;
    Tag: Integer;
  end;

procedure RunDeepCopyForms;
var
  A, B: array[0..2] of TCell;
  CC: TCell;
  K: Integer;
begin
  for K := 0 to 2 do
  begin
    A[K].S := AnsiString('cell') + AnsiChar(Ord('0') + K);
    SetLength(A[K].D, 2);
    A[K].D[0] := K * 10;
    A[K].D[1] := K * 10 + 1;
    A[K].Tag := K;
  end;

  B := A;                                { element-wise managed copy }
  B[1].S := B[1].S + 'x';
  Check(A[1].S = 'cell1', 'zoo2-deepcopy-str-cow');
  B[0].D[0] := 777;
  Check(A[0].D[0] = 777, 'zoo2-deepcopy-dyn-shared');
  SetLength(B[2].D, 2);                  { same length still splits }
  B[2].D[1] := -1;
  Check(A[2].D[1] = 21, 'zoo2-deepcopy-setlength-detach');
  B[1].Tag := 42;
  Check(A[1].Tag = 1, 'zoo2-deepcopy-plain-field');

  CC := A[1];                            { single record copy }
  CC.D[1] := 555;
  Check(A[1].D[1] = 555, 'zoo2-deepcopy-single-share');

  Mix(UInt64(UInt32(A[0].D[0] + A[1].D[1] + Length(B[1].S))));
end;

{ ---------------------------------------------------------------- }
{ 15. const record parameter aliasing: Win64 passes a 32-byte const }
{ record by REFERENCE, so a mutation of the global between two      }
{ reads is visible inside the callee. Deliberate seam probe pinned  }
{ to the re-read value 7012: dcc64 O- re-reads (passes), dcc64 O+   }
{ caches R.B in a register across the opaque call (7007, FAILS —    }
{ expected, documents the level split). A by-value convention also  }
{ gives 7007. The var-param twin is guaranteed alias-visible: the   }
{ compiler must not cache through var, so that one is a core pin.   }

type
  TBigRec = record
    A, B, C, D: Int64;
  end;

var
  GRec: TBigRec;

procedure PokeG;
begin
  GRec.B := GRec.B + 5;
end;

function TwoReadsRec(const R: TBigRec): Int64;
begin
  Result := R.B;
  PokeG;
  Result := Result * 1000 + R.B;
end;

function TwoReadsVarRec(var R: TBigRec): Int64;
begin
  Result := R.B;
  PokeG;
  Result := Result * 1000 + R.B;
end;

procedure RunConstRecForms;
begin
  GRec.A := 1;
  GRec.B := 7;
  GRec.C := 3;
  GRec.D := 4;
  Check(TwoReadsRec(GRec) = 7012, 'zoo2-constrec-alias');

  GRec.B := 7;
  Check(TwoReadsVarRec(GRec) = 7012, 'zoo2-varparam-rec-alias');

  Mix(UInt64(GRec.B));
end;

{ ---------------------------------------------------------------- }
{ 16. Exception machinery: base handler catches derived, handler    }
{ ORDER is textual, a finally between raise and the matching        }
{ handler runs while the exception is in flight, except-else takes  }
{ what no "on" matched. The trail pins the exact sequence.          }

type
  EZooBase = class(Exception);
  EZooCub = class(EZooBase);

procedure RunExcOrderForms;
var
  Trail: Int64;
begin
  Trail := 0;

  try
    raise EZooCub.Create('c1');
  except
    on E: EZooBase do
    begin
      Trail := Trail * 10 + 1;
      Check(E.ClassType = EZooCub, 'zoo2-exc-classtype');
    end;
  end;

  try
    raise EZooBase.Create('b1');
  except
    on EZooCub do
      Trail := Trail * 10 + 8;           { must NOT match }
    on EZooBase do
      Trail := Trail * 10 + 2;
  end;

  try
    try
      try
        raise EZooCub.Create('c2');
      except
        on EZooBase do
        begin
          Trail := Trail * 10 + 3;
          raise;                         { same object onwards }
        end;
      end;
    finally
      Trail := Trail * 10 + 5;           { runs with exception in flight }
    end;
  except
    on EZooCub do
      Trail := Trail * 10 + 4;
  end;

  try
    raise EZooBase.Create('b2');
  except
    on EZooCub do
      Trail := Trail * 10 + 9;
  else
    Trail := Trail * 10 + 6;             { except-else fallback }
  end;

  Check(Trail = 123546, 'zoo2-exc-trail');
  Mix(UInt64(Trail));
end;

{ ---------------------------------------------------------------- }
{ 17. Rotations composed from masked shifts vs a 1-bit-step twin.   }
{ Shift counts stay in 0..63 / 0..31 by construction (masks), so    }
{ every operation is defined; counts above the width exercise the   }
{ mask path.                                                        }

function RotL64(X: UInt64; K: Integer): UInt64;
begin
  K := K and 63;
  if K = 0 then
    Result := X
  else
    Result := (X shl K) or (X shr (64 - K));
end;

function RotL64Slow(X: UInt64; K: Integer): UInt64;
var
  I: Integer;
begin
  Result := X;
  for I := 1 to K and 63 do
    Result := (Result shl 1) or (Result shr 63);
end;

function RotL32(X: UInt32; K: Integer): UInt32;
begin
  K := K and 31;
  if K = 0 then
    Result := X
  else
    Result := (X shl K) or (X shr (32 - K));
end;

function RotL32Slow(X: UInt32; K: Integer): UInt32;
var
  I: Integer;
begin
  Result := X;
  for I := 1 to K and 31 do
    Result := (Result shl 1) or (Result shr 31);
end;

procedure RunRotForms;
var
  I, K: Integer;
  X, W: UInt64;
  X32: UInt32;
begin
  W := 0;
  for I := 1 to 40 do
  begin
    X := Rnd;
    K := Integer(Rnd mod 100);           { above 63 exercises the mask }
    Check(RotL64(X, K) = RotL64Slow(X, K), 'zoo2-rot64-model');
    W := W xor RotL64(X, K);
  end;
  for I := 1 to 24 do
  begin
    X32 := UInt32(Rnd);
    K := Integer(Rnd mod 70);
    Check(RotL32(X32, K) = RotL32Slow(X32, K), 'zoo2-rot32-model');
    W := W xor X32;
  end;
  X := OpaqueU(UInt64($DEADBEEFCAFEBABE));
  Check((RotL64(X, 0) = X) and (RotL64(X, 64) = X), 'zoo2-rot-edge0');

  Mix(W);
end;

{ ---------------------------------------------------------------- }
{ 18. Routine-LOCAL writable typed consts: static storage duration, }
{ state persists across calls (the Pascal "C static"). One scalar,  }
{ one record with field-wise mutation.                              }

{$J+}
function NextTicket: Integer;
const
  Ticket: Integer = 100;
begin
  Inc(Ticket);
  Result := Ticket;
end;

function StampPoint: Integer;
const
  Pt: TWInner = (A: 5; B: 40);
begin
  Inc(Pt.A);
  Result := Pt.A * 1000 + Pt.B;
end;
{$J-}

procedure RunLocalWtcForms;
var
  R1, R2, R3: Integer;
begin
  R1 := NextTicket;
  R2 := NextTicket;
  R3 := NextTicket;
  Check((R1 = 101) and (R2 = 102) and (R3 = 103), 'zoo2-wtc-counter');

  R1 := StampPoint;
  R2 := StampPoint;
  Check(R1 = 6040, 'zoo2-wtc-record-first');
  Check(R2 = 7040, 'zoo2-wtc-record-persists');

  Mix(UInt64(UInt32(R2 + R3)));
end;

{ ---------------------------------------------------------------- }
{ 19. New/Dispose with managed record fields: New must init the     }
{ string and dyn array, Dispose must finalize them. A prepend-built }
{ list is walked, reversed in place, walked again.                  }

type
  PZNode = ^TZNode;
  TZNode = record
    Name: AnsiString;
    Load: TIntDyn;
    Next: PZNode;
  end;

procedure RunListForms;
var
  Head, P, Prev, Nxt: PZNode;
  K, Sum: Integer;
  Trail: AnsiString;
begin
  Head := nil;
  for K := 0 to 4 do
  begin
    New(P);
    { New inits MANAGED fields only; the raw Next pointer is undefined }
    Check((P^.Name = '') and (P^.Load = nil), 'zoo2-list-new-init');
    P^.Name := AnsiString('n') + AnsiChar(Ord('0') + K);
    SetLength(P^.Load, 1);
    P^.Load[0] := K * 100;
    P^.Next := Head;
    Head := P;
  end;

  Trail := '';
  P := Head;
  while P <> nil do
  begin
    Trail := Trail + P^.Name;
    P := P^.Next;
  end;
  Check(Trail = 'n4n3n2n1n0', 'zoo2-list-walk');

  { in-place reversal }
  Prev := nil;
  P := Head;
  while P <> nil do
  begin
    Nxt := P^.Next;
    P^.Next := Prev;
    Prev := P;
    P := Nxt;
  end;
  Head := Prev;

  Trail := '';
  Sum := 0;
  P := Head;
  while P <> nil do
  begin
    Trail := Trail + P^.Name;
    Sum := Sum * 10 + P^.Load[0] div 100;
    P := P^.Next;
  end;
  Check(Trail = 'n0n1n2n3n4', 'zoo2-list-reversed');
  Check(Sum = 1234, 'zoo2-list-dyn-payload');   { 0,1,2,3,4 folded }

  P := Head;
  while P <> nil do
  begin
    Nxt := P^.Next;
    Dispose(P);                          { finalizes Name and Load }
    P := Nxt;
  end;

  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 20. case over AnsiChar ranges swept through all 256 byte values   }
{ from runtime-opaque input, vs an explicit ord-compare model.      }

function Classify(C: AnsiChar): Integer;
begin
  case C of
    'a'..'z': Result := 1;
    'A'..'Z': Result := 2;
    '0'..'9': Result := 3;
    '_', '$': Result := 4;
  else
    Result := 0;
  end;
end;

function ClassifyModel(B: Byte): Integer;
begin
  if (B >= Ord('a')) and (B <= Ord('z')) then
    Result := 1
  else if (B >= Ord('A')) and (B <= Ord('Z')) then
    Result := 2
  else if (B >= Ord('0')) and (B <= Ord('9')) then
    Result := 3
  else if (B = Ord('_')) or (B = Ord('$')) then
    Result := 4
  else
    Result := 0;
end;

procedure RunCaseCharForms;
var
  K, Sum: Integer;
  C: AnsiChar;
begin
  Sum := 0;
  for K := 0 to 255 do
  begin
    C := AnsiChar(Byte(OpaqueI(K)));
    Check(Classify(C) = ClassifyModel(Byte(K)), 'zoo2-case-char-sweep');
    Sum := Sum + Classify(C);
  end;
  { 26+26 letters, 10 digits, 2 specials: 26+52+30+8 }
  Check(Sum = 116, 'zoo2-case-char-total');

  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ ROUND 3 (zoo3-): code forms mined from live Pascal repositories.  }
{ Core: caret control-char literals, index-specifier properties.    }
{ Modern (gated): custom managed records, an object implementing a  }
{ "reference to" type, Delphi 12 surface syntax.                    }
{ ---------------------------------------------------------------- }

{ 21. Caret control-char literals: ^A..^Z, ^[, ^\, ^] are still in  }
{ the grammar; they are plain char constants usable in expressions  }
{ and case labels.                                                  }

procedure RunCaretForms;
var
  C: Char;
  S: AnsiString;
  R: Integer;
begin
  C := ^M;
  Check(Ord(C) = 13, 'zoo3-caret-cr');
  Check((Ord(^A) = 1) and (Ord(^Z) = 26), 'zoo3-caret-az');
  Check((Ord(^[) = 27) and (Ord(^\) = 28) and (Ord(^]) = 29),
    'zoo3-caret-brackets');

  S := AnsiChar(^J);
  S := S + AnsiChar(^M);
  Check((Length(S) = 2) and (S[1] = #10) and (S[2] = #13),
    'zoo3-caret-concat');

  C := Char(Integer(OpaqueI(9)));
  case C of
    ^I: R := 1;
    ^M: R := 2;
  else
    R := 0;
  end;
  Check(R = 1, 'zoo3-caret-case');

  Mix(UInt64(UInt32(Ord(C) + R)));
end;

{ ---------------------------------------------------------------- }
{ 22. Index-specifier properties: several properties dispatch into  }
{ ONE getter/setter pair distinguished by a compile-time index.     }

type
  TZDialCore = class
  private
    FCells: array[0..2] of Integer;
    function GetScaled(Ix: Integer): Integer;
    function GetCell(Ix: Integer): Integer;
    procedure SetCell(Ix: Integer; V: Integer);
  public
    Base: Integer;
    property Units: Integer index 1 read GetScaled;
    property Tens: Integer index 10 read GetScaled;
    property Hundreds: Integer index 100 read GetScaled;
    property CellA: Integer index 0 read GetCell write SetCell;
    property CellB: Integer index 1 read GetCell write SetCell;
    property CellC: Integer index 2 read GetCell write SetCell;
  end;

function TZDialCore.GetScaled(Ix: Integer): Integer;
begin
  Result := Base * Ix;
end;

function TZDialCore.GetCell(Ix: Integer): Integer;
begin
  Result := FCells[Ix];
end;

procedure TZDialCore.SetCell(Ix: Integer; V: Integer);
begin
  FCells[Ix] := V;
end;

procedure RunIndexPropForms;
var
  D: TZDialCore;
begin
  D := TZDialCore.Create;
  D.Base := 3;
  Check((D.Units = 3) and (D.Tens = 30) and (D.Hundreds = 300),
    'zoo3-idxprop-read');
  D.CellB := 55;
  D.CellC := D.CellB + 1;
  Check((D.CellA = 0) and (D.CellB = 55) and (D.CellC = 56),
    'zoo3-idxprop-write');
  D.Base := Integer(OpaqueI(7));
  Check(D.Tens = 70, 'zoo3-idxprop-opaque-base');
  Mix(UInt64(UInt32(D.Hundreds + D.CellC)));
  D.Free;
end;

{$ifdef HAS_MREC}
{ ---------------------------------------------------------------- }
{ 23. Custom managed records: the compiler injects Initialize on    }
{ declaration, Finalize on scope exit, Assign on :=. The counters   }
{ pin exactly WHERE those hidden calls happen — value params, dyn   }
{ arrays, function results. Where the docs are vague the pins are   }
{ measured on dcc64 12.2 and serve as tripwires.                    }

var
  MInit, MFini, MCopy: Integer;

type
  TMRecZ = record
    V: Integer;
    class operator Initialize(out Dest: TMRecZ);
    class operator Finalize(var Dest: TMRecZ);
    class operator Assign(var Dest: TMRecZ; const [ref] Src: TMRecZ);
  end;
  TMRecDyn = array of TMRecZ;

class operator TMRecZ.Initialize(out Dest: TMRecZ);
begin
  Dest.V := 7;
  Inc(MInit);
end;

class operator TMRecZ.Finalize(var Dest: TMRecZ);
begin
  Inc(MFini);
end;

class operator TMRecZ.Assign(var Dest: TMRecZ; const [ref] Src: TMRecZ);
begin
  Dest.V := Src.V + 100;                 { custom copy is observable }
  Inc(MCopy);
end;

procedure MRecScopePair;
var
  A, B: TMRecZ;
begin
  Check(A.V = 7, 'zoo3-mrec-init-value');
  A.V := 1;
  B := A;
  Check(B.V = 101, 'zoo3-mrec-assign-custom');
end;

procedure MRecEatByValue(M: TMRecZ);
begin
  M.V := M.V + 1;
end;

function MRecMake(K: Integer): TMRecZ;
begin
  Result.V := K;
end;

procedure RunManagedRecForms;
var
  I0, F0, C0: Integer;
  DA: TMRecDyn;
  L: TMRecZ;
begin
  I0 := MInit;
  F0 := MFini;
  C0 := MCopy;
  MRecScopePair;
  Check(MInit - I0 = 2, 'zoo3-mrec-init-on-decl');
  Check(MFini - F0 = 2, 'zoo3-mrec-fini-on-exit');
  Check(MCopy - C0 = 1, 'zoo3-mrec-assign-fires');

  { value parameter: the callee copy is a full managed lifecycle }
  I0 := MInit;
  F0 := MFini;
  C0 := MCopy;
  L.V := 40;                             { L initialized at proc entry }
  MRecEatByValue(L);
  Check(L.V = 40, 'zoo3-mrec-valparam-isolated');
  Check((MInit - I0) + (MCopy - C0) >= 1, 'zoo3-mrec-valparam-copied');
  Check(MFini - F0 = MInit - I0, 'zoo3-mrec-valparam-balanced');

  { function result assigned to an existing initialized local: NRV
    aliases Result straight into L — the custom Assign does NOT run
    (V stays 5, not 105) and copy count is untouched }
  C0 := MCopy;
  L := MRecMake(5);
  Check(L.V = 5, 'zoo3-mrec-result-value');
  Check(MCopy - C0 = 0, 'zoo3-mrec-result-nrv');

  { dyn array growth initializes new elements, shrink finalizes }
  I0 := MInit;
  F0 := MFini;
  SetLength(DA, 3);
  Check(MInit - I0 = 3, 'zoo3-mrec-setlength-inits');
  Check(DA[2].V = 7, 'zoo3-mrec-setlength-value');
  SetLength(DA, 1);
  Check(MFini - F0 = 2, 'zoo3-mrec-setlength-finis');
  DA := nil;
  Check(MFini - F0 = 3, 'zoo3-mrec-nil-finalizes');

  Mix(UInt64(UInt32(MInit - MFini)));
  Mix(UInt64(UInt32(L.V)));
end;
{$endif}

{$ifdef HAS_FUNCOBJ}
{ ---------------------------------------------------------------- }
{ 24. A class IMPLEMENTS a "reference to function" type: anonymous  }
{ method types are interfaces with Invoke, so a method resolution   }
{ clause maps Invoke onto a plain method. The object is assignable  }
{ to the func variable, is CALLABLE as F(x), carries mutable state, }
{ and refcounts like any interface. A real closure can then be      }
{ swapped into the same variable.                                   }

type
  TZFunc = reference to function(A: Integer): Integer;

  TTripler = class(TInterfacedObject, TZFunc)
  private
    function TZFunc.Invoke = Scale;
  public
    Mult: Integer;                       { instance field before class var }
    class var Alive: Integer;
    constructor Create(AMult: Integer);
    destructor Destroy; override;
    function Scale(A: Integer): Integer;
  end;

constructor TTripler.Create(AMult: Integer);
begin
  inherited Create;
  Mult := AMult;
  Inc(Alive);
end;

destructor TTripler.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TTripler.Scale(A: Integer): Integer;
begin
  Result := A * Mult;
end;

procedure RunFuncObjForms;
var
  F: TZFunc;
  Tr: TTripler;
begin
  TTripler.Alive := 0;
  Tr := TTripler.Create(3);
  F := Tr;
  Check(F(14) = 42, 'zoo3-funcobj-call');
  Tr.Mult := 5;                          { state visible through F }
  Check(F(14) = 70, 'zoo3-funcobj-state');
  { Tr is a raw pointer, F owns the only counted ref; after the swap
    below the object dies and Tr dangles — never touched again }
  F := function(A: Integer): Integer
    begin
      Result := A + 1;
    end;
  Check(TTripler.Alive = 0, 'zoo3-funcobj-refcount');
  Check(F(41) = 42, 'zoo3-funcobj-swap-closure');
  Mix(UInt64(UInt32(F(1))));
end;
{$endif}

{$ifdef HAS_D12}
{ ---------------------------------------------------------------- }
{ 25. Delphi 12 surface syntax: multiline string literals (CRLF     }
{ line breaks, indentation stripped to the closing quotes column),  }
{ the align clause on records, digit separators and % binary        }
{ literals. Semantics-light but pins the lowering of brand-new      }
{ sugar against hand-built equivalents.                             }

type
  TAl8 = record
    B: Byte;
  end align 8;
  TAl16 = record
    W: Word;
  end align 16;

procedure RunD12SyntaxForms;
var
  ML: string;
  Arr16: array[0..1] of TAl16;
  A, B, C: Integer;
begin
  ML := '''
    alpha
    beta
    ''';
  Check(ML = 'alpha' + #13#10 + 'beta', 'zoo3-d12-multiline');
  ML := '''
      alpha
    ''';
  Check(ML = '  alpha', 'zoo3-d12-multiline-indent');

  Check(SizeOf(TAl8) = 8, 'zoo3-d12-align8');
  Check(SizeOf(TAl16) = 16, 'zoo3-d12-align16');
  Check(NativeInt(@Arr16[1]) - NativeInt(@Arr16[0]) = 16,
    'zoo3-d12-align-stride');

  A := 1_234_567;
  B := %1010_1010;
  C := $BE_EF;
  Check((A = 1234567) and (B = 170) and (C = $BEEF), 'zoo3-d12-digitsep');

  Mix(UInt64(UInt32(Length(ML) + A + B + C)));
end;
{$endif}

{ ---------------------------------------------------------------- }
{ ROUND f2f: control/data-flow forms verified on dcc64 at O+/O-.    }
{ Two forms stay OUT of the                                         }
{ shared file by design: variable-carrier for-in mutation (use-     }
{ after-free risk if FPC does not retain the carrier) and the       }
{ inter-arm case goto (possible FPC compile error).                 }
{ ---------------------------------------------------------------- }

{ 26. for-in over a FUNCTION-RESULT carrier: the temp must be       }
{ materialized under any capture policy; called exactly once, and   }
{ niling the source global mid-walk is harmless.                    }

var
  CarArr: TIntDyn;
  CarCalls: Integer = 0;

function CarFeed: TIntDyn;
begin
  Inc(CarCalls);
  Result := CarArr;
end;

procedure RunForInFuncCarrierForms;
var
  Model: TIntDyn;
  V, K, Sum, ModelSum: Integer;
begin
  SetLength(CarArr, 6);
  for K := 0 to 5 do
    CarArr[K] := K * K + 1;            { 1 2 5 10 17 26 }
  Model := Copy(CarArr);
  ModelSum := 0;
  for K := 0 to High(Model) do
    ModelSum := ModelSum + Model[K];
  CarCalls := 0;
  Sum := 0;
  for V in CarFeed do
  begin
    Sum := Sum + V;
    CarArr := nil;                     { temp keeps the walk alive }
  end;
  Check(Sum = ModelSum, 'f2f-forin-func-carrier-walk');
  Check(CarCalls = 1, 'f2f-forin-func-carrier-once');
  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 27. Exit(expr): the argument is evaluated BEFORE the finally      }
{ chain; a finally running because of an Exit may call a helper     }
{ doing its own Exit-through-finally (funclet-in-funclet).          }

var
  XTrail: AnsiString;

function XMark(V: Integer): Integer;
begin
  XTrail := XTrail + 'E';
  Result := V;
end;

function ExitArgOrder: Integer;
begin
  Result := 0;
  try
    try
      Exit(XMark(5));
    finally
      XTrail := XTrail + 'a';
    end;
  finally
    XTrail := XTrail + 'b';
  end;
end;

function InnerExiter: Integer;
begin
  Result := 0;
  try
    Exit(3);
  finally
    XTrail := XTrail + 'i';
  end;
end;

function OuterExiter: Integer;
begin
  Result := 0;
  try
    Exit(40);
  finally
    XTrail := XTrail + 'f';
    XTrail := XTrail + AnsiChar(Ord('0') + InnerExiter);
  end;
end;

procedure RunExitUnwindForms;
var
  K: Integer;
begin
  XTrail := '';
  K := ExitArgOrder;
  Check((K = 5) and (XTrail = 'Eab'), 'f2f-exit-arg-before-finally');

  XTrail := '';
  K := OuterExiter;
  Check((K = 40) and (XTrail = 'fi3'), 'f2f-exit-nested-unwind');
  Mix(UInt64(UInt32(K + Length(XTrail))));
end;

{ ---------------------------------------------------------------- }
{ 28. raise inside finally: with nothing in flight it is just a new }
{ exception; with EVictim in flight the original is LOST and (pin)  }
{ dcc64 still destroys the lost object. FPC leak = expected split.  }

type
  EQuiet = class(Exception);
  EVictim = class(Exception)
  public
    destructor Destroy; override;
  end;
  EUsurper = class(Exception);

var
  VictimGone: Integer = 0;

destructor EVictim.Destroy;
begin
  Inc(VictimGone);
  inherited Destroy;
end;

procedure RunFinallyRaiseForms;
var
  Trail: AnsiString;
begin
  Trail := '';
  try
    try
      Trail := Trail + '1';
    finally
      Trail := Trail + '2';
      raise EQuiet.Create('fresh');
    end;
    Trail := Trail + 'X';              { skipped: finally raised }
  except
    on EQuiet do
      Trail := Trail + '3';
  end;
  Check(Trail = '123', 'f2f-raise-in-quiet-finally');

  VictimGone := 0;
  Trail := '';
  try
    try
      raise EVictim.Create('victim');
    finally
      Trail := Trail + 'f';
      raise EUsurper.Create('usurper');
    end;
  except
    on EUsurper do
      Trail := Trail + 'U';
    on EVictim do
      Trail := Trail + 'V';
  end;
  Check(Trail = 'fU', 'f2f-finally-usurps-exception');
  Check(VictimGone = 1, 'f2f-usurped-object-freed');
  Mix(UInt64(UInt32(Length(Trail) + VictimGone)));
end;

{ ---------------------------------------------------------------- }
{ 29. for bounds are FROZEN at entry; an empty loop still evaluates }
{ both bound expressions exactly once (side effects commutative on  }
{ purpose — Lo/Hi order is a gray zone we skip). Loop variable is   }
{ readable after Break (FPC documents it, Delphi folklore pin).     }

var
  LoCalls: Integer = 0;
  HiCalls: Integer = 0;

function LoB(V: Integer): Integer;
begin
  Inc(LoCalls);
  Result := V;
end;

function HiB(V: Integer): Integer;
begin
  Inc(HiCalls);
  Result := V;
end;

procedure RunFrozenBoundForms;
var
  I, J, N, Cnt: Integer;
begin
  N := Integer(OpaqueI(5));
  Cnt := 0;
  for I := 1 to N do
  begin
    if I = 1 then
      N := 1;                          { too late: bound is frozen }
    Inc(Cnt);
  end;
  Check((Cnt = 5) and (N = 1), 'f2f-frozen-bound-to');

  N := Integer(OpaqueI(5));
  Cnt := 0;
  for I := N downto 1 do
  begin
    if I = 5 then
      N := -100;
    Inc(Cnt);
  end;
  Check((Cnt = 5) and (N = -100), 'f2f-frozen-bound-downto');

  LoCalls := 0;
  HiCalls := 0;
  Cnt := 0;
  for I := LoB(5) to HiB(4) do
    Inc(Cnt);
  Check((Cnt = 0) and (LoCalls = 1) and (HiCalls = 1),
    'f2f-empty-loop-evals-bounds');

  for I := 0 to 99 do
    if I = Integer(OpaqueI(37)) then
      Break;
  Check(I = 37, 'f2f-break-preserves-var');

  for J := 99 downto 0 do
    if J = Integer(OpaqueI(61)) then
      Break;
  Check(J = 61, 'f2f-break-preserves-var-downto');
  Mix(UInt64(UInt32(I + J)));
end;

{ ---------------------------------------------------------------- }
{ 30. for-in over a SET iterates a SNAPSHOT on dcc64: Exclude of a  }
{ not-yet-visited member does not hide it, Include does not add it. }
{ Pinned behavior, not a language guarantee — FPC live-read would   }
{ be a dialect seam for the known-failures table.                   }

procedure RunSetSnapshotForms;
var
  BS: set of 0..31;
  Model: array[0..31] of Boolean;
  B: Byte;
  K, Walk, ModelWalk: Integer;
begin
  BS := [1, 3, 5, 30];
  for K := 0 to 31 do
    Model[K] := K in BS;               { snapshot before mutation }
  Walk := 0;
  for B in BS do
  begin
    Walk := Walk * 100 + B;
    if B = 1 then
      Exclude(BS, 30);
    if B = 3 then
      Include(BS, 20);
  end;
  ModelWalk := 0;
  for K := 0 to 31 do
    if Model[K] then
      ModelWalk := ModelWalk * 100 + K;
  Check(Walk = ModelWalk, 'f2f-set-forin-snapshot');
  Check(not (30 in BS), 'f2f-set-forin-excluded');
  Check(20 in BS, 'f2f-set-forin-included');
  Mix(UInt64(UInt32(Walk)));
end;

{ ---------------------------------------------------------------- }
{ 31. var-parameter aliasing braids: several var params bound to    }
{ one variable; a var param aliasing a global the callee names.     }
{ No gray zone: var must alias at every optimization level.         }

procedure Mangle(var A, B: Integer);
begin
  A := A + B;                          { X = 2X }
  B := B * 3;                          { X = 6X }
  A := A - 1;                          { X = 6X - 1 }
end;

procedure Tri(var A, B, C: Integer);
begin
  A := A + 1;
  B := B * 2;
  C := C + A;
end;

var
  GAlias: Integer;

procedure PokeThrough(var A: Integer);
begin
  A := A + 1;                          { G = 8 }
  GAlias := GAlias * 2;                { G = 16 }
  A := A + GAlias;                     { G = 32 }
end;

procedure RunVarAliasForms;
var
  X: Integer;
begin
  X := Integer(OpaqueI(5));
  Mangle(X, X);
  Check(X = 29, 'f2f-var-alias-pair');

  X := Integer(OpaqueI(3));
  Tri(X, X, X);
  Check(X = 16, 'f2f-var-alias-triple');

  GAlias := Integer(OpaqueI(7));
  PokeThrough(GAlias);
  Check(GAlias = 32, 'f2f-var-alias-global');
  Mix(UInt64(UInt32(X + GAlias)));
end;

{ ---------------------------------------------------------------- }
{ 32. Recursion through a procedural VARIABLE that every step       }
{ reassigns to the other function: the indirect call site must      }
{ re-read the variable after the assignment in the same body.       }

type
  TStep = function(N: Integer): Integer;

var
  StepV: TStep;

function StepB(N: Integer): Integer; forward;

function StepA(N: Integer): Integer;
begin
  if N = 0 then
    Exit(0);
  StepV := StepB;
  Result := StepV(N - 1) * 10 + 1;
end;

function StepB(N: Integer): Integer;
begin
  if N = 0 then
    Exit(0);
  StepV := StepA;
  Result := StepV(N - 1) * 10 + 2;
end;

procedure RunProcVarFlipForms;
begin
  StepV := StepA;
  { A4=B3*10+1, B3=A2*10+2, A2=B1*10+1, B1=A0*10+2, A0=0 -> 2121 }
  Check(StepV(4) = 2121, 'f2f-procvar-flipflop');
  Check(StepV(5) = 12121, 'f2f-procvar-flipflop-odd');
  Mix(UInt64(UInt32(StepV(4))));
end;

{ ---------------------------------------------------------------- }
{ 33. Re-entering try/try..finally 100 times with alternating       }
{ exception classes: unwind state must reset perfectly per round.   }

procedure RunEhReentryForms;
var
  K, FinCount, Caught: Integer;
begin
  FinCount := 0;
  Caught := 0;
  for K := 1 to 100 do
    try
      try
        if Odd(K) then
          raise EVictim.Create('o')
        else
          raise EUsurper.Create('r');
      finally
        Inc(FinCount);
      end;
    except
      on EVictim do
        Inc(Caught);
      on EUsurper do
        Inc(Caught, 1000);
    end;
  Check(FinCount = 100, 'f2f-eh-reentry-finallys');
  Check(Caught = 50050, 'f2f-eh-reentry-catches');
  Mix(UInt64(UInt32(Caught)));
end;

{ ---------------------------------------------------------------- }
{ 34. while condition = 5-link short-circuit braid of functions     }
{ with side effects. Oracle: the same predicate re-lowered by hand  }
{ into explicit if/Exit steps over its OWN state, trails compared.  }

var
  BrState: Integer;
  BrLimit: Integer;
  BrTrail: UInt64;

procedure BLog(D: Integer; var Tr: UInt64);
begin
  Tr := (Tr xor UInt64(UInt32(D))) * FNVPrm;
end;

function BrA: Boolean;
begin
  BLog(1, BrTrail);
  Inc(BrState);
  Result := BrState < BrLimit;
end;

function BrB: Boolean;
begin
  BLog(2, BrTrail);
  Result := (BrState and 3) = 3;
end;

function BrC: Boolean;
begin
  BLog(3, BrTrail);
  Result := (BrState mod 3) <> 1;
end;

function BrD: Boolean;
begin
  BLog(4, BrTrail);
  Result := (BrState and 4) <> 0;
end;

function BrE: Boolean;
begin
  BLog(5, BrTrail);
  Result := (BrState and 2) <> 0;
end;

function ModelStep(Limit: Integer; var St: Integer; var Tr: UInt64): Boolean;
var
  FA, FB, FC, FD: Boolean;
begin
  BLog(1, Tr);
  Inc(St);
  FA := St < Limit;
  if FA then
  begin
    BLog(2, Tr);
    FB := (St and 3) = 3;
    if not FB then
      Exit(True);
  end;
  BLog(3, Tr);
  FC := (St mod 3) <> 1;
  if not FC then
    Exit(False);
  BLog(4, Tr);
  FD := (St and 4) <> 0;
  if FD then
    Exit(True);
  BLog(5, Tr);
  Result := (St and 2) <> 0;
end;

procedure RunShortCircuitBraidForms;
var
  Body, ModelBody, ModelState: Integer;
  ModelTrail: UInt64;
begin
  { long life: left arm carries most rounds, right arm rescues St=3 }
  BrState := 0;
  BrTrail := 0;
  BrLimit := 20;
  Body := 0;
  while (BrA and not BrB) or (BrC and (BrD or BrE)) do
    Inc(Body);
  ModelState := 0;
  ModelTrail := 0;
  ModelBody := 0;
  while ModelStep(20, ModelState, ModelTrail) do
    Inc(ModelBody);
  Check(Body = ModelBody, 'f2f-braid-long-body');
  Check(BrState = ModelState, 'f2f-braid-long-state');
  Check(BrTrail = ModelTrail, 'f2f-braid-long-trail');
  Check(Body = 6, 'f2f-braid-long-pin');

  { short life: A goes false early, the B call must be SKIPPED and
    the right arm alone keeps the loop alive }
  BrState := 0;
  BrTrail := 0;
  BrLimit := 3;
  Body := 0;
  while (BrA and not BrB) or (BrC and (BrD or BrE)) do
    Inc(Body);
  ModelState := 0;
  ModelTrail := 0;
  ModelBody := 0;
  while ModelStep(3, ModelState, ModelTrail) do
    Inc(ModelBody);
  Check(Body = ModelBody, 'f2f-braid-short-body');
  Check(BrTrail = ModelTrail, 'f2f-braid-short-trail');
  Check(Body = 3, 'f2f-braid-short-pin');
  Mix(BrTrail);
end;

{ ---------------------------------------------------------------- }
{ 35. repeat..until with a side-effect CONDITION function and       }
{ Continue: Continue jumps to the condition, so condition-eval      }
{ count = iteration count, always.                                  }

var
  CondEvals: Integer = 0;

function TickCond(V: Boolean): Boolean;
begin
  Inc(CondEvals);
  Result := V;
end;

procedure RunRepeatCondForms;
var
  K, Body: Integer;
begin
  CondEvals := 0;
  K := 0;
  Body := 0;
  repeat
    Inc(K);
    if (K and 1) = 1 then
      Continue;                        { straight to the condition }
    Inc(Body);
  until TickCond(K >= 14);
  Check(K = 14, 'f2f-repeat-cond-iters');
  Check(CondEvals = 14, 'f2f-repeat-cond-evals');
  Check(Body = 7, 'f2f-repeat-cond-body');
  Mix(UInt64(UInt32(K + Body)));
end;

{ ---------------------------------------------------------------- }
{ ROUND fty: type/declaration forms verified on dcc64 at O+/O-. The }
{ for-in-via-record-helper CRASH finding lives as forinhlp.dpr in   }
{ the corpus root (cannot be a form — it kills the run). Helper     }
{ operators and dual default properties are gated (HAS_HOPERS /     }
{ HAS_MULTIDEF): high FPC compile-rejection risk.                   }
{ ---------------------------------------------------------------- }

{ 36. Legacy TP-style object types on Win64: stack instances, VMT   }
{ set by the constructor, virtual dispatch through a pointer and a  }
{ var parameter, a static method calling a virtual one.             }

type
  POShape = ^TOShape;
  TOShape = object
    Tag: Integer;
    constructor Init(ATag: Integer);
    function Area: Integer; virtual;
    function TwiceArea: Integer;
  end;

  TOSquare = object(TOShape)
    Side: Integer;
    constructor Init(ATag, ASide: Integer);
    function Area: Integer; virtual;
  end;

constructor TOShape.Init(ATag: Integer);
begin
  Tag := ATag;
end;

function TOShape.Area: Integer;
begin
  Result := 10 + Tag;
end;

function TOShape.TwiceArea: Integer;
begin
  Result := Area * 2;                  { virtual call from a static method }
end;

constructor TOSquare.Init(ATag, ASide: Integer);
begin
  inherited Init(ATag);
  Side := ASide;
end;

function TOSquare.Area: Integer;
begin
  Result := Side * Side;
end;

function CallAreaVar(var S: TOShape): Integer;
begin
  Result := S.Area;                    { dispatch through var-param view }
end;

procedure RunTpObjectForms;
var
  Sh: TOShape;
  Sq: TOSquare;
  P: POShape;
begin
  Sh.Init(3);
  Sq.Init(4, Integer(OpaqueI(5)));
  Check(Sh.Area = 13, 'fty-tpobj-static-area');
  Check(Sq.Area = Sq.Side * Sq.Side, 'fty-tpobj-virtual-area');
  Check(Sq.Tag = 4, 'fty-tpobj-inherited-ctor');
  P := @Sq;
  Check(P^.Area = 25, 'fty-tpobj-ptr-dispatch');
  Check(CallAreaVar(Sq) = 25, 'fty-tpobj-varparam-dispatch');
  Check(Sq.TwiceArea = 50, 'fty-tpobj-static-calls-virtual');
  Check(Sh.TwiceArea = 26, 'fty-tpobj-base-twice');
  Check(SizeOf(TOSquare) > SizeOf(TOShape), 'fty-tpobj-size-grows');
  Mix(UInt64(UInt32(Sh.Area + Sq.Area)));
end;

{ ---------------------------------------------------------------- }
{ 37. Class helper HIDES a virtual method. Pins: the helper wins at }
{ every call site including the class's OWN method bodies; helper   }
{ binding is by STATIC type of the reference; "inherited X" inside  }
{ a helper is a STATIC call to the extended class's X; a derived    }
{ helper's inherited binds to the derived extended class's method.  }

type
  TAni = class
  public
    function Speak: Integer; virtual;
    function SelfSpeak: Integer;
  end;

  TDog = class(TAni)
  public
    function Speak: Integer; override;
  end;

  TAniHelper = class helper for TAni
  public
    function Speak: Integer;
    function RealSpeak: Integer;
  end;

  TDogHelper = class helper(TAniHelper) for TDog
  public
    function Speak: Integer;
    function ParentSpeak: Integer;
  end;

  THelperPropertyBase = class
  private
    FValue: Single;
    procedure SetValue(const AValue: Single);
  public
    property Value: Single read FValue write SetValue;
  end;

  THelperProperty = class helper for THelperPropertyBase
  private
    function GetValue: Single;
    procedure SetValue(AValue: Single);
  public
    property Value: Single read GetValue write SetValue;
  end;

function TAni.Speak: Integer;
begin
  Result := 1;
end;

function TAni.SelfSpeak: Integer;
begin
  Result := Speak;                     { helper already in scope here }
end;

function TDog.Speak: Integer;
begin
  Result := 2;
end;

function TAniHelper.Speak: Integer;
begin
  Result := 100 + inherited Speak;
end;

function TAniHelper.RealSpeak: Integer;
begin
  Result := inherited Speak;
end;

function TDogHelper.Speak: Integer;
begin
  Result := 9000 + inherited Speak;
end;

function TDogHelper.ParentSpeak: Integer;
begin
  Result := inherited Speak;
end;

procedure THelperPropertyBase.SetValue(const AValue: Single);
begin
  FValue := AValue;
end;

function THelperProperty.GetValue: Single;
begin
  Result := inherited Value;
end;

procedure THelperProperty.SetValue(AValue: Single);
begin
  inherited Value := AValue;
end;

procedure RunHelperShadowForms;
var
  A: TAni;
  D: TDog;
  P: THelperPropertyBase;
begin
  D := TDog.Create;
  A := D;
  Check(A.Speak = 101, 'fty-helper-hides-virtual');
  Check(D.Speak = 9002, 'fty-helper-static-type-dispatch');
  Check(A.RealSpeak = 1, 'fty-helper-inherited-static');
  Check(D.ParentSpeak = 2, 'fty-helper-chain-inherited');
  Check(A.SelfSpeak = 101, 'fty-helper-hijacks-class-internals');
  D.Free;
  A := TAni.Create;
  Check(A.Speak = 101, 'fty-helper-base-object');
  Check(A.RealSpeak = 1, 'fty-helper-base-real');
  A.Free;
  P := THelperPropertyBase.Create;
  P.Value := 7.5;
  Check(P.Value = 7.5, 'fty-helper-inherited-property-accessors');
  P.Free;
  Mix(101);
end;

{ ---------------------------------------------------------------- }
{ 38. Custom enumerator whose Current is a POINTER: for-in hands    }
{ out PInteger and the loop body mutates the array through it.      }
{ GetEnumerator sits directly on the range record (the helper-      }
{ provided variant is the forinhlp.dpr crash).                      }

type
  TPtrEnum = record
    FP: PInteger;
    FIdx, FHigh: Integer;
    function MoveNext: Boolean;
    property Current: PInteger read FP;
  end;

  TPtrRange = record
    FBase: PInteger;
    FCount: Integer;
    function GetEnumerator: TPtrEnum;
  end;

function TPtrEnum.MoveNext: Boolean;
begin
  Inc(FIdx);
  if FIdx > 0 then
    Inc(FP);
  Result := FIdx <= FHigh;
end;

function TPtrRange.GetEnumerator: TPtrEnum;
begin
  Result.FP := FBase;
  Result.FIdx := -1;
  Result.FHigh := FCount - 1;
end;

function OverArr(var A: array of Integer): TPtrRange;
begin
  Result.FBase := @A[0];
  Result.FCount := Length(A);
end;

procedure RunPtrEnumForms;
var
  Arr, Model: array[0..7] of Integer;
  PP: PInteger;
  K: Integer;
  W: UInt64;
begin
  for K := 0 to 7 do
  begin
    Arr[K] := Integer(Rnd and $FFFF);
    Model[K] := Arr[K];
  end;
  for PP in OverArr(Arr) do
    PP^ := PP^ * 2 + 1;
  for K := 0 to 7 do
    Check(Arr[K] = Model[K] * 2 + 1, 'fty-ptrenum-mutate');
  W := 0;
  for K := 0 to 7 do
    W := W * 31 + UInt64(UInt32(Arr[K]));
  Mix(W);
end;

{ ---------------------------------------------------------------- }
{ 39. class constructor / class destructor on a class, on a RECORD, }
{ and on a generic (one run PER INSTANTIATION with its own class    }
{ var copy). All run before the main block; *100+7 trail proves     }
{ single execution.                                                 }

var
  GBootTrail: Integer = 0;
  GBootCount: Integer = 0;

type
  TBooted = class
  public
    class var Stamp: Integer;
    class constructor Create;
    class destructor Destroy;
  end;

  TRecBoot = record
  public
    class var Seen: Integer;
    class constructor Create;
  end;

  TGBoot<T> = class
  public
    class var Mark: Integer;
    class constructor Create;
  end;

class constructor TBooted.Create;
begin
  Stamp := 41;
  GBootTrail := GBootTrail * 100 + 7;
end;

class destructor TBooted.Destroy;
begin
  Stamp := 0;                          { runs at shutdown; not checkable }
end;

class constructor TRecBoot.Create;
begin
  Seen := 88;
end;

class constructor TGBoot<T>.Create;
begin
  Mark := SizeOf(T);
  Inc(GBootCount);
end;

procedure RunClassCtorForms;
begin
  Check(TBooted.Stamp = 41, 'fty-clsctor-stamp');
  Check(GBootTrail = 7, 'fty-clsctor-ran-once');
  Check(TRecBoot.Seen = 88, 'fty-recctor-seen');
  Check(TGBoot<Integer>.Mark = 4, 'fty-genctor-per-inst-int');
  Check(TGBoot<Int64>.Mark = 8, 'fty-genctor-per-inst-i64');
  Check(GBootCount = 2, 'fty-genctor-count');
  Mix(UInt64(UInt32(TBooted.Stamp + TRecBoot.Seen + GBootCount)));
end;

{ ---------------------------------------------------------------- }
{ 40. A record as a NAMESPACE: consts (one derived from another),   }
{ nested enum and record types, the const as the record's OWN array }
{ bound, as a DEFAULT PARAMETER and as global array bounds (via an  }
{ intermediate const — "array[TDeck.Half..]" directly is E2029).    }
{ Nested enum members need the FULL path outside (TDeck.TSuit.ds*). }

type
  TDeck = record
  public
    const Cap = 8;
    const Half = Cap div 2;
    type
      TSuit = (dsHearts, dsClubs, dsSpades);
      TCard = record
        V: Integer;
        S: TSuit;
      end;
    var
      Cards: array[0..Cap - 1] of Integer;
      Best: TCard;
    function Fill(Start: Integer): Integer;
  end;

function TDeck.Fill(Start: Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := 0 to Cap - 1 do
  begin
    Cards[K] := Start + K;
    Inc(Result, Cards[K]);
  end;
  Best.V := Cards[Cap - 1];
  Best.S := dsClubs;                   { bare name legal inside the record }
end;

function DealSize(N: Integer = TDeck.Cap): Integer;
begin
  Result := N * 10;
end;

const
  DeckHalf = TDeck.Half;

var
  GHalfArr: array[DeckHalf .. TDeck.Cap] of Byte;

procedure RunRecNamespaceForms;
var
  D: TDeck;
begin
  Check(D.Fill(1) = (TDeck.Cap * (TDeck.Cap + 1)) div 2, 'fty-recns-fill');
  Check((TDeck.Cap = 8) and (D.Cap = 8), 'fty-recns-const-access');
  Check(DealSize = 80, 'fty-recns-default-param');
  Check(DealSize(2) = 20, 'fty-recns-explicit-param');
  GHalfArr[TDeck.Half] := Byte(D.Cards[0]);
  GHalfArr[TDeck.Cap] := GHalfArr[TDeck.Half] + 1;
  Check((Low(GHalfArr) = 4) and (High(GHalfArr) = 8) and
    (SizeOf(GHalfArr) = 5) and (GHalfArr[8] = GHalfArr[4] + 1),
    'fty-recns-derived-const-bounds');
  Check(Ord(TDeck.TSuit.dsSpades) = 2, 'fty-recns-nested-enum-path');
  Check((D.Best.V = 8) and (D.Best.S = TDeck.TSuit.dsClubs),
    'fty-recns-nested-record');
  Mix(UInt64(UInt32(D.Cards[TDeck.Half])));
end;

{ ---------------------------------------------------------------- }
{ 41. Properties on a RECORD: default array property (Q[i] with a   }
{ masked getter), index-specifier properties sharing one getter/    }
{ setter pair, a computed read-only property. Oracle: model array.  }

type
  TQuad = record
  private
    FV: array[0..3] of Integer;
    function GetV(I: Integer): Integer;
    procedure SetV(I: Integer; Val: Integer);
    function GetSum: Integer;
  public
    property V[I: Integer]: Integer read GetV write SetV; default;
    property North: Integer index 0 read GetV write SetV;
    property South: Integer index 2 read GetV write SetV;
    property Sum: Integer read GetSum;
  end;

function TQuad.GetV(I: Integer): Integer;
begin
  Result := FV[I and 3];
end;

procedure TQuad.SetV(I: Integer; Val: Integer);
begin
  FV[I and 3] := Val;
end;

function TQuad.GetSum: Integer;
begin
  Result := FV[0] + FV[1] + FV[2] + FV[3];
end;

procedure RunRecPropForms;
var
  Q: TQuad;
  M: array[0..3] of Integer;
  K, N: Integer;
begin
  FillChar(M, SizeOf(M), 0);
  Q[0] := 0;
  Q[1] := 0;
  Q[2] := 0;
  Q[3] := 0;
  for K := 1 to 12 do
  begin
    N := Integer(Rnd and 15);          { indices beyond 3 exercise the mask }
    Q[N] := K * 7;
    M[N and 3] := K * 7;
  end;
  for K := 0 to 3 do
    Check(Q[K] = M[K], 'fty-recprop-default-model');
  Q.North := 1000;
  M[0] := 1000;
  Q.South := 2000;
  M[2] := 2000;
  Check((Q[0] = 1000) and (Q[2] = 2000), 'fty-recprop-index-spec');
  Check(Q.Sum = M[0] + M[1] + M[2] + M[3], 'fty-recprop-sum');
  Mix(UInt64(UInt32(Q.Sum)));
end;

{ ---------------------------------------------------------------- }
{ 42. Distinct type alias (type X = type Integer): assignment       }
{ compatible, but overloads resolve by declared type and TypeInfo   }
{ is its own. A bare literal is E2251-ambiguous (compile fact).     }

type
  TUserId = type Integer;

function WhichOne(X: TUserId): Integer; overload;
begin
  Result := 1;
end;

function WhichOne(X: Integer): Integer; overload;
begin
  Result := 2;
end;

procedure RunDistinctAliasForms;
var
  U: TUserId;
  I: Integer;
begin
  U := TUserId(OpaqueI(7));
  I := Integer(OpaqueI(7));
  Check(WhichOne(U) = 1, 'fty-alias-overload-uid');
  Check(WhichOne(I) = 2, 'fty-alias-overload-int');
  Check(TypeInfo(TUserId) <> TypeInfo(Integer), 'fty-alias-typeinfo-distinct');
  Check(AnsiString(GetTypeName(TypeInfo(TUserId))) = 'TUserId',
    'fty-alias-typeinfo-name');
  U := I;
  Check(U = 7, 'fty-alias-assign-compat');
  Mix(UInt64(UInt32(WhichOne(U) * 10 + WhichOne(I))));
end;

{ ---------------------------------------------------------------- }
{ 43. Interface WITHOUT a GUID as a generic constraint: dispatch    }
{ through the constrained type param works, refcount stays sane     }
{ (GUID only matters for Supports/as).                              }

type
  INoGuid = interface
    function Twist(V: Integer): Integer;
  end;

  TTwister = class(TInterfacedObject, INoGuid)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
    function Twist(V: Integer): Integer;
  end;

  TNgWorker<T: INoGuid> = class
    class function Go(const X: T; Seed: Integer): Integer;
  end;

constructor TTwister.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TTwister.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TTwister.Twist(V: Integer): Integer;
begin
  Result := V * 3 + 1;
end;

class function TNgWorker<T>.Go(const X: T; Seed: Integer): Integer;
begin
  Result := X.Twist(Seed) * 10 + X.Twist(0);
end;

procedure RunNoGuidIntfForms;
var
  NG: INoGuid;
  N: Integer;
begin
  TTwister.Alive := 0;
  NG := TTwister.Create;
  Check(TTwister.Alive = 1, 'fty-noguid-alive');
  N := Integer(OpaqueI(5));
  Check(TNgWorker<INoGuid>.Go(NG, N) = (N * 3 + 1) * 10 + 1,
    'fty-noguid-constraint-call');
  NG := nil;
  Check(TTwister.Alive = 0, 'fty-noguid-released');
  Mix(UInt64(UInt32(TTwister.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 44. Anonymous record types straight in var sections: plain, with  }
{ a MANAGED field (auto init), and with a VARIANT PART. dcc64 lays  }
{ the ANONYMOUS variant arms at DIFFERENT offsets (each aligned     }
{ independently: Int64 arm @8, integer pair @4) while the identical }
{ NAMED record overlays both at 8 — pinned; FPC overlay expected =  }
{ split (fty-anon-varpart-arm-*). FillChar first keeps every read   }
{ deterministic under either layout.                                }

type
  TNamedVR = record
    Tag: Integer;
    case Byte of
      0: (I64: Int64);
      1: (Lo32, Hi32: Integer);
  end;

var
  GAnonVR: record
    Tag: Integer;
    case Byte of
      0: (I64: Int64);
      1: (Lo32, Hi32: Integer);
  end;

procedure RunAnonRecForms;
var
  R: record
    A, B: Integer;
  end;
  MS: record
    S: AnsiString;
    N: Integer;
  end;
  NV: TNamedVR;
begin
  R.A := Integer(OpaqueI(3));
  R.B := 4;
  Check(R.A * 10 + R.B = 34, 'fty-anon-plain');

  Check(MS.S = '', 'fty-anon-managed-init');
  MS.S := AnsiString('xy');
  MS.N := 2;
  Check(Length(MS.S) + MS.N = 4, 'fty-anon-managed-use');

  NV.Tag := 1;
  NV.I64 := Int64(OpaqueI($0000000500000007));
  Check((NV.Lo32 = 7) and (NV.Hi32 = 5), 'fty-varpart-named-overlay');

  FillChar(GAnonVR, SizeOf(GAnonVR), 0);
  GAnonVR.Tag := 1;
  GAnonVR.I64 := Int64(OpaqueI($0000000500000007));
  Check(GAnonVR.Lo32 = 0, 'fty-anon-varpart-arm-lo');   { Delphi: arm at ofs 4 }
  Check(GAnonVR.Hi32 = 7, 'fty-anon-varpart-arm-hi');   { overlaps I64's low }

  Mix(UInt64(UInt32(NV.Lo32 * 100 + NV.Hi32)));
  Mix(UInt64(UInt32(GAnonVR.Lo32 * 100 + GAnonVR.Hi32)));
end;

{ ---------------------------------------------------------------- }
{ 45. Generic record with a NESTED TYPE built from the type param   }
{ (reachable outside as TWrapG<Byte>.TCell); and <T: class,         }
{ constructor> calling the ACTUAL declared constructor (Val = 5),   }
{ not TObject.Create as the old folklore claims.                    }

type
  TWrapG<T> = record
  type
    { named TGCell, not TCell: a global TCell exists in round zoo2 and
      the method-implementation signature resolves the bare name to the
      GLOBAL type, breaking Result.V }
    TGCell = record
      V: T;
      Tag: Integer;
    end;
  var
    Main: TGCell;
    function Pack(X: T; ATag: Integer): TGCell;
  end;

  TSeeded = class
  public
    Val: Integer;
    constructor Create;
  end;

  TFactory<T: class, constructor> = class
    class function Make: T;
  end;

function TWrapG<T>.Pack(X: T; ATag: Integer): TGCell;
begin
  Result.V := X;
  Result.Tag := ATag;
end;

constructor TSeeded.Create;
begin
  inherited Create;
  Val := 5;
end;

class function TFactory<T>.Make: T;
begin
  Result := T.Create;
end;

procedure RunGenericNestedForms;
var
  W: TWrapG<Integer>;
  CB: TWrapG<Byte>.TGCell;
  Sd: TSeeded;
begin
  W.Main := W.Pack(Integer(OpaqueI(11)), 22);
  Check(W.Main.V + W.Main.Tag = 33, 'fty-gennested-pack');
  CB.V := 200;
  CB.Tag := 3;
  Check(CB.V + CB.Tag = 203, 'fty-gennested-extern-cell');
  Sd := TFactory<TSeeded>.Make;
  Check(Sd.Val = 5, 'fty-ctor-constraint-real-ctor');
  Sd.Free;
  Mix(UInt64(UInt32(W.Main.V)));
end;

{ ---------------------------------------------------------------- }
{ 46. Forward-declared class cycle with a METACLASS type declared   }
{ between the forward and the full declaration; ring walk, class-   }
{ reference field on the forward type.                              }

type
  TEgg = class;
  CEgg = class of TEgg;

  TChicken = class
  public
    MyEgg: TEgg;
    Tag: Integer;
  end;

  TEgg = class
  public
    Mom: TChicken;
    Kind: CEgg;
    Tag: Integer;
  end;

procedure RunForwardCycleForms;
var
  Ch: TChicken;
begin
  Ch := TChicken.Create;
  Ch.MyEgg := TEgg.Create;
  Ch.MyEgg.Mom := Ch;
  Ch.MyEgg.Kind := TEgg;
  Ch.Tag := Integer(OpaqueI(6));
  Ch.MyEgg.Tag := 7;
  Check(Ch.MyEgg.Mom.Tag * 10 + Ch.MyEgg.Tag = 67, 'fty-fwd-cycle-walk');
  Check(Ch.MyEgg.Mom.MyEgg = Ch.MyEgg, 'fty-fwd-ring-closed');
  Check(AnsiString(Ch.MyEgg.Kind.ClassName) = 'TEgg', 'fty-fwd-metaclass');
  Check(Ch.MyEgg.Kind.InheritsFrom(TObject), 'fty-fwd-meta-inherits');
  Ch.MyEgg.Free;
  Ch.Free;
  Mix(67);
end;

{$ifdef HAS_HOPERS}
{ ---------------------------------------------------------------- }
{ 47. Class operators declared in a RECORD HELPER — widely believed }
{ impossible, but dcc64 12.2 accepts Add/Subtract/Implicit/Equal/   }
{ NotEqual in a helper and resolves infix operators through it.     }
{ Gated: high FPC compile-rejection risk (-dTRY_HOPERS to probe).   }

type
  TVec2 = record
    X, Y: Integer;
  end;

  TVec2H = record helper for TVec2
    class operator Add(const A, B: TVec2): TVec2;
    class operator Subtract(const A, B: TVec2): TVec2;
    class operator Implicit(V: Integer): TVec2;
    class operator Equal(const A, B: TVec2): Boolean;
    class operator NotEqual(const A, B: TVec2): Boolean;
  end;

class operator TVec2H.Add(const A, B: TVec2): TVec2;
begin
  Result.X := A.X + B.X;
  Result.Y := A.Y + B.Y;
end;

class operator TVec2H.Subtract(const A, B: TVec2): TVec2;
begin
  Result.X := A.X - B.X;
  Result.Y := A.Y - B.Y;
end;

class operator TVec2H.Implicit(V: Integer): TVec2;
begin
  Result.X := V;
  Result.Y := -V;
end;

class operator TVec2H.Equal(const A, B: TVec2): Boolean;
begin
  Result := (A.X = B.X) and (A.Y = B.Y);
end;

class operator TVec2H.NotEqual(const A, B: TVec2): Boolean;
begin
  Result := not ((A.X = B.X) and (A.Y = B.Y));
end;

procedure RunHelperOperatorForms;
var
  A, B, C: TVec2;
  N: Integer;
begin
  N := Integer(OpaqueI(30));
  A.X := 1;
  A.Y := 2;
  B.X := N;
  B.Y := N + 10;
  C := A + B;
  Check((C.X = 1 + N) and (C.Y = 2 + N + 10), 'fty-hop-add');
  C := B - A;
  Check((C.X = N - 1) and (C.Y = N + 8), 'fty-hop-sub');
  C := 9;
  Check((C.X = 9) and (C.Y = -9), 'fty-hop-implicit');
  Check(A = A, 'fty-hop-eq');
  Check(A <> B, 'fty-hop-noteq');
  Mix(UInt64(UInt32(C.X - C.Y)));
end;
{$endif}

{$ifdef HAS_MULTIDEF}
{ ---------------------------------------------------------------- }
{ 48. TWO default array properties on one class, overloaded by the  }
{ index type: B[int] and B['str'] dispatch to different getters.    }
{ Gated: high FPC rejection risk (-dTRY_MULTIDEF to probe).         }

type
  TBag = class
  private
    FByIx: array[0..3] of Integer;
    function GetIx(I: Integer): Integer;
    function GetName(const S: string): Integer;
  public
    property Items[I: Integer]: Integer read GetIx; default;
    property Items[const S: string]: Integer read GetName; default;
  end;

function TBag.GetIx(I: Integer): Integer;
begin
  Result := FByIx[I and 3];
end;

function TBag.GetName(const S: string): Integer;
begin
  Result := 1000 + Length(S);
end;

procedure RunMultiDefaultForms;
var
  B: TBag;
  K: Integer;
begin
  B := TBag.Create;
  try
    for K := 0 to 3 do
      B.FByIx[K] := K * 11;
    Check(B[3] = 33, 'fty-mdef-int');
    Check(B[Integer(OpaqueI(2))] = 22, 'fty-mdef-int-opaque');
    Check(B['abc'] = 1003, 'fty-mdef-str');
    Check(B[''] = 1000, 'fty-mdef-str-empty');
    Mix(UInt64(UInt32(B[1] + B['zz'])));
  finally
    B.Free;
  end;
end;
{$endif}

{ ---------------------------------------------------------------- }
{ ROUND mem: memory/layout/lifetime forms verified on dcc64 O+/O-.  }
{ Discarded as UB there: Move over managed fields, FillChar on live }
{ managed data, reading padding, string-header offsets (layout      }
{ differs per compiler), ReallocMem on managed fields.              }
{ ---------------------------------------------------------------- }

{ 49. Packed vs aligned record layout: field offsets pinned via     }
{ byte pointers (documented alignment rules, no padding reads).     }

type
  TMLifeObj = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TMLifeObj.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TMLifeObj.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

type
  TLifeRec = record
    S: AnsiString;
    D: array of Integer;
    Intf: IInterface;
    Tag: Integer;
  end;

  TAligned = record
    A: Byte;
    B: Word;
    C: Int64;
    D: Byte;
    E: Integer;
  end;

  TPackedA = packed record
    A: Byte;
    B: Word;
    C: Int64;
    D: Byte;
    E: Integer;
  end;

procedure RunPackedLayoutForms;
var
  R: TAligned;
  PR: TPackedA;
  P: PByte;
begin
  Check(SizeOf(TAligned) = 24, 'mem-align-unpacked-size');
  Check(SizeOf(TPackedA) = 16, 'mem-align-packed-size');
  Check(SizeOf(TAligned) - SizeOf(TPackedA) = 8, 'mem-align-pad-delta');

  R.A := $AA;
  R.B := $BBCC;
  R.C := Int64($DDDDDDDDEEEEEEEE);
  R.D := $FF;
  R.E := Integer($11223344);
  P := PByte(@R);
  Check(P[0] = $AA, 'mem-align-a-at-0');
  Check(PWord(@P[2])^ = $BBCC, 'mem-align-b-at-2');
  Check(PInt64(@P[8])^ = Int64($DDDDDDDDEEEEEEEE), 'mem-align-c-at-8');
  Check(P[16] = $FF, 'mem-align-d-at-16');
  Check(PInteger(@P[20])^ = Integer($11223344), 'mem-align-e-at-20');

  PR.A := $AA;
  PR.B := $BBCC;
  PR.C := Int64($DDDDDDDDEEEEEEEE);
  PR.D := $FF;
  PR.E := Integer($11223344);
  P := PByte(@PR);
  Check(P[0] = $AA, 'mem-align-pk-a-at-0');
  Check(PWord(@P[1])^ = $BBCC, 'mem-align-pk-b-at-1');
  Check(PInt64(@P[3])^ = Int64($DDDDDDDDEEEEEEEE), 'mem-align-pk-c-at-3');
  Check(P[11] = $FF, 'mem-align-pk-d-at-11');
  Check(PInteger(@P[12])^ = Integer($11223344), 'mem-align-pk-e-at-12');

  Mix(UInt64(SizeOf(TAligned)) * 100 + UInt64(SizeOf(TPackedA)));
end;

{ ---------------------------------------------------------------- }
{ 50. Initialize/Finalize intrinsics on GetMem'd raw memory — the   }
{ low-level path New/Dispose use internally. Finalize releases AND  }
{ zeroes managed fields; unmanaged fields survive.                  }

procedure RunInitFinForms;
var
  P: ^TLifeRec;
begin
  TMLifeObj.Alive := 0;
  GetMem(P, SizeOf(TLifeRec));
  Initialize(P^);
  Check(P^.S = '', 'mem-initfin-str-empty');
  Check(P^.D = nil, 'mem-initfin-dyn-nil');
  Check(P^.Intf = nil, 'mem-initfin-intf-nil');

  P^.S := AnsiString('lifecycle');
  SetLength(P^.D, 3);
  P^.D[0] := 42;
  P^.D[1] := 43;
  P^.D[2] := 44;
  P^.Intf := TMLifeObj.Create;
  P^.Tag := 99;
  Check(P^.S = 'lifecycle', 'mem-initfin-str-assigned');
  Check(P^.D[2] = 44, 'mem-initfin-dyn-assigned');
  Check(TMLifeObj.Alive = 1, 'mem-initfin-obj-alive');

  Finalize(P^);
  Check(TMLifeObj.Alive = 0, 'mem-initfin-obj-released');
  Check(P^.S = '', 'mem-initfin-str-after-fin');
  Check(P^.D = nil, 'mem-initfin-dyn-after-fin');
  Check(P^.Tag = 99, 'mem-initfin-tag-survives');

  FreeMem(P);
  Mix(UInt64(UInt32(TMLifeObj.Alive + 99)));
end;

{ ---------------------------------------------------------------- }
{ 51. AllocMem WITHOUT Initialize: zero-fill IS a valid empty state }
{ for every managed type (nil = empty string/array/interface), so   }
{ the documented Initialize step can be skipped entirely.           }

procedure RunAllocZeroForms;
var
  P: ^TLifeRec;
begin
  TMLifeObj.Alive := 0;
  P := AllocMem(SizeOf(TLifeRec));
  Check(P^.S = '', 'mem-alloczero-str-empty');
  Check(P^.D = nil, 'mem-alloczero-dyn-nil');
  Check(P^.Intf = nil, 'mem-alloczero-intf-nil');
  Check(P^.Tag = 0, 'mem-alloczero-tag-zero');

  P^.S := AnsiString('alloc');
  SetLength(P^.D, 2);
  P^.D[0] := 77;
  P^.Intf := TMLifeObj.Create;
  Check(P^.S = 'alloc', 'mem-alloczero-str-used');
  Check(P^.D[0] = 77, 'mem-alloczero-dyn-used');
  Check(TMLifeObj.Alive = 1, 'mem-alloczero-obj-alive');

  Finalize(P^);
  Check(TMLifeObj.Alive = 0, 'mem-alloczero-obj-released');
  FreeMem(P);
  Mix(UInt64(UInt32(TMLifeObj.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 52. Set storage sizes at the 8/16/32 element boundaries plus the  }
{ boundary bits themselves. FPC may round differently — expected    }
{ seam candidates for the known-failures table.                     }

procedure RunSetBoundForms;
type
  TSet7 = set of 0..7;
  TSet8 = set of 0..8;
  TSet15 = set of 0..15;
  TSet16 = set of 0..16;
  TSet31 = set of 0..31;
  TSet32 = set of 0..32;
  TSet63 = set of 0..63;
  TSetByte = set of Byte;
var
  S8: TSet8;
  S16: TSet16;
  S32: TSet32;
begin
  Check(SizeOf(TSet7) = 1, 'mem-setbound-size-7');
  Check(SizeOf(TSet8) = 2, 'mem-setbound-size-8');
  Check(SizeOf(TSet15) = 2, 'mem-setbound-size-15');
  Check(SizeOf(TSet16) = 4, 'mem-setbound-size-16');
  Check(SizeOf(TSet31) = 4, 'mem-setbound-size-31');
  Check(SizeOf(TSet32) = 8, 'mem-setbound-size-32');
  Check(SizeOf(TSet63) = 8, 'mem-setbound-size-63');
  Check(SizeOf(TSetByte) = 32, 'mem-setbound-size-byte');

  S8 := [Integer(OpaqueI(8))];
  Check(8 in S8, 'mem-setbound-bit8-in');
  Check(not (7 in S8), 'mem-setbound-bit7-notin');
  Check(not (0 in S8), 'mem-setbound-bit0-notin-8');

  S16 := [Integer(OpaqueI(16))];
  Check(16 in S16, 'mem-setbound-bit16-in');
  Check(not (15 in S16), 'mem-setbound-bit15-notin');

  S32 := [0, Integer(OpaqueI(31)), Integer(OpaqueI(32))];
  Check(32 in S32, 'mem-setbound-bit32-in');
  Check(31 in S32, 'mem-setbound-bit31-in');
  Check(0 in S32, 'mem-setbound-bit0-in-32');
  Check(not (16 in S32), 'mem-setbound-bit16-notin-32');

  Mix(UInt64(SizeOf(TSet7)) + UInt64(SizeOf(TSet8)) +
    UInt64(SizeOf(TSet16)) + UInt64(SizeOf(TSet32)));
end;

{ ---------------------------------------------------------------- }
{ 53. Empty AnsiString IS the nil pointer — every road to empty     }
{ (literal, clear, concat of empties, SetLength 0, zero-count Copy) }
{ ends at nil, never at an allocated zero-length buffer.            }

procedure RunNilStrForms;
var
  S, T: AnsiString;
begin
  S := '';
  Check(Pointer(S) = nil, 'mem-nilstr-empty-literal');
  Check(Length(S) = 0, 'mem-nilstr-empty-length');

  S := AnsiString('hello');
  Check(Pointer(S) <> nil, 'mem-nilstr-nonempty');
  S := '';
  Check(Pointer(S) = nil, 'mem-nilstr-cleared');

  T := '';
  Check(Pointer(S) = Pointer(T), 'mem-nilstr-both-nil-eq');

  S := '' + '';
  Check(Pointer(S) = nil, 'mem-nilstr-concat-empties');

  S := AnsiString('temp');
  SetLength(S, 0);
  Check(Pointer(S) = nil, 'mem-nilstr-setlen-zero');

  T := Copy(AnsiString('abc'), 1, 0);
  Check(Pointer(T) = nil, 'mem-nilstr-copy-zero');

  T := Copy(S, 1, 100);
  Check(Pointer(T) = nil, 'mem-nilstr-copy-empty-source');

  Mix(UInt64(Length(S)));
end;

{ ---------------------------------------------------------------- }
{ 54. A managed LOCAL initializes once at proc entry and persists   }
{ across loop iterations — the previous iteration's value is still  }
{ there at the top of the next one.                                 }

procedure RunLoopPersistForms;
var
  S: AnsiString;
  K: Integer;
  Trail: Int64;
begin
  Trail := 0;
  for K := 0 to 3 do
  begin
    if K = 0 then
      Check(S = '', 'mem-looppersist-init-empty')
    else
      Check(S = AnsiString('v') + AnsiChar(Ord('0') + K - 1),
        'mem-looppersist-prev-survives');
    S := AnsiString('v') + AnsiChar(Ord('0') + K);
    Trail := Trail * 10 + K;
  end;
  Check(Trail = 123, 'mem-looppersist-trail');
  Check(S = 'v3', 'mem-looppersist-final');

  Mix(UInt64(Trail));
end;

{ ---------------------------------------------------------------- }
{ 55. Insert/Delete intrinsics on a dyn array of STRINGS: managed   }
{ elements shift without leaking or double-releasing.               }

procedure RunMgdShiftForms;
var
  A: array of AnsiString;
begin
  SetLength(A, 4);
  A[0] := AnsiString('zero');
  A[1] := AnsiString('one');
  A[2] := AnsiString('two');
  A[3] := AnsiString('three');

  Insert(AnsiString('INS'), A, 2);
  Check(Length(A) = 5, 'mem-mgdshift-insert-len');
  Check(A[0] = 'zero', 'mem-mgdshift-insert-0');
  Check(A[1] = 'one', 'mem-mgdshift-insert-1');
  Check(A[2] = 'INS', 'mem-mgdshift-insert-2');
  Check(A[3] = 'two', 'mem-mgdshift-insert-3');
  Check(A[4] = 'three', 'mem-mgdshift-insert-4');

  Delete(A, 1, 2);
  Check(Length(A) = 3, 'mem-mgdshift-delete-len');
  Check(A[0] = 'zero', 'mem-mgdshift-delete-0');
  Check(A[1] = 'two', 'mem-mgdshift-delete-1');
  Check(A[2] = 'three', 'mem-mgdshift-delete-2');

  Insert(AnsiString('HEAD'), A, 0);
  Check(A[0] = 'HEAD', 'mem-mgdshift-head-insert');
  Check(A[3] = 'three', 'mem-mgdshift-head-tail');

  Delete(A, Length(A) - 1, 1);
  Check(Length(A) = 3, 'mem-mgdshift-tail-delete');
  Check(A[2] = 'two', 'mem-mgdshift-tail-last');

  Mix(UInt64(UInt32(Length(A))));
end;

{ ---------------------------------------------------------------- }
{ 56. Deep finalization chain: dyn array of records holding strings,}
{ inner dyn arrays and interfaces — SetLength shrink must walk the  }
{ whole RTTI tree; a wrong descriptor at any level leaks silently.  }

type
  TMemInner = record
    S: AnsiString;
    D: array of Integer;
  end;
  TMemMiddle = record
    Items: array of TMemInner;
    Intf: IInterface;
    Tag: Integer;
  end;

procedure RunDeepFinForms;
var
  Outer: array of TMemMiddle;
  K, J: Integer;
begin
  TMLifeObj.Alive := 0;
  SetLength(Outer, 3);
  for K := 0 to 2 do
  begin
    SetLength(Outer[K].Items, 2);
    for J := 0 to 1 do
    begin
      Outer[K].Items[J].S := AnsiString('s') +
        AnsiChar(Ord('0') + K) + AnsiChar(Ord('0') + J);
      SetLength(Outer[K].Items[J].D, 2);
      Outer[K].Items[J].D[0] := K * 10 + J;
      Outer[K].Items[J].D[1] := K * 100 + J;
    end;
    Outer[K].Intf := TMLifeObj.Create;
    Outer[K].Tag := K;
  end;

  Check(TMLifeObj.Alive = 3, 'mem-deepfin-alive-3');
  Check(Outer[1].Items[0].S = 's10', 'mem-deepfin-inner-str');
  Check(Outer[2].Items[1].D[1] = 201, 'mem-deepfin-inner-dyn');

  SetLength(Outer, 1);
  Check(TMLifeObj.Alive = 1, 'mem-deepfin-shrink-alive');
  Check(Outer[0].Items[0].S = 's00', 'mem-deepfin-survivor-str');
  Check(Outer[0].Tag = 0, 'mem-deepfin-survivor-tag');

  Outer := nil;
  Check(TMLifeObj.Alive = 0, 'mem-deepfin-all-released');

  Mix(UInt64(UInt32(TMLifeObj.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 57. SetLength shrink finalizes exactly the dropped interface      }
{ elements, keeps the survivors alive.                              }

procedure RunShrinkFinForms;
var
  A: array of IInterface;
  K: Integer;
begin
  TMLifeObj.Alive := 0;
  SetLength(A, 5);
  for K := 0 to 4 do
    A[K] := TMLifeObj.Create;
  Check(TMLifeObj.Alive = 5, 'mem-shrinkfin-5-alive');

  SetLength(A, 3);
  Check(TMLifeObj.Alive = 3, 'mem-shrinkfin-3-after-shrink');
  Check(Length(A) = 3, 'mem-shrinkfin-len-3');

  SetLength(A, 0);
  Check(TMLifeObj.Alive = 0, 'mem-shrinkfin-zero-released');

  SetLength(A, 2);
  A[0] := TMLifeObj.Create;
  A[1] := TMLifeObj.Create;
  Check(TMLifeObj.Alive = 2, 'mem-shrinkfin-2-alive');
  A := nil;
  Check(TMLifeObj.Alive = 0, 'mem-shrinkfin-nil-released');

  Mix(UInt64(UInt32(TMLifeObj.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 58. String lifecycle through pointers: assignment shares,         }
{ UniqueString splits shared / no-ops on unique, indexed write is   }
{ an implicit COW split. Pointer values only compared, never folded.}

procedure RunStrLifeForms;
var
  S1, S2, S3: AnsiString;
  P: Pointer;
begin
  S1 := AnsiString('share');
  UniqueString(S1);
  S2 := AnsiString('share');
  UniqueString(S2);
  Check(Pointer(S1) <> Pointer(S2), 'mem-strlife-heap-distinct');
  Check(S1 = S2, 'mem-strlife-heap-value-eq');

  S3 := S1;
  Check(Pointer(S3) = Pointer(S1), 'mem-strlife-assign-shares');

  UniqueString(S3);
  Check(Pointer(S3) <> Pointer(S1), 'mem-strlife-unique-shared');
  Check(S3 = S1, 'mem-strlife-unique-value-eq');

  P := Pointer(S3);
  UniqueString(S3);
  Check(Pointer(S3) = P, 'mem-strlife-unique-noop');

  S3 := S1;
  S3[1] := 'X';
  Check(S1 = 'share', 'mem-strlife-cow-intact');
  Check(S3 = 'Xhare', 'mem-strlife-cow-mutated');
  Check(Pointer(S3) <> Pointer(S1), 'mem-strlife-cow-detach');

  Mix(UInt64(UInt32(Length(S1))));
end;

{ ---------------------------------------------------------------- }
{ 59. Finalize with an explicit COUNT walks exactly that many array }
{ elements — a range finalizer over a static array slice.           }

procedure RunRangeFinForms;
var
  Arr: array[0..3] of TLifeRec;
  K: Integer;
begin
  TMLifeObj.Alive := 0;
  for K := 0 to 3 do
  begin
    Arr[K].S := AnsiString('r') + AnsiChar(Ord('0') + K);
    SetLength(Arr[K].D, 1);
    Arr[K].D[0] := K * 10;
    Arr[K].Intf := TMLifeObj.Create;
    Arr[K].Tag := K;
  end;
  Check(TMLifeObj.Alive = 4, 'mem-rangefin-4-alive');

  Finalize(Arr[0], 2);
  Check(TMLifeObj.Alive = 2, 'mem-rangefin-2-after');
  Check(Arr[0].S = '', 'mem-rangefin-0-str-cleared');
  Check(Arr[0].D = nil, 'mem-rangefin-0-dyn-cleared');
  Check(Arr[1].S = '', 'mem-rangefin-1-cleared');
  Check(Arr[2].S = 'r2', 'mem-rangefin-2-intact');
  Check(Arr[3].S = 'r3', 'mem-rangefin-3-intact');
  Check(Arr[0].Tag = 0, 'mem-rangefin-tag-survives');

  Finalize(Arr[2], 2);
  Check(TMLifeObj.Alive = 0, 'mem-rangefin-all-released');

  Mix(UInt64(UInt32(TMLifeObj.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 60. Concat of managed dyn arrays: element strings share buffers   }
{ with the sources until COW splits them; the concat result is      }
{ independent of later source mutations.                            }

procedure RunMgdConcatForms;
var
  A, B, C, D: array of AnsiString;
begin
  SetLength(A, 2);
  A[0] := AnsiString('alpha');
  A[1] := AnsiString('beta');
  SetLength(B, 2);
  B[0] := AnsiString('gamma');
  B[1] := AnsiString('delta');

  C := Concat(A, B);
  Check(Length(C) = 4, 'mem-mgdconcat-len');
  Check(C[0] = 'alpha', 'mem-mgdconcat-0');
  Check(C[1] = 'beta', 'mem-mgdconcat-1');
  Check(C[2] = 'gamma', 'mem-mgdconcat-2');
  Check(C[3] = 'delta', 'mem-mgdconcat-3');

  C[0] := C[0] + 'x';
  Check(A[0] = 'alpha', 'mem-mgdconcat-cow-intact');
  Check(C[0] = 'alphax', 'mem-mgdconcat-cow-mutated');

  A[1] := AnsiString('BETA');
  Check(C[1] = 'beta', 'mem-mgdconcat-orig-independent');

  SetLength(D, 0);
  D := Concat(A, D);
  Check(Length(D) = Length(A), 'mem-mgdconcat-empty-len');
  Check(D[0] = A[0], 'mem-mgdconcat-empty-content');

  Mix(UInt64(UInt32(Length(C))));
end;

{ ---------------------------------------------------------------- }
{ 61. Default(T) on a deeply nested record with anonymous inner     }
{ records: releases the interface, clears every managed field at    }
{ every level, zeroes the plain ones.                               }

type
  TDeepRec = record
    S: AnsiString;
    Inner: record
      D: array of Integer;
      Intf: IInterface;
      Sub: record
        S2: AnsiString;
        Tag: Integer;
      end;
    end;
    N: Integer;
  end;

procedure RunDefaultDeepForms;
var
  R: TDeepRec;
begin
  TMLifeObj.Alive := 0;

  R.S := AnsiString('outer');
  SetLength(R.Inner.D, 3);
  R.Inner.D[0] := 42;
  R.Inner.Intf := TMLifeObj.Create;
  R.Inner.Sub.S2 := AnsiString('deep');
  R.Inner.Sub.Tag := 99;
  R.N := 7;

  Check(TMLifeObj.Alive = 1, 'mem-defaultdeep-alive');
  Check(R.Inner.Sub.S2 = 'deep', 'mem-defaultdeep-before');

  R := Default(TDeepRec);

  Check(TMLifeObj.Alive = 0, 'mem-defaultdeep-intf-released');
  Check(R.S = '', 'mem-defaultdeep-str-empty');
  Check(R.Inner.D = nil, 'mem-defaultdeep-dyn-nil');
  Check(R.Inner.Intf = nil, 'mem-defaultdeep-intf-nil');
  Check(R.Inner.Sub.S2 = '', 'mem-defaultdeep-deep-str-empty');
  Check(R.Inner.Sub.Tag = 0, 'mem-defaultdeep-deep-tag-zero');
  Check(R.N = 0, 'mem-defaultdeep-n-zero');

  Mix(UInt64(UInt32(TMLifeObj.Alive)));
end;

{ ---------------------------------------------------------------- }
{ 61b. Static arrays of records with management operators have a    }
{ distinct Default(T) assignment contract: the fresh Initialize     }
{ values are transferred as-is, without the element Assign operator.}
{ Exercise direct, field, indexed-single-evaluation and generic     }
{ spellings of the same semantic class.                              }

type
  TOmniDefaultCell = record
    Value: Integer;
    class operator Initialize(out Dest: TOmniDefaultCell);
    class operator Finalize(var Dest: TOmniDefaultCell);
    class operator Assign(var Dest: TOmniDefaultCell;
      const [ref] Src: TOmniDefaultCell);
  end;
  TOmniDefaultPair = array[0..1] of TOmniDefaultCell;
  TOmniDefaultAssignOnly = record
    Value: Integer;
    class operator Assign(var Dest: TOmniDefaultAssignOnly;
      const [ref] Src: TOmniDefaultAssignOnly);
  end;
  TOmniDefaultAssignOnlyPair = array[0..1] of TOmniDefaultAssignOnly;
  TOmniDefaultMatrix = array[0..1] of TOmniDefaultPair;
  TOmniDefaultHolder = record
    Pair: TOmniDefaultPair;
  end;
  TOmniDefaultReset = class sealed
  public
    class procedure Reset<T>(var Dest: T); static;
  end;

var
  OmniDefaultPickCalls: Integer;

class operator TOmniDefaultCell.Initialize(out Dest: TOmniDefaultCell);
begin
  Dest.Value := 100;
end;

class operator TOmniDefaultCell.Finalize(var Dest: TOmniDefaultCell);
begin
  Dest.Value := -1;
end;

class operator TOmniDefaultCell.Assign(var Dest: TOmniDefaultCell;
  const [ref] Src: TOmniDefaultCell);
begin
  Dest.Value := Src.Value + 1;
end;

class operator TOmniDefaultAssignOnly.Assign(var Dest: TOmniDefaultAssignOnly;
  const [ref] Src: TOmniDefaultAssignOnly);
begin
  Dest.Value := Src.Value + 1;
end;

class procedure TOmniDefaultReset.Reset<T>(var Dest: T);
begin
  Dest := Default(T);
end;

function PickOmniDefaultRow: Integer;
begin
  Result := OmniDefaultPickCalls;
  Inc(OmniDefaultPickCalls);
end;

procedure RunDefaultOperatorArrayForms;
var
  Pair: TOmniDefaultPair;
  AssignOnlyPair: TOmniDefaultAssignOnlyPair;
  Matrix: TOmniDefaultMatrix;
  Holder: TOmniDefaultHolder;
begin
  Pair[0].Value := 10;
  Pair[1].Value := 11;
  Pair := Default(TOmniDefaultPair);
  Check((Pair[0].Value = 100) and (Pair[1].Value = 100),
    'mem-defaultop-direct-fresh-transfer');

  AssignOnlyPair[0].Value := 12;
  AssignOnlyPair[1].Value := 13;
  AssignOnlyPair := Default(TOmniDefaultAssignOnlyPair);
  Check((AssignOnlyPair[0].Value = 0) and (AssignOnlyPair[1].Value = 0),
    'mem-defaultop-assign-only-fresh-transfer');

  Holder.Pair[0].Value := 20;
  Holder.Pair[1].Value := 21;
  Holder.Pair := Default(TOmniDefaultPair);
  Check((Holder.Pair[0].Value = 100) and
    (Holder.Pair[1].Value = 100), 'mem-defaultop-field-fresh-transfer');

  Matrix[0][0].Value := 30;
  Matrix[0][1].Value := 31;
  Matrix[1][0].Value := 40;
  Matrix[1][1].Value := 41;
  OmniDefaultPickCalls := 0;
  Matrix[PickOmniDefaultRow] := Default(TOmniDefaultPair);
  Check(OmniDefaultPickCalls = 1, 'mem-defaultop-index-single-eval');
  Check((Matrix[0][0].Value = 100) and (Matrix[0][1].Value = 100),
    'mem-defaultop-index-fresh-transfer');
  Check((Matrix[1][0].Value = 40) and (Matrix[1][1].Value = 41),
    'mem-defaultop-index-neighbour-intact');

  Pair[0].Value := 50;
  Pair[1].Value := 51;
  TOmniDefaultReset.Reset<TOmniDefaultPair>(Pair);
  Check((Pair[0].Value = 100) and (Pair[1].Value = 100),
    'mem-defaultop-generic-fresh-transfer');
  Mix(UInt64(UInt32(Pair[0].Value * 1000 + Pair[1].Value)));
end;

{ ---------------------------------------------------------------- }
{ ROUND zoo4: repository-mining pass 2 (mORMot2 RSA, fundamentals5 }
{ HugeInt, lgenerics TGOptional, QuickLib TFlexValue). Every shape  }
{ is wrapped in LOOPS, RECURSION or NESTED CALLS, aiming at LICM,   }
{ strength reduction and induction-variable rewrites.               }
{ ---------------------------------------------------------------- }

{ 62. Rare class operators nobody ships: Inc/Dec dispatch through   }
{ overloads (an induction variable stepped BY an operator), div/mod }
{ and shl/shr overloads chained in loops, and the resolver pin that }
{ xor on a record picks BitwiseXor. Oracle: plain-field model.      }

type
  TOdo = record
    V: Integer;
    class operator Inc(const A: TOdo): TOdo;
    class operator Dec(const A: TOdo): TOdo;
    class operator IntDivide(const A: TOdo; B: Integer): TOdo;
    class operator Modulus(const A: TOdo; B: Integer): Integer;
    class operator LeftShift(const A: TOdo; N: Integer): TOdo;
    class operator RightShift(const A: TOdo; N: Integer): TOdo;
    class operator BitwiseXor(const A, B: TOdo): TOdo;
  end;

class operator TOdo.Inc(const A: TOdo): TOdo;
begin
  Result.V := A.V + 10;
end;

class operator TOdo.Dec(const A: TOdo): TOdo;
begin
  Result.V := A.V - 10;
end;

class operator TOdo.IntDivide(const A: TOdo; B: Integer): TOdo;
begin
  Result.V := A.V div B + 7;
end;

class operator TOdo.Modulus(const A: TOdo; B: Integer): Integer;
begin
  Result := A.V mod B + 500;
end;

class operator TOdo.LeftShift(const A: TOdo; N: Integer): TOdo;
begin
  Result.V := A.V shl N or 1;
end;

class operator TOdo.RightShift(const A: TOdo; N: Integer): TOdo;
begin
  Result.V := A.V shr N or 2;
end;

class operator TOdo.BitwiseXor(const A, B: TOdo): TOdo;
begin
  Result.V := (A.V xor B.V) + 40000;
end;

procedure RunRareOperatorLoopForms;
var
  X, Y: TOdo;
  K, MV: Integer;
begin
  { Inc as the loop STEP: 12 operator-driven increments }
  X.V := Integer(OpaqueI(5));
  MV := X.V;
  for K := 1 to 12 do
  begin
    Inc(X);                            { dispatches to the overload }
    MV := MV + 10;
  end;
  Check(X.V = MV, 'zoo4-rareop-inc-loop');
  for K := 1 to 5 do
    Dec(X);
  Check(X.V = MV - 50, 'zoo4-rareop-dec-loop');

  { div/mod overloads chained inside a loop }
  X.V := Integer(OpaqueI(1000));
  MV := 0;
  for K := 2 to 5 do
  begin
    X := X div K;                      { IntDivide overload }
    MV := MV + X mod 7;                { Modulus overload }
  end;
  { model: 1000->507->176->51->17; mod7+500 each: 503+501+502+503 }
  Check(X.V = 17, 'zoo4-rareop-intdiv-chain');
  Check(MV = 2009, 'zoo4-rareop-mod-sum');

  { shift ladder through overloads }
  X.V := 1;
  for K := 1 to 6 do
    X := X shl 1;                      { (V shl 1) or 1 six times }
  Check(X.V = 127, 'zoo4-rareop-shl-ladder');
  X := X shr 3;
  Check(X.V = (127 shr 3) or 2, 'zoo4-rareop-shr');

  { xor on records resolves to the BITWISE operator; X.V here is
    (127 shr 3) or 2 = 15, so 15 xor 15 = 0 }
  Y.V := Integer(OpaqueI(15));
  X := X xor Y;
  Check(X.V = 40000, 'zoo4-rareop-xor-bitwise-wins');

  Mix(UInt64(UInt32(X.V + MV)));
end;

{$ifdef HAS_RAREX}
{ Trunc/Round/Positive overloads — gated: unverified on the FPC     }
{ side (-dTRY_RAREX to probe there).                                }

type
  TOdoX = record
    V: Integer;
    class operator Trunc(const A: TOdoX): Integer;
    class operator Round(const A: TOdoX): Integer;
    class operator Positive(const A: TOdoX): TOdoX;
  end;

class operator TOdoX.Trunc(const A: TOdoX): Integer;
begin
  Result := A.V * 2;
end;

class operator TOdoX.Round(const A: TOdoX): Integer;
begin
  Result := A.V * 3;
end;

class operator TOdoX.Positive(const A: TOdoX): TOdoX;
begin
  Result.V := A.V + 1000;
end;

procedure RunRareXOperatorForms;
var
  X: TOdoX;
  K, S: Integer;
begin
  X.V := Integer(OpaqueI(4));
  S := 0;
  for K := 1 to 3 do
  begin
    X := +X;                           { Positive overload, looped }
    S := S + Trunc(X) + Round(X);
  end;
  { V: 1004, 2004, 3004; per pass 2V+3V = 5V }
  Check(X.V = 3004, 'zoo4-rarex-positive-loop');
  Check(S = 5 * (1004 + 2004 + 3004), 'zoo4-rarex-trunc-round-sum');
  Mix(UInt64(UInt32(S)));
end;
{$endif}

{ ---------------------------------------------------------------- }
{ 63. Multi-word big-number arithmetic (mORMot RSA / fundamentals   }
{ HugeInt shape, pure pascal): 256-bit value as 8x UInt32, carry    }
{ rippling through word loops. Oracles: Int64 reference on small    }
{ values, X+Y-Y=X self-inverse, and multiply-by-small vs repeated   }
{ addition (structurally different algorithm).                      }

type
  TBig256 = array[0..7] of UInt32;

procedure BigFromU64(var R: TBig256; V: UInt64);
var
  K: Integer;
begin
  for K := 0 to 7 do
    R[K] := 0;
  R[0] := UInt32(V);
  R[1] := UInt32(V shr 32);
end;

function BigToU64(const A: TBig256): UInt64;
begin
  Result := UInt64(A[0]) or (UInt64(A[1]) shl 32);
end;

procedure BigAdd(var R: TBig256; const A, B: TBig256);
var
  K: Integer;
  Carry, S: UInt64;
begin
  Carry := 0;
  for K := 0 to 7 do
  begin
    S := UInt64(A[K]) + UInt64(B[K]) + Carry;
    R[K] := UInt32(S);
    Carry := S shr 32;
  end;
end;

procedure BigSub(var R: TBig256; const A, B: TBig256);
var
  K: Integer;
  Borrow, S: UInt64;
begin
  Borrow := 0;
  for K := 0 to 7 do
  begin
    S := UInt64(A[K]) - UInt64(B[K]) - Borrow;
    R[K] := UInt32(S);
    Borrow := (S shr 32) and 1;
  end;
end;

procedure BigMulWord(var R: TBig256; const A: TBig256; W: UInt32);
var
  K: Integer;
  Carry, P: UInt64;
begin
  Carry := 0;
  for K := 0 to 7 do
  begin
    P := UInt64(A[K]) * W + Carry;
    R[K] := UInt32(P);
    Carry := P shr 32;
  end;
end;

function BigFold(const A: TBig256): UInt64;
var
  K: Integer;
begin
  Result := FNVOfs;
  for K := 0 to 7 do
    Result := (Result xor A[K]) * FNVPrm;
end;

procedure RunBigCarryForms;
var
  A, B, C, D: TBig256;
  K: Integer;
  RefA, RefB: UInt64;
begin
  { small values: the 256-bit path must agree with plain UInt64 }
  RefA := OpaqueU($1234567890ABCDEF);
  RefB := OpaqueU($0FEDCBA987654321);
  BigFromU64(A, RefA);
  BigFromU64(B, RefB);
  BigAdd(C, A, B);
  Check(BigToU64(C) = RefA + RefB, 'zoo4-big-add-small-ref');
  BigSub(D, C, B);
  Check(BigFold(D) = BigFold(A), 'zoo4-big-add-sub-inverse');

  { carry ripple across every word: all-FF + 1 }
  for K := 0 to 7 do
    A[K] := $FFFFFFFF;
  BigFromU64(B, 1);
  BigAdd(C, A, B);
  for K := 0 to 7 do
    Check(C[K] = 0, 'zoo4-big-ripple-zero');

  { multiply by a small word vs repeated addition (different algo) }
  BigFromU64(A, OpaqueU($DEADBEEFCAFE));
  BigMulWord(B, A, 37);
  BigFromU64(C, 0);
  for K := 1 to 37 do
  begin
    BigAdd(D, C, A);
    C := D;
  end;
  Check(BigFold(B) = BigFold(C), 'zoo4-big-mul-vs-addloop');

  { chain of mul-by-word: factorial 12 built in 256 bits }
  BigFromU64(A, 1);
  for K := 2 to 12 do
  begin
    BigMulWord(B, A, UInt32(K));
    A := B;
  end;
  Check(BigToU64(A) = 479001600, 'zoo4-big-fact12');

  Mix(BigFold(A));
end;

{ ---------------------------------------------------------------- }
{ 64. Micro-VM: the same bytecode run by a case-dispatch loop AND   }
{ by an if/else-chain twin (two different lowerings of the same     }
{ machine). Program: factorial 10 with a backward jump. Both        }
{ interpreters must agree with each other and the hand pin.         }

const
  VmProg: array[0..13] of Integer = (
    1, 0, 1,        { LOADI R0, 1 }
    1, 1, 10,       { LOADI R1, 10 }
    2, 0, 1,        { MUL R0, R1   <- loop head at IP 6 }
    3, 1,           { DEC R1 }
    4, 1, 6);       { JNZ R1, 6 }

function VmRunCase(out Steps: Integer): Integer;
var
  R: array[0..1] of Integer;
  IP: Integer;
begin
  R[0] := 0;
  R[1] := 0;
  IP := 0;
  Steps := 0;
  while IP <= High(VmProg) do
  begin
    Inc(Steps);
    case VmProg[IP] of
      1:
        begin
          R[VmProg[IP + 1]] := VmProg[IP + 2];
          Inc(IP, 3);
        end;
      2:
        begin
          R[VmProg[IP + 1]] := R[VmProg[IP + 1]] * R[VmProg[IP + 2]];
          Inc(IP, 3);
        end;
      3:
        begin
          R[VmProg[IP + 1]] := R[VmProg[IP + 1]] - 1;
          Inc(IP, 2);
        end;
      4:
        if R[VmProg[IP + 1]] <> 0 then
          IP := VmProg[IP + 2]
        else
          Inc(IP, 3);
    end;
  end;
  Result := R[0];
end;

function VmRunIfChain(out Steps: Integer): Integer;
var
  R: array[0..1] of Integer;
  IP, Op: Integer;
begin
  R[0] := 0;
  R[1] := 0;
  IP := 0;
  Steps := 0;
  while IP <= High(VmProg) do
  begin
    Inc(Steps);
    Op := VmProg[IP];
    if Op = 1 then
    begin
      R[VmProg[IP + 1]] := VmProg[IP + 2];
      Inc(IP, 3);
    end else if Op = 2 then
    begin
      R[VmProg[IP + 1]] := R[VmProg[IP + 1]] * R[VmProg[IP + 2]];
      Inc(IP, 3);
    end else if Op = 3 then
    begin
      R[VmProg[IP + 1]] := R[VmProg[IP + 1]] - 1;
      Inc(IP, 2);
    end else if Op = 4 then
    begin
      if R[VmProg[IP + 1]] <> 0 then
        IP := VmProg[IP + 2]
      else
        Inc(IP, 3);
    end;
  end;
  Result := R[0];
end;

procedure RunVmLoopForms;
var
  V1, V2, S1, S2: Integer;
begin
  V1 := VmRunCase(S1);
  V2 := VmRunIfChain(S2);
  Check(V1 = V2, 'zoo4-vm-case-vs-ifchain');
  Check(V1 = 3628800, 'zoo4-vm-fact-pin');
  Check((S1 = S2) and (S1 = 32), 'zoo4-vm-steps');
  Mix(UInt64(UInt32(V1 + S1)));
end;

{ ---------------------------------------------------------------- }
{ 65. Managed churn under a loop: strings, dyn arrays and counted   }
{ interfaces created and dropped 200 times from a NESTED procedure, }
{ every 17th survivor retained. Refcount balance and survivor       }
{ content checked at the end.                                       }

procedure RunManagedChurnForms;
var
  SurvI: array of IInterface;
  SurvS: array of AnsiString;
  Kept: Integer;

  procedure ChurnOnce(K: Integer);
  var
    S: AnsiString;
    D: TIntDyn;
    I: IInterface;
  begin
    S := AnsiString('c') + AnsiChar(Ord('0') + K mod 10);
    SetLength(D, 3);
    D[2] := K;
    I := TMLifeObj.Create;
    if K mod 17 = 0 then
    begin
      SurvI[Kept] := I;
      SurvS[Kept] := S + AnsiString('!');
      Inc(Kept);
    end;
  end;                                 { S, D, I die here each pass }

var
  K: Integer;
begin
  TMLifeObj.Alive := 0;
  SetLength(SurvI, 16);
  SetLength(SurvS, 16);
  Kept := 0;
  for K := 0 to 199 do
    ChurnOnce(K);
  Check(Kept = 12, 'zoo4-churn-kept');
  Check(TMLifeObj.Alive = 12, 'zoo4-churn-alive');
  Check(SurvS[0] = 'c0!', 'zoo4-churn-content-first');
  Check(SurvS[11] = AnsiString('c') + AnsiChar(Ord('0') + 187 mod 10) + '!',
    'zoo4-churn-content-last');
  SurvI := nil;
  Check(TMLifeObj.Alive = 0, 'zoo4-churn-drained');
  Mix(UInt64(UInt32(Kept)));
end;

{ ---------------------------------------------------------------- }
{ 66. Recursion RETURNING managed values: a string built by 40      }
{ levels of Result := Build(N-1) + chunk, and a dyn array grown the }
{ same way. Oracle: iterative twins.                                }

function RecStr(N: Integer): AnsiString;
begin
  if N = 0 then
    Result := ''
  else
    Result := RecStr(N - 1) + AnsiChar(Ord('a') + (N - 1) mod 26);
end;

function RecDyn(N: Integer): TIntDyn;
begin
  if N = 0 then
    Result := nil
  else begin
    Result := RecDyn(N - 1);
    SetLength(Result, N);
    Result[N - 1] := N * 3;
  end;
end;

procedure RunRecManagedForms;
var
  S, M: AnsiString;
  D: TIntDyn;
  K: Integer;
  Ok: Boolean;
begin
  S := RecStr(40);
  M := '';
  for K := 0 to 39 do
    M := M + AnsiChar(Ord('a') + K mod 26);
  Check(S = M, 'zoo4-recstr-eq');
  Check(Length(S) = 40, 'zoo4-recstr-len');

  D := RecDyn(30);
  Ok := Length(D) = 30;
  for K := 0 to 29 do
    Ok := Ok and (D[K] = (K + 1) * 3);
  Check(Ok, 'zoo4-recdyn-eq');
  Mix(UInt64(Length(S) + Length(D)));
end;

{ ---------------------------------------------------------------- }
{ 67. An operator implemented BY RECURSION on itself: Peano-style   }
{ Add peels one unit per level (depth = operand value), and Mul is  }
{ a loop of operator +. Oracle: plain integer arithmetic.           }

type
  TPeano = record
    N: Integer;
    class operator Add(const A, B: TPeano): TPeano;
    function NextP: TPeano;
    function PrevP: TPeano;
  end;

function TPeano.NextP: TPeano;
begin
  Result.N := N + 1;
end;

function TPeano.PrevP: TPeano;
begin
  Result.N := N - 1;
end;

class operator TPeano.Add(const A, B: TPeano): TPeano;
begin
  if B.N = 0 then
    Result := A
  else
    Result := A.NextP + B.PrevP;       { operator + recursing into itself }
end;

procedure RunPeanoOperatorForms;
var
  A, B, C, Acc: TPeano;
  K: Integer;
begin
  A.N := Integer(OpaqueI(21));
  B.N := 17;
  C := A + B;
  Check(C.N = 38, 'zoo4-peano-add-recursive');

  { multiplication as a loop of recursive + }
  Acc.N := 0;
  for K := 1 to 6 do
    Acc := Acc + A;                    { 6 * 21, each + recurses 21 deep }
  Check(Acc.N = 126, 'zoo4-peano-mul-loop');
  Mix(UInt64(UInt32(C.N * 1000 + Acc.N)));
end;

{ ---------------------------------------------------------------- }
{ 68. Fixed-point distinct type (graphics32 TFixed shape) in loops: }
{ 16.16 multiply via Int64 intermediate, accumulated over the loop  }
{ index — strength-reduction bait. Oracle: the same math done on    }
{ raw Int64 without the distinct type.                              }

type
  TFixp = type Integer;                { 16.16 fixed point }

function FixpMul(A, B: TFixp): TFixp;
begin
  Result := TFixp((Int64(A) * Int64(B)) shr 16);
end;

function FixpOf(V: Integer): TFixp;
begin
  Result := TFixp(V shl 16);
end;

procedure RunFixpLoopForms;
var
  C, Acc: TFixp;
  K: Integer;
  RawC, RawAcc, Term: Int64;
begin
  C := TFixp(OpaqueI($18000));         { 1.5 in 16.16 }
  RawC := $18000;
  Acc := 0;
  RawAcc := 0;
  for K := 0 to 63 do
  begin
    Acc := Acc + FixpMul(FixpOf(K), C);
    Term := ((Int64(K) shl 16) * RawC) shr 16;
    RawAcc := RawAcc + Term;
  end;
  Check(Int64(Acc) = Int64(Integer(RawAcc)), 'zoo4-fixp-model-eq');
  { sum K=0..63 of K*1.5 = 3024.0 exactly -> $BD00000 }
  Check(Integer(Acc) = $BD00000, 'zoo4-fixp-sum-pin');
  Mix(UInt64(UInt32(Acc)));
end;

{ ---------------------------------------------------------------- }
{ 69. Nested-function call CHAINS over shared outer state: the same }
{ three one-liners composed in two different orders depending on    }
{ loop parity; every call mutates the enclosing frame through the   }
{ static link. Oracle: hand-lowered model with explicit steps.      }

procedure RunNestChainForms;
var
  State: Integer;
  Trail: UInt64;

  function HN(X: Integer): Integer;
  begin
    Trail := (Trail xor 1) * FNVPrm;
    Inc(State);
    Result := X + State;
  end;

  function GN(X: Integer): Integer;
  begin
    Trail := (Trail xor 2) * FNVPrm;
    Result := X * 2;
  end;

  function FN(X: Integer): Integer;
  begin
    Trail := (Trail xor 3) * FNVPrm;
    Result := X - 3;
  end;

var
  K, R, Sum: Integer;
  MState, MR, MSum: Integer;
  MTrail: UInt64;
begin
  State := 0;
  Trail := 0;
  Sum := 0;
  for K := 1 to 8 do
  begin
    if K and 1 = 0 then
      R := FN(GN(HN(K)))
    else
      R := HN(GN(FN(K)));
    Sum := Sum + R;
  end;

  { hand-lowered model, same order of effects }
  MState := 0;
  MTrail := 0;
  MSum := 0;
  for K := 1 to 8 do
  begin
    if K and 1 = 0 then
    begin
      MTrail := (MTrail xor 1) * FNVPrm;
      Inc(MState);
      MR := K + MState;
      MTrail := (MTrail xor 2) * FNVPrm;
      MR := MR * 2;
      MTrail := (MTrail xor 3) * FNVPrm;
      MR := MR - 3;
    end else begin
      MTrail := (MTrail xor 3) * FNVPrm;
      MR := K - 3;
      MTrail := (MTrail xor 2) * FNVPrm;
      MR := MR * 2;
      MTrail := (MTrail xor 1) * FNVPrm;
      Inc(MState);
      MR := MR + MState;
    end;
    MSum := MSum + MR;
  end;
  Check(Sum = MSum, 'zoo4-nestchain-sum');
  Check(State = MState, 'zoo4-nestchain-state');
  Check(Trail = MTrail, 'zoo4-nestchain-trail');
  Mix(Trail);
end;

{ ---------------------------------------------------------------- }
{ 70. Double bits stepped through an overlay in a loop: adding 1 to }
{ the bit pattern of 1.0 walks ADJACENT representable doubles —     }
{ strictly monotone, distance recoverable exactly.                  }

procedure RunBitsStepForms;
var
  O: record
    case Byte of
      0: (U: UInt64);
      1: (D: Double);
  end;
  Base: UInt64;
  Prev: Double;
  K: Integer;
begin
  Base := DoubleBits(1.0);
  O.U := Base;
  Prev := O.D;
  for K := 1 to 49 do
  begin
    O.U := Base + UInt64(UInt32(K));
    Check(O.D > Prev, 'zoo4-bits-step-monotone');
    Prev := O.D;
  end;
  Check(O.U - Base = 49, 'zoo4-bits-step-distance');
  Mix(O.U);
end;

{ ---------------------------------------------------------------- }
{ 71. Generic optional wrapper (lgenerics TGOptional / QuickLib     }
{ value shape): Implicit BOTH ways on a generic record, exercised   }
{ through a loop of wrap/unwrap round trips, in actual-parameter    }
{ position, and nested optional-of-optional built explicitly.       }

type
  TGOpt<T> = record
    HasVal: Boolean;
    Val: T;
    class operator Implicit(const AV: T): TGOpt<T>;
    class operator Implicit(const O: TGOpt<T>): T;
    class operator Add(const A, B: TGOpt<T>): TGOpt<T>;
  end;
  TGOptInt = TGOpt<Integer>;

class operator TGOpt<T>.Implicit(const AV: T): TGOpt<T>;
begin
  Result.HasVal := True;
  Result.Val := AV;
end;

class operator TGOpt<T>.Implicit(const O: TGOpt<T>): T;
begin
  Result := O.Val;
end;

class operator TGOpt<T>.Add(const A, B: TGOpt<T>): TGOpt<T>;
begin
  Result.HasVal := A.HasVal and B.HasVal;
  Result.Val := Default(T);
end;

function TakeInt(V: Integer): Integer;
begin
  Result := V * 2;
end;

procedure RunGOptChainForms;
var
  OI, OJ, OS: TGOptInt;
  NestedO: TGOpt<TGOptInt>;
  I, K: Integer;
begin
  { wrap/unwrap round trips in a loop: every assignment converts }
  OI := 1;
  for K := 1 to 20 do
  begin
    I := OI;                           { implicit unwrap }
    OI := I + 1;                       { implicit wrap }
  end;
  Check((OI.Val = 21) and OI.HasVal, 'zoo4-gopt-roundtrip-loop');

  { implicit unwrap in actual-parameter position }
  Check(TakeInt(OI) = 42, 'zoo4-gopt-param-unwrap');

  { operator on the generic specialization }
  OJ := 5;
  OS := OI + OJ;
  Check(OS.HasVal and (OS.Val = 0), 'zoo4-gopt-add-meet');

  { optional of optional, built explicitly to dodge ambiguity }
  NestedO.HasVal := True;
  NestedO.Val := OI;
  I := NestedO.Val;                    { unwrap the INNER through implicit }
  Check(I = 21, 'zoo4-gopt-nested-unwrap');

  Mix(UInt64(UInt32(OI.Val * 100 + Ord(OS.HasVal))));
end;

{ ---------------------------------------------------------------- }
{ ROUND zoo5: what the corpus has NOT touched yet — full-range byte }
{ and word index loops with permutation strides, pointer walks      }
{ compared through NativeUInt, the same record ops across stack /   }
{ heap / dyn-array / object-field storage, managed values built     }
{ INSIDE threads and read after join, and (modern) closure frames:  }
{ escape, sharing, managed capture, self-reference, thread handoff. }
{ ---------------------------------------------------------------- }

{ 72. Full-range ordinal index loops: for over EVERY Byte and EVERY }
{ Word (the High-edge termination itself is the form), xor-index    }
{ permutation reads, and a coprime-stride (257) permutation walk    }
{ over a 64K byte array. Oracle: closed-form sums.                  }

var
  GWordArr: array[Word] of Byte;

procedure RunByteWordIndexForms;
var
  BArr: array[Byte] of Word;
  B: Byte;
  W: Word;
  Cnt: Integer;
  Sum: Int64;
begin
  Cnt := 0;
  for B := Low(Byte) to High(Byte) do
  begin
    BArr[B] := Word(B) * 3;
    Inc(Cnt);
  end;
  Check(Cnt = 256, 'zoo5-byteloop-count');
  Check((BArr[0] = 0) and (BArr[255] = 765), 'zoo5-byteloop-fill');

  { xor-index visits a permutation: sum is invariant }
  Sum := 0;
  for B := Low(Byte) to High(Byte) do
    Sum := Sum + BArr[B xor $A5];
  Check(Sum = 3 * 32640, 'zoo5-byteloop-xor-perm');

  { 257 is coprime to 65536: the strided walk writes every cell once }
  for W := Low(Word) to High(Word) do
    GWordArr[(W * 257) and $FFFF] := Byte(W);
  Sum := 0;
  for W := Low(Word) to High(Word) do
    Sum := Sum + GWordArr[W];
  Check(Sum = 256 * 32640, 'zoo5-wordperm-sum');
  Check(GWordArr[(1000 * 257) and $FFFF] = Byte(1000), 'zoo5-wordperm-spot');

  Mix(UInt64(Sum));
end;

{ ---------------------------------------------------------------- }
{ 73. Pointer walks driven by NativeUInt comparisons (raw pointers  }
{ have no ordering operators): forward, backward past the base, a   }
{ 2D static array flattened to one linear byte walk (row-major      }
{ guarantee), and PAnsiChar over string content.                    }

procedure RunPtrLoopForms;
var
  A: array[0..15] of Integer;
  M: array[0..7, 0..7] of Byte;
  S: AnsiString;
  P: PInteger;
  PB: PByte;
  PC: PAnsiChar;
  K, R, C: Integer;
  Sum, Model: Integer;
begin
  for K := 0 to 15 do
    A[K] := K * K - 5;
  Model := 0;
  for K := 0 to 15 do
    Model := Model + A[K];

  Sum := 0;
  P := @A[0];
  while NativeUInt(P) <= NativeUInt(@A[15]) do
  begin
    Sum := Sum + P^;
    Inc(P);
  end;
  Check(Sum = Model, 'zoo5-ptrwalk-fwd');

  Sum := 0;
  P := @A[15];
  while NativeUInt(P) >= NativeUInt(@A[0]) do
  begin
    Sum := Sum + P^;
    Dec(P);
  end;
  Check(Sum = Model, 'zoo5-ptrwalk-back');

  for R := 0 to 7 do
    for C := 0 to 7 do
      M[R, C] := Byte(R * 8 + C);
  Sum := 0;
  PB := @M[0, 0];
  for K := 0 to 63 do
  begin
    Sum := Sum + PB^;
    Inc(PB);
  end;
  Model := 0;
  for R := 0 to 7 do
    for C := 0 to 7 do
      Model := Model + M[R, C];
  Check(Sum = Model, 'zoo5-ptr2d-flatten');
  Check(Sum = 2016, 'zoo5-ptr2d-pin');

  S := AnsiString('pointer-walk');
  Sum := 0;
  PC := PAnsiChar(S);
  for K := 1 to Length(S) do
  begin
    Sum := Sum + Ord(PC^);
    Inc(PC);
  end;
  Model := 0;
  for K := 1 to Length(S) do
    Model := Model + Ord(S[K]);
  Check(Sum = Model, 'zoo5-ptrstr-walk');

  Mix(UInt64(UInt32(Sum + Model)));
end;

{ ---------------------------------------------------------------- }
{ 74. The same record machinery run in FOUR storage homes: a stack  }
{ local, a New'd heap record, a dyn-array element and an object     }
{ field. Identical seed must produce identical folds everywhere.    }

type
  TSHRec = record
    A, B: Int64;
    S: AnsiString;
  end;
  TSHHost = class
  public
    R: TSHRec;
  end;
  TSHDyn = array of TSHRec;
  PSHRec = ^TSHRec;

procedure CrunchSH(var R: TSHRec; Seed: Integer);
var
  K: Integer;
begin
  R.A := Seed;
  R.B := 1;
  R.S := '';
  for K := 1 to 10 do
  begin
    R.A := R.A * 3 + K;
    R.B := R.B xor R.A;
    if K and 1 = 1 then
      R.S := R.S + AnsiChar(Ord('a') + K);
  end;
end;

function FoldSH(const R: TSHRec): UInt64;
var
  K: Integer;
begin
  Result := (UInt64(R.A) xor UInt64(R.B)) * FNVPrm;
  for K := 1 to Length(R.S) do
    Result := (Result xor UInt64(Ord(R.S[K]))) * FNVPrm;
end;

procedure RunStackHeapForms;
var
  Loc: TSHRec;
  PH: PSHRec;
  DA: TSHDyn;
  Host: TSHHost;
  Seed: Integer;
  FLoc: UInt64;
begin
  Seed := Integer(OpaqueI(9));
  CrunchSH(Loc, Seed);
  FLoc := FoldSH(Loc);

  New(PH);
  CrunchSH(PH^, Seed);
  Check(FoldSH(PH^) = FLoc, 'zoo5-storage-heap');
  Dispose(PH);

  SetLength(DA, 3);
  CrunchSH(DA[1], Seed);
  Check(FoldSH(DA[1]) = FLoc, 'zoo5-storage-dyn');

  Host := TSHHost.Create;
  CrunchSH(Host.R, Seed);
  Check(FoldSH(Host.R) = FLoc, 'zoo5-storage-field');
  Host.Free;

  Mix(FLoc);
end;

{ ---------------------------------------------------------------- }
{ 75. Managed values built INSIDE worker threads and read after     }
{ join: each worker owns its slots (no shared mutable state), the   }
{ join is the visibility barrier. Strings, dyn arrays and sums      }
{ must match main-thread models exactly.                            }

type
  TZWorker = class(TThread)
  public
    Seed: Integer;
    OutSum: Int64;
    OutStr: AnsiString;
    OutDyn: TIntDyn;
    constructor Create(ASeed: Integer);
  protected
    procedure Execute; override;
  end;

constructor TZWorker.Create(ASeed: Integer);
begin
  inherited Create(True);
  Seed := ASeed;
end;

procedure TZWorker.Execute;
var
  K: Integer;
begin
  OutSum := 0;
  OutStr := '';
  SetLength(OutDyn, 4);
  for K := 1 to 25 do
  begin
    OutSum := OutSum + (Int64(Seed) * K) xor K;
    if K mod 7 = 0 then
      OutStr := OutStr + AnsiChar(Ord('A') + (Seed + K) mod 26);
    OutDyn[K and 3] := OutDyn[K and 3] + Seed * K;
  end;
end;

procedure RunThreadHandoffForms;
var
  Ws: array[0..3] of TZWorker;
  Seeds: array[0..3] of Integer;
  K, J, T: Integer;
  MSum: Int64;
  MStr: AnsiString;
  MDyn: array[0..3] of Integer;
  W: UInt64;
begin
  Seeds[0] := 3;
  Seeds[1] := 5;
  Seeds[2] := 7;
  Seeds[3] := 9;
  for T := 0 to 3 do
    Ws[T] := TZWorker.Create(Seeds[T]);
  for T := 0 to 3 do
    Ws[T].Start;
  for T := 0 to 3 do
    Ws[T].WaitFor;

  W := 0;
  for T := 0 to 3 do
  begin
    { main-thread model, same formulas }
    MSum := 0;
    MStr := '';
    for J := 0 to 3 do
      MDyn[J] := 0;
    for K := 1 to 25 do
    begin
      MSum := MSum + (Int64(Seeds[T]) * K) xor K;
      if K mod 7 = 0 then
        MStr := MStr + AnsiChar(Ord('A') + (Seeds[T] + K) mod 26);
      MDyn[K and 3] := MDyn[K and 3] + Seeds[T] * K;
    end;
    Check(Ws[T].OutSum = MSum, 'zoo5-thread-sum');
    Check(Ws[T].OutStr = MStr, 'zoo5-thread-str');
    for J := 0 to 3 do
      Check(Ws[T].OutDyn[J] = MDyn[J], 'zoo5-thread-dyn');
    W := (W xor UInt64(MSum)) * FNVPrm;
  end;
  for T := 0 to 3 do
    Ws[T].Free;
  Mix(W);
end;

{$ifdef HAS_FUNCOBJ}
{ ---------------------------------------------------------------- }
{ 76. Closure FRAMES: a closure escaping to a global keeps its      }
{ captured locals alive after the maker returns; two closures over  }
{ one frame share state; a captured interface is held by the frame  }
{ and released with the last closure; a closure captures another    }
{ closure; recursion through the captured variable itself; and the  }
{ shared-local loop-capture pin (all slots see the LAST value —     }
{ complement of probe7's inline-var single-slot pin).               }

type
  TZProc = reference to procedure;
  TZFuncI = reference to function: Integer;

var
  GEscape: TZFuncI;
  GKeep: TZProc;
  GTouch: Integer = 0;

procedure MakeCounterZ(Start: Integer);
var
  C: Integer;
begin
  C := Start;
  GEscape := function: Integer
    begin
      Inc(C);
      Result := C;
    end;
end;

procedure MakeKeeper;
var
  LI: IInterface;
begin
  LI := TMLifeObj.Create;
  GKeep := procedure
    begin
      if LI <> nil then
        Inc(GTouch);
    end;
end;                                   { LI's only home is now the frame }

procedure RunClosureFrameForms;
var
  X, K, I: Integer;
  Bump: TZProc;
  Peek: TZFuncI;
  Intf: IInterface;
  Add5, Mul3After, Fib: TZFunc;
  Slots: array[0..3] of TZFuncI;
begin
  { escaped frame: state lives past the maker's return }
  MakeCounterZ(100);
  Check((GEscape() = 101) and (GEscape() = 102) and (GEscape() = 103),
    'zoo5-closure-escape-state');
  GEscape := nil;

  { two closures over ONE frame }
  X := Integer(OpaqueI(40));
  Bump := procedure
    begin
      Inc(X);
    end;
  Peek := function: Integer
    begin
      Result := X;
    end;
  Bump();
  Bump();
  Check(Peek() = 42, 'zoo5-closure-shared-frame');
  Check(X = 42, 'zoo5-closure-frame-is-var');

  { capture is BY REFERENCE: one shared storage, so niling the local
    releases immediately — there is no hidden frame copy }
  TMLifeObj.Alive := 0;
  Intf := TMLifeObj.Create;
  GKeep := procedure
    begin
      if Intf = nil then
        X := -1;
    end;
  Intf := nil;
  Check(TMLifeObj.Alive = 0, 'zoo5-closure-capture-by-ref');
  GKeep := nil;

  { the true holder form: the maker RETURNED, its local lives on only
    inside the escaped frame — and is still usable through the closure }
  TMLifeObj.Alive := 0;
  GTouch := 0;
  MakeKeeper;
  Check(TMLifeObj.Alive = 1, 'zoo5-closure-holds-managed');
  GKeep();
  Check(GTouch = 1, 'zoo5-closure-frame-usable');
  GKeep := nil;
  Check(TMLifeObj.Alive = 0, 'zoo5-closure-release-managed');

  { closure capturing another closure }
  K := Integer(OpaqueI(5));
  Add5 := function(A: Integer): Integer
    begin
      Result := A + K;
    end;
  Mul3After := function(A: Integer): Integer
    begin
      Result := Add5(A) * 3;
    end;
  Check(Mul3After(2) = 21, 'zoo5-closure-in-closure');

  { recursion through the captured variable itself }
  Fib := function(N: Integer): Integer
    begin
      if N < 2 then
        Result := N
      else
        Result := Fib(N - 1) + Fib(N - 2);
    end;
  Check(Fib(10) = 55, 'zoo5-closure-fib-selfref');

  { loop capture of a SHARED local: every slot sees the final value }
  for I := 0 to 3 do
  begin
    K := I * 5;
    Slots[I] := function: Integer
      begin
        Result := K;
      end;
  end;
  for I := 0 to 3 do
    Check(Slots[I]() = 15, 'zoo5-closure-loop-shared-pin');

  Mix(UInt64(UInt32(X + Fib(10))));
end;

{ ---------------------------------------------------------------- }
{ 77. A closure handed to ANOTHER THREAD mutates the main frame's   }
{ locals through the captured references; WaitFor is the barrier    }
{ that makes the writes visible.                                    }

type
  TZClosureThread = class(TThread)
  public
    Proc: TZProc;
  protected
    procedure Execute; override;
  end;

procedure TZClosureThread.Execute;
begin
  if Assigned(Proc) then
    Proc();
end;

procedure RunClosureThreadForms;
var
  Total: Integer;
  S: AnsiString;
  T: TZClosureThread;
begin
  Total := Integer(OpaqueI(1));
  S := AnsiString('m');
  T := TZClosureThread.Create(True);
  T.Proc := procedure
    begin
      Total := Total + 41;
      S := S + AnsiString('T');
    end;
  T.Start;
  T.WaitFor;
  Check(Total = 42, 'zoo5-closure-thread-int');
  Check(S = 'mT', 'zoo5-closure-thread-str');
  T.Free;
  Mix(UInt64(UInt32(Total + Length(S))));
end;
{$endif}

{ ---------------------------------------------------------------- }
{ ROUND zoo6 "salad": curated from random code-form combinations.  }
{ Rejected by the compiler during curation: a closure calling a     }
{ NESTED function of the enclosing scope (E2555 Cannot capture      }
{ symbol) — mutual recursion between two closures is the legal      }
{ substitute. Doubtful syntax was checked separately before merge. }
{ ---------------------------------------------------------------- }

{ 78. (#5) Writable typed const: a PACKED record with an AnsiString }
{ field living in the data segment, mutated through a LeftShift     }
{ operator inside repeat..until — the first concat must COW the     }
{ literal away; state persists across two invocations.              }

type
  TShifty = packed record
    V: Integer;
    S: AnsiString;
    class operator LeftShift(const A: TShifty; N: Integer): TShifty;
  end;

class operator TShifty.LeftShift(const A: TShifty; N: Integer): TShifty;
begin
  Result.V := A.V shl N;
  Result.S := A.S + AnsiChar(Ord('0') + N);
end;

{$J+}
const
  WShift: TShifty = (V: 1; S: 'q');
{$J-}

procedure ShiftRound;
begin
  repeat
    WShift := WShift shl 1;
  until WShift.V >= 64;
end;

procedure RunWtcShiftForms;
begin
  ShiftRound;                          { 1 -> 64 in six shifts }
  Check(WShift.V = 64, 'zoo6-wtcshift-v1');
  Check(WShift.S = 'q111111', 'zoo6-wtcshift-s1');
  ShiftRound;                          { already >= 64: exactly one pass }
  Check(WShift.V = 128, 'zoo6-wtcshift-persist-v');
  Check(WShift.S = 'q1111111', 'zoo6-wtcshift-persist-s');
  Mix(UInt64(UInt32(WShift.V + Length(WShift.S))));
end;

{ ---------------------------------------------------------------- }
{ 79. (#40) for-in over a SECOND reference while Insert through the }
{ first one reallocs it mid-walk: refcount 2 forces copy-on-write,  }
{ so the enumerator and B keep the ORIGINAL memory — safe under any }
{ capture policy (unlike the variable-carrier probe).               }

procedure RunForInAliasForms;
var
  A, B, Model: TIntDyn;
  V, K, Sum, ModelSum: Integer;
  Inserted: Boolean;
begin
  SetLength(A, 6);
  for K := 0 to 5 do
    A[K] := K * K + 1;
  Model := Copy(A);
  ModelSum := 0;
  for K := 0 to High(Model) do
    ModelSum := ModelSum + Model[K];
  B := A;
  Inserted := False;
  Sum := 0;
  for V in B do
  begin
    Sum := Sum + V;
    if not Inserted then
    begin
      Insert(99, A, 0);                { A detaches, B keeps the original }
      Inserted := True;
    end;
  end;
  Check(Sum = ModelSum, 'zoo6-forin-alias-walk');
  Check((Length(A) = 7) and (A[0] = 99) and (A[1] = 1),
    'zoo6-forin-alias-grown');
  Check((Length(B) = 6) and (B[0] = 1), 'zoo6-forin-alias-original');
  Mix(UInt64(UInt32(Sum)));
end;

{ ---------------------------------------------------------------- }
{ 80. (#12) Manual va_arg: walking an array-of-const by raw PByte   }
{ strides of SizeOf(TVarRec) must agree with normal indexing (the   }
{ NormFold walker from round zoo).                                  }

function VaArgFold(const A: array of const): UInt64;
var
  PB: PByte;
  K: Integer;
  PV: PVarRec;
begin
  Result := FNVOfs;
  PB := PByte(@A[0]);
  for K := 0 to High(A) do
  begin
    PV := PVarRec(PB);
    case PV^.VType of
      vtInteger:
        Result := FStep(Result, UInt64(Int64(PV^.VInteger)));
      vtBoolean:
        Result := FStep(Result, UInt64(Ord(PV^.VBoolean)));
      vtInt64:
        Result := FStep(Result, UInt64(PV^.VInt64^));
    else
      Result := FStep(Result, $99);
    end;
    Inc(PB, SizeOf(TVarRec));
  end;
end;

procedure RunVaArgForms;
begin
  Check(VaArgFold([12, True, Int64(9000000000)]) =
    NormFold([12, True, Int64(9000000000)]), 'zoo6-varrec-vaarg');
  Check(VaArgFold([]) = FNVOfs, 'zoo6-varrec-vaarg-empty');
  Mix(VaArgFold([Integer(OpaqueI(5)), False]));
end;

{ ---------------------------------------------------------------- }
{ 81. (#29) An exception ESCAPES Execute: the finally on the        }
{ thread's unwind path runs in the thread, the object survives as   }
{ FatalException until the TThread is freed.                        }

type
  TZFatalThread = class(TThread)
  public
    FinRan: Integer;
  protected
    procedure Execute; override;
  end;

procedure TZFatalThread.Execute;
begin
  try
    raise EVictim.Create('escapee');
  finally
    Inc(FinRan);
  end;
end;

procedure RunThreadFatalForms;
var
  T: TZFatalThread;
begin
  VictimGone := 0;
  T := TZFatalThread.Create(True);
  T.Start;
  T.WaitFor;
  Check(T.FinRan = 1, 'zoo6-thread-fatal-finally-ran');
  Check((T.FatalException <> nil) and (T.FatalException.ClassType = EVictim),
    'zoo6-thread-fatal-class');
  T.Free;
  Check(VictimGone = 1, 'zoo6-thread-fatal-freed');
  Mix(UInt64(UInt32(VictimGone)));
end;

{ ---------------------------------------------------------------- }
{ 82. (#24) A loop driven ENTIRELY by operators: the body is one    }
{ overloaded Dec, the until condition is an Implicit conversion to  }
{ Boolean.                                                          }

type
  TCntDn = record
    V: Integer;
    class operator Dec(const A: TCntDn): TCntDn;
    class operator Implicit(const A: TCntDn): Boolean;
  end;

class operator TCntDn.Dec(const A: TCntDn): TCntDn;
begin
  Result.V := A.V - 3;
end;

class operator TCntDn.Implicit(const A: TCntDn): Boolean;
begin
  Result := A.V <= 0;
end;

procedure RunDecUntilForms;
var
  C: TCntDn;
  Steps: Integer;
begin
  C.V := Integer(OpaqueI(20));
  Steps := 0;
  repeat
    Dec(C);
    Inc(Steps);
  until C;                             { record as the loop condition }
  Check((Steps = 7) and (C.V = -1), 'zoo6-dec-until-implicit');
  Mix(UInt64(UInt32(Steps)));
end;

{ ---------------------------------------------------------------- }
{ 83. (#38) NativeUInt absolute OVER a pointer variable: the same   }
{ cell steered numerically and typed, interleaved.                  }

procedure RunAbsPtrForms;
var
  Arr6: array[0..7] of Integer;
  P6: PInteger;
  NU: NativeUInt absolute P6;
  K: Integer;
begin
  for K := 0 to 7 do
    Arr6[K] := K * 11;
  P6 := @Arr6[0];
  NU := NU + 3 * SizeOf(Integer);      { numeric stride }
  Check(P6^ = 33, 'zoo6-absptr-stride');
  Inc(P6);                             { typed forward }
  NU := NU - SizeOf(Integer);          { numeric back }
  Check(P6^ = 33, 'zoo6-absptr-mixed');
  Mix(UInt64(UInt32(P6^)));
end;

{ ---------------------------------------------------------------- }
{ 84. (#8) Default array property added by a RECORD HELPER, and the }
{ navigation recurses on the TYPE level: record -> host class ->    }
{ record, so R[i][j] chains with no method names in sight.          }

type
  THive = class;
  TNode = record
    Val: Integer;
    Host: THive;
  end;
  THive = class
  public
    Cells: array of TNode;
  end;
  TNodeHelper = record helper for TNode
    function GetCell(I: Integer): TNode;
    property Cell[I: Integer]: TNode read GetCell; default;
  end;

function TNodeHelper.GetCell(I: Integer): TNode;
begin
  Result := Host.Cells[I];
end;

procedure RunHelperDefPropForms;
var
  Hive: THive;
  N: TNode;
  K: Integer;
begin
  Hive := THive.Create;
  SetLength(Hive.Cells, 3);
  for K := 0 to 2 do
  begin
    Hive.Cells[K].Val := K * 100;
    Hive.Cells[K].Host := Hive;
  end;
  N := Hive.Cells[0];
  Check(N[1][2].Val = 200, 'zoo6-helpdef-chain');
  Check(N[Integer(OpaqueI(2))][0].Val = 0, 'zoo6-helpdef-opaque');
  Mix(UInt64(UInt32(N[1].Val)));
  Hive.Free;
end;

{ ---------------------------------------------------------------- }
{ 85. (#27+#6) Helper-provided enumerator on the INTRINSIC          }
{ ShortString type — works, in sharp contrast to the record-helper  }
{ enumerator crash (forinhlp.dpr): this pins the healthy axis.      }
{ Plus length-byte surgery redefining what for-in sees.             }

type
  TSSEnum = record
    FP: Integer;
    FS: ^ShortString;
    function MoveNext: Boolean;
    function GetCur: AnsiChar;
    property Current: AnsiChar read GetCur;
  end;
  TSSHelper = record helper for ShortString
    function GetEnumerator: TSSEnum;
  end;

function TSSEnum.MoveNext: Boolean;
begin
  Inc(FP);
  Result := FP <= Length(FS^);
end;

function TSSEnum.GetCur: AnsiChar;
begin
  Result := FS^[FP];
end;

function TSSHelper.GetEnumerator: TSSEnum;
begin
  Result.FP := 0;
  Result.FS := @Self;
end;

procedure RunSSEnumForms;
var
  SS: ShortString;
  C: AnsiChar;
  Sum: Integer;
begin
  SS := 'abcdef';
  SS[0] := AnsiChar(3);                { length surgery: only 'abc' visible }
  Sum := 0;
  for C in SS do
    Sum := Sum + Ord(C);
  Check(Sum = Ord('a') + Ord('b') + Ord('c'), 'zoo6-ssenum-cut');
  SS[0] := AnsiChar(6);                { restore: full walk }
  Sum := 0;
  for C in SS do
    Sum := Sum + Ord(C);
  Check(Sum = 597, 'zoo6-ssenum-grown');
  Mix(UInt64(UInt32(Sum)));
end;

{$ifdef HAS_FUNCOBJ}
{ ---------------------------------------------------------------- }
{ 86. (#3) A closure dispatches a VIRTUAL method of a legacy        }
{ TP-object through a captured pointer; New(P, Init) and            }
{ Dispose(P, Done) drive the 1989 lifecycle around the 2009         }
{ capture machinery.                                                }

type
  POBeast = ^TOBeast;
  TOBeast = object
    Tag: Integer;
    constructor Init(ATag: Integer);
    destructor Done; virtual;
    function Roar: Integer; virtual;
  end;
  TOLion = object(TOBeast)
    function Roar: Integer; virtual;
  end;
  POLion = ^TOLion;

var
  GDone6: Integer = 0;

constructor TOBeast.Init(ATag: Integer);
begin
  Tag := ATag;
end;

destructor TOBeast.Done;
begin
  Inc(GDone6);
end;

function TOBeast.Roar: Integer;
begin
  Result := Tag * 10;
end;

function TOLion.Roar: Integer;
begin
  Result := Tag * 1000;
end;

procedure RunTpClosureForms;
var
  PL: POLion;
  PB: POBeast;
  Grab: TZFunc;
begin
  GDone6 := 0;
  New(PL, Init(4));
  PB := PL;
  Grab := function(N: Integer): Integer
    begin
      Result := PB^.Roar + N;          { virtual dispatch via capture }
    end;
  Check(Grab(5) = 4005, 'zoo6-tpclosure-vmt');
  Dispose(PL, Done);
  Check(GDone6 = 1, 'zoo6-tpclosure-done');
  Grab := nil;                         { PB dangles; never called again }
  Mix(UInt64(UInt32(GDone6)));
end;

{ ---------------------------------------------------------------- }
{ 87. (#2, legal half + #34) Mutual recursion between TWO closures  }
{ through each other's captured variables (the direct closure ->    }
{ nested-function call is E2555); a nested function calls a closure }
{ one-directionally — static link and capture frame meet in one     }
{ call chain. Plus a LIVE captured pointer: Inc from outside is     }
{ visible through the closure (by-ref capture, no snapshot).        }

procedure RunClosureMutualForms;
var
  FA, FB: TZFunc;
  Calls: Integer;
  CapArr: array[0..5] of Integer;
  CapP: PInteger;
  Rd: TZFuncI;
  K: Integer;

  function ViaLink(N: Integer): Integer;
  begin
    Inc(Calls);
    Result := FA(N);
  end;

begin
  Calls := 0;
  FA := function(N: Integer): Integer
    begin
      if N = 0 then
        Result := 7
      else
        Result := FB(N - 1) * 10 + 1;
    end;
  FB := function(N: Integer): Integer
    begin
      if N = 0 then
        Result := 8
      else
        Result := FA(N - 1) * 10 + 2;
    end;
  Check(FA(3) = 8121, 'zoo6-closure-mutual');
  Check((ViaLink(2) = 721) and (Calls = 1), 'zoo6-closure-vialink');

  for K := 0 to 5 do
    CapArr[K] := K * 7;
  CapP := @CapArr[0];
  Rd := function: Integer
    begin
      Result := CapP^;
    end;
  Check(Rd() = 0, 'zoo6-ptr-capture-start');
  Inc(CapP, 2);                        { moved OUTSIDE the closure }
  Check(Rd() = 14, 'zoo6-ptr-capture-live');
  Mix(UInt64(UInt32(FA(2) + Rd())));
end;
{$endif}

{$ifdef HAS_D12}
{ ---------------------------------------------------------------- }
{ 88. (#22) Multiline string + caret control literals + a           }
{ resourcestring, concatenated across the compile-time/run-time     }
{ boundary.                                                         }

resourcestring
  RS6 = 'rs-part';

procedure RunMlCaretResForms;
var
  S: string;
begin
  S := '''
    head
    ''' + ^M + ^J + RS6;
  Check(S = 'head' + #13 + #10 + 'rs-part', 'zoo6-d12-ml-caret-res');
  Mix(UInt64(UInt32(Length(S))));
end;
{$endif}

{ ---------------------------------------------------------------- }


{ ---------------------------------------------------------------- }
{ ROUND iss: the compiler-slice assimilated. 36 repros from the FPC }
{ bugtracker (local slice, originals in slice/) triaged: 22 are    }
{ portable and wrapped below with oracles and permanent iss-NNNNN   }
{ names; 14 stay standalone in slice/ (FPC-only syntax: dyn-array   }
{ "+", IndexByte, local dyn consts, TP-object VMT semantics, page-  }
{ boundary probes; or UB by corpus rule 1: shift >= width,          }
{ out-of-bounds writes in the repro itself). dcc64 rejections found }
{ while porting: property read X.B where B is a class var (E2562).  }
{ Expected values pinned from issue texts + verified on dcc64.      }

{ --- portable slice, part A: arithmetic and codegen shapes ------- }

var
  IssFn1Calls: Integer = 0;

function IssFn1True: Boolean;
begin
  Inc(IssFn1Calls);
  Result := True;
end;

function IssIsAlpha(C: Byte): Integer;
begin
  if ((AnsiChar(C) >= 'A') and (AnsiChar(C) <= 'Z')) or
     ((AnsiChar(C) >= 'a') and (AnsiChar(C) <= 'z')) then
    Result := 1
  else
    Result := 0;
end;

function IssGetDoubleAbs(V1, V2: Integer): Double;
type
  TpD = packed record
    A, B: Integer;
  end;
var
  V: TpD absolute Result;
begin
  V.A := V1;
  V.B := V2;
end;

type
  TIssRecEC = record
    EntryCount: NativeUInt;
  end;

function IssLoopUnsigned(const R: TIssRecEC): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to R.EntryCount - 1 do
    Inc(Result);
end;

function IssShl32(V: UInt64): UInt64; inline;
begin
  Result := V;
  Result := Result shl 32;
end;

function IssWB(A: Cardinal; B: Int64): Int64;
begin
  while True do
  begin
    if B > 0 then
      B := A;
    Result := B;
    Break;
  end;
end;

function IssF0Bits(const Value: UInt64): Double; inline;
var
  R: UInt64 absolute Result;
begin
  R := Value;
end;

type
  TIssU1 = array[0..0] of UInt64;

function IssF2Bits(const Value: UInt64): Double; inline;
begin
  TIssU1(Result)[0] := Value;
end;

function IssHiDW(Q: UInt64): Cardinal; inline;
begin
  Result := Cardinal(Q shr 32);
end;

type
  TIssBytes = array of Byte;

function IssReadByte(const D: TIssBytes; var P: Integer): Byte;
begin
  Result := D[P];
  Inc(P);
end;

function IssReadSubLen(const D: TIssBytes; var P: Integer): Integer;
var
  O1: Integer;
begin
  O1 := IssReadByte(D, P);
  if O1 < 192 then
    Result := O1
  else if O1 < 255 then
    Result := ((O1 - 192) shl 8) + IssReadByte(D, P) + 192
  else
    Result := -1;
end;

procedure RunIssueSliceAForms;
var
  C1, C2, Prod: Currency;
  I, K, N, P: Integer;
  W: Word;
  RE: TIssRecEC;
  DV: Double;
  A4: array[0..3] of Double;
  PD: PDouble;
  BD: TIssBytes;
  Entered: Boolean;
begin
  { iss-39480: Currency multiply precision (self-checked upstream) }
  C1 := -542226.5406;
  C2 := 1387845832.7798;
  Prod := C1 * C2;
  Check(Abs(Prod - (-752526844794317.0355)) <= 1, 'iss-39480-curr-mul-neg');
  C1 := -539324.3317;
  C2 := -593647440.2441;
  Prod := C1 * C2;
  Check(Abs(Prod - 320168508975064.9173) <= 1, 'iss-39480-curr-mul-pos');

  { iss-39851: (I<0) or (not Fn()) short-circuit — branch must not run,
    the function must run exactly once }
  IssFn1Calls := 0;
  Entered := False;
  I := Integer(OpaqueI(0));
  if (I < 0) or (not IssFn1True) then
    Entered := True;
  Check((not Entered) and (IssFn1Calls = 1), 'iss-39851-shortcircuit-not');

  { iss-39922: AnsiChar(byte) range classification, full sweep }
  N := 0;
  for K := 0 to 255 do
  begin
    I := IssIsAlpha(Byte(OpaqueI(K)));
    Check(I = Ord(((K >= Ord('A')) and (K <= Ord('Z'))) or
      ((K >= Ord('a')) and (K <= Ord('z')))), 'iss-39922-alpha-sweep');
    Inc(N, I);
  end;
  Check(N = 52, 'iss-39922-alpha-count');

  { iss-40191: Int64(Cardinal) - Int64(Cardinal) wrap-free delta }
  Check(Int64(Cardinal(OpaqueI(5))) - Int64(Cardinal(OpaqueI($FFFFFFF0))) =
    -4294967275, 'iss-40191-card-delta');

  { iss-40212: Double assembled through absolute over Result }
  Check(Round(IssGetDoubleAbs(1052909725, 1092805937) * 100000) =
    61916062257, 'iss-40212-abs-result-double');

  { iss-40611: signed Integer vs Word div comparison }
  W := 123;
  I := Integer(OpaqueI(-123123));
  Check(not (I > W div 3), 'iss-40611-signed-vs-worddiv');

  { iss-41126: for-to bound NativeUInt(0)-1 truncates, loop must skip }
  RE.EntryCount := NativeUInt(OpaqueU(0));
  Check(IssLoopUnsigned(RE) = 0, 'iss-41126-unsigned-bound-skip');

  { iss-41225: inline UInt64 shl 32 }
  Check(IssShl32(OpaqueU($ABCD)) = UInt64($ABCD) shl 32,
    'iss-41225-inline-shl32');

  { iss-41317: while/if with DWord assigned into Int64, B=-1 stays }
  Check(IssWB(Cardinal(OpaqueI(0)), OpaqueI(-1)) = -1,
    'iss-41317-while-break');

  { iss-41446: raw bits into a Double result — absolute and array-cast }
  Check(DoubleBits(IssF0Bits(OpaqueU(1))) = 1, 'iss-41446-abs-result-bits');
  Check(DoubleBits(IssF2Bits(OpaqueU(1))) = 1, 'iss-41446-arraycast-bits');

  { iss-41820: high dword of a qword shift }
  Check(IssHiDW(OpaqueU(1)) = 0, 'iss-41820-hi-of-1');
  Check(IssHiDW(OpaqueU($500000000)) = 5, 'iss-41820-hi-hi');

  { iss-41824: byte reader chain with var-position cursor }
  SetLength(BD, 2);
  BD[0] := 2;
  BD[1] := 99;
  P := 0;
  Check((IssReadSubLen(BD, P) = 2) and (P = 1), 'iss-41824-sublen-short');
  BD[0] := 200;
  BD[1] := 10;
  P := 0;
  Check((IssReadSubLen(BD, P) = 2250) and (P = 2), 'iss-41824-sublen-long');

  { iss-41811: Int64 / Double division must keep Double precision }
  DV := (OpaqueI(1356062706000) / 86400000.0) + 25569.0;
  Check(Abs(DV - 41264.170208) < 0.0001, 'iss-41811-int64-div-precision');

  { iss-41581: Power(10, Floor(Log10(0.01))) = 0.01, not 0.001 }
  DV := Power(10, Floor(Log10(0.01)));
  Check(Abs(DV - 0.01) < 1E-6, 'iss-41581-pow-floor-log');

  { iss-41270: p[i+i+0] addressing on PDouble }
  for K := 0 to 3 do
    A4[K] := K * 1.5 + 0.25;
{$POINTERMATH ON}
  PD := @A4[0];
  I := Integer(OpaqueI(0));
  Check(PD[I + I + 0] = A4[0], 'iss-41270-addr-zero');
  I := 1;
  Check(PD[I + I + 0] = A4[2], 'iss-41270-addr-two');
{$POINTERMATH OFF}

  Mix(UInt64(UInt32(N + P)));
  Mix(DoubleBits(DV));
end;

{ --- portable slice, part B: type and data shapes ---------------- }

type
  TIssWrapD = record
    Data: Pointer;
    function CloneW: TIssWrapD;
  end;
  TIssWrapDH = record helper for TIssWrapD
    function GetD: Pointer;
  end;

function TIssWrapD.CloneW: TIssWrapD;
begin
  Result.Data := Data;
end;

function TIssWrapDH.GetD: Pointer;
begin
  Result := Data;
end;

{$SCOPEDENUMS ON}
type
  TIssTarget = (
    None = 0, Translation, Rotation, Scale, Weights, Pointer_,
    PointerNodeRotation, PointerNodeScale, PointerNodeTranslation,
    PointerNodeWeights, PointerMeshWeights,
    PointerCameraOrthographicXMag, PointerCameraOrthographicYMag,
    PointerCameraOrthographicZFar, PointerCameraOrthographicZNear,
    PointerCameraPerspectiveAspectRatio, PointerCameraPerspectiveYFov,
    PointerCameraPerspectiveZFar, PointerCameraPerspectiveZNear,
    PointerPunctualLightColor, PointerPunctualLightIntensity,
    PointerPunctualLightRange, PointerPunctualLightSpotInnerConeAngle,
    PointerPunctualLightSpotOuterConeAngle,
    PointerMaterialPBRMetallicRoughnessBaseColorFactor,
    PointerMaterialPBRMetallicRoughnessMetallicFactor,
    PointerMaterialPBRMetallicRoughnessRoughnessFactor,
    PointerMaterialAlphaCutOff, PointerMaterialEmissiveFactor,
    PointerMaterialNormalTextureScale,
    PointerMaterialOcclusionTextureStrength,
    PointerMaterialPBRClearCoatFactor,
    PointerMaterialPBRClearCoatRoughnessFactor,
    PointerMaterialEmissiveStrength, PointerMaterialIOR,
    PointerMaterialPBRIridescenceFactor, PointerMaterialPBRIridescenceIor,
    PointerMaterialPBRIridescenceMinimum,
    PointerMaterialPBRIridescenceMaximum,
    PointerMaterialPBRSheenColorFactor,
    PointerMaterialPBRSheenRoughnessFactor,
    PointerMaterialPBRSpecularFactor,
    PointerMaterialPBRSpecularColorFactor,
    PointerMaterialPBRTransmissionFactor,
    PointerMaterialPBRVolumeThicknessFactor,
    PointerMaterialPBRVolumeAttenuationDistance,
    PointerMaterialPBRVolumeAttenuationColor,
    PointerTextureOffset, PointerTextureRotation, PointerTextureScale);
  TIssTargetSet = set of TIssTarget;
{$SCOPEDENUMS OFF}

const
  IssMaterialTargets: TIssTargetSet = [
    TIssTarget.PointerMaterialPBRMetallicRoughnessBaseColorFactor,
    TIssTarget.PointerMaterialPBRMetallicRoughnessMetallicFactor,
    TIssTarget.PointerMaterialPBRMetallicRoughnessRoughnessFactor,
    TIssTarget.PointerMaterialAlphaCutOff,
    TIssTarget.PointerMaterialEmissiveFactor,
    TIssTarget.PointerMaterialNormalTextureScale,
    TIssTarget.PointerMaterialOcclusionTextureStrength,
    TIssTarget.PointerMaterialPBRClearCoatFactor,
    TIssTarget.PointerMaterialPBRClearCoatRoughnessFactor,
    TIssTarget.PointerMaterialEmissiveStrength,
    TIssTarget.PointerMaterialIOR,
    TIssTarget.PointerMaterialPBRIridescenceFactor,
    TIssTarget.PointerMaterialPBRIridescenceIor,
    TIssTarget.PointerMaterialPBRIridescenceMinimum,
    TIssTarget.PointerMaterialPBRIridescenceMaximum,
    TIssTarget.PointerMaterialPBRSheenColorFactor,
    TIssTarget.PointerMaterialPBRSheenRoughnessFactor,
    TIssTarget.PointerMaterialPBRSpecularFactor,
    TIssTarget.PointerMaterialPBRSpecularColorFactor,
    TIssTarget.PointerMaterialPBRTransmissionFactor,
    TIssTarget.PointerMaterialPBRVolumeThicknessFactor,
    TIssTarget.PointerMaterialPBRVolumeAttenuationDistance,
    TIssTarget.PointerMaterialPBRVolumeAttenuationColor,
    TIssTarget.PointerTextureOffset,
    TIssTarget.PointerTextureRotation,
    TIssTarget.PointerTextureScale];
  IssTextureTargets: TIssTargetSet = [
    TIssTarget.PointerTextureOffset,
    TIssTarget.PointerTextureRotation,
    TIssTarget.PointerTextureScale];

function IssBisect(P: PInteger; R: NativeInt; AValue: Integer): NativeInt;
var
  L, M: NativeInt;
begin
  L := 0;
  while L < R do
  begin
    M := (L + R) shr 1;
{$POINTERMATH ON}
    if P[M] < AValue then
      L := M + 1
    else
      R := M;
{$POINTERMATH OFF}
  end;
  Result := R;
end;

function IssEqual(L, R: Integer): Boolean; inline;
begin
  Result := not ((L < R) or (R < L));
end;

function IssBinSearch(const A: array of Integer; AValue: Integer): NativeInt;
var
  R: NativeInt;
  P: PInteger;
begin
  if Length(A) = 0 then
    Exit(-1);
  P := @A[0];
  R := High(A);
  Result := -1;
{$POINTERMATH ON}
  if P[0] < P[R] then
  begin
    if (AValue < P[0]) or (P[R] < AValue) then
      Exit;
    R := IssBisect(P, R, AValue);
    if IssEqual(P[R], AValue) then
      Result := R;
  end else if IssEqual(P[0], P[R]) and IssEqual(P[0], AValue) then
    Result := 0;
{$POINTERMATH OFF}
end;

{ iss-40518 dropped from the wrap: dcc64 REJECTS a record helper for a
  static-array type (E2474 Record type required) — the shape is FPC-only
  (type helper), the repro stays standalone in slice/. }

type
  TIssTB = record
    Physical, Logical, Offset: Integer;
    procedure Init; inline;
  end;
  TIssAttr = class
  public
    FStartX: TIssTB;
    procedure SetStartX(AValue: TIssTB); virtual;
    procedure SetFrameBoundsLog; inline;
  end;
  TIssMatch = class
  public
    function HasDisplayAbleMatches: Boolean; virtual;
    function GetMarkupAttr: TIssAttr;
  end;

procedure TIssTB.Init;
begin
end;

procedure TIssAttr.SetStartX(AValue: TIssTB);
begin
end;

procedure TIssAttr.SetFrameBoundsLog;
var
  B: TIssTB;
begin
  B.Init;
  SetStartX(B);
end;

function TIssMatch.HasDisplayAbleMatches: Boolean;
begin
  Result := False;
end;

function TIssMatch.GetMarkupAttr: TIssAttr;
begin
  Result := nil;
  if not HasDisplayAbleMatches then
    Exit;
  Result.SetFrameBoundsLog;
end;

{$A4}
type
  TIssFN = UnicodeString;
  TIssFNArr = array of TIssFN;
  TIssSubOptions = record
    MakeCommand: TIssFN;
    TargetFile: TIssFN;
    TargPref: TIssFN;
    MainFile: TIssFN;
    UnitDirs: TIssFNArr;
    UnitDirsOn: array of Integer;
    ReversePathOrder: Boolean;
    UnitPref, IncPref, LibPref, ObjPref: TIssFN;
    MakeOptions: array of TIssFN;
    MakeOptionsOn: array of Integer;
  end;
  TIssProjOptions = record
    K: TIssSubOptions;
  end;
  TIssTExp = record
    OptAfterMainFileMask: Integer;
  end;
  TIssCmdBuilder = class
  private
    FOptions: TIssProjOptions;
    FTExp: TIssTExp;
  public
    constructor Create;
    function BuildMakeCommandLine(const ATag: Integer): TIssFN;
  end;
{$A8}

constructor TIssCmdBuilder.Create;
var
  I: Integer;
begin
  FOptions.K.MakeCommand := 'fpc -O3';
  FOptions.K.TargetFile := 'output_binary.exe';
  FOptions.K.TargPref := '-o';
  FOptions.K.MainFile := 'myprog.pas';
  FOptions.K.ReversePathOrder := False;
  FOptions.K.UnitPref := '-Fu';
  FOptions.K.IncPref := '-Fi';
  FTExp.OptAfterMainFileMask := $400;
  SetLength(FOptions.K.UnitDirs, 12);
  SetLength(FOptions.K.UnitDirsOn, 12);
  for I := 0 to 11 do
  begin
    FOptions.K.UnitDirs[I] :=
      TIssFN('C:\MseLibraries\Path_Subdir_Layout_For_Testing\') +
      TIssFN(IntToStr(I));
    FOptions.K.UnitDirsOn[I] := $10000 or $20000;
  end;
  SetLength(FOptions.K.MakeOptions, 2);
  SetLength(FOptions.K.MakeOptionsOn, 2);
  FOptions.K.MakeOptions[0] := '-gl';
  FOptions.K.MakeOptionsOn[0] := $1;
  FOptions.K.MakeOptions[1] := '-Xg';
  FOptions.K.MakeOptionsOn[1] := $400;
end;

function TIssCmdBuilder.BuildMakeCommandLine(const ATag: Integer): TIssFN;

  function NormalizeName(const AName: TIssFN): TIssFN;
  begin
    Result := UpperCase(Trim(AName));
  end;

var
  Int1, Int2, Step: Integer;
  Str1, Str2, Str3: TIssFN;
begin
  with FOptions, K, FTExp do
  begin
    if MakeCommand = '' then
    begin
      Result := '';
      Exit;
    end;
    Str3 := '"' + MakeCommand + '"';
    Str1 := Str3;
    if (TargetFile <> '') and (TargPref <> '') then
      Str1 := Str1 + ' ' + TargPref + NormalizeName(TargetFile);
    Int2 := High(UnitDirs);
    Int1 := High(UnitDirsOn);
    if Int1 < Int2 then
      Int2 := Int1;
    if not ReversePathOrder then
    begin
      Int1 := Int2;
      Int2 := -1;
      Step := -1;
    end else begin
      Int1 := 0;
      Int2 := Int2 + 1;
      Step := 1;
    end;
    while Int1 <> Int2 do
    begin
      if (ATag and UnitDirsOn[Int1] <> 0) and (UnitDirs[Int1] <> '') then
      begin
        Str2 := NormalizeName(UnitDirs[Int1]);
        if UnitDirsOn[Int1] and $10000 <> 0 then
          Str1 := Str1 + ' ' + UnitPref + Str2;
        if UnitDirsOn[Int1] and $20000 <> 0 then
          Str1 := Str1 + ' ' + IncPref + Str2;
      end;
      Inc(Int1, Step);
    end;
    for Int1 := 0 to High(MakeOptions) do
      if MakeOptionsOn[Int1] and OptAfterMainFileMask = 0 then
        if (ATag and MakeOptionsOn[Int1] <> 0) and (MakeOptions[Int1] <> '') then
          Str1 := Str1 + ' ' + MakeOptions[Int1];
    Str1 := Str1 + ' ' + NormalizeName(MainFile);
    for Int1 := 0 to High(MakeOptions) do
      if MakeOptionsOn[Int1] and OptAfterMainFileMask <> 0 then
        if (ATag and MakeOptionsOn[Int1] <> 0) and (MakeOptions[Int1] <> '') then
          Str1 := Str1 + ' ' + MakeOptions[Int1];
  end;
  Result := Str1;
end;

procedure RunIssueSliceBForms;
var
  WD: TIssWrapD;
  P1, P2: Pointer;
  TG: TIssTarget;
  MatCount, TexCount, K: Integer;
  A3: array[0..2] of Integer;
  B4: array[0..3] of Integer;
  MO: TIssMatch;
  AT: TIssAttr;
  CB: TIssCmdBuilder;
  Cmd: TIssFN;
  H: UInt64;
  S: string;
begin
  { iss-40280: with on a clone-result + helper method }
  WD.Data := Pointer(NativeUInt(OpaqueU($1234)));
  with WD.CloneW do
    P1 := GetD;
  P2 := WD.CloneW.GetD;
  Check((NativeUInt(P1) = $1234) and (P1 = P2), 'iss-40280-with-clone-helper');

  { iss-40304: scoped-enum sets with high ordinals + in }
  MatCount := 0;
  TexCount := 0;
  for TG := TIssTarget.PointerMaterialPBRMetallicRoughnessBaseColorFactor to
      TIssTarget.PointerMaterialPBRVolumeAttenuationColor do
    if TG in IssMaterialTargets then
      Inc(MatCount);
  for TG := TIssTarget.PointerTextureOffset to TIssTarget.PointerTextureScale do
  begin
    if TG in IssTextureTargets then
      Inc(TexCount);
    if TG in IssMaterialTargets then
      Inc(MatCount);
  end;
  Check(MatCount = 26, 'iss-40304-set-in-material');
  Check(TexCount = 3, 'iss-40304-set-in-texture');

  { iss-40490: nested binary search over descending-equal plateaus }
  A3[0] := 7;
  A3[1] := 7;
  A3[2] := 7;
  B4[0] := 5;
  B4[1] := 5;
  B4[2] := 5;
  B4[3] := 5;
  Check(IssBinSearch(A3, Integer(OpaqueI(2))) = -1, 'iss-40490-plateau3');
  Check(IssBinSearch(B4, Integer(OpaqueI(2))) = -1, 'iss-40490-plateau4');
  Check(IssBinSearch(A3, Integer(OpaqueI(7))) = 0, 'iss-40490-plateau-hit');

  { iss-40894: zero-based strings — Low/High/char access }
{$ZEROBASEDSTRINGS ON}
  S := 'abc';
  Check((Low(S) = 0) and (High(S) = 2) and (S[0] = 'a') and (S[2] = 'c'),
    'iss-40894-zbs-bounds');
{$ZEROBASEDSTRINGS OFF}

  { iss-41558: nil result + exit before a call chain on it }
  MO := TIssMatch.Create;
  AT := MO.GetMarkupAttr;
  Check(AT = nil, 'iss-41558-nil-exit');
  MO.Free;

  { iss-41781: nested function under with over three frames, string
    builder loops — pins captured on dcc64 }
  CB := TIssCmdBuilder.Create;
  Cmd := CB.BuildMakeCommandLine($F000F);
  CB.Free;
  Check(Length(Cmd) = 1296, 'iss-41781-builder-len');
  H := FNVOfs;
  for K := 1 to Length(Cmd) do
    H := (H xor UInt64(Ord(Cmd[K]))) * FNVPrm;
  Check(H = UInt64($F02490EC02D6DBD2), 'iss-41781-builder-fnv');

  Mix(UInt64(UInt32(MatCount + TexCount)));
  Mix(H);
end;
{$ifdef HAS_FUNCOBJ}

{ --- portable slice, modern: function references ----------------- }

type
  TZProcI = reference to procedure(V: Integer);

  TIssMul = class
  private
    FA, FB: Integer;
    function GetB: Integer;
    procedure SetB(const Value: Integer);
  public
    function MultiplyA(Value: Integer): Integer;
    function MultiplyB(Value: Integer): Integer;
    property A: Integer read FA write FA;
    property B: Integer read GetB write SetB;
  end;

function TIssMul.GetB: Integer;
begin
  Result := FB;
end;

procedure TIssMul.SetB(const Value: Integer);
begin
  FB := Value;
end;

function TIssMul.MultiplyA(Value: Integer): Integer;
begin
  Result := Value * A;
end;

function TIssMul.MultiplyB(Value: Integer): Integer;
begin
  Result := Value * B;
end;

function IssR1: TZFuncI;
var
  N: Integer;
begin
  N := 5;
  Result := function: Integer
    begin
      Result := N;
    end;
end;

function IssR2: TZFuncI;
var
  N: Integer;
begin
  N := 5;
  Result := function: Integer
    begin
      Inc(N);
      Result := N;
    end;
end;

function IssR3: TZFuncI;
var
  N: Integer;
begin
  N := 5;
  Result := function: Integer
    begin
      N := N + 1;
      Result := N;
    end;
end;

function IssR4: TZFuncI;
var
  N: Integer;
begin
  N := 5;
  Result := function: Integer
    var
      T: Integer;
    begin
      T := N;
      N := T + 1;
      Result := N;
    end;
end;

function IssR5: TZFuncI;
var
  N: Integer;
begin
  N := 5;
  Result := function: Integer
    begin
      N := 7;
      Result := N;
    end;
end;

procedure RunIssueModernForms;
var
  T: TIssMul;
  M: TZFunc;
  I, SumRef, SumDir: Integer;
  PInner: TZProc;
  PO: TZProcI;
  X, X2: Integer;

  procedure ChkClo(const F: TZFuncI; W1, W2: Integer; const Name: AnsiString);
  begin
    Check((F() = W1) and (F() = W2), Name);
  end;

begin
  { iss-39765: a METHOD bound to a function reference }
  T := TIssMul.Create;
  M := T.MultiplyA;
  SumRef := 0;
  SumDir := 0;
  for I := 0 to 4 do
  begin
    T.A := I;
    SumRef := SumRef + M(4);
  end;
  for I := 0 to 4 do
  begin
    T.A := I;
    SumDir := SumDir + T.MultiplyA(4);
  end;
  Check((SumRef = SumDir) and (SumRef = 40), 'iss-39765-methodref-field');
  M := T.MultiplyB;
  SumRef := 0;
  for I := 0 to 4 do
  begin
    T.B := I;
    SumRef := SumRef + M(4);
  end;
  Check(SumRef = 40, 'iss-39765-methodref-property');
  T.Free;

  { iss-40316: inner closure created by an outer closure captures the
    outer's PARAM — later mutation of the source variable is invisible }
  X2 := 0;
  PO := procedure(S: Integer)
    begin
      PInner := procedure
        begin
          X2 := S;
        end;
    end;
  X := Integer(OpaqueI(1));
  PO(X);
  X := 0;
  PInner();
  Check((X2 = 1) and (X = 0), 'iss-40316-inner-captures-param');
  PInner := nil;
  PO := nil;

  { iss-41828: write-back semantics of captured locals, five spellings }
  ChkClo(IssR1(), 5, 5, 'iss-41828-read-only');
  ChkClo(IssR2(), 6, 7, 'iss-41828-inc');
  ChkClo(IssR3(), 6, 7, 'iss-41828-rmw');
  ChkClo(IssR4(), 6, 7, 'iss-41828-rmw-temp');
  ChkClo(IssR5(), 7, 7, 'iss-41828-write-only');

  Mix(UInt64(UInt32(SumRef + X2)));
end;
{$endif}

{$ifdef HAS_DELPHI_EQUALITY_COMPARER}
procedure RunDelphiEqualityComparerForms;
var
  Salt: Integer;
  Comparer: IEqualityComparer<string>;
  Dictionary: TDictionary<string, Integer>;
  Found: Integer;
begin
  Salt := 10;
  Comparer := TEqualityComparer<string>.Construct(
    function(const Left, Right: string): Boolean
    begin
      Result := SameText(Left, Right);
    end,
    function(const Value: string): Integer
    begin
      Result := Length(Value) + Salt;
    end);
  Check(Comparer.Equals('Spot', 'spot'),
    'generics-equality-comparer-anon-equals');
  Check(Comparer.GetHashCode('abc') = 13,
    'generics-equality-comparer-anon-integer-hash');
  Dictionary := TDictionary<string, Integer>.Create(Comparer);
  try
    Dictionary.Add('Spot', 17);
    Check(Dictionary.TryGetValue('spot', Found) and (Found = 17),
      'generics-equality-comparer-anon-dictionary');
  finally
    Dictionary.Free;
  end;
end;
{$endif}

{$ifdef HAS_ANON}
{ Delphi allows an explicit cast from a read-only anonymous callback to a
  by-value generic callback. The compiler must generate the anonymous routine
  with the target ABI; a 24-byte record makes a mere signature bypass fail. }
type
  TExplicitConstLargeRecord = record
    A: Int64;
    B: Int64;
    C: Int64;
  end;

  TExplicitConstManagedRecord = record
    Text: AnsiString;
    Value: Integer;
  end;

  TExplicitConstFunc<T, TResult> = reference to function(Arg: T): TResult;

procedure RunExplicitAnonymousConstCastForms;
var
  LargeCallback: TExplicitConstFunc<TExplicitConstLargeRecord, Int64>;
  ManagedCallback: TExplicitConstFunc<TExplicitConstManagedRecord, AnsiString>;
  LargeItem: TExplicitConstLargeRecord;
  ManagedItem: TExplicitConstManagedRecord;
begin
  LargeCallback := TExplicitConstFunc<TExplicitConstLargeRecord, Int64>(
    function(const Arg: TExplicitConstLargeRecord): Int64
    begin
      Result := Arg.A + Arg.B + Arg.C;
    end);
  ManagedCallback := TExplicitConstFunc<TExplicitConstManagedRecord, AnsiString>(
    function(const Arg: TExplicitConstManagedRecord): AnsiString
    begin
      Result := Arg.Text + AnsiString(IntToStr(Arg.Value));
    end);

  LargeItem.A := 10;
  LargeItem.B := 12;
  LargeItem.C := 20;
  ManagedItem.Text := 'managed-';
  ManagedItem.Value := 42;
  Check(LargeCallback(LargeItem) = 42,
    'anon-explicit-const-to-value-large-record');
  Check(ManagedCallback(ManagedItem) = 'managed-42',
    'anon-explicit-const-to-value-managed-record');
end;
{$endif}

{ ---------------------------------------------------------------- }

{$ifdef FPC}
{$asmmode intel}
{$endif}

function MoonHashAsm(BinanceID: Int64; CoinIndex, Profit: Cardinal): Cardinal;
asm
{$ifdef MSWINDOWS}
  xor rax, rax
  mov eax, edx
  mov rdx, rax
  xor rax, rax
  mov eax, r8d
  mov r8, rax
  mov rax, rcx
{$else}
  mov r8d, edx
  mov edx, esi
  mov rax, rdi
{$endif}
  rol rax, 16
  adc rax, rdx
  rol rax, 16
  adc rax, r8
  rol rax, 16
  adc rax, rdx
  rol rax, 8
{$ifdef MSWINDOWS}
  adc rax, rcx
{$else}
  adc rax, rdi
{$endif}
  rol rax, 8
  adc rax, r8
  xor rax, $37B2E8D9
  rol rax, 32
  xor rax, $1A7B29E5
  rol rax, 5
  adc rax, rdx
  rol rax, 7
{$ifdef MSWINDOWS}
  adc rax, rcx
{$else}
  adc rax, rdi
{$endif}
  rol rax, 9
  adc rax, r8
  mov rcx, rax
  rol rax, 32
  mov rdx, rax
  xor rax, rax
  mov eax, ecx
  add eax, edx
  adc eax, ecx
end;

function MoonBitCountAsm(X: Cardinal): Integer;
asm
{$ifdef MSWINDOWS}
  mov edx, ecx
{$else}
  mov edx, edi
{$endif}
  and edx, $55555555
  mov eax, edx
{$ifdef MSWINDOWS}
  mov edx, ecx
{$else}
  mov edx, edi
{$endif}
  shr edx, 1
  and edx, $55555555
  add eax, edx
  mov ecx, eax
  mov edx, ecx
  and edx, $33333333
  mov eax, edx
  mov edx, ecx
  shr edx, 2
  and edx, $33333333
  add eax, edx
  mov ecx, eax
  mov edx, ecx
  and edx, $0f0f0f0f
  mov eax, edx
  mov edx, ecx
  shr edx, 4
  and edx, $0f0f0f0f
  add eax, edx
  mov ecx, eax
  mov edx, ecx
  and edx, $00ff00ff
  mov eax, edx
  mov edx, ecx
  shr edx, 8
  and edx, $00ff00ff
  add eax, edx
  mov ecx, eax
  mov edx, ecx
  and edx, $0000ffff
  mov eax, edx
  mov edx, ecx
  shr edx, 16
  and edx, $0000ffff
  add eax, edx
end;

procedure RunIntelAsmAbiForms;
begin
  Check(MoonHashAsm(0, 0, 0) = 2490449953, 'asm-hash-zero');
  Check(MoonHashAsm(1, 2, 3) = 3038069607, 'asm-hash-small');
  Check(MoonHashAsm(-1, 0, 0) = 2490448929, 'asm-hash-negative');
  Check(MoonHashAsm(High(Int64), High(Cardinal), High(Cardinal)) = 1847606761,
    'asm-hash-high');
  Check(MoonHashAsm(Low(Int64), $80000000, $7fffffff) = 2444345861,
    'asm-hash-sign-bits');
  Check(MoonHashAsm(123456789012345, 54321, 98765) = 855063605,
    'asm-hash-production-shape');
  Check(MoonBitCountAsm(0) = 0, 'asm-bitcount-zero');
  Check(MoonBitCountAsm(1) = 1, 'asm-bitcount-one');
  Check(MoonBitCountAsm($ffffffff) = 32, 'asm-bitcount-full');
  Check(MoonBitCountAsm($80000001) = 2, 'asm-bitcount-ends');
  Check(MoonBitCountAsm($55555555) = 16, 'asm-bitcount-alternating');
  Check(MoonBitCountAsm($12345678) = 13, 'asm-bitcount-mixed');
  Mix(MoonHashAsm(123456789012345, 54321, 98765));
  Mix(UInt64(UInt32(MoonBitCountAsm($12345678))));
end;

{$ifdef HAS_OLEVARIANT_UTF8}
type
  TOleVariantUtf8Source = class
  private
    FValue: OleVariant;
    function GetValue: OleVariant;
  public
    property Value: OleVariant read GetValue write FValue;
  end;

function TOleVariantUtf8Source.GetValue: OleVariant;
begin
  Result := FValue;
end;

function AcceptOleVariantUtf8(const Value, Expected: UTF8String): Boolean;
begin
  Result := Value = Expected;
end;

procedure RunOleVariantUtf8Forms;
var
  Source: TOleVariantUtf8Source;
  Value: OleVariant;
  Utf8,
  Expected: UTF8String;
  Wide: UnicodeString;
begin
  Source := TOleVariantUtf8Source.Create;
  try
    Source.Value := '12.5';
    Value := Source.Value;
    Check(AcceptOleVariantUtf8(Value, '12.5'),
      'var-olevariant-utf8-ascii-variable');
    Check(AcceptOleVariantUtf8(Source.Value, '12.5'),
      'var-olevariant-utf8-ascii-property');
    Utf8 := Value;
    Mix(Ord(Utf8[1]));

    Wide := UnicodeString(WideChar($03BB)) + WideChar($0434) +
      WideChar($0430) + WideChar($043D) + WideChar($043D) +
      WideChar($044B) + WideChar($0435);
    Expected := UTF8Encode(Wide);
    Source.Value := Wide;
    Value := Source.Value;
    Check(AcceptOleVariantUtf8(Value, Expected),
      'var-olevariant-utf8-unicode-variable');
    Check(AcceptOleVariantUtf8(Source.Value, Expected),
      'var-olevariant-utf8-unicode-property');

    Source.Value := '';
    Value := Source.Value;
    Check(AcceptOleVariantUtf8(Value, ''),
      'var-olevariant-utf8-empty-variable');
    Check(AcceptOleVariantUtf8(Source.Value, ''),
      'var-olevariant-utf8-empty-property');
  finally
    Source.Free;
  end;
end;
{$endif}

{$ifdef HAS_VARIANT_DISTINCT_ORDINAL}
type
  TOmniUnixTime = type Int64;

function AcceptOmniUnixTime(const Value: TOmniUnixTime): Int64;
begin
  Result := Value;
end;

procedure RunVariantDistinctOrdinalForms;
var
  OleValue: OleVariant;
  Value: Variant;
begin
  OleValue := Int64(1723456789);
  Value := Int64(-1723456789);
  Check(AcceptOmniUnixTime(OleValue) = 1723456789,
    'variant-distinct-int64-olevariant');
  Check(AcceptOmniUnixTime(Value) = -1723456789,
    'variant-distinct-int64-variant');
end;
{$endif}

{ ---------------------------------------------------------------- }

type
  TMoonQualifiedException = class(SysUtils.Exception);
  TMoonUnsignedColor = type Cardinal;
  TMoonSignedColor = Integer;

var
  MoonSigned64: Int64 = $B0BA0AF1E6CABFE6;
  MoonColorCast: TMoonSignedColor = TMoonUnsignedColor($FF800080);
  MoonColorDirect: TMoonSignedColor = $FF0080FF;

procedure RunMoonBotStaticAndQualifiedForms;
var
  E: TMoonQualifiedException;
begin
  { MoonBot qualifies FMX ancestors with their declaring unit name. }
  E := TMoonQualifiedException.Create('qualified');
  try
    Check(E.Message = 'qualified', 'moonbot-qualified-ancestor');
  finally
    E.Free;
  end;

  { Production lock backoff uses both static TThread calls. }
  TThread.Yield;
  TThread.Sleep(0);
  Check(True, 'moonbot-thread-static-calls');

  { MoonBot uses high-bit hexadecimal literals as exact bit patterns with
    range checking disabled in the Delphi project. }
  Check(UInt64(MoonSigned64) = UInt64($B0BA0AF1E6CABFE6),
    'moonbot-signed-hex-int64');
  Check(Cardinal(MoonColorCast) = Cardinal($FF800080),
    'moonbot-signed-hex-distinct-cast');
  Check(Cardinal(MoonColorDirect) = Cardinal($FF0080FF),
    'moonbot-signed-hex-direct');
  Mix(31);
  Mix(UInt64(MoonSigned64));
  Mix(Cardinal(MoonColorCast));
  Mix(Cardinal(MoonColorDirect));
end;

{ ---------------------------------------------------------------- }
{ MoonBot composite forms, round 2. These are not isolated syntax  }
{ probes: each section combines the same lowering/lifetime axes     }
{ that meet in the production registry, caches and worker paths.    }
{ ---------------------------------------------------------------- }

type
  TMoonNotifyCode = procedure(AInstance, Sender: TObject);

function MoonAttributeValue(ARttiType: TRttiType;
  AAttributeClass: TClass): Integer;
var
  Attribute: TCustomAttribute;
begin
  Result := -1;
  for Attribute in ARttiType.GetAttributes do
    if Attribute.ClassType.InheritsFrom(AAttributeClass) then
    begin
      if Attribute is TMoonGroupAttribute then
        Result := TMoonGroupAttribute(Attribute).Value
      else if Attribute is TMoonIdAttribute then
        Result := TMoonIdAttribute(Attribute).Value;
      Exit;
    end;
end;

function MoonInheritedGroup(ARttiType: TRttiType): Integer;
begin
  Result := -1;
  while ARttiType <> nil do
  begin
    Result := MoonAttributeValue(ARttiType, TMoonGroupAttribute);
    if Result >= 0 then
      Exit;
    ARttiType := ARttiType.BaseType;
  end;
end;

function MoonFindRttiType(const Types: TArray<TRttiType>;
  ATypeInfo: Pointer): TRttiType;
var
  RttiType: TRttiType;
begin
  Result := nil;
  for RttiType in Types do
    if RttiType.Handle = ATypeInfo then
      Exit(RttiType);
end;

procedure RunMoonRttiCompositeForms;
var
  Context: TRttiContext;
  Types: TArray<TRttiType>;
  RttiType, BaseType, CatalogBaseType: TRttiType;
  InstanceType: TRttiInstanceType;
  CommandClass: TMoonRttiCommandClass;
  Command: TMoonRttiCommand;
  Field, NameField, CountField, SecretField: TRttiField;
  Method, PublicMethod, CatalogPublicMethod: TRttiMethod;
  Snapshot: TDictionary<TRttiField, TValue>;
  Pair: TPair<TRttiField, TValue>;
  PublicCount: Integer;
begin
  Context := TRttiContext.Create;
  Snapshot := TDictionary<TRttiField, TValue>.Create;
  try
    Types := Context.GetTypes;
    RttiType := MoonFindRttiType(Types, TypeInfo(TMoonRttiLeaf));
    Check(RttiType is TRttiInstanceType, 'moon-rtti-catalog-leaf');
    if not (RttiType is TRttiInstanceType) then
      Exit;

    InstanceType := TRttiInstanceType(RttiType);
    Check(InstanceType.MetaclassType.InheritsFrom(TMoonRttiCommand),
      'moon-rtti-metaclass-parent');
    Check(MoonAttributeValue(RttiType, TMoonIdAttribute) = 13,
      'moon-rtti-direct-id');
    Check(MoonInheritedGroup(RttiType) = 7,
      'moon-rtti-inherited-group');

    CommandClass := TMoonRttiCommandClass(InstanceType.MetaclassType);
    Command := CommandClass.Create;
    try
      Check(Command.ClassType = TMoonRttiLeaf, 'moon-rtti-meta-create');
      Check(CommandClass.Kind = 13, 'moon-rtti-meta-virtual-class-call');
      Check(TMoonRttiLeaf(Command).Extra, 'moon-rtti-leaf-field-init');

      BaseType := Context.GetType(TypeInfo(TMoonRttiCommand));
      Check(BaseType <> nil, 'moon-rtti-direct-base');
      if BaseType = nil then
        Exit;
      CatalogBaseType := MoonFindRttiType(Types, TypeInfo(TMoonRttiCommand));
      Check(CatalogBaseType <> nil, 'moon-rtti-catalog-base');
      NameField := BaseType.GetField('Name');
      CountField := BaseType.GetField('Count');
      SecretField := BaseType.GetField('FSecret');
      Check((NameField <> nil) and (CountField <> nil) and
        (SecretField <> nil), 'moon-rtti-explicit-fields');
      if (NameField = nil) or (CountField = nil) or (SecretField = nil) then
        Exit;
      Check(SecretField.Visibility = mvPrivate,
        'moon-rtti-private-visibility');
      Check(SecretField.GetValue(Command).AsInteger = 11,
        'moon-rtti-private-getvalue');

      PublicCount := 0;
      for Field in BaseType.GetFields do
        if Field.Visibility = mvPublic then
        begin
          Snapshot.Add(Field, Field.GetValue(Command));
          Inc(PublicCount);
        end;
      Check(PublicCount = 2, 'moon-rtti-public-field-count');

      NameField.SetValue(Command, TValue.From<string>('changed'));
      CountField.SetValue(Command, TValue.From<Int64>(100));
      Check((Command.Name = 'changed') and (Command.Count = 100),
        'moon-rtti-tvalue-set');
      for Pair in Snapshot do
        Pair.Key.SetValue(Command, Pair.Value);
      Check((Command.Name = 'base') and (Command.Count = 20),
        'moon-rtti-dictionary-restore');

      Method := BaseType.GetMethod('Fire');
      Check((Method <> nil) and (Method.CodeAddress <> nil),
        'moon-rtti-method-code-address');
      if (Method <> nil) and (Method.CodeAddress <> nil) then
        TMoonNotifyCode(Method.CodeAddress)(Command, Command);
      Check((Command.Name = 'base-fired') and (Command.Count = 43),
        'moon-rtti-code-address-call');

      PublicMethod := BaseType.GetMethod('PublicFire');
      CatalogPublicMethod := nil;
      if CatalogBaseType <> nil then
        CatalogPublicMethod := CatalogBaseType.GetMethod('PublicFire');
      Check(PublicMethod <> nil, 'moon-rtti-public-method-direct-visible');
      Check(CatalogPublicMethod <> nil,
        'moon-rtti-public-method-catalog-visible');
      Check((PublicMethod <> nil) and (PublicMethod.CodeAddress <> nil),
        'moon-rtti-public-method-code-address');
      if (PublicMethod <> nil) and (PublicMethod.CodeAddress <> nil) then
        TMoonNotifyCode(PublicMethod.CodeAddress)(Command, Command);
      Check((Command.Name = 'base-fired-public') and (Command.Count = 72),
        'moon-rtti-public-code-address-call');
    finally
      Command.Free;
    end;
  finally
    Snapshot.Free;
    Context.Free;
  end;
  Mix(UInt64(PublicCount));
end;

type
  TMoonFlagList = array of Boolean;

  TMoonCacheObject = class
  public
    class var Alive: Integer;
    Value: Integer;
    constructor Create(AValue: Integer);
    destructor Destroy; override;
  end;

  TMoonManagedCache = class
  private
    FFlags: TDictionary<string, TMoonFlagList>;
    FObjects: TObjectDictionary<string, TMoonCacheObject>;
  public
    constructor Create;
    destructor Destroy; override;
    function FlagsFor(const Key: string): TMoonFlagList;
    function ObjectFor(const Key: string): TMoonCacheObject;
  end;

constructor TMoonCacheObject.Create(AValue: Integer);
begin
  inherited Create;
  Inc(Alive);
  Value := AValue;
end;

destructor TMoonCacheObject.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

constructor TMoonManagedCache.Create;
begin
  inherited Create;
  FFlags := TDictionary<string, TMoonFlagList>.Create;
  FObjects := TObjectDictionary<string, TMoonCacheObject>.Create([doOwnsValues]);
end;

destructor TMoonManagedCache.Destroy;
begin
  FFlags.Free;
  FObjects.Free;
  inherited Destroy;
end;

function TMoonManagedCache.FlagsFor(const Key: string): TMoonFlagList;
var
  I: Integer;
begin
  if FFlags.TryGetValue(Key, Result) then
    Exit;
  SetLength(Result, Length(Key) + 2);
  for I := 0 to High(Result) do
    Result[I] := ((I + Length(Key)) and 1) = 0;
  FFlags.Add(Key, Result);
end;

function TMoonManagedCache.ObjectFor(const Key: string): TMoonCacheObject;
begin
  if FObjects.TryGetValue(Key, Result) then
    Exit;
  Result := TMoonCacheObject.Create(Length(Key) * 10);
  FObjects.Add(Key, Result);
end;

procedure RunMoonManagedCacheForms;
var
  Cache: TMoonManagedCache;
  Shared, CopyFlags: TMoonFlagList;
  Obj1, Obj2: TMoonCacheObject;
  I, TrueCount: Integer;
begin
  Check(TMoonCacheObject.Alive = 0, 'moon-cache-object-clean-start');
  Cache := TMoonManagedCache.Create;
  try
    Shared := Cache.FlagsFor('CAT');
    CopyFlags := Copy(Cache.FlagsFor('CAT'));
    Check((Length(Shared) = 5) and (Length(CopyFlags) = 5),
      'moon-cache-result-through-trygetvalue');
    CopyFlags[0] := not CopyFlags[0];
    Check(Shared[0] <> CopyFlags[0], 'moon-cache-explicit-copy-isolation');

    TrueCount := 0;
    for I := 0 to High(Shared) do
      if Shared[I] then
        Inc(TrueCount);
    Check(TrueCount = 2, 'moon-cache-flags-oracle');

    Obj1 := Cache.ObjectFor('BTC');
    Obj2 := Cache.ObjectFor('BTC');
    Check((Obj1 = Obj2) and (Obj1.Value = 30),
      'moon-cache-owned-object-identity');
    Check(TMoonCacheObject.Alive = 1, 'moon-cache-owned-object-alive');
  finally
    Cache.Free;
  end;
  Check(TMoonCacheObject.Alive = 0, 'moon-cache-owned-object-release');
  Mix(UInt64(UInt32(TrueCount)));
end;

{$ifdef HAS_INLINEVAR}
type
  PMoonManagedRow = ^TMoonManagedRow;
  TMoonManagedRow = record
    Id: Integer;
    Text: AnsiString;
    Values: TArray<Integer>;
    Token: IInterface;
  end;
  TMoonManagedRows = TArray<TMoonManagedRow>;

  TMoonRowHolder = class
  private
    FRows: TMoonManagedRows;
  public
    property Rows: TMoonManagedRows read FRows write FRows;
  end;

function ExerciseMoonManagedArray: UInt64;
var
  Holder: TMoonRowHolder;
  Rows, AliasRows: TMoonManagedRows;
  Pointers: TArray<PMoonManagedRow>;
  Row: TMoonManagedRow;
  I, Sum: Integer;
begin
  Result := 0;
  Holder := TMoonRowHolder.Create;
  try
    SetLength(Rows, 0);
    for I := 0 to 7 do
    begin
      Row := Default(TMoonManagedRow);
      Row.Id := I;
      Row.Text := AnsiString('row-') + AnsiString(IntToStr(I));
      Row.Values := [I, I * I, I + 10];
      Row.Token := TMLifeObj.Create;
      Rows := Rows + [Row];
    end;

    for I := 0 to Length(Rows) div 2 - 1 do
    begin
      var Temp := Rows[I];
      Rows[I] := Rows[High(Rows) - I];
      Rows[High(Rows) - I] := Temp;
    end;

    Holder.Rows := Rows;
    Rows := nil;
    AliasRows := Holder.Rows;
    SetLength(Pointers, Length(AliasRows));
    for I := 0 to High(AliasRows) do
      Pointers[I] := @AliasRows[I];

    Sum := 0;
    for var P in Pointers do
    begin
      Check(P <> nil, 'moon-array-pointer-forin-non-nil');
      Check(P^.Id = 7 - Sum, 'moon-array-inline-swap-order');
      Check(P^.Text = AnsiString('row-') + AnsiString(IntToStr(P^.Id)),
        'moon-array-managed-text');
      Check((Length(P^.Values) = 3) and
        (P^.Values[1] = P^.Id * P^.Id), 'moon-array-managed-values');
      Inc(Sum);
    end;
    Check(Sum = 8, 'moon-array-pointer-forin-count');
    Check(TMLifeObj.Alive = 8, 'moon-array-singleton-concat-lifetime');
    Result := UInt64(Sum * 100 + AliasRows[0].Id * 10 + AliasRows[7].Id);
  finally
    Holder.Free;
  end;
end;

procedure RunMoonManagedArrayForms;
var
  Digest: UInt64;
begin
  Check(TMLifeObj.Alive = 0, 'moon-array-clean-start');
  Digest := ExerciseMoonManagedArray;
  Check(Digest = 870, 'moon-array-explicit-oracle');
  Check(TMLifeObj.Alive = 0, 'moon-array-all-managed-released');
  Mix(Digest);
end;
{$endif}

type
  TMoonRing<T> = class(TEnumerable<T>)
  private
    FBuffer: TArray<T>;
    FCount: Integer;
    FPos: Integer;
  protected
    function DoGetEnumerator: Generics.Collections.TEnumerator<T>; override;
  public
    type
      TEnumerator = class(Generics.Collections.TEnumerator<T>)
      private
        FRing: TMoonRing<T>;
        FIndex: Integer;
        FRead: Integer;
      protected
        function DoGetCurrent: T; override;
        function DoMoveNext: Boolean; override;
      public
        constructor Create(ARing: TMoonRing<T>);
        function GetCurrent: T;
        function MoveNext: Boolean;
        property Current: T read GetCurrent;
      end;
    constructor Create(ACapacity: Integer);
    destructor Destroy; override;
    procedure Add(const Value: T);
    procedure Clear;
    function GetEnumerator: TEnumerator; reintroduce;
    property Count: Integer read FCount;
  end;

constructor TMoonRing<T>.Create(ACapacity: Integer);
begin
  inherited Create;
  SetLength(FBuffer, ACapacity);
end;

destructor TMoonRing<T>.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TMoonRing<T>.Add(const Value: T);
begin
  FBuffer[FPos] := Value;
  FPos := (FPos + 1) mod Length(FBuffer);
  if FCount < Length(FBuffer) then
    Inc(FCount);
end;

procedure TMoonRing<T>.Clear;
begin
  FBuffer := nil;
  FCount := 0;
  FPos := 0;
end;

function TMoonRing<T>.DoGetEnumerator:
  Generics.Collections.TEnumerator<T>;
begin
  Result := TMoonRing<T>.TEnumerator.Create(Self);
end;

function TMoonRing<T>.GetEnumerator: TEnumerator;
begin
  Result := TMoonRing<T>.TEnumerator.Create(Self);
end;

constructor TMoonRing<T>.TEnumerator.Create(ARing: TMoonRing<T>);
begin
  inherited Create;
  FRing := ARing;
  FRead := 0;
  FIndex := (FRing.FPos - FRing.FCount + Length(FRing.FBuffer)) mod
    Length(FRing.FBuffer) - 1;
end;

function TMoonRing<T>.TEnumerator.DoGetCurrent: T;
begin
  Result := FRing.FBuffer[FIndex];
end;

function TMoonRing<T>.TEnumerator.GetCurrent: T;
begin
  Result := DoGetCurrent;
end;

function TMoonRing<T>.TEnumerator.DoMoveNext: Boolean;
begin
  Result := FRead < FRing.FCount;
  if Result then
  begin
    FIndex := (FIndex + 1) mod Length(FRing.FBuffer);
    Inc(FRead);
  end;
end;

function TMoonRing<T>.TEnumerator.MoveNext: Boolean;
begin
  Result := DoMoveNext;
end;

type
  TMoonRingItem = record
    Seq: Integer;
    Text: AnsiString;
    Values: TArray<Integer>;
    Token: IInterface;
  end;

function ExerciseMoonGenericRing: UInt64;
var
  Ring: TMoonRing<TMoonRingItem>;
  Item, Current: TMoonRingItem;
  I, Expected, Seen: Integer;
begin
  Result := 0;
  Ring := TMoonRing<TMoonRingItem>.Create(4);
  try
    for I := 0 to 9 do
    begin
      Item := Default(TMoonRingItem);
      Item.Seq := I;
      Item.Text := AnsiString('ring-') + AnsiString(IntToStr(I));
      Item.Values := [I, I + 100];
      Item.Token := TMLifeObj.Create;
      Ring.Add(Item);
    end;
    Check((Ring.Count = 4) and (TMLifeObj.Alive = 4),
      'moon-ring-overwrite-finalization');

    Expected := 6;
    Seen := 0;
    for Current in Ring do
    begin
      Check(Current.Seq = Expected, 'moon-ring-nested-enumerator-order');
      Check((Current.Text = AnsiString('ring-') +
        AnsiString(IntToStr(Expected))) and
        (Current.Values[1] = Expected + 100),
        'moon-ring-managed-current');
      Result := Result * 17 + UInt64(Current.Seq);
      Inc(Expected);
      Inc(Seen);
    end;
    Check(Seen = 4, 'moon-ring-nested-enumerator-count');
  finally
    Ring.Free;
  end;
end;

procedure RunMoonGenericRingForms;
var
  Digest: UInt64;
begin
  Check(TMLifeObj.Alive = 0, 'moon-ring-clean-start');
  Digest := ExerciseMoonGenericRing;
  Check(Digest = 31646, 'moon-ring-explicit-digest');
  Check(TMLifeObj.Alive = 0, 'moon-ring-all-managed-released');
  Mix(Digest);
end;

{$ifdef HAS_ANON}
type
  TMoonPacket = record
    Id: Integer;
    Text: AnsiString;
    Values: TArray<Integer>;
    Token: IInterface;
  end;
  TMoonPacketProc = reference to procedure(const Packet: TMoonPacket);

  TMoonPacketWorker = class(TThread)
  private
    FWorkerId: Integer;
    FPublish: TMoonPacketProc;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWorkerId: Integer; const APublish: TMoonPacketProc);
    property Error: string read FError;
  end;

constructor TMoonPacketWorker.Create(AWorkerId: Integer;
  const APublish: TMoonPacketProc);
begin
  inherited Create(True);
  FWorkerId := AWorkerId;
  FPublish := APublish;
end;

procedure TMoonPacketWorker.Execute;
var
  Packet: TMoonPacket;
  I: Integer;
begin
  try
    for I := 0 to 15 do
    begin
      Packet := Default(TMoonPacket);
      Packet.Id := FWorkerId * 16 + I;
      Packet.Text := AnsiString('packet-') + AnsiString(IntToStr(Packet.Id));
      Packet.Values := [FWorkerId, I, Packet.Id * Packet.Id];
      Packet.Token := TInterfacedObject.Create;
      FPublish(Packet);
    end;
  except
    on E: Exception do
      FError := E.ClassName + ': ' + E.Message;
  end;
end;

function ExerciseMoonMonitorCallback: UInt64;
var
  LockObject: TObject;
  Packets: TList<TMoonPacket>;
  Publish: TMoonPacketProc;
  Workers: array[0..3] of TMoonPacketWorker;
  Seen: array[0..63] of Boolean;
  Packet: TMoonPacket;
  I: Integer;
begin
  Result := 0;
  LockObject := TObject.Create;
  Packets := TList<TMoonPacket>.Create;
  try
    Publish := procedure(const Packet: TMoonPacket)
      begin
        TMonitor.Enter(LockObject);
        try
          Packets.Add(Packet);
        finally
          TMonitor.Exit(LockObject);
        end;
      end;

    for I := Low(Workers) to High(Workers) do
      Workers[I] := TMoonPacketWorker.Create(I, Publish);
    for I := Low(Workers) to High(Workers) do
      Workers[I].Start;
    for I := Low(Workers) to High(Workers) do
      Workers[I].WaitFor;

    for I := Low(Workers) to High(Workers) do
    begin
      Check(Workers[I].Error = '', 'moon-monitor-worker-no-error');
      Workers[I].Free;
    end;
    Publish := nil;

    Check(Packets.Count = 64, 'moon-monitor-callback-count');
    FillChar(Seen, SizeOf(Seen), 0);
    for Packet in Packets do
    begin
      Check((Packet.Id >= Low(Seen)) and (Packet.Id <= High(Seen)),
        'moon-monitor-packet-id-range');
      if (Packet.Id >= Low(Seen)) and (Packet.Id <= High(Seen)) then
      begin
        Check(not Seen[Packet.Id], 'moon-monitor-packet-id-unique');
        Seen[Packet.Id] := True;
      end;
      Check(Packet.Text = AnsiString('packet-') +
        AnsiString(IntToStr(Packet.Id)), 'moon-monitor-managed-text');
      Check((Length(Packet.Values) = 3) and
        (Packet.Values[2] = Packet.Id * Packet.Id),
        'moon-monitor-managed-array');
      Check(Packet.Token <> nil, 'moon-monitor-managed-interface');
      Result := Result + UInt64(Packet.Id + Packet.Values[0] * 100);
    end;
    for I := Low(Seen) to High(Seen) do
      Check(Seen[I], 'moon-monitor-all-ids-seen');
  finally
    Packets.Free;
    LockObject.Free;
  end;
end;

procedure RunMoonMonitorCallbackForms;
var
  Digest: UInt64;
begin
  Digest := ExerciseMoonMonitorCallback;
  Check(Digest = 11616, 'moon-monitor-order-independent-digest');
  Mix(Digest);
end;

type
  TMoonProcRef2 = reference to procedure;

  TMoonCountingException = class(Exception)
  public
    destructor Destroy; override;
  end;

var
  MoonExceptionDestroyCount: Integer;

destructor TMoonCountingException.Destroy;
begin
  Inc(MoonExceptionDestroyCount);
  inherited Destroy;
end;

procedure MoonInvoke(const AProc: TProcRef); inline;
begin
  AProc;
end;

procedure MoonInvokeCast(const AProc: TProcRef); inline;
begin
  TMoonProcRef2(AProc)();
end;

function MoonHasProc(const AProc: TProcRef): Boolean; inline;
begin
  Result := Assigned(AProc);
end;

procedure MoonCopyProc(const AProc: TProcRef; var ADest: TProcRef); inline;
begin
  ADest := AProc;
end;

procedure RunMoonExceptionCaptureForms;
var
  FirstProc,
  SecondProc,
  StoredProc,
  StoredCopy: TProcRef;
  FirstSeen,
  SecondSeen: string;
  LocalValue,
  Count: Integer;
begin
  MoonExceptionDestroyCount := 0;
  LocalValue := 17;
  try
    raise TMoonCountingException.Create('captured');
  except
    on E: TMoonCountingException do begin
      FirstProc :=
        procedure
        begin
          if E = nil then
            FirstSeen := 'nil'
          else
            FirstSeen := E.Message + ':' + IntToStr(LocalValue);
        end;
      SecondProc :=
        procedure
        begin
          if E = nil then
            SecondSeen := 'nil'
          else
            SecondSeen := E.Message;
        end;
      FirstProc;
      Check(FirstSeen = 'captured:17',
        'moon-exception-captured-value-before-mutation');
      E := nil;
      FirstProc;
      SecondProc;
    end;
  end;
  Check(FirstSeen = 'nil', 'moon-exception-shared-slot-mutation');
  Check(SecondSeen = 'nil', 'moon-exception-second-closure-slot');
  Check(MoonExceptionDestroyCount = 1,
    'moon-exception-hidden-owner-destroys-once');

  Count := 0;
  StoredProc :=
    procedure
    begin
      Inc(Count);
    end;
  MoonInvoke(StoredProc);
  MoonInvokeCast(StoredProc);
  Check(MoonHasProc(StoredProc), 'moon-funcref-assigned-inline');
  MoonCopyProc(StoredProc, StoredCopy);
  Check(Assigned(StoredCopy), 'moon-funcref-copy-inline');
  Check(Count = 2, 'moon-funcref-invoke-oracle');
  Mix(UInt64(UInt32(LocalValue + Count)));
end;
{$endif}

{ ---------------------------------------------------------------- }

function OmniCharOrRaw(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function OmniCharOrRaw(const Value: RawByteString): Byte; overload;
begin
  Result := 2;
end;

function OmniCharOrUnicode(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function OmniCharOrUnicode(const Value: UnicodeString): Byte; overload;
begin
  Result := 2;
end;

function OmniAnsiOrWide(const Value: AnsiChar): Byte; overload;
begin
  Result := 1;
end;

function OmniAnsiOrWide(const Value: WideChar): Byte; overload;
begin
  Result := 2;
end;

function OmniWideOrRaw(const Value: WideChar): Byte; overload;
begin
  Result := 1;
end;

function OmniWideOrRaw(const Value: RawByteString): Byte; overload;
begin
  Result := 2;
end;

function OmniReturnWide(Value: WideChar): WideChar;
begin
  Result := Value;
end;

procedure RunDelphiCharacterOverloadForms;
const
  NamedAscii = 'A';
  NamedWide = #$2603;
var
  A: AnsiChar;
  W: WideChar;
  R: RawByteString;
  WideTable: array[0..1] of WideChar;
begin
  { Delphi treats an ordinal character constant as a character argument
    before considering any string conversion, even above the AnsiChar range. }
  Check(OmniCharOrRaw(#0) = 1, 'litov-char-raw-nul');
  Check(OmniCharOrRaw(#$7f) = 1, 'litov-char-raw-ascii-edge');
  Check(OmniCharOrRaw(#$80) = 1, 'litov-char-raw-high-bit');
  Check(OmniCharOrRaw(#$ff) = 1, 'litov-char-raw-byte-edge');
  Check(OmniCharOrRaw(#$100) = 1, 'litov-char-raw-wide-edge');
  Check(OmniCharOrRaw(#$2603) = 1, 'litov-char-raw-nonascii');
  Check(OmniCharOrRaw(NamedAscii) = 1, 'litov-char-raw-named-ascii');
  Check(OmniCharOrRaw(NamedWide) = 1, 'litov-char-raw-named-wide');
  Check(OmniCharOrRaw(Chr(65)) = 1, 'litov-char-raw-folded-chr');
  Check(OmniCharOrUnicode(#0) = 1, 'litov-char-unicode-nul');
  Check(OmniCharOrUnicode(#$2603) = 1, 'litov-char-unicode-wide');
  Check(OmniAnsiOrWide('A') = 2, 'litov-ansi-wide-literal');
  Check(OmniAnsiOrWide(#$2603) = 2, 'litov-ansi-wide-nonascii');
  Check(OmniWideOrRaw(#0) = 1, 'litov-wide-raw-nul');
  Check(OmniWideOrRaw(#$2603) = 1, 'litov-wide-raw-nonascii');

  { A non-constant WideChar expression follows Delphi's different rule:
    against AnsiChar it uses the string candidate, while an exact WideChar
    candidate still wins. This keeps the tie-breaker out of literal typing. }
  A := 'A';
  W := #$2603;
  R := 'raw';
  WideTable[0] := W;
  WideTable[1] := 'Z';
  Check(OmniCharOrRaw(A) = 1, 'litov-char-raw-ansi-variable');
  Check(OmniCharOrRaw(W) = 2, 'litov-char-raw-wide-variable');
  Check(OmniCharOrRaw(OmniReturnWide(W)) = 2,
    'litov-char-raw-wide-result');
  Check(OmniCharOrRaw(WideTable[Integer(RtZero)]) = 2,
    'litov-char-raw-wide-indexed');
  Check(OmniCharOrRaw(R) = 2, 'litov-char-raw-string-variable');
  Check(OmniAnsiOrWide(W) = 2, 'litov-ansi-wide-variable');
  Check(OmniWideOrRaw(W) = 1, 'litov-wide-raw-variable');
  Mix(UInt64(A) xor (UInt64(W) shl 8) xor UInt64(Length(R)));
end;

{ A loop optimizer may replace indexed access with a bumped pointer only while
  the managed pointer stored in the string/dynamic-array variable is stable. }
procedure RunMutableStringBaseLoopForms;
var
  U: UnicodeString;
  A: AnsiString;
  D: array of Byte;
  I: Integer;
  Sum: Integer;
begin
  U := 'abcdefgh';
  Sum := 0;
  for I := 1 to 8 do
  begin
    Inc(Sum, Ord(U[I]));
    If I = 3 then
      U := 'ABCDEFGH';
  end;
  Check(Sum = 644, 'optloop-mutable-unicode-base');

  A := 'abcdefgh';
  Sum := 0;
  for I := 1 to 8 do
  begin
    Inc(Sum, Ord(A[I]));
    If I = 3 then
      A := 'ABCDEFGH';
  end;
  Check(Sum = 644, 'optloop-mutable-ansi-base');

  SetLength(D, 8);
  for I := 0 to High(D) do
    D[I] := Byte(I + 1);
  Sum := 0;
  for I := 0 to High(D) do
  begin
    Inc(Sum, D[I]);
    If I = 2 then
    begin
      SetLength(D, 12);
      D[3] := 40;
    end;
  end;
  Check(Sum = 72, 'optloop-mutable-dynarray-base');
  Mix(UInt64(UInt32(Sum)));
end;

var
  OmniWideSetCalls: Integer;

function OmniCountedWide(Value: Word): WideChar;
begin
  Inc(OmniWideSetCalls);
  Result := WideChar(Value);
end;

procedure RunWideCharSetMembershipForms;
var
  I: Integer;
  W: WideChar;
  Hits4, Hits5, HitsDense, HitsByte, HitsVariable: Integer;
  ByteSet: set of AnsiChar;
begin
  Hits4 := 0;
  Hits5 := 0;
  HitsDense := 0;
  HitsByte := 0;
  for I := 0 to 1000 do
  begin
    W := WideChar(I);
    If W in ['a', 'e', 'i', 'o'] then Inc(Hits4);
    If W in ['a', 'e', 'i', 'o', 'u'] then Inc(Hits5);
    If W in ['0'..'9', 'A'..'F', 'a'..'f', '_', '$', #$80..#$ff] then
      Inc(HitsDense);
    If W in [#$80..#$ff] then Inc(HitsByte);
  end;
  Check(Hits4 = 4, 'wide-set-four-ranges');
  Check(Hits5 = 5, 'wide-set-five-ranges');
  Check(HitsDense = 152, 'wide-set-dense-ranges');
  Check(HitsByte = 128, 'wide-set-byte-range');

  OmniWideSetCalls := 0;
  Check(not (OmniCountedWide($410) in ['a', 'e', 'i', 'o', 'u']),
    'wide-set-no-ansi-remap');
  Check(OmniWideSetCalls = 1, 'wide-set-single-evaluation');

  ByteSet := [AnsiChar(#$80)..AnsiChar(#$ff)];
  HitsVariable := 0;
  for I := 0 to 1000 do
    If WideChar(I) in ByteSet then Inc(HitsVariable);
  Check(HitsVariable = 128, 'wide-set-variable-byte-set');
  Mix(UInt64(UInt32(HitsDense + HitsVariable)));
end;

{ ---------------------------------------------------------------- }

procedure CheckOmniRawBytes(const Value: RawByteString;
  const Expected: array of Byte; const Name: AnsiString);
var
  I: Integer;
begin
  Check(Length(Value) = Length(Expected), Name + '-length');
  if Length(Value) <> Length(Expected) then
    Exit;
  for I := 0 to High(Expected) do
    Check(Byte(Value[I + 1]) = Expected[I], Name + '-byte-' + IntToStr(I));
end;

procedure RunRawByteConstantForms;
const
  ByteEf = AnsiChar($ef);
  ByteBb = AnsiChar($bb);
  ByteBf = AnsiChar($bf);
  Direct: RawByteString =
    AnsiChar($ef) + AnsiChar($bb) + AnsiChar($bf);
  Pair: RawByteString = AnsiChar($80) + AnsiChar($ff);
  NestedLeft: RawByteString =
    (AnsiChar($ef) + AnsiChar($bb)) + AnsiChar($bf);
  NestedRight: RawByteString =
    AnsiChar($ef) + (AnsiChar($bb) + AnsiChar($bf));
  Named: RawByteString = ByteEf + ByteBb + ByteBf;
  LiteralMixed: RawByteString = #$ef + AnsiChar($bb) + AnsiChar($bf);
  AsciiEdges: RawByteString =
    AnsiChar('A') + AnsiChar($80) + AnsiChar('Z');
begin
  CheckOmniRawBytes(Direct, [$ef, $bb, $bf], 'rawconst-direct');
  CheckOmniRawBytes(Pair, [$80, $ff], 'rawconst-pair');
  CheckOmniRawBytes(NestedLeft, [$ef, $bb, $bf], 'rawconst-left');
  CheckOmniRawBytes(NestedRight, [$ef, $bb, $bf], 'rawconst-right');
  CheckOmniRawBytes(Named, [$ef, $bb, $bf], 'rawconst-named');
  CheckOmniRawBytes(LiteralMixed, [$ef, $bb, $bf], 'rawconst-mixed');
  CheckOmniRawBytes(AsciiEdges, [$41, $80, $5a], 'rawconst-ascii-edges');
  Mix(UInt64(Byte(Direct[1])) or (UInt64(Byte(Direct[2])) shl 8) or
    (UInt64(Byte(Direct[3])) shl 16));
end;

{ ---------------------------------------------------------------- }

function OmniPickAnsiConcat(const V: AnsiString): Integer; overload;
begin
  Result := 1;
end;

function OmniPickAnsiConcat(const V: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

function OmniPickRawConcat(const V: RawByteString): Integer; overload;
begin
  Result := 1;
end;

function OmniPickRawConcat(const V: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

function OmniPickUtf8Concat(const V: UTF8String): Integer; overload;
begin
  Result := 1;
end;

function OmniPickUtf8Concat(const V: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

function OmniMakeAnsiConcat: AnsiString;
begin
  Result := 'f';
end;

function OmniRuntimeWideConcat(Value: Word): WideChar;
begin
  Result := WideChar(Value + Word(RtZero));
end;

procedure RunByteStringConcatDomainForms;
const
  NamedAnsi: AnsiString = 'a';
  NamedU8: UTF8String = 'u';
var
  A: AnsiString;
  Expected: AnsiString;
  R: RawByteString;
  U8, U8Value, ExpectedU8: UTF8String;
  U: UnicodeString;
  W: WideChar;
begin
  A := 'a';
  R := 'r';
  U8 := 'u';
  U := 'w';

  Check(OmniPickAnsiConcat(AnsiString('a') + 'b') = 2,
    'strdom-ansi-cast-plus-literal');
  Check(OmniPickAnsiConcat(AnsiString('a') + AnsiString('b')) = 1,
    'strdom-two-ansi-casts');
  Check(OmniPickAnsiConcat(NamedAnsi + 'b') = 1,
    'strdom-named-ansi-plus-literal');
  Check(OmniPickAnsiConcat(A + 'b') = 1,
    'strdom-ansi-var-plus-literal');
  Check(OmniPickAnsiConcat('b' + A) = 1,
    'strdom-literal-plus-ansi-var');
  Check(OmniPickAnsiConcat(OmniMakeAnsiConcat + 'b') = 1,
    'strdom-ansi-result-plus-literal');
  Check(OmniPickAnsiConcat(A + #233) = 1,
    'strdom-ansi-var-plus-char');
  Check(OmniPickAnsiConcat(A + #1081) = 1,
    'strdom-ansi-var-plus-wide-literal');
  Check(OmniPickAnsiConcat(A + WideChar(1081)) = 1,
    'strdom-ansi-var-plus-wide-cast');
  Check(OmniPickAnsiConcat(A + U) = 2,
    'strdom-ansi-plus-unicode-var');

  Check(OmniPickRawConcat(RawByteString('r') + 'b') = 2,
    'strdom-raw-cast-plus-literal');
  Check(OmniPickRawConcat(RawByteString('r') + RawByteString('b')) = 1,
    'strdom-two-raw-casts');
  Check(OmniPickRawConcat(R + 'b') = 1,
    'strdom-raw-var-plus-literal');
  Check(OmniPickRawConcat('b' + R) = 1,
    'strdom-literal-plus-raw-var');
  Check(OmniPickRawConcat(R + U) = 2,
    'strdom-raw-plus-unicode-var');

  Check(OmniPickUtf8Concat(UTF8String('u') + 'b') = 2,
    'strdom-utf8-cast-plus-literal');
  Check(OmniPickUtf8Concat(UTF8String('u') + UTF8String('b')) = 1,
    'strdom-two-utf8-casts');
  Check(OmniPickUtf8Concat(U8 + 'b') = 1,
    'strdom-utf8-var-plus-literal');
  Check(OmniPickUtf8Concat('b' + U8) = 1,
    'strdom-literal-plus-utf8-var');
  Check(OmniPickUtf8Concat(U8 + U) = 2,
    'strdom-utf8-plus-unicode-var');

  Check(Byte((A + #$85)[2]) = $85,
    'strdom-raw-byte-literal');
  Check((Byte((A + #$85#$86)[2]) = $85) and
    (Byte((A + #$85#$86)[3]) = $86),
    'strdom-raw-byte-literal-pair');
  Check(Byte((A + AnsiChar($85))[2]) = $85,
    'strdom-explicit-ansichar-byte');
  Check(Byte((A + AnsiChar('Z'))[2]) = Ord('Z'),
    'strdom-explicit-ansichar-quoted');
  W := OmniRuntimeWideConcat($85);
  Expected := A + W;
  Check(A + Chr($85) = Expected,
    'strdom-chr-uses-codepage');
  Expected := A + W;
  Check(A + WideChar($85) = Expected,
    'strdom-wide-cast-uses-codepage');

  U8 := 'u';
  U8Value := U8 + #$85;
  Check((StringCodePage(U8Value) = 65001) and
    (Length(U8Value) = 2) and (Byte(U8Value[2]) = $85),
    'strdom-utf8-runtime-single-byte');
  U8Value := U8 + AnsiChar($85);
  Check((StringCodePage(U8Value) = 65001) and
    (Length(U8Value) = 2) and (Byte(U8Value[2]) = $85),
    'strdom-utf8-runtime-ansichar');
  U8Value := NamedU8 + #$85;
  Check((Length(U8Value) = 2) and (Byte(U8Value[2]) = $85),
    'strdom-utf8-named-single-byte');
  ExpectedU8 := U8 + AnsiString(#$85#$86);
  Check(U8 + #$85#$86 = ExpectedU8,
    'strdom-utf8-runtime-pair-transcode');
  Check(NamedU8 + #$85#$86 = ExpectedU8,
    'strdom-utf8-named-pair-transcode');
  ExpectedU8 := U8 + AnsiString(#$85);
  Check(UTF8String('u') + #$85 = ExpectedU8,
    'strdom-utf8-folded-single-transcode');
  Check(UTF8String('u') + AnsiChar($85) = ExpectedU8,
    'strdom-utf8-folded-ansichar-transcode');
  ExpectedU8 := U8 + AnsiString(#$85#$86);
  Check(UTF8String('u') + #$85#$86 = ExpectedU8,
    'strdom-utf8-folded-pair-transcode');
end;

{ ---------------------------------------------------------------- }

type
  TOmniByteArray = array[0..255] of Byte;
  POmniByteArray = ^TOmniByteArray;
  TOmniWordArray = array[0..255] of Word;
  POmniWordArray = ^TOmniWordArray;

function OmniByteAddress(P: Pointer): Pointer; inline;
begin
  Result := @POmniByteArray(P)[PByte(P + 1)^ + 2];
end;

function OmniByteAddressConstLeft(P: Pointer): Pointer; inline;
begin
  Result := @POmniByteArray(P)[2 + PByte(P + 1)^];
end;

function OmniByteAddressSubtract(P: Pointer): Pointer; inline;
begin
  Result := @POmniByteArray(P)[PByte(P + 1)^ - (-2)];
end;

function OmniByteAddressFromOffsetBase(P: Pointer): Pointer; inline;
begin
  Result := @POmniByteArray(P + 3)[PByte(P + 1)^ + 2];
end;

function OmniWordAddress(P: Pointer): Pointer; inline;
begin
  Result := @POmniWordArray(P)[PByte(P + 1)^ + 2];
end;

{$push}{$Q-}
function OmniCardinalAddress(Base: PtrUInt; Index: Cardinal): PtrUInt;
{$ifdef FPC}noinline;{$endif}
begin
  Inc(Index, 2);
  Result := Base + Index;
end;
{$pop}

function OmniUInt64Address(Base: PtrUInt; Index: UInt64): PtrUInt;
{$ifdef FPC}noinline;{$endif}
begin
  Inc(Index, 2);
  Result := Base + Index;
end;

procedure RunPointerIndexOffsetForms;
var
  Buffer: array[0..511] of Byte;
  I: Integer;
  Base: PtrUInt;
begin
  Base := PtrUInt(@Buffer);
  for I := 0 to 200 do
  begin
    Buffer[1] := I;
    Check(PtrUInt(OmniByteAddress(@Buffer)) - Base = PtrUInt(I + 2),
      'lea-index-plus-right');
    Check(PtrUInt(OmniByteAddressConstLeft(@Buffer)) - Base = PtrUInt(I + 2),
      'lea-index-plus-left');
    Check(PtrUInt(OmniByteAddressSubtract(@Buffer)) - Base = PtrUInt(I + 2),
      'lea-index-sub-negative');
    Check(PtrUInt(OmniByteAddressFromOffsetBase(@Buffer)) - Base =
      PtrUInt(I + 5), 'lea-index-offset-base');
    Check(PtrUInt(OmniWordAddress(@Buffer)) - Base = PtrUInt((I + 2) * 2),
      'lea-index-scaled-word');
  end;
  Check(OmniCardinalAddress(Base, High(Cardinal)) - Base = 1,
    'lea-narrow-wrap-before-wide');
  Check(OmniUInt64Address(Base, 40) - Base = 42,
    'lea-wide-fold-control');
end;

procedure RunFunctionResultCounterForms;
type
  TResultGranularity = (rgUndefined, rgHour, rgDay, rgMonth, rgYear);
  TResultSignedIndex = -2 .. 0;
const
  GRANULARITY_MARKERS: array[rgDay .. rgYear] of Integer = (29, 30, 31);
  INTEGER_MARKERS: array[2 .. 4] of Integer = (42, 43, 44);
  SIGNED_MARKERS: array[TResultSignedIndex] of Integer = (52, 53, 54);

  function FindGranularity(Marker: Integer): TResultGranularity;
  begin
    for Result := rgDay to rgYear do
      if GRANULARITY_MARKERS[Result] = Marker then
        Exit;
    Result := rgUndefined;
  end;

  function FindInteger(Marker: Integer): Integer;
  begin
    for Result := 2 to 4 do
      if INTEGER_MARKERS[Result] = Marker then
        Exit;
    Result := -1;
  end;

  function FindIntegerBackward(Marker: Integer): Integer;
  begin
    for Result := 4 downto 2 do
      if INTEGER_MARKERS[Result] = Marker then
        Exit;
    Result := -1;
  end;

  function FindSigned(Marker: Integer): TResultSignedIndex;
  begin
    for Result := High(TResultSignedIndex) downto Low(TResultSignedIndex) do
      if SIGNED_MARKERS[Result] = Marker then
        Exit;
    Result := Low(TResultSignedIndex);
  end;

begin
  Check(FindGranularity(29) = rgDay, 'result-loop-enum-first');
  Check(FindGranularity(30) = rgMonth, 'result-loop-enum-middle');
  Check(FindGranularity(31) = rgYear, 'result-loop-enum-last');
  Check(FindGranularity(99) = rgUndefined, 'result-loop-enum-miss');
  Check(FindInteger(42) = 2, 'result-loop-int-first');
  Check(FindInteger(43) = 3, 'result-loop-int-middle');
  Check(FindInteger(44) = 4, 'result-loop-int-last');
  Check(FindInteger(99) = -1, 'result-loop-int-miss');
  Check(FindIntegerBackward(44) = 4, 'result-loop-backward-first');
  Check(FindIntegerBackward(43) = 3, 'result-loop-backward-middle');
  Check(FindIntegerBackward(42) = 2, 'result-loop-backward-last');
  Check(FindIntegerBackward(99) = -1, 'result-loop-backward-miss');
  Check(FindSigned(54) = 0, 'result-loop-signed-first');
  Check(FindSigned(53) = -1, 'result-loop-signed-middle');
  Check(FindSigned(52) = -2, 'result-loop-signed-last');
end;

{ ---------------------------------------------------------------- }

type
  TOmniNilItem = record
    Value: Integer;
  end;
  POmniNilItem = ^TOmniNilItem;
  PPOmniNilItem = ^POmniNilItem;
  TOmniNilHolder = record
    Item: POmniNilItem;
  end;

{$J-}
const
  OmniReadOnlyNilItem: POmniNilItem = nil;

{$J+}
const
  OmniWritableNilItem: POmniNilItem = nil;

function OmniPickNil(AValue: PPOmniNilItem): Integer; overload;
begin
  Result := 11;
end;

function OmniPickNil(var AValue: POmniNilItem): Integer; overload;
begin
  Result := 12;
end;

function OmniPickNilPointer(AValue: Pointer): Integer; overload;
begin
  Result := 21;
end;

function OmniPickNilPointer(var AValue: POmniNilItem): Integer; overload;
begin
  Result := 22;
end;

function OmniPickNilOut(AValue: Pointer): Integer; overload;
begin
  Result := 31;
end;

function OmniPickNilOut(out AValue: POmniNilItem): Integer; overload;
begin
  AValue := nil;
  Result := 32;
end;

procedure OmniCheckConstNilParameter(const AValue: POmniNilItem);
begin
  Check(OmniPickNilPointer(AValue) = 21, 'nil-var-const-parameter');
end;

procedure RunNilVarOverloadForms;
var
  Item: POmniNilItem;
  Outer: PPOmniNilItem;
  Holder: TOmniNilHolder;
  Items: array[0..0] of POmniNilItem;
begin
  Check(OmniPickNil(nil) = 11, 'nil-var-untyped-literal');
  Check(OmniPickNilPointer(nil) = 21, 'nil-var-pointer-literal');
  Check(OmniPickNilPointer(POmniNilItem(nil)) = 21,
    'nil-var-explicit-pointer-literal');
  Check(OmniPickNilPointer(OmniReadOnlyNilItem) = 21,
    'nil-var-readonly-pointer-constant');
  Check(OmniPickNilPointer(OmniWritableNilItem) = 22,
    'nil-var-writable-pointer-constant');
  Check(OmniPickNilOut(nil) = 31, 'nil-out-pointer-literal');
  OmniCheckConstNilParameter(nil);

  Item := nil;
  Check(OmniPickNilPointer(Item) = 22, 'nil-var-local-lvalue');
  Holder.Item := nil;
  Check(OmniPickNilPointer(Holder.Item) = 22, 'nil-var-field-lvalue');
  Items[0] := nil;
  Check(OmniPickNilPointer(Items[0]) = 22, 'nil-var-indexed-lvalue');
  Outer := @Item;
  Check(OmniPickNilPointer(Outer^) = 22, 'nil-var-deref-lvalue');
  Item := Pointer(1);
  Check(OmniPickNilOut(Item) = 32, 'nil-out-local-lvalue');
  Check(Item = nil, 'nil-out-local-written');
end;

{$ifdef HAS_INLINEVAR}
procedure RunExplicitForVarTypeForms;
type
  PLocalInteger = ^Integer;
var
  A,
  B,
  Count,
  Sum: Integer;
  Pointers: array[0..1] of PLocalInteger;
  Words: array[0..1] of string;
begin
  A := 13;
  B := 29;
  Pointers[0] := @A;
  Pointers[1] := @B;
  Words[0] := 'typed';
  Words[1] := 'loop';

  Sum := 0;
  for var Item: PLocalInteger in Pointers do
    Inc(Sum, Item^);
  Check(Sum = 42, 'for-var-explicit-pointer-type');

  Count := 0;
  for var Word: string in Words do
    Inc(Count, Length(Word));
  Check(Count = 9, 'for-var-explicit-managed-type');

  Sum := 0;
  for var I: Integer := 0 to High(Pointers) do
    Inc(Sum, Pointers[I]^);
  Check(Sum = 42, 'for-var-explicit-counted-type');
end;
{$endif}

{ ---------------------------------------------------------------- }

procedure ReadSeed;
var
  S: string;
  V: UInt64;
  Code: Integer;
begin
  RngState := DefaultSeed;
  if ParamCount > 0 then
  begin
    S := ParamStr(1);
    Val(S, V, Code);
    if Code = 0 then
      RngState := V;
  end;
  if RngState = 0 then
    RngState := DefaultSeed;
end;

var
  SeedShown: UInt64;
begin
  ReadSeed;
  Check(DelphiModeDefinesMatchTypes, 'mode-delphi-defines-match-types');
  SeedShown := RngState;
  RtZero := 0;
  if ParamCount >= 9 then
    RtZero := 1;                                 { never true in practice }
  { align the FP environment: Delphi Win64 masks everything by default,
    FPC Linux leaves exInvalidOp unmasked and dies on the NaN forms }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  InstallGeneratedFormsCheck(GeneratedCheckU);
  InstallGeneratedBreadthCheck(GeneratedCheckU);

  { mega side }
  RunNarrowIndexForms;
  RunGeneratedForms;
  RunGeneratedBreadthCoreForms;
  RunSetForms;
  RunCaseForms;
  RunFloatConvForms;
  RunCurrencyForms;
  RunRecordAbiForms;
  RunWideOpForms;
  RunDelphiCharacterOverloadForms;
  RunRawByteConstantForms;
  RunByteStringConcatDomainForms;
  RunPointerIndexOffsetForms;
  RunFunctionResultCounterForms;
  RunNilVarOverloadForms;
  RunStringCowForms;
  RunDispatchForms;
  RunFlowForms;
  RunOldSchoolForms;
  RunAdvancedRecordForms;
  RunVariantForms;
{$ifdef HAS_OLEVARIANT_UTF8}
  RunOleVariantUtf8Forms;
{$endif}
{$ifdef HAS_VARIANT_DISTINCT_ORDINAL}
  RunVariantDistinctOrdinalForms;
{$endif}
{$ifdef HAS_DELPHI_EQUALITY_COMPARER}
  RunDelphiEqualityComparerForms;
{$endif}
  RunFreestyleForms;
  RunManagedLifetimeForms1;
  RunManagedLifetimeForms2;
  RunThreadForms;
  RunWildRound2Forms;
  RunArithmeticControlForms;
  RunIntelAsmAbiForms;
  RunMoonBotStaticAndQualifiedForms;
  RunMoonRttiCompositeForms;
  RunMoonManagedCacheForms;
  RunMoonGenericRingForms;
  RunCollectionForms;
  RunDelegationForms;
  RunLoopStackForms;
  RunDelphiFeatureForms;
  RunFeatureSweep2Forms;
  RunCheckedForms;
  RunPublishedRttiForms;
  RunInterfacePlumbingForms;
  RunStringEdgeForms;
  RunParentFrameForms;
  RunClassMachineryForms;
  RunFloatBooleanForms;
  RunMemoryBoundaryForms;
  RunCheckedIndexForms;
  RunFinalizationForms;
  RunStructuralLifetimeForms;

  { zoo side }
  RunSliceZooForms;
  RunVarRecZooForms;
  RunGenericZooForms;
  RunIntfZooForms;
  RunEnumHoleForms;
  RunSubrangeForms;
  RunWithZooForms;
  RunStonedForms;
  RunNestedLinkForms;
  RunDynAliasForms;
  RunMetaZooForms;
  RunScopedEnumForms;
  RunConvChainForms;
  RunGenIntfForms;
  RunDeepCopyForms;
  RunConstRecForms;
  RunExcOrderForms;
  RunRotForms;
  RunLocalWtcForms;
  RunListForms;
  RunCaseCharForms;
  RunCaretForms;
  RunIndexPropForms;
  RunForInFuncCarrierForms;
  RunExitUnwindForms;
  RunFinallyRaiseForms;
  RunFrozenBoundForms;
  RunSetSnapshotForms;
  RunVarAliasForms;
  RunProcVarFlipForms;
  RunEhReentryForms;
  RunShortCircuitBraidForms;
  RunRepeatCondForms;
  RunTpObjectForms;
  RunHelperShadowForms;
  RunPtrEnumForms;
  RunClassCtorForms;
  RunRecNamespaceForms;
  RunRecPropForms;
  RunDistinctAliasForms;
  RunNoGuidIntfForms;
  RunAnonRecForms;
  RunGenericNestedForms;
  RunForwardCycleForms;
  RunPackedLayoutForms;
  RunInitFinForms;
  RunAllocZeroForms;
  RunSetBoundForms;
  RunNilStrForms;
  RunLoopPersistForms;
  RunMgdShiftForms;
  RunDeepFinForms;
  RunShrinkFinForms;
  RunStrLifeForms;
  RunRangeFinForms;
  RunMgdConcatForms;
  RunDefaultOperatorArrayForms;
  RunDefaultDeepForms;
  RunRareOperatorLoopForms;
  RunBigCarryForms;
  RunVmLoopForms;
  RunManagedChurnForms;
  RunRecManagedForms;
  RunPeanoOperatorForms;
  RunFixpLoopForms;
  RunNestChainForms;
  RunBitsStepForms;
  RunGOptChainForms;
  RunByteWordIndexForms;
  RunPtrLoopForms;
  RunStackHeapForms;
  RunThreadHandoffForms;
  RunWtcShiftForms;
  RunForInAliasForms;
  RunVaArgForms;
  RunThreadFatalForms;
  RunDecUntilForms;
  RunAbsPtrForms;
  RunHelperDefPropForms;
  RunSSEnumForms;
  RunMutableStringBaseLoopForms;
  RunWideCharSetMembershipForms;

  { assimilated compiler-slice }
  RunIssueSliceAForms;
  RunIssueSliceBForms;

  ModernMode := True;
{$ifdef HAS_ANON}
  RunGeneratedBreadthModernForms;
  RunAnonymousForms;
{$ifdef HAS_INLINEVAR}
  RunAnonymousPointerNewForms;
{$endif}
  RunComboModernForms;
  RunQueueClosureForms;
  RunExplicitAnonymousConstCastForms;
  RunMoonMonitorCallbackForms;
  RunMoonExceptionCaptureForms;
{$endif}
{$ifdef HAS_INLINEVAR}
  RunInlineVarForms;
  RunMoonManagedArrayForms;
  RunExplicitForVarTypeForms;
{$endif}
{$ifdef HAS_MREC}
  RunManagedRecForms;
{$endif}
{$ifdef HAS_FUNCOBJ}
  RunFuncObjForms;
  RunClosureFrameForms;
  RunClosureThreadForms;
  RunTpClosureForms;
  RunClosureMutualForms;
  RunIssueModernForms;
{$endif}
{$ifdef HAS_D12}
  RunD12SyntaxForms;
  RunMlCaretResForms;
{$endif}
{$ifdef HAS_HOPERS}
  RunHelperOperatorForms;
{$endif}
{$ifdef HAS_MULTIDEF}
  RunMultiDefaultForms;
{$endif}
{$ifdef HAS_RAREX}
  RunRareXOperatorForms;
{$endif}
  ModernMode := False;

  CoreDigest := (CoreDigest xor UInt64(CoreChecks)) * UInt64($100000001B3);
  ModernDigest := (ModernDigest xor UInt64(ModernChecks)) * UInt64($100000001B3);
  if FailureCount > 0 then
  begin
    WriteLn('FORMS_FAIL seed=', SeedShown, ' failures=', FailureCount,
      ' core_checks=', CoreChecks, ' core_digest=', IntToHex(CoreDigest, 16),
      ' modern_checks=', ModernChecks,
      ' modern_digest=', IntToHex(ModernDigest, 16));
    Halt(1);
  end;
  WriteLn('FORMS_PASS seed=', SeedShown,
    ' core_checks=', CoreChecks, ' core_digest=', IntToHex(CoreDigest, 16),
    ' modern_checks=', ModernChecks,
    ' modern_digest=', IntToHex(ModernDigest, 16));
end.
