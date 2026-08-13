program Fpc41712GenericWithCall;

{$mode delphi}

type
  TTestObject = class
    procedure Invoke<T: class>;
  end;

procedure TTestObject.Invoke<T>;
begin
end;

var
  Instance: TTestObject;
begin
  Instance := TTestObject.Create;
  try
    with Instance do
      Invoke<TTestObject>;
  finally
    Instance.Free;
  end;
end.
