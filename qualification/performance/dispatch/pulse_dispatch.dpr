program pulse_dispatch;

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
  SysUtils,
  TypInfo,
  Generics.Collections,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  InnerCount = 64;

type
  IDispatch = interface
    ['{2A279129-FAF9-4D8C-B69D-EDBFF48F3C48}']
    function Apply(Value: UInt64): UInt64;
  end;
  TDispatchBase = class(TInterfacedObject, IDispatch)
  private
    FDelta: UInt64;
  public
    constructor Create(Delta: UInt64);
    function Apply(Value: UInt64): UInt64; virtual;
    function StaticApply(Value: UInt64): UInt64;
  end;
  TDispatchA = class(TDispatchBase)
  public
    function Apply(Value: UInt64): UInt64; override;
  end;
  TDispatchB = class(TDispatchBase)
  public
    function Apply(Value: UInt64): UInt64; override;
  end;
  TManagedObject = class
  public
    Text: UnicodeString;
    Values: TArray<Integer>;
    constructor Create(Seed: Integer);
  end;
  TSmallRecord = record
    A, B: UInt64;
  end;
  TGenericMixer<T> = class
  public
    class function Apply(const Value: T; Seed: UInt64): UInt64; static; inline;
  end;
  TUInt64Func = function(Value: UInt64): UInt64;

var
  MonoObject: TDispatchBase;
  PolyObjects: array[0..15] of TDispatchBase;
  MonoInterface: IDispatch;
  PolyInterfaces: array[0..15] of IDispatch;
  IntegerList: TList<Integer>;
  PlainFunc: TUInt64Func;

function Mix(Value: UInt64): UInt64; inline;
begin
  Result := (Value xor (Value shr 27)) * UInt64($3C79AC492BA7B653);
end;

constructor TDispatchBase.Create(Delta: UInt64);
begin
  inherited Create;
  FDelta := Delta;
end;

function TDispatchBase.Apply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + FDelta);
end;

function TDispatchBase.StaticApply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + FDelta);
end;

function TDispatchA.Apply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + FDelta + 1);
end;

function TDispatchB.Apply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + FDelta + 3);
end;

constructor TManagedObject.Create(Seed: Integer);
var
  I: Integer;
begin
  inherited Create;
  Text := 'managed-object-' + IntToStr(Seed);
  SetLength(Values, 8);
  for I := 0 to High(Values) do
    Values[I] := Seed * 17 + I;
end;

class function TGenericMixer<T>.Apply(const Value: T; Seed: UInt64): UInt64;
begin
  Result := Mix(Seed + UInt64(SizeOf(T)) + PByte(@Value)^);
end;

function CaseStaticMethod(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := MonoObject.StaticApply(Result + UInt64(J));
end;

function CaseVirtualMono(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := MonoObject.Apply(Result + UInt64(J));
end;

function CaseVirtualPoly(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := PolyObjects[(I + J) and High(PolyObjects)].Apply(
        Result + UInt64(J));
end;

function CaseInterfaceMono(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := MonoInterface.Apply(Result + UInt64(J));
end;

function CaseInterfacePoly(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := PolyInterfaces[(I + J) and High(PolyInterfaces)].Apply(
        Result + UInt64(J));
end;

function CaseFunctionPointer(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := PlainFunc(Result + UInt64(J));
end;

function CaseGenericInteger(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
begin
  Result := 1;
  Value := 17;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value := Value + I + J;
      Result := TGenericMixer<Integer>.Apply(Value, Result);
    end;
end;

function CaseGenericRecord(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: TSmallRecord;
begin
  Result := 1;
  Value.A := 17;
  Value.B := 31;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Value.A := Value.A + UInt64(I);
      Value.B := Value.B + UInt64(J);
      Result := TGenericMixer<TSmallRecord>.Apply(Value, Result);
    end;
end;

function CaseListIndex(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to IntegerList.Count - 1 do
      Result := Result + UInt32(IntegerList[J]);
end;

function CaseListEnumerator(Iterations: Integer): UInt64;
var
  I, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Value in IntegerList do
      Result := Result + UInt32(Value);
end;

function CaseTryExceptNoRaise(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 1;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      try
        Result := Mix(Result + UInt64(J));
      except
        Result := 0;
      end;
end;

function CaseRaiseCatch(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to 4 do
      try
        raise EAbort.Create('pulse');
      except
        on E: EAbort do
          Result := Result + UInt64(Length(E.Message) + I + J);
      end;
end;

function CaseObjectCreateFree(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Obj: TDispatchBase;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
    begin
      Obj := TDispatchBase.Create(UInt64(I + J));
      try
        Result := Result xor Obj.StaticApply(UInt64(J));
      finally
        Obj.Free;
      end;
    end;
end;

function CaseManagedObjectCreateFree(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Obj: TManagedObject;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to 8 do
    begin
      Obj := TManagedObject.Create(I + J);
      try
        Result := Result + UInt64(Length(Obj.Text)) + UInt32(Obj.Values[0]);
      finally
        Obj.Free;
      end;
    end;
end;

function CaseClassNameRtti(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 1 to InnerCount do
      Result := Result + UInt64(Length(PolyObjects[J and High(PolyObjects)].ClassName));
end;

procedure InitializeData;
var
  I: Integer;
begin
  MonoObject := TDispatchBase.Create(17);
  MonoInterface := MonoObject;
  for I := 0 to High(PolyObjects) do
  begin
    If (I and 1) = 0 then
      PolyObjects[I] := TDispatchA.Create(UInt64(I + 1))
    else
      PolyObjects[I] := TDispatchB.Create(UInt64(I + 1));
    PolyInterfaces[I] := PolyObjects[I];
  end;
  IntegerList := TList<Integer>.Create;
  IntegerList.Capacity := 512;
  for I := 0 to 511 do
    IntegerList.Add(I * 17 + 3);
  PlainFunc := @Mix;
end;

procedure FinalizeData;
var
  I: Integer;
begin
  IntegerList.Free;
  for I := 0 to High(PolyInterfaces) do
  begin
    PolyInterfaces[I] := nil;
    PolyObjects[I] := nil;
  end;
  MonoInterface := nil;
  MonoObject := nil;
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  InitializeData;
  try
    PulseInitialize('pulse_dispatch', Profile, SelectedCase);
    Found := False;
    PulseRunCase('pulse_dispatch', 'static-method', 'codegen', 'compiler',
      @CaseStaticMethod, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'virtual-monomorphic', 'codegen', 'compiler',
      @CaseVirtualMono, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'virtual-polymorphic', 'codegen', 'compiler',
      @CaseVirtualPoly, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'interface-monomorphic', 'compiler+rtl',
      'compiler', @CaseInterfaceMono, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'interface-polymorphic', 'compiler+rtl',
      'compiler', @CaseInterfacePoly, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'function-pointer', 'codegen', 'compiler',
      @CaseFunctionPointer, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'generic-integer', 'codegen', 'compiler',
      @CaseGenericInteger, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'generic-record', 'codegen', 'compiler',
      @CaseGenericRecord, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'list-index', 'rtl+mm', 'TList<Integer>',
      @CaseListIndex, 512, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'list-enumerator', 'rtl+mm', 'TList<Integer>',
      @CaseListEnumerator, 512, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'try-except-no-raise', 'compiler+rtl',
      'compiler', @CaseTryExceptNoRaise, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'raise-catch', 'compiler+rtl+mm', 'compiler',
      @CaseRaiseCatch, 4, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'object-create-free', 'rtl+mm', 'TObject',
      @CaseObjectCreateFree, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'managed-object-create-free', 'rtl+mm',
      'TObject', @CaseManagedObjectCreateFree, 8, Profile, SelectedCase, Found);
    PulseRunCase('pulse_dispatch', 'class-name-rtti', 'rtl', 'TObject',
      @CaseClassNameRtti, InnerCount, Profile, SelectedCase, Found);
    PulseFinish('pulse_dispatch', SelectedCase, Found);
  finally
    FinalizeData;
  end;
end.
