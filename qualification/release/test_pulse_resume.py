"""Complete rejected pairs without rebuilding the SDK or replacing prior evidence."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import qualify


class PulseResumeTests(unittest.TestCase):
    def fixture(self, root):
        log = root / 'discovery/logs/pulse_report-0001.log'
        log.parent.mkdir(parents=True)
        log.write_text('Original failed measurement\n')
        result = {'status': 'fail', 'attempt': 1, 'log': str(log), 'log_identity': qualify.digest_paths([log])}
        state = {'pulse_completion': ['', '', ''], 'final_head': None,
                 'product_identity': 'original-sdk', 'results': {'pulse_report': result}}
        source = root / 'discovery/jobs/pulse_report/attempt-0001/out'
        return state, (str(source), 'a' * 64, 'b' * 64), log

    def test_binding_preserves_failed_observation_and_freezes_source(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state, completion, log = self.fixture(root)
            original = copy.deepcopy(state['results']['pulse_report'])
            qualify.bind_pulse_completion(state, completion, root, 'original-sdk')
            self.assertEqual(state['pulse_completion_origin'], original)
            self.assertEqual(state['results']['pulse_report'], original)
            self.assertTrue(qualify.evidence_intact(original))
            bound = copy.deepcopy(state)
            qualify.bind_pulse_completion(state, completion, root, 'original-sdk')
            self.assertEqual(state, bound)
            for replacement in [(completion[0], 'c' * 64, completion[2]),
                                (str(root / 'foreign'), completion[1], completion[2])]:
                with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                    qualify.bind_pulse_completion(state, replacement, root, 'original-sdk')
                self.assertEqual(state, bound)
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, completion, root, 'rebuilt-sdk')

    def test_failed_completion_can_restart_full_but_cannot_rebind(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state, completion, log = self.fixture(root)
            qualify.bind_pulse_completion(state, completion, root, 'original-sdk')
            origin = copy.deepcopy(state['pulse_completion_origin'])
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, ('', '', ''), root, 'original-sdk')
            completion_log = log.with_name('pulse_report-0002.log')
            completion_log.write_text('Completion refused before measurement')
            state['results']['pulse_report'] = dict(origin, attempt=2, log=str(completion_log),
                                                   log_identity=qualify.digest_paths([completion_log]))
            for damage in ('passed', 'final', 'changed-log', 'changed-sdk'):
                with self.subTest(damage=damage):
                    damaged = copy.deepcopy(state)
                    product = 'original-sdk'
                    if damage == 'passed':
                        damaged['results']['pulse_report']['status'] = 'pass'
                    elif damage == 'final':
                        damaged['final_head'] = 'frozen'
                    elif damage == 'changed-log':
                        damaged['results']['pulse_report']['log_identity'] = 'damaged'
                    else:
                        product = 'changed-sdk'
                    before = copy.deepcopy(damaged)
                    with self.assertRaises(ValueError):
                        qualify.bind_pulse_completion(damaged, ('', '', ''), root, product)
                    self.assertEqual(damaged, before)
            qualify.bind_pulse_completion(state, ('', '', ''), root, 'original-sdk')
            self.assertEqual(state['pulse_completion'], ('', '', ''))
            self.assertEqual(state['pulse_completion_origin'], origin)
            self.assertTrue(qualify.evidence_intact(origin))
            before = copy.deepcopy(state)
            qualify.bind_pulse_completion(state, ('', '', ''), root, 'original-sdk')
            self.assertEqual(state, before)
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, completion, root, 'original-sdk')

    def test_bound_origin_evidence_stays_required(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state, completion, log = self.fixture(root)
            qualify.bind_pulse_completion(state, completion, root, 'original-sdk')
            log.write_text('changed after binding')
            before = copy.deepcopy(state)
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, completion, root, 'original-sdk')
            self.assertEqual(state, before)

    def test_invalid_origin_cannot_change_ledger(self):
        for failure in ('no-result', 'passed', 'missing-log', 'changed-log', 'foreign-source', 'changed-sdk', 'final'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                state, completion, log = self.fixture(root)
                product = 'original-sdk'
                if failure == 'no-result':
                    state['results'].clear()
                elif failure == 'passed':
                    state['results']['pulse_report']['status'] = 'pass'
                elif failure == 'missing-log':
                    log.unlink()
                elif failure == 'changed-log':
                    log.write_text('Different evidence')
                elif failure == 'foreign-source':
                    completion = (str(root / 'foreign'), completion[1], completion[2])
                elif failure == 'changed-sdk':
                    product = 'rebuilt-sdk'
                elif failure == 'final':
                    state['final_head'] = 'frozen'
                before = copy.deepcopy(state)
                with self.assertRaises(ValueError):
                    qualify.bind_pulse_completion(state, completion, root, product)
                self.assertEqual(state, before)

    def test_full_completion_reuses_build_and_still_requires_final_light(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'source.txt').write_text('source')
            subprocess.run(['git', '-C', str(root), 'add', 'source.txt'], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c',
                            'user.email=test@example.invalid', 'commit', '-qm', 'source'], check=True)
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'sdk').write_text('baseline')
            baseline_mm = root / 'baseline-mm.pas'
            baseline_mm.write_text('baseline-mm')
            build = """from pathlib import Path
Path('toolchain').mkdir(exist_ok=True)
Path('runtime/mm').mkdir(parents=True, exist_ok=True)
Path('toolchain/sdk').write_text('SDK')
Path('runtime/mm/manager').write_text('MM')
with Path('builds.txt').open('a') as output: output.write('build\\n')
"""
            pulse = """import sys
from pathlib import Path
Path(sys.argv[1]).mkdir(parents=True)
complete = '--complete-from' in sys.argv
print('PULSE_PASS' if complete else 'MEASUREMENT_REJECTED')
raise SystemExit(0 if complete else 2)
"""
            matrix = root / 'matrix.json'
            matrix.write_text(json.dumps({'version': 1,
                'source_inputs': {name: ['source.txt'] for name in ('build', 'pulse_report')},
                'jobs': [
                    {'id': 'build', 'mode': 'light', 'platforms': ['linux'], 'timeout': 10,
                     'commands': {'linux': ['{python}', '-c', build]}},
                    {'id': 'pulse_report', 'mode': 'full', 'platforms': ['linux'], 'needs': ['build'],
                     'timeout': 10, 'expected': 'PULSE_PASS',
                     'commands': {'linux': ['{python}', '-c', pulse, '{job_dir}/out']}}]}))
            run = root / 'run'
            argv = ['qualify.py', 'run', '--run-dir', str(run), '--matrix', str(matrix), '--platform', 'linux',
                    '--mode', 'full', '--baseline-toolchain', str(baseline), '--baseline-mm-source', str(baseline_mm)]
            with patch.object(qualify, 'ROOT', root), patch.object(sys, 'argv', argv):
                self.assertEqual(qualify.main(), 1)
                initial = json.loads((run / 'state.json').read_text())
                self.assertEqual(initial['results']['build']['status'], 'pass')
                original = initial['results']['pulse_report']
                argv += ['--pulse-complete-from', str(run / 'discovery/jobs/pulse_report/attempt-0001/out'),
                         '--pulse-complete-sha256', 'a' * 64, '--pulse-complete-logs-sha256', 'b' * 64]
                matrix_text = matrix.read_text()
                build_log = Path(initial['results']['build']['log'])
                build_log_text = build_log.read_text()
                for damage in ('build-log', 'build-command', 'always-run', 'missing-build', 'failed-build'):
                    with self.subTest(damage=damage):
                        damaged = copy.deepcopy(initial)
                        spec = json.loads(matrix_text)
                        if damage == 'build-log':
                            build_log.write_text('damaged')
                        elif damage == 'build-command':
                            spec['jobs'][0]['commands']['linux'][-1] += '\n# changed build contract'
                        elif damage == 'always-run':
                            spec['jobs'][0]['always_run'] = True
                        elif damage == 'missing-build':
                            damaged['results'].pop('build')
                        elif damage == 'failed-build':
                            damaged['results']['build']['status'] = 'fail'
                        matrix.write_text(json.dumps(spec))
                        (run / 'state.json').write_text(json.dumps(damaged))
                        before = (run / 'state.json').read_bytes()
                        with self.assertRaises(SystemExit) as error:
                            qualify.main()
                        self.assertEqual(error.exception.code, 2)
                        self.assertEqual((run / 'state.json').read_bytes(), before)
                        self.assertEqual((root / 'builds.txt').read_text(), 'build\n')
                        build_log.write_text(build_log_text)
                matrix.write_text(matrix_text)
                (run / 'state.json').write_text(json.dumps(initial))
                self.assertEqual(qualify.main(), 0)
                completed = json.loads((run / 'state.json').read_text())
                self.assertEqual(completed['pulse_completion_origin'], original)
                self.assertEqual(completed['results']['pulse_report']['attempt'], 2)
                self.assertTrue(qualify.evidence_intact(original))
                self.assertEqual((root / 'builds.txt').read_text(), 'build\n')
                self.assertEqual(completed['product_identity'], initial['product_identity'])
                self.assertIsNone(completed['final_head'])
                argv[argv.index('full')] = 'light'
                argv.append('--final')
                self.assertEqual(qualify.main(), 0)
                self.assertEqual((root / 'builds.txt').read_text(), 'build\n')


    def test_failed_completion_restarts_fresh_full(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'source.txt').write_text('source')
            subprocess.run(['git', '-C', str(root), 'add', 'source.txt'], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c',
                            'user.email=test@example.invalid', 'commit', '-qm', 'source'], check=True)
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'sdk').write_text('baseline')
            baseline_mm = root / 'baseline-mm.pas'
            baseline_mm.write_text('baseline-mm')
            build = """from pathlib import Path
Path('toolchain').mkdir(exist_ok=True)
Path('runtime/mm').mkdir(parents=True, exist_ok=True)
Path('toolchain/sdk').write_text('SDK')
Path('runtime/mm/manager').write_text('MM')
with Path('builds.txt').open('a') as output: output.write('build\\n')
"""
            pulse = """import sys
from pathlib import Path
Path(sys.argv[1]).mkdir(parents=True)
complete = '--complete-from' in sys.argv
Path(sys.argv[1], 'record').write_text('fresh-' + Path(sys.argv[1]).parent.name)
passed = not complete and Path(sys.argv[1]).parent.name == 'attempt-0003'
print('PULSE_PASS' if passed else 'COMPLETION_REFUSED' if complete else 'MEASUREMENT_REJECTED')
raise SystemExit(0 if passed else 2)
"""
            matrix = root / 'matrix.json'
            matrix.write_text(json.dumps({'version': 1,
                'source_inputs': {name: ['source.txt'] for name in ('build', 'pulse_report')},
                'jobs': [
                    {'id': 'build', 'mode': 'light', 'platforms': ['linux'], 'timeout': 10,
                     'commands': {'linux': ['{python}', '-c', build]}},
                    {'id': 'pulse_report', 'mode': 'full', 'platforms': ['linux'], 'needs': ['build'],
                     'timeout': 10, 'expected': 'PULSE_PASS',
                     'commands': {'linux': ['{python}', '-c', pulse, '{job_dir}/out']}}]}))
            run = root / 'run'
            argv = ['qualify.py', 'run', '--run-dir', str(run), '--matrix', str(matrix), '--platform', 'linux',
                    '--mode', 'full', '--baseline-toolchain', str(baseline), '--baseline-mm-source', str(baseline_mm)]
            with patch.object(qualify, 'ROOT', root), patch.object(sys, 'argv', argv):
                self.assertEqual(qualify.main(), 1)
                initial = json.loads((run / 'state.json').read_text())
                original = initial['results']['pulse_report']
                source = run / 'discovery/jobs/pulse_report/attempt-0001/out'
                original_record = (source / 'record').read_bytes()
                full_argv = argv[:]
                argv += ['--pulse-complete-from', str(source), '--pulse-complete-sha256', 'a' * 64,
                         '--pulse-complete-logs-sha256', 'b' * 64]
                self.assertEqual(qualify.main(), 1)
                failed = json.loads((run / 'state.json').read_text())
                rejected = copy.deepcopy(failed['results']['pulse_report'])
                self.assertEqual(rejected['attempt'], 2)
                self.assertIn('COMPLETION_REFUSED', Path(rejected['log']).read_text())
                argv[:] = full_argv
                self.assertEqual(qualify.main(), 0)
                restarted = json.loads((run / 'state.json').read_text())
                self.assertEqual(restarted['results']['pulse_report']['attempt'], 3)
                self.assertEqual(restarted['pulse_completion'], ['', '', ''])
                command_line = Path(restarted['results']['pulse_report']['log']).read_text().splitlines()[0]
                command = json.loads(command_line.removeprefix('COMMAND '))
                self.assertNotIn('--complete-from', command)
                self.assertNotIn('--complete-sha256', command)
                with self.assertRaises(ValueError):
                    qualify.bind_pulse_completion(restarted, (str(source), 'a' * 64, 'b' * 64),
                                                 run, restarted['product_identity'])
                build_log = Path(initial['results']['build']['log'])
                original_build_log = build_log.read_bytes()
                build_log.write_text('damaged after reset')
                with self.assertRaises(SystemExit):
                    qualify.main()
                build_log.write_bytes(original_build_log)
                self.assertEqual(restarted['pulse_completion_origin'], original)
                self.assertEqual(restarted['product_identity'], initial['product_identity'])
                self.assertEqual(restarted['results']['build'], initial['results']['build'])
                self.assertEqual((root / 'builds.txt').read_text(), 'build\n')
                self.assertEqual((source / 'record').read_bytes(), original_record)
                self.assertEqual((run / 'discovery/jobs/pulse_report/attempt-0003/out/record').read_text(),
                                 'fresh-attempt-0003')
                self.assertTrue(qualify.evidence_intact(original))
                self.assertTrue(qualify.evidence_intact(rejected))
                for result in (original, rejected, restarted['results']['pulse_report']):
                    self.assertTrue(Path(result['log']).exists())
                argv[argv.index('full')] = 'light'
                argv.append('--final')
                self.assertEqual(qualify.main(), 0)
                self.assertEqual((root / 'builds.txt').read_text(), 'build\n')

    def test_direct_completion_ledger_cannot_reset_and_rebind(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            state, completion, log = self.fixture(root)
            state['pulse_completion'] = completion
            before = copy.deepcopy(state)
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, ('', '', ''), root, 'original-sdk')
            self.assertEqual(state, before)

if __name__ == '__main__':
    unittest.main()
