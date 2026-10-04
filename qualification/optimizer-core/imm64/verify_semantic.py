from pathlib import Path
import argparse
import functools
import operator
import subprocess

MASK = (1 << 64) - 1
K = 0x9E3779B185EBCA87


def mix(v):
    v &= MASK
    return ((v ^ (v >> 29)) * K) & MASK


def verify(text):
    rows = 0
    for line in text.splitlines():
        name, value, *actual = line.split(',')
        v = int(value)
        if name.startswith('return'):
            expected = [mix(v + i) for i in range(int(name[6:]) // 8)]
        elif name == 'different':
            expected = [(((v + i) & MASK) ^ (((v + i) & MASK) >> 23)) * 0xD6E8FEB86659FD93 & MASK for i in range(2)]
        elif name == 'mixed':
            expected = [v * K & MASK, ((v ^ K) + K) & MASK]
        elif name == 'call':
            expected = [mix(v), mix(v ^ 0x13579BDF)]
        elif name.startswith('branch'):
            expected = [mix(v), mix(v + (1 if name == 'branch1' else 2))]
        elif name == 'try':
            expected = [mix(v) ^ v, mix(v + 1)]
        elif name == 'narrow':
            expected = [(v & 255) * K & MASK, ((v >> 8) & 65535) * K & MASK]
        elif name == 'many':
            expected = [mix(v + i) for i in range(17)]
        elif name == 'pressure':
            expected = [functools.reduce(operator.xor, (mix(v + i) for i in range(8)))]
        elif name == 'alias':
            expected = [mix(v + 1), mix(mix(v + 1))]
        elif name == 'checked':
            expected = [int(v == 0)]
        else:
            raise AssertionError(name)
        assert list(map(int, actual)) == expected, (name, v, actual, expected)
        rows += 1
    assert rows == 260 * 14, rows
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('path', type=Path)
    parser.add_argument('--saved-output', action='store_true')
    args = parser.parse_args()
    if args.saved_output:
        output = args.path.read_text()
    else:
        run = subprocess.run([str(args.path.resolve())], capture_output=True, text=True)
        assert run.returncode == 0, run.stderr
        output = run.stdout
        args.path.with_suffix('.oracle-output.txt').write_text(output)
    print('ABI_IMM64_SEMANTIC_PASS', verify(output))
