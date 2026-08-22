program mormot_ikeyvalue_rtti_link;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
  cthreads,
  mormot_ikeyvalue_rtti_link_unit;
begin
  if RunIKeyValueRttiLink<>3 then
    Halt(1);
  WriteLn('MORMOT_IKEYVALUE_RTTI_LINK_PASS');
end.
