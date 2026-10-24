#!/usr/bin/env python3
"""Stdlib-only long-name and DWARF5 count gate for installed MoonCompiler."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


CLASS = 'T' + 'A' * 126
M126 = 'M' + 'B' * 125
M127 = 'M' + 'C' * 126
INNER = 'T' + 'D' * 120
GENERIC = 'TGeneric' + 'G' * 70
LONG_TYPE = 'T' + 'E' * 126


def source_text():
    return f'''program NameBoundaries;
uses SysUtils, lnfodwrf;
type
  {CLASS}=class
    class procedure {M126}; static; noinline;
    class procedure {M127}; static; noinline;
    class procedure Following; static; noinline;
  end;
  TOuter=class
  public type
    {INNER}=class
      class procedure {M127}; static; noinline;
    end;
  end;
  {LONG_TYPE}=record X:Integer end;
  {GENERIC}<T>=class
    class procedure {M127}; static; noinline;
  end;
var CallCount:Integer;
procedure Probe(const LabelName:string); noinline;
var F,S:ShortString; L:LongInt; OK:Boolean;
begin
  OK:=GetLineInfo(PtrUInt(get_caller_addr(get_frame)),F,S,L);
  Writeln(LabelName,'|',OK,'|',F,'|',S,'|',L);
  If not OK or (S='') or (L<=0) then Halt(3);
end;
class procedure {CLASS}.{M126}; begin Probe('254'); Inc(CallCount); end;
class procedure {CLASS}.{M127}; begin Probe('255'); Inc(CallCount); end;
class procedure {CLASS}.Following; begin Probe('following'); Inc(CallCount); end;
class procedure TOuter.{INNER}.{M127}; begin Probe('256'); Inc(CallCount); end;
class procedure {GENERIC}<T>.{M127}; begin Probe('generic'); Inc(CallCount); end;
begin
  {CLASS}.{M126};
  {CLASS}.{M127};
  {CLASS}.Following;
  {{$IFDEF TEST_COMPACT}}
  TOuter.{INNER}.{M127};
  {GENERIC}<{LONG_TYPE}>.{M127};
  If CallCount<>5 then Halt(9);
  {{$ELSE}}
  If CallCount<>3 then Halt(9);
  {{$ENDIF}}
end.
'''


def invoke(argv, cwd, log):
    proc = subprocess.run([str(x) for x in argv], cwd=cwd, capture_output=True, timeout=120)
    log.write_bytes(proc.stdout + proc.stderr)
    assert proc.returncode == 0, (argv, proc.returncode, (proc.stdout + proc.stderr)[-1000:])
    return proc.stdout


def compiled_names(objdump, exe, work):
    proc = subprocess.run([objdump, '--dwarf=info', str(exe)], capture_output=True, timeout=60)
    (work / 'objdump.log').write_bytes(proc.stdout + proc.stderr)
    assert proc.returncode == 0 and not proc.stderr, (exe, proc.stderr[-500:])
    return proc.stdout.decode(errors='replace')


def run_names(compiler, config, objdump, out, fullconfig, section_reader):
    source = out / 'NameBoundaries.dpr'
    source.write_text(source_text())
    modes = [(True, False, False), (True, True, False), (True, False, True), (True, True, True),
             (False, False, False), (False, True, False),
             (False, False, True), (False, True, True)]
    for compression in ([None] if os.name == 'nt' else ['none', 'zlib']):
        for compact, prefix, cpp in modes:
            mode = '-'.join(('compact' if compact else 'full',
                             'prefix' if prefix else 'plain', 'cpp' if cpp else 'pas', compression or 'pe'))
            work = out / mode
            work.mkdir()
            flags = ['-n', '@' + str(config if compact else fullconfig), '-B', '-dRELEASE', '-gl-',
                     '-gw3', '-Xs-', '-goDWARFLINETABLESONLY' if compact else '-goNODWARFLINETABLESONLY']
            if compact:
                flags.append('-dTEST_COMPACT')
            if prefix:
                flags.append('-goDWARFMETHODCLASSPREFIX')
            if cpp:
                flags.append('-goDWARFCPP')
            if compression:
                flags.append('-k--compress-debug-sections=' + compression)
            flags += ['-FU' + str(work), '-FE' + str(work), str(source)]
            invoke([compiler, *flags], work, work / 'compile.log')
            exe = work / ('NameBoundaries.exe' if os.name == 'nt' else 'NameBoundaries')
            output = invoke([exe], work, work / 'runtime.log').decode(errors='replace')
            records = {}
            for row in output.splitlines():
                label, ok, func, file, line = row.split('|', 4)
                assert ok == 'TRUE' and func and file and int(line) > 0, (mode, row)
                records[label] = func
            assert set(records) == ({'254', '255', 'following', '256', 'generic'} if compact
                                    else {'254', '255', 'following'}), mode
            for label, method in [('254', M126), ('255', M127), ('following', 'Following')]:
                owner = CLASS + ('.' if compact else '__' if prefix else '')
                expected = (owner + method if compact or prefix else method)[:255]
                assert records[label] == expected, (mode, label, records[label], expected)
            if compact:
                assert records['256'] == ('TOuter.' + INNER + '.' + M127)[:255]
                assert records['generic'].startswith(GENERIC)
            info = compiled_names(objdump, exe, work)
            for method in (M126, M127):
                expected = (CLASS + ('.' if compact else '__' if prefix else '') + method
                            if compact or prefix else method)
                assert expected in info, (mode, expected)
            if compact:
                assert 'TOuter.' + INNER + '.' + M127 in info, mode
                assert re.search(re.escape(GENERIC) + r'.{100,}\.' + re.escape(M127), info), mode
            if cpp and not compact:
                assert '_ZN127' + CLASS + '127' + M127 + 'Ev' in info, mode
            table = section_reader(exe.read_bytes())
            assert '.debug_info' in table and '.debug_line' in table, mode
            print('NAME_BOUNDARY_PASS', mode, flush=True)


def run_dwarf5_counts(compiler, config, out, section_reader):
    work = out / 'dwarf5-counts'
    work.mkdir()
    source = work / 'ManyFiles.pas'
    lines = ['program ManyFiles;', '{$mode objfpc}']
    for i in range(130):
        directory = work / f'd{i:03}'
        directory.mkdir()
        (directory / f'i{i:03}.inc').write_text(f'procedure P{i:03}; begin writeln({i}); end;\n')
        lines.append('{$I d%03d/i%03d.inc}' % (i, i))
    source.write_text('\n'.join([*lines, 'begin', '  P129;', 'end.']) + '\n')
    flags = ['-n', '@' + str(config), '-B', '-dRELEASE', '-gw5', '-gl-', '-Xs-',
             '-goDWARFLINETABLESONLY', '-FU' + str(work), '-FE' + str(work)]
    if os.name != 'nt':
        flags.append('-k--compress-debug-sections=none')
    invoke([compiler, *flags, source], work, work / 'compile.log')
    exe = work / ('ManyFiles.exe' if os.name == 'nt' else 'ManyFiles')
    assert b'129' in invoke([exe], work, work / 'runtime.log')
    data = exe.read_bytes()
    section = section_reader(data)['.debug_line']
    assert not section['flags'] & 0x800, 'DWARF5 count case must use raw .debug_line'
    debug_line = data[section['offset']:section['offset'] + section['size']]
    file_count = b'\x84\x01'  # 132: main + 130 includes + one compiler entry
    directory_count = b'\x83\x01'  # 131: current directory + 130 include directories
    directory0 = work.as_posix().encode() + b'/\0'
    assert directory_count + directory0 in debug_line, 'DWARF5 directory count is not ULEB128(131)'
    assert file_count + b'ManyFiles.pas\0' in debug_line, 'DWARF5 file count is not ULEB128(132)'
    print('DWARF5_COUNTS_PASS', flush=True)


def run_linux_basename255(compiler, config, out, section_reader):
    filename = 'F' * 251 + '.inc'
    assert len(filename) == 255
    for compression in ('none', 'zlib'):
        work = out / ('basename255-' + compression)
        work.mkdir()
        (work / filename).write_text('''procedure P; noinline;
var F,S:ShortString; L:LongInt;
begin
  If not GetLineInfo(PtrUInt(@P)+1,F,S,L) then Halt(3);
  Writeln(F,'|',S,'|',L);
end;
''')
        source = work / 'Basename255.pas'
        source.write_text('program Basename255;\nuses lnfodwrf;\n{$I ' + filename + '}\nbegin P; end.\n')
        flags = ['-n', '@' + str(config), '-B', '-dRELEASE', '-gw3', '-gl-', '-Xs-',
                 '-goDWARFLINETABLESONLY', '-k--compress-debug-sections=' + compression,
                 '-FU' + str(work), '-FE' + str(work), source]
        invoke([compiler, *flags], work, work / 'compile.log')
        exe = work / 'Basename255'
        result = invoke([exe], work, work / 'runtime.log').decode(errors='replace').strip()
        function, file, line = result.split('|')
        assert function == 'P' and file == filename and int(line) > 0, (compression, result)
        table = section_reader(exe.read_bytes())
        assert '.debug_line' in table, compression
        print('BASENAME255_PASS', compression, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--fullconfig', required=True, type=Path)
    parser.add_argument('--objdump', required=True)
    parser.add_argument('--results', required=True, type=Path)
    parser.add_argument('--root', required=True, type=Path)
    args = parser.parse_args()
    sys.path.insert(0, str(args.root / 'qualification/suite/scripts'))
    from run_dwarf_sections_gate import sections
    args.results.mkdir(parents=True, exist_ok=False)
    run_names(args.compiler, args.config, args.objdump, args.results, args.fullconfig, sections)
    run_dwarf5_counts(args.compiler, args.config, args.results, sections)
    if os.name != 'nt':
        run_linux_basename255(args.compiler, args.config, args.results, sections)


if __name__ == '__main__':
    main()
