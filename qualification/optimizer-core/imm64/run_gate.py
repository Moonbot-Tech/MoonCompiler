#!/usr/bin/env python3
"""Check shared imm64 materialization semantics and linked machine code."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from verify_semantic import mix, verify

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def run(command, directory, name):
    done = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=90)
    output = done.stdout + done.stderr
    (directory / (name + '.log')).write_text(output, encoding='utf-8')
    (directory / (name + '-command.json')).write_text(json.dumps(command, indent=2), encoding='utf-8')
    if done.returncode:
        raise RuntimeError(f'{name} failed ({done.returncode}): {directory}')
    return output


def body(assembly, fragment):
    labels = list(re.finditer(r'^[0-9a-f]+ <([^>]+)>:', assembly, re.M))
    matches = [(i, label) for i, label in enumerate(labels) if fragment in label.group(1)]
    if len(matches) != 1:
        raise RuntimeError(f'expected one linked function matching {fragment}, found {len(matches)}')
    i, label = matches[0]
    return assembly[label.end():labels[i+1].start() if i+1 < len(labels) else len(assembly)]


def loads(assembly):
    return len(re.findall(r'\bmov(?:abs)?q?\s[^\n]*(?:0x9e3779b185ebca87|11400714785074694791)', assembly, re.I))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    binary = ROOT / 'toolchain/bin'
    parser.add_argument('--compiler', type=Path, default=binary / ('x86_64-win64/ppcx64.exe' if os.name == 'nt' else 'fpc'))
    parser.add_argument('--config', type=Path, default=(binary / 'x86_64-win64/moon-base.cfg' if os.name == 'nt'
                                                     else ROOT / 'toolchain/etc/moon-base.cfg'))
    parser.add_argument('--output', type=Path, default=ROOT / '.qualification/imm64-gate')
    args = parser.parse_args()
    compiler, config, output = (path.resolve() for path in (args.compiler, args.config, args.output))
    output.mkdir(parents=True, exist_ok=False)
    disassembler = os.environ.get('MOON_OBJDUMP') or shutil.which('llvm-objdump' if os.name == 'nt' else 'objdump')
    if disassembler is None:
        raise RuntimeError('linked ASM verification requires MOON_OBJDUMP or an installed objdump')
    rows = []
    for mode in ['O-', 'O2', 'O3']:
        directory = output / mode
        directory.mkdir()
        command = [str(compiler), '-n', '@' + str(config), '-' + mode, '-B', '-Ci',
                   '-Fu' + str(ROOT / 'qualification/performance/abi'), '-Fu' + str(HERE),
                   '-FU' + str(directory), '-FE' + str(directory)]
        run(command + [str(HERE / 'semantic.dpr')], directory, 'compile')
        executable = directory / ('semantic.exe' if os.name == 'nt' else 'semantic')
        count = verify(run([str(executable)], directory, 'semantic'))
        run(command + [str(HERE / 'live_register.dpr')], directory, 'compile-live-register')
        live_register = directory / ('live_register.exe' if os.name == 'nt' else 'live_register')
        if run([str(live_register)], directory, 'live-register').splitlines() != [
            'AE4F161853CC4359', 'FCA5F25664168805',
            '9E3779B185EBCA87', '449133AD34E87D12', '-1'
        ]:
            raise RuntimeError(f'{mode}: a shared constant clobbered a live input register')
        assembly = run([disassembler, '-d', str(executable)], directory, 'assembly')
        counts = {}
        for size in [16, 24, 32]:
            counts[size] = loads(body(assembly, '$$_RETURNRECORD' + str(size) + '$'))
            if mode != 'O-' and counts[size] != 1:
                raise RuntimeError(f'{mode} Return{size}: expected one shared constant load, found {counts[size]}')
        run(command + [str(HERE / 'negative_asm.dpr')], directory, 'compile-inline-asm')
        negative = directory / ('negative_asm.exe' if os.name == 'nt' else 'negative_asm')
        lines = run([str(negative)], directory, 'inline-asm').splitlines()
        if len(lines) != 260:
            raise RuntimeError('inline ASM oracle row count differs')
        for line in lines:
            value, first, second = map(int, line.split(','))
            if [first, second] != [mix(value), mix(value+1)]:
                raise RuntimeError(f'inline ASM barrier changed results: {line}')
        negative_assembly = run([disassembler, '-d', str(negative)], directory, 'inline-asm-assembly')
        if mode != 'O-' and loads(body(negative_assembly, '$$_ACROSSASM$')) != 2:
            raise RuntimeError('constant reuse crossed an inline ASM boundary')
        rows.append(dict(mode=mode, oracle_rows=count+len(lines)+5, loads=counts,
                         sha256=hashlib.sha256(executable.read_bytes()).hexdigest()))
    result = dict(status='pass', compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), rows=rows)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('IMM64_GATE_PASS modes=3 oracle_rows=11715 asm=9 inline_asm=3')


if __name__ == '__main__':
    main()
