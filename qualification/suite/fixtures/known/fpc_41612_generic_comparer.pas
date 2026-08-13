program Fpc41612GenericComparer;

{$mode delphi}

uses
  Generics.Defaults;

type
  TGenericArray<T> = array of T;

  TArrayUtilities = class
    class function Contains<T>(const Data: TGenericArray<T>;
      const Value: T): Boolean; static;
  end;

class function TArrayUtilities.Contains<T>(const Data: TGenericArray<T>;
  const Value: T): Boolean;
var
  Comparer: IEqualityComparer<T>;
begin
  Comparer := TEqualityComparer<T>.Default;
  Result := (Length(Data) <> 0) and Comparer.Equals(Data[0], Value);
end;

var
  Data: TGenericArray<Byte>;
begin
  SetLength(Data, 1);
  Data[0] := 2;
  if not TArrayUtilities.Contains<Byte>(Data, 2) then
    Halt(1);
end.
