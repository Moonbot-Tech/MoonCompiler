program list_insert_reserved_semantic;
{$mode delphiunicode}{$H+}
uses SysUtils, Generics.Collections;
type
  TDerived = class(TList<Integer>)
    Preparations, Notifications: Integer;
    FailPrepare: Boolean;
    function PrepareAddingItem: SizeInt; override;
    procedure Notify(const Item: Integer; Action: TCollectionNotification); override;
  end;
  TObserver = class
    Added: Integer;
    procedure Notify(Sender: TObject; const Item: Integer; Action: TCollectionNotification);
  end;

function TDerived.PrepareAddingItem: SizeInt;
begin
  Inc(Preparations);
  if FailPrepare then raise Exception.Create('prepare');
  Result := inherited;
end;

procedure TDerived.Notify(const Item: Integer; Action: TCollectionNotification);
begin
  Inc(Notifications);
  inherited;
end;

procedure TObserver.Notify(Sender: TObject; const Item: Integer; Action: TCollectionNotification);
begin
  if Action = cnAdded then Inc(Added);
end;

procedure Check(Value: Boolean);
begin
  if not Value then Halt(1);
end;

var L: TList<Integer>; D: TDerived; O: TObserver;
  Expected: array[0..127] of Integer;
  I, J, Index: Integer;
  Raised: Boolean;
begin
  L := TList<Integer>.Create;
  L.Capacity := 128;
  for I := 0 to 127 do
  begin
    Index := (I * 17) mod (I + 1);
    for J := I downto Index + 1 do Expected[J] := Expected[J - 1];
    Expected[Index] := I;
    L.Insert(Index, I);
    Check(L.Count = I + 1);
    for J := 0 to I do Check(L[J] = Expected[J]);
  end;
  L.Insert(128, 128);
  Check((L.Count = 129) and (L[128] = 128));
  for I := 0 to 1 do
  begin
    if I = 0 then Index := -1 else Index := 130;
    Raised := False;
    try L.Insert(Index, 999); except on EArgumentOutOfRangeException do Raised := True; end;
    Check(Raised and (L.Count = 129));
  end;
  O := TObserver.Create;
  L.OnNotify := O.Notify;
  L.Insert(0, 777);
  Check((O.Added = 1) and (L[0] = 777));
  L.OnNotify := nil;
  L.Free;
  O.Free;

  D := TDerived.Create;
  D.Capacity := 32;
  D.Insert(0, 11);
  D.Insert(0, 22);
  Check((D.Preparations = 2) and (D.Notifications = 2) and (D[0] = 22) and (D[1] = 11));
  D.FailPrepare := True;
  Raised := False;
  try D.Insert(1, 33); except on E: Exception do Raised := E.Message = 'prepare'; end;
  Check(Raised and (D.Count = 2) and (D[0] = 22) and (D[1] = 11) and (D.Notifications = 2));
  D.Free;
  WriteLn('LIST_INSERT_RESERVED_OK');
end.
