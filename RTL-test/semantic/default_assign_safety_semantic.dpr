program default_assign_safety_semantic;

{ Safety gate for the still-open Default(T) assignment canvas.

  This deliberately does not choose between the current element-wise Assign
  result (101) and DCC64's bare-array move result (100).  It pins the
  invariants that every future repair must preserve:

  - a destination expression is evaluated exactly once;
  - one destination cannot be finalized while another receives the value;
  - a temporary value cannot lose ownership if destination finalization
    raises an exception.

  The rejected raw-byte-temp implementation e5eaa154 violated both axes. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

type
  TValue = record
    Slot: Integer;
    class operator Initialize(out Dest: TValue);
    class operator Finalize(var Dest: TValue);
    class operator Assign(var Dest: TValue; const [ref] Src: TValue);
  end;

  TValuePair = array[0..1] of TValue;
  TValueMatrix = array[0..1] of TValuePair;

  POwned = ^Integer;

  TOwned = record
    Ptr: POwned;
    class operator Initialize(out Dest: TOwned);
    class operator Finalize(var Dest: TOwned);
    class operator Assign(var Dest: TOwned; const [ref] Src: TOwned);
  end;

  TOwnedPair = array[0..1] of TOwned;

const
  OWNED_MARK = $12345678;

var
  FailCount: Integer;
  PickCalls: Integer;
  Values: TValueMatrix;
  LiveOwned: Integer;
  CorruptOwned: Integer;
  ThrowFinalize: Boolean;

class operator TValue.Initialize(out Dest: TValue);
begin
  Dest.Slot := 100;
end;

class operator TValue.Finalize(var Dest: TValue);
begin
  Dest.Slot := -1;
end;

class operator TValue.Assign(var Dest: TValue; const [ref] Src: TValue);
begin
  Dest.Slot := Src.Slot + 1;
end;

class operator TOwned.Initialize(out Dest: TOwned);
begin
  New(Dest.Ptr);
  Dest.Ptr^ := OWNED_MARK;
  Inc(LiveOwned);
end;

class operator TOwned.Finalize(var Dest: TOwned);
begin
  If Dest.Ptr <> nil then
  begin
    If Dest.Ptr^ <> OWNED_MARK then
      Inc(CorruptOwned);
    Dispose(Dest.Ptr);
    Dest.Ptr := nil;
    Dec(LiveOwned);
  end;
  If ThrowFinalize then
  begin
    ThrowFinalize := False;
    raise Exception.Create('finalize bomb');
  end;
end;

class operator TOwned.Assign(var Dest: TOwned; const [ref] Src: TOwned);
begin
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then
  begin
    WriteLn('FAIL ', Name);
    Inc(FailCount);
  end;
end;

function Pick: Integer;
begin
  Result := PickCalls;
  Inc(PickCalls);
end;

procedure ComplexDestination;
var
  FreshValue: Boolean;
begin
  PickCalls := 0;
  Values[0][0].Slot := 10;
  Values[0][1].Slot := 11;
  Values[1][0].Slot := 20;
  Values[1][1].Slot := 21;

  Values[Pick] := Default(TValuePair);

  FreshValue :=
    ((Values[0][0].Slot = 100) and (Values[0][1].Slot = 100)) or
    ((Values[0][0].Slot = 101) and (Values[0][1].Slot = 101));
  Check(PickCalls = 1, 'complex destination evaluated more than once');
  Check(FreshValue, 'selected destination did not receive Default value');
  Check((Values[1][0].Slot = 20) and (Values[1][1].Slot = 21),
    'unselected destination was modified');
end;

procedure ThrowingDestinationFinalize;
var
  P: TOwnedPair;
begin
  ThrowFinalize := True;
  try
    P := Default(TOwnedPair);
  except
    on E: Exception do
      Check(E.Message = 'finalize bomb', 'unexpected finalize exception');
  end;
  ThrowFinalize := False;
end;

procedure FinalizeExceptionOwnership;
var
  Before: Integer;
begin
  Before := LiveOwned;
  ThrowingDestinationFinalize;
  Check(LiveOwned = Before, 'Default temporary ownership leaked');
  Check(CorruptOwned = 0, 'owned payload was corrupted');
end;

begin
  FailCount := 0;
  LiveOwned := 0;
  CorruptOwned := 0;
  ThrowFinalize := False;

  ComplexDestination;
  FinalizeExceptionOwnership;

  If FailCount = 0 then
    WriteLn('DEFAULT_ASSIGN_SAFETY_OK')
  else
  begin
    WriteLn('DEFAULT_ASSIGN_SAFETY_FAIL count=', FailCount);
    Halt(1);
  end;
end.
