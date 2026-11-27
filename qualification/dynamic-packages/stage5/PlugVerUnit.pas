unit PlugVerUnit;

{$mode delphi}

interface

uses
  Classes, BaseVerUnit;

type
  TVersionedPlugin = class(TVersionedBase)
  public
    function Describe: string; override;
  end;

implementation

function TVersionedPlugin.Describe: string;
begin
  Result := 'plugin(' + inherited Describe + ')';
end;

initialization
  RegisterClass(TVersionedPlugin);
finalization
  UnRegisterClass(TVersionedPlugin);
end.
