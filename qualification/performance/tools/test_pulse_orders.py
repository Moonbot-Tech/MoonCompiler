"""Reject unequal work and misleading latency/CPU summaries."""
import unittest
from pulse_orders import parse

VALID = ('PULSE_ORDER mode=orders workers=92 rounds=256 period_ms=31 wall_ns=8000000000 '
         'user_ns=100000000 kernel_ns=80000000 cycles=123 signals=184 timeouts=23368 logs=2944 '
         'latency_p50_ns=16000 latency_p95_ns=30000 latency_p99_ns=60000 latency_max_ns=90000 verified=1')


class OrderOracle(unittest.TestCase):
    def check(self, text):
        return parse(text, 'orders', 92, 256, 2)

    def test_same_work(self):
        self.assertEqual(self.check(VALID)['cpu_ns'], 180000000)

    def test_lost_or_extra_work(self):
        for before, after in [('signals=184', 'signals=183'), ('timeouts=23368', 'timeouts=23369'),
                              ('logs=2944', 'logs=2943'), ('period_ms=31', 'period_ms=16'),
                              ('verified=1', 'verified=0')]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.check(VALID.replace(before, after))

    def test_bad_observations(self):
        for text in ['', VALID+'\n'+VALID, VALID.replace('wall_ns=8000000000', 'wall_ns=0'),
                     VALID.replace('user_ns=100000000', 'user_ns=-1'),
                     VALID.replace('latency_p99_ns=60000', 'latency_p99_ns=100')]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.check(text)

    def test_zero_windows_cpu_remains_zero(self):
        # The runner must not manufacture a CPU estimate from latency or cycles.
        row=self.check(VALID.replace('user_ns=100000000', 'user_ns=0').replace('kernel_ns=80000000', 'kernel_ns=0'))
        self.assertEqual(row['cpu_ns'], 0)

    def test_profile_must_be_applied_by_binary(self):
        with self.assertRaises(ValueError):
            parse(VALID, 'orders', 92, 256, 2, 31, 15625)
        text = VALID + ' granularity_us=15625 min_timeout_ns=31250000 timeout_slack_ns=1000000'
        self.assertEqual(parse(text, 'orders', 92, 256, 2, 31, 15625)['granularity_us'], 15625)
        with self.assertRaises(ValueError):
            self.check(text)
        with self.assertRaises(ValueError):
            parse(text.replace('min_timeout_ns=31250000', 'min_timeout_ns=16000000'), 'orders', 92, 256, 2, 31, 15625)

if __name__ == '__main__':
    unittest.main()
