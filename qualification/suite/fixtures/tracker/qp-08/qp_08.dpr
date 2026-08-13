program tracker_qp_08;

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
  TPositive = 0..High(Int64);

procedure Take(Value: TPositive);
begin
  if Value = 123 then
    Write('');
end;

procedure Run;
begin
var Raised := False;
  var P: TPositive := 1;
  {$R+}
  try
    Take(-P);
  except
    on ERangeError do Raised := True;
  end;
  {$R-}
  Check(Raised, 'range-error-missing');
end;

begin
  try
    Run;
    WriteLn('PASS QP-08');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-08: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
