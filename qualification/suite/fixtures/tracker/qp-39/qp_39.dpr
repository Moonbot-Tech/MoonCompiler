program tracker_qp_39;

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
function CurrencyFromRaw(Value: Int64): Currency;
begin Move(Value, Result, SizeOf(Result)); end;

procedure Run;
begin
var A: Currency := CurrencyFromRaw(9223372036854770000);
  var B: Currency := CurrencyFromRaw(9223372036854769999);
  Check(RawCurrency(Math.Max(A, B)) = RawCurrency(A), 'max-order-1');
  Check(RawCurrency(Math.Max(B, A)) = RawCurrency(A), 'max-order-2');
  Check(RawCurrency(Math.Min(A, B)) = RawCurrency(B), 'min-order-1');
  Check(RawCurrency(Math.Min(B, A)) = RawCurrency(B), 'min-order-2');
end;

begin
  try
    Run;
    WriteLn('PASS QP-39');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-39: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
