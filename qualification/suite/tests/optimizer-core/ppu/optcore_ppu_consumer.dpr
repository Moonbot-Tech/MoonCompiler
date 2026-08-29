program optcore_ppu_consumer;

{$mode delphi}

uses
  optcore_ppu_fixture;

var
  Box: TBox<Integer>;
  Managed: TManagedBox;
  Digest: Integer;

begin
  Box.Item := 7;
  Managed := BuildManaged(11);
  Digest := FoldManaged(Managed) + InlineMix(Box.Item, 5);
  if Digest <> 877 then
    Halt(1);
  WriteLn('PPU_GATE_OK ', Digest);
end.
