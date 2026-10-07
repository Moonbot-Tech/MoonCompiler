"""Check Windows CI stops at each failed command, using real native exit codes."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[3]
COMMAND = re.compile(r'(?m)^(?:python |\.\\)(?:[^\n]*`\n)*[^\n]*\n')


class SmokeExitCodes(unittest.TestCase):
    def test_smoke_checks_require_output_and_normal_exit(self):
        """Run the workflow's smoke steps with native programs, including late failures."""
        windows = os.name == 'nt'
        if not windows and not shutil.which('bash'):
            self.skipTest('bash is required')
        platform = 'Win64' if windows else 'Linux'
        for workflow, step, calls in (
            ('qualification', 'Run product smoke', 3),
            ('moonormot-sync', f'Run the mORMot and memory-manager gates ({platform})', 2),
            ('release', 'Smoke-test the archive as a user installs it', 8),
        ):
            source = (ROOT / f'.github/workflows/{workflow}.yml').read_text(encoding='utf-8')
            blocks = re.findall(r'      - name: ' + re.escape(step) +
                                r'\n.*?        run: \|\n((?:          [^\n]*\n|\n)+)',
                                source, re.DOTALL)
            body = textwrap.dedent(blocks[-1 if windows else 0])
            # Retain the complete compile/run/check chain. Archive extraction
            # and earlier MM gates are separate contracts and need no rebuild.
            if windows:
                body = body[body.index('$Fpc ='):]
            elif workflow == 'release':
                body = body[body.index('fpc="$smoke/toolchain/bin/fpc"'):]
            elif workflow == 'moonormot-sync':
                body = '{\n' + body[body.index('fpc=$PWD/toolchain/bin/fpc'):]
            for failing in range(calls + 1):
                for bad_output in (False, True) if failing else (False,):
                    with self.subTest(workflow=workflow, failing=failing, bad_output=bad_output):
                        self.run_smoke(body, calls, failing, bad_output)

    def run_smoke(self, body, calls, failing, bad_output):
        windows = os.name == 'nt'
        with tempfile.TemporaryDirectory(prefix='moon-smoke-exit-') as directory:
            work = Path(directory)
            for name in ('qualification/suite/tests/smoke', 'examples', 'app',
                         'app/units/x86_64-win64/debug', 'app/units/x86_64-win64/release',
                         'units/x86_64-linux/debug', 'units/x86_64-linux/release'):
                (work / name).mkdir(parents=True, exist_ok=True)
            trace = work / 'calls.txt'
            probe = work / 'program.py'
            probe.write_text(textwrap.dedent(f'''\
                from pathlib import Path
                import sys
                trace = Path({str(trace)!r})
                prior = trace.read_text() if trace.exists() else ''
                trace.write_text(prior + sys.argv[1] + '\\n')
                failed = len(prior.splitlines()) + 1 == {failing}
                markers = {{'build_smoke': 'MOONBOT_BUILD_OK', 'zip': 'ZIP_EXAMPLE_OK',
                            'hello': '3 prices, sum = 42', 'file_resource_semantic': 'FILE_RESOURCE_PASS',
                            'rtl_api_release231_contracts': 'RTL_API_RELEASE231_CONTRACTS_OK'}}
                print('WRONG' if failed and {bad_output} else markers[sys.argv[1]])
                sys.exit(73 if failed and not {bad_output} else 0)
                '''), encoding='utf-8')
            if windows:
                compiler = work / 'toolchain/bin/x86_64-win64/fpc.cmd'
                compiler.parent.mkdir(parents=True)
                compiler.write_text('@echo off\nexit /b 0\n')
                body = body.replace('\\fpc.exe', '\\fpc.cmd')
                body = re.sub(r'\.\\(build_smoke|zip|hello|file_resource_semantic|rtl_api_release231_contracts)\.exe',
                              lambda m: f"'{sys.executable}' '{probe}' {m[1]}", body)
                prefix = f"$ErrorActionPreference = 'Stop'\n$Smoke = '{work}'\n"
                suffix = "\nWrite-Output 'SMOKE_STEP_COMPLETE'\nexit $LASTEXITCODE\n"
                command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']
                script = work / 'probe.ps1'
            else:
                compiler = work / 'toolchain/bin/fpc'
                compiler.parent.mkdir(parents=True)
                compiler.write_text('#!/bin/sh\nexit 0\n')
                compiler.chmod(0o755)
                body = re.sub(r'\./(?:qualification/suite/tests/smoke/|examples/)?'
                              r'(build_smoke|zip|hello|file_resource_semantic|rtl_api_release231_contracts)\b',
                              lambda m: f'"{sys.executable}" "{probe}" {m[1]}', body)
                prefix = f'smoke="{work}"\n'
                suffix = "\nprintf '%s\\n' SMOKE_STEP_COMPLETE\n"
                command = ['bash', '-e', '-o', 'pipefail']
                script = work / 'probe.sh'
            script.write_text(prefix + body + suffix, encoding='utf-8')
            done = subprocess.run(command + [str(script)], cwd=work, capture_output=True,
                                  text=True, timeout=30,
                                  creationflags=0x08000000 if windows else 0)
            invoked = trace.read_text().splitlines() if trace.exists() else []
            self.assertEqual(len(invoked), failing or calls, done.stdout + done.stderr)
            self.assertEqual(done.returncode == 0, failing == 0, done.stdout + done.stderr)
            self.assertEqual('SMOKE_STEP_COMPLETE' in done.stdout, failing == 0)


class StandChainContracts(unittest.TestCase):
    def test_release_requires_exact_sha_qualification_evidence(self):
        qualification = (ROOT / '.github/workflows/qualification.yml').read_text(
            encoding='utf-8'
        )
        release = (ROOT / '.github/workflows/release.yml').read_text(
            encoding='utf-8'
        )
        self.assertIn('qualification-linux-x86-64-${{ github.sha }}', qualification)
        self.assertIn('qualification-win64-x86-64-${{ github.sha }}', qualification)
        self.assertIn('qualification-proof:', release)
        self.assertIn('verify_qualification_run.py', release)
        self.assertIn('source_sha: ${{ steps.tag.outputs.source_sha }}', release)
        self.assertRegex(
            release,
            r'publish:\n\s+needs: \[[^\]]*qualification-proof[^\]]*\]',
        )

    def test_mm_failure_contract_is_mandatory_in_ci_and_release(self):
        for relative in ('.github/workflows/qualification.yml', '.github/workflows/release.yml'):
            with self.subTest(workflow=relative):
                text = (ROOT / relative).read_text(encoding='utf-8')
                self.assertEqual(text.count('mm_failure_gate.py'), 2)
                self.assertEqual(text.count('--group all'), 2)

    def test_mm_profile_matrix_guards_every_way_the_mm_comes_in(self):
        # a MoonORMot MM reaches main through the sync commit, an edit through CI
        for relative in ('.github/workflows/qualification.yml', '.github/workflows/moonormot-sync.yml'):
            with self.subTest(workflow=relative):
                text = (ROOT / relative).read_text(encoding='utf-8')
                self.assertEqual(text.count('mm_profile_matrix.py'), 2)

    def test_stage_two_focused_contracts_are_mandatory_on_both_ci_platforms(self):
        workflow = (ROOT / '.github/workflows/qualification.yml').read_text(
            encoding='utf-8'
        ).replace('\\', '/')
        for gate in (
            'qualification/managed-array-copy/run_gate.py',
            'qualification/compiler-private-ppu/run_ppu_private_crc_gate.py',
            'qualification/compiler-alias-lifetime/run_alias_lifetime_gate.py',
            'qualification/compiler-alias-lifetime/run_alias_reload_gate.py',
            'qualification/optimizer-core/consttemp-lifetime/run_consttemp_gate.py',
            'qualification/optimizer-core/loop-address/run_loop_address_gate.py',
            'qualification/optimizer-core/real-folds/run_real_folds_gate.py',
            'qualification/optimizer-core/fold-guards/run_fold_guards_gate.py',
            'qualification/optimizer-core/sqr-fold/run_sqr_fold_gate.py',
            'qualification/optimizer-core/getter-borrow/run_getter_borrow_gate.py',
            'qualification/optimizer-core/value-in-register/run_value_in_register_gate.py',
            'qualification/optimizer-core/try-nested/run_try_nested_gate.py',
            'qualification/optimizer-core/nested-local/run_nested_local_gate.py',
            'qualification/optimizer-core/record-fields/run_record_fields_gate.py',
            'qualification/optimizer-core/block-locals/run_block_locals_gate.py',
            'qualification/optimizer-core/operand-forms/run_operand_forms_gate.py',
            'qualification/optimizer-core/loop-regvar/run_loop_regvar_gate.py',
            'qualification/thread-pool/run_gate.py',
            'qualification/thread-pool/monitor_exit_gate.py',
            'qualification/optimizer-core/divmod/run_divmod_pair_gate.py',
            'qualification/optimizer-core/range-loop/run_range_loop_gate.py',
            'qualification/optimizer-core/memory-order/run_memory_order_gate.py',
            'qualification/optimizer-core/resources/run_jump_tracking_gate.py',
        ):
            with self.subTest(gate=gate):
                self.assertEqual(workflow.count(gate), 2)

    def test_placement_acceptance_chains_use_case_isolated_evidence(self):
        for relative in ('scripts/Stand-F-Chain.ps1', 'scripts/stand-chain.sh'):
            with self.subTest(script=relative):
                text = (ROOT / relative).read_text(encoding='utf-8')
                self.assertIn('--mode medium', text)
                self.assertNotIn('pulse.py run --mode quick', text)
                self.assertIn('stand_ab_gate.py', text)
                self.assertIn('reason=no-expected-buyer', text)
                self.assertIn('reason=semantics-skipped', text)
                self.assertNotRegex(
                    text,
                    r'(?:SkipSemantics|SKIP_SEMANTICS).{0,120}(?:Finish-Chain|finish_chain)',
                )

    def test_e_chain_checks_every_required_native_stage(self):
        text = (ROOT / 'scripts/Stand-E-Chain.ps1').read_text(encoding='utf-8')
        self.assertIn("Fail-Chain 'E build timeout' 124", text)
        for stage in (
            'filler pulse A vs E',
            'filler summary A vs E',
            'RTL-test E',
            'light E',
        ):
            with self.subTest(stage=stage):
                self.assertIn(f"Require-Success '{stage}' $LASTEXITCODE", text)
        self.assertLess(
            text.index("Require-Success 'light E'"),
            text.index('"CHAIN_E_DIAGNOSTIC_DONE'),
        )
        self.assertNotIn('"CHAIN_E_DONE"', text)


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell exit propagation')
class WorkflowExitCodes(unittest.TestCase):
    def test_win64_acceptance_chain_requires_expected_buyer(self):
        source = ROOT / 'scripts/Stand-F-Chain.ps1'
        with tempfile.TemporaryDirectory(prefix='moon-f-chain-buyer-') as directory:
            workspace = Path(directory)
            script = workspace / 'scripts/Stand-F-Chain.ps1'
            script.parent.mkdir()
            script.write_text(source.read_text(encoding='utf-8'), encoding='utf-8')
            (workspace / 'stand').mkdir(parents=True)
            done = subprocess.run(
                ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                 '-File', str(script)],
                capture_output=True, text=True, timeout=30,
            )
            log = next((workspace / 'stand').glob('chain-F-*-summary.log')).read_text()
            self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
            self.assertIn('CHAIN_F_INCONCLUSIVE reason=no-expected-buyer', log)
            self.assertNotIn('CHAIN_F_DONE', log)

    def test_each_failure_stops_the_remaining_chain(self):
        workflow = (ROOT / '.github/workflows/qualification.yml').read_text(encoding='utf-8')
        pattern = r'      - name: (.+)\n        shell: powershell\n        run: \|\n((?:          .*\n|\n)+)'
        names = {
            'Run platform contracts',
            'Run Stage 2 focused contracts',
            'Run Win64 language and integration gates',
        }
        blocks = {name: ''.join(line[10:] if line.startswith('          ') else line
                               for line in body.splitlines(keepends=True))
                  for name, body in re.findall(pattern, workflow) if name in names}
        self.assertEqual(set(blocks), names)
        with tempfile.TemporaryDirectory(prefix='moon-ci-exit-') as directory:
            script = Path(directory) / 'probe.ps1'
            for name, body in blocks.items():
                count = len(COMMAND.findall(body))
                self.assertGreater(count, 1)
                for failing in range(count + 1):
                    with self.subTest(step=name, failing=failing):
                        index = 0

                        def substitute(match):
                            nonlocal index
                            index += 1
                            code = 7 if index == failing else 0
                            return f"Write-Output 'INVOKED={index}'\n& $env:ComSpec /d /c exit {code}\n"

                        probe = COMMAND.sub(substitute, body)
                        script.write_text("$ErrorActionPreference = 'Stop'\n" + probe +
                                          '\nexit $LASTEXITCODE\n', encoding='utf-8')
                        done = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                               '-File', str(script)], capture_output=True, text=True, timeout=30)
                        invoked = [int(n) for n in re.findall(r'INVOKED=(\d+)', done.stdout)]
                        self.assertEqual(invoked, list(range(1, (failing or count) + 1)), done.stderr)
                        self.assertEqual(done.returncode == 0, failing == 0, done.stderr)

    def test_release_configuration_stops_at_each_native_failure(self):
        workflow = (ROOT / '.github/workflows/release.yml').read_text(encoding='utf-8')
        pattern = r'      - name: (.+)\n        shell: powershell\n        run: \|\n((?:          .*\n|\n)+)'
        blocks = {
            name: ''.join(line[10:] if line.startswith('          ') else line
                          for line in body.splitlines(keepends=True))
            for name, body in re.findall(pattern, workflow)
            if name == 'Verify toolchain configuration, assembler and RTL profile'
        }
        self.assertEqual(len(blocks), 1)
        with tempfile.TemporaryDirectory(prefix='moon-release-exit-') as directory:
            script = Path(directory) / 'probe.ps1'
            body = next(iter(blocks.values()))
            count = len(COMMAND.findall(body))
            self.assertEqual(count, 2)
            for failing in range(count + 1):
                with self.subTest(failing=failing):
                    index = 0

                    def substitute(match):
                        nonlocal index
                        index += 1
                        code = 7 if index == failing else 0
                        return f"Write-Output 'INVOKED={index}'\n& $env:ComSpec /d /c exit {code}\n"

                    probe = COMMAND.sub(substitute, body)
                    script.write_text("$ErrorActionPreference = 'Stop'\n" + probe +
                                      '\nexit $LASTEXITCODE\n', encoding='utf-8')
                    done = subprocess.run(
                        ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                         '-File', str(script)],
                        capture_output=True, text=True, timeout=30,
                    )
                    invoked = [int(n) for n in re.findall(r'INVOKED=(\d+)', done.stdout)]
                    self.assertEqual(invoked, list(range(1, (failing or count) + 1)), done.stderr)
                    self.assertEqual(done.returncode == 0, failing == 0, done.stderr)

    def test_e_chain_timeout_cannot_report_success(self):
        source = ROOT / 'scripts/Stand-E-Chain.ps1'
        with tempfile.TemporaryDirectory(prefix='moon-e-chain-timeout-') as directory:
            workspace = Path(directory)
            script = workspace / 'scripts/Stand-E-Chain.ps1'
            script.parent.mkdir()
            script.write_text(source.read_text(encoding='utf-8'), encoding='utf-8')
            (workspace / 'stand').mkdir(parents=True)
            done = subprocess.run(
                ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                 '-File', str(script), '-BuildTimeoutMinutes', '0',
                 '-BuildPollSeconds', '0'],
                capture_output=True, text=True, timeout=30,
            )
            log = (workspace / 'stand/chain-E-summary.log').read_text()
            self.assertNotEqual(done.returncode, 0, done.stdout + done.stderr)
            self.assertIn('CHAIN_E_FAILED stage=E build timeout exit=124', log)
            self.assertNotIn('CHAIN_E_DONE', log)

    def test_e_chain_native_failure_stops_immediately(self):
        source = (ROOT / 'scripts/Stand-E-Chain.ps1').read_text(encoding='utf-8')
        prefix = source[:source.index('"chain E start')]
        with tempfile.TemporaryDirectory(prefix='moon-e-chain-native-') as directory:
            workspace = Path(directory)
            script = workspace / 'scripts/Stand-E-Chain.ps1'
            script.parent.mkdir()
            script.write_text(
                prefix + '"PROBE_BEFORE" | Add-Content $L\n'
                "Require-Success 'native stub' 7\n"
                '"PROBE_AFTER" | Add-Content $L\n',
                encoding='utf-8',
            )
            (workspace / 'stand').mkdir(parents=True)
            done = subprocess.run(
                ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script)],
                capture_output=True, text=True, timeout=30,
            )
            log = (workspace / 'stand/chain-E-summary.log').read_text()
            self.assertEqual(done.returncode, 7, done.stdout + done.stderr)
            self.assertIn('PROBE_BEFORE', log)
            self.assertIn('CHAIN_E_FAILED stage=native stub exit=7', log)
            self.assertNotIn('PROBE_AFTER', log)


if __name__ == '__main__':
    unittest.main()
