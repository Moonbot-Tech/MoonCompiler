unit f_volatile;

{ Volatile and atomic accesses: every access executes and orders - ie_sync
  is a full barrier for any future consumer. }

interface

var
  GVol: Integer;
  GCnt: Integer;

function VolRead: Integer;
procedure AtomicForm;

implementation

// EXPECT: proc=VolRead ie=s reason=volatile_or_atomic
function VolRead: Integer;
begin
  Result := Volatile(GVol);
end;

// EXPECT: proc=AtomicForm ie=st reason=volatile_or_atomic
procedure AtomicForm;
begin
  AtomicIncrement(GCnt);
end;

end.
