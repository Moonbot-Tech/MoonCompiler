"""Check "uses export" (re-exported units) and --project-uses (project-wide
uses): what the users of a unit see, which name wins, the errors, and the
recompilation of a user when a passed-on unit changes."""

import argparse
import os
import re
from pathlib import Path
import shutil
import subprocess
import time

HERE = Path(__file__).resolve().parent
FLAGS = 0x08000000 if os.name == 'nt' else 0

# id, program source, extra compiler options, expected output lines - or, as
# a string 'error: <text>', a compile error whose message contains <text>
CASES = [
    # A unit passes the units of its interface uses clause on.
    ('uses-export', 'reexp_main.pas', [],
     ['bundle A onlyA 7 B']),
    # "export" before a later unit passes on that unit only.
    ('uses-export-item', 'reexp_partial.pas', [],
     ['B']),
    ('uses-export-item-only', 'reexp_partial_bad.pas', [],
     'error: Identifier not found "TReexpA"'),
    # Nothing to pass on from the implementation uses clause.
    ('uses-export-implementation', 'reexp_impl_bad.pas', [],
     'error: A used unit can be re-exported ("export ReexpA") only in the interface uses clause'),
    # A unit used only for names it passes on (ReexpPartial declares none)
    # is no unused unit, and neither is a unit passed on (ReexpB in
    # ReexpPartial). ReexpA, used there and not passed on, is.
    ('uses-export-no-unused-hint', 'reexp_partial.pas', ['-vh'],
     ['B']),
    # --project-uses: a uses clause for every unit and program.
    ('project-uses', 'projuses_main.pas', ['--project-uses=ReexpBundle'],
     ['bundleonlyA1 bundle']),
    # With -B the units the project unit is built from are compiled in the
    # same run; they do not get it (that would be a circular reference).
    ('project-uses-build-all', 'projuses_main.pas', ['-B', '--project-uses=ReexpBundle'],
     ['bundleonlyA1 bundle']),
]


def compile_case(compiler, config, work, options, source):
    command = [str(compiler), '-n', '@' + str(config), '-Munleashed', *options,
               '-FU' + str(work), '-FE' + str(work), '-Fu' + str(work), str(work / source)]
    compiled = subprocess.run(command, cwd=work, capture_output=True, timeout=120, creationflags=FLAGS)
    log = (compiled.stdout + compiled.stderr).decode(errors='replace')
    return compiled.returncode, log


def run_exe(work, source):
    exe = (work / Path(source).stem).with_suffix('.exe' if os.name == 'nt' else '')
    ran = subprocess.run([str(exe)], cwd=work, capture_output=True, timeout=60, creationflags=FLAGS)
    return ran.returncode, [l.strip() for l in ran.stdout.decode(errors='replace').splitlines() if l.strip()]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    compiler, config = args.compiler.resolve(), args.config.resolve()
    failures = []

    for case_id, source, options, expected in CASES:
        work = output / case_id
        work.mkdir()
        for unit in HERE.glob('*.pas'):
            shutil.copy2(unit, work / unit.name)
        code, log = compile_case(compiler, config, work, options, source)
        (work / 'compile.log').write_text(log, encoding='utf-8')
        if isinstance(expected, str):
            wanted = expected[len('error: '):]
            if code == 0:
                failures.append(f'{case_id}: compiles, expected the error {wanted!r}')
            elif wanted not in log:
                failures.append(f'{case_id}: fails, but not with {wanted!r} (see {work / "compile.log"})')
            else:
                print(f'PASS {case_id}')
            continue
        if code != 0:
            failures.append(f'{case_id}: does not compile (see {work / "compile.log"})')
            continue
        if '-vh' in options and re.search(r'Unit "(ReexpPartial|ReexpB)" not used', log):
            failures.append(f'{case_id}: an unused-unit hint for a unit used through what it passes on')
            continue
        exit_code, got = run_exe(work, source)
        if exit_code != 0 or got != expected:
            failures.append(f'{case_id}: exit {exit_code}, output {got}, expected {expected}')
        else:
            print(f'PASS {case_id}')

    # A user of the bundle records the passed-on units: when the interface of
    # one changes, the user is compiled again although it names the bundle only.
    case_id = 'uses-export-recompile'
    work = output / case_id
    work.mkdir()
    for unit in HERE.glob('*.pas'):
        shutil.copy2(unit, work / unit.name)
    code, log = compile_case(compiler, config, work, [], 'reexp_user_main.pas')
    user_ppu = work / 'reexpuser.ppu'
    if code != 0 or not user_ppu.exists():
        failures.append(f'{case_id}: does not compile ({log[-500:]})')
    else:
        before = user_ppu.stat().st_mtime_ns
        time.sleep(1.1)
        text = (work / 'ReexpA.pas').read_text(encoding='utf-8')
        (work / 'ReexpA.pas').write_text(text.replace('X: Integer;', 'X: Integer;\n    Y: Integer;'), encoding='utf-8')
        code, log = compile_case(compiler, config, work, [], 'reexp_user_main.pas')
        if code != 0:
            failures.append(f'{case_id}: does not compile after the change ({log[-500:]})')
        elif user_ppu.stat().st_mtime_ns == before:
            failures.append(f'{case_id}: the user of the bundle was not compiled again')
        else:
            print(f'PASS {case_id}')

    print(f'USES_EXPORT_GATE {"OK" if not failures else "FAIL"} cases={len(CASES) + 1} failures={len(failures)}')
    for failure in failures:
        print('FAIL', failure)
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
