program Fpc41612GenericExpression;

{$mode delphi}

type
  TGenericArray<T> = array of T;

  TArrayUtilities = class
    class function AreEqual<T>(const A, B: TGenericArray<T>): Boolean; static;
  end;

class function TArrayUtilities.AreEqual<T>(const A, B: TGenericArray<T>): Boolean;
begin
  Result := Length(A) = Length(B);
end;

var
  A, B: TGenericArray<Byte>;
begin
  if not ((1 = 1) and TArrayUtilities.AreEqual<Byte>(A, B)) then
    Halt(1);
end.
