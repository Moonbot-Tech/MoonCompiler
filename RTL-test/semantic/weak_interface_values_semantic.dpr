program weak_interface_values_semantic;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHIUNICODE}{$ENDIF}
{$INLINE OFF}

uses SysUtils;

type
  TSmall = record
    [Weak] Link: IInterface;
  end;

  TRow = record
    Name: string;
    [Weak] Link: IInterface;
  end;

  TGroup = record
    Rows: array[0..1] of TRow;
  end;

  TCustom = record
    [Weak] Link: IInterface;
    class operator Initialize(var Dest: TCustom);
  end;

var
  Owner, Other: IInterface;
  Small: TSmall;
  Group: TGroup;
  Custom: TCustom;
  InitCount: Integer;

procedure Check(Value: Boolean; const Where: string);
begin
  if not Value then
    raise Exception.Create(Where);
end;

class operator TCustom.Initialize(var Dest: TCustom);
begin
  Inc(InitCount);
end;

function MakeSmall: TSmall;
begin
  Result.Link := Owner;
end;

function MakeGroup: TGroup;
begin
  Result.Rows[0].Name := 'first';
  Result.Rows[0].Link := Owner;
  Result.Rows[1].Name := 'other';
  Result.Rows[1].Link := Other;
end;

function MakeCustom: TCustom;
begin
  Result.Link := Owner;
end;

function RaiseAfterAssign: TSmall;
begin
  Result.Link := Other;
  raise EAbort.Create('cancel');
end;

procedure ValueCopy(Value: TGroup);
begin
  Check(@Value <> @Group, 'distinct value parameter');
  Value.Rows[0].Name := 'private';
  Owner := nil;
  Check(PPointer(@Value.Rows[0].Link)^ = nil, 'copied parameter was not cleared');
  Check(PPointer(@Group.Rows[0].Link)^ = nil, 'original parameter was not cleared');
  Check(PPointer(@Small.Link)^ = nil, 'small function result');
  Check(PPointer(@Custom.Link)^ = nil, 'custom record function result');
  Check((Value.Rows[1].Link = Other) and (Group.Rows[1].Link = Other), 'wrong weak target cleared');
end;


type
  TWeakWatch = class
    [Weak] Link: IInterface;
  end;

  TRepublish = class(TInterfacedObject)
    Target: IInterface;
    Observer: TWeakWatch;
    destructor Destroy; override;
  end;

  TManualOwner = class(TNoRefCountObject)
    Callback: IInterface;
  end;

destructor TRepublish.Destroy;
begin
  Observer.Link := Target;
  inherited;
end;

procedure TestReentrantCleanup;
var
  Observer: TWeakWatch;
  Target: TManualOwner;
  Callback: TRepublish;
begin
  Observer := TWeakWatch.Create;
  try
    Target := TManualOwner.Create;
    Callback := TRepublish.Create;
    Target.Callback := Callback;
    Callback.Target := Target;
    Callback.Observer := Observer;
    Target.Free;
    if PPointer(@Observer.Link)^ <> nil then Halt(31);
  finally
    Observer.Free;
  end;
end;

procedure TestOpenConstructor;
type
  TElement = record
    [Weak] Link: IInterface;
  end;
var
  Owner: IInterface;
  Row: TElement;

  procedure ReadRows(const Values: array of TElement);
  begin
    if (Length(Values) <> 2) or (Values[0].Link <> Owner) then Halt(32);
    Owner := nil;
    if (PPointer(@Values[0].Link)^ <> nil) or (PPointer(@Values[1].Link)^ <> nil) then Halt(33);
  end;
begin
  Owner := TInterfacedObject.Create;
  Row.Link := Owner;
  ReadRows([Row, Row]);
  if PPointer(@Row.Link)^ <> nil then Halt(34);
end;

procedure TestExplicitLifetime;
var
  Obj: TInterfacedObject;
  A, B: IInterface;
  Row: TSmall;
begin
  Obj := TInterfacedObject.Create;
  A := Obj;
  B := A;
  Row.Link := A;
  System.Finalize(Row.Link);
  Check((Pointer(Row.Link) = nil) and (Obj.RefCount = 2), 'Finalize weak field');
  Row.Link := A;
  System.Finalize(Row.Link, 1);
  Check((Pointer(Row.Link) = nil) and (Obj.RefCount = 2), 'Finalize weak field with count');
  Row.Link := A;
  System.Initialize(Row.Link);
  Check(Pointer(Row.Link) = nil, 'Initialize weak field');
  Row.Link := A;
  System.Initialize(Row.Link, 1);
  Check(Pointer(Row.Link) = nil, 'Initialize weak field with count');
  Row.Link := A;
  System.Initialize(Row);
  Check((Pointer(Row.Link) = nil) and (Obj.RefCount = 2), 'Initialize enclosing record');
  B := TInterfacedObject.Create;
  Row.Link := B;
  A := nil;
  Check(Row.Link = B, 'old target cannot clear a reinitialized field');
  B := nil;
  Check(Pointer(Row.Link) = nil, 'release after explicit initialization');
end;


begin
  if PVmt(Pointer(TObject))^.vInitTable <> nil then Halt(35);
  TestReentrantCleanup;
  TestOpenConstructor;
  TestExplicitLifetime;
  Owner := TInterfacedObject.Create;
  Other := TInterfacedObject.Create;
  Small := MakeSmall;
  Custom := MakeCustom;
  Group := MakeGroup;
  Check((Small.Link = Owner) and (Custom.Link = Owner), 'returned interface');
  Check(Group.Rows[1].Name = 'other', 'managed fields in result');
  try
    Small := RaiseAfterAssign;
    Halt(2);
  except
    on EAbort do ;
  end;
  Check(Small.Link = Owner, 'failed result overwrote destination');
  ValueCopy(Group);
  Check(Group.Rows[0].Name = 'first', 'value parameter changed caller string');
  Other := nil;
  Check(PPointer(@Group.Rows[1].Link)^ = nil, 'other nested result');
  Check(InitCount > 0, 'user initialization');
  WriteLn('WEAK_INTERFACE_VALUES_PASS');
end.
