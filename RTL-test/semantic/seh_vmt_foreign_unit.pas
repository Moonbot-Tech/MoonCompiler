unit seh_vmt_foreign_unit;
{$mode delphiunicode}
interface
uses SysUtils;
type
  EForeign = class(Exception);
  EForeignAlias = type EForeign;
procedure RaiseForeign;
implementation
procedure RaiseForeign;
begin
  raise EForeign.Create('foreign');
end;
end.
