{ Only an enabled Assert evaluates its operand or enters assertion exception handling. }

function BreadthObserveAssert(var Probes: Integer; Accept: Boolean): Boolean;
begin
  Inc(Probes);
  Result := Accept;
end;

{$ifopt C+}
  {$define BREADTH_ASSERTS_WERE_ON}
{$endif}
{$C+}
procedure BreadthEnabledAssert(var Probes: Integer; Accept: Boolean);
begin
  Assert(BreadthObserveAssert(Probes, Accept), 'breadth assertion marker');
end;

{$C-}
procedure BreadthDisabledAssert(var Probes: Integer; Accept: Boolean);
begin
  Assert(BreadthObserveAssert(Probes, Accept), 'breadth assertion marker');
end;
{$ifdef BREADTH_ASSERTS_WERE_ON}
  {$C+}
  {$undef BREADTH_ASSERTS_WERE_ON}
{$endif}

procedure RunBreadthAssertionControl;
type
  TAssertAction = procedure(var Probes: Integer; Accept: Boolean);
var
  Action: TAssertAction;
  Enabled, Accept, Caught: Boolean;
  Probes, Finalizers: Integer;
begin
  Probes := 0;
  Finalizers := 0;
  for Enabled := False to True do begin
    If Enabled then
      Action := BreadthEnabledAssert
    else
      Action := BreadthDisabledAssert;
    for Accept := False to True do begin
      Caught := False;
      try
        try
          Action(Probes, Accept);
        finally
          Inc(Finalizers);
        end;
      except
        on E: EAssertionFailed do Caught := Pos('breadth assertion marker', E.Message) > 0;
      end;
      Check(Caught = (Enabled and not Accept), 'breadth-assert-switch-enables-only-expected-exception');
      If Enabled then
        Check(Probes = 1 + Ord(Accept), 'breadth-assert-enabled-probes-exactly-once')
      else
        Check(Probes = 0, 'breadth-assert-disabled-removes-operand-side-effects');
    end;
  end;
  Check(Finalizers = 4, 'breadth-assert-unwind-runs-caller-finally');
  Mix(UInt64(Probes * 10 + Finalizers));
end;
