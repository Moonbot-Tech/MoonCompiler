program host2;

{$mode delphi}

uses
  BaseUnit,
  SalesUnit;

var
  GBase: TBase;
begin
  { Construction: TSales's VMT is in SalesPkg.fpl, the ancestor code in CommonPkg.fpl }
  GBase := TSales.Create('acme');

  { Virtual dispatch - the descendant's override must be called }
  WriteLn(GBase.Describe);

  { is / as - walks the VMT inheritance chain across the DLL boundary }
  WriteLn('is TSales  : ', GBase is TSales);
  WriteLn('is TBase   : ', GBase is TBase);
  WriteLn('ClassName  : ', GBase.ClassName);
  WriteLn('Parent     : ', GBase.ClassParent.ClassName);

  (GBase as TSales).Free;
  WriteLn('host2 ok');
end.
