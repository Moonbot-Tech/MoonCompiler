program tracker_qp_28;

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
  TShort20 = string[20];
  TSearch<T> = class
    class function Contains(const Values: array of T; const Needle: T): Boolean; static;
  end;
class function TSearch<T>.Contains(const Values: array of T; const Needle: T): Boolean;
begin
  Result := False;
  for var Value in Values do
    if Value = Needle then Exit(True);
end;

procedure Run;
begin
var A: TShort20 := 'ABC';
  var B: TShort20 := 'DEF';
  var C: TShort20 := 'XYZ';
  Check(TSearch<TShort20>.Contains([A, B, C], B), 'found');
  var Missing: TShort20 := 'NOPE';
  Check(not TSearch<TShort20>.Contains([A, B, C], Missing), 'missing');
end;

begin
  try
    Run;
    WriteLn('PASS QP-28');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-28: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
