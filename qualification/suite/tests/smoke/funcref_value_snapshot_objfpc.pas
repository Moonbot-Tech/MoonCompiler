program funcref_value_snapshot_objfpc;
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{ In the FPC modes a procedure variable given to "reference to" keeps the
  value it has at the conversion (FPC's documented difference from Delphi,
  which reads the variable at every call).  The snapshot belongs to its
  conversion: two conversions of one variable or of one method in a routine
  used to share the Invoke and the field of the first, so the second called
  the first value; an event field or a function result stopped the compiler
  (internal error 2022022102); overloads got the interface of the first. }
type
  TIntProc = reference to procedure(Step: Integer);
  TStrProc = reference to procedure(const S: string);
  TMethodProc = procedure(Step: Integer) of object;

  TCounter = class
    Count: Integer;
    OnStep: TMethodProc;
    procedure Step(Amount: Integer);
  end;

var
  A, B: TCounter;
  GI: Integer;
  GS: string;
  Failures: Integer;

procedure TCounter.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure Put(X: Integer); overload;
begin
  Inc(GI, X);
end;

procedure Put(const S: string); overload;
begin
  GS := GS + S;
end;

function GetHandler: TMethodProc;
begin
  Result := @B.Step;
end;

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Want);
    Inc(Failures);
  end;
end;

function AB: Integer;
begin
  Result := A.Count * 100 + B.Count;
  A.Count := 0;
  B.Count := 0;
end;

procedure TwoObjects;
var
  P, Q: TIntProc;
begin
  P := @A.Step;
  Q := @B.Step;
  P(1);
  Q(2);
end;

procedure OneVariableTwice;
var
  MP: TMethodProc;
  F, G: TIntProc;
begin
  MP := @A.Step;
  F := MP;
  MP := @B.Step;
  G := MP;
  MP := nil;
  F(1);
  G(2);
end;

procedure EventField;
var
  F: TIntProc;
begin
  A.OnStep := @A.Step;
  F := A.OnStep;
  A.OnStep := @B.Step;
  F(1);
end;

procedure HandlerResult;
var
  F: TIntProc;
begin
  F := GetHandler();
  F(3);
end;

procedure Overloads;
var
  P: TIntProc;
  Q: TStrProc;
begin
  GI := 0;
  GS := '';
  P := @Put;
  Q := @Put;
  P(5);
  Q('abc');
end;

begin
  Failures := 0;
  A := TCounter.Create;
  B := TCounter.Create;
  TwoObjects;       Check('two-objects', AB, 102);
  OneVariableTwice; Check('one-variable-twice', AB, 102);
  EventField;       Check('event-field', AB, 100);
  HandlerResult;    Check('handler-result', AB, 3);
  Overloads;        Check('overload-int', GI, 5);
                    Check('overload-str', Length(GS), 3);
  If Failures = 0 then
    WriteLn('FUNCREF_VALUE_SNAPSHOT_OBJFPC_OK')
  else begin
    WriteLn('FUNCREF_VALUE_SNAPSHOT_OBJFPC_FAILED ', Failures);
    Halt(1);
  end;
end.
