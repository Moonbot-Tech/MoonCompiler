#!/usr/bin/env python3
"""A repeated command-line pin retains its priority over a later config pin."""

import argparse
import json
import os
from pathlib import Path
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=True)
    for name, value in (('first', 17), ('second', 23)):
        directory = root / name
        directory.mkdir(exist_ok=True)
        source = directory / 'Chosen.pas'
        source.write_text(
            'unit Chosen; interface function Value: Integer; implementation\n'
            f'function Value: Integer; begin Result := {value} end; end.\n',
            encoding='utf-8')
        (root / (name + '.cfg')).write_text(f'--pinned-unit=Chosen={source}\n', encoding='utf-8')
    program = root / 'probe.dpr'
    program.write_text('program probe; uses Chosen; begin Writeln(Value) end.\n', encoding='utf-8')
    first = f'--pinned-unit=Chosen={root / "first/Chosen.pas"}'
    second = f'--pinned-unit=Chosen={root / "second/Chosen.pas"}'
    first_config = '@' + str(root / 'first.cfg')
    second_config = '@' + str(root / 'second.cfg')
    cases = (
        ('same_then_conflict', [first_config, first, second_config], '17'),
        ('changed_then_conflict', [second_config, first, second_config], '17'),
        ('command_first', [first, second_config], '17'),
        ('config_conflict', [first_config, second_config], None),
        ('command_last_wins', [first_config, first, second], '23'),
        ('same_config_twice', [first_config, first_config], '17'),
    )
    results = []
    for level in ('O-', 'O2', 'O3'):
        for name, options, expected in cases:
            output = root / (level + '-' + name)
            output.mkdir(exist_ok=True)
            command = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
                       '-Mdelphi', '-dMOONCOMPILER_VANILLA_RUNTIME', '-' + level,
                       '-FU' + str(output), '-FE' + str(output), *options, str(program)]
            built = subprocess.run(command, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, encoding='utf-8', errors='replace', timeout=60)
            (output / 'compile.log').write_text(built.stdout, encoding='utf-8')
            actual = None
            run_code = None
            if built.returncode == 0:
                executable = output / ('probe.exe' if os.name == 'nt' else 'probe')
                run = subprocess.run([str(executable)], cwd=root, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, timeout=30)
                actual, run_code = run.stdout.strip(), run.returncode
            if expected is None:
                passed = built.returncode != 0 and 'Illegal parameter' in built.stdout
            else:
                passed = built.returncode == 0 and run_code == 0 and actual == expected
            results.append(dict(case=name, level=level, command=command, build_rc=built.returncode,
                                run_rc=run_code, actual=actual, expected=expected, passed=passed))
            print(level, name, 'PASS' if passed else 'FAIL', flush=True)
    (root / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    passed = all(row['passed'] for row in results)
    print('PIN_PRECEDENCE_GATE_' + ('PASS' if passed else 'FAIL'), len(results))
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
