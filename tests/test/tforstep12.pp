program tforstep12;

{ the loop's own stepping arithmetic is modular by contract and must not
  trip overflow or range checking, even when the exit increment wraps the
  counter's physical domain; user code inside the body stays checked }

{$mode unleashed}
{$Q+}{$R+}

var
  b : byte;
  q : int64;
  count : integer;

begin
  { the exit increment wraps 254 -> 0: no overflow/range error }
  count:=0;
  for b:=250 to 255 step 2 do
    inc(count);
  if count<>3 then
    halt(1);
  if b<>0 then
    halt(2);

  { full-width signed counter wrapping past High(Int64) }
  count:=0;
  for q:=high(int64)-10 to high(int64) step 4 do
    inc(count);
  if count<>3 then
    halt(3);
  if q<>low(int64)+1 then
    halt(4);

  { a step wider than the counter is not truncated under checks either }
  count:=0;
  for b:=0 to 10 step 256 do
    inc(count);
  if count<>1 then
    halt(5);
  if b<>0 then
    halt(6);
end.
