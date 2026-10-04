unit f_temp_record;

{$mode objfpc}

{ The ObjFPC record-with path saves a complex addressable base in a
  compiler pointer temp. A store through it cannot be an exact local store. }

interface

type
  TRec = record
    F: Integer;
  end;
  PRec = ^TRec;

procedure PointerWithTemp;

implementation

var
  GR: TRec;

function GetRec: PRec; noinline;
begin
  Result := @GR;
end;

// EXPECT: proc=PointerWithTemp r=EHGTP w=EHGTP ie=st temps=1 reason=compiler_temp reason=opaque_call
// EXPECT: proc=PointerWithTemp rl=- wl=- sc=1 q=ok un=ok
procedure PointerWithTemp;
begin
  with GetRec^ do
    F := 1;
end;

end.
