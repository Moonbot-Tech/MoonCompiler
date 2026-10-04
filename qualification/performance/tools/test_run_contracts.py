#!/usr/bin/env python3
"""run_contracts.py: a corpus judge that did not run is a failure."""
from __future__ import annotations

import io
import os
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_contracts  # noqa: E402


def corpus_suite(outcome: str) -> unittest.TestSuite:
    def judge(test: unittest.TestCase) -> None:
        if outcome == "all":
            test.assertNotIn("PULSE_CASE_LOOP_PROGRAMS", os.environ)
        if outcome == "skip":
            test.skipTest("the product toolchain is not built")
        if outcome == "fail":
            test.fail("CASE_LOOP_LOAD")

    corpus = type("CorpusTests", (unittest.TestCase,), {"test_judge": judge, "__module__": "test_check_case_loads"})
    other = type("OtherTests", (unittest.TestCase,), {"test_other": lambda test: None, "__module__": "test_other"})
    return unittest.TestSuite([corpus("test_judge"), other("test_other")])


class RunContractsTests(unittest.TestCase):
    def run_main(self, suite: unittest.TestSuite, *arguments: str) -> tuple[int, str]:
        output = io.StringIO()
        with mock.patch.object(unittest.defaultTestLoader, "discover", return_value=suite), \
                mock.patch.object(sys, "argv", ["run_contracts.py", *arguments]), \
                mock.patch.dict(os.environ), \
                redirect_stdout(output), redirect_stderr(io.StringIO()):
            code = run_contracts.main()
        return code, output.getvalue()

    def test_the_judge_that_ran_and_passed_passes(self) -> None:
        with mock.patch.dict(os.environ, {"PULSE_CASE_LOOP_PROGRAMS": "repairs"}):
            code, output = self.run_main(corpus_suite("all"))
        self.assertEqual(code, 0)
        self.assertIn("PULSE_CONTRACTS_OK tests=2 skipped=0 corpus_judge=all", output)

    def test_a_skipped_judge_fails(self) -> None:
        code, output = self.run_main(corpus_suite("skip"))
        self.assertEqual(code, 1)
        self.assertIn("the corpus judge was skipped", output)

    def test_a_failing_judge_fails(self) -> None:
        self.assertEqual(self.run_main(corpus_suite("fail"))[0], 1)

    def test_a_suite_without_the_judge_fails(self) -> None:
        without = unittest.TestSuite([test for test in corpus_suite("pass") if "Corpus" not in test.id()])
        code, output = self.run_main(without)
        self.assertEqual(code, 1)
        self.assertIn("not among the tests", output)

    def test_a_subset_still_requires_the_judge(self) -> None:
        code, output = self.run_main(corpus_suite("pass"), "--case-loop-programs", "repairs,product-forms")
        self.assertEqual(code, 0)
        self.assertIn("tests=2 skipped=0 corpus_judge=repairs,product-forms", output)
        code, output = self.run_main(corpus_suite("fail"), "--case-loop-programs", "repairs,product-forms")
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
