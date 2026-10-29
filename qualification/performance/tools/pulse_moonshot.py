#!/usr/bin/env python3
"""Quiet MoonShot polling: actual strategy mix, CPU and a separate response control."""
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

CASES = {'quiet': 'observed no-trade, no-log polling',
         'no-format': 'diagnostic control omitting discarded text preparation',
         'wait': 'event and application wait-wrapper control',
         'response': 'quiet polling plus artificial addressed signals; no trade',
         'cpu': 'identical check body without waits; not application CPU utilization',
         'cpu-no-format': 'check body without waits or diagnostic formatting',
         'no-filter': 'diagnostic control bypassing the three strategy filter calls',
         'cpu-no-filter': 'check body without waits or strategy filter calls'}


def parse(text, mode, rounds, period, quantum):
    lines = [s for s in text.splitlines() if s.startswith('PULSE_MOONSHOT ')]
    if len(lines) != 1:
        raise ValueError('Missing unique result: ' + text)
    row = {k: v if k == 'mode' else int(v) for k, v in pulse.parse_fields(lines[0]).items()}
    checks = 0 if mode == 'wait' else 92 * rounds
    signals = 184 if mode == 'response' else 0
    timeouts = 0 if mode.startswith('cpu') else 92 * rounds - signals
    formats = 0 if mode in ('wait', 'no-format', 'cpu-no-format') else 8 * checks
    expected = dict(model=2, filter_checks=0 if mode in ('wait', 'no-filter', 'cpu-no-filter') else checks, verified=1, char_bytes=2, workers=92, rounds=rounds, period_ms=period,
                    granularity_us=quantum, checks=checks, signals=signals,
                    timeouts=timeouts, formats=formats, state_checks=checks,
                    local_order_checks=0 if mode == 'wait' else 92 * ((rounds + 3) // 4),
                    log_records=0, exchange_requests=0, history_rows=0)
    if row['mode'] != mode or any(row.get(k) != v for k, v in expected.items()):
        raise ValueError('Work contract mismatch: ' + text)
    if (row.get('borrowed_content') not in (0, 1) or
            not 0 <= row.get('full_checks', -1) <= checks or
            not 0 <= row.get('api_status_replays', -1) <= row['local_order_checks']):
        raise ValueError('Missing or invalid workload variant/counters: ' + text)
    if not (row['wall_ns'] > 0 and min(row['user_ns'], row['kernel_ns']) >= 0 and
            0 <= row['latency_p50_ns'] <= row['latency_p95_ns'] <= row['latency_p99_ns'] <= row['latency_max_ns']):
        raise ValueError('Invalid timings: ' + text)
    if not signals and row['latency_max_ns']:
        raise ValueError('Latency without a signal')
    if signals and row['latency_max_ns'] == 0:
        raise ValueError('Missing signal latency')
    row['cpu_ns'] = row['user_ns'] + row['kernel_ns']
    row['cpu_percent'] = row['cpu_ns'] * 100 / row['wall_ns']
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--toolchain', type=Path, default=pulse.ROOT / 'toolchain')
    p.add_argument('--systems', default='delphi,moon' if os.name == 'nt' else 'moon')
    p.add_argument('--executable', action='append', default=[], metavar='NAME=PATH')
    p.add_argument('--cases', default='quiet,response')
    p.add_argument('--rounds', type=int, default=320)
    p.add_argument('--cpu-rounds', type=int, default=1000)
    p.add_argument('--period-ms', type=int, default=16)
    p.add_argument('--wait-granularity-us', type=int, default=0)
    p.add_argument('--cpu', type=int, required=True)
    p.add_argument('--repeats', type=int, default=3)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--build-only', action='store_true')
    a = p.parse_args()
    cases = a.cases.split(',')
    if not set(cases) <= CASES.keys() or not 1 <= a.rounds <= 640 or a.repeats < 1:
        p.error('Invalid cases/rounds/repeats; maximum twenty seconds of nominal paced work')
    if 'response' in cases and a.rounds < 192:
        p.error('Response needs at least 192 rounds')
    if not 1 <= a.cpu_rounds <= 10000 or a.cpu < 0 or a.period_ms != 16:
        p.error('Invalid CPU rounds/affinity; this observed fixture uses WaitFor(16)')
    if a.wait_granularity_us not in (0, 15625) or (os.name == 'nt' and a.wait_granularity_us):
        p.error('Quantum must be native or the selected Linux application profile')
    if hasattr(os, 'sched_getaffinity') and a.cpu not in os.sched_getaffinity(0):
        p.error('CPU outside allowed affinity')
    source = pulse.PERF_ROOT / 'threads/pulse_moonshot_idle.dpr'
    pulse.PROGRAMS['moonshot-idle'] = source
    binaries = {}
    for item in a.executable:
        name, path = item.split('=', 1)
        if name in binaries:
            p.error('Duplicate executable')
        binaries[name] = Path(path).resolve()
    if not binaries:
        for name in a.systems.split(','):
            if name == 'delphi':
                binaries[name] = pulse.build_delphi('moonshot-idle')
            elif name == 'moon':
                binaries[name] = pulse.build_moon('moonshot-idle', False, toolchain=a.toolchain)
            else:
                p.error('Unknown system')
    a.output.mkdir(parents=True, exist_ok=True)
    manifest = dict(schema='pulse-moonshot-idle-v2', machine=pulse.machine_metadata(),
                    head=pulse.git_text('rev-parse', 'HEAD'), options=vars(a).copy(),
                    sources={f.name: pulse.sha256(f) for f in
                             [source, source.with_name('pulse_moonshot_fixture.inc'),
                              *sorted(source.parent.glob('MoonShot*.pas')), Path(__file__)]},
                    binaries={n: {'path': str(f), 'sha256': pulse.sha256(f)} for n, f in binaries.items()},
                    note='Windows CPU counters are quantized; use ETW before a sparse cross-host CPU verdict.')
    (a.output / 'manifest.json').write_text(json.dumps(manifest, default=str, indent=2))
    if a.build_only:
        return
    rows = []
    for repeat in range(a.repeats):
        for mode in cases if repeat % 2 == 0 else cases[::-1]:
            for name, binary in list(binaries.items())[::1 if repeat % 2 == 0 else -1]:
                rounds = a.cpu_rounds if mode.startswith('cpu') else a.rounds
                cmd = [str(binary), mode, str(rounds), str(a.period_ms)]
                if os.name != 'nt':
                    cmd = ['taskset', '-c', str(a.cpu), *cmd]
                    before = resource.getrusage(resource.RUSAGE_CHILDREN)
                started = time.time()
                result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=35,
                    env=dict(os.environ, PULSE_WAKE_CPU=str(a.cpu), PULSE_WAIT_GRANULARITY_US=str(a.wait_granularity_us)))
                row = parse(result.stdout, mode, rounds, a.period_ms, a.wait_granularity_us)
                if os.name != 'nt':
                    after = resource.getrusage(resource.RUSAGE_CHILDREN)
                    row['whole_cpu_ns'] = round(1e9 * (after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime))
                row.update(system=name, repeat=repeat, started=started, raw=result.stdout)
                rows.append(row)
                (a.output / 'samples.json').write_text(json.dumps(rows, indent=2))
                print(name, mode, f"CPU={row['cpu_percent']:.3f}% p95={row['latency_p95_ns']/1000:.1f}us", flush=True)
    summary = []
    for name in binaries:
        for mode in cases:
            sample = [r for r in rows if r['system'] == name and r['mode'] == mode]
            summary.append(dict(system=name, mode=mode, cpu_ns=statistics.median(r['cpu_ns'] for r in sample),
                cpu_percent=statistics.median(r['cpu_percent'] for r in sample),
                wall_ns=statistics.median(r['wall_ns'] for r in sample),
                p95_ns=[r['latency_p95_ns'] for r in sample]))
    (a.output / 'summary.json').write_text(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
