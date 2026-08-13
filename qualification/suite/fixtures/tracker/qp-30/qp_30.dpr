program tracker_qp_30;

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
  TNumber = record
    Value: Integer;
    class function Make(AValue: Integer): TNumber; static;
  end;
class function TNumber.Make(AValue: Integer): TNumber;
begin Result.Value := AValue; end;
function Slice(const Values: array of Integer; Count, Marker: Integer): TArray<Integer>;
begin
  SetLength(Result, Count);
  for var I := 0 to Count - 1 do Result[I] := Values[I] + Marker;
end;
procedure Consume(const Records: array of TNumber; const Values: array of Integer);
begin
  Check((Length(Records) = 1) and (Records[0].Value = 800), 'record-literal');
  Check((Length(Values) = 2) and (Values[0] = 1077) and (Values[1] = 977), 'function-array');
end;

procedure Run;
begin
Consume([TNumber.Make(800)], Slice([1000, 900, 800], 2, 77));
end;

begin
  try
    Run;
    WriteLn('PASS QP-30');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-30: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
