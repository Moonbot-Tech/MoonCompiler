program tforstep14;

{ strength reduction must not treat a step loop as a unit-stride loop:
  compile with -O3 (loop strength reduction + pointer bump). Array writes
  indexed by a stepped counter have to land on the stepped elements }

{$mode unleashed}
{$Q-}{$R-}

var
  a : array[0..100] of integer;
  i, j, expected : integer;
  sum, check : int64;

begin
  for i:=0 to 100 do
    a[i]:=-1;

  { pointer-bump candidate: a[i] written under a stepped counter }
  for i:=0 to 100 step 7 do
    a[i]:=i;

  for i:=0 to 100 do
    begin
      if i mod 7=0 then
        expected:=i
      else
        expected:=-1;
      if a[i]<>expected then
        halt(1);
    end;

  { multiplication candidate: i*k inside a stepped loop }
  sum:=0;
  for i:=0 to 20 step 4 do
    sum:=sum+i*3;
  check:=0;
  j:=0;
  while j<=20 do
    begin
      check:=check+j*3;
      inc(j,4);
    end;
  if sum<>check then
    halt(2);

  { nested: plain inner loop inside a step loop keeps its own optimization }
  sum:=0;
  for i:=0 to 10 step 5 do
    for j:=0 to 3 do
      sum:=sum+a[j*7]+i;
  { a[0],a[7],a[14],a[21] = 0,7,14,21; inner sum per outer pass = 42+4*i }
  if sum<>(42+0)+(42+20)+(42+40) then
    halt(3);
end.
