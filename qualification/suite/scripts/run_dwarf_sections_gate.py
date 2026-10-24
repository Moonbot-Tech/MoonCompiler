#!/usr/bin/env python3
"""Exercise the runtime reader against real transformed and damaged ELF/PE sections."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time
import zlib


def sections(data):
    result = {}
    if data[:4] == b'\x7fELF':
        assert data[4:6] == b'\x02\x01', 'gate expects little endian ELF64'
        table = struct.unpack_from('<Q', data, 40)[0]
        stride, count, names_index = struct.unpack_from('<HHH', data, 58)
        names = struct.unpack_from('<Q', data, table + names_index * stride + 24)[0]
        for i in range(count):
            header = table + i * stride
            name = struct.unpack_from('<I', data, header)[0] + names
            name = data[name:data.index(0, name)].decode()
            offset, size = struct.unpack_from('<QQ', data, header + 24)
            flags = struct.unpack_from('<Q', data, header + 8)[0]
            result[name] = dict(offset=offset, size=size, header=header, flags=flags, elf=True)
    else:
        pe = struct.unpack_from('<I', data, 60)[0]
        assert data[pe:pe+4] == b'PE\0\0'
        count = struct.unpack_from('<H', data, pe + 6)[0]
        symbols, symbol_count = struct.unpack_from('<II', data, pe + 12)
        names = symbols + 18 * symbol_count
        optional = struct.unpack_from('<H', data, pe + 20)[0]
        for i in range(count):
            header = pe + 24 + optional + i * 40
            name = data[header:header+8].split(b'\0')[0]
            if name.startswith(b'/'):
                pos = names + int(name[1:])
                name = data[pos:data.index(0, pos)]
            size, offset = struct.unpack_from('<II', data, header + 16)
            result[name.decode()] = dict(offset=offset, size=size, header=header, flags=0, elf=False)
    return result


def main():
    ap = argparse.ArgumentParser(__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--rtl', type=Path, required=True)
    ap.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    ap.add_argument('--mormot', type=Path, required=True)
    ap.add_argument('--results', type=Path, required=True)
    ap.add_argument('--option', action='append', default=[])
    args = ap.parse_args()
    root, rtl, out, mormot = [p.resolve() for p in (args.root, args.rtl, args.results, args.mormot)]
    out.mkdir(parents=True, exist_ok=False)
    if os.name == 'nt':
        ctypes.windll.kernel32.SetErrorMode(0x8003)
    binutils = [f'-FD{args.compiler.resolve().parent}'] if os.name == 'nt' else []
    rows = []
    packages = [f'-Fu{p}' for p in sorted(rtl.parent.iterdir()) if p.is_dir() and p != rtl]
    source = root / 'qualification/suite/tests/smoke/dwarf_sections.pas'
    objcopy = shutil.which('objcopy')
    if os.name != 'nt' and not objcopy:
        raise RuntimeError('objcopy is required: compressed cases may not be skipped')

    def run(exe, label, expect, reports, oracle=None):
        destination = out / (label + '-reports')
        start = time.monotonic()
        p = subprocess.run([str(exe), 'symbols' if expect else 'raw', str(destination)],
                           cwd=out, capture_output=True, timeout=15)
        elapsed = time.monotonic() - start
        log = (p.stdout + p.stderr).decode(errors='replace')
        (out / (label + '.log')).write_text(log, encoding='utf-8')
        assert p.returncode == 0 and 'DWARF_SECTIONS_PASS' in log, (label, p.returncode, log[-2000:])
        lookup = next((line for line in log.splitlines() if line.startswith('LOOKUP=')), None)
        if expect:
            assert lookup and (oracle is None or lookup == oracle), (label, lookup, oracle)
        if reports:
            contents = [f.read_text(encoding='utf-8') for f in destination.glob('*.txt')]
            assert len(contents) == 2, (label, contents)
            assert all(c.endswith('MOON_DIAGNOSTIC_END\n') for c in contents), label
            fault = next(c for c in contents if 'exception_message=DWARF original fault' in c)
            assert 'exception_address=$' in fault and 'original_context=unavailable' not in fault, label
            if expect:
                assert 'OriginalFault' in fault and any('dwarf_sections.pas:'+str(n) in fault for n in (8,9)), (label, fault[-2500:])
            else:
                assert '[symbol unavailable]' in fault, label
        rows.append(dict(case=label, symbols=expect, reports=reports, seconds=elapsed))
        return lookup

    def save_variant(data, exe, label):
        target = out / (label + exe.suffix)
        target.write_bytes(data)
        target.chmod(0o755)
        return target

    for opt in ('O-', 'O3'):
        for reports in (False, True):
            label = f'{opt}-report{int(reports)}'
            build = out / label
            build.mkdir()
            command = [str(args.compiler.resolve()), '-n', '-B', '-dMOONCOMPILER_VANILLA_RUNTIME',
                       '-dMOONCOMPILER_UNICODE_DEFAULT', '-gw3', '-Xs-', '-Xg-', '-' + opt,
                       f'-Fu{rtl}', f'-Fu{root / "runtime/reporting"}', f'-Fu{root / "runtime/mormot"}',
                       *[f'-Fu{mormot / x}' for x in ('core', 'net', 'lib', 'crypt')],
                       f'-Fi{mormot}', f'-Fo{mormot}',
                       f'-Fl{mormot / "static" / ("x86_64-win64" if os.name == "nt" else "x86_64-linux")}',
                       *packages, f'-FU{build}', f'-FE{build}', *binutils, *args.option,
                       *(['-dREPORTS'] if reports else []), str(source)]
            if os.name != 'nt':
                libgcc = subprocess.check_output(['gcc', '-print-file-name=libgcc_s.so'], text=True).strip()
                command.insert(-1, '-Fl' + str(Path(libgcc).parent))
            p = subprocess.run(command, capture_output=True, timeout=120)
            (build/'compile.log').write_bytes(p.stdout+p.stderr)
            assert p.returncode == 0, (build/'compile.log').read_text(errors='replace')[-3000:]
            exe = build / ('dwarf_sections.exe' if os.name == 'nt' else 'dwarf_sections')
            original = exe.read_bytes()
            table = sections(original)
            oracle = run(exe, label+'-raw', True, reports)
            if os.name != 'nt':
                renamed=out/(label+'-mixed-renamed')
                compressed=out/(label+'-mixed-compressed')
                mixed=out/(label+'-mixed')
                subprocess.run([objcopy,'--rename-section','.debug_line=.keep_line',exe,renamed],check=True)
                subprocess.run([objcopy,'--compress-debug-sections=zlib',renamed,compressed],check=True)
                subprocess.run([objcopy,'--rename-section','.keep_line=.debug_line',compressed,mixed],check=True)
                mt=sections(mixed.read_bytes())
                assert mt['.debug_line']['flags'] & 0x800 == 0 and mt['.debug_info']['flags'] & 0x800
                run(mixed,label+'-mixed',True,reports,oracle)
                for method in ('zlib', 'zlib-gnu'):
                    target = out / (label+'-'+method)
                    subprocess.run([objcopy, '--compress-debug-sections='+method, exe, target], check=True)
                    compressed = target.read_bytes()
                    # Compression must not change any loaded section.
                    ct = sections(compressed)
                    for name, sec in table.items():
                        if sec['flags'] & 2 and sec['size'] and name in ct:
                            other = ct[name]
                            # NOBITS has no bytes in the file; compare only PROGBITS-like sections.
                            if struct.unpack_from('<I', original, sec['header']+4)[0] != 8:
                                assert original[sec['offset']:sec['offset']+sec['size']] == compressed[other['offset']:other['offset']+other['size']], name
                    run(target, label+'-'+method, True, reports, oracle)
                    for mutation in ('checksum', 'short-stream', 'bad-size', 'header'):
                        data = bytearray(compressed)
                        sec = ct['.debug_line' if method=='zlib' else '.zdebug_line']
                        pos = sec['offset']
                        if mutation == 'checksum': data[pos+sec['size']-1] ^= 0x55
                        elif mutation == 'short-stream': struct.pack_into('<Q', data, sec['header']+32, sec['size']-2)
                        elif mutation == 'bad-size':
                            if method=='zlib': struct.pack_into('<Q', data, pos+8, 0xffffffffffffffff)
                            else: data[pos+4:pos+12] = b'\xff'*8
                        else: data[pos] ^= 0x80
                        name=label+'-'+method+'-'+mutation
                        run(save_variant(data,exe,name),name,False,reports)

            mutations = [
                ('line-zero-unit','.debug_line',0,'<I',0),
                ('line-reserved-length','.debug_line',0,'<I',0xfffffff0),
                ('line-huge-unit','.debug_line',0,'<I',0x7fffffff),
                ('line-header-overrun','.debug_line',6,'<I',0x7fffffff),
                ('line-zero-range','.debug_line',13,'<B',0),
                ('info-address-size','.debug_info',10,'<B',255),
                ('info-abbrev-overrun','.debug_info',6,'<I',0x7fffffff),
                ('abbrev-id-overflow','.debug_abbrev',0,None,b'\x80'*11),
                ('aranges-zero-unit','.debug_aranges',0,'<I',0),
                ('aranges-huge-unit','.debug_aranges',0,'<I',0x7fffffff),
            ]
            for mutation,section,offset,fmt,value in mutations:
                data=bytearray(original)
                sec=table[section]
                if section == '.debug_info':
                    cu = sec['offset']
                    while cu + 11 <= sec['offset'] + sec['size']:
                        length = struct.unpack_from('<I', original, cu)[0]
                        if length == 0 and not any(original[cu:sec['offset']+sec['size']]): break
                        assert length < 0xfffffff0 and length > 0
                        struct.pack_into(fmt, data, cu + offset, value)
                        cu += 4 + length
                elif section == '.debug_abbrev':
                    info = table['.debug_info']
                    cu = info['offset']
                    while cu + 11 <= info['offset'] + info['size']:
                        length = struct.unpack_from('<I', original, cu)[0]
                        if length == 0 and not any(original[cu:info['offset']+info['size']]): break
                        abbrev = struct.unpack_from('<I', original, cu + 6)[0]
                        assert abbrev + len(value) <= sec['size']
                        data[sec['offset']+abbrev:sec['offset']+abbrev+len(value)] = value
                        cu += 4 + length
                elif fmt: struct.pack_into(fmt,data,sec['offset']+offset,value)
                else: data[sec['offset']+offset:sec['offset']+offset+len(value)] = value
                name=label+'-'+mutation
                run(save_variant(data,exe,name),name,False,reports)
            if os.name != 'nt':
                for mutation, offset, fmt, value in (
                    ('elf-section-table-oob', 40, '<Q', len(original)+4096),
                    ('elf-section-name-index-oob', 62, '<H', 0xffff),
                ):
                    data=bytearray(original)
                    struct.pack_into(fmt,data,offset,value)
                    name=label+'-'+mutation
                    run(save_variant(data,exe,name),name,False,reports)
    if os.name != 'nt':
        build=out/'reader-boundaries'
        build.mkdir()
        source=root/'qualification/suite/tests/smoke/dwarf_boundaries.pas'
        command=[str(args.compiler.resolve()),'-n','-dMOONCOMPILER_VANILLA_RUNTIME',
                 '-gw3','-O2',f'-Fu{rtl}',*packages,f'-FU{build}',f'-FE{build}',
                 *binutils,*args.option,str(source)]
        p=subprocess.run(command,capture_output=True,timeout=120)
        (build/'compile.log').write_bytes(p.stdout+p.stderr)
        assert p.returncode==0,(build/'compile.log').read_text(errors='replace')[-3000:]
        for mode in ('close-io','failure','recursive','concurrent'):
            p=subprocess.run([str(build/'dwarf_boundaries'),mode],capture_output=True,timeout=15)
            log=(p.stdout+p.stderr).decode(errors='replace')
            (build/(mode+'.log')).write_text(log,encoding='utf-8')
            assert p.returncode==0,(mode,p.returncode,log)
            fields=dict(line.split('=',1) for line in log.splitlines() if '=' in line)
            if mode=='close-io':
                assert fields.get('INITIAL','').upper()=='TRUE' and fields.get('IO_PRESERVED','').upper()=='TRUE',(mode,log)
                assert 'Marker' in fields.get('WORKER_TRACE','') and not fields.get('WORKER_ERROR'),(mode,log)
            elif mode=='concurrent':
                assert all('Marker' in fields.get(name,'') for name in ('TRACE_A','TRACE_B')),(mode,log)
                assert fields.get('HOOK_PRESERVED','').upper()=='TRUE',(mode,log)
            elif mode=='failure':
                assert fields.get('TRACE','').startswith('  $') and 'Marker' not in fields['TRACE'],(mode,log)
                assert 'TRACE_ERROR' not in fields and fields.get('HOOK_PRESERVED','').upper()=='TRUE',(mode,log)
                assert fields.get('RETRY','').upper().startswith('TRUE MARKER'),(mode,log)
            else:
                assert fields.get('RECURSIVE_TRACE','').startswith('  $') and 'Marker' not in fields['RECURSIVE_TRACE'],(mode,log)
                assert 'Marker' in fields.get('TRACE','') and 'TRACE_ERROR' not in fields,(mode,log)
                assert fields.get('HOOK_PRESERVED','').upper()=='TRUE' and fields.get('RETRY','').upper().startswith('TRUE MARKER'),(mode,log)
            rows.append(dict(case='reader-'+mode,seconds=None))
    build=out/'inflate-boundary'
    build.mkdir()
    source=root/'qualification/suite/tests/smoke/dwarf_inflate_boundary.pas'
    command=[str(args.compiler.resolve()),'-n','-dMOONCOMPILER_VANILLA_RUNTIME',
             '-O2',f'-Fu{rtl}',*packages,f'-FU{build}',f'-FE{build}',
             *binutils,*args.option,str(source)]
    p=subprocess.run(command,capture_output=True,timeout=120)
    (build/'compile.log').write_bytes(p.stdout+p.stderr)
    assert p.returncode==0,(build/'compile.log').read_text(errors='replace')[-3000:]
    exe=build/('dwarf_inflate_boundary.exe' if os.name=='nt' else 'dwarf_inflate_boundary')
    plain=bytes(i%251 for i in range(16377))
    packed=zlib.compress(plain,0)
    assert len(packed)==16388 and zlib.decompress(packed)==plain
    for name,data,size,expected in (
        ('valid',packed,len(plain),True),
        ('checksum',packed[:-1]+bytes([packed[-1]^0x80]),len(plain),False),
        ('truncated',packed[:-1],len(plain),False),
        ('trailing',packed+b'\0',len(plain),False),
        ('short-output',packed,len(plain)-1,False),
        ('long-output',packed,len(plain)+1,False),
    ):
        fixture=build/(name+'.z')
        fixture.write_bytes(data)
        p=subprocess.run([str(exe),str(fixture),str(size),'pass' if expected else 'fail'],
                         capture_output=True,timeout=15)
        assert p.returncode==0,(name,p.stdout,p.stderr)
        rows.append(dict(case='inflate-'+name,seconds=None))
    build=out/'integer-forms'
    build.mkdir()
    source=root/'qualification/suite/tests/smoke/dwarf_integer_forms.pas'
    command=[str(args.compiler.resolve()),'-n','-dMOONCOMPILER_VANILLA_RUNTIME',
             '-gw3','-O-',f'-Fu{rtl}',*packages,f'-FU{build}',f'-FE{build}',
             *binutils,*args.option,str(source)]
    p=subprocess.run(command,capture_output=True,timeout=120)
    (build/'compile.log').write_bytes(p.stdout+p.stderr)
    assert p.returncode==0,(build/'compile.log').read_text(errors='replace')[-3000:]
    exe=build/('dwarf_integer_forms.exe' if os.name=='nt' else 'dwarf_integer_forms')
    variants={'raw':exe}
    if os.name!='nt':
        for method in ('zlib','zlib-gnu'):
            target=build/('dwarf_integer_forms-'+method)
            subprocess.run([objcopy,'--compress-debug-sections='+method,exe,target],check=True)
            variants[method]=target
    oracle=None
    for name,target in variants.items():
        p=subprocess.run([str(target)],capture_output=True,timeout=15)
        output=(p.stdout+p.stderr).decode(errors='replace')
        assert p.returncode==0 and 'INTEGER_FORMS=Marker|' in output,(name,output)
        if oracle is None: oracle=output
        else: assert output==oracle,(name,output,oracle)
        rows.append(dict(case='integer-forms-'+name,seconds=None))
    (out/'summary.json').write_text(json.dumps(dict(cases=rows, compiler=str(args.compiler), rtl=str(rtl)),indent=2),encoding='utf-8')
    print(f'DWARF_SECTIONS_GATE_PASS {len(rows)} cases')


if __name__ == '__main__': main()
