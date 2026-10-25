"""A new CPU plan starts a whole Pulse attempt, never mixes old samples."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import qualify


class PulseCpuRetryTests(unittest.TestCase):
    def test_failed_full_retry_preserves_other_jobs_and_evidence(self):
        self.check_retry(False)

    def test_failed_completion_restarts_on_new_cpus_without_wasted_full(self):
        self.check_retry(True)

    def test_interrupted_cpu_change_resumes_without_losing_failed_evidence(self):
        self.check_retry(False, interrupted=True)

    def test_win64_failed_full_retry(self):
        self.check_retry(False, platform='win64')

    def check_retry(self, completion_first, interrupted=False, platform='linux'):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'source').write_text('source')
            subprocess.run(['git', '-C', str(root), 'add', 'source'], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c',
                            'user.email=test@example.invalid', 'commit', '-qm', 'source'], check=True)
            baseline = root / 'baseline'
            baseline.mkdir()
            (baseline / 'sdk').write_text('baseline')
            baseline_mm = root / 'baseline-mm'
            baseline_mm.write_text('mm')
            build = """from pathlib import Path
Path('toolchain').mkdir(exist_ok=True)
Path('toolchain/sdk').write_text('SDK')
Path('runtime/mm').mkdir(parents=True, exist_ok=True)
Path('runtime/mm/manager').write_text('MM')
with Path('builds').open('a') as f: f.write('build\\n')
"""
            core = "from pathlib import Path; p=Path('cores'); p.write_text(p.read_text()+'core\\n' if p.exists() else 'core\\n')"
            pulse = """from pathlib import Path
import sys
out=Path(sys.argv[1]); out.mkdir()
(out/'args').write_text(repr(sys.argv))
passed='--complete-from' not in sys.argv and '--single-cpus' in sys.argv and sys.argv[sys.argv.index('--single-cpus')+1]=='0,4,10,12'
print('PULSE_PASS' if passed else 'MEASUREMENT_REJECTED')
raise SystemExit(0 if passed else 2)
"""
            jobs = []
            for name, script, mode in [('build', build, 'light'), ('core', core, 'light'),
                                       ('pulse_report', pulse, 'full')]:
                jobs.append({'id': name, 'mode': mode, 'platforms': [platform], 'timeout': 10,
                             'needs': [] if name == 'build' else ['build'],
                             'commands': {platform: ['{python}', '-c', script] +
                                          (['{job_dir}/out'] if name == 'pulse_report' else [])}})
            matrix = root / 'matrix.json'
            matrix.write_text(json.dumps({'version': 1, 'jobs': jobs,
                                          'source_inputs': {j['id']: ['source'] for j in jobs}}))
            run = root / 'run'
            argv = ['qualify.py', 'run', '--run-dir', str(run), '--matrix', str(matrix), '--platform', platform,
                    '--mode', 'full', '--baseline-toolchain', str(baseline), '--baseline-mm-source', str(baseline_mm)]
            with patch.object(qualify, 'ROOT', root), patch.object(sys, 'argv', argv):
                self.assertEqual(qualify.main(), 1)
                state_path = run / 'state.json'
                if completion_first:
                    full_argv = argv[:]
                    argv += ['--pulse-complete-from', str(run / 'discovery/jobs/pulse_report/attempt-0001/out'),
                             '--pulse-complete-sha256', 'a' * 64, '--pulse-complete-logs-sha256', 'b' * 64]
                    self.assertEqual(qualify.main(), 1)
                    argv[:] = full_argv
                initial_bytes = state_path.read_bytes()
                initial = json.loads(initial_bytes)
                failed = initial['results']['pulse_report']
                old_log = Path(failed['log']).read_bytes()
                old_out = (run / 'discovery/jobs/pulse_report/attempt-0001/out/args').read_bytes()
                original_argv = argv[:]
                new_argv = argv + ['--pulse-single-cpus', '0,4,10,12']
                for damage in ('status', 'light', 'final', 'frozen', 'passed', 'missing', 'corrupt-log',
                               'completion-request', 'completion-bound'):
                    with self.subTest(damage=damage):
                        state = copy.deepcopy(initial)
                        argv[:] = new_argv
                        if damage == 'status':
                            argv[1] = 'status'
                        elif damage == 'light':
                            argv[argv.index('full')] = 'light'
                        elif damage == 'final':
                            argv[argv.index('full')] = 'light'
                            argv.append('--final')
                        elif damage == 'frozen':
                            state['final_head'] = initial['created_head']
                        elif damage == 'passed':
                            state['results']['pulse_report']['status'] = 'pass'
                        elif damage == 'missing':
                            state['results'].pop('pulse_report')
                        elif damage == 'corrupt-log':
                            state['results']['pulse_report']['log_identity'] = 'damaged'
                        elif damage == 'completion-request':
                            argv += ['--pulse-complete-from', str(root / 'prior'), '--pulse-complete-sha256',
                                     'a' * 64, '--pulse-complete-logs-sha256', 'b' * 64]
                        else:
                            state['pulse_completion'] = [str(root / 'prior'), 'a' * 64, 'b' * 64]
                            state.pop('pulse_completion_origin', None)
                        state_path.write_text(json.dumps(state))
                        before = state_path.read_bytes()
                        with self.assertRaises(SystemExit) as caught:
                            qualify.main()
                        self.assertEqual(caught.exception.code, 2)
                        self.assertEqual(state_path.read_bytes(), before)
                        self.assertEqual((root / 'builds').read_text(), 'build\n')
                state_path.write_bytes(initial_bytes)
                argv[:] = new_argv
                if interrupted:
                    with patch.object(qualify.ThreadPoolExecutor, 'submit', side_effect=KeyboardInterrupt):
                        with self.assertRaises(KeyboardInterrupt):
                            qualify.main()
                    stopped = json.loads(state_path.read_bytes())
                    self.assertEqual(stopped['pulse_single_cpus'], '0,4,10,12')
                    self.assertEqual(stopped['results'], initial['results'])
                    self.assertTrue(qualify.evidence_intact(failed))
                    source = str(run / 'discovery/jobs/pulse_report/attempt-0001/out')
                    qualify.bind_pulse_completion(stopped, (source, 'a' * 64, 'b' * 64), run,
                                                 stopped['product_identity'])
                    self.assertEqual(stopped['pulse_completion_origin'], failed)
                self.assertEqual(qualify.main(), 0)
                current = json.loads(state_path.read_bytes())
                self.assertEqual(current['results']['pulse_report']['attempt'], failed['attempt'] + 1)
                self.assertEqual(current['pulse_completion'], ['', '', ''])
                command = json.loads(Path(current['results']['pulse_report']['log']).read_text()
                                     .splitlines()[0].removeprefix('COMMAND '))
                self.assertNotIn('--complete-from', command)
                if completion_first:
                    self.assertEqual(current['pulse_completion_origin'], initial['pulse_completion_origin'])
                    self.assertTrue(qualify.evidence_intact(current['pulse_completion_origin']))
                self.assertEqual(current['results']['build'], initial['results']['build'])
                self.assertEqual(current['results']['core'], initial['results']['core'])
                self.assertEqual(current['product_identity'], initial['product_identity'])
                self.assertNotEqual(current['results']['pulse_report']['input_signature'], failed['input_signature'])
                self.assertEqual(Path(failed['log']).read_bytes(), old_log)
                self.assertEqual((run / 'discovery/jobs/pulse_report/attempt-0001/out/args').read_bytes(), old_out)
                self.assertTrue(qualify.evidence_intact(failed))
                before = state_path.read_bytes()
                argv[:] = original_argv
                with self.assertRaises(SystemExit):
                    qualify.main()
                self.assertEqual(state_path.read_bytes(), before)
                argv[:] = new_argv
                self.assertEqual(qualify.main(), 0)
                self.assertEqual(json.loads(state_path.read_bytes())['results']['pulse_report']['attempt'],
                                 failed['attempt'] + 1)
                argv[argv.index('full')] = 'light'
                argv.append('--final')
                self.assertEqual(qualify.main(), 0)
                self.assertEqual((root / 'builds').read_text(), 'build\n')
                self.assertEqual((root / 'cores').read_text(), 'core\ncore\n')
                self.assertEqual(json.loads(state_path.read_bytes())['final_head'], initial['created_head'])

                first_final = json.loads(state_path.read_bytes())['final_results']
                (root / 'unrelated').write_text('controller documentation')
                subprocess.run(['git', '-C', str(root), 'add', 'unrelated'], check=True)
                subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c',
                                'user.email=test@example.invalid', 'commit', '-qm', 'unrelated'], check=True)
                new_head = qualify.git('rev-parse', 'HEAD')
                self.assertNotEqual(new_head, initial['created_head'])
                before_refreeze = state_path.read_bytes()
                for changed_file in (Path(current['results']['pulse_report']['log']), root / 'toolchain/sdk'):
                    saved = changed_file.read_bytes()
                    changed_file.write_text('changed evidence or installed product')
                    with self.assertRaises(SystemExit):
                        qualify.main()
                    self.assertEqual(state_path.read_bytes(), before_refreeze)
                    changed_file.write_bytes(saved)
                self.assertEqual(qualify.main(), 0)
                refreshed = json.loads(state_path.read_bytes())
                self.assertEqual(refreshed['final_head'], new_head)
                self.assertEqual(refreshed['results'], current['results'])
                self.assertTrue(all(row['head'] == new_head for row in refreshed['final_results'].values()))
                self.assertTrue(all(row['attempt'] == 2 for row in refreshed['final_results'].values()))
                self.assertTrue(all(qualify.evidence_intact(row) for row in first_final.values()))
                self.assertEqual((root / 'builds').read_text(), 'build\n')
                self.assertEqual((root / 'cores').read_text(), 'core\ncore\ncore\n')
                # A source change invalidating Full still cannot take the shortcut.
                (root / 'source').write_text('different source')
                subprocess.run(['git', '-C', str(root), 'add', 'source'], check=True)
                subprocess.run(['git', '-C', str(root), '-c', 'user.name=Test', '-c',
                                'user.email=test@example.invalid', 'commit', '-qm', 'changed source'], check=True)
                before = state_path.read_bytes()
                with self.assertRaises(SystemExit):
                    qualify.main()
                self.assertEqual(state_path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
