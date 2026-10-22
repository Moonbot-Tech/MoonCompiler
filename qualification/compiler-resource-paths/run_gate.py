"""Check RC file paths and resource bytes, independently of the resource reader."""
import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import sys


def read_res(path):
    data = path.read_bytes()
    pos, records = 0, {}
    def ident(offset):
        first, = struct.unpack_from('<H', data, offset)
        if first == 0xffff:
            return struct.unpack_from('<H', data, offset + 2)[0], offset + 4
        end = offset
        while struct.unpack_from('<H', data, end)[0]:
            end += 2
        return data[offset:end].decode('utf-16le'), end + 2
    while pos < len(data):
        size, header = struct.unpack_from('<II', data, pos)
        assert header >= 8 and pos + header + size <= len(data), 'invalid RES bounds'
        kind, cursor = ident(pos + 8)
        name, cursor = ident(cursor)
        cursor = (cursor + 3) & ~3
        assert cursor + 16 <= pos + header, 'invalid RES metadata'
        language, = struct.unpack_from('<H', data, cursor + 6)
        if kind != 0:
            key = (kind, name, language)
            assert key not in records, 'duplicate resource'
            records[key] = data[pos + header:pos + header + size]
        pos += header + size
        if pos < len(data):
            pos = (pos + 3) & ~3
    assert pos == len(data) and records, 'empty or truncated resource file'
    return records


def main():
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='backslashreplace')
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--fpcres', type=Path, help='Defaults to the compiler tools directory')
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--config', type=Path)
    args = ap.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    fpcres = (args.fpcres or args.compiler.resolve().with_name('fpcres.exe' if os.name == 'nt' else 'fpcres')).resolve()
    rows = []
    payload = bytes(range(256)) + b'\x00\\\xffresource payload\r\n'
    # The vanilla Classes ABI used to bootstrap fpcres has an ANSI
    # TFileStream filename. Preserve its supported repertoire; includes below
    # separately exercise full Unicode, without that stream-constructor limit.
    native_name = 'файл'
    if os.name == 'nt':
        import ctypes
        native_cp = 'cp' + str(ctypes.windll.kernel32.GetACP())
        for name in ('файл', 'café', 'ソ', '文件'):
            try:
                if name.encode(native_cp).decode(native_cp) == name:
                    native_name = name
                    break
            except UnicodeError:
                pass
        else:
            raise AssertionError('No non-ASCII filename fixture for ' + native_cp)

    def run(cmd, cwd, log):
        # Missing includes must fail, not silently read a valid RC from stdin.
        proc = subprocess.run([str(x) for x in cmd], cwd=cwd, capture_output=True,
                              input=b'STDIN_DECOY RCDATA BEGIN 1 END\n', timeout=30,
                              creationflags=0x08000000 if os.name == 'nt' else 0)
        text = (proc.stdout + proc.stderr).decode(errors='replace')
        log.write_text(text, encoding='utf-8')
        return proc.returncode, text

    def case(name, rc_text, files, expected, failure=None, extra_args=()):
        work = root / name
        source, caller = work / 'source', work / 'caller'
        source.mkdir(parents=True)
        caller.mkdir()
        for rel, content in files.items():
            dest = source / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(content)
        # A successful load must use RC-relative files, not these caller decoys.
        (caller / 'data').mkdir()
        (caller / 'data/payload.bin').write_bytes(b'WRONG CALLER')
        rc = source / 'input.rc'
        rc.write_text('#pragma code_page(65001)\nLANGUAGE 0, 0\n' + rc_text, encoding='utf-8')
        output = work / 'output.res'
        try:
            code, text = run([fpcres, rc, '-of', 'res', '-o', output, *extra_args], caller, work / 'compile.log')
            if failure:
                assert code != 0 and failure in text, (code, text)
            else:
                assert code == 0, (code, text)
                actual = read_res(output)
                assert actual == expected, f'resource content differs: {list(actual)} vs {list(expected)}'
            rows.append(dict(case=name, passed=True))
        except (AssertionError, OSError, ValueError, struct.error, subprocess.TimeoutExpired) as exc:
            rows.append(dict(case=name, passed=False, error=str(exc)))

    expected = {(10, 'TEST', 0): payload}
    refs = {
        'forward': ('data/payload.bin', 'data/payload.bin'),
        'backslash': (r'data\payload.bin', 'data/payload.bin'),
        'doubled': (r'data\\payload.bin', 'data/payload.bin'),
        'mixed': (r'data\nested/payload.bin', 'data/nested/payload.bin'),
        'spaces': (r'data folder\payload file.bin', 'data folder/payload file.bin'),
        'dot': (r'.\data\payload.bin', 'data/payload.bin'),
        'parent': (r'data\..\payload.bin', 'payload.bin'),
        'escape-n': (r'data\new.bin', 'data/new.bin'),
        'escape-t': (r'data\test.bin', 'data/test.bin'),
        'escape-r': (r'data\read.bin', 'data/read.bin'),
        'unicode': (f'data\\{native_name}.bin', f'data/{native_name}.bin'),
    }
    for name, (ref, disk) in refs.items():
        files = {disk: payload, 'data/directory-marker': b''}
        case(name, f'TEST RCDATA "{ref}"', files, expected)
    case('unquoted', r'TEST RCDATA data\payload.bin', {'data/payload.bin': payload}, expected)
    case('macro', '#define FILE_REF "data\\payload.bin"\nTEST RCDATA FILE_REF',
         {'data/payload.bin': payload}, expected)
    case('custom-type', r'TEST 777 "data\payload.bin"', {'data/payload.bin': payload}, {(777, 'TEST', 0): payload})
    absolute = root / 'absolute asset.bin'
    absolute.write_bytes(payload)
    case('absolute', f'TEST RCDATA "{absolute}"', {}, expected)
    case('missing', r'TEST RCDATA "missing\payload.bin"', {}, {}, 'Unable to open file')
    case('caller-only', r'TEST RCDATA "data\payload.bin"', {}, {}, 'Unable to open file')
    for name, ref in [('include-forward', 'inc/header.h'), ('include-backslash', r'inc\header.h'),
                      ('include-doubled', r'inc\\header.h')]:
        case(name, f'#include "{ref}"\nTEST RCDATA FILE_REF',
             {'inc/header.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('included-resource', '#include "inc/part.rc"',
         {'inc/part.rc': b'TEST RCDATA "data\\payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('include-single-character', '#include "a"\nTEST RCDATA FILE_REF',
         {'a': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('include-spaces', '#include "inc folder\\header file.h"\nTEST RCDATA FILE_REF',
         {'inc folder/header file.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('include-unicode', '#include "данные\\файл.h"\nTEST RCDATA FILE_REF',
         {'данные/файл.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('include-unicode-wide', '#include "inc\\😀.h"\nTEST RCDATA FILE_REF',
         {'inc/😀.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    case('include-nested', '#include "inc\\one.h"\nTEST RCDATA FILE_REF',
         {'inc/one.h': b'#include "inc\\two.h"\n',
          'inc/two.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected)
    for depth in (6, 7):
        files = {'data/payload.bin': payload}
        for index in range(depth):
            files[f'level{index}.h'] = (f'#include "level{index+1}.h"\n'.encode() if index+1 < depth
                                      else b'#define FILE_REF "data/payload.bin"\n')
        case(f'include-depth-{depth}', '#include "level0.h"\nTEST RCDATA FILE_REF', files, expected,
             failure='Too many include levels' if depth == 7 else None)
    case('include-cycle', '#include "cycle.h"', {'cycle.h': b'#include "cycle.h"\n'}, {},
         'Too many include levels')
    case('include-missing', '#include "missing\\header.h"\nTEST RCDATA "data/payload.bin"',
         {'data/payload.bin': payload}, {}, 'Include file not found')
    case('include-invalid', '#include header.h\nTEST RCDATA "data/payload.bin"',
         {'data/payload.bin': payload}, {}, 'Invalid include directive')
    case('include-empty', '#include ""\nTEST RCDATA "data/payload.bin"',
         {'data/payload.bin': payload}, {}, 'Invalid include directive')
    case('include-search-path', '#include <inc\\header.h>\nTEST RCDATA FILE_REF',
         {'search/inc/header.h': b'#define FILE_REF "data/payload.bin"\n', 'data/payload.bin': payload}, expected,
         extra_args=('-I', str(root / 'include-search-path/source/search')))
    case('include-search-missing', '#include <missing\\header.h>\nTEST RCDATA "data/payload.bin"',
         {'data/payload.bin': payload}, {}, 'Include file not found on search paths',
         extra_args=('-I', str(root / 'include-search-missing/source')))

    dib = struct.pack('<IiiHHIIiiII', 40, 1, 1, 1, 32, 0, 4, 0, 0, 0, 0) + b'\x11\x22\x33\xff'
    bmp = struct.pack('<2sIHHI', b'BM', 14 + len(dib), 0, 0, 54) + dib
    case('bitmap', r'TEST BITMAP "data\pixel.bmp"', {'data/pixel.bmp': bmp}, {(2, 'TEST', 0): dib})
    image = struct.pack('<IiiHHIIiiII', 40, 1, 2, 1, 32, 0, 4, 0, 0, 0, 0) + b'\x11\x22\x33\xff' + b'\0' * 4
    for name, filetype, childtype, grouptype in [('icon', 1, 3, 14), ('cursor', 2, 1, 12)]:
        if filetype == 2:
            image = struct.pack('<IiiHHIIiiII', 40, 1, 2, 1, 1, 0, 4, 0, 0, 2, 0) + b'\0\0\0\0\xff\xff\xff\0' + b'\x80\0\0\0' + b'\0' * 4
        directory = struct.pack('<BBBBHHII', 1, 1, 0, 0, 1 if filetype == 1 else 0,
                                32 if filetype == 1 else 0, len(image), 22)
        contents = struct.pack('<HHH', 0, filetype, 1) + directory + image
        if filetype == 1:
            group = struct.pack('<HHHBBBBHHIH', 0, 1, 1, 1, 1, 0, 0, 1, 32, len(image), 1)
            child = image
        else:
            group = struct.pack('<HHHHHHHIH', 0, 2, 1, 1, 2, 1, 1, len(image) + 4, 1)
            child = b'\0' * 4 + image
        case(name, f'TEST {name.upper()} "data\\pixel.{name}"', {f'data/pixel.{name}': contents},
             {(grouptype, 'TEST', 0): group, (childtype, 1, 0): child})

    text = 'a\\b\nc\td'
    entries = [b'\0\0'] * 16
    entries[1] = struct.pack('<H', len(text)) + text.encode('utf-16le')
    case('string-table', 'STRINGTABLE\nBEGIN\n1 "a\\\\b\\nc\\td"\nEND', {}, {(6, 1, 0): b''.join(entries)})
    case('inline-data', 'TEST RCDATA BEGIN "a\\\\b\\nc\\td", 123 END', {},
         {(10, 'TEST', 0): text.encode('ascii') + struct.pack('<H', 123)})

    compiler = [args.compiler.resolve()]
    if args.config:
        compiler += ['-n', '@' + str(args.config.resolve())]
    for profile, flags in [('debug', ['-O-', '-uRELEASE']), ('release', ['-O3', '-dRELEASE'])]:
        name = 'consumer-' + profile
        work = root / name
        source, build, caller = work / 'source', work / 'build', work / 'caller'
        for directory in (source, build, caller):
            directory.mkdir(parents=True)
        (source / 'assets').mkdir()
        (source / 'assets/payload.bin').write_bytes(bytes(range(256)))
        (source / 'inc').mkdir()
        (source / 'inc/header.h').write_text('#define FILE_REF "assets\\\\payload.bin"\n')
        (source / 'payload.rc').write_text('#include "inc\\header.h"\nTEST RCDATA FILE_REF\n')
        app = source / 'consumer.dpr'
        app.write_text('''program consumer;
{$mode delphiunicode}
{$R payload.rc}
uses Classes, SysUtils;
var S: TResourceStream; I: Integer; B: Byte;
begin
  S:= TResourceStream.Create(HInstance, 'TEST', PChar(10));
  try
    If S.Size <> 256 then Halt(2);
    for I:= 0 to 255 do begin
      S.ReadBuffer(B, 1);
      If B <> I then Halt(3);
    end;
  finally S.Free end;
  Writeln('RC_CONSUMER_PASS');
end.
''')
        try:
            assert not list(work.rglob('*.res')) and not list(work.rglob('*.dres'))
            code, text = run(compiler + flags + ['-FF', '-FD' + str(fpcres.parent),
                             '-FU' + str(build), '-FE' + str(build), app], caller, work / 'compile.log')
            assert code == 0, (code, text)
            exe = build / ('consumer.exe' if os.name == 'nt' else 'consumer')
            code, text = run([exe], caller, work / 'run.log')
            assert code == 0 and text.strip() == 'RC_CONSUMER_PASS', (code, text)
            rows.append(dict(case=name, passed=True))
        except (AssertionError, OSError, subprocess.TimeoutExpired) as exc:
            rows.append(dict(case=name, passed=False, error=str(exc)))

    (root / 'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    failures = [r for r in rows if not r['passed']]
    for row in failures:
        print(row['case'], row['error'][-600:])
    print(f'FPCRES_PATHS {"FAIL" if failures else "PASS"} {len(rows)-len(failures)}/{len(rows)}')
    raise SystemExit(bool(failures))


if __name__ == '__main__':
    main()
