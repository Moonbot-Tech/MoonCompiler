program minrep;

{ Таблица подстановки применяется к массиву внутри внешнего цикла. На каждом
  проходе внешнего цикла массив уже другой, поэтому и результат обязан быть
  другим. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

var
  Table: array[0 .. 255] of Byte;
  Data: array[0 .. 15] of Byte;
  I, R: Integer;
  Line: string;
begin
  { Таблица — простая перестановка, чтобы не тащить сюда настоящую. }
  for I := 0 to 255 do
    Table[I] := Byte((I * 7 + 13) and $FF);
  for I := 0 to 15 do
    Data[I] := Byte(I);

  for R := 1 to 3 do
  begin
    { подстановка }
    for I := 0 to 15 do
      Data[I] := Table[Data[I]];

    { что-то ещё, меняющее массив: без этого шага цикл вырождается }
    for I := 0 to 15 do
      Data[I] := Byte(Data[I] xor Byte(R));

    Line := '';
    for I := 0 to 7 do
      Line := Line + IntToHex(Data[I], 2) + ' ';
    WriteLn('pass ', R, ': ', Line);
  end;
  WriteLn('done');
end.
