program funcref_value_var_param_rejected;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$ENDIF}
{ The object of a method given to "reference to" is read at every call, from
  the capturer, as by an anonymous method: a var parameter cannot be kept
  there.  Delphi 12.2: E2555 Cannot capture symbol 'C'. }
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

procedure FromVar(var C: TCounter);
var
  P: TIntProc;
begin
  P := C.Step;
  P(2);
end;

var
  G: TCounter;
begin
  G := TCounter.Create;
  FromVar(G);
end.
