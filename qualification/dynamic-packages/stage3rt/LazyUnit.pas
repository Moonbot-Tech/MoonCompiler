unit LazyUnit;

{ A deliberately "lazy" package unit - it registers a class in initialization
  but never unregisters it in finalization. Verifies that the module-unload
  hook of RTL UnloadPackage (UnRegisterModuleClasses in Classes) clears
  leftover registrations. }

{$mode delphi}

interface

uses
  Classes;

type
  TLazyPlugin = class(TPersistent)
  public
    function Describe: string; virtual;
  end;

implementation

function TLazyPlugin.Describe: string;
begin
  Result := 'lazy';
end;

initialization
  RegisterClass(TLazyPlugin);

{ No finalization - UnRegisterClass is omitted on purpose }

end.
