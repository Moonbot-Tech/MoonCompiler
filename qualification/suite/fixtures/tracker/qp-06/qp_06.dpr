program tracker_qp_06;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

type
  TItem = class
    Id: Integer;
    constructor Create(AId: Integer);
  end;

constructor TItem.Create(AId: Integer);
begin
  inherited Create;
  Id := AId;
end;

function FindItem(const List: TObjectList<TItem>; Id: Integer): TItem; inline;
var
  Item: TItem;
begin
  for Item in List do
    if Item.Id = Id then
      Exit(Item);
  Result := nil;
end;

procedure Run;
begin
var List := TObjectList<TItem>.Create(True);
  try
    List.Add(TItem.Create(11));
    List.Add(TItem.Create(22));
    Check(FindItem(List, 22) = List[1], 'found');
    Check(FindItem(List, 99) = nil, 'missing');
  finally
    List.Free;
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-06');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-06: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
