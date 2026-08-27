program tforstep15;

{ 128-bit counters and steps go through the same distance lowering on the
  int128 helpers: forward, downto, physical wrap and mixed widths }

{$mode unleashed}
{$Q-}{$R-}

var
  u : UInt128;
  s : Int128;
  b : byte;
  count : integer;
  bigstep : UInt128;

begin
  { plain forward stepping in the 128-bit domain }
  count:=0;
  for u:=0 to 100 step 7 do
    inc(count);
  if count<>15 then
    halt(1);
  if u<>105 then
    halt(2);

  { signed 128-bit counter across zero }
  count:=0;
  for s:=-100 to 100 step 50 do
    inc(count);
  if count<>5 then
    halt(3);
  if s<>150 then
    halt(4);

  { the exit increment wraps past the 128-bit physical maximum }
  count:=0;
  for u:=high(UInt128)-6 to high(UInt128) step 3 do
    inc(count);
  if count<>3 then
    halt(5);
  if u<>2 then
    halt(6);

  { downto below the physical minimum }
  count:=0;
  for u:=5 downto 0 step 4 do
    inc(count);
  if count<>2 then
    halt(7);
  if u<>high(UInt128)-2 then
    halt(8);

  { a 128-bit step against a byte counter is not truncated }
  bigstep:=UInt128(1) shl 100;
  count:=0;
  for b:=0 to 10 step bigstep do
    inc(count);
  if count<>1 then
    halt(9);
  if b<>0 then
    halt(10);
end.
