program Fpc41614GenericOpenArrayOverload;

{$mode delphi}

type
  TGenericArray<T> = array of T;

  TArrayUtilities = class
    class function Join<T>(const A, B: TGenericArray<T>): TGenericArray<T>;
      overload; static;
    class function Join<T>(const Arrays: array of TGenericArray<T>):
      TGenericArray<T>; overload; static;
  end;

class function TArrayUtilities.Join<T>(const A, B: TGenericArray<T>):
  TGenericArray<T>;
begin
  SetLength(Result, Length(A) + Length(B));
end;

class function TArrayUtilities.Join<T>(const Arrays: array of TGenericArray<T>):
  TGenericArray<T>;
begin
  SetLength(Result, Length(Arrays));
end;

begin
end.
