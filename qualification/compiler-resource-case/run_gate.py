"""Resource lookup must preserve exact selection and resolve only unique case variants."""
import argparse
import json
import os
from pathlib import Path
from struct import pack
import subprocess
import sys


DECL = '''uses System.Classes, System.SysUtils;
type TResourceProbe = class(TComponent)
private FValue: Integer;
published property Value: Integer read FValue write FValue;
end;
'''
BODY = '''var P: TResourceProbe;
begin
  P:=TResourceProbe.Create(nil);
  try
    If not InitInheritedComponent(P,TComponent) then Halt(2);
    If P.Value<>42 then Halt(3);
    WriteLn('RESOURCE_VALUE_42');
  finally P.Free end;
end.
'''


def resource(value, binary=False):
    if not binary:
        return f'object Probe: TResourceProbe\n  Value = {value}\nend\n'.encode()

    def align(data):
        return data + b'\0' * (-len(data) % 4)

    def record(kind, name, data):
        ident = lambda s: pack('<HH', 0xffff, s) if isinstance(s, int) else s.encode('utf-16le') + b'\0\0'
        header = align(ident(kind) + ident(name)) + pack('<IHHII', 0, 0x1030 if kind else 0, 0, 0, 0)
        return pack('<II', len(data), len(header) + 8) + header + align(data)

    def short(s):
        return bytes([len(s)]) + s.encode()

    data = b'TPF0' + short('TResourceProbe') + short('Probe') + short('Value') + b'\x04' + pack('<i', value) + b'\0\0'
    return record(0, 0, b'') + record(10, 'TRESOURCEPROBE', data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--bindir', type=Path, help='Installed tools directory when testing a private backend')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    compiler = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
                '-Mdelphiunicode', '-UaSystem.Classes=Classes', '-UaSystem.SysUtils=SysUtils']
    env = dict(os.environ)
    if args.bindir:
        env['PPC_EXEC_PATH'] = str(args.bindir.resolve())
        compiler.append('-FD' + str(args.bindir.resolve()))
    rows = []

    def run(cmd, cwd, log):
        r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, timeout=30,
                           creationflags=0x08000000 if os.name == 'nt' else 0)
        text = (r.stdout + r.stderr).decode(errors='replace')
        log.write_text(text, encoding='utf-8')
        return r.returncode, text

    def execute(cmd, cwd, log, failure=None):
        rc, text = run(cmd, cwd, log)
        if failure:
            assert rc != 0 and all(token in text for token in failure), (rc, log, text[-2000:])
        else:
            assert rc == 0, (rc, log, text[-2000:])
        return text

    # Probe filesystem capability; do not silently skip Linux ambiguity cases.
    probe = root / 'CaseProbe'
    probe.write_text('x')
    sensitive = not (root / 'caseprobe').exists()
    probe.unlink()
    if os.name != 'nt':
        assert sensitive, 'Linux resource-case gate requires a case-sensitive directory'

    variants = ['exact', 'wildcard', 'explicit-mixed', 'dfm', 'binary', 'subdir', 'absolute',
                'spaces', 'missing', 'directory', 'cwd-decoy']
    if sensitive:
        variants += ['ambiguous', 'ambiguous-reversed', 'exact-wins', 'wrong-directory-case',
                     'symlink', 'dangling-symlink', 'unicode-prefix']
    for profile, flags in [('debug', ['-O-', '-uRELEASE']), ('release', ['-O3', '-dRELEASE'])]:
        for no_cache in (False, True):
            opts = flags + (['-Fd'] if no_cache else [])
            for name in variants:
                tag = f'{profile}-{"uncached" if no_cache else "cached"}-{name}'
                work = root / tag
                src, out, caller = work / 'source', work / 'out', work / 'caller'
                for d in (src, out, caller):
                    d.mkdir(parents=True)
                requested, actual, binary = '*.FMX', 'ResourceCase.fmx', False
                error = None
                if name == 'exact': actual = 'ResourceCase.FMX'
                if name == 'explicit-mixed': requested, actual = 'mIxEd.FMX', 'MiXeD.fMx'
                if name == 'dfm': requested, actual = '*.DFM', 'ResourceCase.dfm'
                if name == 'binary': requested, actual, binary = '*.RES', 'ResourceCase.res', True
                if name == 'subdir': requested, actual = 'Assets/MIXED.FMX', 'Assets/Mixed.fmx'
                if name == 'absolute': requested, actual = str(src / 'ABSOLUTE.FMX'), 'Absolute.fmx'
                if name == 'spaces': requested, actual = 'Form File.FMX', 'Form File.fmx'
                if name == 'unicode-prefix': requested, actual = 'форма.FMX', 'форма.fmx'
                if name == 'wrong-directory-case': requested, actual = 'assets/Form.FMX', 'Assets/Form.fmx'
                target = src / actual
                target.parent.mkdir(parents=True, exist_ok=True)
                if name in ('missing', 'directory', 'cwd-decoy', 'dangling-symlink', 'wrong-directory-case'):
                    error = ["Can't open resource file"]
                if name == 'directory': target.mkdir()
                elif name in ('symlink', 'dangling-symlink'):
                    target.symlink_to('content.dat')
                    if name == 'symlink': (src / 'content.dat').write_bytes(resource(42))
                elif name not in ('missing', 'cwd-decoy'):
                    target.write_bytes(resource(42, binary))
                if name == 'cwd-decoy': (caller / 'ResourceCase.FMX').write_bytes(resource(42))
                if name.startswith('ambiguous'):
                    target.unlink()
                    choices = ['ResourceCase.fmx', 'rEsOuRcEcAsE.FmX']
                    if name.endswith('reversed'): choices.reverse()
                    for choice in choices: (src / choice).write_bytes(resource(42))
                    error = ['Ambiguous resource file', *choices]
                if name == 'exact-wins':
                    target.write_bytes(resource(99))
                    (src / 'ResourceCase.FMX').write_bytes(resource(42))
                source = src / 'ResourceCase.dpr'
                source.write_text('program ResourceCase;\n' + DECL + "{$R '" + requested + "'}\n" + BODY, encoding='utf-8')
                # Same-directory output is essential: otherwise copying could hide
                # failure to retain the resolved name for resource collection.
                destination = src if name in ('wildcard', 'exact-wins', 'subdir') else out
                try:
                    execute(compiler + opts + ['-FU' + str(destination), '-FE' + str(destination), str(source)],
                            caller, work / 'compile.log', error)
                    if not error:
                        exe = destination / ('ResourceCase.exe' if os.name == 'nt' else 'ResourceCase')
                        result = execute([str(exe)], caller, work / 'run.log')
                        assert result.strip() == 'RESOURCE_VALUE_42', result
                    rows.append(dict(case=tag, passed=True))
                except AssertionError as e:
                    rows.append(dict(case=tag, passed=False, error=str(e)))

            tag = f'{profile}-{"uncached" if no_cache else "cached"}-ppu-only'
            work = root / tag
            src, out, consumer = work / 'source', work / 'out', work / 'consumer'
            for d in (src, out, consumer): d.mkdir(parents=True)
            unit = src / 'FormUnit.pas'
            unit.write_text('unit FormUnit;\ninterface\n'+DECL+"implementation\n{$RESOURCE 'Assets/MIXED.FMX'}\nend.\n")
            (src / 'Assets').mkdir()
            (src / 'Assets' / 'Mixed.fmx').write_bytes(resource(42))
            app = consumer / 'Consumer.dpr'
            app.write_text('program Consumer;\nuses FormUnit, System.Classes;\n'+BODY)
            try:
                execute(compiler + opts + ['-FU'+str(out), str(unit)], consumer, work / 'unit.log')
                # Hide the complete source tree, move the PPU/resource package,
                # then link twice using only the moved output directory.
                src.rename(work / 'hidden-source')
                moved = work / 'moved-package'
                out.rename(moved)
                for cycle in range(2):
                    execute(compiler + opts + ['-Fu'+str(moved), '-FU'+str(consumer), '-FE'+str(consumer), str(app)],
                            consumer, work / f'consumer-{cycle}.log')
                    exe = consumer / ('Consumer.exe' if os.name == 'nt' else 'Consumer')
                    result = execute([str(exe)], consumer, work / f'run-{cycle}.log')
                    assert result.strip() == 'RESOURCE_VALUE_42', result
                rows.append(dict(case=tag, passed=True))
            except AssertionError as e:
                rows.append(dict(case=tag, passed=False, error=str(e)))
    (root / 'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    failures = [r for r in rows if not r['passed']]
    for row in failures[:5]: print(row['case'], row['error'][-700:])
    # Exercise resources created after the compiler has cached a directory.
    command = [sys.executable, str(Path(__file__).with_name('stale_cache.py')),
               '--compiler', str(args.compiler.resolve()), '--config', str(args.config.resolve()),
               '--output', str(root / 'stale-cache')]
    if args.bindir:
        command += ['--bindir', str(args.bindir.resolve())]
    stale = subprocess.run(command, check=False, timeout=150)
    failed = bool(failures) or stale.returncode != 0
    print(f'RESOURCE_CASE_GATE {"FAIL" if failed else "PASS"}: {len(rows)-len(failures)}/{len(rows)} cases; stale-cache exit {stale.returncode}')
    raise SystemExit(failed)


if __name__ == '__main__':
    main()
