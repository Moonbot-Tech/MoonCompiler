from contextlib import redirect_stdout
import hashlib
import io
import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SUITE = Path(__file__).resolve().parents[1]
SCRIPTS = SUITE / "scripts"
DEVIL = SUITE / "tests" / "devil"
sys.path.insert(0, str(SCRIPTS))

import generate_devil
import run_devil_env_gate
import run_devil_gate
import run_devil_mutation
import run_devil_resident_gate
import devil_toolchain


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DevilRunnerContractsTest(unittest.TestCase):
    def test_product_profiles_keep_range_checks_disabled(self) -> None:
        debug = ["-O-", "-gl", "-gw3", "-Ci", "-Co-", "-Cr-", "-Ct-", "-Sa"]
        release = ["-O3", "-gl", "-gw3", "-Ci", "-Co-", "-Cr-", "-Ct-", "-Sa-"]
        self.assertEqual(devil_toolchain.PROFILES["debug"], debug)
        self.assertEqual(devil_toolchain.PROFILES["release"], release)
        self.assertEqual(
            devil_toolchain.PROFILES["o1"],
            ["-O1", *release[1:]],
        )
        self.assertEqual(
            devil_toolchain.PROFILES["o2"],
            ["-O2", *release[1:]],
        )

        rtl_test = runpy.run_path(str(SUITE.parents[1] / "RTL-test" / "run.py"))
        self.assertEqual(rtl_test["MODES"]["debug"], debug)
        self.assertEqual(rtl_test["MODES"]["o2"], ["-O2", *release[1:]])
        self.assertEqual(rtl_test["MODES"]["o3"], release)

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

    def test_optimizer_effects_are_a_closed_matrix_not_random_examples(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "17", "--cases", "1",
                    "--layers", "opt", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            manifest = json.loads(
                (output / "devil_manifest.json").read_text(encoding="utf-8"))
            source = (output / "devil_opt.inc").read_text(encoding="utf-8")
            has_cross_unit = (output / "devil_opt_effect_unit.pas").is_file()

        coverage = manifest["optimizer_effects"]
        self.assertEqual(coverage["cases"], 504)
        self.assertEqual(coverage["critical_triples_possible"], 504)
        self.assertEqual(coverage["critical_triples_covered"], 504)
        self.assertEqual(coverage["critical_triples_missing"], [])
        self.assertEqual(coverage["pairs_possible"], 414)
        self.assertEqual(coverage["pairs_covered"], 414)
        self.assertEqual(coverage["pairs_missing"], [])
        self.assertTrue(coverage["exact_stale_global_anchor"])
        self.assertIn(
            "global-call x counter-mul x after-first x for x i32", source)
        self.assertTrue(has_cross_unit)

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

    def test_known_checks_absorb_only_their_derived_runtime_exit(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 2
        build.digest = "0000000000000001"
        build.failures = {
            "dvl-lang-00001-type": ("0000000000000005", "0000000000000006"),
        }
        runtime = [{
            "kind": "runtime-failed", "build": "release", "exit": 2,
            "detail": ["DEVIL_FAIL seed=1"],
        }]
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-type",
            "builds": {"release": "0000000000000005"},
            "known": "dvl-0014",
        }]

        findings, known_hits = run_devil_gate.absorb_derived_runtime_failures(
            runtime, known, [build])

        self.assertEqual(findings, [])
        self.assertEqual(known_hits[-1]["known"], "derived")

    def test_runtime_exit_stays_fresh_without_named_known_failures(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 217
        build.digest = "0000000000000001"
        runtime = [{"kind": "runtime-failed", "build": "release"}]

        findings, known_hits = run_devil_gate.absorb_derived_runtime_failures(
            runtime, [], [build])

        self.assertEqual(findings, runtime)
        self.assertEqual(known_hits, [])

    def test_one_unknown_check_keeps_runtime_exit_fresh(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 2
        build.digest = "0000000000000001"
        build.failures = {
            "dvl-lang-00001-type": ("0000000000000005", "0000000000000006"),
            "dvl-lang-00002-new": ("0000000000000001", "0000000000000002"),
        }
        runtime = [{"kind": "runtime-failed", "build": "release"}]
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-type",
            "builds": {"release": "0000000000000005"},
            "known": "dvl-0014",
        }]

        findings, known_hits = run_devil_gate.absorb_derived_runtime_failures(
            runtime, known, [build])

        self.assertEqual(findings, runtime)
        self.assertEqual(known_hits, known)

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

    def test_resident_rejects_silent_or_incomplete_execution(self) -> None:
        findings: list[str] = []
        run_devil_resident_gate.validate_run(
            "silent",
            run_devil_resident_gate.Run("", 0),
            ["alpha"],
            1,
            findings,
        )
        self.assertTrue(any("missing answer lines" in item for item in findings))
        self.assertTrue(any("stage answers mismatch" in item for item in findings))
        self.assertTrue(any("carrier answers incomplete" in item for item in findings))

    def test_resident_release_shape_cannot_be_silently_weakened(self) -> None:
        layer = {
            "profiles": ["debug", "o1", "o2", "release"],
            "shapes": {
                "default": {"carriers": 8, "laps": 40},
                "handoff": {"carriers": 4, "laps": 8},
            },
        }
        full = SimpleNamespace(
            carriers=None, laps=None, profiles=None, handoff=False,
            diagnostic_subset=False,
        )
        self.assertEqual(
            run_devil_resident_gate.resolve_run_contract(full, layer),
            (8, 40, ["debug", "o1", "o2", "release"], True),
        )

        silent_subset = SimpleNamespace(
            carriers=1, laps=1, profiles="release", handoff=False,
            diagnostic_subset=False,
        )
        with self.assertRaisesRegex(
            run_devil_resident_gate.ContractError, "diagnostic overrides"
        ):
            run_devil_resident_gate.resolve_run_contract(silent_subset, layer)

        explicit_subset = SimpleNamespace(
            carriers=1, laps=1, profiles="release", handoff=False,
            diagnostic_subset=True,
        )
        self.assertEqual(
            run_devil_resident_gate.resolve_run_contract(explicit_subset, layer),
            (1, 1, ["release"], False),
        )

        handoff = SimpleNamespace(
            carriers=None, laps=None, profiles=None, handoff=True,
            diagnostic_subset=False,
        )
        self.assertEqual(
            run_devil_resident_gate.resolve_run_contract(handoff, layer),
            (4, 8, ["debug", "o1", "o2", "release"], False),
        )

    def test_mutation_finding_family_keeps_layer_attribution(self) -> None:
        self.assertEqual(
            run_devil_mutation.finding_family({
                "kind": "model-mismatch",
                "check": "dvl-opt-00001-global-call",
            }),
            "opt",
        )
        self.assertEqual(
            run_devil_mutation.finding_family({
                "kind": "layer-digest-split", "layer": "life",
            }),
            "life",
        )
        self.assertEqual(
            run_devil_mutation.finding_family({"kind": "compile-failed"}),
            "compile-failed",
        )

    def test_mutation_compares_known_and_new_observations_equally(self) -> None:
        report = [{
            "seed": 7,
            "findings": [{
                "kind": "model-mismatch",
                "check": "dvl-opt-00001-fresh",
                "builds": {"release": "0000000000000002"},
            }],
            "known_hits": [{
                "kind": "model-mismatch",
                "check": "dvl-opt-00002-known",
                "builds": {"release": "0000000000000003"},
                "known": "dvl-9999",
            }],
        }]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gate.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            observations = run_devil_mutation.load_observations(path)

        rows = list(observations.values())
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["seed"] for row in rows}, {7})
        self.assertEqual(
            {row["check"] for row in rows},
            {"dvl-opt-00001-fresh", "dvl-opt-00002-known"},
        )
        self.assertFalse(any("known" in row for row in rows))

    def test_mutation_uses_exact_baseline_for_each_generated_layer_set(self) -> None:
        selected = [
            ("a", "first", "lang,capture", "one"),
            ("b", "second", "expr,fold", "two"),
            ("c", "third", "lang,capture", "three"),
        ]
        self.assertEqual(
            run_devil_mutation.baseline_layer_sets(selected, False),
            ["expr,fold", "lang,capture"],
        )
        self.assertEqual(
            run_devil_mutation.baseline_layer_sets(selected, True),
            ["all"],
        )


if __name__ == "__main__":
    unittest.main()
