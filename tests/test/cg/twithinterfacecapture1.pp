{ %OPT=-O3 }

program twithinterfacecapture1;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  IItem = interface
    ['{6D5E34BE-7224-49B2-BCCA-3EA6460B9F88}']
    function GetValue: Integer;
    procedure SetValue(AValue: Integer);
    property Value: Integer read GetValue write SetValue;
  end;

  TItem = class(TInterfacedObject, IItem)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function GetValue: Integer;
    procedure SetValue(AValue: Integer);
  end;

  TReader = reference to function: Integer;

var
  Created,
  Destroyed: Integer;

constructor TItem.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
  Inc(Created);
end;

destructor TItem.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TItem.GetValue: Integer;
begin
  Result := FValue;
end;

procedure TItem.SetValue(AValue: Integer);
begin
  FValue := AValue;
end;

function MakeItem(AValue: Integer): IItem;
begin
  Result := TItem.Create(AValue);
end;

function Capture(Value: Integer): TReader;
begin
  with MakeItem(Value) do
    Result := function: Integer
      begin
        Result := GetValue;
      end;
end;

function ReadImmediately(AValue: Integer): Integer;
var
  Reader: TReader;
begin
  with MakeItem(AValue) do
  begin
    Value := Value + 1;
    Reader := function: Integer
      begin
        Result := GetValue;
      end;
    Result := Reader();
    Reader := nil;
  end;
end;

var
  First,
  Second: TReader;
begin
  First := Capture(17);
  Second := Capture(29);
  If (Created <> 2) or (Destroyed <> 0) then
    Halt(1);
  If (First() <> 17) or (Second() <> 29) then
    Halt(2);

  First := nil;
  If Destroyed <> 1 then
    Halt(3);
  Second := nil;
  If Destroyed <> 2 then
    Halt(4);

  If ReadImmediately(73) <> 74 then
    Halt(5);
  If (Created <> 3) or (Destroyed <> 3) then
    Halt(6);
end.
