program tracker_so_11;

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
  TArrayFactory<T> = class
    class function Make(const A, B: T): TArray<T>; static;
  end;
class function TArrayFactory<T>.Make(const A, B: T): TArray<T>;
begin Result := [A, B]; end;

procedure Run;
begin
var Values := TArrayFactory<string>.Make('a','b');
  Check((Length(Values)=2) and (Values[0]='a') and (Values[1]='b'),'inferred-array');
end;

begin
  try
    Run;
    WriteLn('PASS SO-11');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-11: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
