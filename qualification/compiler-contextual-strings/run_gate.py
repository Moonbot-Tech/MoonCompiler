"""Check contextual string overloads against compiled Delphi 12.2 oracle results."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    command = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
               '-Mdelphiunicode', '-Mimplicitgenerics', '-UaSystem.SysUtils=SysUtils',
               '-UaSystem.Variants=Variants', '-UaSystem.StrUtils=StrUtils']
    fixtures = json.loads(Path(__file__).with_name('oracle.json').read_text(encoding='utf-8'))

    def run(case):
        work = output / case['id']
        work.mkdir()
        source = work / 'Oracle.dpr'
        source.write_text(case['source'], encoding='utf-8')
        flags = case.get('flags', ['-O2', '-dRELEASE'])
        try:
            compiled = subprocess.run(command + flags + ['-FU' + str(work), '-FE' + str(work), str(source)],
                                      cwd=work, capture_output=True,
                                      timeout=30, creationflags=0x08000000 if os.name == 'nt' else 0)
            log = (compiled.stdout + compiled.stderr).decode(errors='replace')
            (work / 'compile.log').write_text(log, encoding='utf-8')
            if not case['compile']:
                rejected_call = any(message in log for message in
                                    ("Error: Can't determine which overloaded function to call",
                                     'Error: Incompatible type'))
                passed = compiled.returncode != 0 and rejected_call and 'Internal error' not in log
                return dict(id=case['id'], passed=passed, compile_exit=compiled.returncode)
            if compiled.returncode:
                return dict(id=case['id'], passed=False, compile_exit=compiled.returncode)
            binary = work / ('Oracle.exe' if os.name == 'nt' else 'Oracle')
            executed = subprocess.run([str(binary)], cwd=work, capture_output=True, timeout=10,
                                      creationflags=0x08000000 if os.name == 'nt' else 0)
            actual = executed.stdout.decode(errors='replace').strip()
            (work / 'run.log').write_bytes(executed.stdout + executed.stderr)
            return dict(id=case['id'], passed=executed.returncode == 0 and actual == case['value'],
                        exit=executed.returncode, actual=actual, expected=case['value'])
        except subprocess.TimeoutExpired as error:
            return dict(id=case['id'], passed=False, error=str(error))

    cases = fixtures['cases']
    if sys.platform == 'linux':
        target = fixtures['linux']
        windows_only = set(target['windows_only_type_identity'])
        cases = [dict(case, **target['expectation_overrides'].get(case['id'], {}))
                 for case in cases if case['id'] not in windows_only]
        print(f'CONTEXTUAL_STRINGS_PLATFORM: {len(windows_only)} Windows-only type-identity cases')
    api_source = Path(__file__).with_name('rtl_calls.dpr').read_text(encoding='utf-8')
    for name, flags in [('debug', ['-O-', '-uRELEASE']), ('release-o2', ['-O2', '-dRELEASE']),
                        ('release-o3', ['-O3', '-dRELEASE'])]:
        cases.append(dict(id='rtl-' + name, source=api_source, flags=flags, compile=True, value='RTL_STRING_OVERLOADS_PASS'))
    with ThreadPoolExecutor(max_workers=4) as pool:
        rows = list(pool.map(run, cases))
    failures = [row for row in rows if not row['passed']]
    (output / 'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    for row in failures[:12]:
        print(row)
    print(f'CONTEXTUAL_STRINGS_{"FAIL" if failures else "PASS"}: {len(rows) - len(failures)}/{len(rows)}')
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
