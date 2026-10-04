#!/usr/bin/env python3
"""Keep the product -Xt boundary explicit and the dynamic control functional."""
import argparse
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
DIAGNOSTIC = 'Static linking (-Xt) is unsupported by the product Linux RTL'


def check(compiler: Path, results: Path, cwd: Path) -> str:
    if os.name == 'nt':
        return 'static Linux contract: Linux only'
    results.mkdir(parents=True)
    for profile in ('DEBUG', 'RELEASE'):
        for static in (False, True):
            out = results / (profile + ('-static' if static else '-dynamic'))
            out.mkdir()
            image = out / 'probe'
            argv = [str(compiler), '-B', f'-FU{out}', f'-o{image}']
            if profile == 'RELEASE': argv += ['-dRELEASE']
            if static: argv += ['-Xt']
            run = subprocess.run(argv + [str(HERE / 'static_linux_contract.dpr')],
                                 cwd=cwd, capture_output=True, text=True)
            (out / 'compile.log').write_text(run.stdout + run.stderr)
            if static:
                assert run.returncode != 0 and DIAGNOSTIC in run.stdout + run.stderr, run.stdout + run.stderr
                assert not image.exists(), 'unsupported static product was linked'
            else:
                assert run.returncode == 0, run.stdout + run.stderr
                run = subprocess.run([str(image)], cwd=out, capture_output=True, text=True, timeout=30)
                (out / 'run.log').write_text(run.stdout + run.stderr)
                assert run.returncode == 0 and run.stdout.strip() == 'STATIC_DYNAMIC_CONTROL_PASS', run.stdout + run.stderr
    return 'STATIC_LINUX_BOUNDARY_PASS rejection and dynamic threads/exceptions, both profiles'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--results', type=Path, required=True)
    args = parser.parse_args()
    print(check(args.compiler.resolve(), args.results.resolve(), Path.cwd()))
