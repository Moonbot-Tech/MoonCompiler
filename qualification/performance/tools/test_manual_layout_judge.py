"""Negative controls: omissions, duplicate evidence and noise cannot earn ACCEPT."""
import copy
import csv
from pathlib import Path
import tempfile
import unittest

from manual_layout_judge import FIELDS, InvalidEvidence, judge, load_spec, parse_runs


class JudgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.manifest = dict(schema=1, cpus=['cpu1', 'cpu2'], processes=['1', '2', '3'], rounds=[1, 2, 3],
                             positions=list(range(0, 4096, 64)), drivers=[0, 32], expected_variants={'cpu1': 3, 'cpu2': 3},
                             cpu_identity={'cpu1': dict(brand='CPU ONE', affinity_cpu=0),
                                           'cpu2': dict(brand='CPU TWO', affinity_cpu=1)},
                             groups=[dict(name='routine', cases=[0], tags=['h'], refphases=[0])], runs=[])
        for cpu_index, cpu in enumerate(self.manifest['cpus']):
            for process in self.manifest['processes']:
                name = f'{cpu}-p{process}.tsv'
                identity = self.manifest['cpu_identity'][cpu]
                lines = [f'# asmstand2 mode=inproc affinity_cpu={identity["affinity_cpu"]} cpu="{identity["brand"]}"',
                         'GEOMETRY_OK 3/3', 'ORACLE_OK 3/3']
                ref = 100 + cpu_index + int(process) / 100
                for position in self.manifest['positions']:
                    for driver in (0, 32):
                        for round_number in (1, 2, 3):
                            for tag, multiplier in [('refp0', 1), ('aap0', 1.001), ('h', .80)]:
                                value = ref * multiplier
                                lines.append(f'S routine c0 {tag} p{position} d{driver} r{round_number} {value:.9f}')
                lines.append('INPROC_DONE func=routine family=64 drivers=2 entries=384 rounds=3 length_case=0')
                (self.base / name).write_text('\n'.join(lines) + '\n', encoding='utf-8')
                self.manifest['runs'].append(dict(cpu=cpu, process=process, raw=name, cases=[0], accepted=True,
                                                  exit_code=0, monitor_mean=0, monitor_peak=0))

    def rewrite(self, index, transform):
        path = self.base / self.manifest['runs'][index]['raw']
        path.write_text(transform(path.read_text(encoding='utf-8')), encoding='utf-8')

    def verdict(self):
        return judge(self.manifest, self.base)['status']

    def invalid(self):
        with self.assertRaises(InvalidEvidence):
            self.verdict()

    def candidate_scale(self, indexes, scale):
        for index in indexes:
            def replace(text):
                lines = []
                for line in text.splitlines():
                    if line.startswith('S ') and ' h ' in line:
                        prefix, value = line.rsplit(' ', 1)
                        line = f'{prefix} {float(value) / .80 * scale:.9f}'
                    lines.append(line)
                return '\n'.join(lines) + '\n'
            self.rewrite(index, replace)

    def test_complete_repeated_gain_accepts(self):
        self.assertEqual(self.verdict(), 'ACCEPT')

    def test_monitor_limits_cannot_be_relaxed(self):
        self.manifest['limits'] = dict(monitor_mean=5, monitor_peak=100)
        self.invalid()

    def test_gain_with_small_loss_accepts(self):
        self.candidate_scale(range(3, 6), 1.02)
        self.assertEqual(self.verdict(), 'ACCEPT')

    def test_repeated_large_loss_rejects(self):
        self.candidate_scale(range(3, 6), 1.08)
        report = judge(self.manifest, self.base)
        self.assertEqual(report['status'], 'KEEP_OLD')
        self.assertEqual(report['results'][0]['verdict'], 'REJECT')

    def test_one_process_large_loss_blocks_acceptance(self):
        self.candidate_scale([3], 1.08)
        report = judge(self.manifest, self.base)
        self.assertEqual(report['results'][0]['verdict'], 'UNPROVEN')

    def test_repeated_loss_with_bimodal_rounds_is_unproved(self):
        self.candidate_scale(range(6), 1.08)
        paths = [self.base / run['raw'] for run in self.manifest['runs']]
        saved = [path.read_bytes() for path in paths]
        for tag in ('refp0', 'aap0', 'h'):
            with self.subTest(tag=tag):
                for index in range(6):
                    def replace(text):
                        lines = []
                        for line in text.splitlines():
                            if f' {tag} ' in line and ' r3 ' in line:
                                prefix, value = line.rsplit(' ', 1)
                                line = f'{prefix} {float(value) * 1.5:.9f}'
                            lines.append(line)
                        return '\n'.join(lines) + '\n'
                    self.rewrite(index, replace)
                report = judge(self.manifest, self.base)
                self.assertEqual(report['status'], 'KEEP_OLD')
                self.assertEqual(report['results'][0]['verdict'], 'UNPROVEN')
                self.assertEqual(report['results'][0]['hard_cells'], 0)
                for path, data in zip(paths, saved):
                    path.write_bytes(data)

    def test_single_process_gain_is_not_reproduced_gain(self):
        self.candidate_scale([1, 2], .96)
        self.candidate_scale(range(3, 6), 1.02)
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_counter_uncertainty_counts_against_loss_budget(self):
        self.candidate_scale(range(3, 6), 1.045)
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_noisy_control_blocks_even_large_gain(self):
        def replace(text):
            lines = []
            for line in text.splitlines():
                if ' aap0 ' in line:
                    prefix, value = line.rsplit(' ', 1)
                    line = f'{prefix} {float(value) / 1.001 * 1.02:.9f}'
                lines.append(line)
            return '\n'.join(lines) + '\n'
        self.rewrite(0, replace)
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_missing_cpu(self):
        self.manifest['runs'] = self.manifest['runs'][:3]
        self.invalid()

    def test_missing_process(self):
        del self.manifest['runs'][2]
        self.invalid()

    def test_missing_case(self):
        self.manifest['groups'][0]['cases'].append(1)
        self.invalid()

    def test_missing_round(self):
        self.rewrite(0, lambda text: '\n'.join(line for line in text.splitlines() if ' r3 ' not in line))
        self.invalid()

    def test_duplicate_round_preserving_total_count(self):
        self.rewrite(0, lambda text: text.replace(' r3 ', ' r2 '))
        self.invalid()

    def test_wrong_positions_preserving_count(self):
        self.rewrite(0, lambda text: text.replace(' p64 ', ' p4096 '))
        self.invalid()

    def test_wrong_driver_preserving_count(self):
        self.rewrite(0, lambda text: text.replace(' d32 ', ' d16 '))
        self.invalid()

    def test_missing_reference_phase(self):
        self.manifest['groups'][0]['refphases'].append(32)
        self.invalid()

    def test_missing_oracle(self):
        self.rewrite(0, lambda text: text.replace('ORACLE_OK 3/3\n', ''))
        self.invalid()

    def test_partial_oracle(self):
        self.rewrite(0, lambda text: text.replace('ORACLE_OK 3/3', 'ORACLE_OK 2/3'))
        self.invalid()

    def test_failure_even_if_ok_count_follows(self):
        self.rewrite(0, lambda text: 'ORACLE_FAIL routine@h\n' + text)
        self.invalid()

    def test_wrong_geometry_registry_count(self):
        self.rewrite(0, lambda text: text.replace('GEOMETRY_OK 3/3', 'GEOMETRY_OK 4/4'))
        self.invalid()

    def test_missing_completion(self):
        self.rewrite(0, lambda text: '\n'.join(line for line in text.splitlines() if not line.startswith('INPROC_DONE')))
        self.invalid()

    def test_wrong_completion_count(self):
        self.rewrite(0, lambda text: text.replace('entries=384', 'entries=385'))
        self.invalid()

    def test_missing_exit_status(self):
        del self.manifest['runs'][0]['exit_code']
        self.invalid()

    def test_rejected_monitor(self):
        self.manifest['runs'][0]['monitor_peak'] = 20.1
        self.invalid()

    def test_same_raw_assigned_to_two_processes(self):
        self.manifest['runs'][1]['raw'] = self.manifest['runs'][0]['raw']
        self.invalid()

    def test_copied_raw_assigned_to_two_processes(self):
        path = self.base / self.manifest['runs'][1]['raw']
        path.write_bytes((self.base / self.manifest['runs'][0]['raw']).read_bytes())
        self.invalid()

    def test_forged_process_evidence_with_different_file(self):
        run = copy.deepcopy(self.manifest['runs'][0])
        run['raw'] = 'extra.tsv'
        (self.base / run['raw']).write_bytes((self.base / self.manifest['runs'][1]['raw']).read_bytes())
        self.manifest['runs'].append(run)
        self.invalid()

    def test_group_cannot_omit_slow_cpu(self):
        self.manifest['groups'][0]['cpus'] = ['cpu1']
        self.invalid()

    def test_acceptance_cannot_omit_position_zero(self):
        self.manifest['positions'].remove(0)
        self.invalid()

    def test_acceptance_cannot_declare_only_two_positions(self):
        self.manifest['positions'] = [0, 64]
        self.invalid()

    def test_acceptance_cannot_declare_single_caller_phase(self):
        self.manifest['drivers'] = [0]
        self.invalid()

    def test_probe_profile_cannot_accept(self):
        self.manifest['profile'] = 'probe'
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def reduce_to_two_processes(self):
        self.manifest['processes'] = ['1', '2']
        self.manifest['runs'] = [run for run in self.manifest['runs'] if run['process'] in ('1', '2')]

    def test_two_processes_cannot_accept(self):
        self.reduce_to_two_processes()
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_two_processes_can_reject(self):
        self.candidate_scale(range(3, 6), 1.08)
        self.reduce_to_two_processes()
        self.assertEqual(judge(self.manifest, self.base)['results'][0]['verdict'], 'REJECT')

    def test_explicit_geometry_mismatch_even_if_counts_complete(self):
        self.rewrite(0, lambda text: 'GEOMETRY_MISMATCH routine.h\n' + text)
        self.invalid()

    def seven_rounds(self):
        self.manifest['rounds'] = list(range(1, 8))
        for index in range(6):
            def replace(text):
                lines = []
                for line in text.splitlines():
                    if ' r3 ' in line:
                        lines.extend(line.replace(' r3 ', f' r{round_number} ') for round_number in range(3, 8))
                    else:
                        lines.append(line.replace('rounds=3 ', 'rounds=7 '))
                return '\n'.join(lines) + '\n'
            self.rewrite(index, replace)

    def perturb_rounds(self, tag, rounds):
        def replace(text):
            lines = []
            for line in text.splitlines():
                if f' {tag} ' in line and any(f' r{number} ' in line for number in rounds):
                    prefix, value = line.rsplit(' ', 1)
                    line = f'{prefix} {float(value) * 1.5:.9f}'
                lines.append(line)
            return '\n'.join(lines) + '\n'
        self.rewrite(0, replace)

    def test_two_bad_rounds_candidate_bimodality_blocks_acceptance(self):
        self.seven_rounds()
        self.perturb_rounds('h', [6, 7])
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_two_bad_rounds_reference_bimodality_blocks_acceptance(self):
        self.seven_rounds()
        self.perturb_rounds('refp0', [6, 7])
        self.assertEqual(self.verdict(), 'KEEP_OLD')

    def test_one_interruption_outlier_does_not_block_acceptance(self):
        self.seven_rounds()
        self.perturb_rounds('h', [7])
        self.assertEqual(self.verdict(), 'ACCEPT')

    def test_wrong_cpu_brand(self):
        self.rewrite(0, lambda text: text.replace('cpu="CPU ONE"', 'cpu="CPU TWO"'))
        self.invalid()

    def test_wrong_cpu_affinity(self):
        self.rewrite(0, lambda text: text.replace('affinity_cpu=0', 'affinity_cpu=22'))
        self.invalid()

    def test_missing_cpu_identity(self):
        del self.manifest['cpu_identity']['cpu1']
        self.invalid()

    def test_missing_cpu_header(self):
        self.rewrite(0, lambda text: '\n'.join(line for line in text.splitlines() if not line.startswith('# asmstand2 ')))
        self.invalid()

    def test_split_rounds_from_separate_launches_are_not_one_process(self):
        run = copy.deepcopy(self.manifest['runs'][0])
        path = self.base / run['raw']
        lines = path.read_text(encoding='utf-8').splitlines()
        path.write_text('\n'.join(line for line in lines if ' r3 ' not in line), encoding='utf-8')
        run['raw'] = 'split.tsv'
        (self.base / run['raw']).write_text('\n'.join(line for line in lines if not line.startswith('S ') or ' r3 ' in line),
                                           encoding='utf-8')
        self.manifest['runs'].append(run)
        self.invalid()

    def write_csv(self):
        rows = parse_runs(load_spec(self.manifest, self.base))
        path = self.base / 'cells.csv'
        with path.open('w', newline='', encoding='utf-8') as stream:
            writer = csv.DictWriter(stream, fieldnames=FIELDS, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(rows)
        return path

    def test_csv_matches_recomputed_raw(self):
        self.assertEqual(judge(self.manifest, self.base, self.write_csv())['status'], 'ACCEPT')

    def test_csv_false_loss_is_rejected(self):
        path = self.write_csv()
        text = path.read_text(encoding='utf-8').splitlines()
        row = text[1].split(',')
        row[-2] = '0'
        text[1] = ','.join(row)
        path.write_text('\n'.join(text), encoding='utf-8')
        with self.assertRaises(InvalidEvidence):
            judge(self.manifest, self.base, path)

    def test_csv_missing_row_is_rejected(self):
        path = self.write_csv()
        path.write_text('\n'.join(path.read_text(encoding='utf-8').splitlines()[:-1]), encoding='utf-8')
        with self.assertRaises(InvalidEvidence):
            judge(self.manifest, self.base, path)


if __name__ == '__main__':
    unittest.main()
