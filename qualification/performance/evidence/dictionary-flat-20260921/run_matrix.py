#!/usr/bin/env python3
"""run_matrix.py - A/B of dict_bench executables over scenarios and placement families.

    python run_matrix.py --variants baseline,candidate --out results/matrix.json
        [--procs 5] [--fillers 0,1,2,3] [--exe-extra delphi=path] [--only lookup]

A variant V with filler k is build/dict_bench-V-fk/dict_bench.exe (see
build.ps1).  Every executable runs each scenario in fresh processes, each
from a fresh copy of the image; the per-process number is the median over
the program's 11 samples of thread cycles per operation (the cycle count
includes the benchmark loop itself: `Index mod FillCount` is an idiv).  Per
scenario and variant the report gives the median over fillers of the
per-filler medians, plus the min..max over fillers - the placement lottery
amplitude - and the change against the first variant.  The digest column
says whether the variants computed the same result.
"""
import argparse
import json
import shutil
import statistics
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

SCENARIOS = [
    ('update', 256, 25, 'int', 'default'),
    ('update', 4096, 50, 'int', 'default'),
    ('lookup', 256, 25, 'int', 'default'),
    ('lookup', 4096, 50, 'int', 'default'),
    ('miss', 4096, 50, 'int', 'default'),
    ('insert', 1048576, 25, 'int', 'default'),
    ('mixed', 1048576, 25, 'int', 'default'),
    ('update', 64, 25, 'int', 'collision'),
    ('lookup', 256, 50, 'str', 'default'),
    ('lookup', 4096, 50, 'str', 'default'),
    ('update', 256, 50, 'str', 'default'),
    ('miss', 256, 50, 'str', 'default'),
    ('insert', 262144, 25, 'str', 'default'),
    ('lookup', 4096, 50, 'i64', 'default'),
    ('update', 4096, 50, 'i64', 'default'),
    ('lookup', 1024, 50, 'obj', 'default'),
    ('update', 1024, 50, 'obj', 'default'),
    # sequential integer keys in tables beyond L1: the arithmetic-progression
    # population where the linear CRC was a perfect hash
    ('lookup', 16384, 50, 'int', 'default'),
    ('miss', 16384, 50, 'int', 'default'),
]


def fields(line):
    return dict(token.split('=', 1) for token in line.split()[1:] if '=' in token)


def run_fresh(executable, scenario):
    with tempfile.TemporaryDirectory(prefix='mx-', dir=executable.parent) as d:
        image = Path(d) / executable.name
        shutil.copy2(executable, image)
        cmd = [str(image), *(str(x) for x in scenario)]
        out = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300).stdout
    if 'DICT_END' not in out:
        raise RuntimeError('failed: %s\n%s' % (cmd, out[-1500:]))
    rows = [fields(l) for l in out.splitlines() if l.startswith('DICT_SAMPLE ')]
    ops = int(rows[0]['operations'])
    return statistics.median(int(r['thread_cycles']) / ops for r in rows), sorted({r['digest'] for r in rows})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--procs', type=int, default=5)
    ap.add_argument('--fillers', default='0,1,2,3')
    ap.add_argument('--variants', default='baseline,candidate')
    ap.add_argument('--program', default='dict_bench')
    ap.add_argument('--exe-extra', action='append', default=[],
                    help='tag=path of an extra executable (e.g. a Delphi build), measured as one placement')
    ap.add_argument('--only', default='', help='substring filter on scenario names')
    args = ap.parse_args()
    fillers = args.fillers.split(',')
    variants = args.variants.split(',')
    exes = {}
    for v in variants:
        for f in fillers:
            exes[(v, f)] = HERE / 'build' / ('%s-%s-f%s' % (args.program, v, f)) / (args.program + '.exe')
    for e in args.exe_extra:
        tag, path = e.split('=', 1)
        exes[(tag, '0')] = Path(path)
        variants.append(tag)
    for path in exes.values():
        if not path.is_file():
            raise SystemExit('missing executable: %s' % path)
    results = {}
    lines = []
    for sc in SCENARIOS:
        name = '%s-c%d-f%d-%s-%s' % sc
        if args.only and args.only not in name:
            continue
        per = {}
        digests = {}
        for p in range(args.procs):
            keys = list(exes)
            if p % 2:
                keys.reverse()
            for key in keys:
                med, dg = run_fresh(exes[key], sc)
                per.setdefault(key, []).append(med)
                digests.setdefault(key[0], set()).update(dg)
        results[name] = {}
        line = '%-32s' % name
        base_med = None
        for v in variants:
            fam = [statistics.median(per[(v, f)]) for f in fillers if (v, f) in per]
            m = statistics.median(fam)
            results[name][v] = {'median': m, 'fillers': fam, 'digests': sorted(digests[v])}
            if base_med is None:
                base_med = m
            line += '  %s %7.2f [%6.2f..%6.2f]' % (v, m, min(fam), max(fam))
            if v != variants[0]:
                line += ' %+6.1f%%' % (100.0 * (m / base_med - 1))
        dset = {tuple(results[name][v]['digests']) for v in variants[:2]}
        line += '  digest ' + ('same' if len(dset) == 1 else 'DIFFERS')
        print(line, flush=True)
        lines.append(line)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, 'w') as f:
        json.dump(results, f, indent=1)
    with open(out.with_suffix('.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
