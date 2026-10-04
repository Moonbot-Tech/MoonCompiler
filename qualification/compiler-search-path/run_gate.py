"""A later search path replaces the same directory regardless of its spelling."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    project = root / 'project'
    mixed = project / 'Mixed'
    mixed.mkdir(parents=True)
    caller = root / 'caller'
    caller.mkdir()
    provider = root / 'provider'
    provider.mkdir()
    (provider / 'onlyppu.pas').write_text('unit onlyppu; interface const V=17; implementation end.\n')
    (mixed / 'unrelated.pas').write_text('unit unrelated; interface implementation end.\n')
    (project / 'test.onlyppu.pas').write_text('unit Test.onlyppu; interface const V=23; implementation end.\n')
    source = project / 'consumer.dpr'
    source.write_text('program consumer; uses onlyppu; begin WriteLn(V); end.\n')
    source.with_suffix('.mooncompiler').write_text('-Fu'+str(mixed)+'\n-FNTest\n')
    compiler = [str(args.compiler.resolve()), '-n', '@'+str(args.config.resolve())]
    executable = source.with_suffix('.exe' if os.name == 'nt' else '')

    def run(command, cwd, log):
        result = subprocess.run(command, cwd=cwd, capture_output=True,
                                creationflags=0x08000000 if os.name == 'nt' else 0)
        log.write_bytes(result.stdout + result.stderr)
        assert result.returncode == 0, (command, result.returncode, log)
        return result.stdout.decode().strip()

    run(compiler + ['-FU'+str(mixed), str(provider / 'onlyppu.pas')], caller, root / 'provider.log')
    rows = []
    for profile, options in [('debug', ['-uRELEASE', '-O-']), ('release', ['-dRELEASE', '-O3'])]:
        variants = [('same-case', mixed)]
        if os.name == 'nt':
            variants.append(('lower-case', Path(str(mixed).lower())))
        for label, directory in variants:
            for location, cwd in [('project', project), ('other', caller)]:
                tag = profile+'-'+label+'-'+location
                units = root / tag
                units.mkdir()
                run(compiler + options + ['-vt', '-Fu'+str(directory)+'/**', '-FU'+str(units), str(source)],
                    cwd, root / (tag+'.compile.log'))
                actual = run([str(executable)], cwd, root / (tag+'.run.log'))
                rows.append(dict(case=tag, expected='23', actual=actual))
        # A deliberate ordinary -Fu still accepts an explicitly supplied PPU.
        units = root / (profile+'-explicit')
        units.mkdir()
        run(compiler + options + ['-FU'+str(units), str(source)], caller, root / (profile+'-explicit.compile.log'))
        actual = run([str(executable)], caller, root / (profile+'-explicit.run.log'))
        rows.append(dict(case=profile+'-explicit', expected='17', actual=actual))
    (root / 'results.json').write_text(json.dumps(rows, indent=2))
    failures = [row for row in rows if row['actual'] != row['expected']]
    assert not failures, failures
    print('SEARCH_PATH_IDENTITY_PASS', len(rows))


if __name__ == '__main__':
    main()
