"""Small code-shape sentinels over objdump output; no frozen instruction bytes.

The generated fixture uses the internal assembler and checks strategy, bounds
and selector width without freezing instruction addresses or padding.
"""
from pathlib import Path
import json
import re
import subprocess
import os
import shutil


def make_source(directory):
    definitions = ['unit asm_paths;', '{$mode delphi}', '{$INLINE OFF}', 'interface',
                   'type TEnum37 = ('+', '.join('e'+str(i) for i in range(37))+');',
                   'TEnum240 = ('+', '.join('n'+str(i) for i in range(240))+');',
                   'TSparse = ('+', '.join('s'+str(i)+'='+str(i*100) for i in range(12))+');']
    definitions += ['TEnum12 = ('+', '.join('b'+str(i) for i in range(12))+');',
                    'TEnum13 = ('+', '.join('c'+str(i) for i in range(13))+');']
    bodies = []
    def func(name, typename, groups, label=str):
        definitions.append(f'function {name}(X:{typename}):Integer;')
        body = [f'function {name}(X:{typename}):Integer;', 'begin case X of']
        for i, group in enumerate(groups):
            labels = ','.join(label(v) for v in group)
            body.append(f'{labels}: Result:={199+i*37};')
        body += ['else Result:=-1; end; end;']
        bodies.extend(body)
    func('DenseEnum37', 'TEnum37', [[i] for i in range(37)], lambda x:'e'+str(x))
    func('DenseEnum12', 'TEnum12', [[i] for i in range(12)], lambda x:'b'+str(x))
    func('DenseEnum13', 'TEnum13', [[i] for i in range(13)], lambda x:'c'+str(x))
    func('AlmostEnum240', 'TEnum240', [[i] for i in range(240)], lambda x:'n'+str(x))
    func('AlmostByte240', 'Byte', [[i] for i in range(240)])
    func('FullByte256', 'Byte', [[i] for i in range(256)])
    func('SparseEnum', 'TSparse', [[i] for i in range(12)], lambda x:'s'+str(x))
    func('SparseWord', 'Word', [[i*100] for i in range(12)])
    func('GroupedEnum', 'TEnum37', [list(range(i,37,3)) for i in range(3)], lambda x:'e'+str(x))
    func('GroupedByte', 'Byte', [list(range(i,37,3)) for i in range(3)])
    func('Signed64', 'Int64', [[i] for i in range(-7,8)])
    (directory/'asm_paths.pas').write_text('\n'.join(definitions+['implementation']+bodies+['end.'])+'\n')


def check_shapes(disassembly, section_headers):
    chunks = re.split(r'Disassembly of section ([^\r\n]+):\r?\n', disassembly)
    functions = {chunks[i].lower(): chunks[i+1] for i in range(1, len(chunks), 2)}
    sizes = {m[1].lower(): int(m[2], 16) for m in
             re.finditer(r'^\s*\d+\s+(\S+)\s+([0-9a-fA-F]+)\s', section_headers, re.M)}
    report = {}

    def instructions(name):
        matches = [text for section, text in functions.items() if '$$_'+name.lower()+'$' in section]
        if len(matches) != 1:
            raise AssertionError(f'{name}: expected one text section, got {len(matches)}')
        result = []
        for line in matches[0].splitlines():
            m = re.match(r'^\s*[0-9a-f]+:\s+([a-z][a-z0-9]*)\s*(.*)$', line)
            if m:
                result.append((m[1], m[2]))
        if any(op.startswith('call') for op, _ in result):
            raise AssertionError(f'{name}: case path gained a helper call')
        return result

    def table_bytes(name):
        return sum(size for section, size in sizes.items()
                   if '$$_'+name.lower()+'$' in section and
                   (section.startswith('.rdata') or section.startswith('.rodata')))

    def indirect(item):
        return item[0].startswith('jmp') and item[1].startswith('*')

    for name, labels in [('DenseEnum12', 12), ('DenseEnum13', 13)]:
        ops = instructions(name)
        equal_branches = sum(op in ('je', 'jz') for op, _ in ops)
        if any(map(indirect, ops)) or table_bytes(name) or equal_branches < labels-1:
            raise AssertionError(f'{name}: expected the established linear chain')
        report[name] = 'linear'

    for name, slots, guard in [('DenseEnum37', 37, True), ('AlmostEnum240', 256, False),
                               ('AlmostByte240', 256, False), ('FullByte256', 256, False)]:
        ops = instructions(name)
        dispatch = next((i for i, item in enumerate(ops) if indirect(item)), None)
        if dispatch is None or not slots*4 <= table_bytes(name) <= slots*4+7:
            raise AssertionError(f'{name}: missing compact 32-bit offset table for {slots} slots')
        prefix = ops[:dispatch]
        bounds = any(op in ('ja', 'jae', 'jnbe', 'jnb') for op, _ in prefix)
        if bounds != guard:
            raise AssertionError(f'{name}: expected guard={guard}, got {bounds}')
        report[name] = 'guarded table' if guard else 'full storage table'

    for name in ('SparseEnum', 'SparseWord'):
        ops = instructions(name)
        if any(map(indirect, ops)) or table_bytes(name) or not any(op in ('jb', 'ja', 'jl', 'jg') for op, _ in ops):
            raise AssertionError(f'{name}: sparse case lost its comparison tree')
        report[name] = 'comparison tree'

    for name in ('GroupedEnum', 'GroupedByte'):
        ops = instructions(name)
        if any(map(indirect, ops)) or sum(op.startswith('bt') for op, _ in ops) < 3:
            raise AssertionError(f'{name}: grouped case lost its set-membership lowering')
        report[name] = 'set membership'

    ops = instructions('Signed64')
    if not any(op == 'cmpq' or op == 'cmp' and re.search(r'%r(?:[abcd]x|[sd]i|[89]|1[0-5])\b', args)
               for op, args in ops):
        raise AssertionError('Signed64: selector check lost its full 64-bit width')
    report['Signed64'] = '64-bit selector'
    return report


def run_shapes(compiler, config, directory):
    directory.mkdir()
    make_source(directory)
    command = [str(compiler), '-n', '@'+str(config), '-O3', '-FU'+str(directory),
               '-FE'+str(directory), str(directory/'asm_paths.pas')]
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=120)
    (directory/'compile.log').write_text(result.stdout+result.stderr, encoding='utf-8')
    result.check_returncode()
    objdump = os.environ.get('MOON_OBJDUMP') or shutil.which('objdump')
    if not objdump and os.name == 'nt':
        binary = Path(os.environ['LOCALAPPDATA'])/'MoonCompiler/bootstrap/3.2.2/bin/i386-win32'
        objdump = next((str(binary/name) for name in ('x86_64-win64-objdump.exe', 'objdump.exe')
                        if (binary/name).is_file()), None)
    if not objdump:
        raise RuntimeError('objdump is required for case strategy checks')
    result = subprocess.run([objdump, '-h', '-d', '--no-show-raw-insn', str(directory/'asm_paths.o')],
                            capture_output=True, text=True, timeout=30)
    (directory/'disassembly.log').write_text(result.stdout+result.stderr, encoding='utf-8')
    result.check_returncode()
    report = check_shapes(result.stdout, result.stdout)
    (directory/'result.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('CASE_SHAPES_PASS', len(report), flush=True)
    return report
