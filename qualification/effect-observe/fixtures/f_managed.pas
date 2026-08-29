unit f_managed;

{ Managed operations (negative pair 4): a managed-record assignment and a
  SetLength may transitively run user management operators - which here
  write a global and could just as well synchronize.  Until a passport
  exists every such operation is wide + sync + managed + trap. }

interface

type
  TMRec = record
    V: Integer;
    class operator Copy(constref Src: TMRec; var Dst: TMRec);
  end;

  TIA = array of Integer;

var
  GOps: Integer;

procedure ManagedAssign;
procedure GrowDyn;

implementation

class operator TMRec.Copy(constref Src: TMRec; var Dst: TMRec);
begin
  { the user operator observably mutates a global }
  GOps := GOps + 1;
  Dst.V := Src.V;
end;

// at the observe point the managed assignment is already lowered to an
// explicit call of the user Copy operator: the barrier arrives through the
// opaque-call classification (wide + sync + trap)
// EXPECT: proc=ManagedAssign ie=st reason=opaque_call
procedure ManagedAssign;
var
  a, b: TMRec;
begin
  a.V := 1;
  b := a;
  GOps := b.V;
end;

// SetLength is lowered to the fpc_dynarray_setlength compilerproc call with
// the array passed by var before the observe point: opaque barrier plus the
// explicit by-ref store
// EXPECT: proc=GrowDyn ie=st reason=opaque_call reason=byref_alias
procedure GrowDyn;
var
  A: TIA;
begin
  SetLength(A, 10);
  A[0] := 1;
end;

end.
