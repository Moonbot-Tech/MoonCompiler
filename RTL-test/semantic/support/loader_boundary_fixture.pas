library loader_boundary_fixture;
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
function Answer: Integer; cdecl;
begin
  Result:=42;
end;
exports Answer;
begin
end.
