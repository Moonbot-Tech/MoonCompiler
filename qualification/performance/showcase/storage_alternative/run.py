"""Compile isolated copied-control/hit-first RTL and retain every raw result."""
import argparse
import itertools
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--work', type=Path, required=True)
p.add_argument('--compiler', required=True)
p.add_argument('--config', required=True)
p.add_argument('--cpu', type=int)
p.add_argument('--pairs', type=int, default=3)
p.add_argument('--full', action='store_true')
p.add_argument('--candidate', choices=('hit-first', 'direct-cast', 'fused'), default='fused')
a = p.parse_args()
work = a.work.resolve()
bins = {}

def run(command):
    if a.cpu is not None and os.name != 'nt':
        command = ['taskset', '-c', str(a.cpu), 'nice', '-n', '10', *command]
    return subprocess.run(command, capture_output=True, text=True, timeout=90, cwd=work)

for encoding, candidate in itertools.product(('utf8', 'utf16'), (False, True)):
    name = (a.candidate if candidate else 'control') + '-' + encoding
    directory = work / name
    directory.mkdir(exist_ok=False)
    feature = {'hit-first': 'ASTRA_HIT_FIRST', 'direct-cast': 'ASTRA_DIRECT_CAST', 'fused': 'ASTRA_FUSED'}[a.candidate]
    defines = (['-dUTF16'] if encoding == 'utf16' else []) + (['-d' + feature] if candidate else [])
    compiler = [a.compiler, '-n', '@' + a.config, '-dRELEASE', '-Fu' + str(directory),
                '-Fu' + str(work), '-FU' + str(directory), '-FE' + str(directory), *defines]
    for source in ('storage_alternative_probe', 'contracts'):
        result = run(compiler + [str(work / (source + '.dpr'))])
        (directory / (source + '-build.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, (name, source, result.stdout[-1500:])
        binary = directory / (source + ('.exe' if os.name == 'nt' else ''))
        result = run([str(binary)])
        (directory / (source + '-contracts.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 0 and 'PASS' in result.stdout, (name, result.stdout, result.stderr)
        if source == 'storage_alternative_probe':
            bins[encoding, candidate] = binary
    print('built', name, flush=True)

cases = [(100000, 0, 90, 0)]
if a.full:
    cases = list(itertools.product((3742, 100000), (0, 1, 2), (0, 90, 100), (0, 1)))
with (work / ('full.jsonl' if a.full else 'quick.jsonl')).open('w') as raw:
    for repeat in range(a.pairs):
        for encoding in ('utf8', 'utf16'):
            for count, profile, hit, same in cases:
                checksums = set()
                for candidate in ((False, True) if repeat % 2 == 0 else (True, False)):
                    result = run([str(bins[encoding, candidate]), str(count), str(profile), str(hit), '5', str(same)])
                    assert result.returncode == 0, result.stderr
                    row = json.loads(result.stdout)
                    row['repeat'] = repeat
                    raw.write(json.dumps(row) + '\n')
                    raw.flush()
                    checksums.add((row['checksum'], row['enum_checksum']))
                    print(encoding, count, profile, hit, same, row['variant'],
                          round(row['lookup_ns'] / 1e6, 2), round(row['enum_ns'] / 1e6, 2), flush=True)
                assert len(checksums) == 1
