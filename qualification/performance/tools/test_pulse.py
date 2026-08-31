from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("pulse.py")
SPEC = importlib.util.spec_from_file_location("pulse", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
PULSE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = PULSE
SPEC.loader.exec_module(PULSE)


class PulseStatisticsTests(unittest.TestCase):
    def test_half_sample_mode_selects_dense_cluster(self) -> None:
        values = [10.0, 10.1, 10.2, 10.15, 10.05, 40.0, 80.0]
        self.assertAlmostEqual(PULSE.half_sample_mode(values), 10.075, places=3)

    def test_robust_stats_rejects_only_extreme_high_tail(self) -> None:
        stats = PULSE.robust_stats([10.0, 10.1, 10.2, 10.0, 10.1, 1000.0])
        self.assertEqual(stats.rejected, 1)
        self.assertEqual(stats.kept, 5)

    def test_robust_stats_keeps_dense_mode_with_large_high_tail(self) -> None:
        values = [10.0 + index * 0.001 for index in range(23)] + [25.0] * 14
        stats = PULSE.robust_stats(values)
        self.assertEqual(stats.kept, 23)
        self.assertEqual(stats.rejected, 14)
        self.assertLess(stats.mode, 10.1)

    def test_process_stats_rejects_one_slow_process(self) -> None:
        stats = PULSE.robust_stats(
            [10.0, 10.1, 10.0, 10.2, 10.1, 10.0, 18.0],
            process_level=True,
        )
        self.assertEqual(stats.kept, 6)
        self.assertEqual(stats.rejected, 1)
        self.assertLess(stats.maximum / stats.minimum, 1.03)

    def test_ratio_stats_rejects_high_and_low_outliers(self) -> None:
        stats = PULSE.robust_ratio_stats([0.5, 0.99, 1.0, 1.01, 1.02, 1.6, 2.0])
        self.assertEqual(stats.kept, 4)
        self.assertEqual(stats.rejected, 3)
        self.assertLessEqual(stats.maximum / stats.minimum, 1.25)

    def test_ratio_stats_requires_a_majority_cluster(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least half"):
            PULSE.robust_ratio_stats([0.5, 0.7, 1.0, 1.4, 2.0])

    def test_parse_fields_keeps_dash_values(self) -> None:
        fields = PULSE.parse_fields(
            "PULSE_CASE program=pulse_codegen case=for-runtime-0-255 layer=codegen"
        )
        self.assertEqual(fields["case"], "for-runtime-0-255")

    def test_primary_metric_uses_cycles_when_every_process_has_them(self) -> None:
        row = {"run_samples": [[{"cycles": 10.0}], [{"cycles": 11.0}]]}
        self.assertEqual(PULSE.select_primary_metric("abi", [row, row]), "cycles")

    def test_primary_metric_falls_back_to_tsc_when_cycles_are_unavailable(self) -> None:
        cycles = {"run_samples": [[{"cycles": 10.0}], [{"cycles": 11.0}]]}
        no_cycles = {"run_samples": [[{"cycles": 0.0}], [{"cycles": 0.0}]]}
        self.assertEqual(
            PULSE.select_primary_metric("abi", [cycles, no_cycles]), "tsc"
        )

    def test_move_and_threads_always_use_tsc(self) -> None:
        row = {"run_samples": [[{"cycles": 10.0}]]}
        self.assertEqual(PULSE.select_primary_metric("move", [row]), "tsc")
        self.assertEqual(PULSE.select_primary_metric("threads", [row]), "tsc")

    def test_linux_pulse_reserves_main_and_eight_worker_cpus(self) -> None:
        available = {1, 2, 3, 4, 5, 7, 8, 9, 12, 13}
        topology = {cpu: (0, cpu) for cpu in available}
        topology[13] = topology[1]  # SMT sibling: never reserve both threads.
        reservation = PULSE.select_pulse_physical_cpus(available, topology)
        self.assertEqual(reservation, (1, 2, 3, 4, 5, 7, 8, 9, 12))

    def test_linux_pulse_rejects_short_thread_reservation(self) -> None:
        available = set(range(9))
        topology = {cpu: (0, cpu) for cpu in available}
        topology[8] = topology[0]
        with self.assertRaisesRegex(RuntimeError, "requires 9 distinct physical cores"):
            PULSE.select_pulse_physical_cpus(available, topology)

    def test_pulse_result_path_stays_below_selected_root(self) -> None:
        root = Path("selected-results")
        self.assertEqual(
            PULSE.pulse_result_path(root, "exact-head/long"),
            root.resolve() / "exact-head/long",
        )
        with self.assertRaisesRegex(ValueError, "relative child path"):
            PULSE.pulse_result_path(root, "../escape")

    def test_linux_pulse_command_uses_taskset_cpu_list(self) -> None:
        command = PULSE.pulse_command(
            Path("/tmp/pulse_threads"), "long", "independent-cpu-8",
            (2, 3, 5), taskset="/usr/bin/taskset"
        )
        self.assertEqual(
            command,
            ["/usr/bin/taskset", "--cpu-list", "2,3,5", str(Path("/tmp/pulse_threads")),
             "long", "independent-cpu-8"],
        )

    def test_tsc_fallback_uses_adjacent_process_pairs(self) -> None:
        self.assertTrue(PULSE.use_paired_process_ratios("abi", "tsc"))
        self.assertTrue(PULSE.use_paired_process_ratios("move", "cycles"))
        self.assertFalse(PULSE.use_paired_process_ratios("abi", "cycles"))

    def test_external_moon_toolchain_paths_are_rooted_at_selection(self) -> None:
        root = Path("/qualification/frozen-toolchain")
        compiler, config = PULSE.moon_toolchain_paths(root)
        if PULSE.IS_WINDOWS:
            self.assertEqual(compiler, root / "bin" / "x86_64-win64" / "fpc.exe")
            self.assertEqual(config, root / "bin" / "x86_64-win64" / "fpc.cfg")
        else:
            self.assertEqual(compiler, root / "bin" / "fpc")
            self.assertEqual(config, root / "etc" / "fpc.cfg")

    def test_external_moon_invokes_frozen_backend_not_driver(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            backend = root / "lib" / "fpc" / "3.3.1" / "ppcx64"
            backend.parent.mkdir(parents=True)
            backend.write_bytes(b"frozen compiler")
            self.assertEqual(PULSE.moon_toolchain_backend(root), backend.resolve())

    def test_external_moon_rejects_ambiguous_backends(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for version in ("3.3.0", "3.3.1"):
                backend = root / "lib" / "fpc" / version / "ppcx64"
                backend.parent.mkdir(parents=True)
                backend.write_bytes(version.encode())
            with self.assertRaisesRegex(RuntimeError, "exactly one"):
                PULSE.moon_toolchain_backend(root)

    def test_external_moon_identity_hashes_driver_config_and_backend(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            driver, config = PULSE.moon_toolchain_paths(root)
            backend = root / "lib" / "fpc" / "3.3.1" / "ppcx64"
            for path, contents in (
                (driver, b"driver"),
                (config, b"config"),
                (backend, b"backend"),
            ):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(contents)
            identity = PULSE.moon_toolchain_identity(root)
            self.assertEqual(identity["fpc_sha256"], PULSE.sha256(driver))
            self.assertEqual(identity["config_sha256"], PULSE.sha256(config))
            self.assertEqual(identity["backend"], str(backend.resolve()))
            self.assertEqual(identity["backend_sha256"], PULSE.sha256(backend))

    def test_external_systems_have_unambiguous_report_roles(self) -> None:
        baseline, candidate = PULSE.report_system_roles(
            ["moon-baseline", "moon-candidate"]
        )
        self.assertEqual(baseline, "moon-baseline")
        self.assertEqual(candidate, "moon-candidate")

    def test_default_mm_undoes_product_config_profile(self) -> None:
        options = PULSE.moon_mm_options(True)
        self.assertIn("-dPULSE_DEFAULT_MM", options)
        self.assertIn("-dMOONCOMPILER_VANILLA_RUNTIME", options)
        platform_units = (
            "-Fafpwinmonitor"
            if PULSE.IS_WINDOWS
            else "-Facthreads,cwstring,fpmonitor"
        )
        self.assertIn(platform_units, options)
        self.assertIn("-uMOONBOT_MM_PROFILE_REQUIRED", options)
        self.assertIn("-uFPCMM_BOOSTER", options)
        self.assertIn("-uFPCMM_MOONSHARD", options)
        self.assertFalse(any(option.startswith("--pinned-unit=") for option in options))

    def test_bundled_mm_is_explicitly_pinned_and_required_first(self) -> None:
        options = PULSE.moon_mm_options(False)
        self.assertIn("-uMOONCOMPILER_VANILLA_RUNTIME", options)
        self.assertIn("-dMOONBOT_MM_PROFILE_REQUIRED", options)
        self.assertTrue(any(option.startswith("--pinned-unit=") for option in options))
        self.assertIn("--required-first-unit=mormot.core.fpcx64mm", options)


if __name__ == "__main__":
    unittest.main()
