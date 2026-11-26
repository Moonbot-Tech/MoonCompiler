unit SharedIntf;

{$mode delphi}

interface

uses
  Classes;

type
  { Base class shared by host and plugin. Inherits from rtlpkg's TPersistent. }
  TPluginBase = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

implementation

function TPluginBase.Describe: string;
begin
  Result := 'base';
end;

end.
