#!/usr/bin/env python3
"""Check generic identity, lifecycle, catalog, mixed codegen and incremental PPUs."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import time


def check_pdata(exe):
    data = exe.read_bytes()
    pe = struct.unpack_from('<I', data, 60)[0]
    count, optional = struct.unpack_from('<H', data, pe+6)[0], struct.unpack_from('<H', data, pe+20)[0]
    start = pe+24+optional
    for i in range(count):
        offset = start+40*i
        if data[offset:offset+8].rstrip(b'\0') != b'.pdata':
            continue
        size, _, _, raw = struct.unpack_from('<IIII', data, offset+8)
        entries = list(struct.iter_unpack('<III', data[raw:raw+size]))
        assert all(a < b and c for a, b, c in entries), 'invalid unwind range'
        assert len({a for a, _, _ in entries}) == len(entries), 'duplicate unwind entries'
        return len(entries)
    raise AssertionError('missing Windows unwind table')


def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--config', type=Path)
    ap.add_argument('--assembler', choices=('native', 'gas'), default='native')
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    ap.add_argument('--results', type=Path, required=True)
    args = ap.parse_args()
    root, out = args.root.resolve(), args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = root/'qualification/suite/tests/generic-sharing'
    common = [str(args.compiler.resolve())]
    if args.config:
        common += ['-n', '@'+str(args.config.resolve())]
    if args.assembler == 'gas':
        common.append('-Aas')
    rows = []

    def run(command, work, log, timeout=90):
        p = subprocess.run(command, cwd=work, capture_output=True, timeout=timeout)
        (work/log).write_bytes(p.stdout+p.stderr)
        assert p.returncode == 0, (work.name, log, p.returncode,
                                   (p.stdout+p.stderr)[-2500:].decode(errors='replace'))
        return p.stdout.decode(errors='replace').replace('\r\n', '\n')

    def compile(work, target, flags, log='compile.log'):
        return run(common+flags+['-Fu'+str(work), '-FU'+str(work), '-FE'+str(work), target], work, log)

    def execute(work, program):
        exe = work/(program+('.exe' if os.name == 'nt' else ''))
        return run([str(exe)], work, 'runtime.log', 30)

    def prepare(label, case, reverse=False):
        work = out/label
        shutil.copytree(source/case, work)
        if reverse:
            for p in work.glob('*.dpr'):
                value = p.read_text()
                for a, b in [('ConsumerA, ConsumerB', 'ConsumerB, ConsumerA'),
                             ('StateA, StateB', 'StateB, StateA'),
                             ('UnwindA, UnwindB', 'UnwindB, UnwindA'), ('Core,A,B', 'Core,B,A'),
                             ('System.Rtti,A,B', 'System.Rtti,B,A'),
                             ('MappingA, MappingB', 'MappingB, MappingA'),
                             ('ForwardA, ForwardB', 'ForwardB, ForwardA'),
                             ('System.SysUtils,A,B', 'System.SysUtils,B,A')]:
                    value = value.replace(a, b)
                p.write_text(value)
        return work

    def verify(case, output, reverse=False, changed=False):
        pairs = dict(line.split('=', 1) for line in output.splitlines() if '=' in line)
        if case in ('mapping', 'forward'):
            assert output == ('MAPPING_FORWARD_PASS\n' if case == 'mapping' else 'FORWARD_PASS\n'), output
        elif case == 'semantic':
            assert len(pairs) == 15, pairs
            assert pairs.pop('INIT_COUNT') == '5', pairs
            for key, value in pairs.items():
                assert value == ('FALSE' if changed and key in ('CROSS_CAST', 'INVOKE') else 'TRUE'), pairs
        elif case == 'lifetime':
            expected = 'startBA' if reverse else 'startAB'
            assert pairs == dict(SHARED='TRUE', TEXT_A=expected, TEXT_B=expected,
                                 COUNTS='1/1/1/1/1/1', TRACE='ICRBAMabDrF' if reverse else 'ICRABMbaDrF'), pairs
        elif case == 'nested':
            assert pairs == dict(COUNT='1', S='ready/ready', CLASS='TRUE', FIN='1'), pairs
        elif case == 'catalog':
            assert pairs == dict(CLASS='TRUE', CATALOG_MATCHES='1'), pairs
        elif case == 'streaming':
            assert pairs == dict(CLASS='TRUE', STREAMED='TRUE', REGISTERED='TRUE'), pairs
        elif case == 'anonymous-fields':
            assert len(pairs) == 24 and all(value == 'TRUE' for value in pairs.values()), pairs
        elif case == 'type-closure':
            assert len(pairs) == 41 and all(value == 'TRUE' for value in pairs.values()), pairs
        elif case == 'keys':
            assert len(pairs) == 11 and all(v == ('GenericCore' if 'UNIT' in k else 'TRUE')
                                           for k, v in pairs.items()), pairs
        elif case == 'long':
            assert pairs == dict(IDENTITY='TRUE', DISTINCT='TRUE', CAST='TRUE'), pairs
        elif case == 'unwind':
            assert pairs == dict(CLASS='TRUE', LEAF='TRUE', NORMAL='TRUE', CAUGHT='2', FINALIZED='4', SYMBOLIZED='2'), pairs
        elif case == 'neighbors':
            assert pairs == dict(ARRAY_ID='TRUE', FUNC_VALUES='4/4', HELPERS='11/11',
                                 LAYOUT='10/10', RANGE='TRUE/TRUE', OVERFLOW='TRUE/TRUE'), pairs
        elif case == 'rtti-context':
            for prefix in ('A', 'B', 'AR', 'BR', 'AI', 'BI'):
                for field in ('PROPERTY', 'HIDDEN', 'HIDDEN_METHOD'):
                    assert pairs[prefix+'_'+field] == 'FALSE', pairs
                assert pairs[prefix+'_VISIBLE'] == 'TRUE', pairs
                has_method = prefix in ('A', 'B')
                assert pairs[prefix+'_VISIBLE_METHOD'] == ('TRUE' if has_method else 'FALSE'), pairs
                assert pairs[prefix+'_FIELD_ATTRS'] == ('1' if has_method else '0'), pairs
                if has_method:
                    assert pairs[prefix+'_METHOD_ATTRS'] == '1', pairs
                # Class-level generic attributes were absent before sharing.
                # Do not turn that existing limitation into an expected contract.
            assert pairs['AL'] == 'FALSE' and pairs['BL'] == 'TRUE', pairs
        elif case in ('const-kinds', 'const-program'):
            values = dict(Bool='1/0', Int='-1/1', QWord='18446744073709551615/1',
                          WideInt='1/0', Enum='0/1', Char='97/98', Text='abc/abd', Nil='1/1')
            if case == 'const-program':
                values.update(Float='1.25/2.50', FloatClose='1/0', Set='1/0', Zero='1/1')
            for name, expected in values.items():
                assert pairs[name+'_DISTINCT'] == ('FALSE' if name == 'Nil' else 'TRUE'), pairs
                # Anonymous literal types can conservatively retain separate instances.
                if name not in ('Text', 'Set'):
                    assert pairs[name+'_SAME'] == 'TRUE', pairs
                    if case == 'const-kinds':
                        assert pairs[name+'_OUTER_SAME'] == 'TRUE', pairs
                tail = expected if case == 'const-kinds' else expected.split('/')[0]
                assert pairs[name+'_VALUES'] == expected+'/'+tail, pairs
            assert pairs['Unicode_DISTINCT'] == 'TRUE' and pairs['Unicode_SAME'] == 'TRUE', pairs
            assert pairs['UNICODE_FULL_DISTINCT'] == 'TRUE' and pairs['UNICODE_FULL_SAME'] == 'TRUE', pairs
            unicode_values = pairs['Unicode_VALUES'].split('/')
            assert unicode_values[0] == unicode_values[2], pairs
            if case == 'const-kinds':
                assert unicode_values[1] == unicode_values[3], pairs
                assert pairs['Unicode_OUTER_SAME'] == 'TRUE', pairs

    cases = [('mapping', 'Mapping', ['MappingA', 'MappingB']),
             ('forward', 'Forward', ['ForwardA', 'ForwardB']),
             ('semantic', 'Semantic', ['ConsumerA', 'ConsumerB']),
             ('lifetime', 'Life', ['StateA', 'StateB']),
             ('nested', 'Probe', ['A', 'B']),
             ('keys', 'Keys', ['ConsumerA', 'ConsumerB']),
             ('catalog', 'Catalog', ['ConsumerA', 'ConsumerB']),
             ('long', 'LongName', ['A', 'B']),
             ('neighbors', 'Probe', ['A', 'B']),
             ('rtti-context', 'Probe', ['A', 'B']),
             ('const-kinds', 'Probe', ['A', 'B']),
             ('streaming', 'Probe', ['A', 'B']),
             ('type-closure', 'Probe', ['A', 'B']),
             ('anonymous-fields', 'Probe', ['A', 'B'])]
    for profile, flags in [('debug', ['-O-', '-Cr', '-Co']), ('o2', ['-dRELEASE', '-O2']), ('o3', ['-dRELEASE', '-O3'])]:
        for case, program, units in cases:
            for mode in ('together', 'reverse', 'source-free'):
                label = f'{case}-{profile}-{mode}'
                work = prepare(label, case, mode == 'reverse')
                if mode == 'source-free':
                    for unit in units:
                        compile(work, unit+'.pas', flags, unit+'.log')
                        (work/(unit+'.pas')).rename(work/(unit+'.pas.hidden'))
                    for p in work.glob('*.pas'):
                        p.rename(p.with_suffix('.pas.hidden'))
                    compile(work, program+'.dpr', flags)
                else:
                    compile(work, program+'.dpr', flags+['-B'])
                output = execute(work, program)
                verify(case, output, mode == 'reverse')
                rows.append(dict(case=label, output=output))
        work = prepare('const-program-'+profile, 'const-program')
        compile(work, 'Probe.dpr', flags+['-B'])
        output = execute(work, 'Probe')
        verify('const-program', output)
        rows.append(dict(case=work.name, output=output))
        print('PASS', profile, 'identity, lifetime, nested, keys, catalog, long names', flush=True)

    # The runtime oracle must reject a deliberately wrong explicit mapping.
    for profile, flags in [('debug', ['-O-']), ('o2', ['-dRELEASE', '-O2']), ('o3', ['-dRELEASE', '-O3'])]:
        work = prepare('mapping-negative-'+profile, 'mapping')
        compile(work, 'Mapping.dpr', flags+['-B', '-dWRONG_MAPPING'])
        binary = work/('Mapping.exe' if os.name == 'nt' else 'Mapping')
        p = subprocess.run([str(binary)], cwd=work, capture_output=True, text=True, timeout=30)
        (work/'negative.log').write_text(p.stdout+p.stderr)
        assert p.returncode == 91 and 'CONTRACT_REJECTED: MAPPING: main dispatch' in p.stdout, (p.returncode, p.stdout, p.stderr)
        rows.append(dict(case=work.name, negative_rejected=True))
    # Unimplemented concrete/other formal arguments cannot bind to a compatible interface.
    for program in ('WrongConcrete', 'WrongFormal'):
        work = prepare('mapping-'+program, 'mapping')
        command = common+['-dRELEASE', '-O2', '-Fu'+str(work), '-FU'+str(work), '-FE'+str(work), program+'.dpr']
        p = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=90)
        (work/'negative.log').write_text(p.stdout+p.stderr)
        assert p.returncode != 0 and 'Interface identifier expected' in p.stdout, (p.returncode, p.stdout, p.stderr)
        rows.append(dict(case=work.name, negative_rejected=True))

    # The initial template switches are persisted even without explicit directives.
    for checked in (False, True):
        work = prepare('default-switches-'+str(checked), 'default-switches')
        for unit, checks in [('Core', checked), ('A', True), ('B', False)]:
            compile(work, unit+'.pas', ['-dRELEASE', '-O2', '-Cr' if checks else '-Cr-',
                                       '-Co' if checks else '-Co-'], unit+'.log')
            (work/(unit+'.pas')).rename(work/(unit+'.pas.hidden'))
        main_source = (work/'Probe.dpr').read_text()
        for reverse in (False, True):
            program = 'ProbeReverse' if reverse else 'ProbeForward'
            (work/(program+'.dpr')).write_text(main_source.replace('A,B', 'B,A') if reverse else main_source)
            compile(work, program+'.dpr', ['-dRELEASE', '-O2'], program+'.log')
            output = execute(work, program)
            expected = 'TRUE/TRUE' if checked else 'FALSE/FALSE'
            assert output == 'RANGE='+expected+'\nOVERFLOW='+expected+'\n', output
            rows.append(dict(case=work.name+'-'+program, output=output))

    # An optimized leaf can have no unwind record while the discarded debug copy
    # has one. Both link orders must retain the record of the selected code only.
    for compact in (False, True):
        profile = ['-dRELEASE'] if compact else []
        for reverse in (False, True):
            work = prepare(f'unwind-{compact}-{reverse}', 'unwind', reverse)
            for unit, flags in [('UnwindA', ['-O-']), ('UnwindB', ['-O3'])]:
                compile(work, unit+'.pas', profile+flags, unit+'.log')
                (work/(unit+'.pas')).rename(work/(unit+'.pas.hidden'))
            compile(work, 'UnwindCheck.dpr', profile+['-O2', '-gl-'])
            output = execute(work, 'UnwindCheck')
            verify('unwind', output)
            if os.name == 'nt':
                check_pdata(work/'UnwindCheck.exe')
            rows.append(dict(case=work.name, output=output))

    work = prepare('incremental', 'semantic')
    def edit(file, before, after):
        p = work/file
        text = p.read_text()
        assert before in text
        # PPU timestamps have second resolution. This exercises the normal
        # source-change path, without forcing a clean build or deleting caches.
        time.sleep(1.05)
        p.write_text(text.replace(before, after))

    def cached(label, changed):
        program = 'Semantic_'+label.replace('-', '_')
        executable = work/(program+('.exe' if os.name == 'nt' else ''))
        compile(work, 'Semantic.dpr', ['-dRELEASE', '-O2', '-o'+str(executable)], label+'.log')
        output = execute(work, program)
        verify('semantic', output, changed=changed)
        rows.append(dict(case=label, output=output))

    cached('clean', False)
    cached('cached', False)
    edit('GenericCore.pas', 'Result := X + 7', 'Result := X + 8')
    cached('implementation-change', True)
    edit('GenericCore.pas', '    Value: T;', '    Padding: array[0..12] of Int64;\n    Value: T;')
    cached('layout-change', True)
    edit('ConsumerA.pas', 'GenericCore;', 'GenericCore;\ntype TInterfaceChange = record X: Int64; end;')
    cached('consumer-interface-change', True)
    edit('ConsumerA.pas', 'implementation', 'implementation\nuses ConsumerB;')
    edit('ConsumerB.pas', 'implementation', 'implementation\nuses ConsumerA;')
    cached('implementation-cycle', True)
    edit('Semantic.dpr', 'ConsumerA, ConsumerB', 'ConsumerB, ConsumerA')
    cached('reverse-cached', True)
    print('PASS mixed unwind and incremental interfaces, layouts, cycles', flush=True)

    # Existing public consumers: discovery, attributes, Invoke and managed arrays.
    for relative, marker in [('qualification/suite/tests/rtti/rtti_gettypes.dpr', 'RTTI_GETTYPES_PASS'),
                             ('RTL-test/semantic/rtti_invoke_product_semantic.dpr', 'RTTI_INVOKE'),
                             ('RTL-test/semantic/managed_array_rtti_semantic.dpr', 'MANAGED_ARRAY_RTTI_OK')]:
        src = root/relative
        work = out/src.stem
        work.mkdir()
        compile(work, str(src), ['-B', '-dRELEASE', '-Fu'+str(src.parent)])
        output = execute(work, src.stem)
        assert marker in output, output
        rows.append(dict(case=src.stem, output=output))
    record = dict(compiler_sha256=hashlib.sha256(args.compiler.read_bytes()).hexdigest(), assembler=args.assembler, cases=rows)
    (out/'results.json').write_text(json.dumps(record, indent=2))
    print('GENERIC_SHARING_PASS', len(rows), flush=True)


if __name__ == '__main__':
    main()
