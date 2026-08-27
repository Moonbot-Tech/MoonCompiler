program tforstep13;

{ cross-unit inlining of for-step bodies: without loopstep in the PPU the
  inlined loop silently degraded to step 1 }

{$mode unleashed}

uses
  uforstep13;

begin
  { 1+4+7+10 }
  if SumStep(1,10)<>22 then
    halt(1);
  { 250,252,254 - and the exit increment wraps without hanging }
  if CountBytesStep(2)<>3 then
    halt(2);
end.
