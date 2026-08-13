program tracker_qp_41;

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

function Mod2147483647(Value: Int64): Int64; inline; begin Result := Value mod 2147483647; end;
function Mod2147483648(Value: Int64): Int64; inline; begin Result := Value mod 2147483648; end;
function Mod3600000000(Value: Int64): Int64; inline; begin Result := Value mod 3600000000; end;
function Mod4294967295(Value: Int64): Int64; inline; begin Result := Value mod 4294967295; end;

procedure Run;
begin
var Value: Int64 := 9223372036854775000;
  Check(Mod2147483647(Value) = 2147482841, 'd2147483647');
  Check(Mod2147483648(Value) = 2147482840, 'd2147483648');
  Check(Mod3600000000(Value) = 54775000, 'd3600000000');
  Check(Mod4294967295(Value) = 2147482840, 'd4294967295');
  Check(Mod3600000000(-Value) = -54775000, 'negative');
end;

begin
  try
    Run;
    WriteLn('PASS QP-41');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-41: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
