{ %fail }
{$mode delphiunicode}
var P: PWideChar;
begin
  { Output support does not turn a pointer into writable string storage. }
  ReadLn(P);
end.
