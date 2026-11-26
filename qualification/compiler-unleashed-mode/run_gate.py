"""Check mode marker macros, single-character resourcestrings and the UTF-8
source default of unleashed mode."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent

# id, program source, extra compiler options, expected output lines
CASES = [
    # A unit with its own $MODE must not change the mode markers of the
    # modules compiled after it.
    ('marker-cmdline-unleashed', 'marker_cmdline.pas', ['-Munleashed'],
     ['unit=delphi', 'program=unleashed']),
    ('marker-cmdline-objfpc', 'marker_cmdline.pas', ['-Mobjfpc'],
     ['unit=delphi', 'program=objfpc']),
    ('marker-directive-delphi', 'marker_directive.pas', [],
     ['unit=unleashed', 'program=delphi']),
    # One character outside ASCII is a WideChar constant.
    ('resourcestring-single-char', 'resstr_single_char.pas', [],
     ['1 50696', '1 233', '1 89', '2 50696 50836']),
    # The same with the code page given explicitly, independent of the
    # unleashed UTF-8 default below.
    ('resourcestring-single-char-fc', 'resstr_single_char.pas', ['-FcUTF8'],
     ['1 50696', '1 233', '1 89', '2 50696 50836']),
    # Unleashed reads a source without BOM or -Fc as UTF-8.
    ('utf8-unleashed-default', 'utf8_unleashed.pas', [],
     ['2 54620 44544']),
    # An interpolated string with arguments is a `string`, not an AnsiString.
    ('interpolated-string-unicode', 'interp_unicode.pas', [],
     ['10 44148 46']),
    # Delphi mode keeps the historical ISO-8859-1 default.
    ('utf8-delphi-control', 'utf8_delphi_control.pas', [],
     ['6']),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    flags = 0x08000000 if os.name == 'nt' else 0
    failures = []

    for case_id, source, options, expected in CASES:
        work = output / case_id
        work.mkdir()
        for unit in HERE.glob('*.pas'):
            shutil.copy2(unit, work / unit.name)
        command = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
                   *options, '-FU' + str(work), '-FE' + str(work), '-Fu' + str(work),
                   str(work / source)]
        compiled = subprocess.run(command, cwd=work, capture_output=True, timeout=120,
                                  creationflags=flags)
        log = (compiled.stdout + compiled.stderr).decode(errors='replace')
        (work / 'compile.log').write_text(log, encoding='utf-8')
        if compiled.returncode != 0:
            failures.append(f'{case_id}: does not compile (see {work / "compile.log"})')
            continue
        exe = work / Path(source).stem
        if os.name == 'nt':
            exe = exe.with_suffix('.exe')
        ran = subprocess.run([str(exe)], cwd=work, capture_output=True, timeout=60,
                             creationflags=flags)
        got = [line.strip() for line in ran.stdout.decode(errors='replace').splitlines()
               if line.strip()]
        (work / 'run.log').write_text('\n'.join(got) + '\n', encoding='utf-8')
        if ran.returncode != 0 or got != expected:
            failures.append(f'{case_id}: exit {ran.returncode}, output {got}, expected {expected}')
        else:
            print(f'PASS {case_id}')

    for failure in failures:
        print('FAIL ' + failure)
    print(f'UNLEASHED_MODE_GATE {"FAIL" if failures else "OK"} '
          f'cases={len(CASES)} failures={len(failures)}')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
