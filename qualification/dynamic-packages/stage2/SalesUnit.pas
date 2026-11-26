unit SalesUnit;

{$mode delphi}

interface

uses
  BaseUnit;

type
  { Inherits a class from another package - cross-module VMT reference }
  TSales = class(TBase)
  public
    function Describe: string; override;
  end;

implementation

function TSales.Describe: string;
begin
  { inherited call - the parent code lives in CommonPkg.fpl }
  Result := 'sales(' + inherited Describe + ')';
end;

end.
