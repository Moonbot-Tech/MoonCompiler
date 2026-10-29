"""Build and measure storage candidates with identical owning-pair consumers."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--compiler', required=True)
p.add_argument('--config', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--cpu', type=int)
p.add_argument('--pairs', type=int, default=5)
p.add_argument('--quick', action='store_true')
p.add_argument('--kinds', default='rtl,slots,split,mirror,dense')
a = p.parse_args()
if a.cpu is not None and os.name == 'nt':
    import ctypes
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    if not kernel.SetProcessAffinityMask(kernel.GetCurrentProcess(), 1 << a.cpu):
        raise ctypes.WinError(ctypes.get_last_error())
a.output.mkdir(parents=True, exist_ok=False)
source = Path(__file__).with_name('string_storage_probe.dpr')
all_variants = {'rtl': ['RTL_BASELINE'], 'slots': [], 'split': ['SPLIT'], 'mirror': ['MIRROR'], 'dense': ['DENSE']}
variants = {v: all_variants[v] for v in a.kinds.split(',')}
(a.output / 'manifest.json').write_text(json.dumps({
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'compiler_sha256': hashlib.sha256(Path(a.compiler).read_bytes()).hexdigest(),
    'config': Path(a.config).read_text(), 'platform': platform.platform(),
    'cpu': a.cpu, 'pairs': a.pairs, 'quick': a.quick,
}, indent=2))
binaries = {}
for encoding, variant in itertools.product(('utf8', 'utf16'), variants):
    directory = a.output / f'{variant}-{encoding}'
    directory.mkdir()
    defines = variants[variant] + (['UTF16'] if encoding == 'utf16' else [])
    command = [a.compiler, '-n', '@' + a.config, '-dRELEASE', '-FU' + str(directory),
               '-FE' + str(directory), *['-d' + d for d in defines], str(source)]
    binary = directory / ('string_storage_probe.exe' if os.name == 'nt' else 'string_storage_probe')
    r = subprocess.run(command, capture_output=True, text=True)
    (directory / 'build.log').write_text(r.stdout + r.stderr)
    if r.returncode:
        raise RuntimeError(f'Build failed: {directory}')
    r = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
    (directory / 'contracts.log').write_text(r.stdout + r.stderr)
    assert r.returncode == 0 and 'STRING_STORAGE_CONTRACTS PASS' in r.stdout, directory
    binaries[encoding, variant] = binary
    print('built', encoding, variant, flush=True)
with (a.output / 'raw.jsonl').open('x') as raw:
    for pair in range(a.pairs):
        for encoding, count, profile, hit, same in itertools.product(
                ('utf8', 'utf16'), (3742, 100000), (0,) if a.quick else (0, 1, 2),
                (90,) if a.quick else (0, 90, 100), (0,) if a.quick else (0, 1)):
            order = list(variants)
            order = order[pair % len(order):] + order[:pair % len(order)]
            checksums = set()
            for variant in order:
                command = [str(binaries[encoding, variant]), str(count), str(profile), str(hit), '5', str(same)]
                if a.cpu is not None and os.name != 'nt':
                    command = ['taskset', '-c', str(a.cpu), *command]
                r = subprocess.run(command, capture_output=True, text=True, timeout=30)
                if r.returncode:
                    raise RuntimeError(f'{command}\n{r.stdout}\n{r.stderr}')
                row = json.loads(r.stdout)
                row.update(pair=pair)
                raw.write(json.dumps(row) + '\n')
                raw.flush()
                checksums.add((row['checksum'], row['enum_checksum']))
                print(encoding, count, profile, hit, same, variant,
                      round(row['lookup_ns'] / 1e6, 2), round(row['enum_ns'] / 1e6, 2), flush=True)
            assert len(checksums) == 1, checksums
