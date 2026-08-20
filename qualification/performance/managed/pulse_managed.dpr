program pulse_managed;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch anonymousfunctions}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Classes,
  Variants,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas',
  pulse_managed_targets in 'pulse_managed_targets.pas';

type
  IPulseValue = interface
    ['{79479902-C6CA-4B70-BE70-64242FCF39CA}']
    function GetValue: UInt64;
  end;

  TPulseValue = class(TInterfacedObject, IPulseValue)
  private
    FValue: UInt64;
  public
    constructor Create(Value: UInt64);
    function GetValue: UInt64;
  end;

  TPulseClosure = reference to function(Value: UInt64): UInt64;

const
  InnerCount = 32;

var
  SourceUnicode: array[0..63] of UnicodeString;
  SourceRaw: array[0..63] of RawByteString;
  SourceBytes: array[0..63] of TBytes;
  SourceInterfaces: array[0..63] of IPulseValue;
  SourceVariants: array[0..63] of Variant;

constructor TPulseValue.Create(Value: UInt64);
begin
  inherited Create;
  FValue := Value;
end;

function TPulseValue.GetValue: UInt64;
begin
  Result := FValue;
end;

{ === audit pack A: ignored managed results and managed out forwarding === }

var
  IgnoredSideEffect: UInt64;
  IgnoredIndex: Integer;

function FetchStatusText: UnicodeString;
begin
  Result := SourceUnicode[IgnoredIndex and 63];
  Inc(IgnoredSideEffect, Length(Result));
end;

function FetchStatusIntf: IPulseValue;
begin
  Result := SourceInterfaces[IgnoredIndex and 63];
  Inc(IgnoredSideEffect);
end;

procedure GetNameInner(out R: UnicodeString);
begin
  R := SourceUnicode[IgnoredIndex and 63];
end;

procedure GetNameForward(out R: UnicodeString);
begin
  GetNameInner(R);
end;

var
  FetchTextProc: function: UnicodeString;
  FetchIntfProc: function: IPulseValue;
  GetForwardProc: procedure(out R: UnicodeString);

function CaseIgnoredStringResult(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  { the call result is deliberately dropped: the oracle lives in the
    side-effect counter, the cost lives in the hidden result temp }
  IgnoredSideEffect := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      IgnoredIndex := I + J;
      FetchTextProc();
    end;
  Result := IgnoredSideEffect;
end;

function CaseIgnoredInterfaceResult(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  IgnoredSideEffect := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      IgnoredIndex := I + J;
      FetchIntfProc();
    end;
  Result := IgnoredSideEffect;
end;

function CaseOutStringForwarding(Iterations: Integer): UInt64;
var
  I, J: Integer;
  R: UnicodeString;
  Digest: UInt64;
begin
  Digest := 0;
  R := SourceUnicode[0];
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      IgnoredIndex := I + J;
      GetForwardProc(R);
      Digest := Digest + UInt64(Length(R));
    end;
  Result := Digest;
end;

function CaseUnicodeAssign(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      S := SourceUnicode[(I + J) and 63];
      Digest := Digest + UInt64(Length(S));
    end;
  Result := Digest;
end;

{ multithreaded variants: a sleeper thread flips the runtime into the
  locked refcount mode, matching the product (always threaded) and
  Delphi (unconditional lock).  Pulse isolates cases per process, so
  the flag does not leak into the other cases. }

var
  SleeperHandle: TThread = nil;

type
  TSleeper = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TSleeper.Execute;
begin
  { sleep forever: the thread exists only to raise IsMultithread and
    must never wake up during runtime finalization }
  Sleep(High(Cardinal));
end;

procedure EnsureThreaded;
begin
  if SleeperHandle = nil then
  begin
    SleeperHandle := TSleeper.Create(False);
    Sleep(50);
  end;
end;

function CaseUnicodeAssignMT(Iterations: Integer): UInt64;
begin
  EnsureThreaded;
  Result := CaseUnicodeAssign(Iterations);
end;

function CaseUnicodeCopyPpu(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      S := CopyUnicode(SourceUnicode[(I + J) and 63]);
      Digest := Digest + UInt64(Length(S));
    end;
  Result := Digest;
end;

function CaseUnicodeConcat(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      S := SourceUnicode[J] + ':' + SourceUnicode[(J + I) and 63];
      Digest := Digest + UInt64(Length(S));
    end;
  Result := Digest;
end;

function CaseRawAssign(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: RawByteString;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      S := SourceRaw[(I + J) and 63];
      Digest := Digest + UInt64(Length(S));
    end;
  Result := Digest;
end;

function CaseRawAssignMT(Iterations: Integer): UInt64;
begin
  EnsureThreaded;
  Result := CaseRawAssign(Iterations);
end;

function CaseDynamicArrayAssign(Iterations: Integer): UInt64;
var
  I, J: Integer;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      B := SourceBytes[(I + J) and 63];
      Digest := Digest + UInt64(Length(B));
    end;
  Result := Digest;
end;

function CaseDynamicArrayCopy(Iterations: Integer): UInt64;
var
  I, J: Integer;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      B := CopyBytes(SourceBytes[(I + J) and 63]);
      Digest := Digest + UInt64(Length(B)) + B[0];
    end;
  Result := Digest;
end;

function CaseInterfaceCopy(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: IPulseValue;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      V := SourceInterfaces[(I + J) and 63];
      Digest := Digest + V.GetValue;
    end;
  Result := Digest;
end;

function CaseVariantNumeric(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: Variant;
  Digest: Int64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      V := SourceVariants[(I + J) and 63];
      V := V * 3 + 7;
      Digest := Digest + Int64(V);
    end;
  Result := UInt64(Digest);
end;

function CaseManagedRecord(Iterations: Integer): UInt64;
var
  I, J: Integer;
  R: TPulseManagedRecord;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      R := MakeManagedRecord((I + J) and 63);
      Digest := Digest + UInt64(Length(R.Name)) + UInt64(Length(R.Payload)) +
        R.Value;
    end;
  Result := Digest;
end;

function CaseEarlyExit(Iterations: Integer): UInt64;
var
  I: Integer;
  Digest: UInt64;

  function Inner(Index: Integer): UInt64;
  var
    S: UnicodeString;
    B: TBytes;
  begin
    S := SourceUnicode[Index and 63];
    B := CopyBytes(SourceBytes[(Index + 1) and 63]);
    If (Index and 1) = 0 then
      Exit(UInt64(Length(S)));
    Result := UInt64(Length(S)) + UInt64(Length(B));
  end;

begin
  Digest := 0;
  for I := 1 to Iterations * InnerCount do
    Digest := Digest + Inner(I);
  Result := Digest;
end;

function CaseExceptionCleanup(Iterations: Integer): UInt64;
var
  I, J: Integer;
  S: UnicodeString;
  B: TBytes;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
      try
        S := SourceUnicode[(I + J) and 63];
        B := CopyBytes(SourceBytes[(I + J + 1) and 63]);
        If J = 7 then
          raise EAbort.Create('pulse');
        Digest := Digest + UInt64(Length(S)) + UInt64(Length(B));
      except
        on EAbort do
          Digest := Digest + 1;
      end;
  Result := Digest;
end;

function MakeClosure(Bias: UInt64): TPulseClosure;
begin
  Result := function(Value: UInt64): UInt64
    begin
      Result := Value + Bias;
    end;
end;

function CaseClosureCreateInvoke(Iterations: Integer): UInt64;
var
  I, J: Integer;
  C: TPulseClosure;
  Digest: UInt64;
begin
  Digest := 0;
  for I := 1 to Iterations do
    for J := 0 to 7 do
    begin
      C := MakeClosure(UInt64(I + J));
      Digest := Digest + C(UInt64(J));
    end;
  Result := Digest;
end;

procedure InitializeSources;
var
  I, J: Integer;
begin
  for I := 0 to 63 do
  begin
    SourceUnicode[I] := UnicodeString('symbol-') + UnicodeString(IntToStr(I)) +
      UnicodeString('-price');
    SourceRaw[I] := RawByteString(AnsiString('raw-symbol-' + IntToStr(I)));
    SetLength(SourceBytes[I], 16 + (I and 31));
    for J := 0 to High(SourceBytes[I]) do
      SourceBytes[I][J] := Byte(I * 17 + J * 29);
    SourceInterfaces[I] := TPulseValue.Create(UInt64(I + 1));
    SourceVariants[I] := I * 11 + 3;
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_managed', Profile, SelectedCase);
  InitializeSources;
  FetchTextProc := @FetchStatusText;
  FetchIntfProc := @FetchStatusIntf;
  GetForwardProc := @GetNameForward;
  Found := False;
  PulseRunCase('pulse_managed', 'ignored-string-result', 'compiler+rtl',
    'dropped managed result', @CaseIgnoredStringResult, InnerCount, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_managed', 'ignored-interface-result', 'compiler+rtl',
    'dropped interface result', @CaseIgnoredInterfaceResult, InnerCount,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'out-string-forwarding', 'compiler+rtl',
    'managed out forwarding', @CaseOutStringForwarding, InnerCount, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_managed', 'unicode-assign', 'rtl', 'UnicodeString',
    @CaseUnicodeAssign, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'unicode-assign-mt', 'rtl', 'UnicodeString MT',
    @CaseUnicodeAssignMT, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'rawbytestring-assign-mt', 'rtl',
    'RawByteString MT', @CaseRawAssignMT, InnerCount, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_managed', 'unicode-return-ppu', 'compiler+rtl',
    'UnicodeString', @CaseUnicodeCopyPpu, InnerCount, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_managed', 'unicode-concat', 'rtl', 'UnicodeString',
    @CaseUnicodeConcat, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'rawbytestring-assign', 'rtl', 'RawByteString',
    @CaseRawAssign, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'dynamic-array-assign', 'rtl', 'DynArray',
    @CaseDynamicArrayAssign, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'dynamic-array-deep-copy', 'rtl', 'DynArray',
    @CaseDynamicArrayCopy, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'interface-copy-call', 'compiler+rtl',
    'Interface', @CaseInterfaceCopy, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'variant-numeric', 'rtl', 'Variant',
    @CaseVariantNumeric, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'managed-record-return', 'compiler+rtl',
    'ManagedRecord', @CaseManagedRecord, InnerCount, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_managed', 'managed-early-exit', 'compiler+rtl',
    'Finalize', @CaseEarlyExit, InnerCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'managed-exception-cleanup', 'compiler+rtl',
    'Finalize', @CaseExceptionCleanup, 8, Profile, SelectedCase, Found);
  PulseRunCase('pulse_managed', 'closure-create-invoke', 'compiler+rtl',
    'AnonymousFunction', @CaseClosureCreateInvoke, 8, Profile, SelectedCase,
    Found);
  PulseFinish('pulse_managed', SelectedCase, Found);
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
