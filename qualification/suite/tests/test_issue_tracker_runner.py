import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "run_issue_tracker_corpus.py"
SPEC = importlib.util.spec_from_file_location("issue_tracker_runner", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
issue_tracker_runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(issue_tracker_runner)


class IssueTrackerRunnerContractsTest(unittest.TestCase):
    def test_cli_path_is_bound_before_case_working_directory_changes(self) -> None:
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as directory:
            invocation = Path(directory)
            try:
                os.chdir(invocation)
                resolved = issue_tracker_runner.absolute_cli_path(
                    Path("toolchain/bin/fpc"),
                )
            finally:
                os.chdir(previous)

        self.assertTrue(resolved.is_absolute())
        expected = (invocation / "toolchain" / "bin" / "fpc").resolve()
        self.assertEqual(resolved, expected)


if __name__ == "__main__":
    unittest.main()
