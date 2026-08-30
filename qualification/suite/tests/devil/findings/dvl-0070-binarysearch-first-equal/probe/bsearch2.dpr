program bsearch2;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}{$Q-}{$R-}
uses SysUtils, Generics.Defaults, Generics.Collections;

var
  A: TArray<Integer>;
  Idx, I, K: Integer;
  Found: Boolean;
  S: string;
begin
  { обычный порядок, обычное сравнение, но с ПОВТОРАМИ }
  A := [0, 0, 1, 1, 1, 2, 3, 3];
  S := '';
  for I := 0 to High(A) do S := S + IntToStr(A[I]) + ' ';
  WriteLn('массив: ', S);
  for K := 0 to 3 do
  begin
    Idx := -1;
    Found := TArray.BinarySearch<Integer>(A, K, Idx);
    WriteLn('  ищем ', K, ': found=', BoolToStr(Found, True), ' idx=', Idx);
  end;
  { и на массиве из одинаковых }
  A := [7, 7, 7, 7, 7];
  Idx := -1;
  Found := TArray.BinarySearch<Integer>(A, 7, Idx);
  WriteLn('пять одинаковых, ищем 7: found=', BoolToStr(Found, True), ' idx=', Idx);
end.
