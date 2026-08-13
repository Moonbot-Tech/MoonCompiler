program tracker_so_17;

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

type TMethod=procedure of object; TAction=reference to procedure; TDummy=class procedure Ping; end;
var Calls:Integer;
procedure TDummy.Ping; begin Inc(Calls); end;
function Wrap(Method:TMethod):TAction;
begin Result:=procedure begin if Assigned(Method) then Method(); end; end;

procedure Run;
begin
Calls:=0; var Empty:TMethod:=nil; var Action:=Wrap(Empty); Check(not Assigned(Empty),'method-nil'); Action(); Check(Calls=0,'no-call');
  var Dummy:=TDummy.Create; try var Live:TMethod:=Dummy.Ping; Action:=Wrap(Live); Action(); Check(Calls=1,'live-call'); finally Dummy.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-17');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-17: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
