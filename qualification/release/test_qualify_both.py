from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from qualification.release import qualify_both as both


class HostBarrierTests(unittest.TestCase):
    def config(self):
        return {host: {"repo": "/checkout", "python": "python", "run_dir": "/run", "jobs": 4,
                       "memory_mb": 8192, "baseline_toolchain": "/baseline", "ssh": ["ssh", "host"]}
                for host in both.HOSTS}

    def test_failed_medium_on_either_host_blocks_full_on_both(self):
        called = []
        head = "a" * 40
        def invoke(config, host, command, capture=False):
            if command[:2] == ["git", "rev-parse"]:
                return 0, head
            if command[0] == "git":
                return 0, ""
            mode = command[command.index("--mode") + 1]
            called.append((host, mode))
            return (1, "failed") if host == "linux" and mode == "medium" else (0, f"DISCOVERY_PASS {head} platform={host}")
        with patch.object(both, "invoke", side_effect=invoke):
            self.assertEqual(both.run_route(self.config()), 1)
        self.assertEqual(set(called), {(host, mode) for host in both.HOSTS for mode in ("light", "medium")})

    def test_mismatching_candidates_do_not_start_tests(self):
        def invoke(config, host, command, capture=False):
            self.assertTrue(capture)
            return 0, ("a" if host == "linux" else "b") * 40 if command[1] == "rev-parse" else ""
        with patch.object(both, "invoke", side_effect=invoke), self.assertRaises(ValueError):
            both.run_route(self.config())

    def test_plan_has_no_process_or_network_side_effects(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "hosts.json"
            config.write_text(json.dumps(self.config()))
            with patch.object(both.sys, "argv", ["both", "plan", "--config", str(config)]), \
                    patch.object(both, "invoke", side_effect=AssertionError("plan executed a command")), \
                    redirect_stdout(io.StringIO()) as output:
                self.assertEqual(both.main(), 0)
            self.assertIn("PLAN_ONLY", output.getvalue())

    def test_full_and_final_only_follow_successful_peers(self):
        head = "a" * 40
        called = []
        def invoke(config, host, command, capture=False):
            if capture:
                return 0, head if command[1] == "rev-parse" else ""
            called.append((host, command[command.index("--mode") + 1], "--final" in command))
            self.assertEqual(command[command.index("--expect-head") + 1], head)
            marker = "FINAL_EXACT_HEAD_PASS" if "--final" in command else "DISCOVERY_PASS"
            return 0, f"{marker} {head} platform={host}"
        with patch.object(both, "invoke", side_effect=invoke):
            self.assertEqual(both.run_route(self.config()), 0)
        self.assertEqual(len(called), 8)

    def test_skip_pulse_reaches_every_phase_without_a_baseline(self):
        config = self.config()
        for settings in config.values():
            del settings["baseline_toolchain"]
        head = "a" * 40
        called = []
        def invoke(config, host, command, capture=False):
            if capture:
                return 0, head if command[1] == "rev-parse" else ""
            self.assertIn("--skip-pulse", command)
            self.assertNotIn("--baseline-toolchain", command)
            called.append((host, command[command.index("--mode") + 1], "--final" in command))
            marker = "FINAL_EXACT_HEAD_PASS" if "--final" in command else "DISCOVERY_PASS"
            return 0, f"{marker} {head} platform={host} scope=correctness-without-pulse"
        with patch.object(both, "invoke", side_effect=invoke), redirect_stdout(io.StringIO()) as output:
            self.assertEqual(both.run_route(config, skip_pulse=True), 0)
        self.assertEqual(len(called), 8)
        self.assertIn("scope=correctness-without-pulse", output.getvalue())


if __name__ == "__main__":
    unittest.main()
