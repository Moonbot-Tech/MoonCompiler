unit chimera_tape_leaf;

{ Чистые шаги прохода по ленте, живущие в ЛИСТОВОМ юните.

  Юнит не подключает ничего, кроме листовых же: он стоит ВНЕ всех колец
  зависимостей. Это условие его существования, а не аккуратность — из юнита,
  затянутого в кольцо, вставка тел не работает, и соседний
  `chimera_tape_ring_far` заведён ровно затем, чтобы это показать: тот же
  текст, то же `inline`, другое место в графе — другой машинный код.

  Ответ обязан совпасть до бита. Не совпал — компилятор портит код при
  вставке либо при отказе от неё. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body, chimera_tape_types;

{$I chimera_tape_steps.decl.inc}

implementation

{$I chimera_tape_steps.impl.inc}

end.
