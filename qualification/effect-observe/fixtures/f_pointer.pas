unit f_pointer;

{ Pointer dereference and escaped locals (negative pair 2): a write through
  any pointer is wide, and a local whose address was taken leaves the exact
  ac_local class forever. }

interface

function DerefRead(p: PInteger): Integer;
procedure DerefWrite(p: PInteger);
function EscapedLocal: Integer;

implementation

// EXPECT: proc=DerefRead r=LEHGTP w=L ie=t reason=pointer_alias
function DerefRead(p: PInteger): Integer;
begin
  Result := p^;
end;

// pointer-alias pair: the write through p must be wide - the model may
// never keep a cached read alive across it
// EXPECT: proc=DerefWrite r=L w=EHGTP ie=t reason=pointer_alias
procedure DerefWrite(p: PInteger);
begin
  p^ := 5;
end;

// EXPECT: proc=EscapedLocal r=LEHGTP w=LE ie=t reason=pointer_alias
function EscapedLocal: Integer;
var
  x: Integer;
  p: PInteger;
begin
  p := @x;
  x := 5;
  Result := x + p^;
end;

end.
