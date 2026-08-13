program tracker_qp_09;

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
  TOpenArrayProbe = record
    LengthSeen: NativeInt;
    HighSeen: NativeInt;
    Sum: Integer;
    class operator Implicit(const Values: array of Byte): TOpenArrayProbe;
  end;

class operator TOpenArrayProbe.Implicit(const Values: array of Byte): TOpenArrayProbe;
begin
  Result.LengthSeen := Length(Values);
  Result.HighSeen := High(Values);
  Result.Sum := 0;
  for var Value in Values do
    Inc(Result.Sum, Value);
end;

procedure Run;
begin
var Empty: TOpenArrayProbe := [];
  var One: TOpenArrayProbe := [7];
  var Many: TOpenArrayProbe := [1, 2, 3];
  Check((Empty.LengthSeen = 0) and (Empty.HighSeen = -1), 'empty');
  Check((One.LengthSeen = 1) and (One.HighSeen = 0) and (One.Sum = 7), 'one');
  Check((Many.LengthSeen = 3) and (Many.HighSeen = 2) and (Many.Sum = 6), 'many');
end;

begin
  try
    Run;
    WriteLn('PASS QP-09');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-09: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
