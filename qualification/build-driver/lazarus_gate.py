"""Build the pinned IDE and exercise its actual signed-hash adapter with checks on."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def check_hash(root, fixture):
    source = root / 'lazarus-src'
    windows = os.name == 'nt'
    target = 'x86_64-win64' if windows else 'x86_64-linux'
    compiler = root / ('toolchain/ide/bin/x86_64-win64/fpc.exe' if windows else 'toolchain/ide/bin/fpc')
    unit_paths = [source / base / target for base in (
        'components/lazedit/lib', 'components/lazutils/lib', 'lcl/units', 'packager/units')]
    with tempfile.TemporaryDirectory(prefix='moon-lazarus-hash-') as directory:
        work = Path(directory)
        shutil.copy2(fixture, work / fixture.name)
        # Recompile this real upstream unit with range checks, not its O3 PPU.
        shutil.copy2(source / 'components/lazedit/lazedithighlighterutils.pas', work)
        binary = work / ('lazarus_hash_contract.exe' if windows else 'lazarus_hash_contract')
        command = [str(compiler), '-Cr', '-Co', '-Sa', '-Fu' + str(work), '-FU' + str(work),
                   '-FE' + str(work)] + ['-Fu' + str(path) for path in unit_paths]
        subprocess.run(command + [str(work / fixture.name)], cwd=work, check=True)
        result = subprocess.run([str(binary)], cwd=work, check=True, capture_output=True, text=True, timeout=30)
        if result.stdout.strip() != 'LAZARUS_HASH_CONTRACT_PASS':
            raise RuntimeError(result.stdout + result.stderr)
        print(result.stdout.strip(), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--shell', default='pwsh')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    build = [args.shell, '-NoProfile', '-File', str(root / 'build.ps1')] if os.name == 'nt' else ['bash', str(root / 'build')]
    subprocess.run(build + ['lazarus'], cwd=root, check=True)
    check_hash(root, Path(__file__).with_name('lazarus_hash_contract.lpr'))


if __name__ == '__main__':
    main()
