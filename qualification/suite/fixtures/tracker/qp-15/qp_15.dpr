program tracker_qp_15;

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
  TUInt64Array = array of UInt64;
  TArrayRecord = record
    Values: TUInt64Array;
    class operator Implicit(const Source: array of UInt64): TArrayRecord;
  end;
class operator TArrayRecord.Implicit(const Source: array of UInt64): TArrayRecord;
begin
  SetLength(Result.Values, Length(Source));
  for var I := 0 to High(Source) do Result.Values[I] := Source[I];
end;
procedure Verify(const Value: TArrayRecord; A, B: UInt64);
begin
  Check(Length(Value.Values) = 2, 'length');
  Check((Value.Values[0] = A) and (Value.Values[1] = B), 'payload');
end;

procedure Run;
begin
var StaticValues: array[0..1] of UInt64;
  StaticValues[0] := 11;
  StaticValues[1] := 22;
  var DynamicValues: TUInt64Array := TUInt64Array.Create(11, 22);
  var R: TArrayRecord := [11, 22]; Verify(R, 11, 22);
  R := StaticValues; Verify(R, 11, 22);
  R := DynamicValues; Verify(R, 11, 22);
end;

begin
  try
    Run;
    WriteLn('PASS QP-15');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-15: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
