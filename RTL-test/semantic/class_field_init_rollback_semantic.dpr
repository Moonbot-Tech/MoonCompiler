program class_field_init_rollback_semantic;

{ A field operator may raise before the constructor begins. Every completed
  field, including an ancestor's, must be finalized exactly once. InitInstance
  borrows its buffer; NewInstance owns the allocation. }
{$ifdef FPC}{$mode delphi}{$endif}

uses
  {$ifdef FPC}mormot.core.fpcx64mm, {$ifdef unix}cthreads, cwstring, {$endif}{$endif}
  SysUtils;

type
  TCell = record
    Id: Integer;
    class operator Initialize(out Dest: TCell);
    class operator Finalize(var Dest: TCell);
  end;
  TBlock = record
    Cells: array[-1..0, 1..2] of TCell;
  end;
  TBase = class
    BaseCell: TCell;
  end;
  TMiddle = class(TBase)
    Block: TBlock;
  end;
  THolder = class(TMiddle)
    Last: TCell;
    constructor Create;
  end;
  TLeaf = class(THolder);
  TTrackedOwner = class(TInterfacedObject)
    destructor Destroy; override;
  end;
  TComposite = record
    Child: TCell;
    Owner: IInterface;
    class operator Initialize(out Dest: TComposite);
    class operator Finalize(var Dest: TComposite);
  end;
  TCompositeHolder = class
    Field: TComposite;
  end;

var
  Attempts, FailAt, Finalized, Constructed: Integer;
  Live: set of 1..6;
  FailComposite: Boolean;
  OwnersDestroyed, CompositesFinalized: Integer;

procedure Check(Ok: Boolean; const Msg: string);
begin
  if not Ok then
  begin
    Writeln('FAIL ', Msg, ' fail-at=', FailAt, ' attempts=', Attempts, ' finalized=', Finalized);
    Halt(1);
  end;
end;

class operator TCell.Initialize(out Dest: TCell);
begin
  Inc(Attempts);
  if Attempts = FailAt then
    raise EAbort.Create('cell initialization');
  Check(Attempts <= 6, 'duplicate initialization');
  Dest.Id := Attempts;
  Include(Live, Dest.Id);
end;

class operator TCell.Finalize(var Dest: TCell);
begin
  Check((Dest.Id >= 1) and (Dest.Id <= 6), 'finalized uninitialized cell');
  Check(Dest.Id in Live, 'duplicate finalization');
  Exclude(Live, Dest.Id);
  Inc(Finalized);
end;

destructor TTrackedOwner.Destroy;
begin
  Inc(OwnersDestroyed);
  inherited;
end;

class operator TComposite.Initialize(out Dest: TComposite);
begin
  Check((Dest.Child.Id = 1) and (Dest.Child.Id in Live), 'child alive before parent initializer');
  Dest.Owner := TTrackedOwner.Create;
  If FailComposite then
    raise EAbort.Create('composite initialization');
end;

class operator TComposite.Finalize(var Dest: TComposite);
begin
  Check(not FailComposite, 'finalized parent whose initializer failed');
  Check((Dest.Owner <> nil) and (Dest.Child.Id in Live), 'parent finalized before its fields');
  Inc(CompositesFinalized);
end;

constructor THolder.Create;
begin
  inherited Create;
  Inc(Constructed);
end;

procedure Exercise(Failure: Integer; CallerOwnsStorage: Boolean);
const
  GuardSize = 16;
var
  Buffer: PByte;
  I: Integer;
  Obj: TLeaf;
  Raised: Boolean;
begin
  Attempts := 0;
  Finalized := 0;
  Constructed := 0;
  FailAt := Failure;
  Live := [];
  Buffer := nil;
  Obj := nil;
  Raised := False;
  if CallerOwnsStorage then
  begin
    GetMem(Buffer, TLeaf.InstanceSize + 2 * GuardSize);
    FillChar(Buffer^, TLeaf.InstanceSize + 2 * GuardSize, $A5);
  end;
  try
    try
      if CallerOwnsStorage then
        Obj := TLeaf(TLeaf.InitInstance(Buffer + GuardSize))
      else
        Obj := TLeaf.Create;
    except
      on E: EAbort do Raised := E.Message = 'cell initialization';
    end;
    Check(Raised = (Failure <> 0), 'exception propagation');
    Check((Obj = nil) = Raised, 'published partial instance');
    Check(Constructed = Ord((Failure = 0) and not CallerOwnsStorage), 'constructor entry');
    if Assigned(Obj) then
    begin
      Check((Obj.BaseCell.Id = 1) and (Obj.Last.Id = 6), 'base and derived order');
      if CallerOwnsStorage then Obj.CleanupInstance else Obj.Free;
    end;
    if Raised then
      Check((Attempts = Failure) and (Finalized = Failure - 1), 'initialized prefix')
    else
      Check((Attempts = 6) and (Finalized = 6), 'complete instance');
    Check(Live = [], 'retained cell');
    if CallerOwnsStorage then
      for I := 0 to GuardSize - 1 do
        Check((Buffer[I] = $A5) and (Buffer[GuardSize + TLeaf.InstanceSize + I] = $A5), 'storage guards');
  finally
    if CallerOwnsStorage then FreeMem(Buffer);
  end;
end;

procedure ExerciseComposite(Failure: Boolean);
var
  Obj: TCompositeHolder;
  Raised: Boolean;
begin
  Attempts := 0;
  Finalized := 0;
  FailAt := 0;
  Live := [];
  FailComposite := Failure;
  OwnersDestroyed := 0;
  CompositesFinalized := 0;
  Obj := nil;
  Raised := False;
  try
    Obj := TCompositeHolder.Create;
  except
    on E: EAbort do Raised := E.Message = 'composite initialization';
  end;
  Check((Raised = Failure) and ((Obj = nil) = Raised), 'composite creation outcome');
  If Assigned(Obj) then
    Obj.Free;
  Check((Attempts = 1) and (Finalized = 1) and (Live = []), 'composite child finalized once');
  Check(OwnersDestroyed = 1, 'composite interface owner destroyed once');
  Check(CompositesFinalized = Ord(not Failure), 'composite finalizer count');
end;

var
  Failure: Integer;
begin
  for Failure := 0 to 6 do
  begin
    Exercise(Failure, False);
    Exercise(Failure, True);
  end;
  ExerciseComposite(True);
  ExerciseComposite(False);
  WriteLn('CLASS_FIELD_INIT_ROLLBACK_PASS');
end.
