"""PPU-only strong aliases; optionally check the instrumented compiler's ownership counts."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess


def run(command, cwd, log, ownership=False, environment=None):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace', env=environment)
    output = result.stdout + result.stderr
    log.write_text(output)
    assert result.returncode == 0, (command, output[-3000:])
    if ownership:
        counters = re.findall(r'^L2_TABLES ([0-9 -]+)$', output, re.M)
        assert len(counters) == 1, output[-3000:]
        assert list(map(int, counters[0].split()))[:2] == [0, 0], counters
    return output


def check(compiler, config, output, ownership=False, compiler_environment=None):
    fixtures = Path(__file__).resolve().parent
    rows = []
    for mode in ('O-', 'O2', 'O3'):
        case = output / mode
        producer, consumer, units = (case / name for name in ('producer', 'consumer', 'units'))
        for directory in (producer, consumer, units):
            directory.mkdir(parents=True)
        source = producer / 'alias_cases.pas'
        shutil.copy2(fixtures / source.name, source)
        command = [str(compiler), '-n', '@' + str(config), '-' + mode]
        run(command + ['-B', '-FU' + str(units), str(source)], producer, case / 'producer.log', ownership,
            compiler_environment)
        source.rename(producer / 'alias_cases.hidden')
        shutil.copy2(fixtures / 'alias_consumer.dpr', consumer)
        run(command + ['-Fu' + str(units), '-FU' + str(consumer), '-FE' + str(consumer),
                       str(consumer / 'alias_consumer.dpr')], consumer, case / 'consumer.log', ownership,
            compiler_environment)
        executable = consumer / ('alias_consumer.exe' if os.name == 'nt' else 'alias_consumer')
        assert run([str(executable)], consumer, case / 'run.log').strip() == 'L2_ALIAS_PASS'
        assert not source.exists()
        rows.append(dict(mode=mode, sha256=hashlib.sha256(executable.read_bytes()).hexdigest()))
    (output / 'result.json').write_text(json.dumps(rows, indent=2))
    print('ALIAS_LIFETIME_GATE_PASS', len(rows), 'ownership=' + str(ownership))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--ownership', action='store_true', help='Require counters from run_alias_reload_gate.py trace compiler')
    args = parser.parse_args()
    assert not args.output.exists(), 'Use a new output directory'
    check(args.compiler.resolve(), args.config.resolve(), args.output.resolve(), args.ownership)
