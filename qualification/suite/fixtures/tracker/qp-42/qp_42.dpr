program tracker_qp_42;

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

function Div4294967295(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967295); end;
function Div4294967296(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967296); end;
function Div4294967297(Value: UInt64): UInt64; inline; begin Result := Value div UInt64(4294967297); end;

procedure Run;
begin
var Value: UInt64 := High(UInt64);
  Check(Div4294967295(Value) = 4294967297, 'd4294967295');
  Check(Div4294967296(Value) = 4294967295, 'd4294967296');
  Check(Div4294967297(Value) = 4294967295, 'd4294967297');
  Check(Value mod UInt64(4294967295) = 0, 'r4294967295');
  Check(Value mod UInt64(4294967296) = 4294967295, 'r4294967296');
end;

begin
  try
    Run;
    WriteLn('PASS QP-42');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-42: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
