program host15;

{ Links BaseVerPkg42.fpl at load time and loads xPlugVerPkg42.fpl at run
  time. Both find the packages they require by the versioned file names. }

{$mode delphi}

uses
  SysUtils, Classes, BaseVerUnit;

var
  H: HMODULE;
  C: TPersistentClass;
  O: TPersistent;
begin
  H := LoadPackage('xPlugVerPkg42.fpl');
  C := GetClass('TVersionedPlugin');
  if (C = nil) or not C.InheritsFrom(TVersionedBase) then
  begin
    WriteLn('TVersionedPlugin not registered or not a TVersionedBase');
    Halt(1);
  end;
  O := C.Create;
  WriteLn((O as TVersionedBase).Describe);
  O.Free;
  UnloadPackage(H);
  if GetClass('TVersionedPlugin') <> nil then
  begin
    WriteLn('TVersionedPlugin still registered after unload');
    Halt(1);
  end;
  WriteLn('host15 ok');
end.
