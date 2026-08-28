unit O3AutoinlineCycleA;

{$mode delphi}

interface

procedure RunCycle;

implementation

uses
  O3AutoinlineCycleB;

procedure RunCycle;
begin
  TouchPrivateClassVar;
end;

end.
