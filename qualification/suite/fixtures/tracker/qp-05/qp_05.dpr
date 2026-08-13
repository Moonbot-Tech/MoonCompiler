program tracker_qp_05;

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

function EarlyFalse: Boolean;
var
  List: TList<TObject>;
  Item: TObject;
begin
  List := TList<TObject>.Create;
  try
    List.Add(TObject.Create);
    List.Add(TObject.Create);
    try
      for Item in List do
      begin
        Result := False;
        Exit;
      end;
      Result := True;
    finally
      for Item in List do
        Item.Free;
    end;
  finally
    List.Free;
  end;
end;

procedure Run;
begin
Check(not EarlyFalse, 'early-false');
end;

begin
  try
    Run;
    WriteLn('PASS QP-05');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-05: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
