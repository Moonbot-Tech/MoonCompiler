program tracker_qp_18;

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

const
  Table: array['A'..'Z'] of AnsiChar =
    ('Q','W','E','R','T','Y','U','I','O','P','A','S','D',
     'F','G','H','J','K','L','Z','X','C','V','B','N','M');
function DoubleLookup(Value: AnsiChar): AnsiChar; inline;
begin Result := Table[Table[Value]]; end;

procedure Run;
begin
for var Code := Ord('A') to Ord('Z') do
  begin
    var C := AnsiChar(Code);
    var First: AnsiChar := Table[C];
    var Expected: AnsiChar := Table[First];
    Check(DoubleLookup(C) = Expected, 'double-lookup');
  end;
  Check((Table[Table['A']] = Table[Table['B']]) = (DoubleLookup('A') = DoubleLookup('B')), 'comparison');
end;

begin
  try
    Run;
    WriteLn('PASS QP-18');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-18: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
