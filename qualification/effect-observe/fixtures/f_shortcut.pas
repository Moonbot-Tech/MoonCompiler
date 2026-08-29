unit f_shortcut;

{ Shortcut evaluation: the right branch may not execute, but its MAY-effects
  belong to the union - a trap or an alias in the conditional branch must be
  visible in the aggregate (availability is the consumer's path problem,
  never a reason to shrink the effect). }

interface

function ShortcutDeref(p: PInteger): Boolean;
function ShortcutCall(x: Integer): Boolean;

implementation

function Check(v: Integer): Boolean;
begin
  Result := v > 0;
end;

// EXPECT: proc=ShortcutDeref ie=t reason=pointer_alias
function ShortcutDeref(p: PInteger): Boolean;
begin
  Result := (p <> nil) and (p^ = 5);
end;

// EXPECT: proc=ShortcutCall ie=st reason=opaque_call
function ShortcutCall(x: Integer): Boolean;
begin
  Result := (x <> 0) or Check(x);
end;

end.
