program unit_scope_own_probe;

{ A program that brings its own units named ZLib and Zip (unit_scope_gate.py
  writes them beside the program, into a directory of a -Fu of the command
  line, or into one of its project options file).  Delphi 12.2 takes a unit
  by the name as written before it tries the unit scopes, so these are the
  units the program gets; the aliases of the product configuration
  (-UaZLib=System.ZLib) step over only the toolchain's own units of these
  names.  ProjectZLibMarker and ProjectZipMarker exist in no other unit. }

uses
  zLib,
  Zip;

begin
  WriteLn('UNIT_SCOPE_OWN_PASS zlib=', ProjectZLibMarker, ' zip=', ProjectZipMarker);
end.
