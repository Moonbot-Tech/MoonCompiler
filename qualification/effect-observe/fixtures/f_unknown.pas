unit f_unknown;

{ Closure of the walker.  The x86 pause intrinsic reaches the observe point
  as an inline node without a whitelist entry: it must fall into the
  conservative default - reads and writes everything with every instruction
  effect.  An absolute variable over a raw address exercises the
  unresolvable-overlay fallback of the classifier.  The Slice form documents
  canonicalization: the intrinsic is rewritten into plain call machinery
  before the observe point. }

interface

type
  TSA = array[0..7] of Integer;

function ShortConcat(c: Char): ShortString;
procedure PauseForm;
function AbsAddr: Integer;
procedure TakeOpen(const a: array of Integer);
procedure SliceForm(var A: TSA);

implementation

// shortstring concatenation lowers to managed RTL helpers
// EXPECT: proc=ShortConcat ie=smt reason=managed_operation
function ShortConcat(c: Char): ShortString;
var
  s: ShortString;
begin
  s := 'a';
  s := s + c;
  Result := s;
end;

// a cpu-specific intrinsic the model has not studied: conservative closure
// EXPECT: proc=PauseForm r=L!EHGTP w=L!EHGTP ie=smt reason=unknown_node
// EXPECT: proc=PauseForm sc=1 q=ok un=ok
procedure PauseForm;
begin
  fpc_x86_pause;
end;

// absolute over a raw address: no target symbol to resolve - wide with the
// alias reason
// EXPECT: proc=AbsAddr r=EHGTP reason=pointer_alias
function AbsAddr: Integer;
var
  Port: Integer absolute $2000;
begin
  Result := Port;
end;

// High(open array) reads the hidden bound parameter - an exact local; a
// pure reader without writes, barriers or temps does not conflict with
// itself
// EXPECT: proc=TakeOpen r=L ie=- reasons=-
// EXPECT: proc=TakeOpen rl=$highA wl=- sc=0 q=ok un=ok
procedure TakeOpen(const a: array of Integer);
begin
  if High(a) > 0 then;
end;

// Slice is rewritten into open-array call machinery before the observe
// point; the barrier of the call remains
// EXPECT: proc=SliceForm ie=st reason=opaque_call
procedure SliceForm(var A: TSA);
begin
  TakeOpen(Slice(A, 2));
end;

end.
