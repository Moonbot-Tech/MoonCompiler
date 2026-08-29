unit f_global;

{ Globals and threadvars: classified precisely as G/T, but journaled as
  refusals - the public memory contract forbids caching them across loop
  iterations, so a future LICM must see the reason. }

interface

var
  GVar: Integer;

threadvar
  TVar: Integer;

function ReadGlobal: Integer;
procedure WriteGlobal(v: Integer);
function ReadThreadVar: Integer;
procedure BumpRef(var p: Integer);
procedure PassGlobalByRef;

implementation

// EXPECT: proc=ReadGlobal r=G w=L ie=- reason=global_memory
function ReadGlobal: Integer;
begin
  Result := GVar;
end;

// EXPECT: proc=WriteGlobal r=L w=G ie=- reason=global_memory
procedure WriteGlobal(v: Integer);
begin
  GVar := v;
end;

// EXPECT: proc=ReadThreadVar r=T w=L ie=- reason=threadvar_memory
function ReadThreadVar: Integer;
begin
  Result := TVar;
end;

// EXPECT: proc=BumpRef reason=byref_alias
procedure BumpRef(var p: Integer);
begin
  p := p + 1;
end;

// a global passed by var: the callee write lands in G (explicit store
// through the actual) on top of the opaque call barrier
// EXPECT: proc=PassGlobalByRef w=EHGTP ie=st reason=byref_alias reason=global_memory reason=opaque_call
procedure PassGlobalByRef;
begin
  BumpRef(GVar);
end;

end.
