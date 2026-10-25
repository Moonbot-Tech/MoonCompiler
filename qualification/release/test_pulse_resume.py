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
            for replacement in [('', '', ''), (completion[0], 'c' * 64, completion[2]),
                                (str(root / 'foreign'), completion[1], completion[2])]:
                with self.subTest(replacement=replacement), self.assertRaises(ValueError):
                    qualify.bind_pulse_completion(state, replacement, root, 'original-sdk')
                self.assertEqual(state, bound)
            with self.assertRaises(ValueError):
                qualify.bind_pulse_completion(state, completion, root, 'rebuilt-sdk')

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


if __name__ == '__main__':
    unittest.main()
