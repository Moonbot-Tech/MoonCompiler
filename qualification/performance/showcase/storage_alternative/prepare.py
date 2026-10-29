"""Create an isolated RTL copy; source RTL is never edited. No compiler rebuild."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[4]
src = root / 'packages/rtl-generics/src'
a.output.mkdir(parents=True, exist_ok=False)
(a.output / 'inc').mkdir()
unit = (src / 'generics.collections.pas').read_text(encoding='utf-8')
unit = unit.replace('Generics.Collections', 'Astra.Collections')
(a.output / 'astra.collections.pas').write_text(unit, encoding='utf-8')
(a.output / 'generics.threadedqueue.inc').write_bytes((src / 'generics.threadedqueue.inc').read_bytes())
for name in ('generics.dictionariesh.inc', 'generics.dictionaries.inc'):
    text = (src / 'inc' / name).read_text(encoding='utf-8')
    if name == 'generics.dictionaries.inc':
        old = '''      if (LItem.Hash and UInt32.GetSignMask) = 0 then
        Exit(not Result);
      if (LItem.Hash = AHash) and FlatEquals(AKey, LItem.Pair.Key) then
        Exit;'''
        new = '''      {$ifdef ASTRA_HIT_FIRST}
      if GetTypeKind(TKey) in [tkUString, tkAString] then
      begin
        if LItem.Hash = AHash then
        begin
          if FlatEquals(AKey, LItem.Pair.Key) then Exit;
        end
        else if (LItem.Hash and UInt32.GetSignMask) = 0 then
          Exit(not Result);
      end
      else
      {$endif}
      begin
''' + old + '''
      end;'''
        assert text.count(old) == 1, 'FlatFindForHash source changed; review before applying'
        text = text.replace(old, new)
        for old, new in (
            ('@PUnicodeString(@AKey)^[1]', '@UnicodeString(AKey)[1]'),
            ('Length(PUnicodeString(@AKey)^)', 'Length(UnicodeString(AKey))'),
            ('@PAnsiString(@AKey)^[1]', '@RawByteString(AKey)[1]'),
            ('Length(PAnsiString(@AKey)^)', 'Length(RawByteString(AKey))'),
            ('PUnicodeString(@ALeft)^ = PUnicodeString(@ARight)^', 'UnicodeString(ALeft) = UnicodeString(ARight)'),
            ('PAnsiString(@ALeft)^ = PAnsiString(@ARight)^', 'RawByteString(ALeft) = RawByteString(ARight)'),
        ):
            assert text.count(old) == 1, old
            text = text.replace(old, '{$ifdef ASTRA_DIRECT_CAST}' + new + '{$else}' + old + '{$endif}')
        old = '''function TOpenAddressingLinearLP<TKey, TValue, THashFactory>.FindKey(const AKey: TKey): SizeInt;
var
  LHash: UInt32;
begin
'''
        new = old.replace('  LHash: UInt32;', '''  LHash: UInt32;
  {$ifdef ASTRA_FUSED}LBase, LItem: PItem; m: SizeInt; LProbeHash: UInt32;{$endif}''') + '''  {$ifdef ASTRA_FUSED}
  if GetTypeKind(TKey) in [tkUString, tkAString] then
  begin
    if not FFlat then Exit(FindBucketIndex(FItems, AKey, LHash));
    {$ifdef ASTRA_BASE_BEFORE_HASH}LBase := Pointer(FItems);{$endif}
    if GetTypeKind(TKey) = tkUString then
      LProbeHash := THashFactory.GetHashCode(@PUnicodeString(@AKey)^[1],
        Length(PUnicodeString(@AKey)^) * SizeOf(UnicodeChar), 0)
    else
      LProbeHash := THashFactory.GetHashCode(@PAnsiString(@AKey)^[1], Length(PAnsiString(@AKey)^), 0);
    LProbeHash := LProbeHash or UInt32.GetSignMask;
    {$ifndef ASTRA_BASE_BEFORE_HASH}LBase := Pointer(FItems);{$endif}
    m := Length(FItems);
    if m <> 0 then
    begin
      Result := LProbeHash and (m - 1);
      LItem := @LBase[Result];
      repeat
        if (LItem.Hash and UInt32.GetSignMask) = 0 then Exit(not Result);
        if LItem.Hash = LProbeHash then
        begin
          if GetTypeKind(TKey) = tkUString then
          begin
            if PUnicodeString(@AKey)^ = PUnicodeString(@LItem.Pair.Key)^ then Exit;
          end
          else if PAnsiString(@AKey)^ = PAnsiString(@LItem.Pair.Key)^ then Exit;
        end;
        Inc(Result);
        Inc(LItem);
        if Result = m then
        begin
          Result := 0;
          LItem := LBase;
        end;
      until False;
    end;
    Exit(-1);
  end;
  {$endif}
'''
        assert text.count(old) == 1
        text = text.replace(old, new)
        old = '''  end;
  {$endif}
  if (GetTypeKind(TKey) in FlatKinds) and FFlat then
    Result := FlatFind(FItems, AKey, LHash)
  else
    Result := FindBucketIndex(FItems, AKey, LHash);
end;

constructor TOpenAddressingLinearLP'''
        new = '''  end
  else
  {$endif}
  begin
    if (GetTypeKind(TKey) in FlatKinds) and FFlat then
      Result := FlatFind(FItems, AKey, LHash)
    else
      Result := FindBucketIndex(FItems, AKey, LHash);
  end;
end;

constructor TOpenAddressingLinearLP'''
        assert text.count(old) == 1
        text = text.replace(old, new)
    (a.output / 'inc' / name).write_text(text, encoding='utf-8')
stand = root / 'qualification/performance/showcase/string_storage_probe.dpr'
text = stand.read_text(encoding='utf-8')
text = text.replace('program string_storage_probe;', 'program storage_alternative_probe;\n{$define RTL_BASELINE}')
text = text.replace('Generics.Collections,', 'Astra.Collections,')
text = text.replace("VariantName = 'rtl';", "{$ifdef ASTRA_HIT_FIRST}VariantName = 'hit-first';{$else}{$ifdef ASTRA_DIRECT_CAST}VariantName = 'direct-cast';{$else}{$ifdef ASTRA_FUSED}VariantName = 'fused';{$else}VariantName = 'copied-rtl';{$endif}{$endif}{$endif}")
(a.output / 'storage_alternative_probe.dpr').write_text(text, encoding='utf-8')
sources = [src / 'generics.collections.pas', src / 'generics.threadedqueue.inc', src / 'inc/generics.dictionaries.inc',
           src / 'inc/generics.dictionariesh.inc', stand]
(a.output / 'source_manifest.json').write_text(json.dumps({str(f.relative_to(root)):
    hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}, indent=2), encoding='utf-8')
print(a.output)
