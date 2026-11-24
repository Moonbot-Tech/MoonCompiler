{ repeat Continue enters the condition after finally, while Break and raising bypass it. }

function BreadthObserveRepeat(const Finalized: AnsiString; var Tested: AnsiString; Step: Integer): Boolean;
begin
  Tested := Tested + Copy(Finalized, Length(Finalized), 1);
  Result := Step = 4;
end;

procedure BreadthRepeatEdges(Mode: Integer; out Finalized, Tested: AnsiString; out Total: Integer);
var
  Step: Integer;
begin
  Step := 0;
  Total := 0;
  repeat
    Inc(Step);
    try
      If Step = 2 then
        Continue;
      If (Step = 3) and (Mode = 2) then
        raise EAbort.Create('repeat body stopped');
      If ((Step = 3) and (Mode = 1)) or (Step = 5) then
        Break;
      Inc(Total, Step);
    finally
      Finalized := Finalized + AnsiChar(Ord('a') + Step - 1);
    end;
  until BreadthObserveRepeat(Finalized, Tested, Step);
end;

procedure RunBreadthRepeatEdges;
const
  FinalTrails: array[0..2] of AnsiString = ('abcd', 'abc', 'abc');
  TestTrails: array[0..2] of AnsiString = ('abcd', 'ab', 'ab');
  Totals: array[0..2] of Integer = (8, 1, 1);
var
  Mode, Total: Integer;
  Finalized, Tested: AnsiString;
  Caught: Boolean;
begin
  for Mode := Low(Totals) to High(Totals) do begin
    Caught := False;
    try
      BreadthRepeatEdges(Integer(OpaqueI(Mode)), Finalized, Tested, Total);
    except
      on E: EAbort do Caught := E.Message = 'repeat body stopped';
    end;
    Check((Caught = (Mode = 2)) and (Total = Totals[Mode]), 'breadth-repeat-body-visits-and-exception');
    Check(Finalized = FinalTrails[Mode], 'breadth-repeat-finally-runs-on-all-exit-edges');
    Check(Tested = TestTrails[Mode], 'breadth-repeat-condition-sees-finally-and-skips-broken-iteration');
    Mix(UInt64(Total * 16 + Length(Tested)));
  end;
end;
