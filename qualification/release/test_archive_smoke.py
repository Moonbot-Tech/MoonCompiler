"""The archive report must describe the completed checks, including failures."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from qualification.release import archive_smoke


class ArchiveReportTest(unittest.TestCase):
    def test_failure_report_keeps_independent_stage_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            mm = root / archive_smoke.MM
            bundled = root / "toolchain" / archive_smoke.MM
            mm.parent.mkdir(parents=True)
            bundled.parent.mkdir(parents=True)
            mm.write_text("source", encoding="utf-8")
            bundled.write_text("source", encoding="utf-8")
            manifest = root / "qualification/suite/runner_manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"mormot": {"sources": {
                "current": {"commit": "b" * 40}}}}), encoding="utf-8")
            output = Path(directory) / "result"

            def fake_git(*args):
                return "a" * 40 if args == ("rev-parse", "HEAD") else ""

            def fake_pack(_toolchain, asset):
                asset.write_bytes(b"archive")

            with patch.object(archive_smoke, "ROOT", root), \
                 patch.object(archive_smoke, "git", side_effect=fake_git), \
                 patch.object(archive_smoke, "pack", side_effect=fake_pack), \
                 patch.object(archive_smoke, "run"), \
                 patch.object(archive_smoke, "consumer_smoke", side_effect=RuntimeError("consumer failed")), \
                 patch.object(archive_smoke, "driver_install"), \
                 patch.object(sys, "argv", ["archive_smoke.py", "--output", str(output)]):
                with self.assertRaisesRegex(RuntimeError, "consumer failed"):
                    archive_smoke.main()

            report = json.loads((output / "report.json").read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "fail")
            self.assertEqual(report["asset_sha256"], archive_smoke.sha256(Path(report["asset"])))
            self.assertEqual([step["name"] for step in report["steps"]], ["pack", "consumer", "driver"])
            self.assertEqual([step["status"] for step in report["steps"]], ["pass", "fail", "pass"])
            self.assertEqual(len(report["failures"]), 1)


if __name__ == "__main__":
    unittest.main()
