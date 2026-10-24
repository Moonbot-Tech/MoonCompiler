#!/usr/bin/env python3
"""Deterministic Linux signal-context unwind at actual Pascal instruction PCs."""
import argparse, hashlib, json, re, shutil, subprocess
from pathlib import Path

def run(argv, cwd=None):
    return subprocess.run([str(x) for x in argv], cwd=cwd, capture_output=True, text=True, timeout=30)

def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--results', type=Path, required=True)
    ap.add_argument('--config', type=Path)
    ap.add_argument('--optimization', action='append', help='Comma-separated compiler flags; may be repeated')
    args = ap.parse_args()
    source = Path(__file__).resolve().parent
    out = args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve(strict=True)
    backend = compiler.with_name('ppcx64')
    if not backend.is_file():
        backend = compiler
    evidence = {'compiler': str(compiler), 'sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                'backend': str(backend), 'backend_sha256': hashlib.sha256(backend.read_bytes()).hexdigest(),
                'config_sha256': hashlib.sha256(args.config.read_bytes()).hexdigest() if args.config else None, 'modes': []}
    for opt in args.optimization or ('-O-', '-O2', '-O3', '-O-,-Os', '-O3,-Os'):
        work = out/opt.replace('-', '').replace(',', '_')
        work.mkdir()
        for name in ('unwind_traps.c', 'unwind_traps.dpr'):
            shutil.copy2(source/name, work/name)
        p = run(['gcc', '-O2', '-c', '-o', 'unwind_traps_helper.o', 'unwind_traps.c'], work)
        assert p.returncode == 0, p.stderr
        p = run([compiler, *(['-n', '@'+str(args.config.resolve(strict=True))] if args.config else []), '-B', '-dRELEASE', '-Xs-', *opt.split(','), '-OoNOAUTOINLINE', '-FU.', '-FE.', 'unwind_traps.dpr'], work)
        (work/'compile.log').write_text(p.stdout+p.stderr)
        assert p.returncode == 0, p.stdout+p.stderr
        binary = work/'unwind_traps'
        listing = run(['objdump', '-d', '--no-show-raw-insn', binary]).stdout
        (work/'disassembly.txt').write_text(listing)
        blocks = re.split(r'(?m)^([0-9a-f]+) <([^>]+)>:\n', listing)
        functions = {}
        for i in range(1, len(blocks), 3):
            address, name, body = blocks[i:i+3]
            for label in ('AuditLeaf', 'AuditEH', 'AuditMiddle', 'AuditAnchor'):
                if ('$$_'+label.upper()) in name:
                    rows = [(int(a, 16), asm.strip()) for a, asm in re.findall(r'(?m)^\s*([0-9a-f]+):\s+(\S[^\n]*)', body)]
                    functions[label] = {'start': int(address, 16), 'end': int(blocks[i+3], 16), 'rows': rows}
        assert len(functions) == 4, functions
        anchor = functions['AuditAnchor']
        rows = []
        for label in ('AuditLeaf', 'AuditEH', 'AuditMiddle'):
            for pc, instruction in functions[label]['rows']:
                if instruction.startswith(('add    %al,', 'nop')):
                    continue
                p = run([binary, hex(pc), hex(anchor['start']), hex(anchor['end']), '0'], work)
                row = {'function': label, 'pc': hex(pc), 'instruction': instruction, 'returncode': p.returncode, 'output': p.stdout.strip()}
                assert p.returncode in (0, 1, 77), (row, p.stderr)
                if p.returncode == 0:
                    ips = [int(s, 16) for s in p.stdout.split('ERROR=')[1].split()[1:]]
                    chain = [next((name for name, span in functions.items() if span['start'] <= ip < span['end']), '?') for ip in ips]
                    expected = ['AuditLeaf', 'AuditEH', 'AuditMiddle', 'AuditAnchor'] if label == 'AuditLeaf' else ['AuditEH', 'AuditMiddle', 'AuditAnchor'] if label == 'AuditEH' else ['AuditMiddle', 'AuditAnchor']
                    row['valid_chain'] = chain[:len(expected)] == expected
                    row['chain'] = chain
                rows.append(row)
        for label in ('AuditLeaf', 'AuditEH', 'AuditMiddle'):
            covered = [r for r in rows if r['function'] == label and r['returncode'] in (0,1)]
            assert covered and any(r['instruction'].startswith('ret') for r in covered), (label, covered)
            assert any(int(r['pc'],16) == functions[label]['start'] for r in covered), label
            if '-O-' in opt.split(',') and '-Os' in opt.split(','):
                assert any(r['instruction'] == 'leave' for r in covered), (label, 'LEAVE was not exercised')
        if any(flag in opt.split(',') for flag in ('-O2', '-O3')):
            # The pressure values must really exercise every intermediate POP.
            pops = [r for r in rows if r['function'] == 'AuditEH'
                    and r['returncode'] in (0, 1) and r['instruction'].startswith('pop')]
            for reg in ('rbx', 'r12', 'r13', 'r14', 'r15'):
                assert any('%' + reg in r['instruction'] for r in pops), (opt, reg, pops)
            # An eight-byte local is released with POP RCX before RET.
            assert any(r['function'] == 'AuditLeaf' and r['returncode'] in (0, 1)
                       and r['instruction'] == 'pop    %rcx' for r in rows), (opt, 'missing local-slot POP')
        negative = run([binary, hex(functions['AuditLeaf']['start']), hex(anchor['start']), hex(anchor['end']), '1'], work)
        assert negative.returncode == 1 and 'ANCHOR=0 DEPTH=1' in negative.stdout, negative
        record = {'optimization': opt, 'functions': functions, 'rows': rows, 'covered': sum(r['returncode'] in (0,1) for r in rows), 'failures': [r for r in rows if r['returncode'] == 1 or r.get('valid_chain') is False], 'unreached': sum(r['returncode'] == 77 for r in rows), 'negative': negative.stdout.strip()}
        evidence['modes'].append(record)
        (out/'results.json').write_text(json.dumps(evidence, indent=2))
        print(opt, 'covered=', record['covered'], 'unreached=', record['unreached'], 'failures=', len(record['failures']), flush=True)
    failures = sum(len(row['failures']) for row in evidence['modes'])
    print('UNWIND_TRAPS_PASS' if not failures else 'UNWIND_TRAPS_FAIL '+str(failures), flush=True)
    raise SystemExit(bool(failures))

if __name__ == '__main__':
    main()
