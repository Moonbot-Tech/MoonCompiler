#!/usr/bin/env python3
"""Compiler/SDK regression gate; sources and output remain outside the checkout."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expect-pooling', action='store_true')
    parser.add_argument('--external-assembler', action='store_true')
    parser.add_argument('--mormot-consumer', action='store_true')
    args = parser.parse_args()
    suite = Path(__file__).resolve().parents[1] / 'suite/tests'
    fixtures = suite / 'generic-sharing/immutable-rtti-pools'
    output = args.output.resolve()
    output.mkdir(parents=True)
    rows = []

    def run(case, src, flags, rebuild=True):
        directory = src.parent
        command = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
                   '-dRELEASE', '-FU' + str(directory), '-FE' + str(directory)]
        if rebuild:
            command.append('-B')
        command.extend(flags)
        command.append(str(src))
        compiled = subprocess.run(command, cwd=directory, capture_output=True, timeout=180)
        (directory / (case + '-compile.log')).write_bytes(compiled.stdout + compiled.stderr)
        row = {'case': case, 'compile_rc': compiled.returncode}
        if compiled.returncode == 0:
            executable = src.with_suffix('.exe' if os.name == 'nt' else '')
            result = subprocess.run([str(executable)], cwd=directory, capture_output=True, timeout=30)
            (directory / (case + '-runtime.log')).write_bytes(result.stdout + result.stderr)
            row.update(runtime_rc=result.returncode, output=result.stdout.decode(errors='replace'),
                       executable_bytes=executable.stat().st_size)
        rows.append(row)
        (output / 'results.json').write_text(json.dumps(rows, indent=2))
        print(json.dumps(row), flush=True)
        if compiled.returncode or row.get('runtime_rc'):
            raise RuntimeError('Failed ' + case + '; see logs in ' + str(directory))

    flags = ['-dEXPECT_IMMUTABLE_POOL'] if args.expect_pooling else []
    for case in ['normal', 'reverse', 'alignment', 'stripped']:
        directory = output / case
        directory.mkdir(exist_ok=True)
        for source in fixtures.iterdir():
            shutil.copy2(source, directory / source.name)
        source = directory / 'Probe.dpr'
        if case == 'reverse':
            source.write_text(source.read_text().replace('System.Rtti,A,B;', 'System.Rtti,B,A;'))
        extra = ['-dPOOL_ALIGN_SPLIT'] if case == 'alignment' else flags
        if case == 'stripped':
            extra = flags + ['--striprtti', '-dPOOL_STRIPPED']
        run(case, source, extra)
        if case == 'normal':
            run('cached', source, extra, rebuild=False)
            for unit in ['A', 'B']:
                (directory / (unit + '.pas')).rename(directory / (unit + '.hidden'))
            run('source-free', source, extra, rebuild=False)
    directory = output / 'public-contract'
    directory.mkdir(exist_ok=True)
    source = directory / 'rtti_public_layout_contract.dpr'
    shutil.copy2(suite / 'rtti' / source.name, source)
    run('public-contract', source, [])
    if args.mormot_consumer:
        directory = output / 'mormot-consumer'
        directory.mkdir()
        source = directory / 'mormot_immutable_pool_consumer.dpr'
        shutil.copy2(suite / 'rtti' / source.name, source)
        run('mormot-consumer', source, [])
    if args.external_assembler:
        directory = output / 'external-assembler'
        directory.mkdir(exist_ok=True)
        for source in fixtures.iterdir():
            shutil.copy2(source, directory / source.name)
        run('external-assembler', directory / 'Probe.dpr', ['-Aas'])


if __name__ == '__main__':
    main()
