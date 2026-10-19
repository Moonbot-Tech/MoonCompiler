"""Resource exact lookup must observe files copied by an earlier unit in this compile."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--bindir', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ)
    compiler = [str(args.compiler.resolve()), '-n', '@' + str(args.config.resolve()),
                '-Mdelphiunicode']
    if args.bindir:
        env['PPC_EXEC_PATH'] = str(args.bindir.resolve())
        compiler.append('-FD' + str(args.bindir.resolve()))

    probe = root / 'CaseProbe'
    probe.write_text('x')
    sensitive = not (root / 'caseprobe').exists()
    probe.unlink()
    if os.name != 'nt':
        assert sensitive, 'Linux probe requires a case-sensitive directory'

    rows = []
    for profile, flags in [('debug', ['-O-', '-uRELEASE']), ('release', ['-O3', '-dRELEASE'])]:
        for no_cache in (False, True):
            tag = profile + ('-uncached' if no_cache else '-cached')
            work = root / tag
            src, out, caller = work / 'src_a', work / 'out', work / 'caller'
            for directory in (src, out, caller):
                directory.mkdir(parents=True)
            (src / 'A.pas').write_text(
                "unit A;\ninterface\nfunction AValue: Integer;\nimplementation\n"
                "{$R Shared.FMX}\nfunction AValue: Integer;\nbegin Result:=42 end;\nend.\n")
            (out / 'B.pas').write_text(
                "unit B;\ninterface\nuses A;\nfunction BValue: Integer;\nimplementation\n"
                "{$R Shared.FMX}\nfunction BValue: Integer;\nbegin Result:=AValue end;\nend.\n")
            expected = b'object Probe: TComponent\n  Tag = 42\nend\n'
            (src / 'Shared.FMX').write_bytes(expected)
            if sensitive:
                (out / 'Shared.fmx').write_text('object Wrong: TComponent\n  Tag = 99\nend\n')
            # Looking for A first searches B's source directory and caches it.
            # Compiling A then copies Shared.FMX into that directory. B must
            # prefer this new exact file over the pre-existing case variant.
            cmd = compiler + flags + (['-Fd'] if no_cache else []) + [
                '-Fu' + str(src), '-FU' + str(out), '-vt', str(out / 'B.pas')]
            result = subprocess.run(cmd, cwd=caller, env=env, capture_output=True, timeout=30,
                                    creationflags=0x08000000 if os.name == 'nt' else 0)
            log = (result.stdout + result.stderr).decode(errors='replace')
            (work / 'compile.log').write_text(log, encoding='utf-8')
            exact = out / 'Shared.FMX'
            created = exact.is_file() and exact.read_bytes() == expected
            outputs = {entry.name.lower() for entry in out.iterdir()}
            passed = result.returncode == 0 and created and {'a.o', 'b.o', 'b.ppu'} <= outputs
            rows.append(dict(case=tag, passed=passed, returncode=result.returncode,
                             exact_resource_created=created,
                             ambiguous='Ambiguous resource file' in log))
    (root / 'results.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    for row in rows:
        print(row)
    failures = [row for row in rows if not row['passed']]
    print(f'STALE_RESOURCE_CACHE {len(rows) - len(failures)}/{len(rows)} PASS')
    raise SystemExit(bool(failures))


if __name__ == '__main__':
    main()
