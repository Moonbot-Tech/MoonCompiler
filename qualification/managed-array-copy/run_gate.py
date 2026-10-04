#!/usr/bin/env python3
"""Check managed-array acquisition failure and AddRef-only copy contracts."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

def run(command: list[str], directory: Path, name: str) -> str:
    completed = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=90)
    output = completed.stdout + completed.stderr
    (directory / (name + '.log')).write_text(output, encoding='utf-8')
    (directory / (name + '-command.json')).write_text(json.dumps(command, indent=2), encoding='utf-8')
    if completed.returncode:
        raise RuntimeError(f'{name} failed ({completed.returncode}): {directory}')
    return output

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    binary = ROOT / 'toolchain/bin'
    parser.add_argument('--compiler', type=Path, default=binary / ('x86_64-win64/ppcx64.exe' if os.name == 'nt' else 'fpc'))
    parser.add_argument('--config', type=Path, default=(binary / 'x86_64-win64/moon-base.cfg' if os.name == 'nt'
                                                     else ROOT / 'toolchain/etc/moon-base.cfg'))
    parser.add_argument('--output', type=Path, default=ROOT / '.qualification/managed-array-copy-gate')
    parser.add_argument('--unit-path', type=Path, action='append', default=[])
    parser.add_argument('--include-path', type=Path, action='append', default=[])
    args = parser.parse_args()
    compiler, config, output = (p.resolve() for p in (args.compiler, args.config, args.output))
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    for optimization in ('O-', 'O2', 'O3'):
        directory = output / optimization
        directory.mkdir()
        command = [str(compiler), '-n', '@' + str(config), '-' + optimization, '-B',
                   '-FU' + str(directory), '-FE' + str(directory)]
        command.extend('-Fu' + str(p.resolve()) for p in args.unit_path)
        command.extend('-Fi' + str(p.resolve()) for p in args.include_path)
        for name in ('middle_throw', 'l1_contract', 'partial_record', 'mutation_failure', 'insert_owned_failure'):
            run(command + [str(HERE / (name + '.dpr'))], directory, name + '-build')
            executable = directory / (name + ('.exe' if os.name == 'nt' else ''))
            actual = run([str(executable)], directory, name + '-semantic')
            if name == 'middle_throw':
                lines = actual.splitlines()
                if len(lines) != 20 or any('leftover 0 duplicate 0 live_delta 0' not in line for line in lines):
                    raise RuntimeError(f'incomplete acquisition failure matrix: {actual!r}')
            elif name == 'l1_contract':
                if actual.strip() != 'L1_CONTRACT_PASS 44':
                    raise RuntimeError(f'AddRef lifecycle differs: {actual!r}')
            elif name == 'partial_record' and actual.strip() != 'PARTIAL_RECORD TRUE unstarted_finalizers=0':
                raise RuntimeError(f'unstarted record was finalized: {actual!r}')
            elif name in ('mutation_failure', 'insert_owned_failure'):
                checks = 2448 if name == 'mutation_failure' else 222
                if actual.strip() != f'{name.upper()}_PASS {checks}':
                    raise RuntimeError(f'incomplete mutation failure matrix: {actual!r}')
            rows.append({'optimization': optimization, 'case': name,
                         'sha256': hashlib.sha256(executable.read_bytes()).hexdigest()})
    result = {'status': 'pass', 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'config_sha256': hashlib.sha256(config.read_bytes()).hexdigest(), 'rows': rows}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f'MANAGED_ARRAY_COPY_GATE_PASS images={len(rows)} failures=60 lifecycle=132 mutation_checks=8010 output={output}')

if __name__ == '__main__':
    main()
