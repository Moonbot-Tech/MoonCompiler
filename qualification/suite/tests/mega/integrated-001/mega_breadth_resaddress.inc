{ Equal-named resources in the program and a compiled unit retain their own counted text. }

resourcestring
  BreadthStatusResource = 'main'#0'resource';

procedure RunBreadthResourceAddress;
var
  MainText, UnitText: UnicodeString;
begin
  MainText := UnicodeString(LoadResString(@BreadthStatusResource));
  UnitText := BreadthReadUnitResource;
  Check(MainText = 'main'#0'resource', 'breadth-resource-address-loads-counted-program-entry');
  Check(UnitText = 'unit'#0'resource', 'breadth-resource-address-loads-distinct-entry-from-compiled-unit');
end;
