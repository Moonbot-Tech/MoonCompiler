program weak_interface_fields_semantic;

{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHIUNICODE}{$ENDIF}

uses SysUtils, Generics.Collections;

type
  TTarget = class(TInterfacedObject)
    destructor Destroy; override;
  end;

  TForeign = class(TInterfacedObject, IInterface)
    function QueryInterface({$IFDEF FPC}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult;
      {$IFDEF MSWINDOWS}stdcall{$ELSE}cdecl{$ENDIF}; reintroduce;
  end;

  THolder = class
    [Weak] Link: IInterface;
  end;

  TRow = record
    [Weak] Link: IInterface;
    Id: Integer;
  end;

  TEmpty = record end;

var
  Destroyed: Integer;

destructor TTarget.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TForeign.QueryInterface({$IFDEF FPC}constref{$ELSE}const{$ENDIF} IID: TGUID; out Obj): HResult;
begin
  Pointer(Obj) := nil;
  Result := HResult($80004002);
end;

procedure Check(Condition: Boolean; const Operation: string);
begin
  if not Condition then
    raise Exception.Create(Operation);
end;

procedure TestLifetime;
var
  A, B: THolder;
  First, Second, Hold: IInterface;
  Target: TTarget;
begin
  Target := TTarget.Create;
  First := Target;
  Second := TTarget.Create;
  A := THolder.Create;
  B := THolder.Create;
  try
    A.Link := First;
    B.Link := A.Link;
    Check(Target.RefCount = 1, 'two weak fields retained the target');
    Check(PPointer(@A.Link)^ = Pointer(First), 'weak field storage');
    A.Link := Second;
    Hold := B.Link;
    First := nil;
    Check((Destroyed = 0) and (Hold = B.Link), 'promotion to strong');
    Hold := nil;
    Check((Destroyed = 1) and (PPointer(@B.Link)^ = nil), 'last owner');
    Check(A.Link = Second, 'reassigned field was cleared');
    B.Link := Second;
    FreeAndNil(B);
    Second := nil;
    Check((Destroyed = 2) and (A.Link = nil), 'holder destroyed first');
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TestCollections;
var
  EvenOwner, OddOwner: IInterface;
  Rows, Shared: TArray<TRow>;
  List: TList<TRow>;
  Row: TRow;
  I: Integer;

  procedure CheckRow(const Value: TRow);
  begin
    if Odd(Value.Id) then
      Check(PPointer(@Value.Link)^ = Pointer(OddOwner), 'surviving target')
    else
      Check(PPointer(@Value.Link)^ = nil, 'relocated field');
  end;

begin
  EvenOwner := TTarget.Create;
  OddOwner := TTarget.Create;
  List := TList<TRow>.Create;
  try
    for I := 0 to 31 do
    begin
      Row.Id := I;
      if Odd(I) then Row.Link := OddOwner else Row.Link := EvenOwner;
      List.Add(Row);
    end;
    List.Insert(3, Row);
    List.Exchange(1, 6);
    List.Move(3, 9);
    List.DeleteRange(2, 4);
    List.Capacity := 4096;
    Rows := List.ToArray;
    Shared := Rows;
    SetLength(Rows, Length(Rows) + 1024);
    EvenOwner := nil;
    Check(Destroyed = 3, 'list or record copy retained target');
    for I := 0 to List.Count - 1 do
    begin
      CheckRow(List.List[I]);
      CheckRow(Rows[I]);
      CheckRow(Shared[I]);
    end;
    OddOwner := nil;
    Check(Destroyed = 4, 'last target');
    for I := 0 to List.Count - 1 do
      Check((List.List[I].Link = nil) and (Rows[I].Link = nil) and
        (Shared[I].Link = nil), 'remaining fields');
  finally
    List.Free;
  end;
end;

procedure TestForeign;
var
  Foreign, Previous: IInterface;
  Owner: THolder;
  Rejected: Boolean;
begin
  Foreign := TForeign.Create;
  Previous := TTarget.Create;
  Owner := THolder.Create;
  try
    Owner.Link := Previous;
    Rejected := False;
    try
      Owner.Link := Foreign;
    except
      on EIntfCastError do Rejected := True;
    end;
    Check(Rejected and (Owner.Link = Previous), 'unsupported target replaced field');
    Previous := nil;
    Check(Owner.Link = nil, 'old registration lost on failed assignment');
  finally
    Owner.Free;
  end;
end;

procedure TestListStorageArguments(Spare: Boolean);
var
  List: TList<TRow>;
  Rows: TArray<TRow>;
  Owners: array[1..3] of IInterface;
  Row: TRow;
  I: Integer;

  procedure CheckIds(const Ids: array of Integer);
  var
    K: Integer;
  begin
    Check(List.Count = Length(Ids), 'list alias count');
    for K := 0 to High(Ids) do
      Check((List.List[K].Id = Ids[K]) and
        (Pointer(List.List[K].Link) = Pointer(Owners[Ids[K]])), 'list alias value');
  end;

begin
  List := TList<TRow>.Create;
  try
    for I := 1 to 3 do Owners[I] := TInterfacedObject.Create;
    for I := 1 to 2 do begin
      Row.Id := I;
      Row.Link := Owners[I];
      List.Add(Row);
    end;
    List.Capacity := List.Count + Ord(Spare);
    List.Insert(0, List.List[0]);
    CheckIds([1, 1, 2]);
    List.Capacity := List.Count;
    List.Add(List.List[2]);
    CheckIds([1, 1, 2, 2]);
    List.Capacity := List.Count + Ord(Spare);
    if Spare then begin
      List.List[4].Id := 3;
      List.List[4].Link := Owners[3];
    end;
    List.InsertRange(2, List.List);
    if Spare then CheckIds([1, 1, 1, 1, 2, 2, 3, 2, 2])
    else CheckIds([1, 1, 1, 1, 2, 2, 2, 2]);
    Rows := List.ToArray;
    for I := 1 to 3 do Owners[I] := nil;
    for I := 0 to High(Rows) do
      Check((Pointer(Rows[I].Link) = nil) and (Pointer(List.List[I].Link) = nil), 'list alias deregistration');
  finally
    List.Free;
  end;
end;

procedure TestEmptyElements;
var
  List: TList<TEmpty>;
  Empty: TEmpty;
begin
  List := TList<TEmpty>.Create;
  try
    List.Add(Empty);
    List.Insert(0, Empty);
    Check(List.Count = 2, 'zero-sized elements');
  finally
    List.Free;
  end;
end;

procedure TestArrayOperations;
var
  A, B: TArray<TRow>;
  EvenOwner, OddOwner: IInterface;
  I: Integer;

  procedure CheckArray(const Rows: TArray<TRow>);
  var
    Index: Integer;
  begin
    for Index := 0 to High(Rows) do
      if Odd(Rows[Index].Id) then
        Check(PPointer(@Rows[Index].Link)^ = Pointer(OddOwner), 'array odd slot')
      else
        Check(PPointer(@Rows[Index].Link)^ = Pointer(EvenOwner), 'array even slot');
  end;

begin
  EvenOwner := TTarget.Create;
  OddOwner := TTarget.Create;
  SetLength(A, 35);
  for I := 0 to High(A) do
  begin
    A[I].Id := I;
    if Odd(I) then A[I].Link := OddOwner else A[I].Link := EvenOwner;
  end;
  B := Copy(A);
  Insert(B, A, 3);
  Delete(A, 10, 14);
  A := Concat(A, A);
  B := A;
  Delete(A, 0, 1);
  Check((Length(A) = 111) and (Length(B) = 112), 'array lengths');
  CheckArray(A);
  CheckArray(B);
  EvenOwner := nil;
  CheckArray(A);
  CheckArray(B);
  SetLength(A, 5);
  OddOwner := nil;
  CheckArray(A);
  CheckArray(B);
end;

begin
  TestLifetime;
  TestCollections;
  TestArrayOperations;
  TestForeign;
  TestListStorageArguments(False);
  TestListStorageArguments(True);
  TestEmptyElements;
  WriteLn('WEAK_INTERFACE_FIELDS_PASS');
end.
