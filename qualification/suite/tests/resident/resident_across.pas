unit resident_across;

{ Соседний юнит для семейства `opaque` — здесь живёт то, что вызывающая
  сторона не видит насквозь.

  Смысл разделения именно в границе компиляции. Пока переменная и процедура,
  которая её меняет, лежат в одном юните, компилятору доступно всё тело сразу,
  и он вправе рассуждать о значении сколь угодно точно. Через границу юнита
  такое рассуждение опирается уже не на текст, а на модель эффектов — и
  ошибиться в ней куда легче. Отсюда правило: всё, что стадия обязана считать
  непрозрачным, обязано жить здесь.

  Тела намеренно тривиальны. Дефект, который мы ловим, не в арифметике, а в
  том, заметил ли оптимизатор сам факт изменения; чем проще тело, тем охотнее
  оно будет вставлено в место вызова, а вставка — как раз тот случай, где
  изменение приезжает после того, как решение об инвариантности уже принято. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, SyncObjs;

var
  AcrossI32: Integer;
  AcrossU32: Cardinal;
  AcrossI64: Int64;
  AcrossText: string;

{ Глобалы общие на программу, а кольцо многопоточное. Стадия, которая их
  трогает, обязана владеть ими целиком — не ради скорости, а ради того, чтобы
  её собственный результат оставался её результатом. Захват берётся на всю
  стадию, а не на отдельный доступ: половина стадии под замком — это уже
  чужая арифметика в середине своей. }
procedure AcrossEnter;
procedure AcrossLeave;

procedure AcrossBump32(Delta: Integer);
procedure AcrossBumpU32(Delta: Cardinal);
procedure AcrossBump64(Delta: Int64);
procedure AcrossSet32(Value: Integer);
procedure AcrossGrowText(const Piece: string);
function AcrossRead32: Integer;
procedure AcrossBumpVia(var Target: Integer; Delta: Integer);

implementation

var
  Gate: TCriticalSection;

procedure AcrossEnter;
begin
  Gate.Enter;
end;

procedure AcrossLeave;
begin
  Gate.Leave;
end;

procedure AcrossBump32(Delta: Integer);
begin
  AcrossI32 := AcrossI32 + Delta;
end;

procedure AcrossBumpU32(Delta: Cardinal);
begin
  AcrossU32 := AcrossU32 + Delta;
end;

procedure AcrossBump64(Delta: Int64);
begin
  AcrossI64 := AcrossI64 + Delta;
end;

procedure AcrossSet32(Value: Integer);
begin
  AcrossI32 := Value;
end;

procedure AcrossGrowText(const Piece: string);
begin
  AcrossText := AcrossText + Piece;
end;

function AcrossRead32: Integer;
begin
  Result := AcrossI32;
end;

{ Меняет то, на что указали. Вызывающая сторона вправе передать сюда свой
  локал, а вправе — и чужой глобал; отличить одно от другого по сигнатуре
  нельзя, и в этом весь смысл. }
procedure AcrossBumpVia(var Target: Integer; Delta: Integer);
begin
  Target := Target + Delta;
end;

initialization
  Gate := TCriticalSection.Create;

finalization
  FreeAndNil(Gate);

end.
