program Fpc41834CorbaGenericName;

{$mode objfpc}
{$interfaces corba}

type
  IFoo = interface ['{613ACB35-37AE-467E-979F-B27647E78AAF}']
    procedure Invoke;
  end;

  TBar = class(TObject, IFoo)
    procedure Invoke; virtual; abstract;
  end;

  generic TGen<I: IFoo> = class
    procedure Invoke;
  end;

  TIFooGen = specialize TGen<IFoo>;

procedure TGen.Invoke;
begin
  (Self as I).Invoke;
end;

begin
  if ParamCount < 0 then
    (TBar(nil) as IFoo).Invoke;
end.
