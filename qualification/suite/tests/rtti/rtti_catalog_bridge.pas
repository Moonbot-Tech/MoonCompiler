unit rtti_catalog_bridge;

{$mode delphi}

interface

uses
  rtti_catalog_transitive;

function ExpectedCommandCount: Integer;

implementation

function ExpectedCommandCount: Integer;
begin
  Result:=5;
end;

end.
