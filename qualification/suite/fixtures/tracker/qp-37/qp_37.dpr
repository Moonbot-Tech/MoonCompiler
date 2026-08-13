program tracker_qp_37;

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

const VariantInputs: array[0..4] of Integer = (0, 42, 200, 15658, 65535);
function NarrowMax(Left, Right: Byte): Integer; overload;
begin if Left > Right then Result := Left else Result := Right; end;
function NarrowMax(Left, Right: Integer): Integer; overload;
begin if Left > Right then Result := Left else Result := Right; end;

procedure Run;
begin
for var N in VariantInputs do
  begin
    var V: Variant := N;
    Check(Integer(Math.Max(V, 100)) = Math.Max(N, 100), 'math-max-' + IntToStr(N));
    Check(Integer(Math.Min(V, 100)) = Math.Min(N, 100), 'math-min-' + IntToStr(N));
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-37');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-37: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
