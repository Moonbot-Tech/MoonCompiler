program tracker_so_15;

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
  ITracked = interface ['{0DD6DAF0-5E52-402B-8763-453910D2DB57}'] end;
  TTracked = class(TInterfacedObject,ITracked) public class var Alive:Integer; constructor Create; destructor Destroy; override; end;
  TAggregate = record Text:string; Ref:ITracked; Marker:Integer; end;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure Exercise;
begin var Value: TAggregate; Value.Text:='ok'; Value.Ref:=TTracked.Create; Value.Marker:=73; Check((Value.Text='ok') and (Value.Marker=73),'payload'); end;

procedure Run;
begin
Exercise; Check(TTracked.Alive=0,'aggregate-release');
end;

begin
  try
    Run;
    WriteLn('PASS SO-15');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-15: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
