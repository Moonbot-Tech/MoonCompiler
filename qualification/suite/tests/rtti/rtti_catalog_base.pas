unit rtti_catalog_base;

{$mode delphi}
interface

uses
  Rtti,
  TypInfo;

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  CommandId = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  CommandGroup = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  [CommandGroup(7), CommandId(0)]
  TCommandBase = class
  end;

  [CommandId(1)]
  TDirectCommand = class(TCommandBase)
  private
    FSecret: Integer;
  public type
    TNestedCatalogClass = class
    end;
  public
    FVisible: Integer;
  end;

  TForwardCommand = class;
  [CommandId(2)]
  TForwardCommand = class(TCommandBase)
  end;

  TCommandAlias = TDirectCommand;
  TUniqueCommand = type TDirectCommand;
  ICatalogInterface = interface
    ['{9B92D0E7-A89D-4DD8-B80A-B908CB29A333}']
    procedure Touch;
  end;
  TUniqueInteger = type Integer;
  TCatalogEnum = (ceZero, ceOne);
  TCatalogRecord = record
    Value: Integer;
  end;

function TouchNonPublicCatalogTypes: Boolean;
function ImplementationCatalogTypeInfo: PTypeInfo;

implementation

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  TImplementationCatalogClass = class
  end;

constructor CommandId.Create(AValue: Integer);
begin
  FValue:=AValue;
end;

constructor CommandGroup.Create(AValue: Integer);
begin
  FValue:=AValue;
end;

function TouchNonPublicCatalogTypes: Boolean;
begin
  Result:=
    TDirectCommand.TNestedCatalogClass.InheritsFrom(TObject) and
    TImplementationCatalogClass.InheritsFrom(TObject);
end;

function ImplementationCatalogTypeInfo: PTypeInfo;
begin
  Result:=TypeInfo(TImplementationCatalogClass);
end;

end.
