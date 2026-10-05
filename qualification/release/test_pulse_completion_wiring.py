"""The stock controller must sign the bounded Pulse completion source and command."""

import unittest
from pathlib import Path

import qualify
import qualify_both


MATRIX = Path(__file__).with_name("matrix.json")


class PulseCompletionWiring(unittest.TestCase):
    def test_only_pulse_receives_completion_inputs(self):
        original = {job["id"]: job for job in qualify.load_matrix(MATRIX, "win64", "full")}
        self.assertIn("qualification/release/pulse_completion.py", original["pulse_report"]["source_inputs"])
        self.assertIn("qualification/release/pulse_roundto_oracle.py", original["pulse_report"]["source_inputs"])
        self.assertEqual(original["pulse_report"]["timeout"], 7200)
        sha = "a" * 64
        changed = {job["id"]: job for job in qualify.load_matrix(
            MATRIX, "win64", "full", pulse_single_cpus="4,6,12,14",
            pulse_completion=("R:/source", sha, "b" * 64))}
        self.assertEqual(original.keys(), changed.keys())
        for name in original:
            before, after = original[name]["commands"]["win64"], changed[name]["commands"]["win64"]
            if name == "pulse_report":
                self.assertEqual(after[-8:], ["--single-cpus", "4,6,12,14", "--complete-from",
                                              "R:/source", "--complete-sha256", sha,
                                              "--complete-logs-sha256", "b" * 64])
            else:
                self.assertEqual(before, after)

    def test_both_hosts_pass_distinct_sources(self):
        for host, platform in (("windows", "win64"), ("linux", "linux")):
            settings = {"python": "python3", "run_dir": "/tmp/test", "jobs": 8, "memory_mb": 16384,
                        "baseline_toolchain": "/tmp/baseline", "pulse_complete_from": f"/tmp/{host}-source",
                        "pulse_complete_sha256": "a" * 64, "pulse_complete_logs_sha256": "b" * 64}
            command = qualify_both.arguments(settings, host, "run", "full", False, "c" * 40)
            self.assertEqual(command[command.index("--pulse-complete-from") + 1], f"/tmp/{host}-source")
            self.assertEqual(command[command.index("--platform") + 1], platform)


if __name__ == "__main__":
    unittest.main()
