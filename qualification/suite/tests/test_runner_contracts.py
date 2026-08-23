import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import runner


class RunnerContractsTest(unittest.TestCase):
    def test_current_compiler_paths_follow_the_host_platform(self) -> None:
        compiler = {
            "driver": "linux/bin/fpc",
            "config": "linux/etc/fpc.cfg",
            "driver_win64": "win64/fpc.exe",
            "config_win64": "win64/fpc.cfg",
        }
        with mock.patch.object(
            runner, "compiler_platform_name", return_value="win64",
        ):
            self.assertEqual(
                runner.compiler_path(compiler, "driver"),
                runner.ROOT / "win64/fpc.exe",
            )
            self.assertEqual(
                runner.compiler_path(compiler, "config"),
                runner.ROOT / "win64/fpc.cfg",
            )
        with mock.patch.object(
            runner, "compiler_platform_name", return_value="linux",
        ):
            self.assertEqual(
                runner.compiler_path(compiler, "driver"),
                runner.ROOT / "linux/bin/fpc",
            )
            self.assertEqual(
                runner.compiler_path(compiler, "config"),
                runner.ROOT / "linux/etc/fpc.cfg",
            )

    def test_executable_path_uses_the_host_suffix(self) -> None:
        source = Path("fixture.pas")
        with mock.patch.object(runner, "executable_suffix", return_value=".exe"):
            self.assertEqual(
                runner.executable_path(Path("build"), source),
                Path("build/fixture.exe"),
            )
        with mock.patch.object(runner, "executable_suffix", return_value=""):
            self.assertEqual(
                runner.executable_path(Path("build"), source),
                Path("build/fixture"),
            )

    def test_fixture_expectations_are_platform_specific(self) -> None:
        manifest = {
            "compilers": {
                "current": {
                    "fixture_exact_expectation_alias_win64": "current-win64",
                },
            },
        }
        with mock.patch.object(
            runner, "compiler_platform_name", return_value="win64",
        ):
            self.assertEqual(
                runner.fixture_exact_expectation_compiler(manifest, "current"),
                "current-win64",
            )
        with mock.patch.object(
            runner, "compiler_platform_name", return_value="linux",
        ):
            self.assertEqual(
                runner.fixture_exact_expectation_compiler(manifest, "current"),
                "current",
            )
        self.assertEqual(
            runner.fixture_exact_expectation_compilers(manifest, "current"),
            {"current", "current-win64"},
        )

    def test_automatic_run_directories_do_not_collide(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first_id, first = runner.create_run_directory(root, "fixtures", None)
            second_id, second = runner.create_run_directory(root, "mega", None)
            self.assertNotEqual(first_id, second_id)
            self.assertNotEqual(first, second)
            self.assertTrue(first.is_dir())
            self.assertTrue(second.is_dir())
            self.assertIn("-fixtures-", first_id)
            self.assertIn("-mega-", second_id)

            runner.create_run_directory(root, "fixtures", "named-run")
            with self.assertRaises(FileExistsError):
                runner.create_run_directory(root, "fixtures", "named-run")

    def test_versioned_mormot_source_must_be_clean_exact_commit(self) -> None:
        completed = SimpleNamespace(stdout="expected\n")
        clean = SimpleNamespace(stdout="")
        with mock.patch.object(
            runner.subprocess, "run", side_effect=(completed, clean),
        ):
            runner.require_clean_git_source(Path("source"), "expected")

        dirty = SimpleNamespace(stdout=" M src/unit.pas\n")
        with mock.patch.object(
            runner.subprocess, "run", side_effect=(completed, dirty),
        ), self.assertRaisesRegex(RuntimeError, "not clean commit"):
            runner.require_clean_git_source(Path("source"), "expected")

        wrong = SimpleNamespace(stdout="wrong\n")
        with mock.patch.object(
            runner.subprocess, "run", side_effect=(wrong, clean),
        ), self.assertRaisesRegex(RuntimeError, "not clean commit"):
            runner.require_clean_git_source(Path("source"), "expected")

    def test_mormot_source_patch_changes_only_the_staged_copy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            staged = root / "staged"
            unit = source / "src/core/unit.pas"
            unit.parent.mkdir(parents=True)
            unit.write_bytes(b"before\r\n")
            staged.mkdir()
            patch = root / "source.patch"
            patch.write_text(
                "diff --git a/src/core/unit.pas b/src/core/unit.pas\n"
                "--- a/src/core/unit.pas\n"
                "+++ b/src/core/unit.pas\n"
                "@@ -1 +1 @@\n"
                "-before\n"
                "+after\n",
                encoding="utf-8",
            )

            runner.stage_mormot_source_tree(source, staged, patch)

            self.assertEqual(unit.read_text(encoding="utf-8"), "before\n")
            self.assertEqual(
                (staged / "src/core/unit.pas").read_text(encoding="utf-8"),
                "after\n",
            )

    def test_upstream_options_require_the_same_current_test_set(self) -> None:
        reference = {
            "unique_tests": 2,
            "phase_records": 3,
            "test_ids_sha256": "abc",
        }
        current = dict(reference, phase_records=4)
        runner.require_same_upstream_test_set(reference, current, "compiler")
        current["unique_tests"] = 1
        with self.assertRaises(RuntimeError):
            runner.require_same_upstream_test_set(reference, current, "compiler")
        current = dict(reference, test_ids_sha256="def")
        with self.assertRaises(RuntimeError):
            runner.require_same_upstream_test_set(reference, current, "compiler")

    def test_upstream_policy_failure_requires_exact_detail(self) -> None:
        detail = {
            "failure_class": "missing_unit",
            "exit_code": 1,
            "first_diagnostic": "missing package unit",
        }
        expected = {"observed_result": "compile_fail", **detail}
        self.assertTrue(runner.exact_upstream_failure(
            detail, "compile_fail", expected,
        ))
        changes = (
            {"failure_class": "compiler_error"},
            {"exit_code": 2},
            {"first_diagnostic": "new compiler failure"},
        )
        for change in changes:
            with self.subTest(change=change):
                self.assertFalse(runner.exact_upstream_failure(
                    dict(detail, **change), "compile_fail", expected,
                ))

    def test_upstream_target_directives_are_excluded_exactly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "target.pp"
            source.write_text("{ %TARGET=win64 }\n{$mode delphi}\n", encoding="utf-8")
            self.assertEqual(
                runner.upstream_target_exclusion(source, "linux"),
                "upstream target directive excludes linux",
            )

            source.write_text(
                "{ %TARGET=linux,win64 }\n{$mode delphi}\n", encoding="utf-8",
            )
            self.assertIsNone(runner.upstream_target_exclusion(source, "linux"))

            source.write_text(
                "{ %SKIPTARGET=linux }\n{$mode delphi}\n", encoding="utf-8",
            )
            self.assertEqual(
                runner.upstream_target_exclusion(source, "linux"),
                "upstream skip-target directive excludes linux",
            )

    def test_resolved_upstream_known_deviation_fails_closed(self) -> None:
        known = {
            "observed_result": "compile_fail",
            "failure_class": "compiler_error",
        }
        upstream = {"known_deviations": {"O3": {"test.pp": known}}}
        expected, is_known = runner.upstream_expected_record(
            upstream, {}, "O3", "test.pp", "pass",
        )
        self.assertIs(expected, known)
        self.assertTrue(is_known)

        expected, is_known = runner.upstream_expected_record(
            upstream, {}, "O2", "test.pp", "pass",
        )
        self.assertEqual(expected, "pass")
        self.assertFalse(is_known)

    def test_mormot_accepts_only_proven_environment_exit(self) -> None:
        self.assertEqual(runner.mormot_suite_result(0, 0, 0, 0), "pass")
        self.assertEqual(runner.mormot_suite_result(1, 1, 1, 0), "pass")
        self.assertEqual(runner.mormot_suite_result(1, 0, 0, 0), "run_fail")
        self.assertEqual(runner.mormot_suite_result(217, 0, 0, 0), "run_fail")
        self.assertEqual(runner.mormot_suite_result(217, 1, 1, 0), "run_fail")
        self.assertEqual(runner.mormot_suite_result(0, 1, 0, 1), "run_fail")
        self.assertEqual(runner.mormot_suite_result(1, 2, 1, 1), "run_fail")

    def test_mormot_product_prefix_requires_mm_then_cthreads(self) -> None:
        compiler = {"driver": "fpc", "config": "fpc.cfg"}
        with mock.patch.object(runner, "compiler_provenance", return_value="hash"):
            command = runner.mormot_compile_command(
                compiler,
                [],
                Path("source"),
                Path("static"),
                Path("work"),
                pinned_memory_manager=Path("mm.pas"),
            )
        self.assertIn(
            "--required-first-unit=mormot.core.fpcx64mm,cthreads",
            command,
        )

    def test_mormot_environment_methods_are_explicit(self) -> None:
        expected_methods = {
            "ip dns ldap",
            "dns and ldap",
            "rtsp over http",
            "rtsp over http buffered write",
        }
        self.assertEqual(runner.MORMOT_ENVIRONMENT_METHODS, expected_methods)

        def parse(method: str) -> dict[str, object]:
            with tempfile.TemporaryDirectory() as directory:
                report = Path(directory) / "report.txt"
                report.write_text(
                    f"! - {method}: 1 / 10 FAILED\n"
                    "Total assertions failed for all test suits: 1 / 10\n",
                    encoding="utf-8",
                )
                return runner.parse_mormot_report(report)

        for method in expected_methods:
            with self.subTest(method=method):
                result = parse(method)
                self.assertEqual(result["environment_failed"], 1)
                self.assertEqual(result["qualification_failed"], 0)
        result = parse("Ordinary compiler contract")
        self.assertEqual(result["environment_failed"], 0)
        self.assertEqual(result["qualification_failed"], 1)

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux socket contract")
    def test_mormot_suite_runtime_path_fits_unix_socket_limit(self) -> None:
        runtime, artifacts = runner.mormot_suite_work_dirs(
            SimpleNamespace(run_id="long-clean-clone-regression"), "mormot/O3",
        )
        try:
            self.assertLess(
                len(runner.os.fsencode(runtime / "mormot2tests.sock:")), 108,
            )
            self.assertEqual(artifacts.parent, runner.ROOT / ".m")
            self.assertNotEqual(runtime, artifacts)
        finally:
            runtime.rmdir()

    @unittest.skipUnless(sys.platform.startswith("linux"), "Linux socket contract")
    def test_mormot_suite_runtime_is_collected_after_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory) / "runtime"
            artifacts = Path(directory) / "artifacts"
            runtime.mkdir()

            def fail(*_args: object, **_kwargs: object) -> None:
                (runtime / "compile.log").write_text("proof\n", encoding="utf-8")
                raise RuntimeError("injected")

            with mock.patch.object(
                runner, "mormot_suite_work_dirs",
                return_value=(runtime, artifacts),
            ), mock.patch.object(
                runner, "_run_mormot_case_in_workspace", side_effect=fail,
            ), self.assertRaisesRegex(RuntimeError, "injected"):
                runner.run_mormot_case(
                    SimpleNamespace(), "source", {}, "compiler", {}, "O3", [],
                )

            self.assertFalse(runtime.exists())
            self.assertEqual(
                (artifacts / "compile.log").read_text(encoding="utf-8"),
                "proof\n",
            )


if __name__ == "__main__":
    unittest.main()
