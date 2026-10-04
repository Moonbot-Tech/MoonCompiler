#!/usr/bin/env python3
"""Exercise monitor demand and idle exit in a private, short-timeout RTL copy."""
import argparse
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError(f"instrumentation anchor changed: {old!r}")
    return source.replace(old, new, 1)


def instrument(source):
    source = replace_once(source, 'uses system.diagnostics;', 'uses monitor_probe, system.diagnostics;')
    source = replace_once(source, 'MonitorIdleLimit = MonitorMaxInactiveInterval div MonitorThreadDelay;',
                          'MonitorIdleLimit = 2;')
    source = replace_once(source, 'FCPUUsage:=TThread.GetCPUUsage(FCPUInfo);',
                          'FCPUUsage:=ProbeCPUUsage;')
    source = replace_once(source, 'FThreadPool.FMonitorStatus:=MonitorNone;',
                          'FThreadPool.FMonitorStatus:=MonitorNone;\n    AtomicIncrement(ProbeMonitorExits);')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=ROOT / 'packages/vcl-compat/src/system.threading.pp')
    parser.add_argument('--modes', nargs='+', choices=('debug', 'o2', 'o3'), default=('debug', 'o2', 'o3'))
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('rtl_test', ROOT / 'RTL-test/run.py')
    rtl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rtl)
    compiler, config, target, suffix = rtl.toolchain()
    failed = False
    for mode in args.modes:
        output = (args.output / mode).resolve()
        output.mkdir(parents=True, exist_ok=True)
        (output / 'system.threading.pp').write_text(instrument(args.source.read_text(encoding='utf-8')), encoding='utf-8')
        for name in ('monitor_probe.pas', 'monitor_exit.dpr'):
            shutil.copy2(HERE / name, output / name)
        command = [str(compiler), '-n', f'@{config}', *rtl.LANGUAGE, *target, *rtl.NAMESPACES,
                   '-Rintel', *rtl.MODES[mode], f'-Fu{output}', f'-FU{output}', f'-FE{output}',
                   str(output / 'monitor_exit.dpr')]
        hidden = 0x08000000 if os.name == 'nt' else 0
        with (output / 'compile.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=output, stdout=log, stderr=subprocess.STDOUT,
                                    creationflags=hidden, timeout=180)
        if result.returncode:
            raise RuntimeError(f'compile failed: {output / "compile.log"}')
        with (output / 'run.log').open('w', encoding='utf-8') as log:
            result = subprocess.run([str(output / ('monitor_exit' + suffix))], stdout=log,
                                    stderr=subprocess.STDOUT, creationflags=hidden, timeout=30)
        print(f'{mode}: exit={result.returncode}: {(output / "run.log").read_text(encoding="utf-8").strip()}', flush=True)
        failed |= result.returncode != 0
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
