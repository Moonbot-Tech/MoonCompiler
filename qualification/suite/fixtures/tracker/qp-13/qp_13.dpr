program tracker_qp_13;

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
  TManagedResult = record
    Text: string;
  end;

function MakeManagedResult(Value: Integer): TManagedResult;
begin Result.Text := 'value:' + IntToStr(Value); end;

procedure JumpOverResults(DoJump: Boolean);
label Done;
begin
  if DoJump then
    goto Done;
  MakeManagedResult(1);
  MakeManagedResult(2);
Done:
end;

procedure Run;
begin
for var I := 0 to 255 do
    JumpOverResults((I and 1) = 0);
end;

begin
  try
    Run;
    WriteLn('PASS QP-13');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-13: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
