#!/usr/bin/env python3
"""Render the templates selected by both RTL stand scripts and use the host config."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def run(command, cwd):
    result = subprocess.run([str(arg) for arg in command], cwd=cwd, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolchain', required=True, type=Path)
    args = parser.parse_args()
    toolchain = args.toolchain.resolve()
    windows = os.name == 'nt'
    binary = toolchain / ('bin/x86_64-win64' if windows else 'bin')
    suffix = '.exe' if windows else ''
    compiler = binary / ('ppcx64' + suffix)
    generator = binary / ('fpcmkcfg' + suffix)
    scripts = ('scripts/Build-RtlProfileStand.ps1', 'scripts/build-rtl-profile-stand.sh')
    with tempfile.TemporaryDirectory(prefix='stand-config-') as temporary:
        work = Path(temporary)
        templates = []
        for script in scripts:
            text = (ROOT / script).read_text(encoding='utf-8-sig')
            names = set(re.findall(r'scripts[/\\]([\w.-]+\.template)', text))
            assert len(names) == 1, (script, names)
            template = ROOT / 'scripts' / names.pop()
            config = work / (Path(script).name + '.cfg')
            run([generator, '-t', template, '-d', 'basepath=stand-template-probe', '-o', config], work)
            assert '-Fustand-template-probe/units/$fpctarget' in config.read_text()
            templates.append(template)

        template = templates[0 if windows else 1]
        for profile, char_size in (('ide', 1), ('product', 2)):
            root = toolchain / 'ide' if profile == 'ide' else toolchain
            base = root if windows else next((root / 'lib/fpc').glob('[0-9]*'))
            config = work / (profile + '.cfg')
            run([generator, '-t', template, '-d', 'basepath=' + str(base), '-o', config], work)
            source = work / (profile + '.dpr')
            source.write_text('program StandConfig; {$mode delphi}\n'
                              f'{{$if SizeOf(Char) <> {char_size}}}{{$fatal wrong ABI}}{{$endif}}\n'
                              "uses SysUtils; begin Writeln(IntToStr(17), ':', SizeOf(Char)) end.\n")
            abi = (['-dMOONCOMPILER_VANILLA_RUNTIME'] if profile == 'ide' else
                   ['-dMOONCOMPILER_UNICODE_DEFAULT', '-dMOONBOT_MM_PROFILE_REQUIRED',
                    '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD',
                    '--pinned-unit=mormot.core.fpcx64mm=' + str(ROOT / 'runtime/mm/mormot.core.fpcx64mm.pas')])
            for level in ('-O-', '-O2', '-O3'):
                output = work / (profile + level)
                output.mkdir()
                run([compiler, '-n', '@' + str(config), *abi, level, '-B', '-FU' + str(output),
                     '-FE' + str(output), source], work)
                assert run([output / (profile + suffix)], work).strip() == f'17:{char_size}'
            source.write_text(source.read_text().replace(f'<> {char_size}', f'<> {3 - char_size}'))
            wrong = subprocess.run([str(compiler), '-n', '@' + str(config), *abi,
                                    '-FU' + str(output), '-FE' + str(output), str(source)],
                                   cwd=work, capture_output=True, text=True)
            assert wrong.returncode != 0 and 'wrong ABI' in wrong.stdout + wrong.stderr
    print('STAND_CONFIG_PASS: both templates; IDE/product at O-/O2/O3; wrong ABI rejected')


if __name__ == '__main__':
    main()
