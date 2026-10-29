#!/usr/bin/env python3
"""Sparse order-worker Pulse: useful-work CPU and selected-recipient latency together."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import time
import pulse
if os.name != 'nt':
    import resource

CASES = {'orders': 'timed workers, clocks and queued logs',
         'wait': 'timed workers without business work',
         'selected': 'one selected recipient among sleeping workers'}

def parse(text, mode, workers, rounds, signals, period_ms=31, granularity_us=0):
    lines = [line for line in text.splitlines() if line.startswith('PULSE_ORDER ')]
    if len(lines) != 1:
        raise ValueError('Missing unique PULSE_ORDER result: ' + text)
    fields = pulse.parse_fields(lines[0])
    row = {k: v if k == 'mode' else int(v) for k, v in fields.items()}
    expected_timeouts = 0 if mode == 'selected' else workers * (rounds - signals)
    expected_logs = workers * (rounds // 8) if mode == 'orders' else 0
    if (row['verified'] != 1 or row['mode'] != mode or row['workers'] != workers or
            row['rounds'] != rounds or row['period_ms'] != period_ms or row['signals'] != workers * signals or
            row['timeouts'] != expected_timeouts or row['logs'] != expected_logs or row['wall_ns'] <= 0 or
            row.get('granularity_us', 0) != granularity_us):
        raise ValueError('Work oracle failed: ' + text)
    if (min(row['user_ns'], row['kernel_ns'], row['cycles']) < 0 or
            not 0 <= row['latency_p50_ns'] <= row['latency_p95_ns'] <= row['latency_p99_ns'] <= row['latency_max_ns']):
        raise ValueError('Invalid timing data: ' + text)
    if granularity_us > 1 and expected_timeouts:
        duration_us = ((period_ms * 1000 + granularity_us - 1) // granularity_us) * granularity_us
        if row.get('min_timeout_ns', 0) + row.get('timeout_slack_ns', 0) < duration_us * 1000:
            raise ValueError('Wait granularity was reported but not observed: ' + text)
    row['cpu_ns'] = row['user_ns'] + row['kernel_ns']
    row['cpu_percent'] = row['cpu_ns'] / row['wall_ns'] * 100
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--toolchain', type=Path, default=pulse.ROOT / 'toolchain')
    p.add_argument('--baseline-toolchain', type=Path)
    p.add_argument('--systems', default='delphi,moon' if os.name == 'nt' else 'moon')
    p.add_argument('--executable', action='append', default=[], metavar='NAME=PATH', help='use prebuilt stand binaries')
    p.add_argument('--cases', default='orders,selected', help='orders, wait, selected')
    p.add_argument('--workers', type=int, default=92)
    p.add_argument('--rounds', type=int, default=256)
    p.add_argument('--signals', type=int, default=2)
    p.add_argument('--period-ms', type=int, default=31)
    p.add_argument('--wait-granularity-us', type=int, default=0, help='opt-in Linux RTL relative wait quantum; 0 is native')
    p.add_argument('--cpu', type=int, required=True)
    p.add_argument('--repeats', type=int, default=3)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--build-only', action='store_true')
    p.add_argument('--no-build', action='store_true')
    a = p.parse_args()
    cases = a.cases.split(',')
    if (not cases or not set(cases) <= CASES.keys() or not 1 <= a.workers <= 256 or
            not 1 <= a.signals <= 100 or not 2 <= a.period_ms <= 1000 or
            not 1 <= a.rounds <= 10000 or a.repeats < 1 or a.cpu < 0 or not 0 <= a.wait_granularity_us <= 1000000):
        p.error('Invalid workload or affinity')
    if os.name == 'nt' and a.wait_granularity_us:
        p.error('Wait granularity is a Linux RTL option')
    if set(cases) != {'selected'} and a.rounds <= a.workers * a.signals + 32:
        p.error('Rounds must leave time for the selected signals to arrive')
    if os.name == 'nt' and a.cpu >= 64:
        p.error('Windows runner supports the primary processor group')
    if hasattr(os, 'sched_getaffinity') and a.cpu not in os.sched_getaffinity(0):
        p.error('CPU is outside allowed affinity')
    source = pulse.PERF_ROOT / 'threads/pulse_order_workers.dpr'
    pulse.PROGRAMS['order-workers'] = source
    binaries = {}
    if a.executable:
        for item in a.executable:
            name, path = item.split('=', 1)
            if name in binaries:
                p.error('Duplicate executable name')
            binaries[name] = Path(path).resolve()
    else:
        for name in a.systems.split(','):
            if name not in ('delphi', 'moon', 'baseline'):
                p.error('Unknown system')
            if name == 'baseline' and a.baseline_toolchain is None:
                p.error('Baseline toolchain is required')
            if a.no_build:
                binaries[name] = pulse.executable('order-workers', name)
            elif name == 'delphi':
                binaries[name] = pulse.build_delphi('order-workers')
            else:
                binaries[name] = pulse.build_moon('order-workers', False, system=name,
                    toolchain=a.baseline_toolchain if name == 'baseline' else a.toolchain)
    a.output.mkdir(parents=True, exist_ok=True)
    manifest = {'schema': 'pulse-order-workers-v1', 'head': pulse.git_text('rev-parse', 'HEAD'),
                'source_sha256': pulse.sha256(source), 'runner_sha256': pulse.sha256(Path(__file__)),
                'machine': pulse.machine_metadata(), 'cpu': a.cpu, 'period_ms': a.period_ms,
                'workers': a.workers, 'rounds': a.rounds, 'signals': a.signals,
                'wait_granularity_us': a.wait_granularity_us,
                'cases': cases, 'repeats': a.repeats,
                'binaries': {n: {'path': str(f), 'sha256': pulse.sha256(f)} for n, f in binaries.items()},
                'cpu_accounting': 'GetProcessTimes (quantized); cycles retained' if os.name == 'nt' else 'getrusage: in-program and whole-child',
                'timer_resolution_changed': False}
    (a.output / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    if a.build_only:
        return
    rows = []
    for repeat in range(a.repeats):
        for mode in cases if repeat % 2 == 0 else cases[::-1]:
            items = list(binaries.items())
            for name, binary in items if repeat % 2 == 0 else items[::-1]:
                cmd = [str(binary), mode, str(a.workers), str(a.rounds), str(a.period_ms), str(a.signals)]
                if os.name != 'nt':
                    cmd = ['taskset', '-c', str(a.cpu), *cmd]
                started = time.time()
                quantum = a.wait_granularity_us
                period_us = a.period_ms * 1000
                if quantum > 1:
                    period_us = ((period_us + quantum - 1) // quantum) * quantum
                if os.name != 'nt':
                    before = resource.getrusage(resource.RUSAGE_CHILDREN)
                proc = subprocess.run(cmd, capture_output=True, text=True, check=True,
                    env=dict(os.environ, PULSE_WAKE_CPU=str(a.cpu), PULSE_WAIT_GRANULARITY_US=str(quantum)),
                    timeout=a.rounds*period_us/250000+20)
                row = parse(proc.stdout, mode, a.workers, a.rounds, a.signals, a.period_ms, quantum)
                if os.name != 'nt':
                    after = resource.getrusage(resource.RUSAGE_CHILDREN)
                    row['whole_cpu_ns'] = round((after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime) * 1e9)
                row.update(system=name, repeat=repeat, started_unix=started)
                rows.append(row)
                (a.output / 'samples.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
                print(f'{name} {mode}: CPU {row["cpu_percent"]:.3f}%, '
                      f'{row["cpu_ns"]/1e6:.2f} ms, latency p50/p99 '
                      f'{row["latency_p50_ns"]/1000:.2f}/{row["latency_p99_ns"]/1000:.2f} us', flush=True)
                if 'whole_cpu_ns' in row:
                    print(f'  Whole-child CPU: {row["whole_cpu_ns"]/1e6:.2f} ms (including startup and teardown)', flush=True)
    summary = []
    for mode in cases:
        for name in binaries:
            group = [r for r in rows if r['mode'] == mode and r['system'] == name]
            summary.append(dict(mode=mode, system=name, **{key: {
                'median': statistics.median(r[key] for r in group),
                'min': min(r[key] for r in group), 'max': max(r[key] for r in group)}
                for key in ['cpu_ns', 'cpu_percent', 'wall_ns', 'cycles', 'latency_p50_ns',
                            'latency_p95_ns', 'latency_p99_ns', 'latency_max_ns'] +
                            (['whole_cpu_ns'] if os.name != 'nt' else [])}))
    (a.output / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    if os.name == 'nt':
        print('Windows process CPU is quantized. For sparse cross-host CPU verdicts use a scheduler ETW trace; '
              'zero or small samples are not free execution. Cycles compare only on this host.', flush=True)


if __name__ == '__main__':
    main()
