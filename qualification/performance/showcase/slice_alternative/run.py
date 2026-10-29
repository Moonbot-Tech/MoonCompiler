"""Paired copied-control/cache runs; fresh build directory per variant."""
import argparse
import ctypes
import json
import os
import statistics
import subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--work', type=Path, required=True)
p.add_argument('--compiler', required=True)
p.add_argument('--config', required=True)
p.add_argument('--cpu', type=int, default=4)
p.add_argument('--pairs', type=int, default=5)
a = p.parse_args()
if os.name == 'nt':
    k = ctypes.windll.kernel32
    k.GetCurrentProcess.restype = ctypes.c_void_p
    k.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    assert k.SetProcessAffinityMask(k.GetCurrentProcess(), 1 << a.cpu)

def run(cmd):
    if os.name != 'nt':
        cmd = ['taskset', '-c', str(a.cpu), *cmd]
    return subprocess.run(cmd, cwd=a.work, capture_output=True, text=True, timeout=120)

exe = '.exe' if os.name == 'nt' else ''
for variant in ('control', 'cache'):
    dest = a.work / variant
    dest.mkdir(exist_ok=False)
    flags = ['-dASTRA_SLICE_CACHE'] if variant == 'cache' else []
    for prog in ('probe', 'contracts'):
        cmd = [a.compiler, '-n', '@' + a.config, '-dRELEASE', '-Xs-',
               '-Fu' + str(dest), '-Fu' + str(a.work), '-FU' + str(dest), '-FE' + str(dest),
               *flags, str(a.work / (prog + '.dpr'))]
        r = run(cmd)
        (dest / (prog + '-build.log')).write_text(r.stdout + r.stderr)
        assert r.returncode == 0, r.stdout[-3000:]
    r = run([str(dest / ('contracts' + exe))])
    (dest / 'contracts.log').write_text(r.stdout + r.stderr)
    assert r.returncode == 0 and 'DICTIONARY_UTF8_SLICE_OK' in r.stdout, r.stdout + r.stderr
    print(variant, r.stdout.strip(), flush=True)

rows = []
with (a.work / 'raw.jsonl').open('w') as f:
    for pair in range(a.pairs):
        for variant in (('control', 'cache') if pair % 2 == 0 else ('cache', 'control')):
            r = run([str(a.work / variant / ('probe' + exe))])
            assert r.returncode == 0, r.stderr
            for line in r.stdout.splitlines():
                row = {k: int(v) for k, v in (part.split('=') for part in line.split())}
                row.update(pair=pair, variant=variant)
                rows.append(row)
                f.write(json.dumps(row) + '\n')
            f.flush()
    for variant in ('control', 'cache'):
        for mode in (0, 1):
            values = [r['nanoseconds'] / 1e6 for r in rows if r['variant'] == variant and r['mode'] == mode]
            print(variant, mode, 'median_ms', statistics.median(values), 'range', min(values), max(values))
