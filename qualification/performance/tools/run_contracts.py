#!/usr/bin/env python3
"""The Pulse contracts the release runs: every test of these tools and the
case-loop judge over the programs the tree builds.

    run_contracts.py [--case-loop-programs repairs,product-forms]

The judge (test_check_case_loads.CorpusTests) builds every program with the
tree's product toolchain unless a subset is named - on Win64 and on Linux
alike. A skipped judge is a failure.
"""
from __future__ import annotations

import argparse
import os
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CORPUS = "test_check_case_loads.CorpusTests."


def tests(suite: unittest.TestSuite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from tests(item)
        else:
            yield item


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case-loop-programs", help="comma-separated programs for the case-loop judge")
    args = parser.parse_args()
    sys.path.insert(0, str(HERE))
    if args.case_loop_programs is not None:
        os.environ["PULSE_CASE_LOOP_PROGRAMS"] = args.case_loop_programs
    else:
        os.environ.pop("PULSE_CASE_LOOP_PROGRAMS", None)
    selected = list(tests(unittest.defaultTestLoader.discover(str(HERE), pattern="test_*.py")))
    judge = [test.id() for test in selected if test.id().startswith(CORPUS)]
    if not judge:
        print("PULSE_CONTRACTS_FAIL the corpus judge is not among the tests")
        return 1
    result = unittest.TextTestRunner(verbosity=1).run(unittest.TestSuite(selected))
    skipped = [test.id() for test, _ in result.skipped if test.id().startswith(CORPUS)]
    if skipped:
        print("PULSE_CONTRACTS_FAIL the corpus judge was skipped: " + ", ".join(skipped))
        return 1
    if not result.wasSuccessful():
        print("PULSE_CONTRACTS_FAIL")
        return 1
    print(f"PULSE_CONTRACTS_OK tests={result.testsRun} skipped={len(result.skipped)} "
          f"corpus_judge={args.case_loop_programs or 'all'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
