{ %OPT=-O2 }
program tmoonrtticatalog1;

{$mode delphi}

uses
  Rtti;

type
  TMoonCatalogType = class
  end;

var
  Context: TRttiContext;
  Item: TRttiType;
  Found: Boolean;
begin
  Found := False;
  Context := TRttiContext.Create(False);
  try
    for Item in Context.GetTypes do
      if Item.Name = 'TMoonCatalogType' then
        Found := True;
  finally
    Context.Free;
  end;
  if not Found then
    Halt(1);
end.
