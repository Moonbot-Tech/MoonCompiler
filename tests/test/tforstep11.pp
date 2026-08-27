program tforstep11;

{ continue and break reach the step latch through try/finally unwinding:
  every finally block runs, the counter keeps stepping, no endless loop }

{$mode unleashed}

var
  i, bodies, finals, sum : integer;

begin
  { continue from inside try/finally: the finally must run and the loop
    must advance to the next stepped value }
  bodies:=0;
  finals:=0;
  sum:=0;
  for i:=1 to 21 step 5 do
    begin
      inc(bodies);
      try
        if (i=6) or (i=16) then
          continue;
        sum:=sum+i;
      finally
        inc(finals);
      end;
    end;
  { body sees 1,6,11,16,21; sum skips 6 and 16 }
  if bodies<>5 then
    halt(1);
  if finals<>5 then
    halt(2);
  if sum<>1+11+21 then
    halt(3);
  if i<>26 then
    halt(4);

  { break from inside try/finally: finally runs, counter keeps the exact
    break-time value }
  bodies:=0;
  finals:=0;
  for i:=1 to 21 step 5 do
    begin
      inc(bodies);
      try
        if i=11 then
          break;
      finally
        inc(finals);
      end;
    end;
  if bodies<>3 then
    halt(5);
  if finals<>3 then
    halt(6);
  if i<>11 then
    halt(7);

  { nested for-step loops with continue in both }
  sum:=0;
  for i:=0 to 20 step 10 do
    begin
      if i=10 then
        continue;
      for var j:=0 to 6 step 3 do
        begin
          if j=3 then
            continue;
          sum:=sum+i+j;
        end;
    end;
  { outer i in 0,20; inner j in 0,6 -> (0+0)+(0+6)+(20+0)+(20+6) }
  if sum<>52 then
    halt(8);
end.
