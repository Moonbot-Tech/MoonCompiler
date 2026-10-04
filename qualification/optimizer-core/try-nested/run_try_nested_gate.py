#!/usr/bin/env python3
"""A routine with try and a nested routine keeps in registers what its exception paths do not read
(compiler/psub.pas, tcgprocinfo.generate_code and mark_seh_memory_syms).

Compiles try_nested.dpr at -O1, -O2, -O3 and -O4 without checks, and at -O3 with range and overflow checks, with the
product compiler and config, and runs each program: the semantic matrix of the file.  In the -O3 object:
  the innermost loop of every Shape routine is found by its backward jump; it reads and writes no frame slot;
  the loop of the routine with a nested procedure and the loop of the routine with an anonymous function are the
  loop of the routine without them: equal instruction counts;
  the loop of TBook.Join, the body of a routine of a trading program, goes through the frame for Self only (an
  anonymous function in a method captures Self), where the target has nonvolatile vector registers (Win64);
  every counted routine - instructions without padding and calls, a routine together with its outlined
  finalizers - against reference.json of the target: a routine that grew is red, one that shrank is reported so
  that the reference is renewed on purpose (--record writes it)."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402
import inline_cleanup_shape  # noqa: E402

SOURCE = HERE / 'try_nested.dpr'
PASS_LINE = 'TRY_NESTED_PASS'
# routine -> (targets, frame slots its innermost loop may touch)
FRAME_IN_LOOP = {
    'SHAPENESTEDLOOP': (('win64', 'linux'), 0),
    'SHAPEANONYMOUSLOOP': (('win64', 'linux'), 0),
    'SHAPEPLAINLOOP': (('win64', 'linux'), 0),
    'JOIN': (('win64',), 1),
}
# pairs whose innermost loops are the same code
SAME_LOOP = (('SHAPENESTEDLOOP', 'SHAPEPLAINLOOP'), ('SHAPEANONYMOUSLOOP', 'SHAPEPLAINLOOP'))
SHAPES = tuple(FRAME_IN_LOOP)
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*([0-9a-f]+):\t(.*)$')
RELOC = re.compile(r'[0-9a-f]+: R_\S+\s+(\S+)')
# a conditional jump: the back edge of a loop
JUMP = re.compile(r'^j(?!mp\b)\w+\s+([0-9a-f]+)\b')
FRAME = re.compile(r'\[(?:rbp|rsp)\s*[-+\]]')
PADDING = ('nop', 'xchg   ax,ax', 'int3', '(bad)')


def fail(message):
    raise SystemExit('TRY_NESTED_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def owner(symbol):
    """(shape, is a finalizer) of a symbol: the routine itself is the symbol whose last name is the shape, its
    outlined finalizers are the symbols named fin$ behind that routine; nested routines, anonymous functions and
    the methods of a capturer are somebody else's code"""
    parts = symbol.split('_$$_')
    last = parts[-1]
    for name in SHAPES:
        if last.startswith(name + '$'):
            return name, False
        if last.startswith('fin$') and len(parts) >= 2 and re.search(
                r'(^|_\$|\$_\$|_\$_)' + re.escape(name) + r'\$', parts[-2]):
            return name, True
    return None, False


def routines(listing):
    """name -> list of bodies, a body is a list of (address, text) without padding: the routine itself first, its
    outlined finalizers behind it"""
    found = {name: [] for name in SHAPES}
    body = None
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            name, finalizer = owner(head[1])
            body = None
            if name is not None:
                body = []
                if finalizer:
                    found[name].append(body)
                else:
                    found[name].insert(0, body)
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
    missing = [name for name, bodies in found.items() if not bodies or not bodies[0]]
    if missing:
        fail('no routine in the -O3 object: ' + ', '.join(missing))
    return found


def innermost_loop(body, name):
    """the instructions from the target of the shortest conditional backward jump to that jump"""
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
    if best is None:
        fail(f'{name}: no loop in the -O3 object')
    return body[best[0]:best[1] + 1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true', help='write the counts of this compiler as the reference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    binary_name = 'try_nested.exe' if os.name == 'nt' else 'try_nested'
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
                              str(args.output / 'O3' / 'try_nested.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    (args.output / 'O3' / 'try_nested.lst').write_text(listing, encoding='utf-8')
    found = routines(listing)
    target = 'win64' if os.name == 'nt' else 'linux'
    problems = []
    if target == 'win64':
        for name in ('SHAPEANONYMOUSLOOP', 'JOIN'):
            problems += inline_cleanup_shape.problems(listing, name, 'fpc_intf_decr_ref', 2)
    loops = {name: innermost_loop(found[name][0], name) for name in SHAPES}
    checked = 0
    for name, (targets, limit) in FRAME_IN_LOOP.items():
        if target not in targets:
            continue
        checked += 1
        slots = [text for _, text in loops[name] if FRAME.search(text)]
        if len(slots) > limit:
            problems.append(f'{name}: the loop goes through the frame {len(slots)} times, {limit} allowed: '
                            + '; '.join(slots))
    for left, right in SAME_LOOP:
        if len(loops[left]) != len(loops[right]):
            problems.append(f'{left}: the loop has {len(loops[left])} instructions, the loop of {right} '
                            f'{len(loops[right])}')
    counts = {}
    for name, bodies in found.items():
        insns = sum(len(body) for body in bodies)
        calls = sum(1 for body in bodies for _, text in body if text.startswith('call'))
        counts[name] = [insns, calls, len(loops[name])]
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = counts
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
    recorded = reference.get(target)
    if recorded is None:
        fail(f'reference.json has no counts for {target}; run once with --record')
    shrunk = []
    for name, now in counts.items():
        was = recorded.get(name)
        if was is None:
            problems.append(f'{name}: no reference; run once with --record')
        elif any(n > w for n, w in zip(now, was)):
            problems.append(f'{name}: {now[0]} instructions / {now[1]} calls / loop {now[2]}, '
                            f'reference {was[0]} / {was[1]} / {was[2]}')
        elif now != was:
            shrunk.append(f'{name} {now[0]}/{now[1]}/{now[2]} < {was[0]}/{was[1]}/{was[2]}')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'TRY_NESTED_GATE_PASS {len(builds)} builds run; O3 {target}: {checked} loops counted, '
          f'no routine above the reference{note}')


if __name__ == '__main__':
    main()
