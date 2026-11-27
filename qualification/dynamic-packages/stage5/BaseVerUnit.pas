unit BaseVerUnit;

{$mode delphi}

interface

uses
  Classes;

type
  TVersionedBase = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

implementation

function TVersionedBase.Describe: string;
begin
  Result := 'base';
end;

end.
