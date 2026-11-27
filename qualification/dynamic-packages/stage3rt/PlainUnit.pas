unit PlainUnit;

{$mode delphi}

interface

uses
  Classes;

type
  { All ancestors live in rtlpkg (TPersistent) - outside the DLL being unloaded }
  TPlainPlugin = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

var
  GFlag: Integer = 3;
  GStr: string;

implementation

function TPlainPlugin.Describe: string;
begin
  Result := 'plain';
end;

initialization
  GStr := 'loaded';
  GFlag := 7;
  RegisterClass(TPlainPlugin);

finalization
  UnRegisterClass(TPlainPlugin);
  GStr := '';
  GFlag := 0;

end.
