program tforstep9;

{ physical-domain contract: steps that meet or exceed the counter's width
  must terminate with the modular first-past value, never hang }

{$mode unleashed}
{$Q-}{$R-}

{$PACKENUM 1}
type
  TE = (te0);
{$PACKENUM DEFAULT}

var
  b : byte;
  w : word;
  s : shortint;
  q : int64;
  uq : qword;
  e : TE;
  count : integer;

begin
  { step equal to the Byte width: one pass, wrap-to-self }
  count:=0;
  for b:=0 to 10 step 256 do
    inc(count);
  if count<>1 then
    halt(1);
  if b<>0 then
    halt(2);

  { step above the width: modular first-past value }
  count:=0;
  for b:=0 to 10 step 257 do
    inc(count);
  if count<>1 then
    halt(3);
  if b<>1 then
    halt(4);

  { twice the width }
  count:=0;
  for b:=0 to 10 step 512 do
    inc(count);
  if count<>1 then
    halt(5);
  if b<>0 then
    halt(6);

  { the last increment wraps past the physical maximum }
  count:=0;
  for b:=250 to 255 step 2 do
    inc(count);
  if count<>3 then
    halt(7);
  if b<>0 then
    halt(8);

  { Word width }
  count:=0;
  for w:=0 to 100 step 65536 do
    inc(count);
  if count<>1 then
    halt(9);
  if w<>0 then
    halt(10);

  count:=0;
  for w:=65530 to 65535 step 3 do
    inc(count);
  if count<>2 then
    halt(11);
  if w<>0 then
    halt(12);

  { signed counter: exit wraps into the negative half }
  count:=0;
  for s:=-100 to 100 step 50 do
    inc(count);
  if count<>5 then
    halt(13);
  if s<>-106 then
    halt(14);

  { full-width Int64 counter near the physical maximum }
  count:=0;
  for q:=high(int64)-10 to high(int64) step 4 do
    inc(count);
  if count<>3 then
    halt(15);
  if q<>low(int64)+1 then
    halt(16);

  { full-width QWord counter across the physical maximum }
  count:=0;
  for uq:=high(qword)-6 to high(qword) step 3 do
    inc(count);
  if count<>3 then
    halt(17);
  if uq<>2 then
    halt(18);

  { enum counter under $R-: physical domain, not the declared range }
  count:=0;
  for e:=TE(250) to TE(255) step 3 do
    inc(count);
  if count<>2 then
    halt(19);
  if ord(e)<>0 then
    halt(20);

  { backward wrap below the physical minimum }
  count:=0;
  for b:=5 downto 0 step 4 do
    inc(count);
  if count<>2 then
    halt(21);
  if b<>253 then
    halt(22);
end.
