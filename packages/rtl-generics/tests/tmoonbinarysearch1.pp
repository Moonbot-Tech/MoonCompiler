{ %OPT=-O2 }
program tmoonbinarysearch1;

{$mode delphi}

uses
  Generics.Defaults,
  Generics.Collections;

var
  Values: TArray<Integer>;
  Index: Integer;
begin
  Values := TArray<Integer>.Create(9, 1, 5);
  TArray.Sort<Integer>(Values);
  if not TArray.BinarySearch<Integer>(Values, 5, Index) or (Index <> 1) then
    Halt(1);
  if TArray.BinarySearch<Integer>(Values, 4, Index,
    TComparer<Integer>.Default) or (Index <> 1) then
    Halt(2);
end.
