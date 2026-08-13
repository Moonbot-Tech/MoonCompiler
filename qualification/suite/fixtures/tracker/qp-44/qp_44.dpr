program tracker_qp_44;

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
  ITracked = interface ['{E7316A62-50AD-4B4B-A31B-78B47B89D26A}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TAction = reference to procedure;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure Execute(const Action: TAction); begin Action(); end;

procedure Run;
begin
for var I := 1 to 100 do
  begin
    var Token: ITracked := TTracked.Create;
    Execute(procedure begin if Token = nil then Halt(2); end);
    Token := nil;
    Check(TTracked.Alive = 0, 'iteration-release-' + IntToStr(I));
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-44');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-44: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
