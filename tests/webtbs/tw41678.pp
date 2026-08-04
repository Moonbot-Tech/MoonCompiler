{$mode delphi}
{$rangechecks off}

type
  tenum = (first, second, third);

const
  upper = tenum(10);

var
  value: tenum;
  count: longint;

begin
  count := 0;
  for value := low(tenum) to upper do
    inc(count);
  if count <> 11 then
    halt(1);

  count := 0;
  for value := low(tenum) to tenum(10) do
    inc(count);
  if count <> 11 then
    halt(2);

  count := 0;
  for value := low(tenum) to succ(high(tenum)) do
    inc(count);
  if count <> 4 then
    halt(3);

end.
