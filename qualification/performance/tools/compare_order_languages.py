#!/usr/bin/env python3
"""Linux sparse order protocol: native library controls and frozen Pascal binaries."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import statistics
import subprocess
import time

from pulse_orders import parse

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / 'threads' / name for name in (
    'pulse_orders_native.c', 'pulse_orders_cpp.cpp', 'pulse_orders_native_workload.h', 'pulse_orders_rust.rs')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text_sum(text):
    result = 0
    for byte in text.encode('ascii'):
        result = (result * 131 + byte) % (1 << 64)
    return result


def oracle(row, mode, workers, rounds, signals):
    """Also validate deterministic work and delivered string contents for new controls."""
    n = signals if mode == 'selected' else rounds
    expected = n * workers * (workers + 1) // 2 * 1000003 + workers * n * (n + 1) // 2
    if 'checksum' in row and row['checksum'] != expected:
        raise ValueError('Iteration checksum failed')
    logs = [f'order={worker} step={step}' for worker in range(workers)
            for step in range(8, rounds + 1, 8)] if mode == 'orders' else []
    if 'log_bytes' in row and (row['log_bytes'] != sum(map(len, logs)) or
            row['log_checksum'] != sum(map(text_sum, logs)) % (1 << 64)):
        raise ValueError('Delivered log checksum failed')


def build(output):
    folder = output / 'binaries'
    folder.mkdir(parents=True, exist_ok=True)
    commands = {
        'c-pthread': ['gcc', '-O2', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pthread', str(SOURCES[0]), '-o', str(folder / 'c-pthread')],
        'cpp-condvar': ['g++', '-O2', '-std=c++20', '-Wall', '-Wextra', '-Werror', '-pthread', str(SOURCES[1]), '-o', str(folder / 'cpp-condvar')],
        'rust-condvar': ['rustc', '-O', '-D', 'warnings', str(SOURCES[3]), '-o', str(folder / 'rust-condvar')],
    }
    for name, command in commands.items():
        result = subprocess.run(command, text=True, capture_output=True)
        (output / (name + '-build.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
    return {name: folder / name for name in commands}, commands


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--cpu', type=int, required=True)
    p.add_argument('--cases', default='orders,wait')
    p.add_argument('--workers', type=int, default=92)
    p.add_argument('--rounds', type=int, default=256)
    p.add_argument('--signals', type=int, default=2)
    p.add_argument('--period-ms', type=int, default=31)
    p.add_argument('--repeats', type=int, default=3)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--executable', action='append', default=[], metavar='NAME=PATH', help='add frozen Pascal binary')
    p.add_argument('--build-only', action='store_true')
    p.add_argument('--no-build', action='store_true')
    a = p.parse_args()
    cases = a.cases.split(',')
    if platform.system() != 'Linux' or a.cpu not in os.sched_getaffinity(0):
        p.error('Linux and an allowed CPU are required')
    if (not cases or not set(cases) <= {'orders', 'wait', 'selected'} or not 1 <= a.workers <= 256 or
            not 1 <= a.rounds <= 10000 or not 1 <= a.signals <= 100 or not 2 <= a.period_ms <= 1000 or not 1 <= a.repeats <= 10):
        p.error('Invalid workload')
    if set(cases) != {'selected'} and a.rounds <= a.workers * a.signals + 32:
        p.error('Insufficient timeout rounds')
    a.output = a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=True)
    if a.no_build:
        binaries = {name: a.output / 'binaries' / name for name in ('c-pthread', 'cpp-condvar', 'rust-condvar')}
        build_manifest = a.output / 'build.json'
        commands = json.loads(build_manifest.read_text())['commands'] if build_manifest.exists() else None
    else:
        binaries, commands = build(a.output)
    for item in a.executable:
        name, path = item.split('=', 1)
        if name in binaries:
            p.error('Duplicate executable name')
        binaries[name] = Path(path).resolve()
    versions = {compiler: subprocess.run([compiler, '--version'], capture_output=True, text=True, check=True).stdout
                for compiler in ('gcc', 'g++', 'rustc')}
    if not a.no_build:
        (a.output / 'build.json').write_text(json.dumps(dict(commands=commands, compiler_versions=versions), indent=2))
    manifest = dict(schema='pulse-order-language-controls-v1', cpu=a.cpu, cases=cases,
        machine=platform.uname()._asdict(), libc=platform.libc_ver(),
        timer_slack_ns=Path('/proc/self/timerslack_ns').read_text().strip(),
        workers=a.workers, rounds=a.rounds, signals_per_worker=a.signals, period_ms=a.period_ms, repeats=a.repeats,
        sources={str(path): sha(path) for path in SOURCES + [Path(__file__), ROOT / 'threads/pulse_order_workers.dpr']},
        binaries={name: dict(path=str(path), sha256=sha(path)) for name, path in binaries.items()},
        compiler_versions=versions, build_commands=commands,
        cpu_accounting='whole-child getrusage delta, sequential children; includes creation, joins, checks and teardown; work interval retained separately',
        differences=[
            'C/C++ use the same pthread OS-thread startup, malloc logger and libc localtime_r calendar; only Event implementation differs.',
            'Rust uses std::thread::scope, Mutex/Condvar, Vec<String> and a Vec callback queue; the same libc clock/calendar reads remain observable.',
            'Pascal uses TThread.Queue/TStringList and Now local-calendar conversion; native logger/allocation and calendar algorithms are not identical.',
            'All controls have 92 worker OS threads plus producer and main; events outlive joined users. Concurrent Event destruction is not modeled.',
            'wait is the closest common mechanism control; orders is the same useful-work protocol, not proof of a language-only cost difference.'])
    (a.output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    if a.build_only:
        return
    rows = []
    for repeat in range(a.repeats):
        names = list(binaries)
        names = names[repeat % len(names):] + names[:repeat % len(names)]
        for mode in cases if repeat % 2 == 0 else cases[::-1]:
            for name in names:
                command = ['taskset', '-c', str(a.cpu), str(binaries[name]), mode, str(a.workers), str(a.rounds), str(a.period_ms), str(a.signals)]
                before = resource.getrusage(resource.RUSAGE_CHILDREN)
                started, whole_start = time.time(), time.monotonic_ns()
                proc = subprocess.run(command, capture_output=True, text=True, timeout=a.rounds * a.period_ms / 250 + 20)
                whole_wall = time.monotonic_ns() - whole_start
                after = resource.getrusage(resource.RUSAGE_CHILDREN)
                (a.output / f'{repeat}-{mode}-{name}.txt').write_text(proc.stdout + proc.stderr)
                if proc.returncode:
                    raise RuntimeError(proc.stdout + proc.stderr)
                row = parse(proc.stdout, mode, a.workers, a.rounds, a.signals, a.period_ms)
                oracle(row, mode, a.workers, a.rounds, a.signals)
                row.update(system=name, repeat=repeat, started_unix=started, whole_wall_ns=whole_wall,
                    whole_user_ns=round((after.ru_utime - before.ru_utime) * 1e9),
                    whole_kernel_ns=round((after.ru_stime - before.ru_stime) * 1e9))
                row['whole_cpu_ns'] = row['whole_user_ns'] + row['whole_kernel_ns']
                row['whole_cpu_percent'] = row['whole_cpu_ns'] / whole_wall * 100
                rows.append(row)
                (a.output / 'samples.json').write_text(json.dumps(rows, indent=2))
                print(f'{name} {mode}: whole CPU {row["whole_cpu_ns"]/1e6:.2f} ms, work wall {row["wall_ns"]/1e9:.3f} s, '
                      f'p50/p95/p99/max {row["latency_p50_ns"]/1000:.2f}/{row["latency_p95_ns"]/1000:.2f}/'
                      f'{row["latency_p99_ns"]/1000:.2f}/{row["latency_max_ns"]/1000:.2f} us', flush=True)
    summary = []
    for mode in cases:
        for name in binaries:
            group = [r for r in rows if r['mode'] == mode and r['system'] == name]
            summary.append(dict(mode=mode, system=name, **{key: dict(median=statistics.median(r[key] for r in group),
                min=min(r[key] for r in group), max=max(r[key] for r in group)) for key in (
                    'whole_cpu_ns', 'whole_cpu_percent', 'whole_wall_ns', 'cpu_ns', 'wall_ns',
                    'latency_p50_ns', 'latency_p95_ns', 'latency_p99_ns', 'latency_max_ns')}))
    (a.output / 'summary.json').write_text(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
