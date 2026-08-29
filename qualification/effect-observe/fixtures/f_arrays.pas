unit f_arrays;

{ Array elements.  Static array elements are the base symbol's own storage.
  Dynamic array elements live in the heap payload class; an element STORE
  reads but never writes the descriptor (Delphi dynamic arrays are not COW,
  axiom A17) - the positive counterpart of the string COW hole. }

interface

type
  TIA = array of Integer;
  TSA = array[0..7] of Integer;

function StaticElem(i: Integer): Integer;
procedure DynElemWrite(A: TIA);
function DynElemRead(A: TIA): Integer;
function DynLen(A: TIA): Integer;
function CheckedElem(const A: TSA; i: Integer): Integer;

implementation

// EXPECT: proc=StaticElem r=L w=L ie=- reasons=-
function StaticElem(i: Integer): Integer;
var
  A: TSA;
begin
  A[i and 7] := i;
  Result := A[0];
end;

// dynarray element store: payload write + descriptor READ only - w must be
// exactly H (no local write of the descriptor, no string_cow); the implicit
// nil-descriptor trap is counted in the statistics without a per-node remark
// EXPECT: proc=DynElemWrite r=L w=H ie=t reasons=may_trap:1
// EXPECT-NOT: proc=DynElemWrite reason=string_cow
procedure DynElemWrite(A: TIA);
begin
  A[0] := 1;
end;

// EXPECT: proc=DynElemRead r=LH w=L ie=t reasons=may_trap:1
function DynElemRead(A: TIA): Integer;
begin
  Result := A[0];
end;

// the length of a heap container is stored in the heap block HEADER: the
// read touches escaped memory (E), so a pointer write (wide, contains E)
// conflicts with it - the dangerous neighbour is DerefWrite in f_pointer
// EXPECT: proc=DynLen r=LE w=L ie=- reasons=-
function DynLen(A: TIA): Integer;
begin
  Result := Length(A);
end;

{$R+}
// EXPECT: proc=CheckedElem ie=t reason=may_trap
function CheckedElem(const A: TSA; i: Integer): Integer;
begin
  Result := A[i];
end;
{$R-}

end.
