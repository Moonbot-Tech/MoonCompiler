program tracker_mb_05;

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

var
  LeftValue: UInt64;
  RightValue: UInt64;

procedure Run;
begin
LeftValue := 0;
  RightValue := 0;
  Check((LeftValue = 0) and (RightValue = 0), 'uint64-comparison-and');
end;

begin
  try
    Run;
    WriteLn('PASS MB-05');
  except
    on E: Exception do
    begin
      WriteLn('FAIL MB-05: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
