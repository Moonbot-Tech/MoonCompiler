{ %OPT=-O3 }
program tinheritedabstractproperty1;

{$mode delphi}

type
  TAbstractBase = class
  protected
    function GetValue: Integer; virtual; abstract;
    procedure SetValue(AValue: Integer); virtual; abstract;
  public
    property Value: Integer read GetValue write SetValue;
  end;

  TConcreteParent = class(TAbstractBase)
  protected
    FValue: Integer;
    function GetValue: Integer; override;
    procedure SetValue(AValue: Integer); override;
  end;

  TChild = class(TConcreteParent)
  protected
    function GetValue: Integer; override;
    procedure SetValue(AValue: Integer); override;
  public
    function ReadInherited: Integer;
    procedure WriteInherited(AValue: Integer);
  end;

function TConcreteParent.GetValue: Integer;
begin
  Result := FValue;
end;

procedure TConcreteParent.SetValue(AValue: Integer);
begin
  FValue := AValue;
end;

function TChild.GetValue: Integer;
begin
  Result := inherited GetValue + 1;
end;

procedure TChild.SetValue(AValue: Integer);
begin
  inherited SetValue(AValue + 1);
end;

function TChild.ReadInherited: Integer;
begin
  Result := inherited Value;
end;

procedure TChild.WriteInherited(AValue: Integer);
begin
  inherited Value := AValue;
end;

var
  Item: TChild;
begin
  Item := TChild.Create;
  try
    Item.WriteInherited(40);
    If Item.ReadInherited <> 42 then
      Halt(1);
  finally
    Item.Free;
  end;
end.
