from contextlib import redirect_stdout
import io
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "suite/scripts"
sys.path.insert(0, str(SCRIPTS))
import run_devil_all as all_gates
import run_devil_gate as gate


class DevilParallelTests(unittest.TestCase):
    def test_determinism_compares_runs_only_for_the_same_product_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(work=Path(directory), profiles="release", defines="", cases=1,
                                   layers="all", timeout=10, program_timeout=10, profile_jobs=1,
                                   separate_units=False, second_program=False, shuffle_order=False,
                                   ppu_reuse=False, dcc=None, determinism=True, checkpoint_key="product-a")
            image = b"compiler a"
            def build(work, profile, defines, timeout, program_timeout):
                out = work / "out-release"
                out.mkdir(exist_ok=True)
                (work / "devil.dpr").write_text("program devil; begin end.")
                (out / "devil.exe").write_bytes(image)
                result = gate.Build(profile)
                result.compiled = True
                return result
            def run(command, cwd, timeout):
                if command == ["fpc"]:
                    (cwd / "out-release-again/devil.exe").write_bytes(image)
                return 0, ""
            with patch.object(gate, "build_fpc", side_effect=build), \
                    patch.object(gate.tc, "compile_command", return_value=["fpc"]), \
                    patch.object(gate, "run", side_effect=run), patch.object(gate, "compare", return_value=[]), \
                    patch.object(gate, "load_known", return_value=[]), redirect_stdout(io.StringIO()):
                self.assertEqual(gate.run_seed(args, 1)["findings"], [])
                args.checkpoint_key = "product-b"
                image = b"compiler b"
                self.assertEqual(gate.run_seed(args, 1)["findings"], [])
                image = b"compiler b changed under identical inputs"
                findings = gate.run_seed(args, 1)["findings"]
            self.assertEqual([row["kind"] for row in findings], ["nondeterministic-across-runs"])

    def test_determinism_includes_and_preserves_the_linked_program_on_both_platforms(self):
        for name in ("devil", "devil.exe"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                first = work / "out-release"
                first.mkdir()
                (first / name).write_bytes(b"first executable")
                (first / "devil.o").write_bytes(b"same object")
                def rebuild(command, cwd, timeout):
                    again = work / "out-release-again"
                    (again / name).write_bytes(b"changed executable")
                    (again / "devil.o").write_bytes(b"same object")
                    return 0, ""
                with patch.object(gate.tc, "compile_command", return_value=["fpc"]), \
                        patch.object(gate, "run", side_effect=rebuild):
                    findings = gate.build_twice(work, "release", [], 10, input_key="product")
                self.assertEqual(len(findings), 1)
                self.assertEqual(findings[0]["kind"], "nondeterministic-build")
                self.assertEqual(findings[0]["artefacts"], [name])
                self.assertEqual((work / "nondeterminism/pair-first" / name).read_bytes(), b"first executable")
                self.assertEqual((work / "nondeterminism/pair-second" / name).read_bytes(), b"changed executable")

    def test_separate_unit_consumers_do_not_force_the_producers_to_recompile(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / "devil_a.pas").write_text("unit devil_a; interface implementation end.")
            (work / "devil_b.pas").write_text("unit devil_b; interface uses devil_a; implementation end.")
            (work / "devil.dpr").write_text("program devil; uses devil_b; begin end.")
            executable = work / "out-separate/devil.exe"
            commands = []
            def run(command, cwd, timeout):
                commands.append(command)
                executable.write_text("fixture")
                return 0, ""
            with patch.object(gate.tc, "compile_command", side_effect=lambda source, *a, **k: ["fpc", "-B", str(source)]), \
                    patch.object(gate.tc, "executable", return_value=executable), patch.object(gate, "run", side_effect=run):
                result = gate.build_separate(work, "release", [], 10, 10)
            self.assertTrue(result.compiled)
            self.assertEqual([Path(command[-1]).name for command in commands[:-1]],
                             ["devil_a.pas", "devil_b.pas", "devil.dpr"])
            for command in commands[:-1]:
                self.assertNotIn("-B", command)

    def test_ppu_reuse_omits_force_rebuild_and_runs_in_profile_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            executable = work / "out-debug/devil.exe"
            commands = []
            def run(command, cwd, timeout):
                commands.append((command, cwd))
                executable.write_text("fixture")
                return 0, ""
            with patch.object(gate.tc, "compile_command", side_effect=lambda *a, **k: ["fpc", "-B", "devil.dpr"]), \
                    patch.object(gate.tc, "executable", return_value=executable), patch.object(gate, "run", side_effect=run):
                gate.build_fpc(work, "debug", [], 10, 10)
                gate.build_fpc(work, "debug", [], 10, 10, reuse=True)
            self.assertIn("-B", commands[0][0])
            self.assertNotIn("-B", commands[2][0])
            self.assertEqual(commands[1][1], work / "out-debug")
            self.assertEqual(commands[3][1], work / "out-debug")

    def test_parallel_profiles_keep_cold_then_reuse_and_cross_profile_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(work=Path(directory), profiles="debug,release", defines="", cases=1,
                                   layers="all", timeout=10, program_timeout=10, profile_jobs=2,
                                   separate_units=False, second_program=False, shuffle_order=False,
                                   ppu_reuse=True, dcc=None, determinism=True, checkpoint_key="product")
            barrier = threading.Barrier(2)
            cold = set()
            mirrored = set()
            seen_work = []
            def build(work, profile, defines, timeout, program_timeout, reuse=False):
                seen_work.append(work)
                if reuse:
                    self.assertIn(profile, cold)
                    if profile == "release":
                        self.assertIn(profile, mirrored)
                else:
                    barrier.wait(timeout=3)
                    cold.add(profile)
                result = gate.Build(profile + ("+reuse" if reuse else ""))
                result.compiled = True
                return result
            def mirror(work, profile, defines, timeout, *, input_key):
                self.assertEqual(input_key, args.checkpoint_key)
                self.assertIn(profile, cold)
                mirrored.add(profile)
                return []
            with patch.object(gate, "run", return_value=(0, "")), patch.object(gate, "build_fpc", side_effect=build), \
                    patch.object(gate, "build_twice", side_effect=mirror), \
                    patch.object(gate, "compare", return_value=[]) as compare, \
                    patch.object(gate, "load_known", return_value=[]), redirect_stdout(io.StringIO()):
                result = gate.run_seed(args, 17)
            self.assertEqual(result["findings"], [])
            self.assertEqual(len(compare.call_args[0][0]), 4)
            self.assertEqual(set(seen_work), {Path(directory) / "seed-17"})

    def test_successful_seed_survives_retry_but_new_inputs_repeat_it(self):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(work=Path(directory), resume=True, checkpoint_key="first")
            row = {"seed": 1, "findings": [], "known_hits": [], "evidence": {}}
            with patch.object(gate, "run_seed", return_value=row) as run:
                gate.cached_seed(args, 1)
                gate.cached_seed(args, 1)
                self.assertEqual(run.call_count, 1)
                args.checkpoint_key = "changed"
                gate.cached_seed(args, 1)
                self.assertEqual(run.call_count, 2)

    def test_determinism_collects_product_inputs_even_without_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            command = ["run_devil_gate.py", "--work", directory, "--seeds", "1", "--determinism"]
            def seed(args, value):
                self.assertFalse(args.resume)
                self.assertEqual(args.checkpoint_key, "product")
                return {"seed": value, "findings": [], "known_hits": []}
            with patch.object(sys, "argv", command), patch.object(gate.tc, "preflight"), \
                    patch.object(gate, "checkpoint_key", return_value="product") as identity, \
                    patch.object(gate, "cached_seed", side_effect=seed), redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    gate.main()
            self.assertEqual(result.exception.code, 0)
            identity.assert_called_once()

    def test_stage_resume_preserves_success_and_repeats_failed_or_damaged_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = SimpleNamespace(jobs=2, timeout=10, main_timeout=10, resume=True, keep_going=True)
            calls = []
            def run(command, timeout, name):
                calls.append(name)
                return (1 if name == "reject" else 0), "test result", 0.1
            stages = [("codegen", ["fake", "codegen"]), ("reject", ["fake", "reject"])]
            with patch.object(all_gates, "checkpoint_key", return_value="identity"), \
                    patch.object(all_gates, "run", side_effect=run), redirect_stdout(io.StringIO()):
                all_gates.run_stages(stages, args, root)
                all_gates.run_stages(stages, args, root)
                self.assertEqual(calls.count("codegen"), 1)
                self.assertEqual(calls.count("reject"), 2)
                (root / "codegen.log").write_text("damaged")
                all_gates.run_stages(stages, args, root)
                self.assertEqual(calls.count("codegen"), 2)


if __name__ == "__main__":
    unittest.main()
