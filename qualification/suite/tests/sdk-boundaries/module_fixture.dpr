library module_fixture;

var MarkerCalls: Integer;

function LibraryMarker: Pointer; cdecl; noinline;
begin
  Result := get_pc_addr;
  Inc(MarkerCalls);
end;

exports LibraryMarker;
begin
end.
