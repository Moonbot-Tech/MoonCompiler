unit f_temp;

{ Class-with materialization uses an exact lexical local. The referenced
  object field and the opaque producer still have wide effects. Actual
  temprefn coverage lives in f_temp_record. }

interface

type
  TObj2 = class
  public
    F: Integer;
  end;

function GetObj: TObj2;
procedure WithTemp;

implementation

var
  GO: TObj2;

// EXPECT: proc=GetObj reason=global_memory
function GetObj: TObj2;
begin
  Result := GO;
end;

// the frontend creates a lexical $with_value local for the call result,
// preserving its identity without disguising the object field as local
// EXPECT: proc=WithTemp r=LEHGTP w=LEHGTP ie=st temps=0 reason=opaque_call
// EXPECT-NOT: proc=WithTemp reason=compiler_temp
procedure WithTemp;
begin
  with GetObj do
    F := 1;
end;

end.
