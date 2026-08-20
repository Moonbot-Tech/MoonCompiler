program managed_assign_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the flattened managed assignment paths and the TList
  fast paths: interface refcounts through _AddRef/_Release built on the
  atomic intrinsics, dynamic-array assignment refcounts including self
  assignment and finalization of managed elements, and TList<T>.Add /
  Delete contracts for plain lists, subscribers and descendants. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils, Generics.Collections;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

type
  ICounted = interface
    function Value: Integer;
  end;

  TCounted = class(TInterfacedObject, ICounted)
  public
    FValue: Integer;
    class var Alive: Integer;
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;

constructor TCounted.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
  Inc(Alive);
end;

destructor TCounted.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TCounted.Value: Integer;
begin
  Result := FValue;
end;

type
  TNotifyIntList = class(TList<Integer>)
  public
    Added, Removed: Integer;
  protected
    procedure Notify(const Item: Integer; Action: TCollectionNotification); override;
  end;

procedure TNotifyIntList.Notify(const Item: Integer; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  case Action of
    cnAdded: Inc(Added);
    cnRemoved, cnExtracted: Inc(Removed);
  end;
end;

var
  A, B, C: ICounted;
  Arr1, Arr2: TBytes;
  SArr1, SArr2: array of UnicodeString;
  Ints: TList<Integer>;
  NotifyList: TNotifyIntList;
  Events: TList<Integer>;
  I: Integer;
  Total: Integer;
begin
  { interface refcount lifecycle }
  A := TCounted.Create(7);
  If TCounted.Alive <> 1 then
    Fail('intf alive after create');
  B := A;
  C := A;
  If (B.Value <> 7) or (C.Value <> 7) then
    Fail('intf copies read');
  A := nil;
  B := nil;
  If TCounted.Alive <> 1 then
    Fail('intf alive with one ref');
  C := nil;
  If TCounted.Alive <> 0 then
    Fail('intf released');

  { reassignment releases the old value exactly once }
  A := TCounted.Create(1);
  B := TCounted.Create(2);
  If TCounted.Alive <> 2 then
    Fail('two intf alive');
  A := B;
  If TCounted.Alive <> 1 then
    Fail('reassign released old');
  If A.Value <> 2 then
    Fail('reassign reads new');
  A := A;
  If (TCounted.Alive <> 1) or (A.Value <> 2) then
    Fail('self assign');
  A := nil;
  B := nil;
  If TCounted.Alive <> 0 then
    Fail('all released');

  { dynamic array assignment: values, self-assign, nil }
  SetLength(Arr1, 8);
  for I := 0 to 7 do
    Arr1[I] := I * 3;
  Arr2 := Arr1;
  If (Length(Arr2) <> 8) or (Arr2[5] <> 15) then
    Fail('dynarray assign');
  Arr2[5] := 99;
  If Arr1[5] <> 99 then
    Fail('dynarray shares storage');
  Arr2 := Arr2;
  If (Length(Arr2) <> 8) or (Arr2[5] <> 99) then
    Fail('dynarray self assign');
  Arr1 := nil;
  If (Length(Arr2) <> 8) or (Arr2[0] <> 0) then
    Fail('dynarray alive after source nil');
  Arr2 := nil;

  { managed elements survive assignment chains and finalize cleanly }
  SetLength(SArr1, 4);
  for I := 0 to 3 do
    SArr1[I] := 'value-' + IntToStr(I);
  SArr2 := SArr1;
  SArr1 := nil;
  for I := 0 to 3 do
    If SArr2[I] <> 'value-' + IntToStr(I) then
      Fail('managed dynarray content');
  SArr2 := nil;

  { TList fast path: values, count, growth beyond capacity }
  Ints := TList<Integer>.Create;
  try
    for I := 0 to 999 do
      If Ints.Add(I * 7) <> I then
        Fail('Add result index');
    If Ints.Count <> 1000 then
      Fail('Add count');
    for I := 0 to 999 do
      If Ints[I] <> I * 7 then
        Fail('Add content at ' + IntToStr(I));
    { Delete keeps order and returns notifications elsewhere }
    Ints.Delete(0);
    Ints.Delete(Ints.Count - 1);
    If (Ints.Count <> 998) or (Ints[0] <> 7) or (Ints[997] <> 998 * 7) then
      Fail('Delete ends');
    If Ints.Remove(7 * 500) <> 499 then
      Fail('Remove index');
    If Ints.Count <> 997 then
      Fail('Remove count');
  finally
    FreeAndNil(Ints);
  end;

  { subscriber forces the notifying path for every add and delete }
  Events := TList<Integer>.Create;
  try
    NotifyList := TNotifyIntList.Create;
    try
      for I := 1 to 20 do
        NotifyList.Add(I);
      If NotifyList.Added <> 20 then
        Fail('descendant saw adds');
      for I := 1 to 5 do
        NotifyList.Delete(0);
      If NotifyList.Removed <> 5 then
        Fail('descendant saw removes');
      Total := 0;
      for I := 0 to NotifyList.Count - 1 do
        Total := Total + NotifyList[I];
      If Total <> 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15 + 16 + 17 + 18 + 19 + 20 then
        Fail('descendant contents');
    finally
      FreeAndNil(NotifyList);
    end;
  finally
    FreeAndNil(Events);
  end;

  WriteLn('MANAGED_ASSIGN_OK');
end.
