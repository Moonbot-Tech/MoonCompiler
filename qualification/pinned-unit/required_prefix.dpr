program required_prefix;

uses
  PinFixture,
  NormalFixture;

begin
  If PinFixtureValue + NormalFixtureValue <> 49 then
    Halt(1);
end.
