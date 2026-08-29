unit f_calls;

{ Calls without a summary are full barriers: wide reads and writes plus
  sync and trap, whatever the call shape - direct, indirect, virtual, or a
  call that mutates memory through a saved pointer. }

interface

type
  TProcVar = procedure;

  TVirt = class
  public
    procedure V; virtual;
  end;

var
  GCalls: Integer;
  GSaved: PInteger;

procedure WritesGlobal;
procedure WritesSavedPtr;
procedure CallDirect;
procedure CallIndirect(f: TProcVar);
procedure CallVirtual(o: TVirt);

implementation

procedure TVirt.V;
begin
  GCalls := GCalls + 1;
end;

// EXPECT: proc=WritesGlobal w=G reason=global_memory
procedure WritesGlobal;
begin
  GCalls := GCalls + 1;
end;

// EXPECT: proc=WritesSavedPtr w=EHGTP ie=t reason=pointer_alias
procedure WritesSavedPtr;
begin
  GSaved^ := 7;
end;

// EXPECT: proc=CallDirect r=EHGTP w=EHGTP ie=st reason=opaque_call
procedure CallDirect;
begin
  WritesGlobal;
end;

// EXPECT: proc=CallIndirect r=LEHGTP w=EHGTP ie=st reason=opaque_call
procedure CallIndirect(f: TProcVar);
begin
  f();
end;

// EXPECT: proc=CallVirtual r=LEHGTP w=EHGTP ie=st reason=opaque_call
procedure CallVirtual(o: TVirt);
begin
  o.V;
end;

end.
