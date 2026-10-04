#!/usr/bin/env python3
"""x*x of a real operand without real effects: folded into sqr(x) and squared in place.

Compiles sqr_fold.dpr at -O2 and -O3 with the product compiler and config, runs it (value, ERangeError of the
checked operand, two calls of an effectful operand, a volatile operand) and requires at -O3 that the loop of
Variance multiplies the loaded element by itself in its register - a `mulsd xmmN,xmmN`, no movapd/movaps copy (the copy
came back when the fold refused every operand that can raise, heartbeat/correlation-32x256) - and that
VolatileSquare still reads its operand twice (no square in place)."""
from pathlib import Path
import argparse, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit(f'SQR_FOLD_GATE_FAIL {command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routine(listing, name):
    head = re.search(r'^[0-9a-f]+ <[^>]*_' + name + r'\$[^>]*>:$', listing, re.MULTILINE)
    if not head:
        raise SystemExit(f'SQR_FOLD_GATE_FAIL no routine {name} in the -O3 object')
    return listing[head.end():].split('\n\n', 1)[0]


def loop_body(body):
    """The lines of the loop of a routine: from the target of its backward jump to the jump (the copy that came
    back sat inside the loop; a parameter moved out of the result register in front of the loop is not one)."""
    lines = [(int(m.group(1), 16), line) for line in body.splitlines()
             for m in [re.match(r'\s*([0-9a-f]+):\t', line)] if m]
    for at, line in reversed(lines):
        jump = re.search(r'\tj\w+\s+([0-9a-f]+) <', line)
        if jump and int(jump.group(1), 16) < at:
            start = int(jump.group(1), 16)
            return '\n'.join(text for where, text in lines if start <= where <= at)
    raise SystemExit('SQR_FOLD_GATE_FAIL no loop in the routine\n' + body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    for mode in ('O2', 'O3'):
        out = args.output / mode
        out.mkdir()
        execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()), '-' + mode,
                 '-FE' + str(out), '-FU' + str(out), str(HERE / 'sqr_fold.dpr')], out, out / 'build.log')
        binary = out / ('sqr_fold.exe' if os.name == 'nt' else 'sqr_fold')
        if execute([str(binary)], out, out / 'run.log').strip() != 'SQR_FOLD_PASS':
            raise SystemExit(f'SQR_FOLD_GATE_FAIL {mode}: the program did not pass')
    listing = code_placement.run([code_placement.tool('objdump'), '-d', '-M', 'intel', '-w', str(args.output / 'O3' / 'sqr_fold.o')])
    body = loop_body(routine(listing, 'VARIANCE'))
    squares = re.findall(r'\bmulsd\s+(xmm\d+),(xmm\d+)\b', body)
    copies = re.findall(r'\bmovap[sd]\s+xmm\d+,xmm\d+', body)
    if not any(a == b for a, b in squares) or copies:
        raise SystemExit(f'SQR_FOLD_GATE_FAIL the loop of Variance at -O3: squares {squares}, copies {copies}\n{body}')
    volatile = routine(listing, 'VOLATILESQUARE')
    if any(a == b for a, b in re.findall(r'\bmulsd\s+(xmm\d+),(xmm\d+)\b', volatile)):
        raise SystemExit(f'SQR_FOLD_GATE_FAIL VolatileSquare at -O3 squares one read\n{volatile}')
    print('SQR_FOLD_GATE_PASS O2/O3 run, O3 Variance squares in place:', [a for a, b in squares if a == b],
          '- VolatileSquare reads twice')


if __name__ == '__main__':
    main()
