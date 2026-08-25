program tdelphinilvaroverload1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

type
  TItem = record
    Value: Integer;
  end;
  PItem = ^TItem;
  PPItem = ^PItem;
  THolder = record
    Item: PItem;
  end;

{$J-}
const
  ReadOnlyNilItemConst: PItem = nil;

{$J+}
const
  WritableNilItemConst: PItem = nil;

var
  Item: PItem;
  Outer: PPItem;
  Holder: THolder;
  Items: array[0..0] of PItem;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

function Pick(AValue: PPItem): Integer; overload;
begin
  Result := 11;
end;

function Pick(var AValue: PItem): Integer; overload;
begin
  Result := 12;
end;

function PickPointer(AValue: Pointer): Integer; overload;
begin
  Result := 21;
end;

function PickPointer(var AValue: PItem): Integer; overload;
begin
  Result := 22;
end;

function PickOut(AValue: Pointer): Integer; overload;
begin
  Result := 31;
end;

function PickOut(out AValue: PItem): Integer; overload;
begin
  AValue := nil;
  Result := 32;
end;

procedure CheckConstParameter(const AValue: PItem);
begin
  Check(PickPointer(AValue) = 21, 12);
end;

begin
  { Literals and read-only constants have no writable storage, so var/out
    candidates must be removed before overload ranking. }
  Check(Pick(nil) = 11, 1);
  Check(PickPointer(nil) = 21, 2);
  Check(PickPointer(PItem(nil)) = 21, 3);
  Check(PickPointer(ReadOnlyNilItemConst) = 21, 4);
  Check(PickOut(nil) = 31, 5);

  { A $J+ typed constant is writable storage. It and ordinary pointer lvalues
    still select the var/out overloads. }
  Check(PickPointer(WritableNilItemConst) = 22, 13);
  Item := nil;
  Check(PickPointer(Item) = 22, 6);
  Holder.Item := nil;
  Check(PickPointer(Holder.Item) = 22, 7);
  Items[0] := nil;
  Check(PickPointer(Items[0]) = 22, 8);
  Outer := @Item;
  Check(PickPointer(Outer^) = 22, 9);
  Item := Pointer(1);
  Check(PickOut(Item) = 32, 10);
  Check(Item = nil, 11);
  CheckConstParameter(nil);
end.
