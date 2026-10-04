#!/usr/bin/env python3
"""Force the queue/idle/exit interleavings in a private RTL copy, without a monitor."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError(f"instrumentation anchor changed: {old!r}")
    return text.replace(old, new, 1)


def instrument(text):
    text = replace_once(text, 'uses system.diagnostics;', 'uses pool_probe, system.diagnostics;')
    text = replace_once(text, '  AtomicIncrement(FRequestCount);',
                        '  AtomicIncrement(FRequestCount);\n  PoolProbe(2,Self);')
    text = replace_once(text, '    Result:=TakeWork;',
                        '    Result:=TakeWork;\n    if not Result then PoolProbe(3,Self);')
    text = replace_once(text, '    Exit(True); // We got work, do not stop thread\n    end;',
                        '    Exit(True); // We got work, do not stop thread\n    end;\n  PoolProbe(1,Self);')
    text = replace_once(text, '  if TakeWork then', '  PoolProbe(4,Self);\n  if TakeWork then')
    wait = '  Woken:=FQueueSemaphore.WaitFor(aThread.CheckWaitTime)=wrSignaled;'
    text = replace_once(text, wait,
        '  if (ProbePool=Self) and (ProbePoint=3) then aThread.FCheckWaitTime:=1;\n' + wait +
        '\n  if (ProbePool=Self) and (ProbePoint=3) then aThread.FCheckWaitTime:=NoRequestsTimeOut+1;')
    text = replace_once(text, '  Status:=FMonitorStatus;', '  Exit; // No monitor may rescue delivery.\n  Status:=FMonitorStatus;')
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT / 'packages/vcl-compat/src/system.threading.pp')
    parser.add_argument('--rounds', type=int, default=1000)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / 'system.threading.pp').write_text(instrument(args.source.read_text(encoding='utf-8')), encoding='utf-8')
    for name in ('pool_probe.pas', 'delivery.dpr'):
        shutil.copy2(HERE / name, output / name)
    spec = importlib.util.spec_from_file_location('rtl_test', ROOT / 'RTL-test/run.py')
    rtl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rtl)
    compiler, config, target, suffix = rtl.toolchain()
    command = [str(compiler), '-n', f'@{config}', *rtl.LANGUAGE, *target, *rtl.NAMESPACES,
               '-Rintel', '-O3', '-gw3', f'-Fu{output}', f'-FU{output}', f'-FE{output}', str(output / 'delivery.dpr')]
    flags = 0x08000000 if os.name == 'nt' else 0
    with (output / 'compile.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=180)
    if result.returncode:
        raise RuntimeError(f'compile failed: {output / "compile.log"}')
    failed = False
    for point in (1, 2, 3, 4):
        with (output / f'point-{point}.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([str(output / ('delivery' + suffix)), str(point), str(args.rounds)],
                                    stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=120)
        print((output / f'point-{point}.log').read_text(encoding='utf-8'), end='', flush=True)
        failed |= result.returncode != 0
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
