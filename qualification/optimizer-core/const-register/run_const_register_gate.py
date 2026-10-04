#!/usr/bin/env python3
"""A float constant which a procedure reads more than once lives in a register temp from the entry (do_consttovar,
compiler/optcse.pas).  The register allocator (compiler/rgobj.pas) knows that the temp holds its constant: spilled, it
reads the constant's memory - no stack slot, no store, no load at the entry - and a value the colouring leaves without a
register takes the colour of constants, which go to their memory, where their reads cost less than its loads and stores
and the colouring stays complete.

Compiles const_register.dpr at -O2 and -O3 with the product compiler and config and runs it (every routine is checked
against the same arithmetic on writable typed constants; a store into the memory of a literal constant would fault).
In the -O3 object a loop is a backward jump inside a routine, and a constant in memory is a rip-relative operand (Win64,
PIC) or an absolute address (a Linux executable):
  HOURDELTAS   - Max/Min expanded in the loop, 0, 1 and 100 needed after it: no xmm value stored to the stack inside the
                 loop (main kept 1 and 100 in registers and stored a variable of the loop on every turn);
  PRESSURELOOP - Max/Min expanded, 0.25 three times a turn of a loop that needs every register: no scalar float stored
                 to the stack (main stored the register of 0.25 to the stack at the entry and read it from there);
  WITNESS14    - the same without any call: no scalar float stored to the stack;
  INLOOP2      - no call, 0.125 twice a turn, accumulators read and written on every turn: no scalar float stored to
                 the stack;
  BRANCHLOOP   - no call, 0.5 in both branches of a loop with few variables: the constant is loaded into a register
                 before the loop and the loop reads at most one constant from memory (the compare);
  REVERSE      - 0.75 four times a turn of a loop that needs every register, a value written before it and read after
                 it: the loop reads no constant from memory;
  DELTAS       - the hour deltas written out, the constant 1 read twice after the loop: no register which Win64 saves
                 and restores (xmm6-xmm15) is written only by loads of constants.
Every routine is counted - instructions without padding - against reference.json of the target: a routine that grew is
red, one that shrank is reported so that the reference is renewed on purpose (--record writes it)."""
from pathlib import Path
import argparse, json, os, re, subprocess, sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'performance' / 'tools'))
import code_placement  # noqa: E402

ROUTINES = ('HOURDELTAS', 'PRESSURELOOP', 'WITNESS14', 'INLOOP2', 'BRANCHLOOP', 'REVERSE', 'DELTAS')
HEAD = re.compile(r'^[0-9a-f]+ <(.+)>:$')
INSN = re.compile(r'^\s*([0-9a-f]+):\t(.*)$')
PAD = ('nop', 'xchg   ax,ax', 'int3', 'data16', 'cs nop', 'ds nop', '(bad)')
# a constant in memory: rip-relative (Win64, PIC) or an absolute address (a Linux executable)
MEMORY = re.compile(r'\[rip[+-]|ds:0x')
# a scalar float stored to the stack (a callee-saved register is saved whole, XMMWORD)
STORE = re.compile(r'^mov\w*\s+(QWORD|DWORD) PTR \[r[sb]p[^\]]*\],xmm')


def fail(message):
    raise SystemExit('CONST_REGISTER_GATE_FAIL ' + message)


def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        fail(f'{command[0]} exited {result.returncode}\n' + (result.stdout + result.stderr)[-2000:])
    return result.stdout


def routines(listing):
    """name -> [(address, instruction)] of the probe routines, padding apart"""
    found = {name: [] for name in ROUTINES}
    current = None
    for line in listing.splitlines():
        head = HEAD.match(line.strip())
        if head:
            current = next((name for name in ROUTINES if re.search(r'_\$\$_' + name + r'\$', head[1])), None)
            continue
        insn = INSN.match(line)
        if current is None or not insn:
            continue
        text = insn[2].strip()
        if not text or text.startswith(PAD) or text == 'add    BYTE PTR [rax],al':
            continue
        found[current].append((int(insn[1], 16), text))
    missing = [name for name, body in found.items() if not body]
    if missing:
        fail('no routine in the -O3 object: ' + ', '.join(missing))
    return found


def shape(body):
    """loops, xmm stores to the stack inside a loop, constants read from memory inside a loop, xmm loads of a
    constant before the first loop, scalar float stores to the stack anywhere"""
    loops = []
    for address, text in body:
        jump = re.match(r'j\w+\s+([0-9a-f]+)', text)
        if jump and int(jump[1], 16) < address:
            loops.append((int(jump[1], 16), address))
    inside = [text for address, text in body if any(a <= address <= b for a, b in loops)]
    spills = [text for text in inside if re.match(r'mov\w*\s+\w+ PTR \[r[sb]p', text) and 'xmm' in text]
    memory = [text for text in inside if MEMORY.search(text) and 'xmm' in text]
    first = min((a for a, _ in loops), default=None)
    preload = [text for address, text in body
               if (first is None or address < first) and re.match(r'mov\w*\s+xmm\d+,\w+ PTR ', text)
               and MEMORY.search(text)]
    stores = [text for _, text in body if STORE.match(text)]
    return loops, spills, memory, preload, stores


def constant_only_saved(body):
    """the callee-saved xmm registers a routine saves and writes only with loads of constants"""
    saved = {m[1] for _, text in body
             for m in [re.match(r'^mov(?:dq[au]|ap[sd]|up[sd])\s+XMMWORD PTR \[r[sb]p[^\]]*\],(xmm(?:[6-9]|1[0-5]))$', text)]
             if m}
    result = []
    for register in sorted(saved):
        # the restore of the register at the exit is no writer
        writers = [text for _, text in body
                   if re.match(r'^\w+\s+' + register + r',', text)
                   and not re.match(r'^mov(?:dq[au]|ap[sd]|up[sd])\s+' + register + r',XMMWORD PTR \[r[sb]p', text)]
        if writers and all(re.match(r'^movs[sd]\s+' + register + r',(QWORD|DWORD) PTR ', text) and MEMORY.search(text)
                           for text in writers):
            result.append(register)
    return result


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
                 '-FE' + str(out), '-FU' + str(out), str(HERE / 'const_register.dpr')], out, out / 'build.log')
        binary = out / ('const_register.exe' if os.name == 'nt' else 'const_register')
        if execute([str(binary)], out, out / 'run.log').strip() != 'CONST_REGISTER_PASS':
            fail(f'{mode}: the program did not pass')
    beside = args.compiler.resolve().parent / 'objdump.exe'
    objdump = (os.environ.get('MOON_OBJDUMP') or (str(beside) if beside.is_file() else None)
               or code_placement.tool('objdump'))
    listing = subprocess.run([objdump, '-d', '-w', '-M', 'intel', '--no-show-raw-insn',
                              str(args.output / 'O3' / 'const_register.o')], capture_output=True, text=True,
                             encoding='utf-8', errors='replace').stdout
    bodies = routines(listing)
    problems = []
    shapes = {name: shape(body) for name, body in bodies.items()}
    for name in ROUTINES:
        if not shapes[name][0]:
            problems.append(f'{name}: no loop found')
    loops, spills, memory, preload, stores = shapes['HOURDELTAS']
    if spills:
        problems.append('HOURDELTAS: a variable of the loop is stored to the stack: ' + '; '.join(spills))
    for name in ('PRESSURELOOP', 'WITNESS14', 'INLOOP2'):
        stores = shapes[name][4]
        if stores:
            problems.append(f'{name}: a float value is stored to the stack: ' + '; '.join(stores))
    loops, spills, memory, preload, stores = shapes['BRANCHLOOP']
    if not preload or len(memory) > 1:
        problems.append(f'BRANCHLOOP: the constant of the loop is not in a register ({len(preload)} loads before the '
                        f'loop, {len(memory)} constants read from memory inside it)')
    loops, spills, memory, preload, stores = shapes['REVERSE']
    if memory:
        problems.append('REVERSE: the loop reads its constant from memory: ' + '; '.join(memory))
    held = constant_only_saved(bodies['DELTAS'])
    if held:
        problems.append('DELTAS: saved and restored for constants alone: ' + ', '.join(held))
    target = 'win64' if os.name == 'nt' else 'linux'
    counts = {name: len(body) for name, body in bodies.items()}
    reference_path = HERE / 'reference.json'
    reference = json.loads(reference_path.read_text()) if reference_path.is_file() else {}
    if args.record:
        reference[target] = counts
        reference_path.write_text(json.dumps(reference, indent=1, sort_keys=True) + '\n')
    recorded = reference.get(target)
    if recorded is None:
        fail(f'reference.json has no counts for {target}; run once with --record')
    shrunk = []
    for name, count in counts.items():
        if name not in recorded:
            problems.append(f'{name}: no count in reference.json for {target}; run once with --record')
        elif count > recorded[name]:
            problems.append(f'{name}: {count} instructions, reference {recorded[name]}')
        elif count < recorded[name]:
            shrunk.append(f'{name} {count} < {recorded[name]}')
    if problems:
        fail('-O3 object:\n  ' + '\n  '.join(problems))
    note = ('; shorter than the reference, renew it with --record: ' + ', '.join(shrunk)) if shrunk else ''
    print(f'CONST_REGISTER_GATE_PASS O2/O3 run; O3 {target}: no float value of HOURDELTAS, PRESSURELOOP, WITNESS14 '
          f'and INLOOP2 in the stack, BRANCHLOOP and REVERSE keep their constant in a register, DELTAS saves no '
          f'register for constants alone; counts within the reference{note}')


if __name__ == '__main__':
    main()
