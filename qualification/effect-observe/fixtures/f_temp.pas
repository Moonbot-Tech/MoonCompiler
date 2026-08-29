unit f_temp;

{ Compiler temporaries (Pascal-check hole 2): v1 has no identity carrier for
  temps, so a temp-carrying tree must be flagged (temps=1) and a write
  through a temp base is wide. }

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

// with on a call result stores the reference in a compiler temp: the
// field write goes through the temp base
// EXPECT: proc=WithTemp temps=1 reason=compiler_temp reason=opaque_call
procedure WithTemp;
begin
  with GetObj do
    F := 1;
end;

end.
