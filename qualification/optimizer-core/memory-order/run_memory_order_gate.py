#!/usr/bin/env python3
"""The peephole optimizer of x86 keeps the order of a read and of a write which may be of one memory, and keeps
its optimizations where the memory is certainly another one (compiler/x86/aoptx86.pas: RefsApart, CellsApart,
RefModifiedBetween, MemoryOrderFree, WriteMayMoveUp; compiler/x86/cgx86.pas: the number of a copy of a block).

Values.  generate_programs.py writes programs in which one memory has two names - a variable by its name, a pointer
to it, a field, an element, a half of a cell, a local through its address - and counts the values every call must
give from the order of the statements.  The programs of PROGRAMS are written to the output directory, built with
the product compiler and config at -O1, -O2, -O3 and -O4 and run.  memory_order_shapes.dpr is built and run the
same way.

Shapes.  In the -O3 object of memory_order_shapes.dpr every routine of SHAPES is counted - instructions without
padding, calls, loads and stores of 16 bytes - against reference.json of the target: a routine that grew or lost
a move of 16 bytes is red, one that shrank is reported so that the reference is renewed on purpose (--record
writes it)."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402
import generate_programs  # noqa: E402

SOURCE = HERE / 'memory_order_shapes.dpr'
PASS_LINE = 'MEMORY_ORDER_SHAPES_PASS'
# (family, seed, routines)
# mixed 11 has the mask of a value which is not used (doc/COMPILER_FIXES.md)
PROGRAMS = (('mixed', 1, 300), ('mixed', 2, 300), ('mixed', 11, 300), ('float', 1, 300), ('step', 1, 300),
            ('step', 2, 300))
LEVELS = ('O1', 'O2', 'O3', 'O4')
# the routine is the symbol which ends with the name and the mangled parameters
SHAPES = ('WRITEIFNOTEMPTY', 'LESS', 'SHAPEOTHERFIELD', 'SHAPEOTHERNAME', 'SHAPECOPYRECORD', 'SHAPEREADANDSTEP',
          'SHAPEREADNUMBER')
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*([0-9a-f]+):\t(.*)$')
RELOC = re.compile(r'[0-9a-f]+: R_\S+\s+(\S+)')
PADDING = ('nop', 'xchg   ax,ax', 'int3', '(bad)')
WIDE = re.compile(r'^v?movdq[ua]\b|^v?movup[sd]\b|^v?movap[sd]\b')


def fail(message):
    raise SystemExit('MEMORY_ORDER_GATE_FAIL ' + message)


def execute(command, cwd, log, what):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        fail(f'{what}: {Path(command[0]).name} exited {result.returncode}\n' +
             (result.stdout + result.stderr)[-2000:])
    return result.stdout


def build_and_run(args, source, name, out, options, pass_line):
    out.mkdir(parents=True)
    binary = out / (name + ('.exe' if os.name == 'nt' else ''))
    execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve())] + options +
            ['-FE' + str(out), '-FU' + str(out), str(source)], out, out / 'build.log', f'{name} {options[0]}')
    lines = execute([str(binary)], out, out / 'run.log', f'{name} {options[0]}').split()
    if not lines or lines[-1] != pass_line:
        fail(f'{name} {options[0]}: the program did not pass\n' + (out / 'run.log').read_text()[-2000:])
    binary.unlink()


def routines(listing):
    """name -> the instructions of the routine without padding"""
    found = {}
    body = None
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            body = None
            last = head[1].split('_$$_')[-1]
            for name in SHAPES:
                if last.startswith(name + '$') and 'fin$' not in last:
                    body = found.setdefault(name, [])
            continue
        if body is None:
            continue
        insn = INSN.match(line)
        if not insn:
            continue
        text = re.sub(r'^(?:ds |cs |data16 )+', '', RELOC.sub('', insn[2]).strip())
        if not text or text.startswith(PADDING) or text == 'add    BYTE PTR [rax],al':
            continue
        body.append(text)
    missing = [name for name in SHAPES if not found.get(name)]
    if missing:
        fail('no routine in the -O3 object: ' + ', '.join(missing))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true', help='write the counts of this compiler as the reference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)

    builds = 0
    for level in LEVELS:
        build_and_run(args, SOURCE, 'memory_order_shapes', args.output / 'shapes' / level, ['-' + level], PASS_LINE)
        builds += 1
    calls = 0
    for family, seed, count in PROGRAMS:
        name = f'memory_order_{family}_{seed}'
        text, made = generate_programs.generate(family, seed, count, name)
        source = args.output / 'programs' / (name + '.dpr')
        source.parent.mkdir(exist_ok=True)
        source.write_text(text, encoding='utf-8', newline='\n')
        calls += made
        for level in LEVELS:
            build_and_run(args, source, name, args.output / 'programs' / name / level, ['-' + level],
                          name.upper() + '_PASS')
            builds += 1

    # the objdump of the toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects
    beside = args.compiler.resolve().parent / 'objdump.exe'
    objdump = (os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else None)
               or code_placement.tool('objdump'))
    shapes = args.output / 'shapes' / 'O3'
    listing = subprocess.run([objdump, '-d', '-r', '-w', '-M', 'intel', '--no-show-raw-insn',
                              str(shapes / 'memory_order_shapes.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    (shapes / 'memory_order_shapes.lst').write_text(listing, encoding='utf-8')
    found = routines(listing)
    target = 'win64' if os.name == 'nt' else 'linux'
    counts = {}
    for name, body in found.items():
        counts[name] = [len(body), sum(1 for text in body if text.startswith('call')),
                        sum(1 for text in body if WIDE.match(text))]
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
    for name, now in counts.items():
        was = recorded.get(name)
        if was is None:
            problems.append(f'{name}: no reference; run once with --record')
        elif now[0] > was[0] or now[1] > was[1] or now[2] < was[2]:
            problems.append(f'{name}: {now[0]} instructions / {now[1]} calls / {now[2]} moves of 16 bytes, '
                            f'reference {was[0]} / {was[1]} / {was[2]}')
        elif now != was:
            shrunk.append(f'{name} {now[0]}/{now[1]}/{now[2]} against {was[0]}/{was[1]}/{was[2]}')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'MEMORY_ORDER_GATE_PASS {builds} builds run, {len(PROGRAMS)} programs of {calls} calls at '
          f'{len(LEVELS)} levels; O3 {target}: {len(counts)} routines counted, none above the reference{note}')


if __name__ == '__main__':
    main()
