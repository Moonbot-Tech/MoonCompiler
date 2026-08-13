program tracker_so_14;

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

type TIntMatrix = TArray<TArray<Integer>>;

procedure Run;
begin
var Values: TIntMatrix; SetLength(Values,2,3);
  for var I:=0 to 1 do for var J:=0 to 2 do Values[I,J]:=I*10+J;
  Check((Length(Values)=2) and (Length(Values[0])=3) and (Values[1,2]=12),'matrix');
end;

begin
  try
    Run;
    WriteLn('PASS SO-14');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-14: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
