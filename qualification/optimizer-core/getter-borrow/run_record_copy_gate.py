#!/usr/bin/env python3
"""Aggregate returns: preserve values, checks and snapshots; reject redundant getter copies."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ONE_COPY = ('ITEMSLOCAL', 'ITEMSVAR', 'ITEMSFIELD', 'ITEMSGLOBAL', 'ITEMSRESULT',
            'DIRECTLOCAL', 'INLINEVAR', 'CHAINITEMS', 'INDEXITEMS', 'ASSIGNRECORD')
MODES = [('O0', ['-O-']), ('O2', ['-O2']), ('O3', ['-O3']),
         ('checked', ['-O3', '-Cr', '-Co']), ('autoinline', ['-O3']),
         ('noregvar', ['-O3', '-OoNOREGVAR'])]


def execute(command, output, log):
    result = subprocess.run(command, cwd=output, capture_output=True, text=True, errors='replace', timeout=120)
    log.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'{command[0]} exited {result.returncode}:\n{result.stdout}{result.stderr}')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compiler, config, output = args.compiler.resolve(), args.config.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    beside = compiler.parent / 'objdump.exe'
    objdump = os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else shutil.which('objdump'))
    if not objdump:
        raise RuntimeError('objdump is required to verify copy counts')
    summary = {}
    for mode, flags in MODES:
        directory = output / mode
        directory.mkdir()
        options = [str(compiler), '-n', '@' + str(config), *flags]
        if mode != 'autoinline':
            options.append('-OoNOAUTOINLINE')
        for name, expected in [('record_copy_probe', ['RECORD_COPY_PROBE_PASS 360', 'SEMANTIC_CHECKS 24']),
                               ('aggregate_sizes', ['AGGREGATE_SIZES_PASS 14'])]:
            execute([*options, '-FE' + str(directory), '-FU' + str(directory), str(HERE / (name + '.dpr'))],
                    directory, directory / (name + '-build.log'))
            binary = directory / (name + ('.exe' if os.name == 'nt' else ''))
            actual = execute([str(binary)], directory, directory / (name + '-run.log')).splitlines()
            if actual != expected:
                raise RuntimeError(f'{mode}/{name}: unexpected output {actual}')
        listing = execute([objdump, '-drw', '-M', 'intel', '--no-show-raw-insn',
                           str(directory / 'record_copy_probe.o')], directory, directory / 'code.txt')
        copies = {}
        for block in re.split(r'(?m)^(?=[0-9a-f]+ <)', listing):
            head = block.splitlines()[0] if block else ''
            for name in ONE_COPY:
                if '_' + name + '$' in head:
                    copies[name] = sum('rep movs' in line or ('call' in line and 'FPC_MOVE' in line.upper())
                                       for line in block.splitlines()[1:]
                                       if re.match(r'^\s*[0-9a-f]+:\s', line))
        if set(copies) != set(ONE_COPY) or any(count != 1 for count in copies.values()):
            raise RuntimeError(f'{mode}: expected one copy in every getter/assignment probe, got {copies}')
        summary[mode] = copies
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print('RECORD_COPY_GATE_PASS 6 modes; 24 semantic checks; 14 aggregate sizes; 10 single-copy forms')


if __name__ == '__main__':
    main()
