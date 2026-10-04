#!/usr/bin/env python3
"""Targeted x86-64 static-address hoist semantics and internal-emitter gate."""
from pathlib import Path
import argparse, json, os, re, subprocess
from oracle import verify

HERE = Path(__file__).resolve().parent
POSITIVE = ('reduction64', 'reduction4096', 'matrix_row', 'matrix_column', 'histogram',
            'write_one_base', 'write_two_base', 'aliased', 'nonaliased', 'pressure_low',
            'pressure_high', 'matrix_2_fields', 'matrix_3_fields', 'matrix_4_fields',
            'local_table', 'literal_table', 'literal_fp')
NEGATIVE = ('OneUse', 'RuntimeBase', 'CallInLoop', 'BranchInLoop', 'SideEntry',
            'AsmInLoop', 'TryInLoop', 'RedefinedBase', 'ZeroTrip', 'CrossUnit')

def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(str(command) + '\n' + (result.stdout + result.stderr)[-2500:])
    return result.stdout

def prove_hoist(assembly, name):
    match = re.search(r'^[0-9a-fA-F]+ <[^>]*\$\$_' + name + r'\$[^>]*>:\n(.*?)(?=\n[0-9a-fA-F]+ <|\Z)', assembly, re.M | re.S)
    assert match, name
    leas, backedges = [], []
    for line in match[1].splitlines():
        row = re.match(r'\s*([0-9a-fA-F]+):\s+(?:[0-9a-fA-F]{2}\s+)+\s*(.*)', line)
        if not row:
            continue
        pc, ins = int(row[1], 16), row[2].strip()
        if ins.startswith('lea') and 'rip' in ins:
            leas.append(pc)
        branch = re.match(r'j\w+\s+(?:0x)?([0-9a-fA-F]+)\b', ins)
        if branch and int(branch[1], 16) < pc:
            backedges.append((int(branch[1], 16), pc))
    assert len(backedges) == 2, (name, backedges)
    inner = min(backedges, key=lambda pair: pair[1]-pair[0])
    assert len(leas) == 1 and leas[0] < inner[0], (name, leas, inner)
    return dict(function=name, lea=leas[0], inner=inner)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--objdump', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    win = os.name == 'nt'
    rows = []
    for mode in ('O-', 'O2', 'O3'):
        for pic in ((False,) if win else (False, True)):
            for stem in ('semantic', 'negative_semantic'):
                out = args.output.resolve() / (mode + ('-pic' if pic else '') + '-' + stem)
                out.mkdir(parents=True, exist_ok=True)
                cmd = [str(args.compiler.resolve()), '-n', '@'+str(args.config.resolve()), '-'+mode, '-B',
                       '-Fu'+str(HERE), '-FE'+str(out), '-FU'+str(out), str(HERE/(stem+'.dpr'))]
                if pic:
                    cmd.insert(3, '-Cg')
                execute(cmd, HERE, out/'build.log')
                binary = out/(stem+('.exe' if win else ''))
                output = execute([str(binary)], out, out/'run.log')
                names, inputs = (POSITIVE, (0, 1, 2, 17)) if stem == 'semantic' else (NEGATIVE, range(-1, 18))
                expected = {(name, n) for name in names for n in inputs}
                observed = [(line.split()[0], int(line.split()[1])) for line in output.splitlines()]
                assert len(observed) == len(expected) and set(observed) == expected, (stem, observed)
                row = dict(mode=mode, pic=pic, stem=stem, oracle_rows=verify(output), command=cmd)
                if stem == 'semantic' and mode == 'O3' and (win or pic):
                    options = ['-d', '--x86-asm-syntax=intel'] if 'llvm' in args.objdump.name else ['-d', '-Mintel', '--insn-width=16']
                    assembly = execute([str(args.objdump.resolve()), *options, str(binary)], out, out/'image.asm')
                    row['hoist'] = prove_hoist(assembly, 'REDUCTION64' if win else 'LITERAL_FP')
                rows.append(row)
    (args.output/'results.json').write_text(json.dumps(rows, indent=2))
    print('LOOP_ADDRESS_GATE_PASS', len(rows), sum(row['oracle_rows'] for row in rows))

if __name__ == '__main__':
    main()
