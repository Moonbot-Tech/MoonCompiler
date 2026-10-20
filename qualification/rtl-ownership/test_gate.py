"""A value-correct executable that leaks must fail the ownership gate."""
import unittest
from run_gate import passed


class OwnershipOracle(unittest.TestCase):
    def test_zero_balance_and_completion(self):
        self.assertTrue(passed(0, "DONE\nFPCX64MM_DIAGNOSTIC live-blocks=0 tagged=0", "DONE"))

    def test_exit_zero_does_not_hide_a_leak(self):
        self.assertFalse(passed(0, "DONE\nFPCX64MM_DIAGNOSTIC live-blocks=32", "DONE"))

    def test_missing_or_duplicate_balance_is_not_evidence(self):
        for output in ["DONE", "DONE\nFPCX64MM_DIAGNOSTIC live-blocks=0\nFPCX64MM_DIAGNOSTIC live-blocks=0"]:
            self.assertFalse(passed(0, output, "DONE"))

    def test_process_failure_and_incomplete_execution_fail(self):
        self.assertFalse(passed(1, "DONE\nFPCX64MM_DIAGNOSTIC live-blocks=0", "DONE"))
        self.assertFalse(passed(0, "FPCX64MM_DIAGNOSTIC live-blocks=0", "DONE"))


if __name__ == "__main__":
    unittest.main()
