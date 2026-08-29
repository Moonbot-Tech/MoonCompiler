unit chimera_tape_v4;

{ Четвёртое тело органа «лента»: ТОТ ЖЕ текст, что в третьем, — он подключается
  одним и тем же файлом, — но чистые шаги взяты из юнита, с которым этот юнит
  замкнут в кольцо зависимостей. Изнутри кольца вставка не работает, и цикл
  идёт по вызовам.

  Один исходник, два машинных кода. Расхождение ответа означает, что
  компилятор портит либо вставку, либо отказ от неё. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body, chimera_tape_types, chimera_tape_ring_far;

function ChiTapeV4(const Tape: TChiTape): TChiSum;

{ Половина замыкания кольца: сосед зовёт это из своей реализации. }
function ChiTapeV4Stamp(N: Integer): Integer;

implementation

{$I chimera_tape_pure.inc}

function ChiTapeV4(const Tape: TChiTape): TChiSum;
begin
  Result := TapePure(Tape);
end;

function ChiTapeV4Stamp(N: Integer): Integer;
begin
  Result := N * 2 + 1;
end;

end.
