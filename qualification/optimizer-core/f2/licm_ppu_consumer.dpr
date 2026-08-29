program licm_ppu_consumer;

{$mode unleashed}

uses
  licm_ppu_source;

var
  Value: Int64;
begin
  Value := TScaleWorker<Byte>.Run(7, 64);
  WriteLn('F2-PPU:', Value);
end.
