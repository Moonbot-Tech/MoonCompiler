program Fpc41612GenericContainerAlias;

{$mode delphi}

uses
  Generics.Collections;

type
  TGenericArray<T> = array of T;

var
  Lists: TList<TGenericArray<Byte>>;
begin
  Lists := TList<TGenericArray<Byte>>.Create;
  Lists.Free;
end.
