program rtti_nocall;

{$mode delphi}

uses
  SysUtils,
  rtti_catalog_bridge,
  rtti_catalog_base,
  rtti_catalog_plain,
  rtti_catalog_runtime_tables;

var
  Command: TDirectCommand;
begin
  if not TouchNonPublicCatalogTypes or (ExpectedCommandCount<>5) or
     (CatalogResource<>'resource-ok') then
    Halt(1);
  Command:=TDirectCommand.Create;
  try
    Command.FVisible:=42;
    Writeln('RTTI_NOCALL_PASS ',Command.FVisible);
  finally
    Command.Free;
  end;
end.
