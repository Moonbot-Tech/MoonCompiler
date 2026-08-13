program tracker_so_07;

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
  ITest = interface ['{12E78E26-9AA3-4371-B670-F4355B272944}'] procedure Ping; end;
  TComponentLike = class(TInterfacedObject, ITest) procedure Ping; virtual; end;
  TGenericBase<T: TComponentLike> = class(TInterfacedObject) protected FTarget: T; end;
  TAdapter = class(TGenericBase<TComponentLike>, ITest)
  private function GetTarget: TComponentLike;
  public constructor Create; destructor Destroy; override; property Target: TComponentLike read GetTarget implements ITest; end;
var PingCount: Integer;
procedure TComponentLike.Ping; begin Inc(PingCount); end;
constructor TAdapter.Create; begin inherited; FTarget := TComponentLike.Create; FTarget._AddRef; end;
destructor TAdapter.Destroy; begin FTarget._Release; inherited; end;
function TAdapter.GetTarget: TComponentLike; begin Result := FTarget; end;

procedure Run;
begin
PingCount := 0; var Value: ITest := TAdapter.Create; Value.Ping; Check(PingCount = 1, 'implements'); Value := nil;
end;

begin
  try
    Run;
    WriteLn('PASS SO-07');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-07: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
