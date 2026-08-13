unit mega_runtime_fpc;

{$mode objfpc}{$H+}{$codepage utf8}
{$excessprecision on}
{$modeswitch advancedrecords}
{$if FPC_FULLVERSION >= 30301}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$define HAS_ANONYMOUS_FUNCTIONS}
{$endif}

interface

type
  TMegaRuntimeReport = record
    Failed: Boolean;
    ErrorText: RawByteString;
    Checks: LongInt;
    Visits: LongInt;
    CrossThreadVisits: LongInt;
    PeakWorkers: LongInt;
    ManagedInitializes: LongInt;
    ManagedFinalizes: LongInt;
    PortableChecks: Int64;
    PortableDigest: QWord;
  end;

procedure RunMegaRuntime(Seed: QWord; out Report: TMegaRuntimeReport);

implementation

uses
  {$ifdef UNIX}cthreads,{$endif} SysUtils, Classes, Math, mega_portable;

const
  WorkerCount = 4;
  PhaseCount = 4;
  CategoryCount = 8;
  TraceDepth = 16;
  MaxRecordedFailures = 64;
  DefaultSeed = QWord($6D6F6F6E626F7421);

type
  EMegaFailure = class(Exception);

  generic TBox<T> = record
    Value: T;
  end;

  TIntBox = specialize TBox<Int64>;

  IValue = interface
    ['{715294B9-47F2-4F27-9D16-A8EFA6E4FCA1}']
    function GetValue: Int64;
    function GetRawText: RawByteString;
    function GetWideText: UnicodeString;
    function GetItemCount: Integer;
    function GetItem(Index: Integer): Int64;
  end;

  TValue = class(TInterfacedObject, IValue)
  private
    FValue: Int64;
    FRawText: RawByteString;
    FWideText: UnicodeString;
    FItems: array of Int64;
  public
    constructor Create(AValue: Int64);
    constructor CreatePayload(AValue: Int64; APhase, AWorker: Integer);
    function GetValue: Int64;
    function GetRawText: RawByteString;
    function GetWideText: UnicodeString;
    function GetItemCount: Integer;
    function GetItem(Index: Integer): Int64;
  end;

  TManagedCell = record
    Text: RawByteString;
    Values: array of Int64;
    class operator Initialize(var Dest: TManagedCell);
    class operator Finalize(var Dest: TManagedCell);
  end;

  TWorker = class(TThread)
  private
    FId: Integer;
    FSeed: QWord;
    FState: QWord;
    FPhase: Integer;
    FContext: RawByteString;
    FError: RawByteString;
    FRecordedFailureCount: Integer;
    FRecordedFailures: array[0..MaxRecordedFailures - 1] of RawByteString;
    FTrace: array[0..TraceDepth - 1] of RawByteString;
    FTracePos: Integer;
    function NextRandom: QWord; inline;
    procedure Trace(const S: RawByteString);
    procedure Check(Condition: Boolean; const CheckName: RawByteString);
    procedure CaptureFailure(E: Exception);
    procedure RunCrossThreadChecks;
    procedure RunStrings;
    procedure RunManagedAndInterfaces;
    procedure RunArraysAndGenerics;
    procedure RunExceptionsAndCaptures;
    procedure RunAliasingAndMath;
    procedure RunOptimizerOracles;
    procedure RunKnownRuntimeRegressions;
    procedure RunPortableStateMachine;
    procedure RunPhase;
  protected
    procedure Execute; override;
  public
    constructor Create(AId: Integer; ASeed: QWord);
    property ErrorText: RawByteString read FError;
  end;

var
  PhaseGates: array[0..PhaseCount - 1, 0..WorkerCount - 1] of PRTLEvent;
  CopyGates: array[0..PhaseCount - 1, 0..WorkerCount - 1] of PRTLEvent;
  PhaseReady: array[0..PhaseCount - 1] of LongInt;
  PhaseCopied: array[0..PhaseCount - 1] of LongInt;
  PhaseDone: array[0..PhaseCount - 1] of LongInt;
  PublishedValues: array[0..PhaseCount - 1, 0..WorkerCount - 1] of QWord;
  PublishedInterfaces: array[0..PhaseCount - 1, 0..WorkerCount - 1] of IValue;
  PortableResults: array[0..PhaseCount - 1, 0..WorkerCount - 1] of TPortableResult;
  AtomicChecks: LongInt = 0;
  ManagedInitializes: LongInt = 0;
  ManagedFinalizes: LongInt = 0;
  ThreadVisits: LongInt = 0;
  CrossThreadVisits: LongInt = 0;
  ActiveWorkers: LongInt = 0;
  PeakWorkers: LongInt = 0;

threadvar
  ThreadCookie: QWord;
  KnownLongIndex: Integer;

const
  KnownLongValues: array[0..1] of Integer = (1052909725, 1092805937);

function KnownGetLong: Integer;
begin
  Result := KnownLongValues[KnownLongIndex];
  Inc(KnownLongIndex);
end;

function KnownAbsoluteDouble: Double;
type
  TDoubleWords = packed record
    LowWord, HighWord: Integer;
  end;
var
  Words: TDoubleWords absolute Result;
begin
  Words.LowWord := KnownGetLong;
  Words.HighWord := KnownGetLong;
end;

type
  TUnsignedLoopRecord = record
    EntryCount: SizeUInt;
  end;
  PUnsignedLoopRecord = ^TUnsignedLoopRecord;

{$push}{$R-}
function KnownUnsignedLoop(Rec: PUnsignedLoopRecord): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Rec^.EntryCount - 1 do
  begin
    Inc(Result);
    if Result > 4 then
      Exit;
  end;
end;
{$pop}

function KnownConditionalMove(A: DWord; B: Int64): Int64;
begin
  while True do
  begin
    if B > 0 then
      B := A;
    Result := B;
    Break;
  end;
end;

type
  TRotateWords = packed array[0..3] of Word;

  TPointerFields = packed record
    A, B, C: Word;
  end;

  TPointerLayoutA = packed record
    Fields: TPointerFields;
    R: Word;
  end;

  TPointerLayoutB = packed record
    R: Word;
    Fields: TPointerFields;
  end;

function KnownRotateWords(P: QWord): QWord; inline;
var
  Source: TRotateWords absolute P;
  Dest: TRotateWords absolute Result;
begin
  Dest[0] := Source[3];
  Dest[1] := Source[0];
  Dest[2] := Source[1];
  Dest[3] := Source[2];
end;

function KnownConvertPointer(const P: Pointer): Pointer;
var
  Source: TPointerLayoutA absolute P;
  Dest: TPointerLayoutB absolute Result;
begin
  Dest.R := Source.R;
  Dest.Fields.A := Source.Fields.A;
  Dest.Fields.B := Source.Fields.B;
  Dest.Fields.C := Source.Fields.C;
end;

function KnownConvertPointerInline(const P: Pointer): Pointer; inline;
var
  Source: TPointerLayoutA absolute P;
  Dest: TPointerLayoutB absolute Result;
begin
  Dest.R := Source.R;
  Dest.Fields.A := Source.Fields.A;
  Dest.Fields.B := Source.Fields.B;
  Dest.Fields.C := Source.Fields.C;
end;

function KnownShiftRight(Q: QWord): DWord; inline;
begin
  Result := DWord(Q shr 32);
end;

function KnownShiftLeft(Q: QWord): DWord; inline;
begin
  Result := DWord(Q shl 32);
end;

function KnownReadByte(const Data: TBytes; var Position: Integer): Byte;
begin
  Result := Data[Position];
  Inc(Position);
end;

function KnownReadSubLength(const Data: TBytes; var Position: Integer): Integer;
var
  First: Integer;
begin
  First := KnownReadByte(Data, Position);
  if First < 192 then
    Result := First
  else if First < 255 then
    Result := ((First - 192) shl 8) + KnownReadByte(Data, Position) + 192
  else
    Result := -1;
end;

function KnownInlineShortString(S: ShortString): PChar; inline;
begin
  GetMem(Result, Length(S) + 1);
  if Length(S) > 0 then
    Move(S[1], Result^, Length(S));
  Result[Length(S)] := #0;
end;

constructor TValue.Create(AValue: Int64);
begin
  inherited Create;
  FValue := AValue;
end;

constructor TValue.CreatePayload(AValue: Int64; APhase, AWorker: Integer);
var
  I: Integer;
begin
  inherited Create;
  FValue := AValue;
  FRawText := Format('payload/%d/%d/%d', [AValue, APhase, AWorker]);
  FWideText := UnicodeString('worker-') + UnicodeString(IntToStr(AWorker)) +
    ':' + UnicodeString(IntToStr(APhase)) + ':' + UnicodeString(WideChar($03BB));
  SetLength(FItems, (APhase + AWorker) mod 7 + 3);
  for I := 0 to High(FItems) do
    FItems[I] := AValue * 101 + I * 17 - AWorker;
end;

function TValue.GetValue: Int64;
begin
  Result := FValue;
end;

function TValue.GetRawText: RawByteString;
begin
  Result := FRawText;
end;

function TValue.GetWideText: UnicodeString;
begin
  Result := FWideText;
end;

function TValue.GetItemCount: Integer;
begin
  Result := Length(FItems);
end;

function TValue.GetItem(Index: Integer): Int64;
begin
  Result := FItems[Index];
end;

class operator TManagedCell.Initialize(var Dest: TManagedCell);
begin
  InterlockedIncrement(ManagedInitializes);
end;

class operator TManagedCell.Finalize(var Dest: TManagedCell);
begin
  InterlockedIncrement(ManagedFinalizes);
end;

constructor TWorker.Create(AId: Integer; ASeed: QWord);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FId := AId;
  FSeed := ASeed;
  FState := ASeed xor (QWord(AId + 1) * QWord($9E3779B97F4A7C15));
  if FState = 0 then
    FState := QWord($A0761D6478BD642F) xor QWord(AId + 1);
end;

function TWorker.NextRandom: QWord;
begin
  { xorshift64*: fixed-width wraparound is intentional and independently
    reproducible for every compiler/options tuple. }
  FState := FState xor (FState shr 12);
  FState := FState xor (FState shl 25);
  FState := FState xor (FState shr 27);
  Result := FState * QWord($2545F4914F6CDD1D);
end;

procedure TWorker.Trace(const S: RawByteString);
begin
  FTrace[FTracePos mod TraceDepth] := S;
  Inc(FTracePos);
end;

procedure TWorker.Check(Condition: Boolean; const CheckName: RawByteString);
var
  I, StartAt: Integer;
  History: RawByteString;
begin
  InterlockedIncrement(AtomicChecks);
  if Condition then
    Exit;
  History := '';
  if FTracePos > TraceDepth then
    StartAt := FTracePos - TraceDepth
  else
    StartAt := 0;
  for I := StartAt to FTracePos - 1 do
    History := History + FTrace[I mod TraceDepth] + ';';
  raise EMegaFailure.CreateFmt(
    'seed=%u worker=%d phase=%d check=%s state=%u trace=%s',
    [FSeed, FId, FPhase, CheckName, FState, History]);
end;

procedure TWorker.CaptureFailure(E: Exception);
var
  I, CheckAt, CheckEnd: Integer;
  FailureKey, MessageText: RawByteString;
begin
  MessageText := RawByteString(E.Message);
  CheckAt := Pos('check=', MessageText);
  if CheckAt > 0 then
  begin
    CheckEnd := CheckAt + Length('check=');
    while (CheckEnd <= Length(MessageText)) and (MessageText[CheckEnd] > ' ') do
      Inc(CheckEnd);
    FailureKey := Copy(MessageText, CheckAt, CheckEnd - CheckAt);
  end
  else
    FailureKey := RawByteString(E.ClassName) + ':' + FContext + ':' + MessageText;
  for I := 0 to FRecordedFailureCount - 1 do
    if FRecordedFailures[I] = FailureKey then
      Exit;
  if FRecordedFailureCount >= MaxRecordedFailures then
    Exit;
  FRecordedFailures[FRecordedFailureCount] := FailureKey;
  Inc(FRecordedFailureCount);
  if FError <> '' then
    FError := FError + ' | ';
  if FContext <> '' then
    FError := FError + FContext + ' ';
  FError := FError + RawByteString(E.ClassName) + ': ' + MessageText;
end;

procedure TWorker.RunCrossThreadChecks;
const
  PhaseSalt = QWord($9E3779B97F4A7C15);
  WorkerSalt = QWord($D1B54A32D192ED03);
var
  PeerId, I, J, ItemIndex: Integer;
  Decoded, ExpectedSum, Sum: QWord;
  ExpectedRaw: RawByteString;
  ExpectedWide: UnicodeString;
  Peers: array[0..WorkerCount - 1] of IValue;
  ReleaseOrder: array[0..WorkerCount - 1] of Integer;
begin
  Sum := 0;
  ExpectedSum := 0;
  try
    for PeerId := 0 to WorkerCount - 1 do
      Peers[PeerId] := PublishedInterfaces[FPhase, PeerId];
  finally
    { Every worker now owns every reference it managed to copy. The main
      thread drops the published references only after all workers reach this
      barrier. Reaching it in finally also prevents a refcount failure from
      deadlocking the test harness itself. }
    InterlockedIncrement(PhaseCopied[FPhase]);
    RTLEventWaitFor(CopyGates[FPhase, FId]);
  end;

  for PeerId := 0 to WorkerCount - 1 do
  begin
    Decoded := (PublishedValues[FPhase, PeerId] -
      QWord(PeerId + 1) * WorkerSalt) xor QWord(FPhase + 1) * PhaseSalt;
    Check(Decoded = FSeed, 'cross-thread-value-publication');
    Check(Assigned(Peers[PeerId]), 'cross-thread-interface-publication');
    Inc(Sum, QWord(Peers[PeerId].GetValue));
    Inc(ExpectedSum, QWord(FPhase * 100 + PeerId));
    ExpectedRaw := RawByteString('payload/') +
      RawByteString(IntToStr(FPhase * 100 + PeerId)) + '/' +
      RawByteString(IntToStr(FPhase)) + '/' + RawByteString(IntToStr(PeerId));
    Check(Peers[PeerId].GetRawText = ExpectedRaw,
      'cross-thread-managed-raw-string');
    ExpectedWide := UnicodeString(Format('worker-%d:%d:', [PeerId, FPhase])) +
      UnicodeString(WideChar($03BB));
    Check(Peers[PeerId].GetWideText = ExpectedWide,
      'cross-thread-managed-wide-string');
    Check(Peers[PeerId].GetItemCount = (FPhase + PeerId) mod 7 + 3,
      'cross-thread-managed-array-length');
    for ItemIndex := 0 to Peers[PeerId].GetItemCount - 1 do
      Check(Peers[PeerId].GetItem(ItemIndex) =
        Int64(FPhase * 100 + PeerId) * 101 + ItemIndex * 17 - PeerId,
        'cross-thread-managed-array-item');
    InterlockedIncrement(CrossThreadVisits);
  end;
  Check(Sum = ExpectedSum, 'cross-thread-interface-sum');

  for I := 0 to High(ReleaseOrder) do
    ReleaseOrder[I] := I;
  for I := High(ReleaseOrder) downto 1 do
  begin
    J := Integer(NextRandom mod QWord(I + 1));
    PeerId := ReleaseOrder[I];
    ReleaseOrder[I] := ReleaseOrder[J];
    ReleaseOrder[J] := PeerId;
  end;
  for I := 0 to High(ReleaseOrder) do
    Peers[ReleaseOrder[I]] := nil;
end;

procedure TWorker.RunStrings;
var
  S, Token, CopyS: RawByteString;
  Model: array[0..4095] of Byte;
  TokenLengths: array[0..511] of Byte;
  ModelLength, TokenCount, CodePoints: Integer;
  I, J, Op, TokenLength: Integer;
  Decoded: UnicodeString;
begin
  S := '';
  ModelLength := 0;
  TokenCount := 0;
  CodePoints := 0;
  for I := 0 to 799 do
  begin
    Op := NextRandom mod 5;
    if (Op <> 0) or (TokenCount = 0) then
    begin
      case NextRandom mod 4 of
        0: Token := 'A';
        1: Token := #$C3#$A9;       { U+00E9 }
        2: Token := #$CE#$BB;       { U+03BB }
      else
        Token := #$E2#$82#$AC;      { U+20AC }
      end;
      TokenLength := Length(Token);
      if (ModelLength + TokenLength <= Length(Model)) and
         (TokenCount < Length(TokenLengths)) then
      begin
        S := S + Token;
        for J := 1 to TokenLength do
        begin
          Model[ModelLength] := Byte(Token[J]);
          Inc(ModelLength);
        end;
        TokenLengths[TokenCount] := TokenLength;
        Inc(TokenCount);
        Inc(CodePoints);
        Trace(Format('str+%d/%d', [TokenLength, ModelLength]));
      end;
    end
    else
    begin
      Dec(TokenCount);
      TokenLength := TokenLengths[TokenCount];
      Delete(S, Length(S) - TokenLength + 1, TokenLength);
      Dec(ModelLength, TokenLength);
      Dec(CodePoints);
      Trace(Format('str-%d/%d', [TokenLength, ModelLength]));
    end;

    Check(Length(S) = ModelLength, 'string-byte-length');
    for J := 1 to Length(S) do
      Check(Byte(S[J]) = Model[J - 1], 'string-byte-oracle');
    if (I and 31) = 0 then
    begin
      CopyS := Copy(S, 1, Length(S));
      Check(CopyS = S, 'string-copy');
      Decoded := UTF8Decode(S);
      Check(Length(Decoded) = CodePoints, 'utf8-codepoint-count');
    end;
  end;
end;

procedure TWorker.RunManagedAndInterfaces;
var
  Cells, CellCopy: array of TManagedCell;
  Values: array of IValue;
  I, J: Integer;
  Sum, Expected: Int64;
begin
  SetLength(Cells, 24);
  for I := 0 to High(Cells) do
  begin
    Cells[I].Text := Format('w%d-p%d-cell%d-%s',
      [FId, FPhase, I, RawByteString(#$CE#$BB)]);
    SetLength(Cells[I].Values, 8);
    for J := 0 to High(Cells[I].Values) do
      Cells[I].Values[J] := Int64(I * 101 + J * 17 + FId);
  end;
  SetLength(CellCopy, Length(Cells));
  for I := 0 to High(Cells) do
  begin
    CellCopy[I].Text := Cells[I].Text;
    CellCopy[I].Values := Copy(Cells[I].Values, 0, Length(Cells[I].Values));
  end;
  for I := 0 to High(CellCopy) do
  begin
    Check(CellCopy[I].Text = Cells[I].Text, 'managed-record-string-copy');
    for J := 0 to High(CellCopy[I].Values) do
      Check(CellCopy[I].Values[J] = Int64(I * 101 + J * 17 + FId),
        'managed-record-array-copy');
  end;

  SetLength(Values, 96);
  Expected := 0;
  for I := 0 to High(Values) do
  begin
    Values[I] := TValue.Create(Int64(I) * 37 - FId * 11);
    Inc(Expected, Int64(I) * 37 - FId * 11);
  end;
  Sum := 0;
  for I := High(Values) downto 0 do
    Inc(Sum, Values[I].GetValue);
  Check(Sum = Expected, 'interface-refcount-and-dispatch');
  SetLength(Values, 0);
  SetLength(CellCopy, 0);
  SetLength(Cells, 0);
end;

procedure TWorker.RunArraysAndGenerics;
var
  Actual: array of Int64;
  Model, Scratch: array[0..127] of Int64;
  Box: TIntBox;
  I, J, Op, Position, Count: Integer;
  V, FoldActual, FoldModel: Int64;
begin
  Count := 0;
  for I := 0 to 1199 do
  begin
    Op := NextRandom mod 4;
    Trace(Format('arrop=%d/%d/%d', [I, Op, Count]));
    if ((Op = 0) or (Count = 0)) and (Count < Length(Model)) then
    begin
      V := Int64(NextRandom and $7FFFFFFF) - $3FFFFFFF;
      SetLength(Actual, Count + 1);
      Actual[Count] := V;
      Model[Count] := V;
      Inc(Count);
      Trace(Format('arr+/%d', [Count]));
    end
    else if (Op = 1) and (Count > 0) then
    begin
      Position := Integer(NextRandom mod QWord(Count));
      Trace(Format('arrdel-pos=%d/%d', [Position, Count]));
      for J := Position to Count - 2 do
      begin
        Trace(Format('arrshift=%d/%d', [J, Count]));
        Actual[J] := Actual[J + 1];
      end;
      if Position < Count - 1 then
        Move(Model[Position + 1], Model[Position],
          (Count - Position - 1) * SizeOf(Model[0]));
      Trace('arrshift-complete');
      Dec(Count);
      SetLength(Actual, Count);
      Trace(Format('arr-%d/%d', [Position, Count]));
    end
    else if (Op = 2) then
    begin
      for J := 0 to Count - 1 do
        Scratch[J] := Model[Count - 1 - J];
      J := 0;
      while J < Count div 2 do
      begin
        V := Actual[J];
        Actual[J] := Actual[Count - 1 - J];
        Actual[Count - 1 - J] := V;
        Inc(J);
      end;
      for J := 0 to Count - 1 do
        Model[J] := Scratch[J];
    end;

    Check(Length(Actual) = Count, 'dynamic-array-length');
    Trace(Format('arrcheck/%d/%d', [Length(Actual), Count]));
    FoldActual := 0;
    FoldModel := 0;
    for J := 0 to Count - 1 do
    begin
      Trace(Format('arridx=%d/%d', [J, Count]));
      Check(Actual[J] = Model[J], 'dynamic-array-model');
      FoldActual := (FoldActual xor Actual[J]) + J * 13;
      FoldModel := (FoldModel xor Model[J]) + J * 13;
    end;
    Trace('arrfold-complete');
    Box.Value := FoldActual;
    Trace('arrbox-assigned');
    Check(Box.Value = FoldModel, 'generic-record-fold');
    Trace('arrbox-checked');
  end;
end;

procedure TWorker.RunExceptionsAndCaptures;
var
  ParentText, ModelText: RawByteString;
  ParentBase, ModelBase, Actual, Expected: Int64;
  I, FinallyCount, RaisedCount: Integer;

  function CapturedStep(Index: Integer): Int64;
  begin
    ParentText := ParentText + Chr(Ord('a') + (Index mod 26));
    if Length(ParentText) > 32 then
      Delete(ParentText, 1, 1);
    Inc(ParentBase, Index * 3 + Length(ParentText));
    Result := ParentBase xor (Length(ParentText) * 257);
  end;

{$ifdef HAS_ANONYMOUS_FUNCTIONS}
type
  TIntTransform = reference to function(X: Int64): Int64;
var
  Transform: TIntTransform;
  CapturedBias: Int64;
{$endif}
begin
  ParentText := '';
  ModelText := '';
  ParentBase := FId * 19 + FPhase;
  ModelBase := ParentBase;
  Actual := 0;
  Expected := 0;
  for I := 0 to 499 do
  begin
    Actual := Actual xor CapturedStep(I);
    ModelText := ModelText + Chr(Ord('a') + (I mod 26));
    if Length(ModelText) > 32 then
      Delete(ModelText, 1, 1);
    Inc(ModelBase, I * 3 + Length(ModelText));
    Expected := Expected xor (ModelBase xor (Length(ModelText) * 257));
  end;
  Check(ParentText = ModelText, 'nested-capture-parent-string');
  Check(ParentBase = ModelBase, 'nested-capture-parent-frame');
  Check(Actual = Expected, 'nested-capture-result');

  FinallyCount := 0;
  RaisedCount := 0;
  for I := 0 to 255 do
  begin
    try
      try
        if ((I * 17 + FId * 5 + FPhase) mod 19) = 0 then
          raise ERangeError.CreateFmt('expected-%d', [I]);
      finally
        Inc(FinallyCount);
      end;
    except
      on E: ERangeError do
        Inc(RaisedCount);
    end;
  end;
  Check(FinallyCount = 256, 'exception-finally-count');
  Expected := 0;
  for I := 0 to 255 do
    if ((I * 17 + FId * 5 + FPhase) mod 19) = 0 then
      Inc(Expected);
  Check(RaisedCount = Expected, 'exception-raised-count');

{$ifdef HAS_ANONYMOUS_FUNCTIONS}
  CapturedBias := FId * 1000 + FPhase * 10;
  Transform := function(X: Int64): Int64
    begin
      Inc(CapturedBias, 3);
      Result := X * 7 + CapturedBias;
    end;
  Actual := 0;
  for I := 0 to 63 do
    Inc(Actual, Transform(I));
  Expected := 0;
  ModelBase := FId * 1000 + FPhase * 10;
  for I := 0 to 63 do
  begin
    Inc(ModelBase, 3);
    Inc(Expected, I * 7 + ModelBase);
  end;
  Check(Actual = Expected, 'anonymous-method-capture');
  Check(CapturedBias = ModelBase, 'anonymous-method-parent-state');
{$endif}
end;

procedure TWorker.RunAliasingAndMath;
var
  Wide: QWord;
  LowWord: LongWord absolute Wide;
  Bytes: array[0..7] of Byte absolute Wide;
  A, B, Product, ProductModel, Quotient: QWord;
  I: Integer;
  X, Y, Hypotenuse: Double;
begin
  Wide := QWord($1122334455667788);
  Check(LowWord = $55667788, 'absolute-lowword-read');
  Bytes[0] := $AA;
  Bytes[3] := $BB;
  Check((Wide and QWord($00000000FF0000FF)) = QWord($00000000BB0000AA),
    'absolute-byte-write');
  LowWord := $DEADBEEF;
  Check((Wide and $FFFFFFFF) = $DEADBEEF, 'absolute-lowword-write');

  A := NextRandom and $FFFF;
  B := (NextRandom and $7FF) + 1;
  Product := A * B;
  ProductModel := 0;
  for I := 1 to B do
    Inc(ProductModel, A);
  Check(Product = ProductModel, 'integer-multiply-oracle');
  Quotient := Product div B;
  Check(Quotient = A, 'integer-division-oracle');

  X := 3.0 * (FId + 1);
  Y := 4.0 * (FId + 1);
  Hypotenuse := Sqrt(X * X + Y * Y);
  Check(Abs(Hypotenuse - 5.0 * (FId + 1)) < 1E-12,
    'float-pythagorean-oracle');
end;

procedure TWorker.RunOptimizerOracles;
type
  TOemAnsi = type AnsiString(866);
var
  Value, Divisor, ActualQ, ActualR, OracleQ, OracleR: LongInt;
  Magnitude, Denominator, QMagnitude, RMagnitude, Candidate: QWord;
  MixedActual, MixedOracle: LongInt;
  B: Byte;
  S: ShortInt;
  Selector, Shift, I, J, ForCount, WhileCount: Integer;
  ForSum, WhileSum: Int64;
  OemText: TOemAnsi;

  procedure OptimizerCheck(Condition: Boolean; const Name: RawByteString);
  begin
    try
      Check(Condition, Name);
    except
      on E: Exception do
        CaptureFailure(E);
    end;
  end;
begin
  { Exercise promotion and sign extension of mixed 8-bit operands. The oracle
    first converts both operands to the result width. }
  for I := 0 to 255 do
  begin
    B := Byte(NextRandom);
    S := ShortInt(Byte(NextRandom));
    case NextRandom mod 3 of
      0:
        begin
          MixedActual := B or S;
          MixedOracle := LongInt(B) or LongInt(S);
        end;
      1:
        begin
          MixedActual := B xor S;
          MixedOracle := LongInt(B) xor LongInt(S);
        end;
    else
      begin
        MixedActual := B and S;
        MixedOracle := LongInt(B) and LongInt(S);
      end;
    end;
    Check(MixedActual = MixedOracle, 'mixed-width-bitwise-promotion');
  end;

  { Compare for-loop execution with an independently structured while loop;
    neither oracle relies on the post-loop value of the Pascal counter. }
  for I := 0 to 63 do
  begin
    Selector := Integer(NextRandom mod 40);
    ForCount := 0;
    ForSum := 0;
    for J := -Selector to Selector do
    begin
      Inc(ForCount);
      Inc(ForSum, Int64(J) * J + 3 * J - 7);
    end;
    WhileCount := 0;
    WhileSum := 0;
    J := -Selector;
    while J <= Selector do
    begin
      Inc(WhileCount);
      Inc(WhileSum, Int64(J) * J + 3 * J - 7);
      Inc(J);
    end;
    Check(ForCount = WhileCount, 'for-while-iteration-count');
    Check(ForSum = WhileSum, 'for-while-sum-oracle');
  end;

  { A typed AnsiString must keep its declared code page after Str writes it. }
  Str(123456 + FId * 10 + FPhase, OemText);
  Check(StringCodePage(OemText) = 866, 'typed-ansistring-str-codepage');
  Check(Pos('123', string(OemText)) = 1, 'typed-ansistring-str-content');

  { Keep the known-failing mutation last so every earlier optimizer oracle is
    exercised even when latest Unleashed reports the division regression. }
  for I := 0 to 511 do
  begin
    Value := LongInt(NextRandom mod 2000000001) - 1000000000;
    Selector := NextRandom and 7;
    case Selector of
      0: begin Divisor := -19; ActualQ := Value div -19; ActualR := Value mod -19; end;
      1: begin Divisor :=  19; ActualQ := Value div  19; ActualR := Value mod  19; end;
      2: begin Divisor :=  -7; ActualQ := Value div  -7; ActualR := Value mod  -7; end;
      3: begin Divisor :=   7; ActualQ := Value div   7; ActualR := Value mod   7; end;
      4: begin Divisor :=  -3; ActualQ := Value div  -3; ActualR := Value mod  -3; end;
      5: begin Divisor :=   3; ActualQ := Value div   3; ActualR := Value mod   3; end;
      6: begin Divisor := -512; ActualQ := Value div -512; ActualR := Value mod -512; end;
    else
      begin Divisor := 512; ActualQ := Value div 512; ActualR := Value mod 512; end;
    end;

    { The oracle is unsigned binary long division and shares neither div/mod
      nor the compiler's constant-divisor lowering. }
    if Value < 0 then
      Magnitude := QWord(-Int64(Value))
    else
      Magnitude := QWord(Value);
    if Divisor < 0 then
      Denominator := QWord(-Int64(Divisor))
    else
      Denominator := QWord(Divisor);
    QMagnitude := 0;
    RMagnitude := Magnitude;
    for Shift := 31 downto 0 do
    begin
      Candidate := Denominator shl Shift;
      if Candidate <= RMagnitude then
      begin
        Dec(RMagnitude, Candidate);
        QMagnitude := QMagnitude or (QWord(1) shl Shift);
      end;
    end;
    if (Value < 0) xor (Divisor < 0) then
      OracleQ := -LongInt(QMagnitude)
    else
      OracleQ := LongInt(QMagnitude);
    if Value < 0 then
      OracleR := -LongInt(RMagnitude)
    else
      OracleR := LongInt(RMagnitude);
    Trace(Format('divmod-v=%d/d=%d/a=%d,%d/o=%d,%d',
      [Value, Divisor, ActualQ, ActualR, OracleQ, OracleR]));
    OptimizerCheck(ActualQ = OracleQ, 'signed-constant-div-binary-oracle');
    OptimizerCheck(ActualR = OracleR, 'signed-constant-mod-binary-oracle');
    OptimizerCheck(Int64(ActualQ) * Divisor + ActualR = Value,
      'signed-divmod-recomposition');
  end;
end;

{$push}{$R-}
procedure TWorker.RunKnownRuntimeRegressions;
var
  LoopRecord: TUnsignedLoopRecord;
  Data: TBytes;
  Position, Value, BitIndex: Integer;
  BitResult: SizeUInt;
  BitResult32: LongWord;
  MaskByte: Byte;
  MaskWord: Word;
  MaskDWord: DWord;
  MaskQWord: QWord;
  Milliseconds: Int64;
  ActualFloat, OracleFloat: Double;
  ActualBits, OracleBits: QWord;
  TextPointer: PChar;
  PointerValue, NormalPointer, InlinePointer: Pointer;

  procedure KnownCheck(Condition: Boolean; const Name: RawByteString);
  begin
    try
      Check(Condition, Name);
    except
      on E: Exception do
        CaptureFailure(E);
    end;
  end;
begin
  KnownLongIndex := 0;
  ActualFloat := KnownAbsoluteDouble;
  Move(ActualFloat, ActualBits, SizeOf(ActualBits));
  OracleBits := (QWord(LongWord(KnownLongValues[1])) shl 32) or
    QWord(LongWord(KnownLongValues[0]));
  KnownCheck(ActualBits = OracleBits,
    'known-absolute-result-double');

  LoopRecord.EntryCount := 0;
  KnownCheck(KnownUnsignedLoop(@LoopRecord) = 0, 'known-unsigned-empty-loop');
  KnownCheck(KnownConditionalMove(0, -1) = -1, 'known-cmov-negative-int64');
  KnownCheck(KnownConditionalMove(17, 1) = 17, 'known-cmov-positive-int64');

  KnownCheck(KnownRotateWords(QWord($1122334455667788)) =
    QWord($3344556677881122), 'known-absolute-result-layout');
  PointerValue := Pointer(PtrUInt($1122334455667788));
  NormalPointer := KnownConvertPointer(PointerValue);
  InlinePointer := KnownConvertPointerInline(PointerValue);
  KnownCheck(PtrUInt(NormalPointer) = PtrUInt($3344556677881122),
    'known-absolute-pointer-result');
  KnownCheck(PtrUInt(InlinePointer) = PtrUInt($3344556677881122),
    'known-absolute-pointer-result-inline');
  KnownCheck(KnownShiftRight(1) = 0, 'known-inline-shift-right');
  KnownCheck(KnownShiftLeft(1) = 0, 'known-inline-shift-left');

  MaskByte := 1;
  for BitIndex := 0 to SizeOf(MaskByte) * 8 do
  begin
    BitResult := BsfByte(MaskByte);
    KnownCheck(((MaskByte = 0) and (BitResult = $FF)) or
      ((MaskByte <> 0) and (BitResult = BitIndex)), 'known-bsf-byte');
    MaskByte := MaskByte shl 1;
  end;
  MaskWord := 1;
  for BitIndex := 0 to SizeOf(MaskWord) * 8 do
  begin
    BitResult := BsfWord(MaskWord);
    KnownCheck(((MaskWord = 0) and (BitResult = $FF)) or
      ((MaskWord <> 0) and (BitResult = BitIndex)), 'known-bsf-word');
    MaskWord := MaskWord shl 1;
  end;
  MaskDWord := 1;
  for BitIndex := 0 to SizeOf(MaskDWord) * 8 do
  begin
    BitResult32 := BsfDWord(MaskDWord);
    KnownCheck(((MaskDWord = 0) and (BitResult32 = $FF)) or
      ((MaskDWord <> 0) and (BitResult32 = LongWord(BitIndex))),
      'known-bsf-dword');
    MaskDWord := MaskDWord shl 1;
  end;
  MaskQWord := 1;
  for BitIndex := 0 to SizeOf(MaskQWord) * 8 do
  begin
    BitResult32 := BsfQWord(MaskQWord);
    KnownCheck(((MaskQWord = 0) and (BitResult32 = $FF)) or
      ((MaskQWord <> 0) and (BitResult32 = LongWord(BitIndex))),
      'known-bsf-qword-longword');
    BitResult := BsfQWord(MaskQWord);
    KnownCheck(((MaskQWord = 0) and (BitResult = $FF)) or
      ((MaskQWord <> 0) and (BitResult = SizeUInt(BitIndex))),
      'known-bsf-qword-sizeuint');
    MaskQWord := MaskQWord shl 1;
  end;

  Milliseconds := 1356062706000;
  ActualFloat := (Milliseconds / 86400000.0) + 25569.0;
  OracleBits := QWord($40E426057258BF26);
  Move(OracleBits, OracleFloat, SizeOf(OracleFloat));
  KnownCheck(Abs(ActualFloat - OracleFloat) <= 1E-9,
    'known-int64-float-literal');

  SetLength(Data, 2);
  Data[0] := 2;
  Data[1] := 99;
  Position := 0;
  Value := KnownReadSubLength(Data, Position);
  KnownCheck((Value = 2) and (Position = 1), 'known-narrow-compare');

  TextPointer := KnownInlineShortString('hello');
  try
    KnownCheck((TextPointer[0] = 'h') and (TextPointer[1] = 'e') and
      (TextPointer[2] = 'l') and (TextPointer[3] = 'l') and
      (TextPointer[4] = 'o') and (TextPointer[5] = #0),
      'known-inline-shortstring-literal');
  finally
    FreeMem(TextPointer);
  end;
end;
{$pop}

procedure TWorker.RunPortableStateMachine;
var
  ScenarioResult: TPortableResult;
begin
  RunPortableScenario(FSeed, FId, FPhase, ScenarioResult);
  PortableResults[FPhase, FId] := ScenarioResult;
end;

procedure TWorker.RunPhase;
var
  CategoryOrder: array[0..CategoryCount - 1] of Integer;
  I, J, Category: Integer;
begin
  Trace(Format('phase=%d state=%u', [FPhase, FState]));
  for I := 0 to High(CategoryOrder) do
    CategoryOrder[I] := I;
  for I := High(CategoryOrder) downto 1 do
  begin
    J := Integer(NextRandom mod QWord(I + 1));
    Category := CategoryOrder[I];
    CategoryOrder[I] := CategoryOrder[J];
    CategoryOrder[J] := Category;
  end;
  for I := 0 to High(CategoryOrder) do
  begin
    Category := CategoryOrder[I];
    FContext := 'category=' + RawByteString(IntToStr(Category));
    try
      case Category of
        0:
          begin
            Trace('category=strings');
            RunStrings;
          end;
        1:
          begin
            Trace('category=arrays-generics');
            RunArraysAndGenerics;
          end;
        2:
          begin
            Trace('category=managed-interfaces');
            RunManagedAndInterfaces;
          end;
        3:
          begin
            Trace('category=exceptions-captures');
            RunExceptionsAndCaptures;
          end;
        4:
          begin
            Trace('category=aliasing-math');
            RunAliasingAndMath;
          end;
        5:
          begin
            Trace('category=optimizer-oracles');
            RunOptimizerOracles;
          end;
        6:
          begin
            Trace('category=portable-state-machine');
            RunPortableStateMachine;
          end;
        7:
          begin
            Trace('category=known-runtime-regressions');
            RunKnownRuntimeRegressions;
          end;
      end;
    except
      on E: Exception do
        CaptureFailure(E);
    end;
  end;
end;

procedure TWorker.Execute;
const
  PhaseSalt = QWord($9E3779B97F4A7C15);
  WorkerSalt = QWord($D1B54A32D192ED03);
var
  Phase, NowActive, OldPeak: Integer;
begin
  ThreadCookie := FSeed xor QWord(FId + 1) * QWord($D1B54A32D192ED03);
  for Phase := 0 to PhaseCount - 1 do
  begin
    FPhase := Phase;
    PublishedValues[Phase, FId] :=
      (FSeed xor QWord(Phase + 1) * PhaseSalt) + QWord(FId + 1) * WorkerSalt;
    PublishedInterfaces[Phase, FId] :=
      TValue.CreatePayload(Phase * 100 + FId, Phase, FId);
    InterlockedIncrement(PhaseReady[Phase]);
    RTLEventWaitFor(PhaseGates[Phase, FId]);
    FContext := 'cross-thread';
    try
      Check(ThreadCookie = (FSeed xor QWord(FId + 1) * WorkerSalt),
        'thread-local-storage');
      RunCrossThreadChecks;
    except
      on E: Exception do
        CaptureFailure(E);
    end;

    NowActive := InterlockedIncrement(ActiveWorkers);
    OldPeak := InterlockedCompareExchange(PeakWorkers, 0, 0);
    while NowActive > OldPeak do
    begin
      if InterlockedCompareExchange(PeakWorkers, NowActive, OldPeak) = OldPeak then
        Break;
      OldPeak := InterlockedCompareExchange(PeakWorkers, 0, 0);
    end;
    try
      FContext := 'phase-workload';
      try
        RunPhase;
      except
        on E: Exception do
          CaptureFailure(E);
      end;
    finally
      InterlockedDecrement(ActiveWorkers);
    end;
    InterlockedIncrement(ThreadVisits);
    InterlockedIncrement(PhaseDone[Phase]);
  end;
end;

procedure EmitKnownFacts;
var
  LoopRecord: TUnsignedLoopRecord;
  Data: TBytes;
  Position, Value, Quotient, Remainder: Integer;
  ActualFloat: Double;
  ActualBits: QWord;
  PointerValue: Pointer;
  TextPointer: PChar;
begin
  KnownLongIndex := 0;
  ActualFloat := KnownAbsoluteDouble;
  Move(ActualFloat, ActualBits, SizeOf(ActualBits));
  WriteLn(StdErr, 'MEGA_FACT known-absolute-result-double=',
    IntToHex(ActualBits, 16));

  LoopRecord.EntryCount := 0;
  WriteLn(StdErr, 'MEGA_FACT known-unsigned-empty-loop=',
    KnownUnsignedLoop(@LoopRecord));
  WriteLn(StdErr, 'MEGA_FACT known-cmov=', KnownConditionalMove(0, -1), ',',
    KnownConditionalMove(17, 1));
  WriteLn(StdErr, 'MEGA_FACT known-absolute-result-layout=',
    IntToHex(KnownRotateWords(QWord($1122334455667788)), 16));

  PointerValue := Pointer(PtrUInt($1122334455667788));
  WriteLn(StdErr, 'MEGA_FACT known-absolute-pointer-result=',
    IntToHex(PtrUInt(KnownConvertPointer(PointerValue)), 16));
  WriteLn(StdErr, 'MEGA_FACT known-absolute-pointer-result-inline=',
    IntToHex(PtrUInt(KnownConvertPointerInline(PointerValue)), 16));
  WriteLn(StdErr, 'MEGA_FACT known-inline-shifts=', KnownShiftRight(1), ',',
    KnownShiftLeft(1));
  WriteLn(StdErr, 'MEGA_FACT known-bsf-zero=', BsfByte(0), ',', BsfWord(0), ',',
    BsfDWord(0), ',', BsfQWord(0));

  Value := 162784145;
  Quotient := Value div -19;
  Remainder := Value mod -19;
  WriteLn(StdErr, 'MEGA_FACT known-negative-constant-divmod=', Quotient, ',',
    Remainder);

  ActualFloat := (Int64(1356062706000) / 86400000.0) + 25569.0;
  Move(ActualFloat, ActualBits, SizeOf(ActualBits));
  WriteLn(StdErr, 'MEGA_FACT known-int64-float-bits=', IntToHex(ActualBits, 16));

  SetLength(Data, 2);
  Data[0] := 2;
  Data[1] := 99;
  Position := 0;
  Value := KnownReadSubLength(Data, Position);
  WriteLn(StdErr, 'MEGA_FACT known-narrow-compare=', Value, ',', Position);

  TextPointer := KnownInlineShortString('hello');
  try
    WriteLn(StdErr, 'MEGA_FACT known-inline-shortstring-literal=',
      IntToHex(Ord(TextPointer[0]), 2), IntToHex(Ord(TextPointer[1]), 2),
      IntToHex(Ord(TextPointer[2]), 2), IntToHex(Ord(TextPointer[3]), 2),
      IntToHex(Ord(TextPointer[4]), 2), IntToHex(Ord(TextPointer[5]), 2));
  finally
    FreeMem(TextPointer);
  end;
end;

function ReadSeed: QWord;
var
  Code: Integer;
begin
  Result := DefaultSeed;
  if ParamCount > 0 then
  begin
    Val(ParamStr(1), Result, Code);
    if Code <> 0 then
      raise EConvertError.Create('seed must be an unsigned decimal integer');
  end;
end;

function WaitForCounter(var Counter: LongInt; Expected, TimeoutMs: LongInt): Boolean;
var
  Deadline: QWord;
begin
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  repeat
    if InterlockedCompareExchange(Counter, 0, 0) = Expected then
      Exit(True);
    Sleep(1);
  until GetTickCount64 >= Deadline;
  Result := False;
end;

procedure ReleaseAllPhaseGates;
var
  Phase, WorkerId: Integer;
begin
  for Phase := 0 to PhaseCount - 1 do
    for WorkerId := 0 to WorkerCount - 1 do
    begin
      RTLEventSetEvent(PhaseGates[Phase, WorkerId]);
      RTLEventSetEvent(CopyGates[Phase, WorkerId]);
    end;
end;

procedure RunMegaRuntime(Seed: QWord; out Report: TMegaRuntimeReport);
var
  Workers: array[0..WorkerCount - 1] of TWorker;
  PortableDigest: QWord;
  PortableChecks: Int64;
  I, Phase: Integer;
  Failed: Boolean;
begin
  Report.Failed := False;
  Report.ErrorText := '';
  Report.Checks := 0;
  Report.Visits := 0;
  Report.CrossThreadVisits := 0;
  Report.PeakWorkers := 0;
  Report.ManagedInitializes := 0;
  Report.ManagedFinalizes := 0;
  Report.PortableChecks := 0;
  Report.PortableDigest := 0;
  FillChar(PhaseReady, SizeOf(PhaseReady), 0);
  FillChar(PhaseCopied, SizeOf(PhaseCopied), 0);
  FillChar(PhaseDone, SizeOf(PhaseDone), 0);
  AtomicChecks := 0;
  ManagedInitializes := 0;
  ManagedFinalizes := 0;
  ThreadVisits := 0;
  CrossThreadVisits := 0;
  ActiveWorkers := 0;
  PeakWorkers := 0;
  for Phase := 0 to PhaseCount - 1 do
    for I := 0 to WorkerCount - 1 do
    begin
      PhaseGates[Phase, I] := RTLEventCreate;
      CopyGates[Phase, I] := RTLEventCreate;
    end;
  for I := 0 to WorkerCount - 1 do
  begin
    Workers[I] := TWorker.Create(I, Seed);
    Workers[I].Start;
  end;

  for Phase := 0 to PhaseCount - 1 do
  begin
    if not WaitForCounter(PhaseReady[Phase], WorkerCount, 30000) then
    begin
      WriteLn(StdErr, 'MEGA_FAIL phase-ready-timeout phase=', Phase,
        ' ready=', PhaseReady[Phase]);
      ReleaseAllPhaseGates;
      raise EMegaFailure.CreateFmt('phase-ready-timeout phase=%d ready=%d',
        [Phase, PhaseReady[Phase]]);
    end;
    for I := 0 to WorkerCount - 1 do
      RTLEventSetEvent(PhaseGates[Phase, I]);
    if not WaitForCounter(PhaseCopied[Phase], WorkerCount, 30000) then
    begin
      WriteLn(StdErr, 'MEGA_FAIL phase-copy-timeout phase=', Phase,
        ' copied=', PhaseCopied[Phase]);
      ReleaseAllPhaseGates;
      raise EMegaFailure.CreateFmt('phase-copy-timeout phase=%d copied=%d',
        [Phase, PhaseCopied[Phase]]);
    end;
    for I := 0 to WorkerCount - 1 do
    begin
      PublishedInterfaces[Phase, I] := nil;
      RTLEventSetEvent(CopyGates[Phase, I]);
    end;
    if not WaitForCounter(PhaseDone[Phase], WorkerCount, 30000) then
    begin
      WriteLn(StdErr, 'MEGA_FAIL phase-done-timeout phase=', Phase,
        ' done=', PhaseDone[Phase]);
      ReleaseAllPhaseGates;
      raise EMegaFailure.CreateFmt('phase-done-timeout phase=%d done=%d',
        [Phase, PhaseDone[Phase]]);
    end;
  end;

  Failed := False;
  for I := 0 to WorkerCount - 1 do
    Workers[I].WaitFor;
  for I := 0 to WorkerCount - 1 do
    if Workers[I].ErrorText <> '' then
    begin
      if Report.ErrorText <> '' then
        Report.ErrorText := Report.ErrorText + ' | ';
      Report.ErrorText := Report.ErrorText + Workers[I].ErrorText;
      Failed := True;
    end;
  for I := 0 to WorkerCount - 1 do
    Workers[I].Free;
  for Phase := 0 to PhaseCount - 1 do
    for I := 0 to WorkerCount - 1 do
    begin
      RTLEventDestroy(PhaseGates[Phase, I]);
      RTLEventDestroy(CopyGates[Phase, I]);
    end;

  PortableDigest := QWord($CBF29CE484222325);
  PortableChecks := 0;
  for Phase := 0 to PhaseCount - 1 do
    for I := 0 to WorkerCount - 1 do
    begin
      Inc(PortableChecks, PortableResults[Phase, I].Checks);
      FoldPortableResult(PortableDigest, PortableResults[Phase, I], I, Phase);
    end;

  if ManagedInitializes <> ManagedFinalizes then
  begin
    if Report.ErrorText <> '' then
      Report.ErrorText := Report.ErrorText + ' | ';
    Report.ErrorText := Report.ErrorText + RawByteString(Format(
      'managed-lifetime init=%d final=%d',
      [ManagedInitializes, ManagedFinalizes]));
    Failed := True;
  end;
  if ThreadVisits <> WorkerCount * PhaseCount then
  begin
    if Report.ErrorText <> '' then
      Report.ErrorText := Report.ErrorText + ' | ';
    Report.ErrorText := Report.ErrorText + RawByteString(Format(
      'deterministic-interleave visits=%d expected=%d',
      [ThreadVisits, WorkerCount * PhaseCount]));
    Failed := True;
  end;
  if CrossThreadVisits <> WorkerCount * WorkerCount * PhaseCount then
  begin
    if Report.ErrorText <> '' then
      Report.ErrorText := Report.ErrorText + ' | ';
    Report.ErrorText := Report.ErrorText + RawByteString(Format(
      'cross-thread visits=%d expected=%d',
      [CrossThreadVisits, WorkerCount * WorkerCount * PhaseCount]));
    Failed := True;
  end;
  if PeakWorkers < 2 then
  begin
    if Report.ErrorText <> '' then
      Report.ErrorText := Report.ErrorText + ' | ';
    Report.ErrorText := Report.ErrorText + RawByteString(Format(
      'no-concurrent-overlap peak=%d', [PeakWorkers]));
    Failed := True;
  end;
  Report.Failed := Failed;
  Report.Checks := AtomicChecks;
  Report.Visits := ThreadVisits;
  Report.CrossThreadVisits := CrossThreadVisits;
  Report.PeakWorkers := PeakWorkers;
  Report.ManagedInitializes := ManagedInitializes;
  Report.ManagedFinalizes := ManagedFinalizes;
  Report.PortableChecks := PortableChecks;
  Report.PortableDigest := PortableDigest;
end;

end.
