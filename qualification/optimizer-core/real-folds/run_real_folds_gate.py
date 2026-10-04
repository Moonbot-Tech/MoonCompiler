#!/usr/bin/env python3
"""The code shape of real operations in the forms a trading program writes (compiler/ncon.pas, fold_ordinary_real;
compiler/nflw.pas, the min/max rewrite).

Compiles real_folds.dpr at -O2 and -O3 with the product compiler and config and runs it: every value against the one
computed at run time, 1/0 after inlining still raises with the zero divide unmasked.  In the -O3 object each routine is
counted - instructions without padding, calls - against reference.json of the target: more instructions or more calls
than recorded is red (a fold was lost), fewer is reported (record it with --record after reading why).  The shape
itself is required too:
  ScaleFour       X*(4.0*0.5) after inlining: one arithmetic instruction;
  PickSmall       the branch on 50 > 100 after inlining: no comparison, no conditional jump;
  LerpConst       Lerp(1, 3, 0.5): the value alone, no arithmetic;
  ClampConst      Clamp01(0.75): the value alone, no comparison;
  MinPrice        the minimum of an array: minsd, no comisd;
  Widen           the range of a candle through a pointer: minsd and maxsd, no conditional jump;
and the operations that stay at run time:
  RatioByZero     1/0: divsd;
  RootOfNegative  the root of -1: sqrtsd;
  TimesZero       X*0.0 (NaN*0 is NaN, -1*0 is -0): mulsd;
  MinInclusive    V <= P^.Lo (the sign of zero, NaN): a comparison, no minsd.

The program is built again at -O3 with -Cr -Co and run: the checked object must carry the checks the plain one has
not (a range or overflow switch in the file would make both builds one code), MinPrice over a checked element among
them.  The value oracles of the repair run on both targets: tfoldruntimereal1 (every fold bit for bit against the
run-time operation, the traps) at -O-, -O2, -O3 and -O3 -Cr -Co, tobservableintrinsics1, tfloatminselect1 and
tdelphinegativezero1 at -O2 and -O3.

    run_real_folds_gate.py --compiler PPCX64 --config MOON-BASE.CFG --output NEW_DIR [--record]"""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

PLAIN = ['-Cr-', '-Co-']
CHECKED = ['-Cr', '-Co']
CHECK_CALL = re.compile(r'\b(?:fpc_rangeerror|fpc_dynarray_rangecheck|fpc_overflow)\b', re.IGNORECASE)
# 029c8caf8, 737f84f79, 11e955c0b, 339012b17: real constants after inlining, real min/max, real identities with zero
ORACLES = (('tfoldruntimereal1', ('O-', 'O2', 'O3', 'O3-checked')), ('tobservableintrinsics1', ('O2', 'O3')),
           ('tfloatminselect1', ('O2', 'O3')), ('tdelphinegativezero1', ('O2', 'O3')),
           ('tifminmaxtarget1', ('O-', 'O2', 'O3')),
           ('tinlineminmaxsnapshot1', ('O-', 'O2', 'O3')))

ROUTINES = ('SCALEFOUR', 'PICKSMALL', 'LERPCONST', 'CLAMPCONST', 'RATIOBYZERO', 'ROOTOFNEGATIVE', 'TIMESZERO',
            'MINPRICE', 'WIDEN', 'MININCLUSIVE')
ARITHMETIC = r'(add|sub|mul|div|min|max|sqrt)sd '
COMPARISON = r'u?comisd '
CONDITIONAL = r'j(?!mp)[a-z]+ '


def fail(message):
    raise SystemExit('REAL_FOLDS_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routine(listing, name):
    head = re.search(r'^[0-9a-f]+ <[^>]*_\$\$_' + name + r'\$[^>]*>:$', listing, re.MULTILINE)
    if not head:
        fail(f'no routine {name} in the -O3 object')
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true', help='write the counts of this object as the reference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    target = 'x86_64-win64' if os.name == 'nt' else 'x86_64-linux'
    compiler = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve())]
    suffix = '.exe' if os.name == 'nt' else ''

    def build_run(source, mode, out):
        out.mkdir()
        switches = CHECKED if mode.endswith('-checked') else PLAIN
        execute([*compiler, '-' + mode.removesuffix('-checked'), *switches, '-FE' + str(out), '-FU' + str(out),
                 str(source)], out, out / 'build.log')
        return execute([str(out / (source.stem + suffix))], out, out / 'run.log').strip()

    for mode in ('O2', 'O3', 'O3-checked'):
        if build_run(HERE / 'real_folds.dpr', mode, args.output / mode) != 'REAL_FOLDS_PASS':
            fail(f'{mode}: the program did not pass')
    for name, modes in ORACLES:
        for mode in modes:
            build_run(ROOT / 'tests' / 'test' / 'cg' / (name + '.pp'), mode, args.output / f'{name}-{mode}')
    # the objdump of the toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects
    beside = args.compiler.resolve().parent / 'objdump.exe'
    relocations = os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else code_placement.tool('objdump'))
    checks = {mode: len(CHECK_CALL.findall(code_placement.run([relocations, '-d', '-r', '-w', str(
        args.output / mode / 'real_folds.o')]))) for mode in ('O3', 'O3-checked')}
    if checks['O3-checked'] <= checks['O3']:
        fail(f'-Cr -Co built the code of the plain build: {checks} range and overflow check calls')
    checked = routine(code_placement.run([code_placement.tool('objdump'), '-d', '-M', 'intel', '-w',
                                          str(args.output / 'O3-checked' / 'real_folds.o')]), 'MINPRICE')
    if not any(i.startswith('call ') for i in checked):
        fail('-O3 -Cr -Co: MinPrice reads its elements without a range check\n    ' + '\n    '.join(checked))
    listing = code_placement.run([code_placement.tool('objdump'), '-d', '-M', 'intel', '-w',
                                  str(args.output / 'O3' / 'real_folds.o')])
    body = {name: routine(listing, name) for name in ROUTINES}
    counts = {name: {'insns': len(body[name]), 'calls': sum(1 for i in body[name] if i.startswith('call '))}
              for name in ROUTINES}
    (args.output / 'counts.json').write_text(json.dumps(counts, indent=1, sort_keys=True))
    problems = []

    def count(name, pattern):
        return sum(1 for i in body[name] if re.match(pattern, i))

    def require(condition, name, what):
        if not condition:
            problems.append(f'{name}: {what}\n    ' + '\n    '.join(body[name]))

    require(count('SCALEFOUR', ARITHMETIC) == 1, 'SCALEFOUR', 'not one arithmetic instruction')
    require(count('PICKSMALL', COMPARISON) == 0 and count('PICKSMALL', CONDITIONAL) == 0, 'PICKSMALL',
            'the constant condition is compared or branched on')
    require(count('LERPCONST', ARITHMETIC) == 0, 'LERPCONST', 'arithmetic on constants')
    require(count('CLAMPCONST', COMPARISON) == 0 and count('CLAMPCONST', ARITHMETIC) == 0, 'CLAMPCONST',
            'a comparison or arithmetic on a constant')
    require(count('MINPRICE', r'minsd ') == 1 and count('MINPRICE', COMPARISON) == 0, 'MINPRICE',
            'not minsd without a comparison')
    require(count('WIDEN', r'minsd ') == 1 and count('WIDEN', r'maxsd ') == 1 and count('WIDEN', CONDITIONAL) == 0,
            'WIDEN', 'not minsd and maxsd without a conditional jump')
    require(count('RATIOBYZERO', r'divsd ') == 1, 'RATIOBYZERO', '1/0 folded')
    require(count('ROOTOFNEGATIVE', r'sqrtsd ') == 1, 'ROOTOFNEGATIVE', 'the root of -1 folded')
    require(count('TIMESZERO', r'mulsd ') == 1, 'TIMESZERO', 'X*0.0 folded')
    require(count('MININCLUSIVE', COMPARISON) == 1 and count('MININCLUSIVE', r'minsd ') == 0, 'MININCLUSIVE',
            'the inclusive selection is not a branch')
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = counts
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
        print(f'REAL_FOLDS_REFERENCE_RECORDED {target}')
    recorded = reference.get(target)
    if recorded is None:
        problems.append(f'no reference for {target}: run with --record after reading the object')
    else:
        report = []
        for name in ROUTINES:
            want, got = recorded.get(name), counts[name]
            if want is None:
                problems.append(f'{name}: no reference count')
                continue
            if got['insns'] > want['insns'] or got['calls'] > want['calls']:
                problems.append(f'{name}: {got} against the reference {want}\n    ' + '\n    '.join(body[name]))
            elif got != want:
                report.append(f'{name} {want} -> {got}')
        if report:
            print('REAL_FOLDS_SHORTER ' + '; '.join(report))
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    print('REAL_FOLDS_GATE_PASS O2/O3 run; O3: constants after inlining folded, the dead arm gone, minsd/maxsd over an '
          'element and a field, 1/0, the root of -1, X*0.0 and the inclusive selection at run time; counts within '
          f'the {target} reference; -O3 -Cr -Co run with {checks["O3-checked"]} check calls against {checks["O3"]}, '
          f'MinPrice checked; {len(ORACLES)} value oracles of the repair')


if __name__ == '__main__':
    main()
