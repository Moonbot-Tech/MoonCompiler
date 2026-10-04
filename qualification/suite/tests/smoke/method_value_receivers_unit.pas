unit method_value_receivers_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ The initialization of a unit gives a method of a value to a method pointer:
  a global of the implementation, which only the initialization reads, and a
  value that is no variable - a record with a managed field returned by a
  function (tests/smoke/method_value_receivers.pas) }

interface

var
  InitRecord, InitManaged: Int64;

implementation

type
  TMethodProc = procedure(Step: Integer) of object;
  TRec8 = record
    V: Int64;
    procedure Step(A: Integer);
  end;
  TRecStr = record
    S: string;
    V: Integer;
    procedure Step(A: Integer);
  end;

var
  SeenLength: Integer;

procedure TRec8.Step(A: Integer);
begin
  Inc(V, A);
end;

procedure TRecStr.Step(A: Integer);
begin
  Inc(V, A);
  SeenLength := Length(S);
  InitManaged := V;
end;

function MakeStr(const S: string): TRecStr;
begin
  Result.S := S;
  Result.V := 1;
end;

var
  R: TRec8;
  M, N: TMethodProc;

initialization
  R.V := 1;
  M := R.Step;
  M(2);
  InitRecord := R.V;
  N := MakeStr('abcde').Step;
  N(2);
  InitManaged := InitManaged * 1000 + SeenLength;
end.
