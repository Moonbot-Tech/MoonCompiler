{ Evaluation mode controls whether a checked load or arithmetic can raise. }

type
  TBreadthGuardedRead = function(const Cells: array of Int64; Enabled: Boolean; Index: Integer; Ceiling: Int64): Boolean;

{$B-}{$Q+}{$R+}
function BreadthCheckedLazy(const Cells: array of Int64; Enabled: Boolean; Index: Integer; Ceiling: Int64): Boolean;
begin
  Result := Enabled and (Index >= Low(Cells)) and (Index <= High(Cells)) and (Cells[Index] + 1 <= Ceiling);
end;

{$B+}
function BreadthCheckedEager(const Cells: array of Int64; Enabled: Boolean; Index: Integer; Ceiling: Int64): Boolean;
begin
  Result := Enabled and (Index >= Low(Cells)) and (Index <= High(Cells)) and (Cells[Index] + 1 <= Ceiling);
end;
{$B-}{$Q-}{$R-}

procedure RunBreadthEvaluationGuards;
const
  Indices: array[0..3] of Integer = (0, -1, 1, 1);
  Enabled: array[0..3] of Boolean = (False, True, True, True);
  Ceilings: array[0..3] of Int64 = (7, 7, 32, 30);
  Guarded: array[0..3] of Integer = (0, 0, 1, 0);
  Eager: array[0..3] of Integer = (2, 3, 1, 0);
var
  Cells: array[-5..-4] of Int64;
  Evaluate: TBreadthGuardedRead;
  CaseIndex, Mode, Actual: Integer;
begin
  Cells[-5] := OpaqueI(High(Int64));
  Cells[-4] := OpaqueI(31);
  for Mode := 0 to 1 do begin
    If Mode = 0 then
      Evaluate := BreadthCheckedLazy
    else
      Evaluate := BreadthCheckedEager;
    for CaseIndex := Low(Indices) to High(Indices) do begin
      try
        Actual := Ord(Evaluate(Cells, Enabled[CaseIndex], Integer(OpaqueI(Indices[CaseIndex])), OpaqueI(Ceilings[CaseIndex])));
      except
        on EIntOverflow do Actual := 2;
        on ERangeError do Actual := 3;
      end;
      If Mode = 0 then
        Check(Actual = Guarded[CaseIndex], 'breadth-short-circuit-guards-checked-operations')
      else
        Check(Actual = Eager[CaseIndex], 'breadth-complete-evaluation-runs-checked-operations');
      Mix(UInt64(Actual));
    end;
  end;
end;
