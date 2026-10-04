{ %fail }
{$mode delphiunicode}
var P: Pointer;
begin
  P := nil;
  { Ordinary pointers are not zero-terminated text. }
  WriteLn(P);
end.
