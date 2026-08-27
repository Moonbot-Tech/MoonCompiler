unit uforstep13;

{ inline routines with for-step bodies: the loopstep tree must survive the
  PPU round trip of the inline info (compile this unit separately, then the
  program, so inlining really reads the PPU) }

{$mode unleashed}

interface

function SumStep(lo,hi : integer) : integer; inline;
function CountBytesStep(step : integer) : integer; inline;

implementation

function SumStep(lo,hi : integer) : integer;
var
  i : integer;
begin
  result:=0;
  for i:=lo to hi step 3 do
    result:=result+i;
end;

function CountBytesStep(step : integer) : integer;
var
  b : byte;
begin
  result:=0;
  for b:=250 to 255 step step do
    inc(result);
end;

end.
