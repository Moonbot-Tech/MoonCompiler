program host_fields;

{ A class of the host with a published field whose class lives in a package,
  and no other reference to that class. The field class table is data that
  names the package's VMT; nothing in the code refers to it, so the package
  import pass used to miss it and the link failed with
  VMT_$BASEUNIT_$$_TBASE$indirect undefined. }

{$mode delphi}

uses
  { named so that the host links CommonPkg; the code never uses it }
  BaseUnit,
  HolderUnit;

var
  H: THolder;
begin
  H := THolder.Create;
  if H.FieldAddress('Item') = nil then
  begin
    WriteLn('published field not found');
    Halt(1);
  end;
  WriteLn('host_fields ok');
  H.Free;
end.
