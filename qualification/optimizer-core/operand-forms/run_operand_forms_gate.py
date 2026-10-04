#!/usr/bin/env python3
"""The operand of an instruction is what the statement names: the memory of the subtrahend, the element at the
scaled index, the variable of the unit, the part which the target and the value of an assignment share.

Compiles operand_forms.dpr at -O1, -O2, -O3 and -O4 without checks, and at -O3 with range and overflow checks, with
the product compiler and config, and runs each program: the values of every statement of the file.  In the -O3
object every routine whose name begins with Shape is counted - instructions without padding, calls, and the
instructions of its innermost loop - against reference.json of the target: a count which grew is red, one which
shrank is reported so that the reference is renewed on purpose (--record writes it)."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

SOURCE = HERE / 'operand_forms.dpr'
PASS_LINE = 'OPERAND_FORMS_PASS'
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*([0-9a-f]+):\t(.*)$')
RELOC = re.compile(r'[0-9a-f]+: R_\S+\s+(\S+)')
SHAPE = re.compile(r'^(SHAPE[A-Z0-9]+)(?:\$|$)')
# a conditional jump: the back edge of a loop
JUMP = re.compile(r'^j(?!mp\b)\w+\s+([0-9a-f]+)\b')
PADDING = ('nop', 'xchg   ax,ax', 'int3', '(bad)')


def fail(message):
    raise SystemExit('OPERAND_FORMS_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routines(listing):
    """name of the shape -> the instructions of the routine without padding, each with its address"""
    found = {}
    body = None
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            shape = SHAPE.match(head[1].split('_$$_')[-1].upper())
            body = None
            if shape:
                if shape[1] in found:
                    fail(f'two routines named {shape[1]} in the -O3 object')
                body = found[shape[1]] = []
            continue
        if body is None:
            continue
        insn = INSN.match(line)
        if not insn:
            continue
        text = re.sub(r'^(?:ds |cs |data16 )+', '', RELOC.sub('', insn[2]).strip())
        if not text or text.startswith(PADDING) or text == 'add    BYTE PTR [rax],al':
            continue
        body.append((int(insn[1], 16), text))
    return found


def innermost_loop(body):
    """the number of instructions from the target of the shortest conditional backward jump to that jump; 0 for
    a routine without a loop"""
    best = None
    for index, (address, text) in enumerate(body):
        jump = JUMP.match(text)
        if not jump:
            continue
        target = int(jump[1], 16)
        if target > address:
            continue
        first = next((i for i, (a, _) in enumerate(body) if a >= target), None)
        if first is None or first > index:
            continue
        if best is None or index - first < best[1] - best[0]:
            best = (first, index)
    return 0 if best is None else best[1] - best[0] + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true', help='write the counts of this compiler as the reference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    binary_name = 'operand_forms.exe' if os.name == 'nt' else 'operand_forms'
    builds = (('O1', ['-O1']), ('O2', ['-O2']), ('O3', ['-O3']), ('O4', ['-O4']), ('O3-checked', ['-O3', '-Cr', '-Co']))
    for mode, options in builds:
        out = args.output / mode
        out.mkdir()
        execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve())] + options +
                ['-FE' + str(out), '-FU' + str(out), str(SOURCE)], out, out / 'build.log')
        if execute([str(out / binary_name)], out, out / 'run.log').strip() != PASS_LINE:
            fail(f'{mode}: the program did not pass\n' + (out / 'run.log').read_text()[-2000:])
    # the objdump of the toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects
    beside = args.compiler.resolve().parent / 'objdump.exe'
    objdump = (os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else None)
               or code_placement.tool('objdump'))
    listing = subprocess.run([objdump, '-d', '-r', '-w', '-M', 'intel', '--no-show-raw-insn',
                              str(args.output / 'O3' / 'operand_forms.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    (args.output / 'O3' / 'operand_forms.lst').write_text(listing, encoding='utf-8')
    found = routines(listing)
    target = 'win64' if os.name == 'nt' else 'linux'
    counts = {name: [len(body), sum(1 for _, text in body if text.startswith('call')), innermost_loop(body)]
              for name, body in sorted(found.items())}
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = counts
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
    recorded = reference.get(target)
    if recorded is None:
        fail(f'reference.json has no counts for {target}; run once with --record')
    problems = []
    shrunk = []
    for name, was in recorded.items():
        now = counts.get(name)
        if now is None:
            problems.append(f'{name}: no routine in the -O3 object')
        elif any(n > w for n, w in zip(now, was)):
            problems.append(f'{name}: {now[0]} instructions / {now[1]} calls / loop {now[2]}, '
                            f'reference {was[0]} / {was[1]} / {was[2]}')
        elif now != was:
            shrunk.append(f'{name} {now[0]}/{now[1]}/{now[2]} < {was[0]}/{was[1]}/{was[2]}')
    for name in counts:
        if name not in recorded:
            problems.append(f'{name}: no reference; run once with --record')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'OPERAND_FORMS_GATE_PASS {len(builds)} builds run; O3 {target}: {len(recorded)} routines counted, '
          f'none above the reference{note}')


if __name__ == '__main__':
    main()
