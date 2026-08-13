program tracker_qp_47;

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

type TItem = record Text: string; Marker: Integer; end;

procedure Run;
begin
var List := TList<TItem>.Create;
  try
    for var I := 1 to 16 do
    begin var Item: TItem; Item.Text := 'item-' + IntToStr(I); Item.Marker := I; List.Add(Item); end;
    for var Pass := 1 to 4 do
    begin
      var Sum := 0;
      for var Item in List do
      begin Check(Item.Text = 'item-' + IntToStr(Item.Marker), 'payload'); Inc(Sum, Item.Marker); end;
      Check(Sum = 136, 'sum');
    end;
  finally List.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-47');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-47: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
