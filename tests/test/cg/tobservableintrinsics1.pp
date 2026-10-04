{ %CPU=x86_64 }
{ %OPT=-O3 }

program tobservableintrinsics1;

{$mode delphiunicode}
{$INLINE ON}{$Q+}{$R+}

uses
  SysUtils,
  Math;

type
  TSmall = 1..5;
  TDoublePair = record
    First,
    Second: Double;
  end;
  PDoublePair = ^TDoublePair;
  TDoubleHolder = class
    Value: Double;
  end;
  TIntegerHolder = class
    Value: LongInt;
  end;
  TDistances = array[0..7] of LongWord;
  TWideDistances = array[0..7] of Int64;

var
  Counter: LongInt;

function AtomicDiscard: LongInt;
begin
  Result := AtomicIncrement(Counter) * 0;
end;

function AtomicPair: LongInt;
begin
  Result := AtomicIncrement(Counter) - AtomicIncrement(Counter);
end;

function VolatileDiscard: LongInt;
begin
  Result := Volatile(Counter) * 0;
end;

function CheckedAbsDiscard(Value: Int64): Int64;
begin
  Result := Abs(Value) - Abs(Value);
end;

function CheckedSuccDiscard(Value: TSmall): LongInt;
begin
  Result := Ord(Succ(Value)) - Ord(Succ(Value));
end;

function CheckedTruncDiscard(Value: Double): Int64;
begin
  Result := Trunc(Value) - Trunc(Value);
end;

function CheckedRoundDiscard(Value: Double): Int64;
begin
  Result := Round(Value) * 0;
end;

function InlineRoot(Value: Double): Double; inline;
begin
  Result := Sqrt(Value);
end;

{$if SizeOf(CExtended)>8}
function InlineCExtendedRoot(Value: CExtended): CExtended; inline;
begin
  Result := Sqrt(Value);
end;

function PrecisionSensitiveCExtendedRoot: CExtended; noinline;
begin
  Result := InlineCExtendedRoot(1.00000005960464566356904470012523233890533447265625);
end;

function ExactCExtendedRoot: CExtended; noinline;
begin
  Result := InlineCExtendedRoot(2.25);
end;

function RuntimeCExtendedRoot(Value: CExtended): CExtended; noinline;
begin
  Result := Sqrt(Value);
end;
{$endif}

function InlineProduct(Value: Double): Double; inline;
begin
  Result := Value * Value;
end;

function InlineRound(Value: Double): Int64; inline;
begin
  Result := Round(Value);
end;

function InlineSingle(Value: Double): Single; inline;
begin
  Result := Value;
end;

function InlineDouble(Value: Single): Double; inline;
begin
  Result := Value;
end;

{$if SizeOf(Extended)>8}
function InlineDoubleFromExtended(Value: Extended): Double; inline;
begin
  Result := Value;
end;
{$endif}

function ExactRoot: Double;
begin
  Result := InlineRoot(2.25);
end;

function ExactSubunitRoot: Double;
begin
  Result := InlineRoot(0.25);
end;

function IrrationalRoot: Double;
begin
  Result := InlineRoot(2.0);
end;

function ExactSingle: Single; noinline;
begin
  Result := InlineSingle(1.5);
end;

function RoundingSensitiveSingle: Single; noinline;
begin
  Result := InlineSingle(1.000000059604644775390625);
end;

function RuntimeSingle(Value: Double): Single; noinline;
begin
  Result := Value;
end;

function ExactDouble: Double; noinline;
begin
  Result := InlineDouble(1.5);
end;

function SubnormalSingleToDouble: Double; noinline;
begin
  Result := InlineDouble(1.40129846432481707092372958328991613e-45);
end;

function RuntimeDouble(Value: Single): Double; noinline;
begin
  Result := Value;
end;

function RuntimeMinDouble(A, B: Double): Double; noinline;
begin
  Result := Min(A, B);
end;

function RuntimeMaxDouble(A, B: Double): Double; noinline;
begin
  Result := Max(A, B);
end;

function RuntimeMinSingle(A, B: Single): Single; noinline;
begin
  Result := Min(A, B);
end;

function RuntimeMaxSingle(A, B: Single): Single; noinline;
begin
  Result := Max(A, B);
end;

function RuntimeFieldMin(P: PDoublePair; B: Double): Double; noinline;
begin
  Result := Min(P^.First, B);
end;

function RuntimeFieldMax(P: PDoublePair; B: Double): Double; noinline;
begin
  Result := Max(P^.Second, B);
end;

procedure UpdateObjectFieldMin(Holder: TDoubleHolder; Value: Double); noinline;
begin
  If Value < Holder.Value then
    Holder.Value := Value;
end;

procedure UpdateObjectFieldMax(Holder: TDoubleHolder; Value: Double); noinline;
begin
  If Value > Holder.Value then
    Holder.Value := Value;
end;

{ Integer operands that can raise: an array element (range check), a pointer
  target and a class field (nil).  The comparison evaluates them in both forms,
  so the update is a min/max (cmov), and the exception stays where it was. }
procedure UpdateElementMin(var Distances: TDistances; Index: LongInt;
  Candidate: LongWord); noinline;
begin
  If Candidate < Distances[Index] then
    Distances[Index] := Candidate;
end;

procedure UpdateElementMax(var Distances: TWideDistances; Index: LongInt;
  Candidate: Int64); noinline;
begin
  If Candidate > Distances[Index] then
    Distances[Index] := Candidate;
end;

procedure UpdateTargetMin(Target: PLongInt; Candidate: LongInt); noinline;
begin
  If Candidate < Target^ then
    Target^ := Candidate;
end;

procedure UpdateIntegerFieldMax(Holder: TIntegerHolder; Candidate: LongInt); noinline;
begin
  If Candidate > Holder.Value then
    Holder.Value := Candidate;
end;

function NextObservedInteger: LongInt; noinline;
begin
  Inc(Counter);
  Result := 5;
end;

procedure UpdateElementEffectful(var Distances: TDistances; Index: LongInt); noinline;
begin
  If LongWord(NextObservedInteger) < Distances[Index] then
    Distances[Index] := LongWord(NextObservedInteger);
end;

function NextObservedDouble: Double; noinline;
begin
  Inc(Counter);
  Result := 5.0;
end;

procedure UpdateObjectFieldEffectful(Holder: TDoubleHolder); noinline;
begin
  If NextObservedDouble < Holder.Value then
    Holder.Value := NextObservedDouble;
end;

{$if SizeOf(Extended)>8}
function RoundingSensitiveDouble: Double; noinline;
begin
  Result := InlineDoubleFromExtended(1.00000000000000011102230246251565404236316680908203125);
end;

function RuntimeDoubleFromExtended(Value: Extended): Double; noinline;
begin
  Result := Value;
end;
{$endif}

procedure DeferredRoot(Execute: Boolean);
var
  Value: Double;
begin
  If Execute then
    Value := InlineRoot(-1.0);
end;

procedure ExpectIntOverflow(Kind: LongInt);
var
  Value: Int64;
begin
  try
    case Kind of
      0: Value := CheckedAbsDiscard(Low(Int64));
    else
      Value := 0;
    end;
    If Value = 0 then
      Halt(10 + Kind);
  except
    on EIntOverflow do
      Exit;
  end;
  Halt(20 + Kind);
end;

procedure ExpectRangeError;
var
  Value: LongInt;
begin
  try
    Value := CheckedSuccDiscard(5);
    If Value = 0 then
      Halt(30);
  except
    on ERangeError do
      Exit;
  end;
  Halt(31);
end;

procedure ExpectInvalid(Kind: LongInt);
var
  Value: Int64;
  SavedMask: TFPUExceptionMask;
begin
  SavedMask := GetExceptionMask;
  SetExceptionMask(SavedMask - [exInvalidOp,exOverflow]);
  try
    try
      case Kind of
        0: Value := CheckedTruncDiscard(NaN);
        1: Value := CheckedRoundDiscard(NaN);
        2: begin DeferredRoot(True); Value := 0; end;
      else
        Value := 0;
      end;
      If Value = 0 then
        Halt(40 + Kind);
    except
      on EInvalidOp do
        Exit;
    end;
    Halt(50 + Kind);
  finally
    SetExceptionMask(SavedMask);
    ClearExceptions(False);
  end;
end;

procedure ExpectFPOverflow;
var
  Value: Double;
  SavedMask: TFPUExceptionMask;
begin
  SavedMask := GetExceptionMask;
  SetExceptionMask(SavedMask - [exOverflow]);
  try
    try
      Value := InlineProduct(1.0e308);
      If Value <> 0 then
        Halt(61);
    except
      on EOverflow do
        Exit;
    end;
    Halt(62);
  finally
    SetExceptionMask(SavedMask);
    ClearExceptions(False);
  end;
end;

function RuntimeRoot(Value: Double): Double; noinline;
begin
  Result := Sqrt(Value);
end;

{ Round stays at run time after inlining and follows the rounding mode.  An
  inexact root of an ordinary constant is folded in the FP state the product
  runs in (round to nearest), as a constant written in the source is: its
  value is the one the run-time root gives there; a program that changes the
  rounding mode does not see it change. }
procedure CheckRoundingMode;
var
  SavedMode: TFPURoundingMode;
begin
  SavedMode := GetRoundMode;
  try
    SetRoundMode(rmUp);
    If InlineRound(2.25) <> 3 then
      Halt(63);
    SetRoundMode(rmDown);
    If InlineRound(2.25) <> 2 then
      Halt(64);
    SetRoundMode(rmNearest);
    If TDoubleRec(IrrationalRoot).Data <> TDoubleRec(RuntimeRoot(2.0)).Data then
      Halt(65);
  finally
    SetRoundMode(SavedMode);
  end;
end;

procedure CheckInlineSqrtDenormal;
var
  SavedMXCSR,
  InlineStatus,
  RuntimeStatus: DWord;
  InlineValue,
  RuntimeValue,
  RuntimeInput: Double;
  InputBits: QWord;
  Daz: Boolean;
begin
  SavedMXCSR := GetMXCSR;
  try
    for Daz := False to True do
      begin
        SetMXCSR((SavedMXCSR or $1f80) and not DWord($7f));
        If Daz then
          SetMXCSR(GetMXCSR or $40);
        InlineValue := InlineRoot(4.94065645841246544176568792868221372e-324);
        InlineStatus := GetMXCSR and $3f;

        InputBits := 1;
        Move(InputBits, RuntimeInput, SizeOf(RuntimeInput));
        SetMXCSR((SavedMXCSR or $1f80) and not DWord($7f));
        If Daz then
          SetMXCSR(GetMXCSR or $40);
        RuntimeValue := InlineRoot(RuntimeInput);
        RuntimeStatus := GetMXCSR and $3f;
        If (TDoubleRec(InlineValue).Data <> TDoubleRec(RuntimeValue).Data) or
           (InlineStatus <> RuntimeStatus) then
          Halt(68 + Ord(Daz));
      end;
  finally
    SetMXCSR(SavedMXCSR);
  end;
end;

{$if SizeOf(CExtended)>8}
{ The x87 root is folded at the precision the product runs the x87 at (full
  64 bits): the run-time root at that precision. }
procedure CheckInlineSqrtPrecision;
var
  InlineValue,
  RuntimeInput,
  RuntimeValue: CExtended;
begin
  RuntimeInput:=1.00000005960464566356904470012523233890533447265625;
  InlineValue:=PrecisionSensitiveCExtendedRoot;
  RuntimeValue:=RuntimeCExtendedRoot(RuntimeInput);
  if InlineValue<>RuntimeValue then
    Halt(90);
  if ExactCExtendedRoot<>1.5 then
    Halt(94);
end;
{$endif}

{ An inexact conversion of an ordinary constant is folded in the product FP
  state (round to nearest): the value of the run-time conversion there.  A
  subnormal stays at run time: the value and the status flags of the inline
  conversion are those of the run-time one, with and without DAZ. }
procedure CheckInlineFPConversion;
var
  SavedMode: TFPURoundingMode;
  InlineValue,
  RuntimeValue: Single;
  InlineDoubleValue,
  RuntimeDoubleValue: Double;
  InlineStatus,
  RuntimeStatus,
  SavedMXCSR: DWord;
  RuntimeInput: Double;
  RuntimeSingleInput: Single;
  SingleBits: DWord;
  Daz: Boolean;
  {$if SizeOf(Extended)>8}
  RuntimeExtendedInput: Extended;
  {$endif}
begin
  If TSingleRec(ExactSingle).Data <> $3fc00000 then
    Halt(70);
  If TDoubleRec(ExactDouble).Data <> $3ff8000000000000 then
    Halt(71);
  RuntimeInput := 1.000000059604644775390625;
  SavedMode := GetRoundMode;
  SavedMXCSR := GetMXCSR;
  try
    SetRoundMode(rmNearest);
    InlineValue := RoundingSensitiveSingle;
    RuntimeValue := RuntimeSingle(RuntimeInput);
    If TSingleRec(InlineValue).Data <> TSingleRec(RuntimeValue).Data then
      Halt(72);

    {$if SizeOf(Extended)>8}
    RuntimeExtendedInput := 1.00000000000000011102230246251565404236316680908203125;
    InlineDoubleValue := RoundingSensitiveDouble;
    RuntimeDoubleValue := RuntimeDoubleFromExtended(RuntimeExtendedInput);
    If TDoubleRec(InlineDoubleValue).Data <> TDoubleRec(RuntimeDoubleValue).Data then
      Halt(76);
    {$endif}

    SingleBits := 1;
    Move(SingleBits,RuntimeSingleInput,SizeOf(RuntimeSingleInput));
    for Daz := False to True do
      begin
        SetMXCSR((SavedMXCSR or $1f80) and not DWord($7f));
        If Daz then
          SetMXCSR(GetMXCSR or $40);
        InlineDoubleValue := SubnormalSingleToDouble;
        InlineStatus := GetMXCSR and $3f;
        SetMXCSR((SavedMXCSR or $1f80) and not DWord($7f));
        If Daz then
          SetMXCSR(GetMXCSR or $40);
        RuntimeDoubleValue := RuntimeDouble(RuntimeSingleInput);
        RuntimeStatus := GetMXCSR and $3f;
        If (TDoubleRec(InlineDoubleValue).Data <> TDoubleRec(RuntimeDoubleValue).Data) or
           (InlineStatus <> RuntimeStatus) then
          Halt(80 + Ord(Daz));
      end;
  finally
    SetRoundMode(SavedMode);
    SetMXCSR(SavedMXCSR);
  end;
end;

procedure CheckIntegerMinMax;
var
  Distances: TDistances;
  Wide: TWideDistances;
  Holder: TIntegerHolder;
  Plain: LongInt;
  Raised: Boolean;
  I: LongInt;
begin
  for I := 0 to High(Distances) do
  begin
    Distances[I] := 100 + LongWord(I);
    Wide[I] := -100 - I;
  end;
  UpdateElementMin(Distances, 3, 7);
  UpdateElementMin(Distances, 4, 900);
  If (Distances[3] <> 7) or (Distances[4] <> 104) or (Distances[2] <> 102) then
    Halt(210);
  UpdateElementMax(Wide, 5, Int64(1) shl 40);
  UpdateElementMax(Wide, 6, -1000);
  If (Wide[5] <> Int64(1) shl 40) or (Wide[6] <> -106) then
    Halt(211);
  Raised := False;
  try
    UpdateElementMin(Distances, 8, 0);
  except
    on ERangeError do
      Raised := True;
  end;
  If not Raised then
    Halt(212);
  Raised := False;
  try
    UpdateElementMax(Wide, -1, High(Int64));
  except
    on ERangeError do
      Raised := True;
  end;
  If not Raised then
    Halt(213);
  Plain := 50;
  UpdateTargetMin(@Plain, 60);
  If Plain <> 50 then
    Halt(214);
  UpdateTargetMin(@Plain, -60);
  If Plain <> -60 then
    Halt(215);
  Raised := False;
  try
    UpdateTargetMin(nil, 1);
  except
    on EAccessViolation do
      Raised := True;
  end;
  If not Raised then
    Halt(216);
  Holder := TIntegerHolder.Create;
  try
    Holder.Value := 5;
    UpdateIntegerFieldMax(Holder, 4);
    If Holder.Value <> 5 then
      Halt(217);
    UpdateIntegerFieldMax(Holder, 6);
    If Holder.Value <> 6 then
      Halt(218);
  finally
    Holder.Free;
  end;
  Raised := False;
  try
    UpdateIntegerFieldMax(nil, 1);
  except
    on EAccessViolation do
      Raised := True;
  end;
  If not Raised then
    Halt(219);
  Counter := 0;
  Distances[1] := 9;
  UpdateElementEffectful(Distances, 1);
  If (Distances[1] <> 5) or (Counter <> 2) then
    Halt(220);
end;

procedure CheckRuntimeMinMax;
var
  Pair: TDoublePair;
  Holder: TDoubleHolder;
begin
  If RuntimeMinDouble(5.0, 7.0) <> 5.0 then
    Halt(197);
  If RuntimeMaxDouble(5.0, 7.0) <> 7.0 then
    Halt(198);
  If RuntimeMinSingle(5.0, 7.0) <> 5.0 then
    Halt(199);
  If RuntimeMaxSingle(5.0, 7.0) <> 7.0 then
    Halt(200);
  Pair.First := 5.0;
  Pair.Second := 7.0;
  If RuntimeFieldMin(@Pair, 7.0) <> 5.0 then
    Halt(201);
  If RuntimeFieldMax(@Pair, 5.0) <> 7.0 then
    Halt(202);
  Holder := TDoubleHolder.Create;
  try
    Holder.Value := 7.0;
    UpdateObjectFieldMin(Holder, 5.0);
    If Holder.Value <> 5.0 then
      Halt(203);
    UpdateObjectFieldMax(Holder, 9.0);
    If Holder.Value <> 9.0 then
      Halt(204);
    Counter := 0;
    UpdateObjectFieldEffectful(Holder);
    If (Holder.Value <> 5.0) or (Counter <> 2) then
      Halt(205);
  finally
    Holder.Free;
  end;
  try
    UpdateObjectFieldMin(nil, 5.0);
  except
    on EAccessViolation do
      Exit;
  end;
  Halt(206);
end;

begin
  Counter := 0;
  If AtomicDiscard <> 0 then
    Halt(1);
  If Counter <> 1 then
    Halt(2);
  If AtomicPair <> -1 then
    Halt(3);
  If Counter <> 3 then
    Halt(4);
  If VolatileDiscard <> 0 then
    Halt(5);

  ExpectIntOverflow(0);
  ExpectRangeError;
  DeferredRoot(False);
  ExpectInvalid(0);
  ExpectInvalid(1);
  ExpectInvalid(2);
  ExpectFPOverflow;
  CheckRoundingMode;
  CheckInlineSqrtDenormal;
  {$if SizeOf(CExtended)>8}
  CheckInlineSqrtPrecision;
  {$endif}
  CheckInlineFPConversion;
  CheckRuntimeMinMax;
  CheckIntegerMinMax;

  If ExactRoot <> 1.5 then
    Halt(66);
  If ExactSubunitRoot <> 0.5 then
    Halt(67);

  If (17 - 17 <> 0) or (17 * 0 <> 0) then
    Halt(60);
end.
