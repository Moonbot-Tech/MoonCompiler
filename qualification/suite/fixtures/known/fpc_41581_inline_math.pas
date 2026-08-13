program Fpc41581InlineMath;

{$mode objfpc}

uses
  Math;

function Calc: Double; inline;
begin
  Result := Power(10, Floor(Log10(0.01)));
end;

begin
  if Abs(Calc - 0.01) > 1.0e-12 then
    Halt(1);
end.
