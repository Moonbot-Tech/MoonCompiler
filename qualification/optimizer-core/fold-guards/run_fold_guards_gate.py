#!/usr/bin/env python3
"""The folds of an expression ask what they do with its evaluation (compiler/nutils.pas, might_have_sideeffects).

Compiles fold_guards.dpr at -O2 and -O3 with the product compiler and config and runs it: values, no fault where a
short-circuit guards a memory access (a short-circuit operand made unconditional faults on nil), the ERangeError of
checked operands whose evaluation is merged or dropped, 0*x unchanged for a NaN element.  In the -O3 object it
requires the folds that keep one evaluation of two, repeat one or drop one whose value is not needed, on operands
read through memory (a field, a dereference, an element) - the folds the guard of every possible exception refused:
  IsDigitAt       (x >= '0') and (x <= '9') of an element: one unsigned compare, one compare in all;
  CheckedIsDigit  the same under $R+: the range check stays, the compare is one unsigned (setbe, no signed jump);
  RotateField     (x shl n) or (x shr (64-n)) of fields: rol;
  RoundDown       x - x mod 8 of a field: one read of the field;
  DropProduct     x*0 + 7 of a field: the constant 7 alone;
  DropDifference  x - x of a field: no memory access;
  FieldFirst      of TBox<UnicodeString>: FFlag and <kind known false> - no call of the dead arm;
and keeps ZeroTimes a multiplication (0*x of a real is not 0 for a NaN: only fast math folds it).

The repair of 20.09 these folds refine guarded enabled range and overflow checks, so the same program is built again at
-O3 with -Cr -Co and run: the checked object must carry the checks the plain one has not (a range or overflow switch
in the file would make both builds one code) and IsDigitAt, now checked, must keep its one unsigned compare with its
checks.  The regressions of that repair, which set their own checks, run at -O2 and -O3 on both targets."""
from pathlib import Path
import argparse, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

PLAIN = ['-Cr-', '-Co-']
CHECKED = ['-Cr', '-Co']
CHECK_CALL = re.compile(r'\b(?:fpc_rangeerror|fpc_dynarray_rangecheck|fpc_overflow)\b', re.IGNORECASE)
# 23424ec1d, Optimizer: preserve required evaluation when folding expressions
REGRESSIONS = ('tobservablesimplify1', 'trangefoldobservable1', 'trotatefold1', 'tshortboolprune1',
               'tinlinecheckedruntime1')


def fail(message):
    raise SystemExit('FOLD_GUARDS_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routine(listing, pattern):
    head = re.search(r'^[0-9a-f]+ <[^>]*' + pattern + r'[^>]*>:$', listing, re.MULTILINE)
    if not head:
        fail(f'no routine matching {pattern} in the -O3 object')
    out = []
    for line in listing[head.end():].split('\n\n', 1)[0].splitlines():
        m = re.match(r'^\s*[0-9a-f]+:\t(?:[0-9a-f]{2} )+\s*\t(.*)$', line)
        if not m:
            continue
        text = re.sub(r'^(?:ds |cs |data16 )+', '', m[1].strip())
        if not text.startswith(('nop', 'xchg   ax,ax', 'int3')):
            out.append(re.sub(r'\s+', ' ', text))
    while out and out[-1] in ('add BYTE PTR [rax],al', '(bad)'):
        out.pop()
    return out


def check_calls(compiler, obj):
    """Calls of the range and overflow check routines, read from the relocations of an object.  The objdump of the
    toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects."""
    beside = compiler.resolve().parent / 'objdump.exe'
    objdump = os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else code_placement.tool('objdump'))
    return len(CHECK_CALL.findall(code_placement.run([objdump, '-d', '-r', '-w', str(obj)])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    compiler = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve())]
    suffix = '.exe' if os.name == 'nt' else ''
    for mode, switches in (('O2', PLAIN), ('O3', PLAIN), ('O3-checked', CHECKED)):
        out = args.output / mode
        out.mkdir()
        execute([*compiler, '-' + mode[:2], *switches, '-FE' + str(out), '-FU' + str(out),
                 str(HERE / 'fold_guards.dpr')], out, out / 'build.log')
        if execute([str(out / ('fold_guards' + suffix))], out, out / 'run.log').strip() != 'FOLD_GUARDS_PASS':
            fail(f'{mode}: the program did not pass')
    for name in REGRESSIONS:
        for mode in ('O2', 'O3'):
            out = args.output / f'{name}-{mode}'
            out.mkdir()
            execute([*compiler, '-' + mode, '-FE' + str(out), '-FU' + str(out),
                     str(ROOT / 'tests' / 'test' / 'cg' / (name + '.pp'))], out, out / 'build.log')
            execute([str(out / (name + suffix))], out, out / 'run.log')
    checks = {mode: check_calls(args.compiler, args.output / mode / 'fold_guards.o') for mode in ('O3', 'O3-checked')}
    if checks['O3-checked'] <= checks['O3']:
        fail(f'-Cr -Co built the code of the plain build: {checks} range and overflow check calls')
    objdump = code_placement.tool('objdump')
    listing = code_placement.run([objdump, '-d', '-M', 'intel', '-w', str(args.output / 'O3' / 'fold_guards.o')])
    body = {name: routine(listing, r'_\$\$_' + name + r'\$')
            for name in ('ISDIGITAT', 'CHECKEDISDIGIT', 'ROTATEFIELD', 'ROUNDDOWN', 'DROPPRODUCT', 'DROPDIFFERENCE',
                         'ZEROTIMES')}
    body['FIELDFIRST'] = routine(listing, r'_\$\$_FIELDFIRST\$UNICODESTRING')
    body['ISDIGITAT-CHECKED'] = routine(code_placement.run([objdump, '-d', '-M', 'intel', '-w', str(
        args.output / 'O3-checked' / 'fold_guards.o')]), r'_\$\$_ISDIGITAT\$')
    problems = []

    def require(condition, name, what):
        if not condition:
            problems.append(f'{name}: {what}\n    ' + '\n    '.join(body[name]))

    def count(name, pattern):
        return sum(1 for i in body[name] if re.match(pattern, i))

    require(count('ISDIGITAT', r'cmp ') == 1 and count('ISDIGITAT', r'setbe ') == 1, 'ISDIGITAT',
            'not one unsigned compare')
    for name in ('CHECKEDISDIGIT', 'ISDIGITAT-CHECKED'):
        require(count(name, r'call ') == 2 and count(name, r'setbe ') == 1 and count(name, r'j[lg]e? ') == 0, name,
                'not the range checks and one unsigned compare')
    require(count('ROTATEFIELD', r'rol ') == 1, 'ROTATEFIELD', 'no rol')
    require(sum(1 for i in body['ROUNDDOWN'] if 'PTR [' in i) == 1, 'ROUNDDOWN', 'not one read of the field')
    require(body['DROPPRODUCT'][:-1] == ['mov eax,0x7'], 'DROPPRODUCT', 'not the constant alone')
    require(not any('PTR [' in i for i in body['DROPDIFFERENCE']), 'DROPDIFFERENCE', 'a memory access')
    require(count('FIELDFIRST', r'call ') == 0, 'FIELDFIRST', 'the dead arm calls')
    require(count('ZEROTIMES', r'mulsd ') == 1, 'ZEROTIMES', '0*x folded')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    print('FOLD_GUARDS_GATE_PASS O2/O3 run; O3: one unsigned compare (and under $R+ with its checks), rol, one read, '
          'the constant alone, no access, the dead arm gone, 0*x kept; -O3 -Cr -Co run with '
          f'{checks["O3-checked"]} check calls against {checks["O3"]}, IsDigitAt one unsigned compare with its checks; '
          f'{len(REGRESSIONS)} regressions of the checked folds at O2/O3')


if __name__ == '__main__':
    main()
