program tracker_so_05;

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
  ITracked = interface ['{F6EBBE46-90CF-4FB4-B95F-546FF4E53E9C}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
  TAction = reference to procedure;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
function MakeProc: TAction;
begin
  var Token: ITracked := TTracked.Create;
  Result := procedure begin if Token = nil then Halt(2); end;
end;

procedure Run;
begin
var First := MakeProc; var Second := First;
  Check(TTracked.Alive = 1, 'alive=' + IntToStr(TTracked.Alive));
  First := nil;
  Check(TTracked.Alive = 1, 'copy-alive=' + IntToStr(TTracked.Alive));
  Second := nil;
  Check(TTracked.Alive = 0, 'released=' + IntToStr(TTracked.Alive));
end;

begin
  try
    Run;
    WriteLn('PASS SO-05');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-05: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
