from __future__ import annotations

import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


import pulse as PULSE


class PulseStatisticsTests(unittest.TestCase):
    def test_family_process_order_is_locally_mirrored(self) -> None:
        systems = [f + s for f in ("B", "C") for s in ("", "1", "2", "3")]
        self.assertEqual(PULSE.process_order(systems, 2),
                         ["B", "C", "C", "B", "B1", "C1", "C1", "B1",
                          "B2", "C2", "C2", "B2", "B3", "C3", "C3", "B3"])
        order = PULSE.process_order(systems, 7)
        self.assertTrue(all(order.count(system) == 7 for system in systems))
        self.assertEqual(PULSE.process_order(["moon"], 2), ["moon", "moon"])

    def test_fresh_image_is_hashed_then_removed_and_canonical_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            canonical = Path(temporary) / "benchmark.exe"
            canonical.write_bytes(b"frozen image")
            images = []
            def run(command, **kwargs):
                image = Path(command[0])
                self.assertNotEqual(image, canonical)
                self.assertEqual(image.read_bytes(), canonical.read_bytes())
                self.assertEqual(image.parent.parent, canonical.parent)
                images.append(image)
                return subprocess.CompletedProcess(command, 0, stdout="PASS")
            with mock.patch.object(PULSE, "run", side_effect=run):
                for _ in range(2):
                    _, identity = PULSE.run_fresh_image(canonical, "medium", "case", (), PULSE.sha256(canonical))
                    self.assertEqual(identity["executed_image_sha256"], PULSE.sha256(canonical))
            self.assertNotEqual(images[0], images[1])
            self.assertTrue(all(not image.parent.exists() for image in images))
            self.assertEqual(canonical.read_bytes(), b"frozen image")
            with mock.patch.object(PULSE, "run", side_effect=subprocess.CalledProcessError(1, "test")):
                with self.assertRaises(subprocess.CalledProcessError):
                    PULSE.run_fresh_image(canonical, "medium", "case", (), PULSE.sha256(canonical))
            self.assertEqual(list(canonical.parent.iterdir()), [canonical])

    def test_changed_canonical_is_rejected_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            canonical = Path(temporary) / "benchmark.exe"
            canonical.write_bytes(b"different")
            with mock.patch.object(PULSE, "run") as run:
                with self.assertRaisesRegex(ValueError, "executable changed"):
                    PULSE.run_fresh_image(canonical, "medium", "case", (), "old-hash")
                run.assert_not_called()

    def test_process_center_does_not_erase_three_slow_processes(self) -> None:
        row = {"run_samples": [[{"cycles": value}] for value in [100] * 4 + [140] * 3]}
        stats, _ = PULSE.process_balanced_stats(row, "cycles")
        self.assertEqual((stats.kept, stats.rejected, stats.maximum / stats.minimum), (7, 0, 1.4))

    def test_common_drift_preserves_paired_ratio_and_all_observations(self) -> None:
        stats = PULSE.paired_centers({1: 100, 4: 80, 5: 80}, {2: 118, 3: 94.4, 6: 94.4})
        self.assertAlmostEqual(stats.median, 1.18)
        self.assertAlmostEqual(stats.maximum / stats.minimum, 1)
        self.assertEqual(stats.kept, 3)

    def test_paired_modes_are_not_trimmed(self) -> None:
        stats = PULSE.paired_centers({2 * i: 100 for i in range(7)},
                                    {2 * i + 1: value for i, value in enumerate([100] * 4 + [140] * 3)})
        self.assertEqual((stats.kept, stats.rejected, stats.maximum / stats.minimum), (7, 0, 1.4))
        with self.assertRaisesRegex(ValueError, "incomplete adjacent"):
            PULSE.paired_centers({1: 100, 10: 100}, {2: 100, 20: 100})

    def test_broad_within_process_variation_is_visible(self) -> None:
        row = {"run_samples": [[{"cycles": value} for value in [100] * 20 + [140] * 17]]}
        self.assertEqual(PULSE.sample_spread(row, "cycles"), 1.4)

    def test_parse_fields_keeps_dash_values(self) -> None:
        fields = PULSE.parse_fields(
            "PULSE_CASE program=pulse_codegen case=for-runtime-0-255 layer=codegen"
        )
        self.assertEqual(fields["case"], "for-runtime-0-255")

    def test_program_log_name_accepts_pascal_identifier_for_hyphenated_source(self) -> None:
        self.assertEqual(
            PULSE.emitted_program_names("mormot-json"),
            {"mormot-json", "pulse_mormot-json", "pulse_mormot_json"},
        )

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

    def test_linux_family_uses_six_cores_without_relaxing_worker_requirements(self) -> None:
        available = set(range(12))
        topology = {cpu: (0, cpu % 6) for cpu in available}
        with mock.patch.object(PULSE, "IS_WINDOWS", False), \
                mock.patch.object(PULSE.os, "sched_getaffinity", return_value=available, create=True), \
                mock.patch.object(PULSE, "linux_cpu_topology", return_value=topology):
            self.assertEqual(PULSE.linux_pulse_cpu_reservation(["numeric", "product-forms"], None), tuple(range(6)))
            self.assertEqual(PULSE.linux_pulse_cpu_reservation(["repairs"], None), tuple(range(6)))
            with self.assertRaisesRegex(RuntimeError, "requires 9 distinct physical cores"):
                PULSE.linux_pulse_cpu_reservation(["threads"], None)
            four = set(range(4))
            with mock.patch.object(PULSE.os, "sched_getaffinity", return_value=four):
                self.assertEqual(PULSE.linux_pulse_cpu_reservation(["repairs"], {"repairs/ring-64"}), tuple(range(4)))
                with self.assertRaisesRegex(RuntimeError, "requires 5 distinct physical cores"):
                    PULSE.linux_pulse_cpu_reservation(["repairs"], {"repairs/padded-counters-4"})

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
            backend = root / "bin" / "x86_64-win64" / (
                "ppcx64.exe" if PULSE.IS_WINDOWS else "ppcx64"
            )
            backend.parent.mkdir(parents=True)
            backend.write_bytes(b"frozen compiler")
            self.assertEqual(PULSE.moon_toolchain_backend(root), backend.resolve())

    def test_external_moon_rejects_ambiguous_backends(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for version in ("3.3.0", "3.3.1"):
                backend = root / "bin" / version / (
                    "ppcx64.exe" if PULSE.IS_WINDOWS else "ppcx64"
                )
                backend.parent.mkdir(parents=True)
                backend.write_bytes(version.encode())
            with self.assertRaisesRegex(RuntimeError, "exactly one"):
                PULSE.moon_toolchain_backend(root)

    def test_external_moon_identity_hashes_driver_config_and_backend(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            driver, config = PULSE.moon_toolchain_paths(root)
            backend = root / "bin" / "x86_64-win64" / (
                "ppcx64.exe" if PULSE.IS_WINDOWS else "ppcx64"
            )
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
            self.assertEqual(identity["legacy_release_config_sha256"],
                             PULSE.sha256(Path(PULSE.__file__).with_name("pulse_legacy_release.cfg")))

    def test_external_systems_have_unambiguous_report_roles(self) -> None:
        baseline, candidate = PULSE.report_system_roles(
            ["moon-baseline", "moon-candidate"]
        )
        self.assertEqual(baseline, "moon-baseline")
        self.assertEqual(candidate, "moon-candidate")

    def test_stand_report_roles_use_family_roots(self) -> None:
        baseline, candidate = PULSE.report_system_roles(
            ["C", "C1", "C2", "C3", "T", "T1", "T2", "T3"]
        )
        self.assertEqual((baseline, candidate), ("C", "T"))

    def test_repair_program_requires_before_after_moon_pair(self) -> None:
        PULSE.validate_program_systems(
            ["repairs"], ["moon-baseline", "moon-candidate"]
        )
        with self.assertRaisesRegex(ValueError, "Moon-only repair programs"):
            PULSE.validate_program_systems(
                ["numeric", "repairs"], ["delphi", "moon", "moon-default"]
            )

    def test_default_programs_exclude_moon_only_repairs(self) -> None:
        self.assertNotIn("repairs", PULSE.DEFAULT_PROGRAMS)
        self.assertIn("repairs", PULSE.PROGRAMS)

    def test_drift_is_correctness_only_and_excluded_from_aggregates(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            result = Path(temporary)
            runs = []
            modes = [10.0, 11.0, 12.0, 13.0, 12.0, 11.0, 10.0]
            for system, scale in (("delphi", 1.0), ("moon", 0.8)):
                for sequence, mode in enumerate(modes, 1):
                    log_name = f"{system}-{sequence}.log"
                    cycles = int(mode * scale * 1000)
                    (result / log_name).write_text(
                        "PULSE_CASE program=synthetic mode=medium case=drift "
                        "layer=codegen unit=test iterations=1 operations=1 "
                        "samples=1 warmup_ns=1 oracle=0000000000000001\n"
                        "PULSE_SAMPLE program=synthetic mode=medium case=drift "
                        "sample=1 iterations=1 operations=1 wall_ns=1000 "
                        f"thread_cpu_ns=1000 process_cpu_ns=1000 thread_cycles={cycles} "
                        f"tsc_ticks={cycles} digest=0000000000000001\n"
                        "PULSE_TOTAL program=synthetic mode=medium case=drift "
                        "samples=1 operations=1 wall_ns=1000 thread_cpu_ns=1000 "
                        "process_cpu_ns=1000 thread_cycles=1000 tsc_ticks=1000\n"
                        "PULSE_END program=synthetic status=PASS\n",
                        encoding="utf-8",
                    )
                    runs.append({
                        "sequence": sequence,
                        "system": system,
                        "program": "synthetic",
                        "log": log_name,
                    })
            (result / "manifest.json").write_text(
                json.dumps({
                    "mode": "medium",
                    "systems": ["delphi", "moon"],
                    "runs": runs,
                }),
                encoding="utf-8",
            )

            with self.assertRaises(PULSE.UnstablePairsError):
                PULSE.write_report(result)
            details = json.loads((result / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(details["synthetic/drift"]["comparison_status"], "DRIFT")
            self.assertIsNone(details["synthetic/drift"]["candidate_over_baseline"])
            self.assertAlmostEqual(
                details["synthetic/drift"]["diagnostic_candidate_over_baseline"],
                0.8,
            )
            self.assertIn(
                "Excluded Unstable Measurements",
                (result / "REPORT.md").read_text(encoding="utf-8"),
            )
            PULSE.write_report(result, accept_drift=True)

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

    def test_external_mm_source_is_pinned_instead_of_current_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "mormot.core.fpcx64mm.pas"
            source.write_text("unit mormot.core.fpcx64mm;", encoding="utf-8")
            options = PULSE.moon_mm_options(False, source)
            self.assertIn(
                f"--pinned-unit=mormot.core.fpcx64mm={source.resolve()}",
                options,
            )
            self.assertNotIn(
                f"--pinned-unit=mormot.core.fpcx64mm={PULSE.MM_SOURCE.resolve()}",
                options,
            )

    def test_a_toolchain_without_the_programs_unit_leaves_the_program_out(self) -> None:
        # the release has no System.ZLib: zlib is not built with it and not compared, the rest is
        with tempfile.TemporaryDirectory() as temporary:
            release, current = Path(temporary) / "release", Path(temporary) / "current"
            for toolchain in (release, current):
                units = toolchain / ("units/x86_64-win64" if PULSE.IS_WINDOWS
                                     else "lib/fpc/3.3.1/units/x86_64-linux")
                (units / "vcl-compat").mkdir(parents=True)
            (PULSE.toolchain_units(current) / PULSE.PROGRAM_TOOLCHAIN_UNITS["zlib"]).write_bytes(b"ppu")
            built_programs = []
            def build_moon(program, default_mm, **options):
                built_programs.append((options["system"], program))
                return Path(options["system"]) / program
            with mock.patch.object(PULSE, "build_moon", side_effect=build_moon), \
                 contextlib.redirect_stdout(io.StringIO()):
                built = PULSE.build(["json", "zlib"], ["moon-baseline", "moon-candidate"],
                                    {"moon-baseline": release, "moon-candidate": current})
                programs, left_out = PULSE.buildable_everywhere(built, ["json", "zlib"])
            self.assertNotIn(("moon-baseline", "zlib"), built_programs)
            self.assertEqual(sorted(built["moon-candidate"]), ["json", "zlib"])
            self.assertEqual((programs, left_out), (["json"], {"zlib": ["moon-baseline"]}))


if __name__ == "__main__":
    unittest.main()
