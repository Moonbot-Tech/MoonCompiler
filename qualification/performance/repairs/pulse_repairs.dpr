program pulse_repairs;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  Classes,
  SyncObjs,
  Math,
  Variants,
  Generics.Collections,
  pulse_abi_targets,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

const
  InnerCount = 64;
  ArrayCount = 256;
  RingCount = 128;
  { a trade feed long enough that no branch predictor learns it }
  FeedCount = 65536;

type
  TSmallEnum = (se0, se1, se2, se3, se4, se5, se6, se7,
    se8, se9, se10, se11, se12, se13, se14, se15);
  TSmallSet = set of TSmallEnum;
  TRecord16 = record
    A, B: UInt64;
  end;
  TRecord24 = record
    A, B, C: UInt64;
  end;
  TStatic4 = array[0..3] of UInt64;
  TDoubleArray = array of Double;
  TManagedStatic4 = array[0..3] of UnicodeString;
  TDataHolder = class
  public
    Values: array[0..ArrayCount - 1] of UInt64;
  end;
  IAdder = interface
    ['{0A113825-CBAD-44F4-B914-D981520E1977}']
    function Add(Value: UInt64): UInt64;
  end;
  TAdder = class(TInterfacedObject, IAdder)
    function Add(Value: UInt64): UInt64;
  end;
  { one candle of a trade feed: its range is widened by every trade }
  TCandle = record
    Open, High, Low, Close: Double;
  end;
  PCandle = ^TCandle;
  TPaddedCounter = record
    Value: UInt64;
    Padding: array[0..7] of UInt64;
  end;
  TRepairWorker = class(TThread)
  private
    FIndex: Integer;
    FIterations: Integer;
    FStartEvent: TEvent;
    FDoneEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(Index: Integer);
    destructor Destroy; override;
    procedure StartWork(Iterations: Integer);
    procedure WaitDone;
  end;
  { A book of an exchange symbol keeps its name and volumes private behind
    inline getters, as a class keeps a string and a dynamic array. }
  TGetterBook = class
  private
    FName: UnicodeString;
    FVolumes: TArray<Int64>;
    function GetName: UnicodeString; inline;
    function GetVolumes: TArray<Int64>; inline;
  public
    property Name: UnicodeString read GetName;
    property Volumes: TArray<Int64> read GetVolumes;
  end;
  { An engine keeps its symbols in a list field and looks a key up in it. }
  TGetterShelf = class
  private
    FNames: TList<UnicodeString>;
  public
    function Find(const Key: UnicodeString): Integer;
  end;
  { An engine keeps its orders in a list field as records with the symbol
    string, and reads them field by field. }
  TGetterOrder = record
    Symbol: UnicodeString;
    Price: Double;
    Qty: Int64;
  end;
  TGetterDesk = class
  private
    FOrders: TList<TGetterOrder>;
  public
    function Volume(const Key: UnicodeString): Int64;
  end;

var
  Doubles4: array of Double;
  Doubles256: array of Double;
  Prices256: TDoubleArray;
  PriceFeed: TDoubleArray;
  Candles16: array[0..15] of TCandle;
  Singles256: array of Single;
  Int64s4: array of Int64;
  Int64s256: array of Int64;
  Integers: array[0..ArrayCount - 1] of Integer;
  StaticData: TStatic4;
  ManagedStaticData: TManagedStatic4;
  Holder: TDataHolder;
  IntegerList: TList<Integer>;
  VariantDictionary: TDictionary<Variant, Integer>;
  Adder: IAdder;
  PaddedCounters: array[0..3] of TPaddedCounter;
  Workers: array[0..3] of TRepairWorker;
  StopWorkers: Boolean;
  RuntimeDouble: Double;
  RuntimeUInt64: UInt64;
  GetterNames: TList<UnicodeString>;
  GetterBooks: TList<TGetterBook>;
  GetterKeys: array[0..15] of UnicodeString;
  GetterShelf: TGetterShelf;
  GetterDesk: TGetterDesk;

function DoubleDigest(Value: Double): UInt64; inline;
begin
  Move(Value, Result, SizeOf(Result));
end;

function SingleDigest(Value: Single): UInt64; inline;
var
  Bits: UInt32;
begin
  Move(Value, Bits, SizeOf(Bits));
  Result := Bits;
end;

function InlineFour: Double; inline;
begin
  Result := 4.0;
end;

function TAdder.Add(Value: UInt64): UInt64;
begin
  Result := Value * 33 + 17;
end;

function MakeRecord16(Value: UInt64): TRecord16; noinline;
begin
  Result.A := Value + 1;
  Result.B := Value + 3;
end;

function MakeRecord24(Value: UInt64): TRecord24; noinline;
begin
  Result.A := Value + 1;
  Result.B := Value + 3;
  Result.C := Value + 5;
end;

function SumStatic(const Values: TStatic4): UInt64; noinline;
begin
  Result := Values[0] + Values[1] + Values[2] + Values[3];
end;

function EightArgs(A, B, C, D, E, F, G, H: UInt64): UInt64; noinline;
begin
  Result := A + B * 3 + C * 5 + D * 7 + E * 11 + F * 13 + G * 17 + H * 19;
end;

function SumArrayOfConst(const Values: array of const): UInt64; noinline;
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

function ManagedStaticLength(const Values: TManagedStatic4): UInt64; noinline;
begin
  Result := Length(Values[0]) + Length(Values[1]) + Length(Values[2]) + Length(Values[3]);
end;

function ManagedStringLength(const Value: UnicodeString): UInt64; noinline;
begin
  Result := Length(Value);
end;

constructor TRepairWorker.Create(Index: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FIndex := Index;
  FStartEvent := TEvent.Create(nil, False, False, '');
  FDoneEvent := TEvent.Create(nil, False, False, '');
end;

destructor TRepairWorker.Destroy;
begin
  FDoneEvent.Free;
  FStartEvent.Free;
  inherited Destroy;
end;

procedure TRepairWorker.Execute;
var
  I: Integer;
begin
  PinWorkerThread(FIndex);
  while True do
  begin
    FStartEvent.WaitFor(INFINITE);
    If StopWorkers then
      Exit;
    for I := 1 to FIterations do
      Inc(PaddedCounters[FIndex].Value);
    FDoneEvent.SetEvent;
  end;
end;

procedure TRepairWorker.StartWork(Iterations: Integer);
begin
  FIterations := Iterations;
  FStartEvent.SetEvent;
end;

procedure TRepairWorker.WaitDone;
begin
  FDoneEvent.WaitFor(INFINITE);
end;

function CaseFpConstantFolding(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Double;
begin
  Value := 0;
  for I := 1 to Iterations * InnerCount do
    Value := Value + Sqr(2.0) + Trunc(2.5) + Exp(0.0) + Ln(1.0) + (I and 1);
  Result := DoubleDigest(Value);
end;

function CaseFpDirectConstant(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Double;
begin
  Value := 0;
  for I := 1 to Iterations * InnerCount do
    Value := Value + Sqrt(4.0) + (I and 1);
  Result := DoubleDigest(Value);
end;

function CaseFpAfterInline(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Double;
begin
  Value := 0;
  for I := 1 to Iterations * InnerCount do
    Value := Value + Sqrt(InlineFour) + (I and 1);
  Result := DoubleDigest(Value);
end;

function CaseFpRuntime(Iterations: Integer): UInt64;
var
  I: Integer;
  Input, Value: Double;
begin
  Input := RuntimeDouble;
  Value := 0;
  for I := 1 to Iterations * InnerCount do
  begin
    Value := Value + Sqrt(Input);
    Input := Input + 0.000001;
  end;
  Result := DoubleDigest(Value);
end;

function CaseRoundNormal(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Double;
  Total: Int64;
begin
  Total := 0;
  Value := RuntimeDouble;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Total := Total + Round(Value + (J and 15) * 0.125);
      Value := Value + 0.000001;
    end;
  Result := UInt64(Total);
end;

function CaseLdexpDoubleNormal(Iterations: Integer): UInt64;
var
  I, J, Exponent: Integer;
  Total: Double;
begin
  Total := 0.0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Exponent := ((I + J) and 15) - 7;
      Total := Total + Ldexp(Doubles256[(I + J) and 255], Exponent);
    end;
  Result := DoubleDigest(Total);
end;

function CaseLdexpSingleNormal(Iterations: Integer): UInt64;
var
  I, J, Exponent: Integer;
  Total: Single;
begin
  Total := 0.0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Exponent := ((I + J) and 15) - 7;
      Total := Total + Ldexp(Singles256[(I + J) and 255], Exponent);
    end;
  Result := SingleDigest(Total);
end;

function RoundToCase(Iterations, Digits: Integer): UInt64;
var
  I, J: Integer;
  Value, BucketScale: Double;
  Total: Int64;
begin
  case Digits of
    -8: BucketScale := 100000000.0;
    -6: BucketScale := 1000000.0;
    -4: BucketScale := 10000.0;
    -2: BucketScale := 100.0;
     0: BucketScale := 1.0;
     2: BucketScale := 0.01;
  else
    BucketScale := 1.0;
  end;
  Total := 0;
  Value := RuntimeDouble;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Total := Total + Round(RoundTo(Value + (J and 15) * 0.03125, Digits) * BucketScale);
      Value := Value + 0.000001;
    end;
  Result := UInt64(Total);
end;

function CaseRoundToMinus2(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, -2);
end;

function CaseRoundToMinus4(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, -4);
end;

function CaseRoundToMinus6(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, -6);
end;

function CaseRoundToMinus8(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, -8);
end;

function CaseRoundToZero(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, 0);
end;

function CaseRoundToPlus2(Iterations: Integer): UInt64;
begin
  Result := RoundToCase(Iterations, 2);
end;

function CaseMean4(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Total := Total + Mean(Doubles4);
  Result := DoubleDigest(Total);
end;

function CaseMean256(Iterations: Integer): UInt64;
var
  I: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    Total := Total + Mean(Doubles256);
  Result := DoubleDigest(Total);
end;

function CaseMeanInt64_4(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Total := Total + Mean(Int64s4);
  Result := DoubleDigest(Total);
end;

function CaseMeanInt64_256(Iterations: Integer): UInt64;
var
  I: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    Total := Total + Mean(Int64s256);
  Result := DoubleDigest(Total);
end;

function CaseVariance4(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Total := Total + Variance(Doubles4);
  Result := DoubleDigest(Total);
end;

function CaseVariance256(Iterations: Integer): UInt64;
var
  I: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    Total := Total + Variance(Doubles256);
  Result := DoubleDigest(Total);
end;

function CaseStdDev4(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Total := Total + StdDev(Doubles4);
  Result := DoubleDigest(Total);
end;

function CaseStdDev256(Iterations: Integer): UInt64;
var
  I: Integer;
  Total: Double;
begin
  Total := 0;
  for I := 1 to Iterations do
    Total := Total + StdDev(Doubles256);
  Result := DoubleDigest(Total);
end;

function CaseMinMaxNormal(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, Total: Double;
begin
  Total := 0;
  A := RuntimeDouble;
  B := RuntimeDouble + 0.75;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Total := Total + Min(A, B) + Max(A, B);
      A := A + 0.000001;
      B := B - 0.0000005;
    end;
  Result := DoubleDigest(Total);
end;

{ Helpers of a trading hot path called with constant parameters: the constants
  meet after inlining (the tick size decides the branch, the fee is a constant
  fraction).  The prices are multiples of 0.25, every value is exact, so the
  digest is the same for Delphi and MoonCompiler. }
function TicksBetween(Bid, Ask, Tick: Double): Double; inline;
begin
  If Tick > 0.0 then
    Result := (Ask - Bid) / Tick
  else
    Result := Ask - Bid;
end;

function WithFee(Price, FeeNum, FeeDen: Double): Double; inline;
begin
  Result := Price + Price * (FeeNum / FeeDen);
end;

function CaseFpConstAfterInline(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Total: Double;
  Prices: TDoubleArray;
begin
  { A local: the loop read Prices256 from .bss on every pass. }
  Prices := Prices256;
  Total := 0;
  for I := 1 to Iterations do
    for J := 0 to ArrayCount - 1 do
      Total := Total + TicksBetween(Prices[J], Prices[J] + 0.5, 0.25) +
        WithFee(Prices[J], 3.0, 1024.0);
  Result := DoubleDigest(Total);
end;

{ The best bid and ask of the next 256 trades of the feed: min/max through an
  element }
function CaseFpBestPriceScan(Iterations: Integer): UInt64;
var
  I, J, First: Integer;
  Best, Worst, Total: Double;
  Feed: TDoubleArray;
begin
  { A local: the loop read PriceFeed from .bss on every pass. }
  Feed := PriceFeed;
  Total := 0;
  for I := 1 to Iterations do
  begin
    First := (I * ArrayCount) and (FeedCount - 1);
    Best := Feed[First];
    Worst := Feed[First];
    for J := First + 1 to First + ArrayCount - 1 do
    begin
      If Feed[J] < Best then
        Best := Feed[J];
      If Feed[J] > Worst then
        Worst := Feed[J];
    end;
    Total := Total + Best + Worst;
  end;
  Result := DoubleDigest(Total);
end;

{ Candles of the trade feed, sixteen trades each: min/max through a field of a
  record reached by a pointer }
function CaseFpCandleUpdate(Iterations: Integer): UInt64;
var
  I, J, First: Integer;
  C: PCandle;
  V, Total: Double;
  Feed: TDoubleArray;
begin
  { A local: the loop read PriceFeed from .bss on every pass. }
  Feed := PriceFeed;
  for I := 1 to Iterations do
  begin
    First := (I * ArrayCount) and (FeedCount - 1);
    for J := 0 to ArrayCount - 1 do
    begin
      C := @Candles16[J shr 4];
      V := Feed[First + J];
      If (J and 15) = 0 then begin
        C^.Open := V;
        C^.High := V;
        C^.Low := V;
      end;
      If V < C^.Low then
        C^.Low := V;
      If V > C^.High then
        C^.High := V;
      C^.Close := V;
    end;
  end;
  Total := 0;
  for J := 0 to High(Candles16) do
    Total := Total + Candles16[J].High - Candles16[J].Low + Candles16[J].Close;
  Result := DoubleDigest(Total);
end;

function CaseDivModShared(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Divisor, Value: UInt64;
begin
  Result := 0;
  Value := RuntimeUInt64;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Divisor := UInt64((J and 15) + 3);
      Result := Result + Value div Divisor + Value mod Divisor;
      Value := Value * 33 + 17;
    end;
end;

function CaseSwapEndian(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  Value := RuntimeUInt64;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Value := SwapEndian(Value + UInt64(J));
  Result := Value;
end;

function CaseRangeProof(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Index := (I + J) and 255;
      Result := Result + UInt32(Integers[Index]);
    end;
end;

function CaseSmallSetOps(Iterations: Integer): UInt64;
var
  I, J: Integer;
  A, B, C: TSmallSet;
  E: TSmallEnum;
begin
  A := [se0, se2, se4, se6, se8, se10, se12, se14];
  B := [se1, se2, se5, se6, se9, se10, se13, se14];
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      C := (A + B) - [TSmallEnum(J and 15)];
      for E := Low(TSmallEnum) to High(TSmallEnum) do
        If E in C then
          Inc(Result, Ord(E) + 1);
      A := B;
      B := C;
    end;
end;

function CaseUnrollDeadCounter(Iterations: Integer): UInt64;
var
  I, J, K: Integer;
  Values: array[0..7] of UInt64;
begin
  FillChar(Values, SizeOf(Values), 0);
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      for K := 0 to High(Values) do
        Values[K] := Values[K] + UInt64(I + J + K);
  Result := Values[0] xor Values[3] xor Values[7];
end;

function CaseLoopInvariantField(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ArrayCount - 1 do
      Result := Result + Holder.Values[J];
end;

function CasePointerBump(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: PInteger;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    P := @Integers[0];
    for J := 0 to ArrayCount - 1 do
    begin
      Result := Result + UInt32(P^);
      Inc(P);
    end;
  end;
end;

function CaseListReverse(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
begin
  { A local: IntegerList reloaded after each Reverse 4K-aliased its stores. }
  List := IntegerList;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 15 do
    begin
      List.Reverse;
      Result := Result + UInt32(List[J]);
    end;
end;

function CaseListExchange(Iterations: Integer): UInt64;
var
  I, J, Other: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to 15 do
    begin
      Other := 255 - J;
      IntegerList.Exchange(J, Other);
      Result := Result + UInt32(IntegerList[J]) + UInt32(IntegerList[Other]);
    end;
end;

function CaseUnicodeCow(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := StringOfChar('x', ArrayCount);
    for J := 1 to ArrayCount do
      Value[J] := WideChar(Ord('a') + (J and 15));
    Result := Result + Ord(Value[(I and 255) + 1]);
  end;
end;

function CaseByteStringCow(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: RawByteString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    SetLength(Value, ArrayCount);
    for J := 1 to ArrayCount do
      Value[J] := AnsiChar(Ord('a') + (J and 15));
    Result := Result + Ord(Value[(I and 255) + 1]);
  end;
end;

function CaseSameTextShort(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      If SameText('MoonCompiler', 'mooncompiler') then
        Inc(Result);
      If SameText('Delphi', 'Delphi') then
        Inc(Result);
    end;
end;

function CaseUnicodeLiteralEqual(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  Value := 'x';
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      If Value = 'x' then
        Inc(Result);
      If Value <> 'y' then
        Inc(Result);
    end;
end;

function CaseUtf8RoundTrip(Iterations: Integer): UInt64;
var
  I: Integer;
  Bytes: UTF8String;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Bytes := UTF8Encode('MoonCompiler: Привет, мир!');
    Text := UTF8Decode(Bytes);
    Result := Result + Length(Bytes) + Length(Text);
  end;
end;

function CaseUtf8Encode(Iterations: Integer): UInt64;
var
  I: Integer;
  Bytes: UTF8String;
  Text: UnicodeString;
begin
  Result := 0;
  Text := 'MoonCompiler: Привет, мир!';
  for I := 1 to Iterations do
  begin
    Bytes := UTF8Encode(Text);
    Result := Result + Length(Bytes) + Ord(Bytes[1]);
  end;
end;

function CaseUtf8Decode(Iterations: Integer): UInt64;
var
  I: Integer;
  Bytes: UTF8String;
  Text: UnicodeString;
begin
  Result := 0;
  Bytes := UTF8Encode('MoonCompiler: Привет, мир!');
  for I := 1 to Iterations do
  begin
    Text := UTF8Decode(Bytes);
    Result := Result + Length(Text) + Ord(Text[1]);
  end;
end;

function CaseUtf8Raw(Iterations: Integer): UInt64;
var
  I: Integer;
  ByteCount, CharCount: SizeUInt;
  Bytes: array[0..127] of AnsiChar;
  Chars: array[0..127] of WideChar;
  Text: UnicodeString;
begin
  Result := 0;
  Text := 'MoonCompiler: Привет, мир!';
  for I := 1 to Iterations do
  begin
    ByteCount := UnicodeToUtf8(@Bytes[0], Length(Bytes), PWideChar(Text), Length(Text));
    CharCount := UTF8ToUnicode(@Chars[0], Length(Chars), @Bytes[0], ByteCount);
    Result := Result + ByteCount + CharCount + Ord(Bytes[0]) + Ord(Chars[0]);
  end;
end;

function CaseStringBuilderReplace(Iterations: Integer): UInt64;
var
  I: Integer;
  Builder: TStringBuilder;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Builder := TStringBuilder.Create('alpha-beta-alpha-beta', 64);
    try
      Builder.Replace('alpha', 'moon', 0, Builder.Length);
      Result := Result + Builder.Length + Ord(Builder.Chars[0]);
    finally
      Builder.Free;
    end;
  end;
end;

function CaseVariantDictionary(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
  Key: Variant;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Key := (I + J) and 31;
      If VariantDictionary.TryGetValue(Key, Value) then
        Result := Result + UInt32(Value);
    end;
end;

function CaseRecordReturns(Iterations: Integer): UInt64;
var
  I, J: Integer;
  R16: TRecord16;
  R24: TRecord24;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      R16 := MakeRecord16(Result + UInt64(J));
      R24 := MakeRecord24(R16.A + R16.B);
      Result := Result + R24.A + R24.B + R24.C;
    end;
end;

function CaseCrossUnitRecord16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec16;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := ReturnRecord16(Result + UInt64(I + J));
      Result := Result + Value.A + Value.B;
    end;
end;

function CaseCrossUnitRecord24(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TRec24;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := ReturnRecord24(Result + UInt64(I + J));
      Result := Result + Value.A + Value.B + Value.C;
    end;
end;

function CaseStaticArrayConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + SumStatic(StaticData) + UInt64(J);
end;

function CaseManagedStaticArray(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + ManagedStaticLength(ManagedStaticData) + UInt64(J);
end;

function CaseArrayOfConst(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + SumArrayOfConst([I, J, Int64(I) * J, 17]);
end;

function CaseManagedArgument(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Value := 'MoonCompiler';
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + ManagedStringLength(Value) + UInt64(J);
end;

function CaseEightArgs(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + EightArgs(J, J + 1, J + 2, J + 3, J + 4, J + 5, J + 6, J + 7);
end;

function CaseInterfaceCall(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Adder.Add(Result);
end;

function CasePaddedCounters(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  FillChar(PaddedCounters, SizeOf(PaddedCounters), 0);
  for I := 0 to High(Workers) do
    Workers[I].StartWork(Iterations * 4096);
  for I := 0 to High(Workers) do
    Workers[I].WaitDone;
  Result := 0;
  for I := 0 to High(PaddedCounters) do
    Result := Result + PaddedCounters[I].Value;
end;

function CaseRaiseCatch(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    try
      raise EAbort.Create('pulse');
    except
      on EAbort do
        Inc(Result);
    end;
end;

function RingAlloc(Size, Iterations: Integer): UInt64;
var
  I, J: Integer;
  Pointers: array[0..RingCount - 1] of Pointer;
  P: PByte;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    for J := 0 to RingCount - 1 do
    begin
      GetMem(Pointers[J], Size);
      P := Pointers[J];
      P[0] := Byte(I + J);
    end;
    for J := RingCount - 1 downto 0 do
    begin
      P := Pointers[J];
      Result := Result + P[0];
      FreeMem(Pointers[J]);
    end;
  end;
end;

function CaseRing64(Iterations: Integer): UInt64;
begin
  Result := RingAlloc(64, Iterations);
end;

function CaseRing256(Iterations: Integer): UInt64;
begin
  Result := RingAlloc(256, Iterations);
end;

function CaseRing1024(Iterations: Integer): UInt64;
begin
  Result := RingAlloc(1024, Iterations);
end;

function TGetterBook.GetName: UnicodeString;
begin
  Result := FName;
end;

function TGetterBook.GetVolumes: TArray<Int64>;
begin
  Result := FVolumes;
end;

{ The value of an inlined string or dynamic-array getter read straight from its
  source: a symbol looked up in a string list, the first character of each
  name, a name compared through an object property, the volumes of a book. }
function CaseGetterListFind(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Names: TList<UnicodeString>;
begin
  { A local: the loop read GetterNames from .bss on every pass. }
  Names := GetterNames;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to Names.Count - 1 do
      If Names[J] = GetterKeys[I and 15] then
        Result := Result + UInt64(J + 1);
end;

function CaseGetterFirstChar(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Names: TList<UnicodeString>;
begin
  { A local: the loop read GetterNames from .bss on every pass. }
  Names := GetterNames;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to Names.Count - 1 do
      If Names[J] <> '' then
        Result := Result + Ord(Names[J][1]) + UInt64(I and 1);
end;

function CaseGetterPropertyCompare(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Books: TList<TGetterBook>;
begin
  { A local: the loop read GetterBooks from .bss on every pass. }
  Books := GetterBooks;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to Books.Count - 1 do
      If Books[J].Name = GetterKeys[I and 15] then
        Result := Result + UInt64(J + 1);
end;

function TGetterShelf.Find(const Key: UnicodeString): Integer;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to FNames.Count - 1 do
    If FNames[J] = Key then
      Result := Result + J + 1;
end;

function CaseGetterFieldListFind(Iterations: Integer): UInt64;
var
  I: Integer;
  Shelf: TGetterShelf;
begin
  { A local: the loop read GetterShelf from .bss on every pass. }
  Shelf := GetterShelf;
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(Shelf.Find(GetterKeys[I and 15]));
end;

function TGetterDesk.Volume(const Key: UnicodeString): Int64;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to FOrders.Count - 1 do
    If FOrders[J].Symbol = Key then
      Result := Result + FOrders[J].Qty;
end;

function CaseGetterRecordField(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(GetterDesk.Volume(GetterKeys[I and 15]));
end;

function CaseGetterArraySum(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Book: TGetterBook;
  Books: TList<TGetterBook>;
begin
  { A local: the loop read GetterBooks from .bss on every pass. }
  Books := GetterBooks;
  Result := 0;
  for I := 1 to Iterations do
  begin
    Book := Books[I and 15];
    for J := 0 to High(Book.Volumes) do
      Result := Result + UInt64(Book.Volumes[J]);
  end;
end;

procedure InitializeData(const SelectedCase: string);
const
  Symbols: array[0..15] of UnicodeString = ('BTCUSDT', 'ETHUSDT', 'SOLUSDT',
    'XRPUSDT', 'DOGEUSDT', 'ADAUSDT', 'AVAXUSDT', 'LINKUSDT', 'DOTUSDT',
    'TRXUSDT', 'LTCUSDT', 'BCHUSDT', 'NEARUSDT', 'ATOMUSDT', 'FILUSDT',
    'APTUSDT');
var
  I, J: Integer;
  Book: TGetterBook;
  Order: TGetterOrder;
  Seed: Cardinal;
  Price: Double;
begin
  SetLength(Doubles4, 4);
  SetLength(Doubles256, 256);
  SetLength(Prices256, 256);
  SetLength(PriceFeed, FeedCount);
  SetLength(Singles256, 256);
  SetLength(Int64s4, 4);
  SetLength(Int64s256, 256);
  Doubles4[0] := 1.25;
  Doubles4[1] := 2.5;
  Doubles4[2] := 3.75;
  Doubles4[3] := 5.0;
  Int64s4[0] := 1000001;
  Int64s4[1] := 1000003;
  Int64s4[2] := 1000005;
  Int64s4[3] := 1000007;
  Holder := TDataHolder.Create;
  IntegerList := TList<Integer>.Create;
  VariantDictionary := TDictionary<Variant, Integer>.Create;
  for I := 0 to ArrayCount - 1 do
  begin
    Doubles256[I] := 1.0 + I * 0.03125;
    Singles256[I] := 1.0 + I * 0.03125;
    Int64s256[I] := 1000000 + I * 17;
    Integers[I] := I * 197 + 17;
    Holder.Values[I] := UInt64(Integers[I]);
    IntegerList.Add(Integers[I]);
    If I < 32 then
      VariantDictionary.Add(Variant(I), I * 3 + 1);
  end;
  { a random walk of prices in quarter ticks, the same for every compiler }
  Seed := 12345;
  Price := 100.0;
  for I := 0 to ArrayCount - 1 do
  begin
    Seed := Seed * 1103515245 + 12345;
    Price := Price + (Integer((Seed shr 16) mod 9) - 4) * 0.25;
    Prices256[I] := Price;
  end;
  for I := 0 to FeedCount - 1 do
  begin
    Seed := Seed * 1103515245 + 12345;
    Price := Price + (Integer((Seed shr 16) mod 9) - 4) * 0.25;
    If Price < 50.0 then
      Price := Price + 25.0;
    PriceFeed[I] := Price;
  end;
  StaticData[0] := 11;
  StaticData[1] := 13;
  StaticData[2] := 17;
  StaticData[3] := 19;
  ManagedStaticData[0] := 'Moon';
  ManagedStaticData[1] := 'Compiler';
  ManagedStaticData[2] := 'Win64';
  ManagedStaticData[3] := 'Linux';
  Adder := TAdder.Create;
  RuntimeDouble := 123.456789;
  RuntimeUInt64 := $123456789ABCDEF1;
  GetterNames := TList<UnicodeString>.Create;
  GetterBooks := TList<TGetterBook>.Create;
  GetterShelf := TGetterShelf.Create;
  GetterShelf.FNames := GetterNames;
  GetterDesk := TGetterDesk.Create;
  GetterDesk.FOrders := TList<TGetterOrder>.Create;
  for I := 0 to 15 do
  begin
    GetterNames.Add(Symbols[I]);
    Order.Symbol := Symbols[I];
    Order.Price := 100 + I;
    Order.Qty := (I + 1) * 10;
    GetterDesk.FOrders.Add(Order);
    Book := TGetterBook.Create;
    Book.FName := Symbols[I];
    SetLength(Book.FVolumes, 64);
    for J := 0 to 63 do
      Book.FVolumes[J] := (I + 1) * 1000 + J * 7;
    GetterBooks.Add(Book);
    If I and 3 = 3 then
      GetterKeys[I] := 'MISS' + Symbols[I]
    else
      GetterKeys[I] := Symbols[(I * 5) and 15];
  end;
  { The workers belong only to padded-counters-4.  Keeping four parked
    threads in every unrelated single-thread process needlessly reserves
    four physical cores and contaminates process-wide counters. }
  If not CaseSelected(SelectedCase, 'padded-counters-4') then
    Exit;
  If not CanPinWorkerThreads(Length(Workers) + 1) then
    raise EAbort.Create('padded-counter sentinel requires five available logical CPUs');
  StopWorkers := False;
  for I := 0 to High(Workers) do
  begin
    Workers[I] := TRepairWorker.Create(I);
    Workers[I].Start;
  end;
end;

procedure FinalizeData;
var
  I: Integer;
begin
  If not Assigned(Workers[0]) then
    Exit;
  StopWorkers := True;
  for I := 0 to High(Workers) do
    Workers[I].FStartEvent.SetEvent;
  for I := 0 to High(Workers) do
  begin
    Workers[I].WaitFor;
    Workers[I].Free;
  end;
end;

procedure Run;
var
  I: Integer;
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_repairs', Profile, SelectedCase);
  If Profile.Name <> 'list' then
    InitializeData(SelectedCase);
  Found := False;
  try
    PulseRunCase('pulse_repairs', 'fp-constant-folding', 'codegen', 'compiler', @CaseFpConstantFolding, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-direct-constant', 'codegen', 'compiler', @CaseFpDirectConstant, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-after-inline', 'codegen', 'compiler', @CaseFpAfterInline, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-runtime', 'codegen', 'compiler', @CaseFpRuntime, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'round-normal', 'rtl', 'Math.Round', @CaseRoundNormal, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'ldexp-double-normal', 'rtl', 'Math.Ldexp', @CaseLdexpDoubleNormal, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'ldexp-single-normal', 'rtl', 'Math.Ldexp', @CaseLdexpSingleNormal, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-minus2', 'rtl', 'Math.RoundTo', @CaseRoundToMinus2, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-minus4', 'rtl', 'Math.RoundTo', @CaseRoundToMinus4, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-minus6', 'rtl', 'Math.RoundTo', @CaseRoundToMinus6, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-minus8', 'rtl', 'Math.RoundTo', @CaseRoundToMinus8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-zero', 'rtl', 'Math.RoundTo', @CaseRoundToZero, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'roundto-plus2', 'rtl', 'Math.RoundTo', @CaseRoundToPlus2, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'mean-double-4', 'rtl', 'Math.Mean', @CaseMean4, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'mean-double-256', 'rtl', 'Math.Mean', @CaseMean256, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'mean-int64-4', 'rtl', 'Math.Mean', @CaseMeanInt64_4, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'mean-int64-256', 'rtl', 'Math.Mean', @CaseMeanInt64_256, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'variance-4', 'rtl', 'Math.Variance', @CaseVariance4, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'variance-256', 'rtl', 'Math.Variance', @CaseVariance256, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'stddev-4', 'rtl', 'Math.StdDev', @CaseStdDev4, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'stddev-256', 'rtl', 'Math.StdDev', @CaseStdDev256, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'minmax-normal', 'codegen+rtl', 'Math.Min/Max', @CaseMinMaxNormal, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-const-after-inline', 'codegen', 'compiler', @CaseFpConstAfterInline, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-best-price-scan', 'codegen', 'compiler', @CaseFpBestPriceScan, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'fp-candle-update', 'codegen', 'compiler', @CaseFpCandleUpdate, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'divmod-shared', 'codegen', 'compiler', @CaseDivModShared, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'swapendian', 'codegen', 'compiler', @CaseSwapEndian, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'range-proof', 'codegen', 'compiler', @CaseRangeProof, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'small-set-ops', 'codegen', 'compiler', @CaseSmallSetOps, InnerCount * 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'unroll-dead-counter', 'codegen', 'compiler', @CaseUnrollDeadCounter, InnerCount * 8, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'loop-invariant-field', 'codegen', 'compiler', @CaseLoopInvariantField, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'pointer-bump', 'codegen', 'compiler', @CasePointerBump, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'list-reverse', 'rtl+managed', 'Generics.Collections', @CaseListReverse, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'list-exchange', 'rtl+managed', 'Generics.Collections', @CaseListExchange, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'unicode-cow', 'codegen+rtl', 'UnicodeString', @CaseUnicodeCow, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'bytestring-cow', 'codegen+rtl', 'RawByteString', @CaseByteStringCow, ArrayCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'sametext-short', 'rtl', 'SysUtils.SameText', @CaseSameTextShort, InnerCount * 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'unicode-literal-equal', 'codegen+rtl', 'UnicodeString', @CaseUnicodeLiteralEqual, InnerCount * 2, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'utf8-roundtrip', 'rtl', 'SysUtils', @CaseUtf8RoundTrip, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'utf8-encode', 'rtl', 'SysUtils', @CaseUtf8Encode, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'utf8-decode', 'rtl', 'SysUtils', @CaseUtf8Decode, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'utf8-raw', 'rtl', 'System', @CaseUtf8Raw, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'stringbuilder-replace', 'rtl', 'SysUtils.TStringBuilder', @CaseStringBuilderReplace, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'variant-dictionary', 'rtl+managed', 'Generics.Collections', @CaseVariantDictionary, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'record-returns', 'abi', 'compiler', @CaseRecordReturns, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'return-record16-cross-unit', 'abi', 'compiler', @CaseCrossUnitRecord16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'return-record24-cross-unit', 'abi', 'compiler', @CaseCrossUnitRecord24, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'static-array-const', 'abi', 'compiler', @CaseStaticArrayConst, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'managed-static-array', 'abi+managed', 'compiler', @CaseManagedStaticArray, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'array-of-const', 'abi+managed', 'compiler', @CaseArrayOfConst, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'managed-argument', 'abi+managed', 'compiler', @CaseManagedArgument, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'eight-args', 'abi', 'compiler', @CaseEightArgs, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'interface-call', 'abi', 'compiler', @CaseInterfaceCall, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'padded-counters-4', 'codegen+threads', 'compiler', @CasePaddedCounters, 4 * 4096, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'raise-catch', 'compiler+rtl', 'exceptions', @CaseRaiseCatch, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'ring-64', 'mm', 'fpcx64mm', @CaseRing64, RingCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'ring-256', 'mm', 'fpcx64mm', @CaseRing256, RingCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'ring-1024', 'mm', 'fpcx64mm', @CaseRing1024, RingCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-list-find', 'codegen+managed', 'compiler', @CaseGetterListFind, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-first-char', 'codegen+managed', 'compiler', @CaseGetterFirstChar, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-property-compare', 'codegen+managed', 'compiler', @CaseGetterPropertyCompare, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-array-sum', 'codegen+managed', 'compiler', @CaseGetterArraySum, 64, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-field-list-find', 'codegen+managed', 'compiler', @CaseGetterFieldListFind, 16, Profile, SelectedCase, Found);
    PulseRunCase('pulse_repairs', 'getter-record-field', 'codegen+managed', 'compiler', @CaseGetterRecordField, 16, Profile, SelectedCase, Found);
  finally
    If Assigned(GetterBooks) then
      for I := 0 to GetterBooks.Count - 1 do
        GetterBooks[I].Free;
    GetterBooks.Free;
    GetterShelf.Free;
    If Assigned(GetterDesk) then
      GetterDesk.FOrders.Free;
    GetterDesk.Free;
    GetterNames.Free;
    VariantDictionary.Free;
    IntegerList.Free;
    Holder.Free;
    Adder := nil;
    FinalizeData;
  end;
  PulseFinish('pulse_repairs', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
