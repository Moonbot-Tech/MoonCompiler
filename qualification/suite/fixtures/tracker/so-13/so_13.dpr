program tracker_so_13;

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
  TOpenArrayProc<T> = procedure(var Values: array of T);
  TSwapper<T> = class
    class procedure SwapFirstLast(var Values: array of T); static;
  end;
class procedure TSwapper<T>.SwapFirstLast(var Values: array of T);
begin if Length(Values)>1 then begin var Temp:=Values[0]; Values[0]:=Values[High(Values)]; Values[High(Values)]:=Temp; end; end;

procedure Run;
begin
var Values: TArray<Integer> := [1,2,3]; var Proc: TOpenArrayProc<Integer> := TSwapper<Integer>.SwapFirstLast;
  Proc(Values); Check((Values[0]=3) and (Values[2]=1),'swap');
end;

begin
  try
    Run;
    WriteLn('PASS SO-13');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-13: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
