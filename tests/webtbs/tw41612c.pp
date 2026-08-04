program tw41612c;

{$mode delphi}

uses
  Generics.Collections;

type
  TGenericArray<T> = array of T;

  TGenericPair<TLeft, TRight> = class
  end;

var
  Lists: TList<TGenericArray<Byte>>;
  NestedLists: TList<TList<Byte>>;
  TripleLists: TList<TList<TGenericArray<Word>>>;
  Pair: TGenericPair<TList<Byte>, TList<Word>>;
  Data: TGenericArray<Byte>;
begin
  Lists := TList<TGenericArray<Byte>>.Create;
  try
    SetLength(Data, 2);
    Data[0] := 41;
    Data[1] := 42;
    Lists.Add(Data);
    if (Lists.Count <> 1) or
        (Length(Lists[0]) <> 2) or
        (Lists[0][0] <> 41) or
        (Lists[0][1] <> 42) then
      Halt(1);
  finally
    Lists.Free;
  end;

  NestedLists := TList<TList<Byte>>.Create;
  try
    if NestedLists.Count <> 0 then
      Halt(2);
  finally
    NestedLists.Free;
  end;

  TripleLists := TList<TList<TGenericArray<Word>>>.Create;
  try
    if TripleLists.Count <> 0 then
      Halt(3);
  finally
    TripleLists.Free;
  end;

  Pair := TGenericPair<TList<Byte>, TList<Word>>.Create;
  try
    if Pair = nil then
      Halt(4);
  finally
    Pair.Free;
  end;
end.
