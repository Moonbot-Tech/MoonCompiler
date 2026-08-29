unit f_local;

{ Exact locals: the only storage class with symbol identity.  The safe form
  must classify as pure L reads/writes with no instruction effects; the
  neighbouring dangerous form differs by one opaque call. }

interface

var
  GHit: Integer;

procedure Poke;
function AddLocals(a, b: Integer): Integer;
function AddLocalsClobber(a, b: Integer): Integer;

implementation

// EXPECT: proc=Poke r=G w=G ie=- temps=0 reason=global_memory
// EXPECT: proc=Poke rl=- wl=- sc=1 q=ok un=ok
procedure Poke;
begin
  GHit := GHit + 1;
end;

// the algebra line carries the exact facts a future consumer decides by:
// the named locals read/written, the self-conflict verdict (writes exist),
// and the public-query consistency checks
// EXPECT: proc=AddLocals r=L w=L ie=- temps=0 reasons=-
// EXPECT: proc=AddLocals rl=a,b,x,y wl=$result,x,y sc=1 q=ok un=ok
function AddLocals(a, b: Integer): Integer;
var
  x, y: Integer;
begin
  x := a + b;
  y := x * 2;
  Result := x + y;
end;

// negative pair 1 (call-clobber): one call turns the routine into a full
// barrier with wide reads and writes
// EXPECT: proc=AddLocalsClobber r=LEHGTP w=LEHGTP ie=st reason=opaque_call
function AddLocalsClobber(a, b: Integer): Integer;
var
  x: Integer;
begin
  x := a + b;
  Poke;
  Result := x + a;
end;

end.
