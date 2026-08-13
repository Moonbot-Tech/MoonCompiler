program fpc_40212_absolute_result;

{$mode objfpc}{$H+}

var
  Index: Integer = 0;

const
  Values: array[0..1] of Integer = (1052909725, 1092805937);

function GetLong: Integer;
begin
  Result := Values[Index];
  Inc(Index);
end;

function GetDouble: Double;
type
  TDoubleWords = packed record
    LowWord, HighWord: Integer;
  end;
var
  Words: TDoubleWords absolute Result;
begin
  Words.LowWord := GetLong;
  Words.HighWord := GetLong;
end;

var
  R: Double;
begin
  R := GetDouble;
  if Round(R * 100000) <> 61916062257 then
  begin
    WriteLn('FAIL fpc-40212 value=', R:0:12);
    Halt(1);
  end;
  WriteLn('PASS fpc-40212');
end.
