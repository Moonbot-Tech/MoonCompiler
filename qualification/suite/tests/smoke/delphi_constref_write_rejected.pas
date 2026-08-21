program delphi_constref_write_rejected;

{$mode delphiunicode}

procedure Mutate(const [ref] Value: Integer);
begin
  Value := 8;
end;

begin
end.
