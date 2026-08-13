program tracker_qp_02;

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
begin
  Move(Value, Result, SizeOf(Result));
end;

procedure Run;
begin
{$EXCESSPRECISION OFF}
  Check(RawCurrency(Currency(15) / Currency(12)) = 12500, '15-div-12');
  Check(RawCurrency(Currency(-15) / Currency(12)) = -12500, 'negative');
  Check(RawCurrency(Currency(16) / Currency(4)) = 40000, 'exact');
  {$EXCESSPRECISION ON}
  Check(RawCurrency(Currency(15) / Currency(12)) = 12500, 'on-control');
end;

begin
  try
    Run;
    WriteLn('PASS QP-02');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-02: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
