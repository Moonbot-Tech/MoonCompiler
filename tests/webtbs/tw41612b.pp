program tw41612b;

{$mode delphi}

uses
  Generics.Defaults;

type
  TGenericArray<T> = array of T;

  TUtilities = class
    class function Contains<T>(const Data: TGenericArray<T>;
      const Value: T): Boolean; static;
  end;

class function TUtilities.Contains<T>(const Data: TGenericArray<T>;
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
  if not TUtilities.Contains<Byte>(Data, 2) then
    Halt(1);
  if not TUtilities.Contains<Byte>(Data, 2) and
      TUtilities.Contains<Byte>(Data, 3) then
    Halt(2);
  if not TUtilities.Contains<Byte>(Data, 3) and
      TUtilities.Contains<Byte>(Data, 2) then
  begin
  end
  else
    Halt(3);
  if not not TUtilities.Contains<Byte>(Data, 3) then
    Halt(4);
end.
