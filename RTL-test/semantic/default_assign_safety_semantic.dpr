program default_assign_safety_semantic;

{ Exact gate for Default(T) assignment to static arrays whose elements have
  management operators.  It pins all invariants of the transactional lowering:

  - freshly initialized elements are transferred without calling Assign;
  - a destination expression is evaluated exactly once;
  - one destination cannot be finalized while another receives the value;
  - a throwing Initialize unwinds its completed prefix before Dest is touched;
  - a temporary value cannot lose ownership if destination finalization
    raises an exception;
  - the temporary honours the array alignment and never consumes an
    array-sized stack slot. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils,
  default_assign_generic_probe;

type
  TValue = record
    Slot: Integer;
    class operator Initialize(out Dest: TValue);
    class operator Finalize(var Dest: TValue);
    class operator Assign(var Dest: TValue; const [ref] Src: TValue);
  end;

  TValuePair = array[0..1] of TValue;
  TValueMatrix = array[0..1] of TValuePair;

  TAssignOnly = record
    Slot: Integer;
    class operator Assign(var Dest: TAssignOnly;
      const [ref] Src: TAssignOnly);
  end;

  TAssignOnlyPair = array[0..1] of TAssignOnly;

  POwned = ^Integer;

  TOwned = record
    Ptr: POwned;
    class operator Initialize(out Dest: TOwned);
    class operator Finalize(var Dest: TOwned);
    class operator Assign(var Dest: TOwned; const [ref] Src: TOwned);
  end;

  TOwnedPair = array[0..1] of TOwned;

  TInitBomb = record
    Slot: Integer;
    Alive: Boolean;
    class operator Initialize(out Dest: TInitBomb);
    class operator Finalize(var Dest: TInitBomb);
    class operator Assign(var Dest: TInitBomb; const [ref] Src: TInitBomb);
  end;

  TInitBombPair = array[0..1] of TInitBomb;

  TAlignedValue = record
    Slot: Integer;
    Padding: array[0..27] of Byte;
    class operator Initialize(out Dest: TAlignedValue);
    class operator Finalize(var Dest: TAlignedValue);
    class operator Assign(var Dest: TAlignedValue;
      const [ref] Src: TAlignedValue);
  end
{$ifdef FPC}
    align 32
{$endif FPC}
  ;

  TAlignedPair = array[0..1] of TAlignedValue;
  TLargeAlignedArray = array[0..65535] of TAlignedValue;

const
  OWNED_MARK = $12345678;

var
  FailCount: Integer;
  InitialLiveOwned: Integer;
  PickCalls: Integer;
  Values: TValueMatrix;
  LiveOwned: Integer;
  CorruptOwned: Integer;
  ThrowFinalize: Boolean;
  ThrowInitAt: Integer;
  InitCalls: Integer;
  LiveInitBombs: Integer;
  AlignmentFailures: Integer;
  CheckTemporaryAlignment: Boolean;
  LargeValues: TLargeAlignedArray;

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

class operator TAssignOnly.Assign(var Dest: TAssignOnly;
  const [ref] Src: TAssignOnly);
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

class operator TInitBomb.Initialize(out Dest: TInitBomb);
begin
  Inc(InitCalls);
  Dest.Alive := False;
  If InitCalls = ThrowInitAt then
    raise Exception.Create('initialize bomb');
  Dest.Slot := 100;
  Dest.Alive := True;
  Inc(LiveInitBombs);
end;

class operator TInitBomb.Finalize(var Dest: TInitBomb);
begin
  If Dest.Alive then
  begin
    Dest.Alive := False;
    Dec(LiveInitBombs);
  end;
end;

class operator TInitBomb.Assign(var Dest: TInitBomb;
  const [ref] Src: TInitBomb);
begin
  Dest.Slot := Src.Slot + 1;
end;

class operator TAlignedValue.Initialize(out Dest: TAlignedValue);
begin
{$ifdef FPC}
  If CheckTemporaryAlignment and (PtrUInt(@Dest) and 31 <> 0) then
  begin
    Inc(AlignmentFailures);
  end;
{$endif FPC}
  Dest.Slot := 100;
end;

class operator TAlignedValue.Finalize(var Dest: TAlignedValue);
begin
  Dest.Slot := -1;
end;

class operator TAlignedValue.Assign(var Dest: TAlignedValue;
  const [ref] Src: TAlignedValue);
begin
  Dest.Slot := Src.Slot + 1;
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
begin
  PickCalls := 0;
  Values[0][0].Slot := 10;
  Values[0][1].Slot := 11;
  Values[1][0].Slot := 20;
  Values[1][1].Slot := 21;

  Values[Pick] := Default(TValuePair);

  Check(PickCalls = 1, 'complex destination evaluated more than once');
  Check((Values[0][0].Slot = 100) and (Values[0][1].Slot = 100),
    'Default array elements went through Assign');
  Check((Values[1][0].Slot = 20) and (Values[1][1].Slot = 21),
    'unselected destination was modified');
end;

procedure GenericReplay;
var
  Pair: TValuePair;
begin
  Pair[0].Slot := 30;
  Pair[1].Slot := 31;
  TDefaultReset.Reset<TValuePair>(Pair);
  Check((Pair[0].Slot = 100) and (Pair[1].Slot = 100),
    'generic PPU replay lost Default array transfer');
end;

procedure AssignWithoutInitialize;
var
  Pair: TAssignOnlyPair;
begin
  Pair[0].Slot := 32;
  Pair[1].Slot := 33;
  Pair := Default(TAssignOnlyPair);
  Check((Pair[0].Slot = 0) and (Pair[1].Slot = 0),
    'Assign-only array went through Assign');
end;

procedure ThrowingTemporaryInitialize;
var
  Pair: TInitBombPair;
  Before: Integer;
begin
  Pair[0].Slot := 40;
  Pair[1].Slot := 41;
  Before := LiveInitBombs;
  ThrowInitAt := InitCalls + 2;
  try
    Pair := Default(TInitBombPair);
    Check(False, 'throwing Initialize did not raise');
  except
    on E: Exception do
      Check(E.Message = 'initialize bomb', 'unexpected Initialize exception');
  end;
  ThrowInitAt := 0;
  Check(LiveInitBombs = Before, 'initialized temporary prefix leaked');
  Check((Pair[0].Slot = 40) and (Pair[1].Slot = 41),
    'destination changed before temporary initialization completed');
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
  Check((P[0].Ptr <> nil) and (P[0].Ptr^ = OWNED_MARK),
    'throwing Finalize left the replaced destination element dead');
  Check((P[1].Ptr <> nil) and (P[1].Ptr^ = OWNED_MARK),
    'throwing Finalize damaged the untouched destination tail');
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

procedure AlignedTemporary;
var
  Pair: TAlignedPair;
begin
  Pair[0].Slot := 50;
  Pair[1].Slot := 51;
  CheckTemporaryAlignment := True;
  Pair := Default(TAlignedPair);
  CheckTemporaryAlignment := False;
  Check(AlignmentFailures = 0, 'Default temporary is misaligned');
  Check((Pair[0].Slot = 100) and (Pair[1].Slot = 100),
    'aligned Default array elements went through Assign');
end;

procedure LargeHeapTemporary;
begin
  LargeValues[0].Slot := 60;
  LargeValues[High(LargeValues)].Slot := 61;
  CheckTemporaryAlignment := True;
  LargeValues := Default(TLargeAlignedArray);
  CheckTemporaryAlignment := False;
  Check((LargeValues[0].Slot = 100) and
    (LargeValues[High(LargeValues)].Slot = 100),
    'large Default array transfer failed');
  Check(AlignmentFailures = 0, 'large Default temporary is misaligned');
end;

begin
  FailCount := 0;
  InitialLiveOwned := LiveOwned;
  CorruptOwned := 0;
  ThrowFinalize := False;
  ThrowInitAt := 0;
  AlignmentFailures := 0;
  CheckTemporaryAlignment := False;

  ComplexDestination;
  GenericReplay;
  AssignWithoutInitialize;
{$ifdef FPC}
  { DCC64 destroys part of Dest when a later Initialize raises.  Moon keeps
    the stronger transactional invariant: initialize the whole replacement
    before touching the live destination. }
  ThrowingTemporaryInitialize;
{$endif FPC}
  FinalizeExceptionOwnership;
  AlignedTemporary;
  LargeHeapTemporary;
  Check(LiveOwned = InitialLiveOwned,
    'tests changed ownership held by the Default source');

  If FailCount = 0 then
    WriteLn('DEFAULT_ASSIGN_SAFETY_OK')
  else
  begin
    WriteLn('DEFAULT_ASSIGN_SAFETY_FAIL count=', FailCount);
    Halt(1);
  end;
end.
