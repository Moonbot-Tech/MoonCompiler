program Fpc41770GenericConstraintHeader;

{$mode delphi}

type
  TBase = class
  end;

  TGeneric<T: TBase> = class
  end;

  TWrapper = class
    procedure DoWork<T: TBase>(Value: TGeneric<T>);
  end;

procedure TWrapper.DoWork<T>(Value: TGeneric<T>);
begin
end;

begin
end.
