program psabieh_product_semantic;

{$mode delphiunicode}{$H+}

{$ifdef linux}
  {$ifndef FPC_USE_PSABIEH}
    {$fatal Moon Compiler Linux product must use PSABI exception handling}
  {$endif}
{$endif}

uses
  mormot.core.fpcx64mm,
{$ifdef unix}
  cthreads,
{$endif}
  SysUtils,
  Classes;

type
  EProbe = class(Exception);
  EChildProbe = class(EProbe);

  EReplacedProbe = class(Exception)
  public
    destructor Destroy; override;
  end;

  IProbe = interface
    ['{40E0D0C1-52DC-423B-8CE6-B8D174647B31}']
  end;

  TProbeObject = class(TInterfacedObject, IProbe)
  public
    destructor Destroy; override;
  end;

  TSavedRegisterProbe = class(TInterfacedObject, IProbe)
  private
    FTag: AnsiChar;
  public
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

  TManagedProbe = record
    Text: UnicodeString;
    class operator Initialize(var Value: TManagedProbe);
    class operator Finalize(var Value: TManagedProbe);
  end;

  TExceptionThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  Trail: AnsiString = '';
  FinalizeCount: LongInt = 0;
  DestroyCount: LongInt = 0;
  ThreadResult: LongInt = 0;
  ReplacedDestroyCount: LongInt = 0;

threadvar
  AfterUnwindText: AnsiString;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    begin
      WriteLn('FAIL ', MessageText);
      Halt(1);
    end;
end;

destructor TProbeObject.Destroy;
begin
  InterlockedIncrement(DestroyCount);
  inherited Destroy;
end;

destructor EReplacedProbe.Destroy;
begin
  InterlockedIncrement(ReplacedDestroyCount);
  inherited Destroy;
end;

constructor TSavedRegisterProbe.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TSavedRegisterProbe.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

class operator TManagedProbe.Initialize(var Value: TManagedProbe);
begin
  Value.Text := 'managed';
end;

class operator TManagedProbe.Finalize(var Value: TManagedProbe);
begin
  if Value.Text = 'managed' then
    InterlockedIncrement(FinalizeCount);
end;

procedure RaiseNested;
begin
  Trail := Trail + 'body;';
  raise EChildProbe.Create('child');
end;

procedure CheckTypedCatchAndFinally;
begin
  Trail := '';
  try
    try
      RaiseNested;
    finally
      Trail := Trail + 'finally;';
    end;
  except
    on E: EChildProbe do
      Trail := Trail + E.Message + ';';
  end;
  Check(Trail = 'body;finally;child;', 'typed catch/finally order');
end;

procedure CheckBareReraise;
begin
  Trail := '';
  try
    try
      raise EChildProbe.Create('reraised');
    except
      on E: EProbe do
        begin
          Trail := Trail + E.Message + ';';
          raise;
        end;
    end;
  except
    on E: EChildProbe do
      Trail := Trail + 'outer-' + E.Message + ';';
  end;
  Check(Trail = 'reraised;outer-reraised;', 'bare reraise');
end;

procedure CheckCatchAll;
begin
  Trail := '';
  try
    raise TObject.Create;
  except
    Trail := 'caught;';
  end;
  Check(Trail = 'caught;', 'catch all');
end;

function NormalTryExcept(Value: Integer): Integer; noinline;
begin
  try
    Result := Value + 1;
  except
    Result := -1;
  end;
end;

function NormalTryFinally(Value: Integer): Integer; noinline;
begin
  Result := Value;
  try
    Inc(Result);
  finally
    Inc(Result, 2);
  end;
end;

procedure CheckNormalPath;
begin
  Check(NormalTryExcept(40) = 41, 'normal try/except');
  Check(NormalTryFinally(40) = 43, 'normal try/finally');
end;

procedure RaiseWithManagedLocals;
var
  Managed: TManagedProbe;
  Ref: IProbe;
  Text: UnicodeString;
  Values: TArray<UnicodeString>;
begin
  Text := 'text';
  SetLength(Values, 2);
  Values[0] := Text;
  Ref := TProbeObject.Create;
  Check((Managed.Text = 'managed') and (Values[0] = 'text') and
    Assigned(Ref), 'managed setup');
  raise EProbe.Create('managed unwind');
end;

procedure CheckManagedUnwind;
begin
  FinalizeCount := 0;
  DestroyCount := 0;
  try
    RaiseWithManagedLocals;
  except
    on E: EProbe do
      Check(E.Message = 'managed unwind', 'managed exception payload');
  end;
  Check(FinalizeCount = 1, 'managed record unwind');
  Check(DestroyCount = 1, 'interface unwind');
end;

procedure CheckExceptionReplacement;
begin
  ReplacedDestroyCount := 0;
  try
    try
      raise EReplacedProbe.Create('replaced');
    finally
      raise EChildProbe.Create('replacement');
    end;
  except
    on E: EChildProbe do
      Check(E.Message = 'replacement', 'replacement exception payload');
  end;
  Check(ReplacedDestroyCount = 1, 'replaced exception destroyed');
end;

procedure RaiseWithSavedRegister; noinline;
var
  Ref: IProbe;
begin
  Ref := TSavedRegisterProbe.Create('x');
  raise EProbe.Create('saved register unwind');
end;

procedure CheckSavedRegisterUnwind;
begin
  Trail := '';
  try
    RaiseWithSavedRegister;
  except
    on E: EProbe do
      Check(E.Message = 'saved register unwind', 'saved-register payload');
  end;
  AfterUnwindText := 'threadvar-after-unwind';
  Check((Trail = 'x') and (AfterUnwindText = 'threadvar-after-unwind'),
    'callee-saved register restored across managed unwind');
end;

function ExitThroughFinally: Integer;
begin
  Result := 1;
  try
    Exit(2);
  finally
    Inc(Result, 3);
  end;
end;

procedure CheckStructuredExits;
var
  I, FinallyRuns, Sum: Integer;
begin
  Check(ExitThroughFinally = 5, 'Exit through finally');
  FinallyRuns := 0;
  Sum := 0;
  for I := 0 to 5 do
    try
      if I = 1 then
        Continue;
      if I = 4 then
        Break;
      Inc(Sum, I);
    finally
      Inc(FinallyRuns);
    end;
  Check((Sum = 5) and (FinallyRuns = 5), 'Break/Continue through finally');
end;

procedure TExceptionThread.Execute;
begin
  try
    CheckTypedCatchAndFinally;
    CheckBareReraise;
    InterlockedExchange(ThreadResult, 1);
  except
    InterlockedExchange(ThreadResult, -1);
  end;
end;

procedure CheckThreadUnwind;
var
  Worker: TExceptionThread;
begin
  ThreadResult := 0;
  Worker := TExceptionThread.Create(False);
  try
    Worker.WaitFor;
  finally
    Worker.Free;
  end;
  Check(ThreadResult = 1, 'thread unwind');
end;

begin
  CheckTypedCatchAndFinally;
  CheckBareReraise;
  CheckExceptionReplacement;
  CheckCatchAll;
  CheckNormalPath;
  CheckManagedUnwind;
  CheckSavedRegisterUnwind;
  CheckStructuredExits;
  CheckThreadUnwind;
  WriteLn('PSABIEH_PRODUCT_OK');
end.
