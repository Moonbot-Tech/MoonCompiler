unit ReverseAliasGeneric;

{$mode delphi}

interface

uses
  AliasTarget;

type
  TAliasReader<T> = record
    class function ReadMarker: Integer; static;
  end;

implementation

class function TAliasReader<T>.ReadMarker: Integer;
begin
  Result:=ScopeX.AliasTarget.Marker;
end;

end.
