program tracker_qp_16;

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

type TIntegerArray = array of Integer;
var Calls: Integer;
function GetArray(Tag: Integer): TIntegerArray;
begin Inc(Calls); Result := TIntegerArray.Create(Tag); end;
procedure Consume(const Values: array of Integer);
begin
  Check(Length(Values) = 2, 'length');
  Check((Values[0] = 11) and (Values[1] = 22), 'payload');
end;

procedure Run;
begin
Calls := 0;
  Consume(GetArray(11) + GetArray(22));
  Check(Calls = 2, 'call-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-16');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-16: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
