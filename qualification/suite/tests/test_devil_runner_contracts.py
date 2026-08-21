from contextlib import redirect_stdout
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SUITE = Path(__file__).resolve().parents[1]
SCRIPTS = SUITE / "scripts"
DEVIL = SUITE / "tests" / "devil"
sys.path.insert(0, str(SCRIPTS))

import generate_devil
import run_devil_env_gate
import run_devil_gate


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DevilRunnerContractsTest(unittest.TestCase):
    def test_generator_never_rewrites_the_tracked_corpus(self) -> None:
        tracked = [
            DEVIL / "devil.dpr",
            DEVIL / "devil_manifest.json",
            DEVIL / "devil_support.inc",
            DEVIL / "devil_expr.inc",
            DEVIL / "devil_runtime.pas",
        ]
        before = {path: sha256(path) for path in tracked}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "91", "--cases", "1",
                    "--layers", "expr", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            self.assertTrue((output / "devil.dpr").is_file())
            self.assertEqual(
                (output / "devil_runtime.pas").read_bytes(),
                (DEVIL / "devil_runtime.pas").read_bytes(),
            )
        self.assertEqual(before, {path: sha256(path) for path in tracked})

    def test_environment_comparison_fails_on_missing_artefact(self) -> None:
        self.assertEqual(
            run_devil_env_gate.changed_artefacts(
                {"program.o": "same", "program.exe": "old"},
                {"program.o": "same", "program.ppu": "new"},
            ),
            ["program.exe", "program.ppu"],
        )

    def test_allocator_contention_uses_a_boolean_oracle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "5", "--cases", "101",
                    "--layers", "load", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            source = (output / "devil_load.inc").read_text(encoding="utf-8")
        self.assertIn("DevilCheckBool('dvl-load-contended-240-waited'", source)
        self.assertIn("SmallGetmemSleepCount > Waited", source)
        self.assertNotIn("DevilNoteLoose('dvl-load-contended-240-waited'", source)

    def test_main_comparison_rejects_runtime_without_terminal_summary(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 217
        build.output = "EVariantTypeCastError: broken generated form"
        self.assertEqual(
            run_devil_gate.compare([build]),
            [{
                "kind": "runtime-failed",
                "build": "release",
                "exit": 217,
                "detail": ["EVariantTypeCastError: broken generated form"],
            }],
        )

    def test_main_report_keeps_known_hits(self) -> None:
        def build(_work: Path, profile: str, _defines: list[str],
                  _timeout: int, reuse: bool = False) -> run_devil_gate.Build:
            result = run_devil_gate.Build(profile + ("+reuse" if reuse else ""))
            result.compiled = True
            result.layers = {"gen"}
            result.checks = 1
            result.digest = "0000000000000001"
            result.layer_digests = {"gen": result.digest}
            result.counters = {"FEEDS": 1, "STEPS": 1}
            if profile == "release":
                result.failures["dvl-gen-00109-nested"] = (
                    "00000000FFFF8001", "0000000000008001"
                )
                result.digest = "0000000000000002"
                result.layer_digests["gen"] = result.digest
            return result

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "report.json"
            argv = ["run_devil_gate.py", "--seeds", "1", "--cases", "1",
                    "--profiles", "debug,release", "--work", str(root / "work"),
                    "--report", str(report)]
            with (mock.patch.object(sys, "argv", argv),
                  mock.patch.object(run_devil_gate.tc, "preflight"),
                  mock.patch.object(run_devil_gate, "run", return_value=(0, "")),
                  mock.patch.object(run_devil_gate, "load_known", return_value=[{
                      "id": "dvl-0043", "kind": "model-mismatch",
                      "check": "^dvl-gen-[0-9]+-nested$",
                  }]),
                  mock.patch.object(run_devil_gate, "build_fpc", side_effect=build),
                  redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(SystemExit, "^0$"):
                    run_devil_gate.main()
            row = json.loads(report.read_text(encoding="utf-8"))[0]
        self.assertEqual(row["findings"], [])
        self.assertIn("dvl-0043", {hit["known"] for hit in row["known_hits"]})


if __name__ == "__main__":
    unittest.main()
