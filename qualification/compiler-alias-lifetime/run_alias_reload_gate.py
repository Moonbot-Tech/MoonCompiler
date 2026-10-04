"""Instrument a private compiler copy and exercise real PPU reload with retained aliases.

--command is a JSON array of compiler-build arguments. It must contain {source}
and {output} placeholders, e.g. -Fu{source}, -FU{output}, -FE{output}. The command
builds pp.pas from the private source directory; all runtime/config paths must be
absolute. The supplied source needs the normal generated compiler includes.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil

from run_alias_lifetime_gate import check, run


def replace_once(text, old, new):
    assert text.count(old) == 1, old
    return text.replace(old, new)


def instrument(source):
    path = source / 'symbase.pas'
    code = path.read_text()
    code = replace_once(code, '       verbose;', '       verbose;\n\n    var AliasTables, AliasRefs: SizeInt;')
    code = replace_once(code, '         refcount:=1;', '         refcount:=1;\n         Inc(AliasTables); Inc(AliasRefs);')
    code = replace_once(code, '        dec(refcount);', '        Dec(AliasRefs);\n        if refcount=1 then Dec(AliasTables);\n        dec(refcount);')
    code = replace_once(code, '        inc(refcount);', '        Inc(AliasRefs);\n        inc(refcount);')
    assert code.endswith('end.\n')
    path.write_text(code[:-5] + "{$ifndef MEMDEBUG}\nfinalization\n  WriteLn('L2_TABLES ',AliasTables,' ',AliasRefs);\n{$endif}\nend.\n")
    path = source / 'fppu.pas'
    code = path.read_text()
    code = replace_once(code, '        Message1(unit_u_reresolving_unit,modulename^);',
                        "        WriteLn('L2_RERESOLVE ',modulename^);\n        Message1(unit_u_reresolving_unit,modulename^);")
    path.write_text(code)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--command', type=Path,
                        help='JSON build command; otherwise use --compiler and --build-config')
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--build-config', type=Path,
                        help='vanilla/IDE moon-base.cfg used to build compiler sources')
    parser.add_argument('--msg2inc', type=Path,
                        help='installed message generator for a clean compiler source tree')
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.command:
        if args.compiler or args.build_config:
            parser.error('--command cannot be combined with --compiler/--build-config')
        template = json.loads(args.command.read_text())
    else:
        if not args.compiler or not args.build_config:
            parser.error('use --command or both --compiler and --build-config')
        template = [
            str(args.compiler.resolve()), '-n', '@' + str(args.build_config.resolve()),
            '-dMOONCOMPILER_VANILLA_RUNTIME', '-O2', '-Sew', '-Sg', '-dx86_64',
            '-dGDB', '-dBROWSERLOG', '-Fu{source}/x86_64', '-Fu{source}/x86',
            '-Fu{source}/systems', '-Fi{source}/x86_64', '-Fi{source}/x86',
            '-FE{output}', '-FU{output}', '{source}/pp.pas',
        ]
    output = args.output.resolve()
    assert not output.exists(), 'Use a new output directory'
    source = output / 'source'
    shutil.copytree(args.source, source, ignore=shutil.ignore_patterns('*.ppu', '*.o', '*.exe', 'pp'))
    if not (source / 'msgtxt.inc').is_file() or not (source / 'msgidx.inc').is_file():
        if not args.msg2inc:
            parser.error('clean compiler sources require --msg2inc')
        converter = args.msg2inc.resolve()
        if not converter.is_file():
            parser.error(f'msg2inc does not exist: {converter}')
        run([str(converter), 'msg/errore.msg', 'msg', 'msg'], source, output / 'msg2inc.log')
        if not (source / 'msgtxt.inc').is_file() or not (source / 'msgidx.inc').is_file():
            raise RuntimeError('msg2inc did not generate both message includes')
    assert any('{source}' in item for item in template)
    assert any('{output}' in item for item in template)
    original = {name: (source / name).read_bytes() for name in ('symbase.pas', 'fppu.pas')}
    executable = 'pp.exe' if os.name == 'nt' else 'pp'

    def build(name, builder=None, incremental=False, ownership=False):
        destination = output / name
        destination.mkdir(exist_ok=True)
        command = [item.replace('{source}', str(source)).replace('{output}', str(destination)) for item in template]
        if builder is not None:
            command[0] = str(builder)
        command = [item for item in command if item != '-B']
        if not incremental:
            command.insert(1, '-B')
        text = run(command, source, destination / ('incremental.log' if incremental else 'full.log'), ownership)
        if incremental:
            reloads = re.findall(r'^L2_RERESOLVE (.+)$', text, re.M)
            assert reloads, 'The compiler did not actually re-resolve any module'
        return destination / executable

    instrument(source)
    traced = build('trace')
    for name, content in original.items():
        (source / name).write_bytes(content)
    compiler_environment = None
    if args.compiler:
        # The traced compiler lives outside the toolchain, but the product
        # config resolves $FPCBINDIR relative to its executable directory.
        compiler_environment = {**os.environ, 'PPC_EXEC_PATH': str(args.compiler.resolve().parent)}
    check(traced, args.config.resolve(), output / 'ppu', ownership=True,
          compiler_environment=compiler_environment)
    path = source / 'symdef.pas'
    code = path.read_text()
    aliases = '''type
  TReloadEnumAlias = type taitype;
  TReloadRecordAlias = type toper;
  TReloadObjectAlias = type tai_cpu_abstract;
'''
    path.write_text(replace_once(code, '\nimplementation\n', '\n' + aliases + '\nimplementation\n'))
    build('reload', traced, ownership=True)
    path = source / 'aasmtai.pas'
    path.write_text(replace_once(path.read_text(), 'padowner  : tai;', 'padowner  : tai;\n          alias_probe_field : byte;'))
    incremental = build('reload', traced, incremental=True, ownership=True)
    clean = build('clean', traced, ownership=True)
    by_incremental = build('by-incremental', incremental)
    by_clean = build('by-clean', clean)
    hashes = [hashlib.sha256(path.read_bytes()).hexdigest() for path in (by_incremental, by_clean)]
    assert hashes[0] == hashes[1], hashes
    (output / 'result.json').write_text(json.dumps(dict(selfhost_sha256=hashes[0], ownership='0 tables / 0 refs'), indent=2))
    print('ALIAS_RELOAD_GATE_PASS', hashes[0])


if __name__ == '__main__':
    main()
