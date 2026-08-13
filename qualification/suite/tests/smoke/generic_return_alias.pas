program generic_return_alias;

{$mode delphi}
{$modeswitch implicitgenerics}

uses
  Generics.Collections;

type
  TIntAlias = Int64;

  TOuter<T, U> = class
  public type
    TPairAlias = TPair<T, U>;
    TInner = class
      function Current: TPairAlias;
    end;
  end;

function DirectAlias: TIntAlias; forward;

function DirectAlias: Int64;
begin
  Result:=42;
end;

function TOuter<T, U>.TInner.Current: TPair<T, U>;
begin
  Result:=Default(TPair<T, U>);
end;

var
  Inner: TOuter<Integer, Int64>.TInner;
  Value: TOuter<Integer, Int64>.TPairAlias;

begin
  if DirectAlias<>42 then
    Halt(2);
  Inner:=TOuter<Integer, Int64>.TInner.Create;
  try
    Value:=Inner.Current;
  finally
    Inner.Free;
  end;
  if (Value.Key<>0) or (Value.Value<>0) then
    Halt(1);
  Writeln('GENERIC_RETURN_ALIAS_OK');
end.
