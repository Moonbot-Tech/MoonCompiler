program Fpc41579NestedGenericProcAddress;

{$mode objfpc}

type
  TFoo = class
  public
    procedure P1(A: Integer); virtual;
  end;

  TBar = class
  public type
    TBase = TFoo;
  end;

  generic TGen<TBase: TBar> = class(TBase.TBase)
    procedure Test;
  end;

procedure TFoo.P1(A: Integer);
begin
end;

procedure TGen.Test;
begin
  if @TBase.TBase.P1 <> @TFoo.P1 then
    P1(1);
end;

begin
end.
