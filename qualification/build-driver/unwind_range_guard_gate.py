#!/usr/bin/env python3
"""Exercise signed unwind-range boundaries in disposable assembler builds.

This slower Linux x86-64 gate injects resolved label differences, avoiding a
2 GiB allocation. It changes only copies in a new --results directory, never
the supplied compiler sources or installed compiler. Run after a compiler build
has generated msgtxt.inc/msgidx.inc. --bootstrap uses the ordinary FPC/IDE ABI;
--config is the candidate product SDK configuration for the boundary fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from unwind_encoding_gate import run


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler-source', type=Path, required=True)
    ap.add_argument('--bootstrap', type=Path, required=True)
    ap.add_argument('--bootstrap-config', type=Path, required=True)
    ap.add_argument('--config', type=Path, required=True)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--results', type=Path, required=True)
    args = ap.parse_args()
    out = args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = args.compiler_source.resolve()
    shutil.copytree(source, out / 'compiler', ignore=shutil.ignore_patterns('*.o', '*.ppu', 'pp', 'pp.exe'))
    for name in ('units', 'bin'):
        (out / name).mkdir()
    original = (source / 'assemble.pas').read_text(encoding='utf-8')
    anchor = '                         { Compact Linux FDE ranges are signed 32-bit values, even though'
    assert original.count(anchor) == 1, 'update test injection point after moving the range check'
    build = [args.bootstrap.resolve(), '-n', '@' + str(args.bootstrap_config.resolve()),
             '-dMOONCOMPILER_PRODUCT_RUNTIME', '-dMOONCOMPILER_VANILLA_RUNTIME', '-O2', '-Sg',
             '-dx86_64', '-dGDB', '-dBROWSERLOG', '-Fux86_64', '-Fux86', '-Fusystems',
             '-Fix86_64', '-Fix86', '-FE../bin', '-FU../units', 'pp.pas']
    fixture = args.root.resolve() / 'qualification/suite/tests/unwind-encoding/UnwindRange.pas'
    rows = []
    for value in (2147483647, 2147483648, -1):
        injected = ("                         if (ObjData.CurrObjSec.Name='.eh_frame') and "
                    "(objsym.objsection<>ObjData.CurrObjSec) then\n"
                    f'                           Tai_const(hp).value:={value};\n')
        (out / 'compiler/assemble.pas').write_text(original.replace(anchor, injected + anchor), encoding='utf-8')
        # Force the changed assembler to compile even on coarse timestamp filesystems.
        for suffix in ('.ppu', '.o'):
            (out / 'units' / ('assemble' + suffix)).unlink(missing_ok=True)
        run(build, out / 'compiler', f'build-{value}.log')
        for model, flags in [('small', []), ('large', ['-Xa'])]:
            work = out / (str(value) + '-' + model)
            work.mkdir()
            shutil.copyfile(fixture, work / fixture.name)
            expected = int(model == 'small' and value != 2147483647)
            text = run([out / 'bin/pp', '-n', '@' + str(args.config.resolve()), '-B', '-O2',
                        *flags, '-FU' + str(work), fixture.name], work, 'compile.log', expected)
            if expected:
                assert '32-bit DWARF unwind range overflow; recompile with -Xa' in text, text
            rows.append(dict(value=value, model=model, expected_exit=expected))
    (out / 'results.json').write_text(json.dumps(dict(
        assemble_sha256=hashlib.sha256((source / 'assemble.pas').read_bytes()).hexdigest(), cases=rows), indent=2))
    print('UNWIND_RANGE_GUARD_PASS', len(rows))


if __name__ == '__main__':
    main()
