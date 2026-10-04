#!/usr/bin/env python3
"""Check process-exit I/O with real redirected files (pipes hide buffering)."""
import argparse
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--results', required=True, type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / 'tests/smoke/exit_runtime_contract.pas'
    compiler, config = args.compiler.resolve(), args.config.resolve()
    args.results.mkdir(parents=True, exist_ok=False)
    flags = {'creationflags': 0x08000000} if subprocess._mswindows else {}
    for option in ('O-', 'O2', 'O3'):
        out = args.results / option
        out.mkdir()
        exe = out / ('exit_runtime_contract.exe' if subprocess._mswindows else 'exit_runtime_contract')
        with (out / 'compile.log').open('wb') as log:
            subprocess.run([str(compiler), '-n', '@' + str(config), '-B', '-' + option,
                            '-FU' + str(out), '-FE' + str(out), '-o' + str(exe), str(source)],
                           cwd=out, stdout=log, stderr=subprocess.STDOUT, check=True, **flags)
        for mode in ('main', 'thread', 'pending', 'runerror', 'runerror-stderr'):
            stdout, stderr = out / (mode + '.stdout'), out / (mode + '.stderr')
            with stdout.open('wb') as output, stderr.open('wb') as errors:
                result = subprocess.run([str(exe), mode], cwd=out, stdin=subprocess.DEVNULL,
                                        stdout=output, stderr=errors, timeout=30, **flags)
            output, errors = stdout.read_bytes(), stderr.read_bytes()
            if mode.startswith('runerror'):
                message, empty = (errors, output) if mode.endswith('stderr') else (output, errors)
                passed = result.returncode == 77 and message.startswith(b'Runtime error 77 at ') and not empty
            else:
                expected = {'main': b'MAIN_BUFFER', 'thread': b'MAIN_BUFFERWORKER_BUFFER',
                            'pending': b'PENDING_IO=2\n'}[mode]
                passed = result.returncode == 0 and output.replace(b'\r\n', b'\n') == expected and not errors
            if not passed:
                raise SystemExit(f'{option}/{mode} failed: exit={result.returncode}, files in {out}')
    print('EXIT_RUNTIME_GATE_PASS')


if __name__ == '__main__':
    main()
