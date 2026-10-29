"""Archive active source, exact patch, logs and focused disassembly."""
import argparse
import difflib
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--work', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--objdump', default='objdump')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)

def active(text, enabled):
    out = []
    branch = None
    for line in text.splitlines(True):
        if '{$ifdef ASTRA_SLICE_CACHE}' in line and '{$endif}' in line:
            line = line.replace('{$ifdef ASTRA_SLICE_CACHE}', '').replace('{$endif}', '') if enabled else ''
        elif line.strip() == '{$ifdef ASTRA_SLICE_CACHE}':
            branch = enabled
            continue
        elif branch is not None and line.strip() == '{$else}':
            branch = not branch
            continue
        elif branch is not None and line.strip() == '{$endif}':
            branch = None
            continue
        if branch is not False:
            out.append(line)
    return ''.join(out)

patch = []
for name in ('generics.dictionariesh.inc', 'generics.dictionaries.inc'):
    text = (a.work / 'inc' / name).read_text()
    old, new = active(text, False), active(text, True)
    for variant, data in [('control', old), ('cache', new)]:
        dest = a.output / variant
        dest.mkdir(exist_ok=True)
        (dest / name).write_text(data)
    patch.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                     'a/packages/rtl-generics/src/inc/' + name,
                                     'b/packages/rtl-generics/src/inc/' + name))
(a.output / 'candidate.patch').write_text(''.join(patch))
for name in ('source_manifest.json', 'raw.jsonl', 'probe.dpr', 'contracts.dpr', 'extra.dpr',
             'SliceFactory.pas', 'astraslice.collections.pas', 'generics.threadedqueue.inc'):
    source = a.work / name
    if source.exists():
        shutil.copy2(source, a.output / name)
for variant in ('control', 'cache'):
    dest = a.output / variant
    for f in (a.work / variant).glob('*.log'):
        shutil.copy2(f, dest / f.name)
    binary = a.work / variant / 'probe.exe'
    if not binary.exists():
        binary = a.work / variant / 'probe'
    table = subprocess.check_output([a.objdump, '-t', str(binary)], text=True)
    symbols = [line.split()[-1] for line in table.splitlines()
               if 'TRYGETVALUEUTF8$' in line.upper() and 'fin$' not in line]
    assert symbols
    assembly = subprocess.check_output([a.objdump, '-d', str(binary)], text=True)
    chosen = []
    keep = False
    for line in assembly.splitlines():
        header = re.match(r'^[0-9a-fA-F]+ <(.+)>:', line)
        if header:
            keep = header.group(1) in symbols
        if keep:
            chosen.append(line)
    assert chosen
    (dest / 'slice.asm').write_text('\n'.join(chosen) + '\n')
    (dest / 'binary.sha256').write_text(hashlib.sha256(binary.read_bytes()).hexdigest() + '\n')
hashes = {str(f.relative_to(a.output)): hashlib.sha256(f.read_bytes()).hexdigest()
          for f in a.output.rglob('*') if f.is_file() and f.name != 'artifact_hashes.json'}
(a.output / 'artifact_hashes.json').write_text(json.dumps(hashes, indent=2))
