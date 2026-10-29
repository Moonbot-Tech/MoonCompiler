"""Freeze actual RTL and generate a separately named slice-only candidate."""
import argparse
import hashlib
import json
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
p.add_argument('--mode', choices=('constructor', 'lazy'), default='lazy')
a = p.parse_args()
root = Path(__file__).resolve().parents[4]
src = root / 'packages/rtl-generics/src'
a.output.mkdir(parents=True, exist_ok=False)
(a.output / 'inc').mkdir()
files = ['generics.collections.pas', 'generics.threadedqueue.inc',
         'inc/generics.dictionariesh.inc', 'inc/generics.dictionaries.inc']
manifest = {}
for name in files:
    raw = (src / name).read_bytes()
    manifest[name] = hashlib.sha256(raw).hexdigest()
    text = raw.decode('utf-8').replace('\r\n', '\n').replace('Generics.Collections', 'AstraSlice.Collections')
    if name.endswith('dictionariesh.inc'):
        old = '  private\n    function TryGetValueUtf8Converted'
        new = '''  {$ifdef ASTRA_SLICE_CACHE}
  private class var
    FUtf8SliceDefault: Pointer;
  private
    class constructor InitUtf8Slice;
  {$endif}
  private
    function TryGetValueUtf8Converted'''
        assert text.count(old) == 1
        if a.mode == 'lazy':
            new = new.replace('class constructor InitUtf8Slice;', 'class function InitUtf8Slice: Pointer; static; noinline;')
        text = text.replace(old, new)
    if name.endswith('dictionaries.inc'):
        start = 'function TOpenAddressingLP<OPEN_ADDRESSING_CONSTRAINTS>.TryGetValueUtf8Converted('
        init = '''{$ifdef ASTRA_SLICE_CACHE}
class constructor TOpenAddressingLP<OPEN_ADDRESSING_CONSTRAINTS>.InitUtf8Slice;
var
  LCodePage: TSystemCodePage;
begin
  if (GetTypeKind(TKey) = tkAString) and (TClass(THashFactory) = TDefaultHashFactory) then
  begin
    LCodePage := GetTypeData(TypeInfo(TKey))^.CodePage;
    if (LCodePage = CP_UTF8) or (LCodePage = CP_NONE) then
      FUtf8SliceDefault := Pointer(TEqualityComparer<TKey>.Default);
  end;
end;
{$endif}

'''
        assert text.count(start) == 1
        if a.mode == 'lazy':
            init = init.replace('class constructor TOpenAddressingLP<OPEN_ADDRESSING_CONSTRAINTS>.InitUtf8Slice;',
                                'class function TOpenAddressingLP<OPEN_ADDRESSING_CONSTRAINTS>.InitUtf8Slice: Pointer;')
            init = init.replace('begin\n  if (GetTypeKind', 'begin\n  Result := nil;\n  if (GetTypeKind')
            init = init.replace('      FUtf8SliceDefault := Pointer(TEqualityComparer<TKey>.Default);',
                                '''    begin
      Result := Pointer(TEqualityComparer<TKey>.Default);
      InterlockedCompareExchangePointer(FUtf8SliceDefault, Result, nil);
    end;''')
            varline = '  LIndex, LProbe, LMask: SizeInt;'
            assert text.count(varline) == 1
            text = text.replace(varline, varline + '\n  {$ifdef ASTRA_SLICE_CACHE}LDefault: Pointer;{$endif}')
        text = text.replace(start, init + start)
        old = '''    LCodePage := GetTypeData(TypeInfo(TKey))^.CodePage;
    if ((LCodePage = CP_UTF8) or (LCodePage = CP_NONE)) and
      (TClass(THashFactory) = TDefaultHashFactory) and
      (Pointer(FEqualityComparer) = Pointer(TEqualityComparer<TKey>.Default)) then'''
        new = '''    {$ifdef ASTRA_SLICE_CACHE}
    if (FUtf8SliceDefault <> nil) and (Pointer(FEqualityComparer) = FUtf8SliceDefault) then
    {$else}
''' + old + '''
    {$endif}'''
        assert text.count(old) == 1
        if a.mode == 'lazy':
            new = new.replace('    if (FUtf8SliceDefault <> nil) and (Pointer(FEqualityComparer) = FUtf8SliceDefault) then',
                              '''    LDefault := FUtf8SliceDefault;
    if LDefault = nil then
      LDefault := InitUtf8Slice;
    if (LDefault <> nil) and (Pointer(FEqualityComparer) = LDefault) then''')
        text = text.replace(old, new)
    target = 'astraslice.collections.pas' if name == 'generics.collections.pas' else name
    (a.output / target).write_text(text, encoding='utf-8')
(a.output / 'source_manifest.json').write_text(json.dumps(manifest, indent=2))
for original, target in [
    ('qualification/performance/showcase/dictionary_slice_probe.dpr', 'probe.dpr'),
    ('RTL-test/semantic/dictionary_utf8_slice_semantic.dpr', 'contracts.dpr'),
]:
    text = (root / original).read_text(encoding='utf-8').replace('Generics.Collections', 'AstraSlice.Collections')
    if target == 'probe.dpr' and 'GetTickCount64' in text:
        # Same data and operations; only replace the coarse 15 ms timer.
        text = text.replace('SysUtils, ', 'SysUtils, Diagnostics, ')
        text = text.replace('GetTickCount64', 'TStopwatch.GetTimeStamp')
        text = text.replace("' milliseconds=', Elapsed", "' nanoseconds=', (Elapsed * 1000000000) div UInt64(TStopwatch.Frequency)")
    (a.output / target).write_text(text, encoding='utf-8')
