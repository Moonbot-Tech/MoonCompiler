#!/usr/bin/env python3
"""Real-process Unicode output contract; no shell, Delphi, network or test framework."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
CASES = (
    'api-array api-cmdline api-indir api-indir-cmdline api-indir-exit '
    'api-forbidden-options api-nonzero api-missing api-indir-missing api-merged '
    'loop-ascii loop-even loop-utf8 loop-nul loop-empty loop-stderr-only '
    'loop-stderr-utf8 loop-merged loop-large-both loop-split loop-virtual '
    'loop-callback loop-missing loop-exception loop-finished-failure loop-reuse '
    'stream-stdout stream-stderr stream-stderr-only stream-partial '
    'stream-empty stream-append stream-zero-loops stream-blocking-channel stream-merged '
    'stream-short-write stream-zero-write stream-throw-write '
    'buffer-plain buffer-prefix buffer-alias buffer-staged buffer-stderr-staged '
    'buffer-empty buffer-zero-loops default-class'
).split()
ENCODING_CASES = ['encoding-default', 'encoding-explicit', 'encoding-reuse', 'encoding-override']
UNITS = {
    'Process': [],
    'ProcessUnicode': ['-dUNIT_UNICODE'],
    'System.Process': ['-dUNIT_NAMESPACED'],
    'System.Process.Unicode': ['-dUNIT_NAMESPACED', '-dUNIT_UNICODE'],
}


def run(command, cwd, log, timeout, marker=None):
    """Kill only this invocation and its children if a pipe regression deadlocks."""
    started = time.monotonic()
    options = {'creationflags': 0x08000000 | 0x00000200} if os.name == 'nt' else {'start_new_session': True}
    with log.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, **options)
        try:
            code = process.wait(timeout=timeout)
            status = 'pass' if code == 0 else 'fail'
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
                               creationflags=0x08000000)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
            code, status = None, 'timeout'
    result = {'status': status, 'exit_code': code, 'seconds': round(time.monotonic() - started, 3),
              'log': str(log), 'command': command}
    if status == 'pass' and marker and log.read_text(encoding='utf-8', errors='replace').splitlines().count(marker) != 1:
        result.update(status='fail', reason='expected exactly one success marker: ' + marker)
    return result


def overlay(source, destination):
    source = source.resolve()
    if (source / 'packages/fcl-process/src').is_dir():
        source = source / 'packages/fcl-process/src'
    if source.is_file():
        source = source.parent
    destination.mkdir()
    for name in ('process.pp', 'processunicode.pp', 'processbody.inc'):
        text = (source / name).read_text(encoding='utf-8-sig')
        # Product build-linux.py performs the same platform normalization.
        if name == 'process.pp' and os.name != 'nt':
            text = text.replace('{$define windows}', '')
        (destination / name).write_text(text, encoding='utf-8')
    for name, include in (('System.Process.pp', 'process.pp'),
                          ('System.Process.Unicode.pp', 'processunicode.pp')):
        unit = name[:-3]
        (destination / name).write_text(
            f'unit {unit};\n{{$DEFINE FPC_DOTTEDUNITS}}\n{{$i {include}}}\n', encoding='utf-8')
    # Standalone candidates may carry only the changed include plus package wrappers.
    # --support explicitly supplies unchanged platform includes in that situation.
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--source', type=Path, help='optional package src/repository/candidate overlay')
    parser.add_argument('--support', type=Path, help='unchanged fcl-process src when candidate is partial')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--mode', action='append', choices=('Debug', 'Release'))
    parser.add_argument('--unit', action='append', choices=tuple(UNITS))
    parser.add_argument('--codepage-api', action='store_true', help='also require and test OutputCodePage property')
    parser.add_argument('--case', action='append', choices=CASES + ENCODING_CASES)
    parser.add_argument('--timeout', type=float, default=6)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    modes = args.mode or ['Debug', 'Release']
    packaged_units = ['Process', 'ProcessUnicode'] if os.name == 'nt' else ['Process']
    units = args.unit or (list(UNITS) if args.source else packaged_units)
    cases = args.case or CASES + (ENCODING_CASES if args.codepage_api else [])
    if any(case in ENCODING_CASES for case in cases) and not args.codepage_api:
        parser.error('encoding cases require --codepage-api')
    source = overlay(args.source, output / 'overlay') if args.source else None
    support = args.support.resolve() if args.support else source
    records = []
    for mode in modes:
        for unit in units:
            build = output / (mode + '-' + unit)
            build.mkdir()
            (build / 'units').mkdir()
            command = [str(compiler), '-B', '-dRELEASE' if mode == 'Release' else '-dDEBUG',
                       *UNITS[unit], f'-FU{build / "units"}', f'-FE{build}',
                       '-oProcessOutputContract' + ('.exe' if os.name == 'nt' else '')]
            if args.codepage_api:
                command.append('-dPROCESS_CODEPAGE')
            if source:
                platform = 'win' if os.name == 'nt' else 'unix'
                command += ['-UaSystem.Pipes=Pipes', '-UaSystem.CTypes=ctypes', '-UaUnixApi.Types=unixtype',
                            '-UaUnixApi.Unix=unix', '-UaUnixApi.Base=baseunix',
                            f'-Fu{output / "overlay"}', f'-Fi{output / "overlay"}',
                            f'-Fi{support}', f'-Fi{support / platform}', f'-Fi{support / "winall"}']
            command.append(str(HERE / 'ProcessOutputContract.dpr'))
            result = run(command, build, build / 'compile.log', 120)
            result.update(mode=mode, unit=unit, case='compile')
            records.append(result)
            if result['status'] != 'pass':
                print(f'FAIL {mode} {unit} compile: {result["log"]}', flush=True)
                continue
            executable = build / ('ProcessOutputContract.exe' if os.name == 'nt' else 'ProcessOutputContract')
            failed = []
            for case in cases:
                result = run([str(executable), case], build, build / (case + '.log'), args.timeout, f'PASS {case}')
                result.update(mode=mode, unit=unit, case=case)
                records.append(result)
                if result['status'] != 'pass':
                    failed.append(f'{case}:{result["status"]}')
            print(f'{mode} {unit}: {len(cases) - len(failed)}/{len(cases)} PASS' +
                  ('; ' + ', '.join(failed) if failed else ''), flush=True)
    (output / 'results.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
    failures = sum(item['status'] != 'pass' for item in records)
    print(f'RUNCOMMAND_GATE {"FAIL" if failures else "PASS"} checks={len(records)} failures={failures}', flush=True)
    return int(failures != 0)


if __name__ == '__main__':
    raise SystemExit(main())
