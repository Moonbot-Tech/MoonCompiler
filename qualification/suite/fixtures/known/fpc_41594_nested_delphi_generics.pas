program Fpc41594NestedDelphiGenerics;

{$mode delphi}

type
  TGen1<T> = class end;
  TGen2<T> = class end;

  TMethods = class
    procedure DoWork<T>(ASelector: TGen1<TGen2<T>>);
    procedure Work<T>;
  end;

procedure TMethods.Work<T>;
begin
  DoWork<TObject>(nil);
end;

procedure TMethods.DoWork<T>(ASelector: TGen1<TGen2<T>>);
begin
end;

begin
end.
