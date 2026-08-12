program foreign_lookup;

uses
  PinFixture;

begin
  If PinFixtureValue <> 13 then
    Halt(1);
end.
