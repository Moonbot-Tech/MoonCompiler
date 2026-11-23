program tlist_source_alias_semantic;
{$mode delphiunicode}

uses SysUtils, Generics.Collections;

type
  TTarget = class(TInterfacedObject)
    destructor Destroy; override;
  end;
  TCounter = class(TObject, IInterface)
    Owners, ZeroTransitions: Integer;
    function QueryInterface(constref IID: TGUID; out Obj): HResult; {$ifdef windows}stdcall{$else}cdecl{$endif};
    function _AddRef: LongInt; {$ifdef windows}stdcall{$else}cdecl{$endif};
    function _Release: LongInt; {$ifdef windows}stdcall{$else}cdecl{$endif};
  end;
  TRow = record
    Link: IInterface;
    Id: Integer;
  end;
  TLarge = record
    Fields: array[0..7] of Int64;
  end;
  TAssigned = record
    Number: Integer;
    class operator Assign(var Dest: TAssigned; const [ref] Source: TAssigned);
  end;

var
  Destroyed, Assignments: Integer;

destructor TTarget.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

class operator TAssigned.Assign(var Dest: TAssigned; const [ref] Source: TAssigned);
begin
  Inc(Assignments);
  Dest.Number := Source.Number + 1;
end;

procedure Check(OK: Boolean; const Operation: string);
begin
  if not OK then raise Exception.Create(Operation);
end;

function TCounter.QueryInterface(constref IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result := 0 else Result := E_NOINTERFACE;
end;

function TCounter._AddRef: LongInt;
begin
  Inc(Owners);
  Result := Owners;
end;

function TCounter._Release: LongInt;
begin
  Dec(Owners);
  if Owners = 0 then Inc(ZeroTransitions);
  Result := Owners;
end;

procedure StoreSpare(List: TList<IInterface>; Counter: TCounter);
var
  Value: IInterface;
begin
  Value := Counter;
  List.List[List.Count] := Value;
end;

procedure CheckScalarOwner;
var
  List: TList<IInterface>;
  Counter: TCounter;
  Empty: array[0..0] of IInterface;
begin
  Counter := TCounter.Create;
  List := TList<IInterface>.Create;
  try
    List.Capacity := 3;
    List.Add(nil);
    StoreSpare(List, Counter);
    List.Insert(0, List.List[List.Count]);
    Check((Counter.Owners = 1) and (Counter.ZeroTransitions = 0), 'scalar owner lost during insert');
    StoreSpare(List, Counter);
    Empty[0] := nil;
    List.AddRange(Empty);
    Check(Counter.Owners = 1, 'range overwrote an owned spare slot');
    List.Clear;
    Check((Counter.Owners = 0) and (Counter.ZeroTransitions = 1), 'scalar owner release count');
  finally
    List.Free;
    Counter.Free;
  end;
end;

procedure CheckOwners(Spare: Integer);
var
  List: TList<TRow>;
  Row: TRow;
  Owner: Pointer;
  I, Before: Integer;
begin
  Before := Destroyed;
  List := TList<TRow>.Create;
  try
    Row.Link := TTarget.Create;
    Owner := Pointer(Row.Link);
    Row.Id := 41;
    List.Add(Row);
    Row.Link := nil;
    Row.Id := 99;
    List.Add(Row);
    List.Capacity := 2 + Spare;
    List.Insert(0, List.List[0]);
    Check((List.List[0].Id = 41) and (Pointer(List.List[0].Link) = Owner), 'insert lost original value');
    Check((List.List[1].Id = 41) and (Pointer(List.List[1].Link) = Owner), 'insert lost shifted value');
    List.Capacity := List.Count;
    List.Add(List.List[0]);
    List.Capacity := List.Count;
    List.InsertRange(1, List.List);
    for I := 0 to List.Count - 1 do
      if (I = 3) or (I = 6) then
        Check((List.List[I].Id = 99) and (List.List[I].Link = nil), 'range changed empty item')
      else
        Check((List.List[I].Id = 41) and (Pointer(List.List[I].Link) = Owner), 'range lost owner');
    List.DeleteRange(0, List.Count - 1);
    Check((Destroyed = Before) and (Pointer(List.List[0].Link) = Owner), 'last owner was lost');
  finally
    List.Free;
  end;
  Check(Destroyed = Before + 1, 'unbalanced ownership');
end;

procedure CheckUnmanaged;
var
  Values: TList<TLarge>;
  Row: TLarge;
  I: Integer;
begin
  Values := TList<TLarge>.Create;
  try
    for I := 1 to 3 do begin
      Row.Fields[7] := I;
      Values.Add(Row);
    end;
    Values.Insert(0, Values.List[2]);
    Check(Values.List[0].Fields[7] = 3, 'large record taken from shifted slot');
    Values.Capacity := Values.Count;
    Values.InsertRange(1, Values.List);
    Check((Values.List[1].Fields[7] = 3) and (Values.List[2].Fields[7] = 1) and
      (Values.List[3].Fields[7] = 2) and (Values.List[4].Fields[7] = 3), 'overlapping unmanaged range');
  finally
    Values.Free;
  end;
end;

procedure CheckAssignment;
var
  Values: TList<TAssigned>;
  Row: TAssigned;
  Before, Original: Integer;
begin
  Row.Number := 40;
  Values := TList<TAssigned>.Create;
  try
    Values.Capacity := 4;
    Values.Add(Row);
    Original := Values.List[0].Number;
    Before := Assignments;
    Values.Insert(0, Values.List[0]);
    Check((Assignments = Before + 1) and (Values.List[0].Number = Original + 1) and
      (Values.List[1].Number = Original), 'custom assignment ran on a temporary');
    Values.List[Values.Count].Number := 73;
    Before := Assignments;
    Values.Insert(0, Values.List[Values.Count]);
    Check((Assignments = Before + 1) and (Values.List[0].Number = 74), 'source in first spare slot');
    Values.List[3].Number := 127;
    Before := Assignments;
    Values.InsertRange(1, Values.List);
    Check((Assignments = Before + 4) and (Values.List[1].Number = 75) and
      (Values.List[4].Number = 128), 'range crossing live and spare slots');
  finally
    Values.Free;
  end;
end;

begin
  CheckOwners(0);
  CheckOwners(4);
  CheckUnmanaged;
  CheckScalarOwner;
  CheckAssignment;
  WriteLn('TLIST_SOURCE_ALIAS_PASS');
end.
