program tracker_qp_40;

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

function RawCurrency(const Value: Currency): Int64;
begin Move(Value, Result, SizeOf(Result)); end;

procedure Run;
begin
var A: Currency := 12.3450;
  var B: Currency := -12.3450;
  Check(RawCurrency(SimpleRoundTo(A, -2)) = 123500, 'positive-half');
  Check(RawCurrency(SimpleRoundTo(B, -2)) = -123500, 'negative-half');
end;

begin
  try
    Run;
    WriteLn('PASS QP-40');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-40: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
