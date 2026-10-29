"""Keep the quiet workload quiet and reject reduced work masquerading as a win."""
import unittest
from pulse_moonshot import parse

VALID = ('PULSE_MOONSHOT model=2 borrowed_content=0 api_status_replays=0 filter_checks=17664 full_checks=0 mode=quiet workers=92 rounds=192 period_ms=16 granularity_us=15625 '
         'char_bytes=2 phase_start_filetime=0 wall_ns=6000000000 user_ns=100000000 kernel_ns=50000000 '
         'checks=17664 signals=0 timeouts=17664 formats=141312 state_checks=17664 local_order_checks=4416 '
         'log_records=0 exchange_requests=0 history_rows=0 '
         'latency_p50_ns=0 latency_p95_ns=0 latency_p99_ns=0 latency_max_ns=0 verified=1')


class MoonShotOracle(unittest.TestCase):
    def check(self, text):
        return parse(text, 'quiet', 192, 16, 15625)

    def test_quiet_work(self):
        self.assertEqual(self.check(VALID)['cpu_percent'], 2.5)

    def test_wrong_work(self):
        for before, after in [('checks=17664', 'checks=17663'), ('formats=141312', 'formats=0'),
                              ('char_bytes=2', 'char_bytes=1'), ('timeouts=17664', 'timeouts=1'),
                              ('log_records=0', 'log_records=92'), ('exchange_requests=0', 'exchange_requests=1'),
                              ('history_rows=0', 'history_rows=100'), ('granularity_us=15625', 'granularity_us=0'),
                              ('filter_checks=17664', 'filter_checks=0'), ('model=2', 'model=1'),
                              ('state_checks=17664', 'state_checks=0'), ('local_order_checks=4416', 'local_order_checks=0')]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.check(VALID.replace(before, after))

    def test_bad_measurement(self):
        for text in ['', VALID+'\n'+VALID, VALID.replace('wall_ns=6000000000', 'wall_ns=0'),
                     VALID.replace('user_ns=100000000', 'user_ns=-1'),
                     VALID.replace('latency_max_ns=0', 'latency_max_ns=500')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_no_cpu_is_not_invented(self):
        self.assertEqual(self.check(VALID.replace('user_ns=100000000', 'user_ns=0')
                                   .replace('kernel_ns=50000000', 'kernel_ns=0'))['cpu_ns'], 0)

    def test_variant_and_periodic_work_are_explicit(self):
        self.assertEqual(self.check(VALID.replace('borrowed_content=0', 'borrowed_content=1'))['borrowed_content'], 1)
        for before, after in [('borrowed_content=0', ''), ('borrowed_content=0', 'borrowed_content=2'),
                              ('full_checks=0', ''), ('full_checks=0', 'full_checks=17665'),
                              ('api_status_replays=0', ''), ('api_status_replays=0', 'api_status_replays=4417')]:
            with self.subTest(before=before, after=after), self.assertRaises(ValueError):
                self.check(VALID.replace(before, after))

    def test_response_requires_exact_delivery(self):
        row = VALID.replace('mode=quiet','mode=response').replace('signals=0','signals=184')
        row = row.replace('timeouts=17664','timeouts=17480')
        for key, value in [('p50',10),('p95',20),('p99',30),('max',40)]:
            row = row.replace(f'latency_{key}_ns=0', f'latency_{key}_ns={value}')
        self.assertEqual(parse(row,'response',192,16,15625)['signals'],184)
        with self.assertRaises(ValueError):
            parse(row.replace('signals=184','signals=183'),'response',192,16,15625)


if __name__ == '__main__':
    unittest.main()
