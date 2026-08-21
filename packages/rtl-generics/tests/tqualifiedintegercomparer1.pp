program tqualifiedintegercomparer1;

{$mode delphi}

uses
  Generics.Defaults,
  Generics.Collections;

var
  Values: TArray<Word>;
  Index: Integer;
  I: Integer;

begin
  if TComparer<Word>.Default.Compare(65535, 1) <= 0 then
    Halt(1);
  if TComparer<Word>.Default.Compare(1, 65535) >= 0 then
    Halt(2);
  if TComparer<Word>.Default.Compare(32768, 32767) <= 0 then
    Halt(3);
  if TComparer<Word>.Default.Compare(40000, 40000) <> 0 then
    Halt(4);

  Values := TArray<Word>.Create(1, 65535, 2, 40000, 3, 60000, 32768, 32767);
  TArray.Sort<Word>(Values);
  for I := 1 to High(Values) do
    if Values[I - 1] >= Values[I] then
      Halt(10 + I);

  if not TArray.BinarySearch<Word>(Values, 65535, Index) then
    Halt(30);
  if (Index < 0) or (Index > High(Values)) or (Values[Index] <> 65535) then
    Halt(31);
  if TArray.BinarySearch<Word>(Values, 50000, Index) then
    Halt(32);

  { Adjacent unsigned-width controls. }
  if TComparer<Byte>.Default.Compare(255, 1) <= 0 then
    Halt(40);
  if TComparer<Cardinal>.Default.Compare(High(Cardinal), 1) <= 0 then
    Halt(41);
  if TComparer<UInt64>.Default.Compare(High(UInt64), 1) <= 0 then
    Halt(42);
end.
