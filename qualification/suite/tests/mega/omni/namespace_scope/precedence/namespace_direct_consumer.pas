unit namespace_direct_consumer;

interface

uses
  Sample;

function DirectOrigin: Integer;

implementation

function DirectOrigin: Integer;
begin
  Result := Sample.Origin;
end;

end.
