unit f_byref;

{ By-reference parameters: access through a caller-supplied reference may
  touch anything reachable except our exact locals (wide).  A const
  parameter passed by address is a live alias of caller storage and must be
  wide too (the frontend does not mark the const actual as address-taken). }

interface

type
  TBigRec = record
    A, B, C, D, E, F, G, H: Integer;
  end;

function ReadVia(var p: Integer): Integer;
procedure WriteVia(var p: Integer);
function ConstRecByRef(const r: TBigRec): Integer;
procedure TwoRefs(var a, b: Integer);
procedure AliasPair;

implementation

// EXPECT: proc=ReadVia r=EHGTP w=L ie=- reason=byref_alias
function ReadVia(var p: Integer): Integer;
begin
  Result := p;
end;

// EXPECT: proc=WriteVia r=- w=EHGTP ie=- reason=byref_alias
// EXPECT: proc=WriteVia rl=- wl=- sc=1 q=ok un=ok
procedure WriteVia(var p: Integer);
begin
  p := 1;
end;

// larger than both Win64's scalar aggregate limit and SysV's two-eightbyte
// register limit: the const parameter is passed by address on both targets
// EXPECT: proc=ConstRecByRef r=EHGTP w=L reason=byref_alias
function ConstRecByRef(const r: TBigRec): Integer;
begin
  Result := r.A + r.H;
end;

// negative pair 3 (by-ref alias): both writes must be wide - the model may
// never prove a and b disjoint
// EXPECT: proc=TwoRefs w=EHGTP reason=byref_alias
procedure TwoRefs(var a, b: Integer);
begin
  a := 1;
  b := 2;
end;

// the call site of the aliasing pair: var actuals journal byref_alias
// EXPECT: proc=AliasPair reason=byref_alias reason=opaque_call
procedure AliasPair;
var
  x: Integer;
begin
  TwoRefs(x, x);
end;

end.
