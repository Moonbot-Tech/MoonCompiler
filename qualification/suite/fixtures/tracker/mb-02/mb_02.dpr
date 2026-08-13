program tracker_mb_02;

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

function ExerciseFinallyLoop(Seed: Integer; var Trail: AnsiString): Integer;
begin
  Result := Seed;
  for var I := 0 to 9 do
    try
      if (I + Seed) mod 4 = 0 then Continue;
      if I = 8 then Break;
      Inc(Result, I * 3);
    finally
      Trail := Trail + AnsiChar(65 + I);
    end;
end;

procedure Run;
begin
var Trail: AnsiString := '';
  Check(ExerciseFinallyLoop(107, Trail) = 173, 'value');
  Check(Trail = 'ABCDEFGHI', 'finally-trail');
end;

begin
  try
    Run;
    WriteLn('PASS MB-02');
  except
    on E: Exception do
    begin
      WriteLn('FAIL MB-02: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
