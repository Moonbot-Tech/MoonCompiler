program for_step_negative_const_rejected;

{ a negative constant step is a parse-time diagnostic }

{$mode unleashed}

var
  i : integer;

begin
  for i:=10 downto 1 step -2 do
    ;
end.
