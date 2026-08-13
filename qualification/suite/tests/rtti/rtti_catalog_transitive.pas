unit rtti_catalog_transitive;

{$mode delphi}
interface

uses
  rtti_catalog_base;

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  [CommandId(3)]
  TTransitiveCommand = class(TCommandBase)
  private
    FTransitiveSecret: Int64;
  end;

implementation

end.
