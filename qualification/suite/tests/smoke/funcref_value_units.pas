program funcref_value_units;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ A method given to "reference to" without @ where units meet.  A method of
  a class of another unit, given in a unit or in the program, did not link:
  the interface of the reference was put into the class of the other unit,
  compiled already, which never emits it.  A method of a class of a unit's
  interface, given in the unit's initialization, stopped the compiler while
  it wrote the unit (internal error 2019022201).  In the main block and in
  the initialization of a unit -O2 keeps a variable nothing else reads in a
  register, and the Invoke read the object from memory the register never
  reached.  One source for Delphi 12.2 and MoonCompiler: every expected
  number is Delphi's. }
uses
  funcref_value_units_class_unit, funcref_value_units_user_unit;

var
  A, B, C: TCounter;
  MP: TMethodProc;
  P, Q, F: TIntProc;
{$IFDEF FPC}
  PS: TStrProc;
{$ENDIF}
  Failures: Integer;

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': got ', Got, ', Delphi gives ', Want);
    Inc(Failures);
  end;
end;

begin
  Failures := 0;
  Check('unit-initialization', InitResult, 1);
  A := TCounter.Create;
  B := TCounter.Create;
  Check('other-unit', RunUser(A, B), 110);
  Check('other-unit-overloads', PutTotal, 3005);
  A.Count := 0;
  B.Count := 0;
  C := A;
  P := C.Step;
  C := B;
  Q := C.Step;
  P(1);
  Q(10);
  Check('main-block-object', A.Count * 100 + B.Count, 11);
  A.Count := 0;
  B.Count := 0;
  MP := A.Step;
  F := MP;
  MP := B.Step;
  F(1);
  Check('main-block-variable', A.Count * 100 + B.Count, 1);
{$IFDEF FPC}
  { Delphi 12.2 does not choose among overloaded methods for a reference
    (E2010 against the first overload); FPC does }
  A.Count := 0;
  P := A.Put;
  PS := A.Put;
  P(2);
  PS('xy');
  Check('other-unit-method-overloads', A.Count, 2002);
{$ENDIF}
  P := nil;
  Q := nil;
  F := nil;
  A.Free;
  B.Free;
  If Failures = 0 then
    WriteLn('FUNCREF_VALUE_UNITS_OK')
  else begin
    WriteLn('FUNCREF_VALUE_UNITS_FAILED ', Failures);
    Halt(1);
  end;
end.
