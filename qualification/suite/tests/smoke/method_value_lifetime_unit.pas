unit method_value_lifetime_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch inlinevars}{$ENDIF}
{ When the value a method pointer points into is finalized when it is no
  variable (tests/smoke/method_value_lifetime.pas): a record with an
  interface field whose object counts its destruction. The initialization
  of this unit takes such a pointer, whose value lives with the variables of
  the unit, and has an inline variable of its own; the finalization runs
  after the main block of the program, which finalized its value when it
  ended, and before the value of the initialization is finalized. }

interface

type
  TMethodProc = procedure(Step: Integer) of object;
  TTracked = class(TInterfacedObject)
  public
    destructor Destroy; override;
  end;
  TRecI = record
    I: IInterface;
    V: Integer;
    procedure Step(A: Integer);
  end;

var
  Destroyed, Failures, Last: Integer;

function MakeRecI(V: Integer): TRecI;
procedure Check(const Name: string; Got, Expected: Integer);

implementation

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

procedure TRecI.Step(A: Integer);
begin
  Inc(V, A);
  Last := V;
end;

function MakeRecI(V: Integer): TRecI;
begin
  Result.I := TTracked.Create;
  Result.V := V;
end;

procedure Check(const Name: string; Got, Expected: Integer);
begin
  If Got <> Expected then
  begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Expected);
    Inc(Failures);
  end;
end;

var
  M: TMethodProc;

initialization
  M := MakeRecI(1).Step;
  M(2);
  Check('initialization-alive', Destroyed * 10 + Last, 3);
  begin
    var I: IInterface := TTracked.Create;
    Check('initialization-inline-alive', Destroyed, 0);
  end;

finalization
  { the main block has ended, and with it its value }
  Check('main-block-finalized', Destroyed, 6);
  { the value of the initialization lives with the variables of the unit }
  M(1);
  Check('initialization-alive-in-finalization', Destroyed * 10 + Last, 64);
  If Failures = 0 then
    WriteLn('METHOD_VALUE_LIFETIME_OK')
  else begin
    WriteLn('METHOD_VALUE_LIFETIME_FAILED ', Failures);
    ExitCode := 1;
  end;
end.
