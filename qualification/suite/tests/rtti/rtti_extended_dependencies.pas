unit rtti_extended_dependencies;

{$mode delphi}

interface

function CheckExtendedDependencies: Boolean;

implementation

uses
  rtti_generic_dependency_types;

function CheckExtendedDependencies: Boolean;
begin
  Result:=TouchExtendedDependency=0;
end;

end.
