#!/usr/bin/env python3
"""Verify the expected-exception API using only an installed SDK and its config."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = Path(__file__).resolve().parents[1] / 'suite/tests/smoke/diagnostic_expected.pas'
    shutil.copy2(source, out/source.name)
    results = []
    for profile, options in [('debug', []), ('release', ['-dRELEASE'])]:
        build = out/profile
        build.mkdir()
        p = subprocess.run([str(compiler), '-B', *options, '-FU'+str(build), '-FE'+str(build), source.name],
                           cwd=out, capture_output=True, timeout=120)
        (build/'compile.log').write_bytes(p.stdout + p.stderr)
        if p.returncode:
            raise RuntimeError(f'{profile} compile failed: {build / "compile.log"}')
        executable = build/('diagnostic_expected.exe' if os.name == 'nt' else 'diagnostic_expected')
        for mode in ('rules', 'empty', 'unhandled', 'filtered-av'):
            reports = build/mode
            p = subprocess.run([str(executable), str(reports), mode, '0'], cwd=out, capture_output=True, timeout=30)
            (build/(mode+'.log')).write_bytes(p.stdout+p.stderr)
            assert p.returncode == (1 if mode == 'unhandled' else 0), (profile, mode, p.returncode)
            texts = [p.read_text(encoding='utf-8') for p in reports.glob('*.txt')]
            assert len(texts) == {'rules': 3, 'filtered-av': 1}.get(mode, 0), (profile, mode)
            if mode == 'unhandled':
                assert b'An unhandled exception occurred' in p.stdout+p.stderr and b'expected origin' in p.stdout+p.stderr
            else:
                assert b'EXPECTED_FILTER_PASS' in p.stdout
            assert all(t.endswith('MOON_DIAGNOSTIC_END\n') for t in texts)
            if mode == 'rules':
                hardware = next(t for t in texts if 'title=unexpected AV\n' in t)
                assert 'hardware=True' in hardware and 'HARDWAREORIGIN' in hardware.upper()
            elif mode == 'filtered-av':
                assert 'hardware=False' in texts[0] and 'SOFTWAREORIGIN' in texts[0].upper()
            results.append({'profile': profile, 'mode': mode, 'reports': len(texts)})
    (out/'summary.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    print(f'DIAGNOSTICS_EXPECTED_ARCHIVE_PASS {len(results)} cases')


if __name__ == '__main__':
    main()
