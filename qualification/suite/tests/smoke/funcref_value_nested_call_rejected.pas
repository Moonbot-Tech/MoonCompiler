program funcref_value_nested_call_rejected;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ The object is the result of a nested function: the Invoke that evaluates it
  at every call has no frame of the routine the nested function belongs to.
  Delphi 12.2: E2555 Cannot capture symbol 'GetC'; an anonymous method calling
  GetC is refused the same way. }
type
  TIntProc = reference to procedure(Step: Integer);

  TCounter = class
    Count: Integer;
    procedure Step(Amount: Integer);
  end;

procedure TCounter.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure Run;
var
  C: TCounter;
  P: TIntProc;

  function GetC: TCounter;
  begin
    Result := C;
  end;

begin
  C := TCounter.Create;
  P := GetC.Step;
  P(2);
end;

begin
  Run;
end.
