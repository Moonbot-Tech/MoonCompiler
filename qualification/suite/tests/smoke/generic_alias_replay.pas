program generic_alias_replay;

{$mode delphi}
{$modeswitch implicitgenerics}

uses
  generic_alias_replay_unit;

type
  TIntegerBuffer = TBuffer<Integer>;

begin
  if not TIntegerBuffer.InheritsFrom(TObject) then
    Halt(1);
  Writeln('GENERIC_ALIAS_REPLAY_OK');
end.
