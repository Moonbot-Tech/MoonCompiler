"""Exercise the MM gate's actual shell verdict without rebuilding mORMot."""
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


GATE = Path(__file__).resolve().parents[1] / 'scripts/mm/run_mormot_mm_gate.sh'
DNS = ('#1 DNS1  #2 DNS2  #3 DNS3  !  - DNS and LDAP: 3 / 3 FAILED  60us\n'
       '  Total failed: 3 / 3  - Network protocols FAILED  64us\n')
END = ('Total assertions failed for all test suits:  3 / 3\n'
       '! Some tests FAILED: please correct the code.\n'
       'FPCMM_REPORTMEMORYLEAKS_DONE\n')


@unittest.skipUnless(sys.platform == 'linux', 'the mORMot MM gate runs on Linux')
class MormotMMVerdict(unittest.TestCase):
    def verdict(self, output, status):
        with tempfile.TemporaryDirectory(prefix='moon-mm-verdict-') as directory:
            work = Path(directory)
            (work / 'logs').mkdir()
            image = work / 'mormot2tests'
            image.write_text(f'#!{sys.executable}\nimport sys\n'
                             f'sys.stdout.write({output!r})\nsys.exit({status})\n')
            image.chmod(0o755)
            body = GATE.read_text(encoding='utf-8').split('\ntotal=0\n', 1)[1]
            # Keep the whole status, report, census and final-summary path.
            script = work / 'gate.sh'
            script.write_text('set -euo pipefail\n'
                              f'out={shlex.quote(str(work))}\nrun_dir=$out\n'
                              'classes=(TNetworkProtocols)\ntotal=0\n' + body)
            result = subprocess.run(['bash', str(script)], capture_output=True,
                                    text=True, timeout=10)
            return result.returncode, (work / 'SUMMARY.txt').exists()

    def test_allowed_dns_failure_and_clean_run(self):
        self.assertEqual(self.verdict(DNS + END, 1), (0, True))
        self.assertEqual(self.verdict(DNS[DNS.index('!'):] + END, 1), (0, True))
        self.assertEqual(self.verdict('Total failed: 0 / 3\n'
                                     'FPCMM_REPORTMEMORYLEAKS_DONE\n', 0), (0, True))

    def test_caught_group_exception_cannot_hide_behind_dns(self):
        # TSynTests.Run's outer handler prints the class directly. It does
        # not increment AssertionsFailed or print "! Exception...".
        for name in ('EAbort', 'ESynException'):
            with self.subTest(exception=name):
                code, summary = self.verdict(DNS + f'! {name}: group failed\n' + END, 1)
                self.assertNotEqual(code, 0)
                self.assertFalse(summary)

    def test_other_failures_remain_failures(self):
        for output, status in (
            (DNS + END, 73),
            (DNS + '! ExceptionOS EAccessViolation\n' + END, 1),
            (DNS + '!  - HTTP: 1 / 1 FAILED\n' + END, 1),
            (DNS + ' small block leak x1 of size=48\n' + END, 1),
            (DNS + END.replace('FPCMM_REPORTMEMORYLEAKS_DONE\n', ''), 1),
        ):
            with self.subTest(output=output, status=status):
                code, summary = self.verdict(output, status)
                self.assertNotEqual(code, 0)
                self.assertFalse(summary)


if __name__ == '__main__':
    unittest.main()
