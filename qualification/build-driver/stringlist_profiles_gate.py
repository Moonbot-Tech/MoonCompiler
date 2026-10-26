"""Check virtual insertion and object visibility in both installed RTL profiles."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[2]
    windows = os.name == 'nt'
    bin_path = Path('bin/x86_64-win64') if windows else Path('bin')
    suffix = '.exe' if windows else ''
    sources = [
        (root / 'tests/test/units/classes/tstringlistinsertitem.pp', 'ok'),
        (Path(__file__).with_name('stringlist_object_contract.pp'), 'STRINGLIST_OBJECT_CONTRACT_PASS'),
    ]
    for profile in ('product', 'ide'):
        sdk = root / 'toolchain' / ('ide' if profile == 'ide' else '')
        compiler = sdk / bin_path / ('fpc' + suffix)
        config_dir = sdk / bin_path if windows else sdk / 'etc'
        config = config_dir / ('fpc.cfg' if profile == 'ide' else 'moon-base.cfg')
        for optimization in ('-O-', '-O2', '-O3'):
            with tempfile.TemporaryDirectory(prefix='moon-stringlist-') as directory:
                work = Path(directory)
                for source, expected in sources:
                    copied = work / source.name
                    shutil.copy2(source, copied)
                    command = [str(compiler), '-n', '@' + str(config), optimization,
                               '-FU' + str(work), '-FE' + str(work), str(copied)]
                    if profile == 'ide':
                        command.insert(1, '-dTEST_IDE_PROFILE')
                    compiled = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=60)
                    if compiled.returncode:
                        raise RuntimeError(f'{profile} {optimization}: {compiled.stdout}{compiled.stderr}')
                    result = subprocess.run([str(work / (source.stem + suffix))], cwd=work,
                                            capture_output=True, text=True, timeout=15)
                    if result.returncode or result.stdout.strip() != expected:
                        raise RuntimeError(f'{profile} {optimization}: {result.returncode} {result.stdout}{result.stderr}')
                    print(f'PASS {profile} {optimization} {source.stem}', flush=True)
    print('STRINGLIST_PROFILES_PASS 12')


if __name__ == '__main__':
    main()
