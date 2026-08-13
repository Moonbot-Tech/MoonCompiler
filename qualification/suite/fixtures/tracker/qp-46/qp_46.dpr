program tracker_qp_46;

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

procedure WriteValue(out Dest: TValue; const Source: string);
begin Dest := TValue.From<string>(Source); end;

procedure Run;
begin
var Values: array[0..3] of string;
  Values[0] := 'aa'; Values[1] := 'bb'; Values[2] := 'cc'; Values[3] := 'dd';
  for var S in Values do
  begin
    var Value: TValue;
    WriteValue(Value, S);
    Check(Value.AsString = S, 'tvalue-' + S);
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-46');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-46: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
