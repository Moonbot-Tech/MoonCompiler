program method_value_receivers_objfpc;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}{$modeswitch typehelpers}
{ The FPC form of a method pointer to a method of a value, with @
  (M := @R.Step): the same pointer as R.Step in mode Delphi (Delphi has no
  @ of a method, E2036) - Self is the address of the value, which a call
  through the pointer changes (tests/smoke/method_value_receivers.pas) }

type
  TMethodProc = procedure(Step: Integer) of object;
  TRec4 = record V: Integer; procedure Step(A: Integer); end;
  TRec8 = record V: Int64; procedure Step(A: Integer); end;
  TIntHelper = type helper for Integer procedure Bump(A: Integer); end;

var
  Last: Int64;
  Failures: Integer;

procedure TRec4.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TRec8.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TIntHelper.Bump(A: Integer); begin Self := Self + A; end;

function MakeRec(V: Integer): TRec4; begin Result.V := V; end;

procedure Check(const Name: string; Got, Expected: Int64);
begin
  if Got <> Expected then
  begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Expected);
    Inc(Failures);
  end;
end;

procedure Local4; var R: TRec4; M: TMethodProc;
begin R.V := 1; M := @R.Step; M(2); Check('local4', R.V, 3); end;

procedure Local8; var R: TRec8; M: TMethodProc;
begin R.V := 1; M := @R.Step; M(2); Check('local8', R.V, 3); end;

procedure IntegerHelper; var I: Integer; M: TMethodProc;
begin I := 1; M := @I.Bump; M(2); Check('integer-helper', I, 3); end;

procedure FunctionResult; var M: TMethodProc;
begin M := @MakeRec(1).Step; M(2); M(3); Check('function-result', Last, 6); end;

var
  G4: TRec4;
  G8: TRec8;
  M4, M8: TMethodProc;
begin
  Failures := 0;
  Local4; Local8; IntegerHelper; FunctionResult;
  G4.V := 1; M4 := @G4.Step; M4(2); Check('main4', G4.V, 3);
  G8.V := 1; M8 := @G8.Step; M8(2); Check('main8', G8.V, 3);
  if Failures = 0 then
    WriteLn('METHOD_VALUE_RECEIVERS_OBJFPC_OK')
  else begin
    WriteLn('METHOD_VALUE_RECEIVERS_OBJFPC_FAILED ', Failures);
    Halt(1);
  end;
end.
