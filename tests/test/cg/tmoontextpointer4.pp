{ %fail }
{$mode delphiunicode}
begin
  { The second formatting qualifier is still restricted to real values. }
  WriteLn(PWideChar('abc'):5:2);
end.
