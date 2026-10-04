#!/usr/bin/env python3
"""The value of an inlined string or dynamic-array getter, and a field of a record with managed fields that a getter
returns by value, is read straight from its source where its consumer finishes reading before any code can run
(compiler/optcall.pas, mark_funcret_borrow).

Compiles getter_borrow.dpr at -O2 and -O3 with the product compiler and config and runs it.  In the -O3 object every
routine of the probe is counted - instructions without padding and calls, a routine together with its outlined
finalizer - and compared with reference.json for the target: a routine that grew is red, one that shrank is reported so
that the reference is renewed on purpose (--record writes it).  Independently of the reference:
  the borrowed forms call no assignment helper, no release and no finalizer (fpc_*_assign*, *_decr_ref,
  fpc_dynarray_clear, _fin$);
  KeepToCall, KeepChainToCall, KeepIndexCall and KeepRecordToCall still take the result's own reference
  (fpc_unicodestr_assign*, the record's FPC_COPY)."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

BORROWED = ('GETTERLENGTH', 'GETTERCHAR', 'GETTERCOMPARE', 'GETTEREMPTY', 'GETTERELEMENT', 'GETTERLOOP', 'LISTFIND',
            'LISTLENGTHS', 'LISTFIRSTCHARS', 'NESTEDEMPTY', 'NESTEDLENGTH', 'NESTEDSUM', 'CHAINCOMPARE', 'CHAINLENGTH',
            'FIELDLISTFIND', 'FIELDCHAINELEMENT', 'RECORDFIELD', 'RECORDCOMPARE', 'RECORDELEMENT')
KEPT = ('KEEPTOCALL', 'KEEPCHAINTOCALL', 'KEEPINDEXCALL', 'KEEPRECORDTOCALL')
# a string or array reference, the copy of a record with managed fields, their release and cleanup frame
REFERENCE_CALL = re.compile(r'fpc_\w*_assign|_decr_ref|fpc_dynarray_clear|_fin\$|FPC_COPY|fpc_initialize|fpc_finalize',
                            re.IGNORECASE)
OWN_REFERENCE = re.compile(r'fpc_unicodestr_assign|FPC_COPY', re.IGNORECASE)
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*[0-9a-f]+:\t(.*)$')
# objdump -r -w writes the relocation of an instruction on its own line or behind it
RELOC = re.compile(r'[0-9a-f]+: R_\S+\s+(\S+)')


def fail(message):
    raise SystemExit('GETTER_BORROW_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routines(listing):
    """name -> (instructions, calls, called symbols) of the probe routines: a routine and its outlined finalizer
    ($_$NAME$..._fin$, a method's $_$CLASS_$_NAME$..._fin$) count together"""
    found = {name: [0, 0, []] for name in BORROWED + KEPT}
    current = None
    last_call = False
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            current = next((name for name in found
                            if re.search(r'(_\$\$_|\$_\$|_\$_)' + re.escape(name) + r'\$', head[1])), None)
            last_call = False
            continue
        if current is None:
            continue
        insn = INSN.match(line)
        if not insn:
            reloc = RELOC.search(line)
            if reloc and last_call:
                found[current][2].append(reloc[1])
            continue
        relocs = RELOC.findall(insn[1])
        text = re.sub(r'^(?:ds |cs |data16 )+', '', RELOC.sub('', insn[1]).strip())
        last_call = False
        if not text or text.startswith(('nop', 'xchg   ax,ax', 'int3', '(bad)')) or text == 'add    BYTE PTR [rax],al':
            continue
        found[current][0] += 1
        if text.startswith('call'):
            found[current][1] += 1
            last_call = not relocs
            found[current][2].extend(relocs)
            target = re.search(r'<([^>]+)>', text)
            if target:
                found[current][2].append(target[1])
    missing = [name for name, (count, _, _) in found.items() if count == 0]
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
    for mode in ('O2', 'O3'):
        out = args.output / mode
        out.mkdir()
        execute([str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()), '-' + mode,
                 '-FE' + str(out), '-FU' + str(out), str(HERE / 'getter_borrow.dpr')], out, out / 'build.log')
        binary = out / ('getter_borrow.exe' if os.name == 'nt' else 'getter_borrow')
        if execute([str(binary)], out, out / 'run.log').strip() != 'GETTER_BORROW_PASS':
            fail(f'{mode}: the program did not pass')
    # the objdump of the toolchain reads the relocations of its own COFF objects, which a MinGW objdump rejects
    beside = args.compiler.resolve().parent / 'objdump.exe'
    objdump = (os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else None)
               or code_placement.tool('objdump'))
    listing = subprocess.run([objdump, '-d', '-r', '-w', '-M', 'intel', '--no-show-raw-insn',
                              str(args.output / 'O3' / 'getter_borrow.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    counts = routines(listing)
    target = 'win64' if os.name == 'nt' else 'linux'
    problems = []
    for name in BORROWED:
        calls = [symbol for symbol in counts[name][2] if REFERENCE_CALL.search(symbol)]
        if calls:
            problems.append(f'{name}: the borrowed value takes a reference: {", ".join(calls)}')
    for name in KEPT:
        if not any(OWN_REFERENCE.search(symbol) for symbol in counts[name][2]):
            problems.append(f'{name}: the result lost its own reference (the RR-06 hole)')
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = {name: counts[name][:2] for name in counts}
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
    recorded = reference.get(target)
    if recorded is None:
        fail(f'reference.json has no counts for {target}; run once with --record')
    shrunk = []
    for name in counts:
        insns, calls = counts[name][:2]
        ref_insns, ref_calls = recorded[name]
        if insns > ref_insns or calls > ref_calls:
            problems.append(f'{name}: {insns} instructions / {calls} calls, reference {ref_insns} / {ref_calls}')
        elif (insns, calls) != (ref_insns, ref_calls):
            shrunk.append(f'{name} {insns}/{calls} < {ref_insns}/{ref_calls}')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'GETTER_BORROW_GATE_PASS O2/O3 run; O3 {target}: {len(BORROWED)} borrowed forms without a reference, '
          f'{len(KEPT)} kept forms with their own, no routine above the reference{note}')


if __name__ == '__main__':
    main()
