program cycmain;

{$mode delphi}

uses
  cyctypes, cycrel;

var
  S: TSpan;
begin
  S.Low := 1; S.High := 3;
  If S.IsEmpty or (Relation(S.Low, S.High) <> -1) then
    Halt(1);
  WriteLn('CYCLIC_UNIT_IMPL_CHANGE_OK ', S.Width:0:0);
end.
