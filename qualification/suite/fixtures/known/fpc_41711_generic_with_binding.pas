program Fpc41711GenericWithBinding;

{$mode delphi}

var
  WrongDestructorCalls: Integer;

type
  TTestObject = class
    procedure ReleaseSelf<T: class>;
  end;

  TOuter = class
    procedure Invoke;
    destructor Destroy; override;
  end;

procedure TTestObject.ReleaseSelf<T>;
begin
  Self.Free;
end;

destructor TOuter.Destroy;
begin
  Inc(WrongDestructorCalls);
  inherited;
end;

procedure TOuter.Invoke;
begin
  with TTestObject.Create do
    ReleaseSelf<TTestObject>;
end;

var
  Outer: TOuter;
begin
  Outer := TOuter.Create;
  Outer.Invoke;
  if WrongDestructorCalls <> 0 then
    Halt(1);
  Outer.Free;
end.
