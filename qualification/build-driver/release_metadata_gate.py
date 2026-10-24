#!/usr/bin/env python3
"""Prove installed Release metadata policy and runtime equivalence to full DWARF."""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'qualification/suite/scripts'))
from run_dwarf_sections_gate import sections
from rtl_profile_gate import without_debug
from elf_link_bindings import check as check_link_bindings


def loaded(path: Path) -> dict:
    data = path.read_bytes()
    result = {}
    for name, sec in sections(data).items():
        p = sec['header']
        if sec['elf']:
            if not sec['flags'] & 2:
                continue
            kind = struct.unpack_from('<I', data, p+4)[0]
            address = struct.unpack_from('<Q', data, p+16)[0]
            size, flags = sec['size'], sec['flags']
            contents = b'' if kind == 8 else data[sec['offset']:sec['offset']+size]
        else:
            flags = struct.unpack_from('<I', data, p+36)[0]
            if not flags & 0xe0000000 or flags & 0x02000000:
                continue
            size, address = struct.unpack_from('<II', data, p+8)
            contents = data[sec['offset']:sec['offset']+sec['size']]
        result[name] = (address, size, flags, hashlib.sha256(contents).hexdigest())
    return result


def elf_bindings(path: Path) -> dict:
    data = path.read_bytes()
    table = sections(data)
    symbols = subprocess.check_output(['readelf','--dyn-syms','-W',str(path)],text=True)
    symbols = sorted(tuple(line.split()[1:8]) for line in symbols.splitlines()
                     if re.match(r'\s*\d+:',line))
    relocs = []
    text = subprocess.check_output(['readelf','-rW',str(path)],text=True)
    for line in text.splitlines():
        fields = line.split()
        if len(fields) < 5 or not re.fullmatch(r'[0-9a-f]{12,16}',fields[0]):
            continue
        offset = int(fields[0],16)
        location = fields[0]
        for name in ('.got','.got.plt'):
            sec = table.get(name)
            if sec:
                start = struct.unpack_from('<Q',data,sec['header']+16)[0]
                if start <= offset < start+sec['size']:
                    location = name
        relocs.append((location,*fields[2:]))
    got = {}
    for name in ('.got','.got.plt'):
        if name in table:
            sec = table[name]
            raw = data[sec['offset']:sec['offset']+sec['size']]
            got[name] = sorted(n[0] for n in struct.iter_unpack('<Q',raw))
    return dict(symbols=symbols,relocations=sorted(relocs),got=got)


def object_payload(path: Path, objdump: str) -> str:
    value = without_debug(path,objdump)
    assert not isinstance(value,str), value
    # DWARF consumes assembler label IDs; removing it renumbers later private
    # data labels. Preserve their one-to-one identity, payload and relocations.
    labels = {}
    def label(match):
        return labels.setdefault(match[0],'.Ld'+str(len(labels)))
    return re.sub(r'\.Ld\d+\b',label,'\n'.join(value[0]+value[1]))


def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--toolchain', type=Path, default=ROOT/'toolchain')
    ap.add_argument('--results', type=Path, required=True)
    ap.add_argument('--root', type=Path, default=ROOT)
    args = ap.parse_args()
    root, tc, out = (p.resolve() for p in (args.root, args.toolchain, args.results))
    out.mkdir(parents=True, exist_ok=False)
    win = os.name == 'nt'
    bindir = tc/('bin/x86_64-win64' if win else 'bin')
    compiler = bindir/('ppcx64.exe' if win else 'ppcx64')
    cfgdir = bindir if win else tc/'etc'
    versions = [tc] if win else [p for p in (tc/'lib/fpc').glob('[0-9]*') if (p/'units').is_dir()]
    assert len(versions) == 1, ('ambiguous installed compiler version',versions)
    unitparent = versions[0]
    target = 'x86_64-win64' if win else 'x86_64-linux'
    objdump = shutil.which('objdump', path=str(bindir)+os.pathsep+os.environ['PATH'])
    assert objdump, 'objdump is required'
    fullbase = (cfgdir/'moon-base.cfg').read_text()
    releasebase = (cfgdir/'moon-release-base.cfg').read_text()
    assert releasebase == fullbase.replace('/units/', '/units-release/'), 'profile search paths differ beyond metadata'
    config = (cfgdir/'fpc.cfg').read_text()
    for basename, contents in [('moon-release-base.cfg', releasebase), ('moon-base.cfg', fullbase)]:
        config = re.sub(r'^#INCLUDE .*?/'+re.escape(basename)+r'$', lambda m: contents, config, flags=re.M)
    config = config.replace('$FPCBINDIR', bindir.as_posix())
    fullconfig = config.replace('/units-release/', '/units/').replace(
        '-goDWARFLINETABLESONLY', '-goNODWARFLINETABLESONLY')
    fullconfig = re.sub(r'^-Xs\s*$', '-Xs-', fullconfig, flags=re.M)
    fullconfig = fullconfig.replace('-k--compress-debug-sections=zlib', '')
    fullcfg = out/'full.cfg'
    fullcfg.write_text(fullconfig, encoding='utf-8')
    releasecfg = out/'release.cfg'
    releasecfg.write_text(config, encoding='utf-8')

    def run(argv, cwd, log, timeout=120):
        p = subprocess.run([str(x) for x in argv], cwd=cwd, capture_output=True, timeout=timeout)
        log.write_bytes(p.stdout+p.stderr)
        assert p.returncode == 0, (argv, p.returncode, (p.stdout+p.stderr)[-3000:].decode(errors='replace'))
        return p.stdout

    # Inspect complete installed SDK objects, not only a newly compiled caller.
    def tags(path):
        p = subprocess.run([objdump, '--dwarf=info', str(path)], capture_output=True, timeout=60)
        assert p.returncode == 0, (path, p.stderr[-500:])
        return collections.Counter(t.decode() for t in re.findall(rb'\((DW_TAG_[a-z_]+)\)', p.stdout))

    for relative in ('rtl/sysutils.o', 'rtl/classes.o', 'rtl-objpas/rtti.o', 'rtl-generics/generics.hashes.o'):
        a = tags(unitparent/'units'/target/relative)
        b = tags(unitparent/'units-release'/target/relative)
        assert len(a) > 2 and b['DW_TAG_subprogram'], (relative,a,b)
        assert set(b) <= {'DW_TAG_compile_unit','DW_TAG_subprogram'}, (relative,b)

    record = dict(line.split('=',1) for line in (tc/'profile.txt').read_text().splitlines() if '=' in line)
    assert '-goDWARFLINETABLESONLY' in record['release_rtl_packages_opt']
    for key, relative in [('release_sysutils_o_sha256','rtl/sysutils.o'),
                          ('release_generics_hashes_o_sha256','rtl-generics/generics.hashes.o')]:
        assert record[key] == hashlib.sha256((unitparent/'units-release'/target/relative).read_bytes()).hexdigest(), key

    cases = [
        ('lookup',root/'qualification/suite/tests/smoke/dwarf_sections.pas',['symbols']),
        ('catalog',root/'qualification/suite/tests/rtti/rtti_gettypes.dpr',[]),
        ('invoke',root/'RTL-test/semantic/rtti_invoke_product_semantic.dpr',[]),
        ('managed',root/'RTL-test/semantic/managed_array_rtti_semantic.dpr',[]),
    ]
    rows = []
    for label, source, arguments in cases:
        variants = {}
        for mode in ('full','release'):
            work = out/(label+'-'+mode)
            work.mkdir()
            argv = [compiler,*(['-n','@'+str(fullcfg)] if mode == 'full' else []),
                    '-B','-dRELEASE',*(['-gl-'] if label == 'lookup' else []),
                    '-Fu'+str(source.parent),'-FU'+str(work),'-FE'+str(work),source]
            run(argv,work,work/'compile.log')
            exe = work/(source.stem+('.exe' if win else ''))
            runtime = run([exe,*arguments],work,work/'runtime.log')
            own_tags = tags(work/(source.stem+'.o'))
            if mode == 'release':
                assert set(own_tags) <= {'DW_TAG_compile_unit','DW_TAG_subprogram'}, own_tags
                if win:
                    data = exe.read_bytes()
                    pe = struct.unpack_from('<I',data,60)[0]
                    assert struct.unpack_from('<I',data,pe+16)[0] == 0, 'static COFF symbols retained'
                else:
                    table = sections(exe.read_bytes())
                    assert '.symtab' not in table and '.strtab' not in table
                    assert all(table[n]['flags'] & 0x800 for n in ('.debug_info','.debug_line','.debug_abbrev','.debug_aranges'))
            variants[mode] = dict(bytes=exe.stat().st_size, loaded=loaded(exe), output=runtime.decode(errors='replace'), tags=own_tags)
        assert variants['full']['output'] == variants['release']['output'], label
        assert variants['full']['loaded'].keys() == variants['release']['loaded'].keys(), 'loaded sections changed'
        differences = {name for name in variants['full']['loaded']
                       if variants['full']['loaded'][name] != variants['release']['loaded'].get(name)}
        if differences:
            # GNU ld can reorder GOT/PLT entries when object metadata changes.
            # Prove identical instructions and target bindings, not just outputs.
            assert not win, (label,differences)
            assert differences <= {'.hash','.gnu.hash','.dynsym','.dynstr','.gnu.version','.gnu.version_r',
                                   '.rela.dyn','.rela.plt','.init','.text','.got','.got.plt'}, differences
            a,b = out/(label+'-full'),out/(label+'-release')
            for obj in a.glob('*.o'):
                assert object_payload(obj,objdump) == object_payload(b/obj.name,objdump), obj.name
            for relative in ('rtl/sysutils.o','rtl/classes.o','rtl-objpas/rtti.o','rtl-generics/generics.hashes.o'):
                x = object_payload(unitparent/'units'/target/relative,objdump)
                y = object_payload(unitparent/'units-release'/target/relative,objdump)
                assert x == y, relative
            assert elf_bindings(a/source.stem) == elf_bindings(b/source.stem), 'dynamic binding changed'
            check_link_bindings(a/source.stem,b/source.stem)
            assert all(variants['full']['loaded'][n][:3] == variants['release']['loaded'][n][:3]
                       for n in differences), 'loaded layout changed'
        variants['linker_reordered_sections'] = sorted(differences)
        rows.append(dict(case=label,variants=variants))
        print('PASS',label,variants['full']['bytes'],'->',variants['release']['bytes'],flush=True)

    # A protection/signing pipeline may need an intermediate build-only symbol
    # map. -Xs- must retain it without restoring debugger-only type information.
    source = cases[0][1]
    for name, flags in [('build-symbols',['-Xs-'])] + ([] if win else [('gnu-compression',['-k--compress-debug-sections=zlib-gnu'])]):
        work = out/name
        work.mkdir()
        run([compiler,'-B','-dRELEASE','-gl-',*flags,'-FU'+str(work),'-FE'+str(work),source],work,work/'compile.log')
        exe = work/(source.stem+('.exe' if win else ''))
        assert run([exe,'symbols'],work,work/'runtime.log').decode() == rows[0]['variants']['release']['output']
        data = exe.read_bytes()
        if win:
            pe = struct.unpack_from('<I',data,60)[0]
            assert struct.unpack_from('<I',data,pe+16)[0] > 0, '-Xs- did not retain static symbols'
        else:
            table = sections(data)
            assert ('.symtab' in table) == (name == 'build-symbols'), name
            if name == 'gnu-compression':
                assert '.zdebug_info' in table and '.zdebug_line' in table
        assert set(tags(work/(source.stem+'.o'))) <= {'DW_TAG_compile_unit','DW_TAG_subprogram'}

    # Flattened DWARF must still describe methods whose parent type DIE is absent.
    source = root/'qualification/suite/tests/smoke/metadata_lookup_main.pas'
    for mode in ('full','release'):
        work = out/('methods-'+mode)
        work.mkdir()
        run([compiler,*(['-n','@'+str(fullcfg)] if mode == 'full' else []),
             '-B','-dRELEASE','-gl-','-Fu'+str(source.parent),'-FU'+str(work),'-FE'+str(work),source],
            work,work/'compile.log')
        runtime = run([work/(source.stem+('.exe' if win else ''))],work,work/'runtime.log').decode()
        expected = {'INIT':'_init', 'CLASS':'Execute', 'RECORD':'Execute', 'GENERIC':'Execute',
                    'NESTED':'Inner', 'ANONYMOUS':'Invoke'}
        if mode == 'release':
            expected.update(CLASS='TClassCase.Execute', RECORD='TRecordCase.Execute', GENERIC='TGenericCase<')
        for label, name in expected.items():
            line = next(s for s in runtime.splitlines() if s.startswith(label+'|'))
            parts = line.split('|')
            assert name in parts[1] and int(parts[3]) > 0, (mode,line)
        assert 'LOOKUP_PASS' in runtime

    # Catch boundary names and DWARF5 ULEB counts in the installed compiler.
    run([sys.executable,Path(__file__).with_name('release_metadata_regression.py'),
         '--compiler',compiler,'--config',releasecfg,'--fullconfig',fullcfg,
         '--objdump',objdump,'--results',out/'name-boundaries','--root',root],
        out,out/'name-boundaries.log',timeout=600)

    # Automatic directories must not reuse old full-DWARF Release PPUs.
    cache = out/'cache'
    cache.mkdir()
    (cache/'cacheunit.pas').write_text('unit CacheUnit; interface function Value:Integer; implementation function Value:Integer; begin Result:=42 end; end.')
    source = cache/'CacheProbe.dpr'
    source.write_text('program CacheProbe; uses CacheUnit; begin WriteLn(Value) end.')
    old = cache/'units'/target/'release'
    old.mkdir(parents=True)
    run([compiler,'-n','@'+str(fullcfg),'-dRELEASE','-FU'+str(old),'-FE'+str(cache),source],cache,cache/'old.log')
    original = hashlib.sha256((old/'cacheunit.o').read_bytes()).hexdigest()
    run([compiler,'-dRELEASE',source],cache,cache/'release.log')
    compact = cache/'units'/target/'release-compact'
    assert (compact/'cacheunit.ppu').is_file(), 'compact Release reused old output directory'
    assert set(tags(compact/'cacheunit.o')) <= {'DW_TAG_compile_unit','DW_TAG_subprogram'}
    assert original == hashlib.sha256((old/'cacheunit.o').read_bytes()).hexdigest()
    run([compiler,source],cache,cache/'debug.log')
    assert (cache/'units'/target/'debug'/'cacheunit.ppu').is_file()
    (out/'summary.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
    print('RELEASE_METADATA_GATE_PASS',len(rows),'runtime cases; SDK metadata, stripping, compression, cache separation')


if __name__ == '__main__':
    main()
