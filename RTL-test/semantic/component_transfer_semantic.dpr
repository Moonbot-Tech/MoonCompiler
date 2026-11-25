program component_transfer_semantic;
{$ifdef FPC}{$mode delphi}{$endif}
{$APPTYPE CONSOLE}
uses SysUtils, Classes;
type
  TItem = class(TComponent);
  THost = class(TComponent)
  public
    Removes, Inserts: Integer;
    Reject: Boolean;
    procedure ValidateRename(AComponent: TComponent; const OldName, NewName: string); override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  published
    Route: TItem;
  end;
procedure THost.ValidateRename(AComponent: TComponent; const OldName, NewName: string);
begin
  if Reject then raise EComponentError.Create('transfer rejected');
  inherited;
end;
procedure THost.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if AComponent is TItem then
    if Operation=opRemove then Inc(Removes) else Inc(Inserts);
end;
procedure Check(Condition: Boolean; const Msg: string);
begin
  if not Condition then raise Exception.Create(Msg);
end;
procedure Run(ExplicitDetach: Boolean);
var A,B:THost; Item:TItem;
begin
  A:=THost.Create(nil);
  B:=THost.Create(nil);
  try
    Item:=TItem.Create(A);
    Item.Name:='Route';
    Check((A.Route=Item) and (A.Inserts=1),'initial owner');
    B.Reject:=True;
    try
      B.InsertComponent(Item);
      raise Exception.Create('accepted rejected transfer');
    except
      on EComponentError do ;
    end;
    B.Reject:=False;
    Check((Item.Owner=A) and (A.Route=Item) and (A.Removes=0),'rejected transfer changed ownership');
    A.Reject:=True;
    try
      try
        if ExplicitDetach then A.RemoveComponent(Item) else B.InsertComponent(Item);
        raise Exception.Create('old owner accepted rejected removal');
      except
        on EComponentError do ;
      end;
    finally
      A.Reject:=False;
    end;
    Check((Item.Owner=A) and (A.ComponentCount=1) and (A.Components[0]=Item) and (A.Route=Item) and
      (A.Removes=0),'old owner changed on rejected removal');
    Check((B.ComponentCount=0) and (B.Route=nil) and (B.Inserts=0),'new owner changed on rejected removal');
    if ExplicitDetach then A.RemoveComponent(Item);
    B.InsertComponent(Item);
    Check((A.Route=nil) and (A.ComponentCount=0) and (A.Removes=1),'old owner');
    Check((B.Route=Item) and (B.ComponentCount=1) and (B.Inserts=1) and (Item.Owner=B),'new owner');
    FreeAndNil(B);
    Check((A.Route=nil) and (A.Removes=1),'old owner');
  finally
    B.Free;
    A.Free;
  end;
end;
procedure ReinsertSameOwner;
var
  Host: THost;
  Item, Other: TItem;
begin
  Host:=THost.Create(nil);
  try
    Item:=TItem.Create(Host);
    Other:=TItem.Create(Host);
    Host.InsertComponent(Item);
    Check((Host.ComponentCount=2) and (Host.Components[0]=Other) and (Host.Components[1]=Item),
      'unnamed reinsert must move item to end');
    Check((Host.Removes=0) and (Host.Inserts=3),'unnamed reinsert notifications');
    Item.Name:='Route';
    try
      Host.InsertComponent(Item);
      raise Exception.Create('accepted named same-owner reinsert');
    except
      on EComponentError do ;
    end;
    Check((Host.Route=Item) and (Host.Removes=0) and (Host.Inserts=3),'named reinsert changed state');
  finally
    Host.Free;
  end;
end;
begin
  Run(False);
  Run(True);
  ReinsertSameOwner;
  WriteLn('COMPONENT_TRANSFER_PASS');
end.
