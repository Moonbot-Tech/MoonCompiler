unit MoonNsFactory;

{$mode delphi}

interface

uses
  MoonNsSample;

function FactoryMarker: Integer;

implementation

function FactoryMarker: Integer;
begin
  Result := MoonNsSample.Marker;
end;

end.
