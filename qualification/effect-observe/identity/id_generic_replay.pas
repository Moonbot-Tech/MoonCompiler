program id_generic_replay;

{ The runner copies this source away from id_generic.pas and compiles it
  against an OFF-built PPU.  The Int64 specialization is intentionally not
  instantiated by the unit itself. }

{$mode delphi}

uses
  id_generic;

var
  Pair: TPair<Int64>;
begin
  Pair := TPair<Int64>.Create;
  try
    Pair.A := 19;
    Pair.B := 23;
    WriteLn(Pair.Sum);
  finally
    Pair.Free;
  end;
end.
