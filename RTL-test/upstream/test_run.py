#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE = Path(__file__).with_name("run.py")
SPEC = importlib.util.spec_from_file_location("rtl_upstream_run", MODULE)
assert SPEC is not None and SPEC.loader is not None
RUN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUN)


class CompileOutcomeTests(unittest.TestCase):
    def test_expected_compile_failure_is_success(self) -> None:
        self.assertEqual(RUN.compile_outcome({"FAIL": [""]}, 1), "expected_failure")

    def test_unexpected_compile_success_is_failure(self) -> None:
        self.assertEqual(RUN.compile_outcome({"FAIL": [""]}, 0), "unexpected_success")

    def test_ordinary_compile_failure_is_failure(self) -> None:
        self.assertEqual(RUN.compile_outcome({}, 1), "unexpected_failure")

    def test_ordinary_compile_success_is_success(self) -> None:
        self.assertEqual(RUN.compile_outcome({}, 0), "success")


if __name__ == "__main__":
    unittest.main()
