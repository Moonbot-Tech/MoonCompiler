program comparer;

{ Сравниватель по умолчанию для узких беззнаковых типов.

  От `Compare` нужен только знак: меньше нуля, ноль, больше нуля. Величина —
  дело реализации. Здесь проверяется именно знак, и на тех парах, где разность
  не помещается в знаковый тип той же ширины. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, Generics.Defaults, Generics.Collections;

procedure Show(const Name: string; Got: Integer; WantPositive: Boolean);
var
  Verdict: string;
begin
  if WantPositive then
  begin
    if Got > 0 then
      Verdict := 'ok'
    else
      Verdict := 'WRONG SIGN';
  end
  else
  begin
    if Got < 0 then
      Verdict := 'ok'
    else
      Verdict := 'WRONG SIGN';
  end;
  WriteLn(Name, ' = ', Got, '  ', Verdict);
end;

procedure Sorting;
var
  Data: TArray<Word>;
  I: Integer;
  Ordered: Boolean;
begin
  WriteLn('--- sorting Word');
  Data := TArray<Word>.Create(1, 65535, 2, 40000, 3, 60000);
  TArray.Sort<Word>(Data);
  Write('  result:');
  for I := 0 to High(Data) do
    Write(' ', Data[I]);
  WriteLn;
  Ordered := True;
  for I := 1 to High(Data) do
    if Data[I] < Data[I - 1] then
      Ordered := False;
  if Ordered then
    WriteLn('  sorted: ok')
  else
    WriteLn('  sorted: BROKEN');
end;

procedure SortingByte;
var
  Data: TArray<Byte>;
  I: Integer;
  Ordered: Boolean;
begin
  WriteLn('--- sorting Byte');
  Data := TArray<Byte>.Create(1, 255, 2, 200, 3, 128);
  TArray.Sort<Byte>(Data);
  Write('  result:');
  for I := 0 to High(Data) do
    Write(' ', Data[I]);
  WriteLn;
  Ordered := True;
  for I := 1 to High(Data) do
    if Data[I] < Data[I - 1] then
      Ordered := False;
  if Ordered then
    WriteLn('  sorted: ok')
  else
    WriteLn('  sorted: BROKEN');
end;

procedure SortingCardinal;
var
  Data: TArray<Cardinal>;
  I: Integer;
  Ordered: Boolean;
begin
  WriteLn('--- sorting Cardinal');
  Data := TArray<Cardinal>.Create(1, $FFFFFFFF, 2, $F0000000, 3, $80000000);
  TArray.Sort<Cardinal>(Data);
  Write('  result:');
  for I := 0 to High(Data) do
    Write(' ', Data[I]);
  WriteLn;
  Ordered := True;
  for I := 1 to High(Data) do
    if Data[I] < Data[I - 1] then
      Ordered := False;
  if Ordered then
    WriteLn('  sorted: ok')
  else
    WriteLn('  sorted: BROKEN');
end;

begin
  WriteLn('--- Word');
  Show('cmp(65535, 1)', TComparer<Word>.Default.Compare(65535, 1), True);
  Show('cmp(1, 65535)', TComparer<Word>.Default.Compare(1, 65535), False);
  Show('cmp(40000, 1)', TComparer<Word>.Default.Compare(40000, 1), True);
  Show('cmp(32768, 1)', TComparer<Word>.Default.Compare(32768, 1), True);
  Show('cmp(32767, 1)', TComparer<Word>.Default.Compare(32767, 1), True);
  Show('cmp(300, 1)', TComparer<Word>.Default.Compare(300, 1), True);

  WriteLn('--- Byte');
  Show('cmp(255, 1)', TComparer<Byte>.Default.Compare(255, 1), True);
  Show('cmp(200, 1)', TComparer<Byte>.Default.Compare(200, 1), True);
  Show('cmp(128, 1)', TComparer<Byte>.Default.Compare(128, 1), True);
  Show('cmp(127, 1)', TComparer<Byte>.Default.Compare(127, 1), True);

  WriteLn('--- Cardinal');
  Show('cmp($FFFFFFFF, 1)', TComparer<Cardinal>.Default.Compare($FFFFFFFF, 1), True);
  Show('cmp($80000000, 1)', TComparer<Cardinal>.Default.Compare($80000000, 1), True);

  WriteLn('--- UInt64');
  Show('cmp($FFFFFFFFFFFFFFFF, 1)',
       TComparer<UInt64>.Default.Compare(UInt64($FFFFFFFFFFFFFFFF), 1), True);

  WriteLn('--- signed control');
  Show('SmallInt cmp(-1, 1)', TComparer<SmallInt>.Default.Compare(-1, 1), False);
  Show('Int64 cmp(-1, 1)', TComparer<Int64>.Default.Compare(-1, 1), False);

  Sorting;
  SortingByte;
  SortingCardinal;
  WriteLn('done');
end.
