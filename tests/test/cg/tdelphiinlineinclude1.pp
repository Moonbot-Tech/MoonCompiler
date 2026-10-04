program tdelphiinlineinclude1;

{$mode unleashed}

var
  Sum: Integer;
begin
  Sum:=0;
{$I tdelphiinlineinclude1a.inc}
{$I tdelphiinlineinclude1b.inc}
{$I tdelphiinlineinclude1a.inc}
  if Sum<>44 then
    Halt(1);
end.
