program tracker_qp_17;

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

function SayHello(const Values: array of Integer): string;
begin
  Check((Length(Values) = 1) and (Values[0] = 42), 'nested-values');
  Result := 'hello';
end;
procedure CheckArrays(const A, B, C: array of string);
begin
  Check((Length(A) = 1) and (A[0] = 'aa'), 'first');
  Check((Length(B) = 1) and (B[0] = 'hello'), 'second');
  Check((Length(C) = 1) and (C[0] = 'zz'), 'third');
end;

procedure Run;
begin
CheckArrays(['aa'], [SayHello([42])], ['zz']);
end;

begin
  try
    Run;
    WriteLn('PASS QP-17');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-17: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
