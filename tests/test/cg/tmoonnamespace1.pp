{ %OPT=-O2 -FNMoonScope -UaMoonAlias=MoonNsAliasTarget }
program tmoonnamespace1;

{$mode delphi}

uses
  MoonScope.MoonNsSample,
  MoonNsFactory,
  MoonAlias;

begin
  if MoonScope.MoonNsSample.Marker <> 17 then
    Halt(1);
  if FactoryMarker <> 17 then
    Halt(2);
  if AliasMarker <> 42 then
    Halt(3);
end.
