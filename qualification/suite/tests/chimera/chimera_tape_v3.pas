unit chimera_tape_v3;

{ Третье тело органа «лента»: работа собрана из чистых шагов, взятых из
  ЛИСТОВОГО юнита. Там вставка тел работает, значит арифметика возвращается в
  тело цикла — но пришедшая с другой стороны, чем в монолите: не как один
  написанный текст, а как сшитая компилятором. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body, chimera_tape_types, chimera_tape_leaf;

function ChiTapeV3(const Tape: TChiTape): TChiSum;

implementation

{$I chimera_tape_pure.inc}

function ChiTapeV3(const Tape: TChiTape): TChiSum;
begin
  Result := TapePure(Tape);
end;

end.
