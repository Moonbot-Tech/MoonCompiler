program tracker_qp_29;

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
  TSubrangeHolder<T> = class
  private
    FValue: 0..10;
  public
    procedure SetValue(Value: Integer); inline;
    function GetValue: Integer; inline;
  end;
procedure TSubrangeHolder<T>.SetValue(Value: Integer);
begin FValue := Value; end;
function TSubrangeHolder<T>.GetValue: Integer;
begin Result := FValue; end;

procedure Run;
begin
var Holder := TSubrangeHolder<Integer>.Create;
  try Holder.SetValue(7); Check(Holder.GetValue = 7, 'subrange-field');
  finally Holder.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-29');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-29: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
