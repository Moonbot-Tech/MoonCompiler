#!/usr/bin/env python3
"""One-off 2.4.11 acceptance: qualified 2.4.10 plus the tested diagnostics delta.

This is not full qualification of a new SHA. The owner authorized reuse of the
240 Windows / 253 Linux reporting checks on TESTED, followed by archive tests.
Any extra product change invalidates this route. Other tags use the normal gate.
"""
import argparse
from pathlib import Path
import subprocess
import sys

BASE = '6a37ceaf33391b712f225e63d68ca577ce9f5efb'
TESTED = '3bf50e631a738701bb6cb07ca08908e24f7b69a3'
TESTED_FILES = {
    'runtime/reporting/Moon.Diagnostics.pas',
    'runtime/reporting/README.md',
    'doc/DIAGNOSTICS.md',
    'qualification/suite/tests/smoke/diagnostic_expected.pas',
    'qualification/suite/tests/smoke/diagnostic_raise_bench.pas',
    'qualification/suite/scripts/run_reporting_gate.py',
}
VERSION_FILES = {
    'compiler/version.pas': (b"mooncompiler_version = '2.4.10'", b"mooncompiler_version = '2.4.11'"),
    'qualification/suite/tests/rtl-api/rtl_api_compiler_identity.dpr': (b'20410', b'20411'),
    'README.md': (b'v2.4.10', b'v2.4.11'),
}
RELEASE_FILES = {
    '.github/workflows/release.yml',
    'doc/RELEASE_NOTES.md',
    'qualification/release/verify_2411_scope.py',
    'qualification/release/test_2411_scope.py',
    'qualification/release/diagnostics_expected_smoke.py',
    'qualification/suite/tests/test_workflow_exit_codes.py',
}


def validate(changed, baseline, tested, current):
    unexpected = set(changed) - TESTED_FILES - VERSION_FILES.keys() - RELEASE_FILES
    if unexpected:
        raise ValueError(f'Changes outside the qualified scope: {sorted(unexpected)}')
    for path in TESTED_FILES:
        if current(path) != tested(path):
            raise ValueError(f'Already tested diagnostics changed: {path}')
    for path, (old, new) in VERSION_FILES.items():
        if old not in baseline(path) or current(path) != baseline(path).replace(old, new):
            raise ValueError(f'Change beyond the 2.4.11 version bump: {path}')
    notes = current('doc/RELEASE_NOTES.md')
    if not notes.startswith(b'# MoonCompiler 2.4.11:') or not notes.endswith(baseline('doc/RELEASE_NOTES.md')):
        raise ValueError('Release notes must prepend 2.4.11 and preserve prior releases')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sha', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]

    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root)

    if git('rev-parse', 'HEAD').decode().strip() != args.sha:
        raise ValueError('The release must check its exact source SHA')
    git('merge-base', '--is-ancestor', BASE, TESTED)
    git('merge-base', '--is-ancestor', TESTED, args.sha)
    if set(git('diff', '--name-only', BASE, TESTED).decode().splitlines()) != TESTED_FILES:
        raise ValueError('The diagnostics evidence does not match its declared source delta')
    validate(git('diff', '--name-only', BASE, args.sha).decode().splitlines(),
             lambda path: git('show', f'{BASE}:{path}'),
             lambda path: git('show', f'{TESTED}:{path}'),
             lambda path: git('show', f'{args.sha}:{path}'))
    print(f'TARGETED_2411_SCOPE_PASS source={args.sha} tested={TESTED}; reporting=240/253', file=sys.stderr)
    print(BASE)


if __name__ == '__main__':
    main()
