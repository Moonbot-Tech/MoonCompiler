unit variant_unicode_early_manager;
{$mode delphiunicode}
interface
var EarlyCalls: Integer;
implementation
var
  Saved, Hooked: TVariantManager;
  Raw: TVarData;
  Payload, Output: UnicodeString;

procedure EarlyRead(var Dest: WideString; const Source: Variant);
begin
  Inc(EarlyCalls);
  Dest := 'early-manager';
end;

procedure Verify;
begin
  Output := UnicodeString(PVariant(@Raw)^);
  if Output <> 'early-manager' then Halt(71);
end;

initialization
  Payload := 'before-Variants';
  Raw.VType := varUString;
  Raw.VUString := Pointer(Payload);
  GetVariantManager(Saved);
  Hooked := Saved;
  Hooked.VarToWStr := @EarlyRead;
  SetVariantManager(Hooked);
  Verify;
  if EarlyCalls <> 1 then Halt(72);
finalization
  Verify;
  if EarlyCalls <> 2 then Halt(73);
  SetVariantManager(Saved);
  WriteLn('V1_FINALIZATION_PASS');
end.
