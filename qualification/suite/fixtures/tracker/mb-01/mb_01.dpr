program tracker_mb_01;

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
  TSparseEnum = (seZero, seOne, seThree = 3, seSeven = 7);
procedure CheckRoundTrip(Value: TSparseEnum);
begin
  var Box := TValue.From<TSparseEnum>(Value);
  Check(Ord(Box.AsType<TSparseEnum>) = Ord(Value),
    'roundtrip-' + IntToStr(Ord(Value)));
end;

procedure Run;
begin
CheckRoundTrip(seZero);
  CheckRoundTrip(seOne);
  CheckRoundTrip(seThree);
  CheckRoundTrip(seSeven);
end;

begin
  try
    Run;
    WriteLn('PASS MB-01');
  except
    on E: Exception do
    begin
      WriteLn('FAIL MB-01: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
