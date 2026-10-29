"""One causal control: array-base read before/after hash, with same-binary A/A."""
import argparse
import json
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--work', type=Path, required=True)
p.add_argument('--compiler', required=True)
p.add_argument('--config', required=True)
p.add_argument('--cpu', type=int, required=True)
a = p.parse_args()
work = a.work.resolve()

def run(args):
    return subprocess.run(['taskset', '-c', str(a.cpu), 'nice', '-n', '10', *args],
                          cwd=work, capture_output=True, text=True, timeout=90)

for mode, defines in (('control', []), ('after', ['ASTRA_FUSED']),
                      ('before', ['ASTRA_FUSED', 'ASTRA_BASE_BEFORE_HASH'])):
    out = work / mode
    out.mkdir(exist_ok=False)
    command = [a.compiler, '-n', '@' + a.config, '-dRELEASE', '-dUTF16', '-Xs-',
               '-Fu' + str(out), '-Fu' + str(work), '-FU' + str(out), '-FE' + str(out),
               *['-d' + d for d in defines]]
    for source in ('storage_alternative_probe', 'contracts', 'reentrant_factory'):
        result = run(command + [str(work / (source + '.dpr'))])
        (out / (source + '-build.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, result.stdout[-1500:]
        result = run([str(out / source)])
        (out / (source + '-contracts.log')).write_text(result.stdout + result.stderr)
        if source != 'reentrant_factory':
            assert result.returncode == 0, result.stderr
    print('built', mode, flush=True)

with (work / 'order.jsonl').open('w') as raw:
    for repeat in range(5):
        for count, profile, hit in ((100000, 0, 0), (100000, 1, 0), (100000, 0, 90), (3742, 0, 90)):
            modes = ['control-a', 'after', 'control-b', 'before']
            modes = modes[repeat % 4:] + modes[:repeat % 4]
            for mode in modes:
                directory = 'control' if mode.startswith('control-') else mode
                result = run([str(work / directory / 'storage_alternative_probe'),
                              str(count), str(profile), str(hit), '5', '0'])
                assert result.returncode == 0, result.stderr
                row = json.loads(result.stdout)
                row.update(experiment=mode, repeat=repeat)
                raw.write(json.dumps(row) + '\n')
                raw.flush()
            print(repeat, count, profile, hit, flush=True)
