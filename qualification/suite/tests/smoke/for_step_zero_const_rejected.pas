program for_step_zero_const_rejected;

{ a constant step of zero is a parse-time diagnostic }

{$mode unleashed}

var
  i : integer;

begin
  for i:=1 to 10 step 0 do
    ;
end.
