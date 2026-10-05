"""Small end-to-end checks for failure collection, resume and final replay."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from qualification.release import qualify

# Runs one matrix command up to its argument parser and no further: accepted
# arguments end the process before the script does any work.
PARSE_ONLY = """
import argparse, os, runpy, sys
parse_args = argparse.ArgumentParser.parse_args
def accepted(self, *args, **kwargs):
    parse_args(self, *args, **kwargs)
    print("MATRIX_ARGUMENTS_ACCEPTED", flush=True)
    os._exit(0)
argparse.ArgumentParser.parse_args = accepted
del sys.argv[0]
if sys.argv[0] == "-m":
    del sys.argv[0]
    runpy.run_module(sys.argv[0], run_name="__main__", alter_sys=True)
else:
    sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[0])))
    runpy.run_path(sys.argv[0], run_name="__main__")
"""


class MatrixRunTests(unittest.TestCase):
    def test_old_ledger_cannot_acquire_new_pulse_cpu_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "source.txt").write_text("source\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "add", "source.txt"], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Test", "-c",
                            "user.email=test@example.invalid", "commit", "-qm", "input"], check=True)
            matrix = root / "matrix.json"
            matrix.write_text(json.dumps({"version": 1, "source_inputs": {"core": ["source.txt"]},
                                          "jobs": [{"id": "core", "mode": "light", "platforms": ["linux"],
                                                    "timeout": 10, "commands": {"linux": ["true"]}}]}), encoding="utf-8")
            run_dir = root / "run"
            run_dir.mkdir()
            (run_dir / "state.json").write_text(json.dumps({"platform": "linux", "results": {},
                                                             "final_results": {}, "skip_pulse": False}), encoding="utf-8")
            argv = ["qualify.py", "status", "--run-dir", str(run_dir), "--matrix", str(matrix),
                    "--platform", "linux", "--mode", "light", "--pulse-single-cpus", "12,14"]
            with patch.object(qualify, "ROOT", root), patch.object(sys, "argv", argv):
                with self.assertRaises(SystemExit):
                    qualify.main()

    def test_single_cpu_selection_changes_only_the_pulse_job_fingerprint(self):
        ordinary = qualify.load_matrix(qualify.MATRIX, "win64", "full")
        pinned = qualify.load_matrix(qualify.MATRIX, "win64", "full", pulse_single_cpus="12,14")
        ordinary_by_id = {job["id"]: qualify.fingerprint(job, "win64") for job in ordinary}
        pinned_by_id = {job["id"]: qualify.fingerprint(job, "win64") for job in pinned}
        self.assertEqual({name for name in ordinary_by_id if ordinary_by_id[name] != pinned_by_id[name]},
                         {"pulse_report"})

    def test_without_pulse_final_checks_correctness_and_cannot_reuse_full_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "source.txt").write_text("source\n")
            subprocess.run(["git", "-C", str(root), "add", "source.txt"], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                            "commit", "-qm", "input"], check=True)
            matrix = root / "matrix.json"
            matrix.write_text(json.dumps({"version": 1,
                "source_inputs": {name: ["source.txt"] for name in ("core", "pulse_report")},
                "jobs": [{"id": name, "mode": mode, "platforms": ["linux"], "timeout": 10,
                          "commands": {"linux": ["{python}", "-c", f"raise SystemExit({code})"]}}
                         for name, mode, code in (("core", "light", 0), ("pulse_report", "full", 7))]}))
            argv = ["qualify.py", "run", "--run-dir", str(root / "run"), "--matrix", str(matrix),
                    "--platform", "linux", "--mode", "full", "--skip-pulse"]
            with patch.object(qualify, "ROOT", root), patch.object(sys, "argv", argv):
                self.assertEqual(qualify.main(), 0)
                state = json.loads((root / "run/state.json").read_text())
                self.assertTrue(state["skip_pulse"])
                self.assertNotIn("pulse_report", state["results"])
                argv[argv.index("full")] = "light"
                argv.append("--final")
                self.assertEqual(qualify.main(), 0)
                argv.remove("--skip-pulse")
                with self.assertRaises(SystemExit):
                    qualify.main()

    def test_final_verifies_the_qualified_product_without_rebuilding(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "source.txt").write_text("source\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "add", "source.txt"], check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Test",
                            "-c", "user.email=test@example.invalid", "commit", "-qm", "input"], check=True)
            build = (
                "from pathlib import Path; import time; "
                "Path('toolchain').mkdir(exist_ok=True); "
                "Path('runtime/mm').mkdir(parents=True, exist_ok=True); "
                "Path('runtime/mm/manager.pas').write_text('MM'); "
                "Path('toolchain/profile.txt').write_text('rtl_packages_opt=-O3\\n'"
                "+'built_utc='+str(time.time_ns())+'\\n')"
            )
            matrix = root / "matrix.json"
            matrix.write_text(json.dumps({"version": 1, "source_inputs": {
                "build": ["source.txt"], "consumer": ["source.txt"]}, "jobs": [
                {"id": "build", "mode": "light", "platforms": ["linux"], "timeout": 30,
                 "commands": {"linux": ["{python}", "-c", build]}},
                {"id": "consumer", "mode": "light", "platforms": ["linux"], "needs": ["build"],
                 "timeout": 30, "commands": {"linux": ["{python}", "-c", "print('PASS')"]}},
            ]}), encoding="utf-8")
            argv = ["qualify.py", "run", "--run-dir", str(root / "run"), "--matrix", str(matrix),
                    "--platform", "linux", "--mode", "light", "--jobs", "1"]
            with patch.object(qualify, "ROOT", root), patch.object(sys, "argv", argv):
                self.assertEqual(qualify.main(), 0)
                first = (root / "toolchain/profile.txt").read_bytes()
                argv.append("--final")
                self.assertEqual(qualify.main(), 0)
                self.assertEqual(first, (root / "toolchain/profile.txt").read_bytes())
                state = json.loads((root / "run/state.json").read_text())
                log = Path(state["final_results"]["build"]["log"]).read_text()
                self.assertIn("VERIFY_QUALIFIED_PRODUCT", log)
                self.assertIn(state["results"]["build"]["log_identity"], log)
                (root / "toolchain/profile.txt").write_text("rtl_packages_opt=-O2\n", encoding="utf-8")
                with self.assertRaises(SystemExit):
                    qualify.main()

    def test_collect_resume_and_final(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / "source.txt").write_text("source\n", encoding="utf-8")
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Test",
                            "-c", "user.email=test@example.invalid", "add", "source.txt"],
                           check=True)
            subprocess.run(["git", "-C", str(root), "-c", "user.name=Test",
                            "-c", "user.email=test@example.invalid", "commit", "-qm", "input"],
                           check=True)
            matrix = root / "matrix.json"
            count = root / "count.txt"
            audit = root / "audit.txt"
            def job(name: str, script: str, needs: list[str] | None = None) -> dict:
                return {"id": name, "mode": "light", "platforms": ["linux"],
                        "needs": needs or [], "resource": name, "timeout": 30,
                        "commands": {"linux": ["{python}", "-c", script]}}
            history = job("history", f"from pathlib import Path; Path({str(audit)!r}).write_text('checked')", ["green"])
            history["final_only"] = True
            matrix.write_text(json.dumps({"version": 1, "source_inputs": {
                name: ["source.txt"] for name in ("green", "red", "child", "history")}, "jobs": [
                job("green", f"from pathlib import Path; p=Path({str(count)!r}); "
                    "p.write_text(p.read_text()+'x' if p.exists() else 'x')"),
                job("red", "from pathlib import Path; "
                    "raise SystemExit(0 if Path('allow').exists() else 1)"),
                job("child", "print('CHILD_PASS')", ["red"]),
                history,
            ]}), encoding="utf-8")
            run_dir = root / "run"
            argv = ["qualify.py", "run", "--run-dir", str(run_dir),
                    "--matrix", str(matrix), "--platform", "linux", "--mode", "light",
                    "--jobs", "2"]
            with patch.object(qualify, "ROOT", root), patch.object(sys, "argv", argv):
                self.assertEqual(qualify.main(), 1)
                state = json.loads((run_dir / "state.json").read_text())
                self.assertEqual(state["results"]["green"]["status"], "pass")
                self.assertEqual(state["results"]["red"]["status"], "fail")
                self.assertEqual(state["results"]["child"]["status"], "blocked")
                (root / "allow").write_text("yes", encoding="utf-8")
                subprocess.run(["git", "-C", str(root), "add", "allow"], check=True)
                subprocess.run(["git", "-C", str(root), "-c", "user.name=Test",
                                "-c", "user.email=test@example.invalid", "commit", "-qm", "fix"],
                               check=True)
                self.assertEqual(qualify.main(), 0)
                self.assertEqual(count.read_text(), "x")
                state = json.loads((run_dir / "state.json").read_text())
                self.assertNotEqual(state["results"]["green"]["head"],
                                    qualify.git("rev-parse", "HEAD"))
                (root / "source.txt").write_text("changed\n", encoding="utf-8")
                subprocess.run(["git", "-C", str(root), "add", "source.txt"], check=True)
                subprocess.run(["git", "-C", str(root), "-c", "user.name=Test",
                                "-c", "user.email=test@example.invalid", "commit", "-qm", "new source"],
                               check=True)
                argv.append("--final")
                with self.assertRaises(SystemExit):
                    qualify.main()
                argv.remove("--final")
                self.assertEqual(qualify.main(), 0)
                self.assertEqual(count.read_text(), "xx")
                argv.append("--final")
                self.assertEqual(qualify.main(), 0)
                self.assertEqual(count.read_text(), "xxx")
                self.assertEqual(audit.read_text(), "checked")


class SchedulingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        self.run_dir = self.base / "run"
        self.matrix = self.base / "matrix.json"
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        (self.root / "source.txt").write_text("one")
        (self.root / "test.txt").write_text("test")
        for folder in (self.root, self.base / "baseline"):
            (folder / "toolchain").mkdir(parents=True)
            (folder / "toolchain/compiler").write_text("binary")
            (folder / "runtime/mm").mkdir(parents=True)
            (folder / "runtime/mm/mm.pas").write_text("mm")
        (self.base / "baseline/toolchain/runtime/mm").mkdir(parents=True)
        (self.base / "baseline/toolchain/runtime/mm/mormot.core.fpcx64mm.pas").write_text("mm")
        self.commit()

    def commit(self):
        subprocess.run(["git", "-C", str(self.root), "add", "source.txt", "test.txt"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Test", "-c",
                        "user.email=test@example.invalid", "commit", "-qm", "input"], check=True)

    def job(self, name, mode="light", *, code="", needs=(), **extra):
        counter = self.base / f"{name}.count"
        script = (f"from pathlib import Path; p=Path({str(counter)!r}); "
                  "p.write_text(p.read_text()+'x' if p.exists() else 'x'); " + (code or "print('OK')"))
        return {"id": name, "mode": mode, "platforms": ["linux"], "needs": list(needs),
                "timeout": 10, "commands": {"linux": ["{python}", "-c", script]}, **extra}

    def run_jobs(self, jobs, *, final=False, workers=4, memory=8192):
        self.matrix.write_text(json.dumps({"version": 1, "source_inputs": {
            job["id"]: ["source.txt" if job["id"] == "build" else "test.txt"] for job in jobs}, "jobs": jobs}))
        argv = ["qualify.py", "run", "--run-dir", str(self.run_dir), "--matrix", str(self.matrix),
                "--platform", "linux", "--mode", "light" if final else "full", "--jobs", str(workers),
                "--memory-mb", str(memory), "--baseline-toolchain", str(self.base / "baseline/toolchain")]
        if final:
            argv.append("--final")
        with patch.object(qualify, "ROOT", self.root), patch.object(sys, "argv", argv):
            return qualify.main()

    def test_fast_failure_collects_peers_but_never_starts_medium_or_full(self):
        jobs = [self.job("z_red", code="raise SystemExit(1)"), self.job("z_green"),
                self.job("a_medium", "medium"), self.job("a_full", "full")]
        self.assertEqual(self.run_jobs(jobs), 1)
        self.assertTrue((self.base / "z_green.count").exists())
        self.assertFalse((self.base / "a_medium.count").exists())
        self.assertFalse((self.base / "a_full.count").exists())

    def test_medium_failure_never_starts_heavy_even_without_explicit_dependency(self):
        jobs = [self.job("fast"), self.job("middle", "medium", code="raise SystemExit(1)"),
                self.job("a_heavy", "full")]
        self.assertEqual(self.run_jobs(jobs), 1)
        self.assertFalse((self.base / "a_heavy.count").exists())

    def test_rebuilt_identical_product_keeps_expensive_pass_then_changed_test_invalidates_it(self):
        jobs = [self.job("build"), self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        (self.root / "source.txt").write_text("comment changed")
        self.commit()
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual((self.base / "build.count").read_text(), "xx")
        self.assertEqual((self.base / "heavy.count").read_text(), "x")
        (self.root / "test.txt").write_text("new test")
        self.commit()
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual((self.base / "heavy.count").read_text(), "xx")

    def test_replaced_installed_product_cannot_reuse_old_pass(self):
        jobs = [self.job("build"), self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        (self.root / "toolchain/compiler").write_text("another binary")
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual((self.base / "build.count").read_text(), "xx")
        self.assertEqual((self.base / "heavy.count").read_text(), "xx")

    def test_interrupted_attempt_is_preserved_and_does_not_block_resume(self):
        attempt = self.run_dir / "discovery/jobs/check/attempt-0001"
        attempt.mkdir(parents=True)
        (attempt / "partial.log").write_text("evidence")
        self.assertEqual(self.run_jobs([self.job("check")]), 0)
        self.assertEqual((attempt / "partial.log").read_text(), "evidence")
        self.assertTrue((attempt.parent / "attempt-0002").is_dir())

    def test_nested_worker_slots_and_memory_are_reserved(self):
        lock = self.base / "busy"
        # Two jobs would collide if the controller counted each pool as one slot.
        script = (f"import time; p=Path({str(lock)!r}); p.mkdir(); time.sleep(0.15); p.rmdir()")
        jobs = [self.job(name, code=script, slots=2, memory_mb_per_slot=512) for name in ("a", "b")]
        self.assertEqual(self.run_jobs(jobs, workers=2), 0)
        self.run_dir = self.base / "memory-run"
        self.assertEqual(self.run_jobs(jobs, workers=4, memory=1024), 0)

    def test_final_never_replaces_the_qualified_artifact_with_a_new_build(self):
        jobs = [self.job("build", code="Path('toolchain/compiler').write_text('after' if p.read_text() == 'xx' else 'before')"),
                self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual(self.run_jobs(jobs, final=True), 0)
        self.assertEqual((self.base / "build.count").read_text(), "x")
        self.assertEqual((self.root / "toolchain/compiler").read_text(), "before")

    def test_final_rejects_a_product_mutated_by_a_replayed_check(self):
        jobs = [self.job("build"), self.job("consumer", needs=["build"], code=
                "Path('toolchain/compiler').write_text('changed') if p.read_text() == 'xx' else None"),
                self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual(self.run_jobs(jobs, final=True), 2)
        self.assertEqual((self.base / "build.count").read_text(), "x")

    def test_final_allows_only_the_profile_build_time_to_change(self):
        profile = self.root / "toolchain/profile.txt"
        jobs = [self.job("build", code=
                        "Path('toolchain/profile.txt').write_text("
                        "'rtl_packages_opt=OPT=-O3\\ncompiler_sha256=unchanged\\nbuilt_utc='"
                        "+ p.read_text() + '\\n')"),
                self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        original = profile.read_bytes()
        profile.write_bytes(original.replace(b"built_utc=x", b"built_utc=later"))
        self.assertEqual(self.run_jobs(jobs, final=True), 0)
        self.assertNotEqual(profile.read_bytes(), original)
        self.assertIn(b"built_utc=later", profile.read_bytes())
        self.assertEqual((self.base / "build.count").read_text(), "x")
        self.assertEqual((self.base / "heavy.count").read_text(), "x")

    def test_final_preserves_build_provenance_after_an_unrelated_commit(self):
        jobs = [self.job("build"), self.job("consumer", needs=["build"]),
                self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        original = json.loads((self.run_dir / "state.json").read_text())["results"]["build"]
        (self.root / "notes.txt").write_text("documentation only")
        subprocess.run(["git", "-C", str(self.root), "add", "notes.txt"], check=True)
        self.commit()
        self.assertEqual(self.run_jobs(jobs, final=True), 0)
        state = json.loads((self.run_dir / "state.json").read_text())
        final = state["final_results"]["build"]
        self.assertNotEqual(final["head"], original["head"])
        self.assertEqual(state["results"]["build"], original)
        self.assertIn(original["head"], Path(final["log"]).read_text())
        self.assertEqual((self.base / "build.count").read_text(), "x")
        self.assertEqual((self.base / "consumer.count").read_text(), "xx")

    def test_changed_profile_flags_invalidate_the_expensive_pass(self):
        profile = self.root / "toolchain/profile.txt"
        profile.write_text("rtl_packages_opt=OPT=-O3\nbuilt_utc=first\n")
        jobs = [self.job("build"), self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        profile.write_text("rtl_packages_opt=OPT=-O2\nbuilt_utc=second\n")
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual((self.base / "heavy.count").read_text(), "xx")

    def test_source_drift_blocks_next_stage_and_invalidates_this_attempt(self):
        jobs = [self.job("edit", code="Path('source.txt').write_text('changed during run')"),
                self.job("heavy", "full")]
        self.assertEqual(self.run_jobs(jobs), 2)
        self.assertFalse((self.base / "heavy.count").exists())
        state = json.loads((self.run_dir / "state.json").read_text())
        self.assertEqual(state["results"]["edit"]["status"], "fail")

    def test_baseline_replacement_cannot_reuse_a_ledger(self):
        jobs = [self.job("check")]
        self.assertEqual(self.run_jobs(jobs), 0)
        (self.base / "baseline/toolchain/compiler").write_text("replaced")
        with self.assertRaises(SystemExit):
            self.run_jobs(jobs)
        self.assertEqual((self.base / "check.count").read_text(), "x")

    def test_cached_dependencies_are_reused_regardless_of_name_order(self):
        jobs = [self.job("z_parent"), self.job("a_child", needs=["z_parent"]),
                self.job("heavy", "full", needs=["a_child"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual(self.run_jobs(jobs), 0)
        for job in jobs:
            self.assertEqual((self.base / (job["id"] + ".count")).read_text(), "x")

    def test_damaged_or_missing_evidence_blocks_final_and_only_repeats_its_job(self):
        jobs = [self.job("check"), self.job("heavy", "full")]
        for damage in ("changed", "missing", "legacy"):
            with self.subTest(damage=damage):
                self.run_dir = self.base / damage
                self.assertEqual(self.run_jobs(jobs), 0)
                before_check = (self.base / "check.count").read_text()
                before_heavy = (self.base / "heavy.count").read_text()
                state_path = self.run_dir / "state.json"
                state = json.loads(state_path.read_text())
                evidence = Path(state["results"]["heavy"]["log"])
                if damage == "changed":
                    evidence.write_text("OK: replaced log")
                elif damage == "missing":
                    evidence.unlink()
                else:
                    state["results"]["heavy"].pop("log_identity", None)
                    state_path.write_text(json.dumps(state))
                with self.assertRaises(SystemExit):
                    self.run_jobs(jobs, final=True)
                self.assertEqual(self.run_jobs(jobs), 0)
                self.assertEqual((self.base / "check.count").read_text(), before_check)
                self.assertEqual((self.base / "heavy.count").read_text(), before_heavy + "x")
                self.assertEqual(self.run_jobs(jobs, final=True), 0)

    def test_final_light_rechecks_full_evidence_after_replay(self):
        logs = self.run_dir / "discovery/logs"
        jobs = [self.job("check", code=f"[log.unlink() for log in Path({str(logs)!r}).glob('heavy-*.log')]"),
                self.job("heavy", "full")]
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual(self.run_jobs(jobs, final=True), 2)

    def test_empty_install_after_interrupted_build_can_be_rebuilt(self):
        (self.root / "toolchain/compiler").unlink()
        jobs = [self.job("build", code="Path('toolchain/compiler').write_text('rebuilt')"),
                self.job("heavy", "full", needs=["build"])]
        self.assertEqual(self.run_jobs(jobs), 0)
        self.assertEqual((self.root / "toolchain/compiler").read_text(), "rebuilt")

    def test_external_prerequisite_is_checked_again_on_resume_and_final(self):
        prerequisite = self.base / "external-input"
        prerequisite.write_text("valid")
        job = self.job("check", always_run=True,
                       code=f"raise SystemExit(Path({str(prerequisite)!r}).read_text() != 'valid')")
        self.assertEqual(self.run_jobs([job]), 0)
        prerequisite.write_text("invalid")
        self.assertEqual(self.run_jobs([job]), 1)
        self.assertEqual((self.base / "check.count").read_text(), "xx")
        prerequisite.write_text("valid")
        self.assertEqual(self.run_jobs([job]), 0)
        prerequisite.write_text("invalid")
        self.assertEqual(self.run_jobs([job], final=True), 1)
        self.assertEqual((self.base / "check.count").read_text(), "xxxx")


class MatrixCommandTests(unittest.TestCase):
    def test_skip_pulse_keeps_every_other_full_job(self):
        for platform in ("win64", "linux"):
            complete = {j["id"] for j in qualify.load_matrix(qualify.MATRIX, platform, "full")}
            correctness = {j["id"] for j in qualify.load_matrix(qualify.MATRIX, platform, "full", skip_pulse=True)}
            self.assertEqual(complete - correctness, {"pulse_report"})
            self.assertTrue({"devil_full", "archive_smoke", "lazarus"} <= correctness)
            if platform == "win64":
                self.assertIn("zlib_delphi", correctness)

    def values(self, base: Path, platform: str, name: str) -> dict[str, str]:
        job_dir = base / "run/discovery/jobs" / name / "attempt-0001"
        values = qualify.context(qualify.ROOT, base / "run", platform, "0" * 40, job_dir, str(base))
        values.update(job_slots="1", baseline_mm=str(base), checkpoint_dir=str(base))
        return values

    def test_optimizer_and_format_gates_are_in_medium_and_platform_ci(self):
        common = {"effect_model", "effect_identity", "licm", "licm_ppu", "exact_licm", "setcc_compare", "setcc_ir", "machine_facts",
                  "seh_regvar", "address_gvn", "managed_load_cse", "loop_base", "optimizer_ppu", "zeroext", "tail_forwarding",
                  "value_forward_ir", "value_relations", "value_relations_ir"}
        workflow = (qualify.ROOT / ".github/workflows/qualification.yml").read_text(encoding="utf-8")
        for platform, target, extra in (("linux", "linux-x86-64", {"linux_large_elf"}),
                                         ("win64", "win64-x86-64", {"win_bigobj", "win_stack"})):
            jobs = {job["id"]: job for job in qualify.load_matrix(qualify.MATRIX, platform, "medium")}
            body = workflow.split(f"\n  {target}:\n", 1)[1].split("\n  win64-x86-64:\n", 1)[0]
            body = body.replace("\\", "/")
            for name in common | extra:
                with self.subTest(platform=platform, name=name):
                    job = jobs[name]
                    self.assertEqual(job["mode"], "light" if name == "optimizer_ppu" else "medium")
                    self.assertIn("build", job["needs"])
                    self.assertTrue(job["expected"])
                    script = next(arg.removeprefix("{root}/") for arg in job["commands"][platform]
                                  if arg.startswith("{root}/"))
                    self.assertIn(script, body)

    def test_legacy_ppu_external_prerequisite_is_replayed_in_final_light(self):
        for platform in ("win64", "linux"):
            for final in (False, True):
                with self.subTest(platform=platform, final=final):
                    jobs = qualify.load_matrix(qualify.MATRIX, platform, "light", final=final)
                    job = next(job for job in jobs if job["id"] == "optimizer_ppu")
                    self.assertTrue(job["always_run"])
                    self.assertEqual(job["needs"], ["build"])

    def test_source_ir_signatures_follow_compiler_sources_even_with_an_unchanged_install(self):
        names = {"setcc_ir", "value_forward_ir", "value_relations_ir"}
        for platform in ("win64", "linux"):
            jobs = qualify.load_matrix(qualify.MATRIX, platform, "medium")
            light = {job["id"] for job in qualify.load_matrix(qualify.MATRIX, platform, "light")}
            self.assertTrue(names.isdisjoint(light))
            selected = [job for job in jobs if job["id"] in names | {"build", "sync"}]
            def tree_id(command, value):
                self.assertEqual(command, "rev-parse")
                head, path = value.split(":", 1)
                return head if path == "compiler" else path
            with patch.object(qualify, "git", side_effect=tree_id):
                before = qualify.input_signatures(selected, platform, "before", product="same-install")
                after = qualify.input_signatures(selected, platform, "after", product="same-install")
            for name in names:
                with self.subTest(platform=platform, name=name):
                    self.assertNotEqual(before[name], after[name])

    def test_legacy_ppu_compiler_uses_the_bootstrap_install_or_explicit_override(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, LOCALAPPDATA=directory):
            os.environ.pop("MOONBOT_BOOTSTRAP_FPC", None)
            win = self.values(Path(directory), "win64", "optimizer_ppu")
            self.assertEqual(Path(win["legacy_fpc"]),
                             Path(directory) / "MoonCompiler/bootstrap/3.2.2/bin/i386-win32/fpc.exe")
            self.assertEqual(self.values(Path(directory), "linux", "optimizer_ppu")["legacy_fpc"], "/usr/bin/fpc")
            os.environ["MOONBOT_BOOTSTRAP_FPC"] = str(Path(directory) / "explicit-bootstrap")
            for platform in ("win64", "linux"):
                self.assertEqual(self.values(Path(directory), platform, "optimizer_ppu")["legacy_fpc"],
                                 os.environ["MOONBOT_BOOTSTRAP_FPC"])

    def test_rtl_profile_gate_takes_only_gnu_make_and_names_a_missing_one(self):
        """The matrix runs the RTL profile gate without --make, and on Windows
        PATH can lead to Delphi's MAKE: it answers --version with its usage
        and exit code 0."""
        gate = runpy.run_path(str(qualify.ROOT / "qualification/build-driver/rtl_profile_gate.py"))
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ):
            base = Path(directory)
            for name in ("MOONBOT_MAKE", "MOONBOT_BOOTSTRAP_FPC"):
                os.environ.pop(name, None)
            os.environ.update(PATH=directory, LOCALAPPDATA=directory)
            make = base / ("make.cmd" if os.name == "nt" else "make")

            def answer(banner: str) -> None:
                make.write_text(f"@echo {banner}\n" if os.name == "nt" else f"#!/bin/sh\necho {banner}\n")
                make.chmod(0o755)

            answer("MAKE Version 5.43")
            with self.assertRaisesRegex(gate["GateError"], "GNU make was not found"):
                gate["find_make"](None)
            answer("GNU Make 4.4.1")
            self.assertEqual(gate["find_make"](None), make)
            os.environ["MOONBOT_MAKE"] = str(base / "absent")
            with self.assertRaisesRegex(gate["GateError"], "MOONBOT_MAKE names no file"):
                gate["find_make"](None)

    def test_pdata_tail_gate_refuses_a_file_that_is_not_pe32_plus(self):
        """RTL-test runs the gate on its Win64 executable. The ELF of a Linux
        build crashed its PE reader, and a 32-bit PE passed with no .pdata
        function read: both are refused by name."""
        gate = qualify.ROOT / "qualification/build-driver/pdata_tail_gate.py"
        stubs = {
            "elf": b"\x7fELF\x02\x01\x01" + bytes(57),
            "mz": b"MZ" + bytes(62),
            "pe32": b"MZ" + bytes(58) + (64).to_bytes(4, "little") + b"PE\0\0" + bytes(20) + b"\x0b\x01",
        }
        with tempfile.TemporaryDirectory() as directory:
            for name, head in stubs.items():
                stub = Path(directory) / name
                stub.write_bytes(head)
                result = subprocess.run([sys.executable, str(gate), str(stub)], capture_output=True,
                                        encoding="utf-8", errors="replace", timeout=120)
                self.assertEqual(result.returncode, 1, f"{name}: {result.stdout}{result.stderr}")
                self.assertIn("PE32+ only", result.stderr, name)
                self.assertNotIn("Traceback", result.stderr, name)

    def test_every_python_command_is_accepted_by_its_parser(self):
        """Valid JSON is not the contract: each script must accept what the matrix passes it."""
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runs, failures = [], []
            for job in json.loads(qualify.MATRIX.read_text(encoding="utf-8"))["jobs"]:
                for platform, command in job["commands"].items():
                    if command[0] != "{python}":
                        continue  # bash and PowerShell scripts take positional values, no parser
                    values = self.values(base, platform, job["id"])
                    argv = [qualify.expand(argument, values) for argument in command]
                    if argv[1] != "-m" and not re.search(r"\.parse_args\(|unittest\.main\(",
                                                         Path(argv[1]).read_text(encoding="utf-8")):
                        # nothing to parse, and running it would do its work
                        if argv[2:]:
                            failures.append(f"{job['id']} {platform}: arguments for a script without a parser")
                        continue
                    runs.append((f"{job['id']} {platform}", [argv[0], "-c", PARSE_ONLY, *argv[1:]],
                                 qualify.expand(job.get("cwd", "{root}"), values)))

            def parse(run: tuple[str, list[str], str]) -> str | None:
                name, argv, cwd = run
                result = subprocess.run(argv, cwd=cwd, capture_output=True,
                                        encoding="utf-8", errors="replace", timeout=120)
                if result.returncode == 0 and "MATRIX_ARGUMENTS_ACCEPTED" in result.stdout:
                    return None
                return f"{name}: {(result.stdout + result.stderr).strip()[-600:]}"

            with ThreadPoolExecutor(max_workers=8) as pool:
                failures += filter(None, pool.map(parse, runs))
            self.assertTrue(runs)
            self.assertEqual(failures, [])

    def test_every_gate_ci_runs_is_a_release_job(self):
        """CI and the matrix name the same gates in two lists kept by hand. The sentries of four
        compiler repairs lived in CI alone for a week, and a release does not run CI. Every script
        a CI job starts, a matrix job starts on the same platform."""
        workflow = (qualify.ROOT / ".github/workflows/qualification.yml").read_text(encoding="utf-8")
        jobs = json.loads(qualify.MATRIX.read_text(encoding="utf-8"))["jobs"]
        released = {platform: {argument.removeprefix("{root}/") for job in jobs
                               for argument in job["commands"].get(platform, [])
                               if argument.startswith("{root}/")}
                    for platform in ("linux", "win64")}
        missing, seen = [], 0
        for platform, job in (("linux", "linux-x86-64"), ("win64", "win64-x86-64")):
            body = workflow.split(f"\n  {job}:\n", 1)[1].split("\n  win64-x86-64:\n", 1)[0]
            for step in body.split("\n      - name: ")[1:]:
                folder = re.search(r"\n        working-directory: (\S+)", step)
                for script in re.findall(r"[\w./\\-]+\.(?:py|sh|ps1)\b", step):
                    script = script.replace("\\", "/").removeprefix("./")
                    if folder and not script.startswith(("qualification/", "RTL-test/")):
                        script = f"{folder.group(1)}/{script}"
                    if not script.startswith(("qualification/", "RTL-test/")):
                        continue  # the build driver and the bootstrap installer
                    seen += 1
                    if script not in released[platform]:
                        missing.append(f"{platform}: {script}")
        self.assertGreater(seen, 100)
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
