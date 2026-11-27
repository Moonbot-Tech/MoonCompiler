unit SalesUnit;

{$mode delphi}

interface

uses
  Classes,
  SharedIntf;

type
  TSalesPlugin = class(TPluginBase)
  public
    function Describe: string; override;
  end;

implementation

function TSalesPlugin.Describe: string;
begin
  Result := 'sales-plugin';
end;

initialization
  { Register in the global class registry - the registry lives in rtlpkg's Classes unit }
  RegisterClass(TSalesPlugin);

finalization
  { Must be unregistered on unload. The registry survives in rtlpkg while
    TSalesPlugin's VMT goes away with this DLL, so a leftover entry would
    make the next GetClass read dead memory. Same rule as Delphi BPLs. }
  UnRegisterClass(TSalesPlugin);

end.
