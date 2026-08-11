{ %OPT=-O3 }
program tdelphihelperinheritedproperty1;

{$mode delphi}

type
  TBase = class
  private
    FValue: Single;
    function GetValue: Single;
    procedure SetValue(const AValue: Single);
  public
    property Value: Single read GetValue write SetValue;
  end;

  TBaseHelper = class helper for TBase
  private
    function GetValue: Single;
    procedure SetValue(AValue: Single);
  public
    property Value: Single read GetValue write SetValue;
  end;

function TBase.GetValue: Single;
begin
  Result := FValue;
end;

procedure TBase.SetValue(const AValue: Single);
begin
  FValue := AValue;
end;

function TBaseHelper.GetValue: Single;
begin
  Result := inherited Value;
end;

procedure TBaseHelper.SetValue(AValue: Single);
begin
  inherited Value := AValue;
end;

var
  Item: TBase;
begin
  Item := TBase.Create;
  Item.Value := 7.5;
  If Item.Value <> 7.5 then
    Halt(1);
  Item.Free;
end.
