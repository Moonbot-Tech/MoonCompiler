#!/usr/bin/env python3
"""Targeted MM OOM/unwind and pending-reason regressions; never a timing gate."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import uuid

import mm_failure_hooks as hooks

HERE = Path(__file__).resolve().parent
MM_NAME = 'mormot.core.fpcx64mm.pas'
COMMON = ['get-small', 'alloc-small', 'get-medium', 'alloc-medium', 'get-large', 'alloc-large',
          'realloc-nil', 'small-medium', 'small-large', 'medium-large', 'large-grow',
          'large-small', 'large-medium', 'large-shrink', 'overflow-get', 'overflow-realloc']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'config', 'mm', 'out'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--group', choices=('oom', 'ownership', 'handoff', 'all'), default='all')
    args = parser.parse_args()
    args.out = args.out.resolve()
    # A new directory keeps failed builds and earlier raw outcomes reviewable.
    args.out.mkdir(parents=True, exist_ok=False)
    source = args.mm.read_text(encoding='utf-8-sig')
    config = args.config.read_text(encoding='utf-8-sig')
    config = re.sub(r'^--pinned-unit=mormot\.core\.fpcx64mm=.*\n?', '', config, flags=re.M)
    rows = []
    manifest = dict(compiler=str(args.compiler.resolve()), compiler_sha256=digest(args.compiler),
                    config=str(args.config.resolve()), config_sha256=digest(args.config),
                    mm=str(args.mm.resolve()), mm_sha256=digest(args.mm), group=args.group, rows=rows)
    result_file = args.out / 'results.json'

    def save():
        result_file.write_text(json.dumps(manifest, indent=2), encoding='utf-8')

    def build(name, fixture, mm_source, defines=()):
        out = args.out / name
        out.mkdir()
        mm = out / MM_NAME
        mm.write_text(mm_source, encoding='utf-8')
        cfg = out / 'test.cfg'
        cfg.write_text(config + '\n--pinned-unit=mormot.core.fpcx64mm=' + mm.as_posix() + '\n', encoding='utf-8')
        program = out / fixture
        shutil.copy2(HERE / fixture, program)
        command = [str(args.compiler.resolve()), '-n', '@' + str(cfg), '-Mdelphi', '-O3', '-B', '-gw3',
                   '-dMOONCOMPILER_VANILLA_RUNTIME', '-dMOONBOT_MM_PROFILE_REQUIRED',
                   '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', '-dNOPATCHRTL',
                   '-FU' + str(out), '-FE' + str(out), *defines, str(program)]
        proc = subprocess.run(command, capture_output=True, text=True, timeout=180)
        (out / 'build.log').write_text(proc.stdout + proc.stderr, encoding='utf-8')
        rows.append(dict(build=name, command=command, source_sha256=digest(mm), exit=proc.returncode))
        save()
        if proc.returncode:
            raise SystemExit('BUILD_FAIL ' + name + ': ' + str(out / 'build.log'))
        return program.with_suffix('.exe' if os.name == 'nt' else '')

    def run(exe, arguments, marker):
        fresh = exe.with_name('fresh-' + uuid.uuid4().hex + exe.suffix)
        shutil.copy2(exe, fresh)
        command = [str(fresh), *arguments]
        try:
            try:
                proc = subprocess.run(command, capture_output=True, text=True, timeout=45)
                row = dict(command=command, exit=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)
            except subprocess.TimeoutExpired as error:
                row = dict(command=command, exit='timeout', stdout=str(error.stdout), stderr=str(error.stderr))
        finally:
            fresh.unlink()
        row['exe_sha256'] = digest(exe)
        rows.append(row)
        save()
        if row['exit'] != 0 or marker not in row['stdout']:
            raise SystemExit('RUN_FAIL ' + str(row))
        print('PASS', exe.parent.name, *arguments, flush=True)

    if args.group in ('oom', 'all'):
        run(build('basic', 'memory_oom_contract.dpr', source), [], 'MEMORY_OOM_CONTRACT_PASS')
        instrumented = hooks.faults(source)
        profiles = [('product', []), ('nomremap', ['-dFPCMM_NOMREMAP'])]
        if os.name != 'nt':
            profiles.append(('nosframe', ['-dFPCMM_NOSFRAME']))
        for profile, defines in profiles:
            exe = build(profile, 'oom_injected.dpr', instrumented, defines)
            extra = []
            if profile != 'nomremap':
                extra = ['reserve-fail', 'commit-fail', 'commit-fallback', 'inplace'] if os.name == 'nt' else ['remap-fallback']
            for case in COMMON + extra:
                for mode in ('raise', 'nil'):
                    run(exe, [case, mode], 'INJECTED_PASS')
            if os.name != 'nt' and profile != 'nomremap':
                run(build('registers-' + profile, 'oom_registers.dpr', instrumented, defines), [], 'REGISTER_PASS kind=4')
    if os.name == 'nt' and args.group in ('ownership', 'all'):
        run(build('ownership', 'oom_ownership.dpr', hooks.ownership(source)), [], 'OWNERSHIP_PASS')
    if os.name == 'nt' and args.group in ('handoff', 'all'):
        defines = ['-dFPCMM_SMALLPOOL_REUSE_TEST', '-dFPCMM_SMALLLASTFREE_TEST', '-dFPCMM_MEDIUMLASTFREE_TEST']
        exe = build('handoff', 'small_pool_pending.dpr', hooks.pending(source), defines)
        for case in ('single', 'multi'):
            run(exe, [case], 'PENDING_PASS')
    if os.name != 'nt' and args.group in ('ownership', 'handoff'):
        raise SystemExit('The ownership and handoff regression hooks are Windows-specific')
    manifest['passed'] = True
    save()
    print('MM_FAILURE_GATE_PASS', result_file)


if __name__ == '__main__':
    main()
