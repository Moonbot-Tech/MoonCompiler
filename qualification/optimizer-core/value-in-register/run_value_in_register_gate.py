#!/usr/bin/env python3
"""A value in a register is not read back from memory (compiler/x86/aoptx86.pas: CanDrop32BitZeroExtend,
ForwardMemoryValue, TEST/Jcc/TEST in OptPass1Test; compiler/ncal.pas: inline_actual_is_callers_own and
inline_constant_goes_in in paraneedsinlinetemp).

Compiles value_in_register.dpr at -O-, -O2 and -O3 with the product compiler and config and runs it: every value is
the one of the text.  In the -O3 object every routine of SHAPES is counted - instructions without padding and memory
accesses (an operand in memory, lea apart; push and pop) - against reference.json of the target: a routine with more
of either is red, one with fewer is reported so that the reference is renewed on purpose (--record writes it).
Independently of the reference:
  StoreReload and StoreOther extend no 32-bit register into itself (mov edx,edx): the upper half of the index is
  already clear, and the extension between the write of the element and its read kept the read;
  CheckAll touches no cell of its frame: the constant empty message reaches the inlined assertion, and the
  assertion does not store it in the frame and read it back on every turn;
  CleanName calls no StringReplace wrapper: the form stays the product's, the worker called with the arguments."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402
import inline_cleanup_shape  # noqa: E402

SHAPES = ('STORERELOAD', 'STOREOTHER', 'STORETHENADD', 'CONTAINSMISS', 'CLEANNAME', 'CHECKALL', 'KIDAT', 'TOBYTE',
          'FLIPSHEET')
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*[0-9a-f]+:\t(.*)$')
RELOC = re.compile(r'[0-9a-f]+: R_\S+\s+(\S+)')
SELF_MOVE = re.compile(r'^mov (e[a-z]{2}|r\d+d),\1$')
FRAME = re.compile(r'\[(?:rsp|rbp)[\]+-]')


def fail(message):
    raise SystemExit('VALUE_IN_REGISTER_GATE_FAIL ' + message)


def execute(command, cwd, log):
    log.with_suffix('.argv.json').write_text(json.dumps(command, indent=2))
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routines(listing):
    """name -> [instructions, memory accesses, self moves, called symbols, frame accesses] of the probe routines"""
    found = {name: [0, 0, [], [], []] for name in SHAPES}
    current = None
    last_call = False
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            last = head[1].split('_$$_')[-1]
            current = next((name for name in SHAPES if last.startswith(name + '$')), None)
            last_call = False
            continue
        if current is None:
            continue
        insn = INSN.match(line)
        if not insn:
            reloc = RELOC.search(line)
            if reloc and last_call:
                found[current][3].append(reloc[1])
            continue
        relocs = RELOC.findall(insn[1])
        text = re.sub(r'^(?:ds |cs |data16 )+', '', RELOC.sub('', insn[1]).strip())
        text = re.sub(r'\s+', ' ', text)
        last_call = False
        if not text or text.startswith(('nop', 'xchg ax,ax', 'int3', '(bad)')) or text == 'add BYTE PTR [rax],al':
            continue
        mnemonic = text.split(' ', 1)[0]
        found[current][0] += 1
        if mnemonic in ('push', 'pop') or ('[' in text and mnemonic != 'lea'):
            found[current][1] += 1
        if SELF_MOVE.match(text):
            found[current][2].append(text)
        if mnemonic not in ('push', 'pop', 'lea') and FRAME.search(text):
            found[current][4].append(text)
        if mnemonic == 'call':
            last_call = not relocs
            found[current][3].extend(relocs)
            target = re.search(r'<([^>]+)>', text)
            if target:
                found[current][3].append(target[1])
    missing = [name for name, found_name in found.items() if found_name[0] == 0]
    if missing:
        fail('no routine in the -O3 object: ' + ', '.join(missing))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--record', action='store_true', help='write the counts of this compiler as the reference')
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    modes = ['O-', 'O2', 'O3'] + (['O3-pic'] if os.name != 'nt' else [])
    for mode in modes:
        out = args.output / mode
        out.mkdir()
        optimization = ['-O3', '-Cg'] if mode == 'O3-pic' else ['-' + mode]
        execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()), '-Mdelphi', *optimization,
                 '-FE' + str(out), '-FU' + str(out), str(HERE / 'value_in_register.dpr')], out, out / 'build.log')
        binary = out / ('value_in_register.exe' if os.name == 'nt' else 'value_in_register')
        lines = execute([str(binary)], out, out / 'run.log').split()
        if not lines or lines[-1] != 'VALUE_IN_REGISTER_PASS':
            fail(f'{mode}: the program did not pass\n' + (out / 'run.log').read_text()[-2000:])
        execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()), '-Mdelphi', *optimization,
                 '-FE' + str(out), '-FU' + str(out), str(HERE / 'value_forward_semantic.dpr')],
                out, out / 'forward-build.log')
        forward = out / ('value_forward_semantic.exe' if os.name == 'nt' else 'value_forward_semantic')
        lines = execute([str(forward)], out, out / 'forward-run.log').split()
        if not lines or lines[-1] != 'VALUE_FORWARD_PASS':
            fail(f'{mode}: value forwarding semantics failed: {out / "forward-run.log"}')
        witnesses = [args.compiler, args.config, HERE / 'value_in_register.dpr',
                     HERE / 'value_forward_semantic.dpr', binary, forward]
        (out / 'identity.json').write_text(json.dumps({str(p.resolve()): hashlib.sha256(p.read_bytes()).hexdigest()
                                                      for p in witnesses}, indent=2))
    # the objdump of the toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects
    beside = args.compiler.resolve().parent / 'objdump.exe'
    objdump = (os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else None)
               or code_placement.tool('objdump'))
    listing = subprocess.run([objdump, '-d', '-r', '-w', '-M', 'intel', '--no-show-raw-insn',
                              str(args.output / 'O3' / 'value_in_register.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    (args.output / 'O3' / 'listing.txt').write_text(listing, encoding='utf-8')
    counts = routines(listing)
    (args.output / 'counts.json').write_text(json.dumps(counts, indent=2))
    target = 'win64' if os.name == 'nt' else 'linux'
    problems = []
    if target == 'win64':
        problems += inline_cleanup_shape.problems(listing, 'CLEANNAME', 'fpc_unicodestr_decr_ref', 2)
    for name in ('STORERELOAD', 'STOREOTHER'):
        if counts[name][2]:
            problems.append(f'{name}: a 32-bit register extended into itself: {", ".join(counts[name][2])}')
    if counts['CHECKALL'][4]:
        problems.append('CHECKALL: the frame is read or written: ' + ', '.join(counts['CHECKALL'][4][:4]))
    if any(re.search(r'_\$\$_STRINGREPLACE\$', symbol, re.IGNORECASE) for symbol in counts['CLEANNAME'][3]):
        problems.append('CLEANNAME: a StringReplace wrapper is called')
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = {name: counts[name][:2] for name in SHAPES}
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
    recorded = reference.get(target)
    if recorded is None:
        fail(f'reference.json has no counts for {target}; run once with --record')
    shrunk = []
    for name in SHAPES:
        insns, memory = counts[name][:2]
        ref_insns, ref_memory = recorded[name]
        if insns > ref_insns or memory > ref_memory:
            problems.append(f'{name}: {insns} instructions / {memory} memory accesses, '
                            f'reference {ref_insns} / {ref_memory}')
        elif (insns, memory) != (ref_insns, ref_memory):
            shrunk.append(f'{name} {insns}/{memory} < {ref_insns}/{ref_memory}')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'VALUE_IN_REGISTER_GATE_PASS {"/".join(modes)} run; O3 {target}: {len(SHAPES)} routines not above the reference, '
          f'no self-extension, no frame in CheckAll, no StringReplace wrapper call{note}')


if __name__ == '__main__':
    main()
