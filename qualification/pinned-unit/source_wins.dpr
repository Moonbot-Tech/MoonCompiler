program source_wins;

uses
  PinFixture;

begin
  If PinFixtureValue <> 42 then
    Halt(1);
end.
