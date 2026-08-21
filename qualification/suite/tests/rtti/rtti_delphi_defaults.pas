unit rtti_delphi_defaults;

{$mode delphi}

interface

uses
  Rtti;

type
  TDefaultFieldAttribute = class(TCustomAttribute)
  public
    constructor Create;
  end;

  TDefaultRttiClass = class
  public
    [TDefaultFieldAttribute]
    Enabled: Boolean;
  end;

  TBooleanPair = array[0..1] of Boolean;

implementation

constructor TDefaultFieldAttribute.Create;
begin
  inherited Create;
end;

end.
