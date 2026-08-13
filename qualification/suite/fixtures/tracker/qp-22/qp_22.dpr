program tracker_qp_22;

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
  TIntArray = TArray<Integer>;
  TStringArray = TArray<string>;
  TUnrelatedAlias = TIntArray;
function Pick(const Values: TIntArray): Integer; overload;
begin Result := 1; end;
function Pick(const Values: TStringArray): Integer; overload;
begin Result := 2; end;

procedure Run;
begin
Check(Pick([2]) = 1, 'literal-overload');
  var Typed: TUnrelatedAlias := [2];
  Check(Pick(Typed) = 1, 'alias-control');
end;

begin
  try
    Run;
    WriteLn('PASS QP-22');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-22: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
