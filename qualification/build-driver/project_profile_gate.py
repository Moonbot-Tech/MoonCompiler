#!/usr/bin/env python3
"""Compile and execute project-profile precedence, path and phase contracts."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess


def check_project_profile(compiler: Path, root: Path, baseline: bool = False) -> str:
    root.mkdir(parents=True, exist_ok=True)
    profile_dir = root / 'shared профили'
    source_dir = root / 'source'
    cwd = root / 'caller'
    for directory in (profile_dir, source_dir, cwd):
        directory.mkdir(parents=True, exist_ok=True)

    def write(path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def unit(path: Path, name: str, value: int) -> None:
        write(path / (name+'.pas'), f'unit {name}; interface const Marker={value}; implementation end.\n')

    unit(source_dir, 'Surface', 10)
    unit(profile_dir/'first', 'Replacement', 20)
    unit(profile_dir/'second', 'Replacement', 30)
    unit(cwd/'override', 'Replacement', 40)
    unit(cwd/'override', 'OverrideUnit', 50)
    for directory, value in [('first', 21), ('second', 31)]:
        write(profile_dir/directory/'marker.inc', f'const IncludeMarker={value};\n')
    write(cwd/'override'/'marker.inc', 'const IncludeMarker=41;\n')
    write(source_dir/'source-marker'/'origin.inc', 'const SourceMarker=1;\n')
    source = source_dir/'probe.dpr'
    write(source, "program probe; uses Surface; {$i marker.inc} {$i origin.inc}\n"
          "begin WriteLn(Marker, ':', IncludeMarker, ':', SourceMarker);\n"
          "{$ifdef RELEASE}WriteLn('RELEASE');{$else}WriteLn('DEBUG');{$endif}\n"
          "{$ifdef DEBUG}WriteLn('DEBUG_DEFINED');{$endif}\n"
          "{$ifdef EARLY_OVERRIDE}WriteLn('EARLY_OVERRIDE');{$endif}\n"
          "{$ifdef INCLUDED}WriteLn('INCLUDED');{$endif}\n"
          "{$ifdef FROM_AUTO}{$fatal explicit profile must replace auto}{$endif}\nend.\n")
    profile = profile_dir/'shared.mooncompiler'
    paths = '-Fufirst\n-Fusecond\n-Fifirst\n-Fisecond\n-Fi$PROJECTDIR/source-marker\n-UaSurface=Replacement\n'
    write(profile, paths)
    count = 0

    def run(name: str, args: list[str], expected: str | None,
            working: Path = cwd, env: dict[str,str] | None = None,
            executable: Path | None = None, failure: str = '',
            profile_outputs: bool = False, frontend: bool = False) -> str:
        nonlocal count
        out = root/name
        out.mkdir(exist_ok=True)
        driver = compiler.with_name('fpc.exe' if os.name == 'nt' else 'fpc') if frontend else compiler
        outputs = [] if profile_outputs else [f'-FU{out}', f'-FE{out}']
        command = [str(driver), '-B', *outputs, *args, str(source)]
        result = subprocess.run(command, cwd=working, env=env, text=True, encoding='utf-8',
                                errors='replace', stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        write(out/'compile.log', result.stdout)
        if expected is None:
            assert result.returncode != 0 and failure in result.stdout, (name, result.stdout)
        else:
            assert result.returncode == 0, (name, result.stdout)
            exe = executable or out/('probe.exe' if os.name == 'nt' else 'probe')
            execution = subprocess.run([str(exe)], text=True, capture_output=True, timeout=15)
            write(out/'run.log', execution.stdout+execution.stderr)
            assert execution.returncode == 0 and execution.stdout.strip() == expected, (name,execution.stdout,execution.stderr)
        count += 1
        return result.stdout

    # Ordinary @files must keep configuration aliases and reverse path order.
    run('response', ['@'+str(profile)], '10:31:1\nDEBUG\nDEBUG_DEFINED', working=profile_dir)
    automatic = source.with_suffix('.mooncompiler')
    write(automatic, paths.replace('-Fufirst', '-Fu'+str(profile_dir/'first'))
          .replace('-Fusecond','-Fu'+str(profile_dir/'second'))
          .replace('-Fifirst','-Fi'+str(profile_dir/'first'))
          .replace('-Fisecond','-Fi'+str(profile_dir/'second')))
    run('automatic', [], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    if baseline:
        automatic.unlink()
        run('selector-unavailable', ['--project-profile='+str(profile)], None, failure='Illegal parameter')
        return f'PROJECT_PROFILE_BASELINE_PASS {count}'

    write(automatic, '-dFROM_AUTO\n')
    select = '--project-profile='+str(profile)
    run('explicit', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    run('frontend', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED', frontend=True)
    run('relative', ['--project-profile='+os.path.relpath(profile,cwd)], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    run('same-selector-twice', [select,select], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    run('cli-paths', [select,'-Fuoverride','-Fioverride'], '40:41:1\nDEBUG\nDEBUG_DEFINED')
    run('cli-alias', ['-Fuoverride','-UaSurface=OverrideUnit',select], '50:21:1\nDEBUG\nDEBUG_DEFINED')

    write(profile_dir/'early.cfg', '#INCLUDE nested.cfg\n')
    write(profile_dir/'nested.cfg', '-dRELEASE\n-dINCLUDED\n')
    write(profile, '#INCLUDE early.cfg\n'+paths)
    run('early-relative-include', [select], '20:21:1\nRELEASE\nINCLUDED')
    run('cli-release-override', ['-uRELEASE',select], '20:21:1\nDEBUG\nDEBUG_DEFINED\nINCLUDED')
    write(profile_dir/'config'/'phase.cfg', '-dRELEASE\n-dINCLUDED\n')
    write(profile, '#CFGDIR config\n#INCLUDE phase.cfg\n'+paths)
    # A profile below the caller used to store caller-relative config paths,
    # then search them from the temporarily changed profile directory.
    run('cfgdir-under-caller', [select], '20:21:1\nRELEASE\nINCLUDED', working=root)
    run('cfgdir-cli-override', [select,'-uRELEASE'], '20:21:1\nDEBUG\nDEBUG_DEFINED\nINCLUDED', working=root)
    write(profile, '#IFDEF CHOICE\n#INCLUDE early.cfg\n#ELSE\n-dEARLY_OVERRIDE\n#ENDIF\n'+paths)
    run('conditional-include', [select,'-dCHOICE'], '20:21:1\nRELEASE\nINCLUDED')
    run('conditional-else', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED\nEARLY_OVERRIDE')
    write(profile, '#IFDEF LINUX\n-dPLATFORM_OK\n#ELSE\n#IFDEF WINDOWS\n-dPLATFORM_OK\n#ENDIF\n#ENDIF\n'
          '#IFNDEF PLATFORM_OK\n--invalid-platform\n#ENDIF\n'+paths)
    run('target-conditional', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    write(profile, paths)
    (profile_dir/'units').mkdir(exist_ok=True)
    (profile_dir/'output').mkdir(exist_ok=True)
    write(profile, paths+'-FUunits\n-FEoutput\n')
    # CLI outputs win even though they precede the selector.
    run('cli-outputs', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED')
    image = profile_dir/'output'/('probe.exe' if os.name == 'nt' else 'probe')
    run('profile-outputs', [select], '20:21:1\nDEBUG\nDEBUG_DEFINED', profile_outputs=True, executable=image)
    assert (profile_dir/'units'/'Replacement.ppu').is_file(), 'profile -FU is not relative to the profile'
    write(profile, paths)
    run('missing', ['--project-profile='+str(profile_dir/'absent.mooncompiler')], None, failure='Unable to open file')
    run('empty', ['--project-profile='], None, failure='Illegal parameter')
    run('directory', ['--project-profile='+str(profile_dir)], None, failure='file')
    run('conflicting', [select,'--project-profile='+str(automatic)], None, failure='Illegal parameter')
    response = cwd/'select.cfg'
    write(response,select+'\n')
    run('late-response', ['@'+str(response)], None, failure='Illegal parameter')
    env = dict(os.environ, MOON_PROFILE_OPTIONS=select)
    run('late-env', ['!MOON_PROFILE_OPTIONS'], None, env=env, failure='Illegal parameter')
    run('env-repeat', [select,'!MOON_PROFILE_OPTIONS'], None, env=env, failure='Illegal parameter')
    write(profile, select+'\n'+paths)
    run('recursive-selector', [select], None, failure='Illegal parameter')
    write(profile, paths+'#INCLUDE absent.cfg\n')
    run('missing-include', [select], None, failure='Unable to open file')
    automatic.unlink()
    write(profile, paths)
    write(source_dir/'early.cfg', '-dRELEASE\n-dINCLUDED\n')
    write(profile, '#INCLUDE $PROJECTDIR/early.cfg\n'+paths)
    run('early-projectdir', [select], '20:21:1\nRELEASE\nINCLUDED')
    run('early-projectdir-override', [select,'-uRELEASE'], '20:21:1\nDEBUG\nDEBUG_DEFINED\nINCLUDED')
    write(automatic, '#INCLUDE early.cfg\n'+paths.replace('-Fufirst', '-Fu'+str(profile_dir/'first'))
          .replace('-Fusecond','-Fu'+str(profile_dir/'second'))
          .replace('-Fifirst','-Fi'+str(profile_dir/'first'))
          .replace('-Fisecond','-Fi'+str(profile_dir/'second')))
    run('automatic-early-include', [], '20:21:1\nRELEASE\nINCLUDED')
    automatic.unlink()
    write(profile,paths)
    return f'PROJECT_PROFILE_GATE_PASS {count}'


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--baseline', action='store_true')
    a = p.parse_args()
    print(check_project_profile(a.compiler.resolve(), a.output.resolve(), a.baseline))
