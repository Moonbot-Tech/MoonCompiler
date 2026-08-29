unit f_nested;

{ Nested routines: a local visible to a nested procedure lives in the
  parent-frame class for BOTH sides - the owner and the nested accessor -
  so cross-frame mutation is always a class conflict. }

interface

function Outer: Integer;

implementation

// the nested Inner is classified separately (see its own summary); the
// owner's accesses to the shared local leave the exact-local class
// EXPECT: proc=Outer w=LEHGTP ie=st reason=captured_or_outer_scope reason=opaque_call
// EXPECT: proc=Inner r=P w=P reason=captured_or_outer_scope
function Outer: Integer;
var
  x: Integer;

  procedure Inner;
  begin
    x := x + 1;
  end;

begin
  x := 0;
  Inner;
  Inner;
  Result := x;
end;

end.
