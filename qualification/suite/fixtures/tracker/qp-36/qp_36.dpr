program tracker_qp_36;
{$ifdef FPC}{$mode delphiunicode}{$endif}
uses qp36_descendant;
var Value: TDescendant<Integer>;
begin
  Value := TDescendant<Integer>.Create;
  try if Value.ReadData <> 41 then Halt(1); finally Value.Free; end;
  WriteLn('PASS QP-36');
end.
