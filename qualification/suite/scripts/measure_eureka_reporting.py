#!/usr/bin/env python3
"""Measure prebuilt Delphi baseline/Eureka worker benchmarks, without report I/O.

Build diagnostic_raise_bench.pas with Delphi 12.2 twice, with and without EUREKA.
The EUREKA executable must be postprocessed with ecc32 and the application's
actual Eureka profile. This runner does not require or distribute that profile.
"""
import argparse
import json
from pathlib import Path
import re
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--eureka', type=Path, required=True)
    parser.add_argument('--results', type=Path, required=True)
    args = parser.parse_args()
    out = args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    samples = {key: [] for key in ('baseline', 'capture', 'thread-off', 'global-off', 'toggle')}
    # Rotate order between fresh processes to avoid assigning all drift to one state.
    for iteration in range(7):
        keys = list(samples)
        keys = keys[iteration % len(keys):] + keys[:iteration % len(keys)]
        for key in keys:
            executable = args.baseline if key == 'baseline' else args.eureka
            command = [str(executable.resolve()), '200000' if key == 'toggle' else '3000',
                       str(out / 'reports'), key]
            process = subprocess.run(command, cwd=out, capture_output=True, timeout=90)
            text = (process.stdout + process.stderr).decode('utf-8', errors='replace')
            (out / f'{key}-{iteration}.log').write_text(text, encoding='utf-8')
            if process.returncode or (key != 'baseline' and 'EUREKA_ACTIVE' not in text):
                raise RuntimeError(f'{key}: exit={process.returncode}; {text}')
            match = re.search(r'NS_PER_(?:RAISE|TOGGLE_PAIR)=([\d.]+)', text)
            if not match:
                raise RuntimeError(f'Missing timing: {text}')
            samples[key].append(float(match[1]))
            print(f'{key} {iteration}: {match[1]} ns', flush=True)
    summary = {key: {'median_ns': statistics.median(values), 'samples_ns': values}
               for key, values in samples.items()}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print('EUREKA_BENCHMARK_PASS', summary)


if __name__ == '__main__':
    main()
