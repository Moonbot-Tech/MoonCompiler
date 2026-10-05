from __future__ import annotations

import contextlib
import functools
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("pulse_full.py")
SPEC = importlib.util.spec_from_file_location("pulse_full", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
FULL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FULL
SPEC.loader.exec_module(FULL)
CALIBRATION_SPEC = importlib.util.spec_from_file_location(
    "pulse_l2_calibration", MODULE_PATH.with_name("pulse_l2_calibration.py"))
assert CALIBRATION_SPEC is not None and CALIBRATION_SPEC.loader is not None
CALIBRATION = importlib.util.module_from_spec(CALIBRATION_SPEC)
CALIBRATION_SPEC.loader.exec_module(CALIBRATION)
REANALYZE_SPEC = importlib.util.spec_from_file_location(
    "pulse_reanalyze", MODULE_PATH.with_name("pulse_reanalyze.py"))
assert REANALYZE_SPEC is not None and REANALYZE_SPEC.loader is not None
REANALYZE = importlib.util.module_from_spec(REANALYZE_SPEC)
REANALYZE_SPEC.loader.exec_module(REANALYZE)


def derived(value: float) -> dict[str, object]:
    metrics = {
        "valid": True,
        "ticks_per_op": value,
        "work_cycles_per_op": value,
        "core_per_op": value,
        "process_cpu_per_op": value,
        "operations_per_second": 1000.0 / value,
        "latency_p99_ns": value,
        "effective_cores": 1.0,
        "memory_peak_resident": 1000.0,
        "memory_after_private": 900.0,
        "memory_cooldown_private": 800.0,
        "samples": [
            {"valid": True, "ticks_per_op": value, "core_per_op": value, "work_cycles_per_op": value},
            {"valid": True, "ticks_per_op": value, "core_per_op": value, "work_cycles_per_op": value},
            {"valid": True, "ticks_per_op": value, "core_per_op": value, "work_cycles_per_op": value},
        ],
    }
    return metrics


def sides(remote: list[float], current: list[float]) -> list[dict[str, object]]:
    return [
        {"variant": system, "repeat": repeat, "case_definition": {"oracle": "1"}, "samples": [{"digest": "1"}],
         "derived": derived(value)}
        for repeat, pair in enumerate(zip(remote, current))
        for system, value in zip(("moon-baseline", "moon-candidate"), pair)
    ]


def records(candidate_values: list[float]) -> list[dict[str, object]]:
    output = []
    for repeat, current in enumerate(candidate_values):
        for system, value in (
            ("moon-baseline", 100.0),
            ("moon-candidate", current),
        ):
            output.append(
                {
                    "variant": system,
                    "repeat": repeat,
                    "case_definition": {"oracle": "1"},
                    "samples": [{"digest": "1"}],
                    "derived": derived(value),
                }
            )
    return output


class PulseFullTests(unittest.TestCase):
    def test_single_cpu_override_keeps_eight_multithread_cores_and_rejects_bad_pairs(self) -> None:
        physical = tuple(range(0, 16, 2))
        with (mock.patch.object(FULL.method, "windows_physical_cpus", return_value=physical),
              mock.patch.object(FULL.method, "linux_physical_cpus", return_value=physical)):
            single, multithread = FULL.benchmark_cpu_sets("12,14")
            self.assertEqual(single, (12, 14))
            self.assertEqual(multithread, physical)
            self.assertEqual(FULL.hostable(["threads"], multithread), (["threads"], {}))
            for requested in ("12", "12,14,12", "12,12", "12,13", "12,,14", "0,2,4,6,8,10,12,14"):
                with self.subTest(requested=requested), self.assertRaises(ValueError):
                    FULL.benchmark_cpu_sets(requested)

    def test_case_selectors_preserve_wildcards_and_the_requested_program_scope(self) -> None:
        class BuildReached(Exception):
            pass

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mm = root / "mm.pas"
            mm.write_text("unit mm; interface implementation end.")
            selections = (
                ("rtl/a,*/b", "rtl,codegen", ["rtl", "codegen"]),
                ("rtl/a,*gen/b", "rtl,codegen,loops", ["rtl", "codegen"]),
                ("rtl/a,*", "rtl,codegen", ["rtl", "codegen"]),
                ("rtl/a", "rtl,codegen", ["rtl"]),
                ("rtl/a", "codegen", []),
            )
            for index, (selectors, programs, expected) in enumerate(selections):
                argv = ["pulse_full.py", "--baseline-toolchain", str(root), "--candidate-toolchain", str(root),
                        "--baseline-mm-source", str(mm), "--candidate-mm-source", str(mm),
                        "--output", str(root / str(index)), "--programs", programs, "--cases", selectors,
                        "--skip-preflight"]
                with (self.subTest(selectors=selectors, programs=programs), mock.patch.object(sys, "argv", argv),
                      mock.patch.object(FULL, "benchmark_cpu_sets", return_value=((0, 1), tuple(range(8)))),
                      mock.patch.object(FULL.pulse, "build", side_effect=BuildReached) as build):
                    with self.assertRaises(BuildReached if expected else ValueError):
                        FULL.run()
                    if expected:
                        self.assertEqual(build.call_args.args[0], expected)
                    else:
                        build.assert_not_called()

    def test_classification_keeps_exclusive_classes_out_of_parallel_cpu(self) -> None:
        self.assertEqual(FULL.classify("threads", "locked-increment-4", "rtl+os"), "multithread")
        self.assertEqual(FULL.classify("repairs", "padded-counters-4", "rtl"), "multithread")
        self.assertEqual(FULL.classify("mm", "realloc-shrink", "memory-manager"), "memory-manager")
        self.assertEqual(FULL.classify("move", "stream-a0-a0-n64", "rtl"), "memory-global")
        self.assertEqual(FULL.classify("move", "hot-a0-a0-n64", "rtl"), "memory-local")
        self.assertEqual(FULL.classify("move", "hot-a0-a0-n1048576", "rtl"), "memory-global")
        self.assertEqual(FULL.classify("codegen", "dep-add", "codegen"), "single-cpu")

    def test_six_paired_processes_can_choose_a_stable_ratio(self) -> None:
        case = FULL.Case("codegen", "dep-add", "codegen", "compiler", "single-cpu")
        analysis = FULL.analyze_case(records([97.0, 97.1, 96.9] * 2), case)
        self.assertTrue(analysis["stable"])
        self.assertTrue(analysis["semantic_match"])
        self.assertAlmostEqual(analysis["metrics"]["work_cycles_per_op"]["median"], 0.97, places=3)
        self.assertEqual(FULL.verdict(case, analysis), "BETTER")

    def test_process_modes_remain_unstable_instead_of_being_trimmed(self) -> None:
        case = FULL.Case("repairs", "utf8-decode", "rtl", "System", "single-cpu")
        analysis = FULL.analyze_case(records([90.0, 90.0, 110.0, 110.0, 110.0]), case)
        self.assertFalse(analysis["stable"])
        self.assertEqual(FULL.verdict(case, analysis), "UNSTABLE")

    def test_large_clear_effect_does_not_require_subpercent_precision(self) -> None:
        case = FULL.Case("repairs", "roundto-minus2", "rtl", "Math.RoundTo", "single-cpu")
        for values, expected in (([26, 27, 28], "BETTER"), ([116, 125, 138], "WORSE")):
            with self.subTest(values=values):
                analysis = FULL.analyze_case(records(values * 2), case)
                self.assertEqual(FULL.verdict(case, analysis), expected)

    def test_same_requires_the_whole_observed_range_inside_threshold(self) -> None:
        case = FULL.Case("codegen", "dep-add", "codegen", "compiler", "single-cpu")
        analysis = FULL.analyze_case(records([99.8, 99.9, 100.0, 100.1, 104.0]), case)
        self.assertEqual(FULL.verdict(case, analysis), "UNSTABLE")

    def test_multithread_cpu_tradeoff_is_explicit(self) -> None:
        case = FULL.Case("threads", "producer-consumer", "threads", "System", "multithread")
        final = {
            "semantic_match": True,
            "stable": True,
            "valid_processes": {
                "moon-baseline": 5,
                "moon-candidate": 5,
            },
            "valid_pairs": 5,
            "attempted_pairs": 5,
            "primary_metrics": (
                "ticks_per_op",
                "work_cycles_per_op",
                "memory_peak_resident",
            ),
            "metrics": {
                "ticks_per_op": {"decision": "BETTER"},
                "work_cycles_per_op": {"decision": "WORSE"},
                "memory_peak_resident": {"decision": "SAME"},
            },
        }
        self.assertEqual(FULL.verdict(case, final), "TRADEOFF")

    @unittest.skipUnless(os.name == "nt", "the Windows processor topology")
    def test_a_windows_runner_measures_inside_its_affinity_mask(self) -> None:
        # Started under a mask, the runner takes its cores from it, as taskset
        # gives them on Linux.  It used to take the first cores of the machine
        # and then find no CPU left for itself (mask 0xCF00, 29.09).
        method = FULL.method
        with mock.patch.object(method, "windows_allowed_cpus", return_value=set(range(64))):
            cores = method.windows_physical_cpus(None)
        if len(cores) < 4:
            self.skipTest("fewer than four cores on this machine")
        second = method.processor_sibling(cores[2])
        second = cores[2] if second is None else second
        with mock.patch.object(method, "windows_allowed_cpus", return_value={cores[1], second, cores[3]}):
            self.assertEqual(method.windows_physical_cpus(None), (cores[1], second, cores[3]))

    def test_a_machine_short_of_a_programs_workers_names_it_in_the_report(self) -> None:
        # pulse_threads pins eight workers and refuses fewer CPUs: a six-core
        # machine leaves it out and says so instead of failing the whole pass
        # at its first process.
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(FULL.hostable(["json", "threads", "repairs"], tuple(range(6))),
                             (["json", "repairs"], {"threads": 8}))
            self.assertEqual(FULL.hostable(["json", "threads"], tuple(range(8))), (["json", "threads"], {}))
            # The padded-counter sentinel of repairs needs five: a four-core mask leaves out that case alone.
            self.assertEqual(FULL.hostable(["repairs/padded-counters-4", "repairs/ring-64"], tuple(range(4))),
                             (["repairs/ring-64"], {"repairs/padded-counters-4": 5}))
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        saved = {
            "baseline_toolchain": {"backend_sha256": "r"},
            "candidate_toolchain": {"backend_sha256": "c"},
            "machine": {"platform": "p", "cpu_work_unit": "u", "multithread_topology": "t"},
            "scope": {"programs": ["codegen"], "cases": "all", "left_out": {},
                      "unhostable": {"threads": {"workers": 8, "multithread_cpus": 6},
                                     "repairs/padded-counters-4": {"workers": 5, "multithread_cpus": 4}}},
            "cases": {"codegen/dep-add": {
                "program": "codegen", "case": "dep-add", "layer": "codegen", "unit": "compiler",
                "category": "single-cpu", "chosen_duration_ms": 6, "final": {"records": records([97.0] * 6)},
            }},
            "elapsed_seconds": 1.0, "stack_phase": "grid", "scaling": [], "placement_errors": [],
            "l2_calibration": None,
        }
        source = directory / "result.json"
        source.write_text(json.dumps(saved), encoding="utf-8")
        REANALYZE.reanalyze(source, directory / "report")
        text = (directory / "report" / "REPORT.md").read_text(encoding="utf-8")
        self.assertIn("программа `threads` не мерилась — она ставит 8 рабочих потоков, каждый на своё "
                      "физическое ядро, а у машины их 6.", text)
        self.assertIn("строка `repairs/padded-counters-4` не мерилась — она ставит 5 рабочих потоков", text)

    def test_memory_modes_are_not_hidden_by_a_near_one_median(self) -> None:
        case = FULL.Case(
            "calibration", "asm-memory-read-64m", "memory", "asm", "memory-global"
        )
        analysis = FULL.analyze_case(records([99.1, 100.2, 95.4, 99.8, 101.5, 100.0]), case)
        self.assertFalse(analysis["stable"])
        self.assertEqual(analysis["metrics"]["ticks_per_op"]["decision"], "UNSTABLE")
        self.assertEqual(FULL.verdict(case, analysis), "UNSTABLE")

    def test_median_interval_has_exact_binomial_coverage(self) -> None:
        self.assertIsNone(FULL.median_interval([1.0] * 5))
        self.assertEqual(FULL.median_interval(list(range(6))), [0, 5])
        self.assertEqual(FULL.median_interval(list(range(12))), [2, 9])

    def test_typical_improvement_keeps_slow_processes_in_the_report(self) -> None:
        case = FULL.Case("repairs", "roundto-minus2", "rtl", "Math", "single-cpu")
        analysis = FULL.analyze_case(records([80.0] * 10 + [105.0, 110.0]), case)
        metric = analysis["metrics"]["work_cycles_per_op"]
        self.assertEqual(metric["decision"], "BETTER")
        self.assertEqual(metric["median_interval_95"], [0.8, 0.8])
        self.assertEqual(metric["maximum"], 1.1)
        self.assertEqual(len(metric["ratios"]), 12)

    def test_sides_that_do_not_overlap_are_a_direction_not_same(self) -> None:
        # Every process of one side cheaper than every one of the other (heartbeat E22, Astra 0.9-169: 12 against 12)
        # is a direction whatever the distance of the median ratio from the threshold.
        case = FULL.Case("heartbeat", "binary-session-pipeline", "rtl", "Pulse", "single-cpu")
        near = [100.0 + 0.04 * index for index in range(12)]
        for remote, current, interval, decision in (
            (near, [value - 0.5 for value in near], "SAME", "BETTER"),  # every ratio 0.995: inside the threshold
            (near, [value + 0.5 for value in near], "SAME", "WORSE"),
            ([100.0, 101.0] * 6, [99.9, 99.0] * 6, "UNSTABLE", "BETTER"),  # ratios 0.999 and 0.980: across it
        ):
            for overlap in (False, True):
                with self.subTest(interval=interval, decision=decision, overlap=overlap):
                    moved = list(current)
                    if overlap:
                        # Negative control: one process of a side just inside the other side - the interval decides.
                        moved[0] = min(remote) + 0.01 if decision == "BETTER" else max(remote) - 0.01
                    analysis = FULL.analyze_case(sides(remote, moved), case)
                    metric = analysis["metrics"]["work_cycles_per_op"]
                    self.assertEqual(metric["decision"], interval if overlap else decision)
                    self.assertEqual(metric["separated"], not overlap)
                    self.assertEqual(FULL.verdict(case, analysis), interval if overlap else decision)

    def test_memory_split_by_a_page_keeps_its_threshold(self) -> None:
        case = FULL.Case("mm", "alloc-free-64", "rtl+memory", "MM", "memory-manager")
        measured = sides([100.0] * 12, [100.0] * 12)
        for record in measured:
            record["derived"]["memory_peak_resident"] = 100 * 1048576 + 4096 * (record["variant"] == "moon-candidate")
        metric = FULL.analyze_case(measured, case)["metrics"]["memory_peak_resident"]
        self.assertEqual(metric["decision"], "SAME")
        self.assertFalse(metric["separated"])

    def test_equal_oracle_cannot_hide_different_measured_work(self) -> None:
        case = FULL.Case("repairs", "roundto-minus2", "rtl", "Math", "single-cpu")
        measured = records([80.0] * 6)
        for row in measured:
            row["fixed_work"] = True
            row["samples"] = [{"operations": 100, "digest": "same"}]
        measured[-1]["samples"][0]["operations"] = 101
        self.assertEqual(FULL.verdict(case, FULL.analyze_case(measured, case)), "SEMANTIC_MISMATCH")

    def test_fixed_work_is_not_rejected_for_a_large_speed_difference(self) -> None:
        sample = dict.fromkeys((
            "operations", "tsc_ticks", "core_cycles", "wall_ns", "process_cycles", "thread_cycles",
            "process_cpu_ns", "thread_cpu_ns", "core_enabled", "core_running", "memory_before_private",
            "memory_after_private", "memory_cooldown_private", "memory_peak_resident", "iterations",
        ), 100)
        sample["context_switches"] = 0
        self.assertFalse(FULL.method.sample_metrics(sample, False, 2)["counter_valid"])
        self.assertTrue(FULL.method.sample_metrics(sample, False, 2, fixed_work=True)["counter_valid"])

    def test_contaminated_pairs_are_retried_as_one_batch(self) -> None:
        def record(variant: str, valid: bool) -> dict[str, object]:
            return {
                "program": "codegen",
                "case": "dep-add",
                "repeat": 0,
                "variant": variant,
                "category": "single-cpu",
                "executable": f"{variant}.exe",
                "log": f"{variant}.log",
                "derived": {"valid": valid},
            }

        initial = [record("moon-baseline", False), record("moon-candidate", True)]
        retried = [record("moon-baseline", True), record("moon-candidate", True)]
        with (
            mock.patch.object(
                FULL.method,
                "record_metrics",
                side_effect=lambda value, _multithread: value["derived"],
            ),
            mock.patch.object(FULL.method, "run_batch", return_value=retried) as run_batch,
        ):
            cleaned = FULL.clean_records(initial, 50, (0, 2), Path("out"), "cpu")

        self.assertEqual(len(cleaned), 2)
        self.assertTrue(all(row["accepted"] for row in cleaned))
        self.assertEqual(run_batch.call_count, 1)
        self.assertEqual(len(run_batch.call_args.args[0]), 2)

    def test_method_controls_fix_stack_phase_on_both_platforms(self) -> None:
        method = FULL.method
        items = [
            (Path(side), "codegen", "dep-add", side, repeat, "single-cpu", repeat * 2 + position)
            for repeat in range(method.PROCESS_REPEATS)
            for position, side in enumerate(("A", "B") if repeat % 2 == 0 else ("B", "A"))
        ]
        items.extend((Path(side), "repairs-control", "stddev-4", side, repeat, "control", repeat * 2 + position)
                     for repeat in range(method.PROCESS_REPEATS)
                     for position, side in enumerate(("work64", "work66")))
        items.append((Path("threads"), "threads", "pool", "A", 0, "multithread", 0))
        for platform in ("posix", "nt"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as directory:
                # Construct Path before mocking os.name, also on a Windows test host.
                output = Path(directory)
                with (mock.patch.object(method.os, "name", platform),
                      mock.patch.object(method, "run_one", return_value={}) as run_one):
                    method.run_batch(items, 200, (0, 2), output, "controls", enable_xperf=False)
                self.assertEqual(run_one.call_count, len(items))
                for call in run_one.call_args_list:
                    category = call.args[6]
                    self.assertEqual(call.kwargs["stack_phase"], None if category == "multithread" else 0)

    def test_stack_grid_puts_both_sides_of_a_pair_on_one_phase(self) -> None:
        self.assertEqual([FULL.stack_phase("grid", pair) for pair in (0, 1, 11)], [0, 336, 3696])
        self.assertEqual(len({FULL.stack_phase("grid", pair) for pair in range(256)}), 256)
        self.assertIsNone(FULL.stack_phase(FULL.stack_phase_plan("fixed"), 5))
        self.assertEqual(FULL.stack_phase(FULL.stack_phase_plan("0"), 5), 0)
        self.assertEqual(FULL.stack_phase(FULL.stack_phase_plan("4080"), 5), 4080)
        for wrong in ("8", "17", "4096", "-16", "native"):
            with self.subTest(wrong=wrong), self.assertRaises(Exception):
                FULL.stack_phase_plan(wrong)
        case = FULL.Case("workloads", "binary-trees-depth-10", "codegen+mm", "Pascal", "single-cpu")
        launched = []

        def run_one(executable, program, name, variant, repeat, *args, **kwargs):
            launched.append((variant, kwargs["stack_phase"]))
            return {"variant": variant, "iterations": 5, "log": "log"}

        with (
            mock.patch.object(FULL.method, "run_one", side_effect=run_one),
            mock.patch.object(FULL.method, "record_metrics", return_value={"valid": True}),
        ):
            FULL.run_pair(case, 3, 6, mock.MagicMock(), (0, 2), (0,), {(case.program, case.name): (5, 6)},
                          Path("out"), "cpu", False, 0)
        self.assertEqual(sorted(launched), [("moon-baseline", 1008), ("moon-candidate", 1008)])

    def test_long_case_logs_keep_identity_without_exceeding_windows_path_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / ("x" * max(1, 106 - len(str(root))))
            executable = root / "benchmark.exe"
            executable.write_bytes(b"benchmark")
            cases = [
                FULL.Case("rtl-collections", name, "rtl", "System", "single-cpu")
                for name in (
                    "list-integer-delete-insert-range-4096",
                    "list-integer-delete-insert-range-4097",
                )
            ]
            tag = "single-cpu-coverage-r0"
            logs = []
            with (
                mock.patch.object(FULL.method, "benchmark_environment", return_value={}),
                mock.patch.object(FULL.method, "launch", return_value=("measured", 0, 123, 0.01, {})),
                mock.patch.object(FULL.method, "record_metrics", return_value={"valid": True}),
                mock.patch.object(FULL.method, "parse_measurement_output") as parse,
            ):
                for case in cases:
                    parse.return_value = ({case.name: {}}, {case.name: [{"iterations": "1"}]})
                    old = (output / "logs" / tag / f"{case.program}-{case.name}-r0-a0"
                           / f"{case.program}-{case.name}-moon-candidate-0.log")
                    self.assertGreaterEqual(len(str(old)), 260)
                    images = {(system, case.program, 0): executable for system in FULL.SYSTEMS}
                    pair = FULL.run_pair(case, 0, 6, images, (4, 6), (0,),
                                         {(case.program, case.name): (1, 6)}, output, tag, False, 0)
                    self.assertEqual({row["case"] for row in pair}, {case.name})
                    logs.extend(Path(row["log"]) for row in pair)
            self.assertEqual(len(set(logs)), 4)
            self.assertEqual(len({log.parent for log in logs}), 2)
            self.assertTrue(all(len(str(log)) < 260 and log.read_text() == "measured" for log in logs))

    def test_measured_l2_misses_run_a_concurrent_case_alone(self) -> None:
        heavy = FULL.Case("layout", "aos-one-field", "codegen+memory", "compiler", "memory-local", 7.0)
        light = FULL.Case("layout", "aligned-read", "codegen+memory", "compiler", "memory-local", 0.01)
        self.assertTrue(heavy.exclusive)
        self.assertFalse(light.exclusive)
        order = []

        def run_pair(case, repeat, duration, images, cpus, threads, cache, output, tag, concurrent, *rest):
            order.append((case.name, concurrent))
            return []

        with (
            mock.patch.object(FULL, "run_pair", side_effect=run_pair),
            mock.patch.object(FULL, "PairPool", functools.partial(FULL.PairPool, quiet=lambda cpu: True)),
        ):
            FULL.run_stage([heavy, light], 0, 2, 6, {}, (0, 2, 4, 6), (0,), {}, Path("out"), "tag")
        self.assertEqual(
            order,
            [("aligned-read", True), ("aligned-read", True), ("aos-one-field", False), ("aos-one-field", False)],
        )

    def test_unknown_l2_traffic_runs_every_case_alone(self) -> None:
        cases = [
            FULL.Case("layout", "aos-one-field", "codegen+memory", "compiler", "memory-local"),
            FULL.Case("layout", "aligned-read", "codegen+memory", "compiler", "memory-local"),
        ]
        section = {"event": "0x4f2e", "created_unix": 1.0,
                   "cases": {"layout/aos-one-field": 0.01, "layout/aligned-read": 0.01}}
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        for label, content, concurrent in (
            ("measured", {"schema": 2, "stand": section}, True),
            ("no file", None, False),
            ("no section for this machine", {"schema": 2, "other-stand": section}, False),
            ("empty cases", {"schema": 2, "stand": {**section, "cases": {}}}, False),
            ("renamed cases", {"schema": 2, "stand": {**section, "cases": {
                "layout/aos-one-field-old": 0.01, "layout/aligned-read-2": 0.01}}}, False),
        ):
            table = directory / f"{label}.json"
            if content is not None:
                table.write_text(json.dumps(content), encoding="utf-8")
            launched = []

            def run_pair(case, repeat, duration, images, cpus, threads, cache, output, tag, concurrent, *rest):
                launched.append(concurrent)
                return []

            with (
                self.subTest(label),
                mock.patch.object(FULL.platform, "node", return_value="stand"),
                mock.patch.object(FULL, "run_pair", side_effect=run_pair),
                mock.patch.object(FULL, "PairPool", functools.partial(FULL.PairPool, quiet=lambda cpu: True)),
            ):
                measured, calibration = FULL.l2_calibration(cases, table)
                FULL.run_stage(measured, 0, 2, 6, {}, (0, 2, 4, 6), (0,), {}, Path("out"), "tag")
                self.assertEqual(launched, [concurrent] * 4)
                self.assertEqual(calibration["machine"], "stand")

    def test_calibration_belongs_to_the_machine_that_measured_it(self) -> None:
        cases = [
            FULL.Case("workloads", "stream-scale", "memory", "Pascal", "memory-local"),
            FULL.Case("layout", "aos-one-field", "codegen+memory", "compiler", "memory-local"),
        ]
        with mock.patch.object(FULL.platform, "node", return_value="hl-node-hel1"):
            measured, calibration = FULL.l2_calibration(cases)
        self.assertEqual((calibration["event"], calibration["created_unix"] > 0), ("0x4f2e", True))
        self.assertTrue(measured[0].exclusive)
        self.assertIsNotNone(measured[1].l2_misses_per_kcycle)
        with mock.patch.object(FULL.platform, "node", return_value="amd2"):
            measured, calibration = FULL.l2_calibration(cases)
        self.assertEqual((calibration["machine"], calibration["event"]), ("amd2", None))
        self.assertEqual([case.l2_misses_per_kcycle for case in measured], [None, None])
        self.assertTrue(all(case.exclusive for case in measured))

    def test_calibration_event_defaults_to_the_cores_requests_to_l3(self) -> None:
        self.assertEqual(CALIBRATION.counted_event(None, "vendor_id\t: GenuineIntel\n"), "0x4f2e")
        self.assertEqual(CALIBRATION.counted_event(None, "vendor_id\t: AuthenticAMD\n"), "0x964+0xff71+0xff72")
        self.assertEqual(CALIBRATION.counted_event("0x0964", "vendor_id\t: AuthenticAMD\n"), "0x0964")
        # Windows has no cpuinfo: its xperf source is named.
        with self.assertRaises(SystemExit) as refused:
            CALIBRATION.counted_event(None, None)
        self.assertIn("--event is required", str(refused.exception))
        self.assertEqual(CALIBRATION.event_parts("0x964+0xff71+0xff72"), ["0x964", "0xff71", "0xff72"])
        self.assertEqual(CALIBRATION.event_parts("CacheMisses"), ["CacheMisses"])
        for bad in ("a++b", "a+b+c+d+e", ""):
            with self.subTest(bad=bad), self.assertRaises(SystemExit):
                CALIBRATION.event_parts(bad)

    def test_reanalysis_reports_the_calibration_as_the_run_used_it(self) -> None:
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        saved = {
            "baseline_toolchain": {"backend_sha256": "r"},
            "candidate_toolchain": {"backend_sha256": "c"},
            "machine": {"platform": "p", "cpu_work_unit": "u", "multithread_topology": "t"},
            "cases": {"codegen/dep-add": {
                "program": "codegen", "case": "dep-add", "layer": "codegen", "unit": "compiler",
                "category": "single-cpu", "chosen_duration_ms": 6, "final": {"records": records([97.0] * 6)},
            }},
            "elapsed_seconds": 1.0, "stack_phase": "grid", "scaling": [], "placement_errors": [],
        }
        # Saved before results recorded the event: the unmeasured case ran concurrently.
        without_event = {"table": "t", "exclusive_per_kcycle": 0.2, "exclusive": ["workloads/stream-scale"],
                         "unmeasured": ["layout/new-case"]}
        measured = {**without_event, "machine": "hl-node-hel1", "event": "0x4f2e", "created_unix": 1.0}
        missing = {**measured, "machine": "amd2", "event": None, "created_unix": None, "exclusive": []}
        for label, calibration, line in (
            ("none", None, "no L2 calibration; concurrent cases were not checked."),
            ("without-event", without_event, "`workloads/stream-scale` (over 0.20 per 1000 cycles); "
                                             "not in the calibration: `layout/new-case`."),
            ("measured", measured, "`workloads/stream-scale` (over 0.20 per 1000 cycles of `0x4f2e` on "
                                   "`hl-node-hel1`); not in the calibration: `layout/new-case` (run alone)."),
            ("missing", missing, "no L2 calibration for `amd2`: every case ran alone."),
        ):
            with self.subTest(label):
                source = directory / f"{label}.json"
                source.write_text(json.dumps({**saved, "l2_calibration": calibration}), encoding="utf-8")
                output = directory / label
                REANALYZE.reanalyze(source, output)
                self.assertLessEqual({"result.raw.json.gz", "result.json", "MEASUREMENTS.md", "REPORT.md"},
                                     {path.name for path in output.iterdir()})
                text = (output / "MEASUREMENTS.md").read_text(encoding="utf-8")
                self.assertIn("\nRun alone by measured L2 misses: " + line + "\n", text)
                self.assertIn("Stack phase: `grid`", text)
                # The unit of the saved costs, not of this runner: reanalysis keeps them as measured.
                self.assertIn("\nCPU work unit: `u`;", text)
                self.assertIn("\nlocal: u.\n", (output / "REPORT.md").read_text(encoding="utf-8"))

    def test_short_process_leaves_the_smt_sibling_not_observed(self) -> None:
        def record(wall_ns: int) -> dict[str, object]:
            sample = dict.fromkeys((
                "operations", "tsc_ticks", "core_cycles", "process_cycles", "thread_cycles", "core_enabled",
                "core_running", "memory_before_private", "memory_after_private", "memory_cooldown_private",
                "memory_peak_resident", "iterations", "sibling_idle_cycles",
            ), 100)
            sample.update(wall_ns=wall_ns, thread_cpu_ns=wall_ns, process_cpu_ns=wall_ns,
                          context_switches=0, sibling_cpu=1)
            return {"duration_ms": 6, "samples": [sample] * 3, "fixed_work": True}

        short = FULL.method.record_metrics(record(2_000_000), False)
        self.assertEqual(
            (short["sibling_idle_observable"], short["sibling_idle_ratio"], short["sibling_idle_valid"]),
            (False, None, True),
        )
        observed = FULL.method.record_metrics(record(20_000_000), False)
        self.assertTrue(observed["sibling_idle_observable"])
        self.assertIsNotNone(observed["sibling_idle_ratio"])
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        process = {**dict.fromkeys((
            "variant", "repeat", "pid", "sha256", "body", "anchor", "iterations", "operations",
            "work_cycles_per_op", "ticks_per_op", "thread_cycles_per_op", "process_cpu_per_op",
            "operations_per_second", "frequency_ratio", "execution_ratio", "page_faults",
            "measurement_seconds", "process_seconds", "accepted_samples", "valid",
        ), 1), "sibling_idle_ratio": short["sibling_idle_ratio"]}
        attempt = {**dict.fromkeys((
            "valid", "passed", "work_spread_percent", "tick_spread_percent", "work_copy_percent",
            "tick_copy_percent", "median_work_cycles_per_op", "median_ticks_per_op", "median_frequency_ratio",
        ), 1), "processes": [process]}
        FULL.method.write_sweep_tables(directory, {"cases": {"codegen/dep-add": {"attempts": {"6": attempt}}}})
        row = (directory / "SWEEP_PROCESSES.tsv").read_text(encoding="utf-8").splitlines()[1].split("\t")
        self.assertEqual(row[-3], "not observed")

    @unittest.skipIf(os.name == "nt", "Linux counts the sibling's idle in clock ticks")
    def test_an_idle_sibling_is_not_short_by_the_ticks_of_its_samples(self) -> None:
        def record(ticks: list[int], wall_ns: int = 19_430_000) -> dict[str, object]:
            samples = []
            for idle in ticks:
                sample = dict.fromkeys((
                    "operations", "tsc_ticks", "core_cycles", "process_cycles", "thread_cycles", "core_enabled",
                    "core_running", "memory_before_private", "memory_after_private", "memory_cooldown_private",
                    "memory_peak_resident", "iterations"), 100)
                sample.update(wall_ns=wall_ns, thread_cpu_ns=wall_ns, process_cpu_ns=wall_ns, context_switches=0,
                              sibling_cpu=1, sibling_idle_cycles=idle)
                samples.append(sample)
            return {"duration_ms": 100, "samples": samples, "fixed_work": True}

        with mock.patch.object(FULL.method.os, "sysconf", return_value=100):
            # HEL1, 28.09: five samples of an idle sibling, 2+2+1+1+2 ticks of 9.7.
            self.assertTrue(FULL.method.record_metrics(record([2, 2, 1, 1, 2]), False)["sibling_idle_valid"])
            # A sibling busy half of every sample stays busy.
            self.assertFalse(FULL.method.record_metrics(record([0, 1, 0, 1, 0]), False)["sibling_idle_valid"])
            self.assertFalse(FULL.method.record_metrics(record([0, 0, 0, 0, 0]), False)["sibling_idle_valid"])

    def test_process_range_keeps_each_sides_tail_and_its_phase(self) -> None:
        case = FULL.Case("workloads", "binary-trees-depth-10", "codegen+mm", "Pascal", "single-cpu")
        measured = records([40.0, 40.2, 50.3, 40.1, 39.9, 40.4])
        for row in measured:
            row["case_definition"]["stack_rsp"] = f"{0x15F000 + 336 * row['repeat'] - 8:016X}"
        extremes = FULL.analyze_case(measured, case)["process_range"]["moon-candidate"]
        self.assertEqual((extremes["minimum"], extremes["maximum"]), (39.9, 50.3))
        self.assertEqual((extremes["minimum_phase"], extremes["maximum_phase"]), (1336, 664))

    def test_xperf_counters_are_joined_by_their_header_names(self) -> None:
        dump = Path(self.id().rsplit(".", 1)[-1] + ".txt")
        self.addCleanup(dump.unlink, missing_ok=True)
        dump.write_text(
            "Trace Start: 1000000\n"
            "SampledProfile, 200, bench.exe ( 1234), 55, 0x1\n"
            "Pmc, TimeStamp, ThreadID, TotalCycles, CacheMisses\n"
            + "".join(f"Pmc, {50 + 100 * step}, 55, {1000 * step}, {10 * step}\n" for step in range(4)),
            encoding="utf-8",
        )
        sample = {"trace_start_100ns": 1000000 + 1000, "trace_stop_100ns": 1000000 + 3000}
        record = {"pid": 1234, "program": "p", "case": "c", "category": "single-cpu", "samples": [sample]}
        FULL.method.attach_windows_core_cycles(dump, [record])
        self.assertEqual((sample["core_cycles"], sample["pmc"]), (2000, {"CacheMisses": 20}))
        self.assertEqual(CALIBRATION.l2_rate(record, lambda row: row["pmc"]["CacheMisses"]), 10.0)

    def test_batch_pair_passes_stack_phase(self) -> None:
        cases = [FULL.Case("move", "hot-a0-a0-n64", "rtl", "System", "memory-local")]
        images = {(system, "move", 0): Path(f"{system}.exe") for system in FULL.SYSTEMS}
        launched_phases = []

        def fake_run_many(executable, program, case_names, variant, repeat, duration,
                          category, affinity, log_dir, samples, warmup, timeout,
                          start_gate, ready_file, barrier, **kwargs):
            launched_phases.append(kwargs.get("stack_phase"))
            return [{
                "program": program, "case": case_names[0], "category": category,
                "affinity": affinity, "variant": variant, "repeat": repeat,
                "duration_ms": duration, "pid": 1, "process_seconds": 0.1,
                "executable": str(executable), "sha256": "a", "log": "log",
                "case_definition": {}, "samples": [sample()] * 3,
                "iterations": 100, "fixed_work": True, "stack_phase": kwargs.get("stack_phase"),
            }]

        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        with (
            mock.patch.object(FULL.method, "run_many", side_effect=fake_run_many),
            mock.patch.object(FULL.method, "record_metrics", return_value={"valid": True}),
        ):
            FULL.run_case_batch_pair(
                cases, 0, 6, images, (0, 2), directory, "tag", 0,
                {("move", "hot-a0-a0-n64"): (100, 6)}, stack_plan="grid",
            )
        self.assertEqual(launched_phases, [0, 0])

    def test_every_process_gets_the_runs_raw_events_and_the_chain(self) -> None:
        environments = []

        def launch(executable, selected, environment, *args):
            environments.append(environment)
            raise RuntimeError("stop after the environment")

        with (
            mock.patch.dict(os.environ, {"PULSE_STACK_PHASE": "999", "PULSE_RAW_CONFIGS": "0xc5"}),
            mock.patch.object(FULL.method, "launch", side_effect=launch),
        ):
            for run in (
                lambda: FULL.method.run_one(Path("t.exe"), "p", "c", "v", 0, 6, "single-cpu", (0,), Path(".")),
                lambda: FULL.method.run_many(Path("t.exe"), "p", ["c"], "v", 0, 6, "single-cpu", (0,),
                                             Path("."), 3, 2),
                lambda: FULL.method.run_one(Path("t.exe"), "p", "c", "v", 0, 6, "single-cpu", (0,), Path("."),
                                            raw_configs="0x4f2e"),
            ):
                with self.assertRaises(RuntimeError):
                    run()
        self.assertEqual([env.get("PULSE_RAW_CONFIGS") for env in environments], ["0xc5", "0xc5", "0x4f2e"])
        self.assertTrue(all(env["PULSE_CHAIN"] == "1" for env in environments))
        self.assertTrue(all("PULSE_STACK_PHASE" not in env for env in environments))

    def test_confirm_changes_passes_stack_plan(self) -> None:
        stages_called = []

        def fake_run_stage(cases, start, count, duration, images, single, multi,
                           cache, output, tag, **kwargs):
            stages_called.append(kwargs.get("stack_plan"))
            return []

        result = {
            "cases": {
                "codegen/dep-add": {
                    "program": "codegen", "case": "dep-add", "layer": "codegen",
                    "unit": "compiler", "category": "single-cpu",
                    "chosen_duration_ms": 6, "verdict": "WORSE",
                    "final": {"records": records([110.0] * 6),
                              "metrics": {"work_cycles_per_op": {"decision": "WORSE", "median": 1.1,
                                          "ratios": [1.1] * 6, "median_interval_95": [1.05, 1.15]}},
                              "primary_metrics": ("work_cycles_per_op",),
                              "valid_pairs": 6, "attempted_pairs": 6,
                              "stable": True, "semantic_match": True},
                },
            },
            "preflight": {"passed": True},
        }
        built = {
            "moon-baseline": {"codegen": Path("b.exe")},
            "moon-candidate": {"codegen": Path("c.exe")},
        }
        case_list = [FULL.Case("codegen", "dep-add", "codegen", "compiler", "single-cpu")]
        with (
            mock.patch.object(FULL, "run_stage", side_effect=fake_run_stage),
            mock.patch.object(FULL, "image_copies", return_value={}),
            mock.patch.object(FULL, "run_fast_preflight", return_value={"passed": True}),
            mock.patch.object(FULL.pulse_assessment, "ranked_changes",
                              return_value=[("codegen", "codegen/dep-add", 1.1)]),
        ):
            FULL.confirm_changes(result, built, case_list, (0, 2), (0,), {}, Path("out"),
                                 stack_plan="grid")
        self.assertTrue(stages_called)
        self.assertTrue(all(plan == "grid" for plan in stages_called))

    def test_run_fast_preflight_passes_stack_plan(self) -> None:
        stages_called = []

        def fake_run_stage(cases, start, count, duration, images, single, multi,
                           cache, output, tag, **kwargs):
            stages_called.append(kwargs.get("stack_plan"))
            return records([100.0] * 6)

        built = {"moon-candidate": {"calibration": Path("c.exe")}, "moon-baseline": {}}
        with (
            mock.patch.object(FULL, "run_stage", side_effect=fake_run_stage),
            mock.patch("shutil.copyfile"),
            mock.patch("shutil.copymode"),
        ):
            FULL.run_fast_preflight(built, (0, 2), (0,), Path("out"), stack_plan="fixed")
        self.assertEqual(stages_called, ["fixed"])

    def test_runner_judges_the_core_before_and_the_sibling_during_the_process(self) -> None:
        for work_only in (True, False):
            for label, runner, core, sibling in (
                ("quiet", QUIET, True, True),
                ("sibling busy half the life", HALF_BUSY_SIBLING, True, False),
                ("core busy before", BUSY_CORE, False, True),
                ("not single-CPU", {}, True, True),
            ):
                with self.subTest(label, work_only=work_only):
                    metrics = FULL.method.record_metrics(process("A", 0, runner), False, work_only=work_only)
                    self.assertEqual((metrics["core_idle_valid"], metrics["lifetime_sibling_valid"]),
                                     (core, sibling))
                    self.assertEqual(metrics["valid"], core and sibling)

    def test_idle_is_a_share_of_the_clock_it_is_counted_in(self) -> None:
        # Windows keeps idle in TSC ticks: 95% of a 3.8 GHz second is 0.95, not 3.61.
        idle = iter((0, 3_610_000_000))
        tsc = iter((0, 0, 3_800_000_000, 3_800_000_000))
        with (
            mock.patch.object(FULL.method.os, "name", "nt"),
            mock.patch.object(FULL.method, "read_processor_idle_cycles", side_effect=lambda cpu: next(idle)),
            mock.patch.object(FULL.method, "tsc_reader", return_value=lambda: next(tsc)),
        ):
            window = FULL.method.idle_since(12, FULL.method.idle_mark(12))
            self.assertEqual(window, [3_610_000_000, 3_800_000_000])
            self.assertTrue(FULL.method.idle_enough(window, 0.95))
            self.assertFalse(FULL.method.idle_enough(window, 0.99))
            self.assertTrue(FULL.method.idle_enough([9, 10], 0.9))
            self.assertFalse(FULL.method.idle_enough([9, 10], 0.99))
        with mock.patch.object(FULL.method.os, "name", "posix"):
            # Linux idle moves in whole clock ticks: one tick of the life is not a busy sibling.
            self.assertTrue(FULL.method.idle_enough([9, 10], 0.99))
            self.assertFalse(FULL.method.idle_enough([5, 10], 0.99))
            self.assertFalse(FULL.method.idle_enough([0, 3], 0.99))
        self.assertTrue(FULL.method.idle_enough(None, 0.99))

    def test_an_idle_read_takes_the_clock_of_its_own_moment(self) -> None:
        # The runner loses the CPU between its TSC read and the query (a 1.3 ms gap): that
        # read is repeated, the kept one sits between two close TSC reads, at their midpoint.
        idle = iter((500, 900))
        tsc = iter((0, 5_000_000, 5_000_100, 5_000_300))
        with (
            mock.patch.object(FULL.method.os, "name", "nt"),
            mock.patch.object(FULL.method, "read_processor_idle_cycles", side_effect=lambda cpu: next(idle)),
            mock.patch.object(FULL.method, "tsc_reader", return_value=lambda: next(tsc)),
        ):
            self.assertEqual(FULL.method.idle_mark(12), (900, 5_000_200))

    def test_both_launch_paths_carry_the_runner_to_every_record(self) -> None:
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        executable = directory / "t.exe"
        executable.write_bytes(b"MZ")
        output = "\n".join([
            *(line for name in ("a", "b") for line in (
                f"PULSE_CASE program=p case={name} oracle=1",
                f"PULSE_SAMPLE program=p case={name} sample=1 iterations=5 operations=5")),
            "PULSE_END program=p status=PASS",
        ])
        # CPU 12 is a label here: its sibling is not read from a machine that may have no CPU 12.
        sibling = mock.patch.object(FULL.method, "processor_sibling", return_value=None)
        with sibling, mock.patch.object(FULL.method, "launch", return_value=(output, 0, 7, 0.1, QUIET)):
            batch = FULL.method.run_many(executable, "p", ["a", "b"], "v", 0, 6, "single-cpu", (12,),
                                         directory, 1, 1)
        with sibling, mock.patch.object(FULL.method, "launch",
                                        return_value=("\n".join(output.splitlines()[:2] + [output.splitlines()[-1]]), 0, 7, 0.1,
                                                      QUIET)):
            single = FULL.method.run_one(executable, "p", "a", "v", 0, 6, "single-cpu", (12,), directory,
                                         samples_per_process=1)
        self.assertEqual([record["runner"] for record in batch + [single]], [QUIET] * 3)

    def test_launch_watches_the_core_before_and_the_sibling_during_the_process(self) -> None:
        events = []

        class Child:
            pid, returncode = 7, 0

        class Watch:
            def before(self, cpu):
                events.append(f"before {cpu}")
                return {"core_idle": [9, 10], "core_rest": [5, 5]}

            def mark(self, cpu):
                events.append(f"began {cpu}")
                return (1.0, 10.0, 3)

            def after(self, cpu, began, busy):
                events.append(f"after {cpu} {began} {busy}")

        def since(cpu, start):
            events.append(f"since {cpu}")
            return [9, 10]

        with (
            mock.patch.object(FULL.method, "keep_runner_off", side_effect=lambda cpu: events.append(f"off {cpu}")),
            mock.patch.object(FULL.method, "processor_sibling", side_effect=lambda cpu: cpu + 1),
            mock.patch.object(FULL.method, "CORE_WATCH", Watch()),
            mock.patch.object(FULL.method, "idle_mark", side_effect=lambda cpu: events.append(f"mark {cpu}") or (0, 0)),
            mock.patch.object(FULL.method, "idle_since", side_effect=since),
            mock.patch.object(FULL.method.time, "sleep", side_effect=lambda seconds: events.append(f"sleep {seconds}")),
            mock.patch.object(FULL.method, "spawn_benchmark",
                              side_effect=lambda *args: events.append("spawn") or Child()),
            mock.patch.object(FULL.method, "finish",
                              side_effect=lambda child, timeout: events.append("exit") or ("PULSE_END", 42.0)),
        ):
            _, code, pid, _, runner = FULL.method.launch(
                Path("t.exe"), "c", {}, "single-cpu", (12,), 5.0, None, None, None, "t")
            # No sleep of its own: the watch decides when the core may take the process.
            self.assertEqual(events, ["off 12", "before 12", "mark 13", "began 12", "spawn", "exit",
                                      "after 12 (1.0, 10.0, 3) 42.0", "since 13"])
            self.assertEqual(runner, {"core_cpu": 12, "core_idle": [9, 10], "core_rest": [5, 5], "own_busy": 42.0,
                                      "sibling_cpu": 13, "sibling_idle": [9, 10]})
            self.assertEqual((code, pid), (0, 7))
            events.clear()
            *_, runner = FULL.method.launch(
                Path("t.exe"), "c", {}, "multithread", (0, 2, 4), 5.0, None, None, None, "t")
            self.assertEqual((events, runner), (["spawn", "exit"], {}))

    def test_a_process_that_fails_leaves_its_time_as_foreign_work(self) -> None:
        after = []

        class Watch:
            def before(self, cpu):
                return {"core_idle": [10, 10]}

            def mark(self, cpu):
                return (1.0, 10.0, 3)

            def after(self, cpu, began, busy):
                after.append(busy)

        class Child:
            pid, returncode = 7, None

            def poll(self):
                return None

            def kill(self):
                pass

            def communicate(self):
                return "", None

        def failing(child, timeout):
            raise OSError("pipe")

        with (
            mock.patch.object(FULL.method, "keep_runner_off"),
            mock.patch.object(FULL.method, "processor_sibling", return_value=None),
            mock.patch.object(FULL.method, "CORE_WATCH", Watch()),
            mock.patch.object(FULL.method, "spawn_benchmark", return_value=Child()),
            mock.patch.object(FULL.method, "finish", side_effect=failing),
        ):
            with self.assertRaises(OSError):
                FULL.method.launch(Path("t.exe"), "c", {}, "single-cpu", (12,), 5.0, None, None, None, "t")
        self.assertEqual(after, [0.0])

    @unittest.skipUnless(os.name == "nt", "the runner reads the TSC itself only on Windows")
    def test_runner_reads_the_tsc_at_a_plausible_rate(self) -> None:
        started, first = time.perf_counter(), FULL.method.tsc_reader()()
        time.sleep(0.05)
        stopped, second = time.perf_counter(), FULL.method.tsc_reader()()
        self.assertTrue(0.5e9 < (second - first) / (stopped - started) < 10e9)

    def test_both_paths_repeat_a_pair_whose_core_the_runner_rejected(self) -> None:
        case = FULL.Case("codegen", "dep-add", "codegen", "compiler", "single-cpu")
        batch = [FULL.Case("move", "hot-a0-a0-n64", "rtl", "System", "memory-local")]
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        for label, first in (("sibling busy", HALF_BUSY_SIBLING), ("core busy", BUSY_CORE), ("quiet", QUIET)):
            calls = {system: 0 for system in FULL.SYSTEMS}

            def runner(variant: str) -> dict[str, object]:
                calls[variant] += 1
                return first if variant == FULL.SYSTEMS[0] and calls[variant] == 1 else QUIET

            def run_one(executable, program, name, variant, repeat, *args, **kwargs):
                return process(variant, repeat, runner(variant), log=f"{variant}-{calls[variant]}.log")

            def run_many(executable, program, names, variant, repeat, *args, **kwargs):
                return [process(variant, repeat, runner(variant), case=names[0],
                                log=f"{variant}-{calls[variant]}.log")]

            with self.subTest(label), mock.patch.object(FULL.method, "run_one", side_effect=run_one):
                pair = FULL.run_pair(case, 0, 6, mock.MagicMock(), (0, 2), (0,),
                                     {(case.program, case.name): (100, 6)}, directory, "cpu", False, 0)
                self.assert_repeated(pair, first is not QUIET)
            calls = {system: 0 for system in FULL.SYSTEMS}
            with self.subTest(label + ", batch"), mock.patch.object(FULL.method, "run_many", side_effect=run_many):
                pair = FULL.run_case_batch_pair(batch, 0, 6, mock.MagicMock(), (0, 2), directory, "tag", 0,
                                                {("move", "hot-a0-a0-n64"): (100, 6)})
                self.assert_repeated(pair, first is not QUIET)

    def assert_repeated(self, pair: list[dict[str, object]], repeated: bool) -> None:
        self.assertEqual(len(pair), 2)
        self.assertTrue(all(record["accepted"] for record in pair))
        self.assertEqual({record["pair_attempt"] for record in pair}, {int(repeated)})
        rejected = pair[0]["rejected_pair_attempts"]
        self.assertEqual(len(rejected), 2 if repeated else 0)
        self.assertEqual(sum(not entry["derived"]["valid"] for entry in rejected), int(repeated))
        self.assertTrue(all(entry["runner"] for entry in rejected))

    def test_measurements_and_report_count_what_the_runner_rejected(self) -> None:
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        judged = records([97.0] * 6)
        rejected_attempt = [
            {"attempt": 0, "variant": "moon-baseline", "log": "b0.log", "runner": HALF_BUSY_SIBLING,
             "derived": {"valid": False, "core_idle_valid": True, "lifetime_sibling_valid": False}},
            {"attempt": 0, "variant": "moon-candidate", "log": "c0.log", "runner": QUIET,
             "derived": {"valid": True, "core_idle_valid": True, "lifetime_sibling_valid": True}},
        ]
        for index, record in enumerate(judged):
            record.update(runner=QUIET, log=f"{index}.log",
                          rejected_pair_attempts=rejected_attempt if record["repeat"] == 0 else [])
            record["derived"].update(core_idle_valid=True, lifetime_sibling_valid=True)
        rule = {"horizon_seconds": 2.0, "idle_ratio": 0.95, "rest_seconds": 0.05, "sibling_ratio": 0.99}
        for label, case_records, watch, measurement, report in (
            ("judged", judged, rule,
             "Runner: no single-CPU process started on a core that ran foreign work in the 2 s before it "
             "(under 95% idle once the runner's own processes are taken out) or that was not idle 50 ms since "
             "its own last process; rejected `1` of `14` processes (core not clean before: `0`, SMT sibling "
             "under 99% idle during: `1`); a rejected pair is repeated within its three attempts.",
             "ни один одноядерный процесс не стартовал на ядре, где за 2 с до него шла чужая работа (свои "
             "процессы раннера вычтены) или которое после своего прошлого процесса простояло меньше 50 мс; "
             "отвергнуто стендом процессов 1 из 14 (ядро не простаивало перед процессом — 0, "
             "SMT-сосед был занят во время процесса — 1); отвергнутая пара повторяется в пределах трёх попыток."),
            ("judged by the 2 s sleep before the watch", judged, None,
             "Runner: every single-CPU process started after its core was watched 2 s idle; rejected `1` of "
             "`14` processes (core not clean before: `0`, SMT sibling under 99% idle during: `1`); "
             "a rejected pair is repeated within its three attempts.",
             "перед каждым одноядерным процессом ядро замера 2 с проверялось на простой; "
             "отвергнуто стендом процессов 1 из 14"),
            ("before the runner judged the core", records([97.0] * 6), None,
             "Runner: the core's idle before each process and its SMT sibling during it were not recorded.",
             None),
        ):
            with self.subTest(label):
                saved = {
                    "baseline_toolchain": {"backend_sha256": "r"},
                    "candidate_toolchain": {"backend_sha256": "c"},
                    "machine": {"platform": "p", "cpu_work_unit": "u", "multithread_topology": "t"},
                    "cases": {"codegen/dep-add": {
                        "program": "codegen", "case": "dep-add", "layer": "codegen", "unit": "compiler",
                        "category": "single-cpu", "chosen_duration_ms": 6, "final": {"records": case_records},
                    }},
                    "elapsed_seconds": 1.0, "stack_phase": "grid", "scaling": [], "placement_errors": [],
                    "l2_calibration": None,
                    **({"core_watch": watch} if watch else {}),
                }
                source = directory / f"{label}.json"
                source.write_text(json.dumps(saved), encoding="utf-8")
                output = directory / label
                REANALYZE.reanalyze(source, output)
                self.assertIn("\n" + measurement + "\n", (output / "MEASUREMENTS.md").read_text(encoding="utf-8"))
                text = (output / "REPORT.md").read_text(encoding="utf-8")
                # The time of the pass is in the report as well as in MEASUREMENTS.md.
                self.assertIn("проход занял 0.0 мин", text)
                if report is None:
                    self.assertNotIn("отвергнуто стендом", text)
                else:
                    self.assertIn(report, text)

    def test_calibration_writes_nothing_it_has_not_proven(self) -> None:
        cases = {
            "calibration": {"asm-dependent-add": {"layer": "calibration"}},
            "codegen": {"dep-add": {"layer": "codegen"}},
            "workloads": {"stream-copy": {"layer": "memory"}, "stream-scale": {"layer": "memory"},
                          "binary-trees-depth-10": {"layer": "codegen+mm"}},
        }
        good = {"calibration/asm-dependent-add": 0.1, "codegen/dep-add": 0.07,
                "workloads/stream-copy": 3.4, "workloads/stream-scale": 3.6,
                "workloads/binary-trees-depth-10": 0.5}
        threshold = FULL.L2_EXCLUSIVE_PER_KCYCLE
        # Within 1e-4 of the threshold: rounded to four digits, both land on it.
        over, under = threshold + 0.00003, threshold - 0.00003
        directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, directory)
        table = directory / "table.json"
        for index, (label, rates, programs, contaminated, published, named) in enumerate((
            ("register control over the threshold", {**good, "codegen/dep-add": 0.98}, cases, (), False,
             "codegen/dep-add"),
            ("register control at the threshold: under it is required",
             {**good, "codegen/dep-add": threshold}, cases, (), False, "codegen/dep-add"),
            ("register control a rounding step over the threshold",
             {**good, "codegen/dep-add": over}, cases, (), False, "codegen/dep-add"),
            ("stream under the threshold: the event does not see the traffic",
             {**good, "workloads/stream-copy": 0.15}, cases, (), False, "workloads/stream-copy"),
            ("stream at the threshold: over it is required",
             {**good, "workloads/stream-copy": threshold}, cases, (), False, "workloads/stream-copy"),
            ("a non-control case stays exclusive after three contaminated processes", good, cases,
             ("workloads/binary-trees-depth-10",), True, None),
            ("a required stream control stays contaminated", good, cases, ("workloads/stream-copy",), False,
             "workloads/stream-copy"),
            ("one register-only control not measured", good,
             {name: cases[name] for name in ("codegen", "workloads")}, (), False, "calibration/asm-dependent-add"),
            ("no register-only control measured", good, {"workloads": cases["workloads"]}, (), False,
             "codegen/dep-add"),
            ("no stream control measured", good, {name: cases[name] for name in ("calibration", "codegen")},
             (), False, "workloads/stream-"),
            ("proven", good, cases, (), True, None),
            ("proven a rounding step under the threshold, written as judged",
             {**good, "codegen/dep-add": under}, cases, (), True, None),
        )):
            before = {"schema": 2, "other": {"event": "0x4f2e", "cases": {"x/y": 1.0}},
                      "stand": {"event": "old", "cases": {"x/y": 9.0}}}
            table.write_text(json.dumps(before), encoding="utf-8")
            launched = []

            def run_one(executable, program, name, *args, **kwargs):
                launched.append(f"{program}/{name}")
                return {"program": program, "case": name, "samples": []}

            def record_metrics(record, multithread, work_only=False):
                # Judged like a Pulse process: counters, core before, sibling during.
                self.assertTrue(work_only)
                return {"valid": f"{record['program']}/{record['case']}" not in contaminated}

            arguments = ["pulse_l2_calibration.py", "--toolchain", str(directory), "--event", "0x0964",
                         "--output", str(directory / f"run{index}"), "--table", str(table),
                         "--programs", ",".join(programs), "--cpu", "3"]
            with (
                self.subTest(label),
                mock.patch.object(sys, "argv", arguments),
                mock.patch.object(CALIBRATION.pulse, "build_moon", side_effect=lambda program, *a, **k: Path(program)),
                mock.patch.object(CALIBRATION.pulse_full, "discover", side_effect=lambda exe: programs[exe.name]),
                mock.patch.object(CALIBRATION.pulse_full, "benchmark_cpu_sets", return_value=((2, 3), (0,))),
                mock.patch.object(CALIBRATION.method, "windows_machine_settings", contextlib.nullcontext),
                mock.patch.object(CALIBRATION.method, "linux_machine_settings", contextlib.nullcontext),
                mock.patch.object(CALIBRATION.method, "xperf_start"),
                mock.patch.object(CALIBRATION.method, "xperf_stop"),
                mock.patch.object(CALIBRATION.method, "attach_windows_core_cycles"),
                mock.patch.object(CALIBRATION.method, "run_one", side_effect=run_one),
                mock.patch.object(CALIBRATION.method, "keep_runner_off"),
                mock.patch.object(CALIBRATION.method, "record_metrics", side_effect=record_metrics),
                mock.patch.object(CALIBRATION, "l2_rate",
                                  side_effect=lambda record, _: rates[f"{record['program']}/{record['case']}"]),
                mock.patch.object(CALIBRATION.pulse, "moon_toolchain_identity",
                                  return_value={"backend_sha256": "t"}),
                mock.patch.object(CALIBRATION.platform, "node", return_value="stand"),
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()) as errors,
            ):
                self.assertEqual(CALIBRATION.run(), 0 if published else 1)
                after = json.loads(table.read_text(encoding="utf-8"))
                self.assertFalse(table.with_name(table.name + ".tmp").exists())
                self.assertEqual(after["other"], before["other"])
                if published:
                    self.assertEqual(after["stand"]["cases"],
                                     {name: rate for name, rate in rates.items() if name in launched and name not in contaminated})
                    self.assertEqual(after["stand"]["unclean"], list(contaminated))
                    self.assertEqual(after["stand"]["event"], "0x0964")
                    with mock.patch.object(FULL.platform, "node", return_value="stand"):
                        measured, _ = FULL.l2_calibration([
                            FULL.Case("workloads", "binary-trees-depth-10", "codegen+mm", "compiler", "single-cpu")
                        ], table)
                    if contaminated:
                        self.assertIsNone(measured[0].l2_misses_per_kcycle)
                        self.assertTrue(measured[0].exclusive)
                else:
                    self.assertEqual(after, before)
                    refused = [line for line in errors.getvalue().splitlines() if line.startswith("PULSE_L2_REFUSED")]
                    self.assertTrue(any(named in line for line in refused), refused)
                self.assertEqual(launched.count("workloads/binary-trees-depth-10"),
                                 3 if "workloads/binary-trees-depth-10" in contaminated else int("workloads" in programs))

    def test_a_hybrid_cpu_is_measured_on_its_big_cores(self) -> None:
        # INTEL3: cpu_core 0-15 (8 P-cores, SMT), cpu_atom 16-31; the harness's cycle
        # counter does not run on an E-core, so no Pulse process may land there.
        pmus = {"/sys/devices/cpu_core/cpus": "0-15" + chr(10), "/sys/devices/cpu_atom/cpus": "16-31" + chr(10)}

        def read_text(path, *args, **kwargs):
            return pmus[path.as_posix()]

        with (
            mock.patch.object(FULL.method.os, "sched_getaffinity", return_value=set(range(32)), create=True),
            mock.patch.object(FULL.method.Path, "is_file", lambda path: path.as_posix() in pmus),
            mock.patch.object(FULL.method.Path, "read_text", read_text),
        ):
            self.assertEqual(FULL.method.linux_measurement_cpus(), set(range(16)))
        self.assertEqual(FULL.method.cpu_list("0-3,8,10-11" + chr(10)), {0, 1, 2, 3, 8, 10, 11})
        # Not hybrid: every allowed CPU.
        with (
            mock.patch.object(FULL.method.os, "sched_getaffinity", return_value={0, 1, 2, 3}, create=True),
            mock.patch.object(FULL.method.Path, "is_file", lambda path: False),
        ):
            self.assertEqual(FULL.method.linux_measurement_cpus(), {0, 1, 2, 3})

    def test_a_rejected_calibration_case_moves_to_another_core(self) -> None:
        cases = [("p", f"c{index}", "single-cpu") for index in range(6)]
        runs: list[tuple[str, int]] = []

        def measure(index, case, cpu):
            runs.append((case[1], cpu))
            # Core 5's sibling stays busy: nothing measured there is clean.
            return None if cpu == 5 else {"case": case[1]}

        measured, unclean = CALIBRATION.spread_over_cores(cases, [3, 5, 7], measure, 3)
        self.assertEqual(sorted(record["case"] for record in measured.values()), [case[1] for case in cases])
        self.assertEqual(unclean, [])
        for name in {name for name, cpu in runs if cpu == 5}:
            self.assertEqual([cpu for run, cpu in runs if run == name][0], 5)
            self.assertNotIn(5, [cpu for run, cpu in runs if run == name][1:])
        # A case every core rejects is given up after its attempts, on different cores.
        runs.clear()
        measured, unclean = CALIBRATION.spread_over_cores(cases[:1], [3, 5, 7], lambda *args: runs.append(args[2]), 3)
        self.assertEqual((measured, unclean, sorted(runs)), ({}, ["p/c0"], [3, 5, 7]))

    def test_a_dirty_pair_of_cores_waits_while_a_clean_one_works(self) -> None:
        dirty = {0}
        pool = FULL.PairPool([(0, 1), (2, 3)], quiet=lambda cpu: cpu not in dirty)
        used: list[tuple[int, int]] = []

        def work(index, task, pair):
            used.append(pair)
            time.sleep(0.01)
            return pair

        FULL.on_cpu_pairs(list(range(6)), pool, work)
        self.assertEqual(set(used), {(2, 3)})
        # Every pair free and none clean for the horizon: the first goes, to be judged as always.
        dirty.update({1, 2, 3})
        with mock.patch.object(FULL.method, "MEASUREMENT_CORE_IDLE_SECONDS", 0.1):
            started = time.monotonic()
            self.assertEqual(pool.take(), (0, 1))
            self.assertGreaterEqual(time.monotonic() - started, 0.1)

    def test_a_case_spreads_its_pairs_over_the_stage(self) -> None:
        cases = [FULL.Case("codegen", f"c{index}", "codegen", "compiler", "single-cpu", 0.0) for index in range(3)]
        calls: list[tuple[str, int]] = []
        lock = __import__("threading").Lock()

        def run_pair(case, repeat, *args, **kwargs):
            with lock:
                calls.append((case.name, repeat))
            return []

        for pairs in ((0, 2), (0, 2, 4, 6)):
            calls.clear()
            with (
                self.subTest(pairs=pairs),
                mock.patch.object(FULL, "run_pair", side_effect=run_pair),
                mock.patch.object(FULL, "PairPool", functools.partial(FULL.PairPool, quiet=lambda cpu: True)),
            ):
                FULL.run_stage(cases, 0, 4, 6, {}, pairs, (0,), {}, Path("out"), "tag")
            # Round 0 (with each case's calibration) whole before any later pair.
            self.assertEqual(sorted(calls[:3]), [("c0", 0), ("c1", 0), ("c2", 0)])
            self.assertEqual(sorted(calls), sorted((f"c{index}", repeat) for index in range(3) for repeat in range(4)))
            if len(pairs) == 2:
                # One pair of cores: strictly round by round.
                self.assertEqual(calls, [(f"c{index}", repeat) for repeat in range(4) for index in range(3)])

    def test_sample_chain_gives_the_core_clock_and_core_cycles(self) -> None:
        # The shorter chain is the clock, whether it ran before the sample or after it.
        for before, after in ((52_000, 53_000), (53_000, 52_000)):
            with self.subTest(before=before, after=after):
                chained = FULL.method.sample_metrics(
                    sample(operations=1000, tsc_ticks=2_000_000, thread_cycles=1_990_000, core_cycles=2_400_000,
                           chain_before=before, chain_after=after), False, 2, fixed_work=True)
                self.assertAlmostEqual(chained["chain_frequency_ratio"], 65536 / 52_000)
                # Windows counts the thread in TSC ticks: at the chain's clock they are core cycles;
                # Linux counts core cycles already.
                core_per_op = 1_990_000 * 65536 / 52_000 / 1000 if os.name == "nt" else 2_400_000 / 1000
                self.assertAlmostEqual(chained["work_cycles_per_op"], core_per_op)
                self.assertAlmostEqual(chained["thread_cycles_per_op"], 1_990)
        # The unit a result carries is the one computed here.
        self.assertIn("core-cycles/op" if os.name == "nt" else "hardware-cycles/op", FULL.method.CPU_WORK_UNIT)
        self.assertEqual(FULL.machine_description((12,), (0, 2))["cpu_work_unit"], FULL.method.CPU_WORK_UNIT)
        plain = FULL.method.sample_metrics(sample(operations=1000, thread_cycles=1_990_000, core_cycles=2_400_000),
                                           False, 2, fixed_work=True)
        self.assertEqual(plain["chain_frequency_ratio"], 0.0)
        self.assertAlmostEqual(plain["work_cycles_per_op"], 1_990 if os.name == "nt" else 2_400)

    def test_a_chain_torn_by_an_interrupt_leaves_the_process_cost_clean(self) -> None:
        # An interrupt inside a 17 us chain only lengthens it (audit r6, aos: 199614 ticks against 66006):
        # two of a process's three samples with one torn chain each, and it costs what a clean one does.
        clean = 66_006
        record = {"duration_ms": 6, "fixed_work": True, "samples": [
            sample(operations=1000, tsc_ticks=2_000_000, thread_cycles=2_000_000,
                   chain_before=before, chain_after=after)
            for before, after in ((clean, 199_614), (72_580, clean), (clean, clean))]}
        with mock.patch.object(FULL.method.os, "name", "nt"):
            metrics = FULL.method.record_metrics(record, False)
        self.assertAlmostEqual(metrics["work_cycles_per_op"], 2_000_000 * 65536 / clean / 1000)

    @unittest.skipUnless(os.name == "nt" or shutil.which("taskset"), "needs process affinity")
    def test_runner_leaves_the_measurement_core_and_its_sibling(self) -> None:
        script = ALLOWED_CPUS + (
            "import sys\n"
            "sys.path.insert(0, sys.argv[1])\n"
            "import qualify_measurement_method as method\n"
            "before = allowed()\n"
            "sibling = method.processor_sibling(before[-1])\n"
            "remaining = set(before) - {before[-1], sibling}\n"
            "if remaining:\n"
            "    method.keep_runner_off(before[-1])\n"
            "else:\n"
            "    try:\n"
            "        method.keep_runner_off(before[-1])\n"
            "    except RuntimeError as error:\n"
            "        assert 'no CPU is left for the runner' in str(error), error\n"
            "    else:\n"
            "        raise AssertionError('empty runner affinity was accepted')\n"
            "print(json.dumps([before, sibling, allowed()]))\n"
        )
        done = subprocess.run([sys.executable, "-c", script, str(MODULE_PATH.parent)],
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        before, sibling, after = json.loads(done.stdout)
        remaining = set(before) - {before[-1], sibling}
        self.assertEqual(set(after), remaining or set(before))

    @unittest.skipUnless(os.name == "nt" or shutil.which("taskset"), "needs process affinity")
    def test_benchmark_starts_on_its_cpu_while_the_runner_stays(self) -> None:
        namespace: dict[str, object] = {}
        exec(ALLOWED_CPUS, namespace)
        allowed = namespace["allowed"]
        runner = allowed()
        during = []
        create = subprocess.Popen

        def watched(*args, **kwargs):
            during.append(allowed())
            return create(*args, **kwargs)

        with mock.patch.object(FULL.method.subprocess, "Popen", side_effect=watched):
            child = FULL.method.spawn_benchmark(
                [sys.executable, "-c", ALLOWED_CPUS + "print(json.dumps(allowed()))\n"], dict(os.environ),
                (runner[0],))
        output, _ = child.communicate(timeout=60)
        self.assertEqual(child.returncode, 0, output)
        self.assertEqual(json.loads(output), [runner[0]])
        # The runner never moved onto the benchmark's CPU, not even to create it.
        self.assertEqual(during, [runner])
        self.assertEqual(allowed(), runner)


class FakeCores:
    """The idle of three CPUs in microseconds on a clock the test moves: every
    second of `run` on a CPU is a second it was not idle."""

    def __init__(self) -> None:
        self.now = 0.0
        self.busy: dict[int, list[tuple[float, float]]] = {}

    def run(self, cpu: int, start: float, end: float) -> None:
        self.busy.setdefault(cpu, []).append((start, end))

    def idle(self, cpu: int) -> int:
        busy = sum(max(0.0, min(end, self.now) - start) for start, end in self.busy.get(cpu, ()) if start < self.now)
        return round((self.now - busy) * 1e6)

    def read(self) -> tuple[float, float, dict[int, int]]:
        return self.now, self.now * 1e6, {cpu: self.idle(cpu) for cpu in (0, 1, 2)}

    def sleep(self, seconds: float) -> None:
        self.now += seconds

    def watch(self):
        watch = FULL.method.CoreWatch(horizon=2.0, interval=0.01, reader=self.read, sleeper=self.sleep)
        watch.thread = object()  # the test reads instead of a thread
        return watch

    def advance(self, watch, until: float) -> None:
        while self.now < until - 1e-9:
            watch.sample()
            self.now = min(until, self.now + 0.01)
        watch.sample()

    def own(self, watch, cpu: int, start: float, end: float, cpu_seconds: float | None = None) -> None:
        """The runner's process on `cpu` from `start` to `end`, busy all its life."""
        self.advance(watch, start)
        began = watch.mark(cpu)
        self.run(cpu, start, end)
        self.advance(watch, end)
        watch.after(cpu, began, (end - start if cpu_seconds is None else cpu_seconds) * 1e6)


class CoreWatchTests(unittest.TestCase):
    """What the runner knows of a core before it starts a process there."""

    def judged(self, runner: dict[str, object]) -> bool:
        record = process("A", 0, {**runner, "sibling_cpu": 13, "sibling_idle": [1000, 1000]})
        return bool(FULL.method.record_metrics(record, False, work_only=True)["core_idle_valid"])

    def test_a_quiet_core_waits_only_for_its_first_horizon(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.advance(watch, 2.1)
        runner = watch.before(0, rest=0.05)
        self.assertAlmostEqual(cores.now, 2.1, places=6)
        self.assertEqual(runner["core_idle"][0], runner["core_idle"][1])
        self.assertGreaterEqual(runner["core_window"]["seconds"], 2.0)
        self.assertTrue(self.judged(runner))
        # No read two seconds back yet: the first process of a run waits the horizon.
        fresh = FakeCores()
        early = fresh.watch()
        early.sample()
        early.before(1, rest=0.05)
        self.assertGreaterEqual(fresh.now, 2.0)

    def test_foreign_work_in_the_horizon_is_waited_out(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.run(0, 1.4, 1.9)  # half a second of someone else's work
        cores.advance(watch, 2.1)
        runner = watch.before(0, rest=0.05)
        # Not before all but 5% of the window (100 ms) of the busy half second has left it.
        self.assertGreaterEqual(cores.now, 3.8 - 0.011)
        self.assertLessEqual(runner["core_window"]["foreign"], 0.05 * runner["core_window"]["elapsed"])
        self.assertTrue(self.judged(runner))

    def test_a_core_that_stays_busy_starts_its_process_dirty(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.run(0, 0.0, 100.0)
        cores.advance(watch, 2.1)
        runner = watch.before(0, rest=0.05)
        self.assertLess(cores.now, 2.1 + 2.0 + 0.05 + 1.0 + 0.1)
        self.assertFalse(self.judged(runner))

    def test_the_runners_own_process_is_not_foreign_work(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.own(watch, 0, 1.0, 1.5)
        cores.advance(watch, 2.6)
        runner = watch.before(0, rest=0.05)
        self.assertAlmostEqual(cores.now, 2.6, places=6)
        window = runner["core_window"]
        self.assertAlmostEqual(window["own"], 0.5e6)
        self.assertAlmostEqual(window["foreign"], 0.0, delta=1e4)
        self.assertTrue(self.judged(runner))
        # A process whose CPU time is unknown (it failed) counts as foreign work.
        other = FakeCores()
        failed = other.watch()
        other.own(failed, 0, 1.0, 1.5, cpu_seconds=0.0)
        other.advance(failed, 2.6)
        failed.before(0, rest=0.05)
        self.assertGreaterEqual(other.now, 3.5 - 0.011)

    def test_the_window_never_starts_inside_an_own_process(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.own(watch, 0, 1.0, 1.5)
        cores.advance(watch, 3.2)
        # 3.2 - 2 s falls at 1.2, inside the process: the window takes it whole.
        window = watch.window(0, watch.mark(0))
        self.assertAlmostEqual(window["seconds"], 2.2, delta=0.011)
        self.assertAlmostEqual(window["own"], 0.5e6)
        self.assertAlmostEqual(window["foreign"], 0.0, delta=1e4)

    def test_the_core_rests_after_its_own_process(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.own(watch, 0, 2.5, 3.0)
        runner = watch.before(0, rest=0.3)
        self.assertGreaterEqual(cores.now, 3.3 - 1e-9)
        self.assertGreaterEqual(runner["core_rest_seconds"], 0.3 - 1e-9)
        self.assertAlmostEqual(runner["core_rest"][0], runner["core_rest"][1], delta=1)
        self.assertTrue(self.judged(runner))

    def test_foreign_work_in_the_rest_is_waited_out(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.own(watch, 0, 2.5, 3.0)
        cores.run(0, 3.02, 3.06)  # 40 ms of someone else's work, under 5% of the horizon
        runner = watch.before(0, rest=0.1)
        # The window of 2 s tolerates 40 ms; the rest right before the process does not.
        self.assertLessEqual(runner["core_window"]["foreign"], 0.05 * runner["core_window"]["elapsed"])
        self.assertGreater(cores.now, 3.06 + 0.1 - 0.011)
        self.assertTrue(self.judged(runner))
        self.assertAlmostEqual(runner["core_rest"][0], runner["core_rest"][1], delta=1)

    def test_a_core_is_quiet_without_foreign_work_and_with_an_idle_sibling(self) -> None:
        cores = FakeCores()
        watch = cores.watch()
        cores.own(watch, 0, 1.0, 1.5)
        cores.advance(watch, 2.6)
        self.assertTrue(watch.quiet(0, 1))
        cores.run(1, 2.6, 2.9)  # the sibling busy
        cores.advance(watch, 3.0)
        self.assertFalse(watch.quiet(0, 1))
        cores.advance(watch, 4.0)  # a second of an idle sibling since
        self.assertTrue(watch.quiet(0, 1))
        cores.run(0, 4.0, 4.3)  # foreign work on the core itself
        cores.advance(watch, 4.5)
        self.assertFalse(watch.quiet(0, None))


# The CPUs this process may run on, for the runner-affinity tests.
ALLOWED_CPUS = """import json, os
def allowed():
    if os.name != "nt":
        return sorted(os.sched_getaffinity(0))
    import ctypes
    kernel32 = ctypes.windll.kernel32
    kernel32.GetCurrentProcess.restype = ctypes.c_void_p
    kernel32.GetProcessAffinityMask.argtypes = [
        ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t), ctypes.POINTER(ctypes.c_size_t)]
    mask, system = ctypes.c_size_t(), ctypes.c_size_t()
    kernel32.GetProcessAffinityMask(kernel32.GetCurrentProcess(), ctypes.byref(mask), ctypes.byref(system))
    return [cpu for cpu in range(64) if mask.value >> cpu & 1]
"""


class HarnessTests(unittest.TestCase):
    """The harness as the product toolchain builds it: list, chain, stack phase, data addresses, anchor."""

    QUICK = {"PULSE_SAMPLES": "3", "PULSE_ITERATIONS": "20", "PULSE_WARMUP_MS": "1"}

    @classmethod
    def setUpClass(cls) -> None:
        toolchain = FULL.pulse.ROOT / "toolchain"
        if not FULL.pulse.moon_toolchain_paths(toolchain)[1].is_file():
            raise unittest.SkipTest(f"the product toolchain is not built: {toolchain}")
        with mock.patch.object(FULL.pulse, "run", functools.partial(FULL.pulse.run, capture=True)):
            cls.executables = {
                program: FULL.pulse.build_moon(program, False, system="harness-test", toolchain=toolchain)
                for program in ("calibration", "move", "dictionary", "rtl", "repairs", "threads")
            }

    def run_pulse(self, program: str, *arguments: str, cpus: tuple[int, ...] | None = None,
                  **environment: str) -> tuple[int, list[dict[str, str]]]:
        variables = {name: value for name, value in os.environ.items() if not name.startswith("PULSE_")}
        variables.update(environment)
        command = [str(self.executables[program]), *arguments]
        if cpus is None:
            done = subprocess.run(command, env=variables, capture_output=True, text=True, timeout=120)
            code, output = done.returncode, done.stdout + done.stderr
        else:
            child = FULL.method.spawn_benchmark(command, variables, cpus)
            try:
                output, _ = child.communicate(timeout=120)
            except BaseException:
                child.kill()
                child.communicate()
                raise
            code = child.returncode
        lines = [{"kind": line.split()[0], "text": line, **FULL.method.fields(line)}
                 for line in output.splitlines() if line.strip()]
        return code, lines

    def test_list_needs_no_clock(self) -> None:
        for program in ("calibration", "move"):
            with self.subTest(program):
                code, lines = self.run_pulse(program, "list", "all")
                self.assertEqual(code, 0, lines[-3:])
                listed = [line["case"] for line in lines if line["kind"] == "PULSE_CASEDEF"]
                self.assertTrue(listed)
                self.assertEqual(lines[-1]["kind"], "PULSE_END")
                if program == "calibration":
                    self.assertEqual(listed, ["asm-dependent-add", "asm-mixed-integer",
                                              "asm-memory-read-64m", "asm-memory-write-64m"])

    @unittest.skipUnless(os.name == "nt" or shutil.which("taskset"), "needs process affinity")
    def test_list_needs_no_workers_but_running_them_requires_reserved_cpus(self) -> None:
        namespace: dict[str, object] = {}
        exec(ALLOWED_CPUS, namespace)
        cpus = (namespace["allowed"]()[0],)
        for program, case, count in (("repairs", "padded-counters-4", "five"),
                                     ("threads", "independent-cpu-1", "eight")):
            with self.subTest(program=program):
                code, lines = self.run_pulse(program, "list", "all", cpus=cpus)
                self.assertEqual(code, 0, lines[-3:])
                self.assertIn(case, [line["case"] for line in lines if line["kind"] == "PULSE_CASEDEF"])
                self.assertEqual(lines[-1]["kind"], "PULSE_END")
                selections = (case, "raise-catch," + case) if program == "repairs" else (case,)
                for selected in selections:
                    code, lines = self.run_pulse(program, "quick", selected, cpus=cpus, **self.QUICK)
                    self.assertNotEqual(code, 0)
                    self.assertIn(count + " available logical CPUs", " ".join(line["text"] for line in lines))

    def test_chain_brackets_every_sample_only_when_asked(self) -> None:
        quick = {"PULSE_SAMPLES": "3", "PULSE_ITERATIONS": "10000", "PULSE_WARMUP_MS": "1"}
        for chain in ("1", ""):
            with self.subTest(chain=chain):
                code, lines = self.run_pulse("calibration", "quick", "asm-dependent-add", PULSE_CHAIN=chain, **quick)
                self.assertEqual(code, 0, lines[-3:])
                begin = next(line for line in lines if line["kind"] == "PULSE_BEGIN")
                self.assertEqual((begin["chain_mode"], begin["chain_cycles"]), (str(int(bool(chain))), "65536"))
                samples = [line for line in lines if line["kind"] == "PULSE_SAMPLE"]
                self.assertEqual(len(samples), 3)
                for sample_line in samples:
                    ticks = [int(sample_line["chain_before"]), int(sample_line["chain_after"])]
                    if chain:
                        # 65536 dependent adds: the core clock is within x8 of the TSC.
                        self.assertTrue(all(65536 / 8 < value < 65536 * 8 for value in ticks), ticks)
                    else:
                        self.assertEqual(ticks, [0, 0])

    def test_stack_phase_is_decimal_or_refused(self) -> None:
        code, lines = self.run_pulse("calibration", "quick", "asm-dependent-add", PULSE_STACK_PHASE="336",
                                     PULSE_SAMPLES="1", PULSE_ITERATIONS="1000", PULSE_WARMUP_MS="1")
        self.assertEqual(code, 0, lines[-3:])
        case = next(line for line in lines if line["kind"] == "PULSE_CASE")
        self.assertEqual(int(case["stack_rsp"], 16) % 4096, 336 - 8)
        for text, message in (("0x150", "decimal multiple of 16"), ("$150", "decimal multiple of 16"),
                              ("grid", "grid is a pulse_full plan"), ("24", "decimal multiple of 16")):
            with self.subTest(text):
                code, lines = self.run_pulse("calibration", "quick", "asm-dependent-add", PULSE_STACK_PHASE=text)
                self.assertNotEqual(code, 0)
                self.assertIn(message, " ".join(line["text"] for line in lines))

    def test_each_move_case_prints_its_first_copy(self) -> None:
        selected = "hot-a0-a0-n64,hot-a1-a0-n64,overlap-backward-d16-n64"
        code, lines = self.run_pulse("move", "quick", selected, **self.QUICK)
        self.assertEqual(code, 0, lines[-3:])
        cases = {line["case"]: line for line in lines if line["kind"] == "PULSE_CASE"}
        self.assertEqual(set(cases), set(selected.split(",")))
        for case in cases.values():
            self.assertEqual(case["text"].count(" data_src="), 1)
            self.assertEqual(case["text"].count(" data_dst="), 1)
        address = {name: (int(case["data_src"], 16), int(case["data_dst"], 16)) for name, case in cases.items()}
        self.assertEqual([value % 4096 for value in address["hot-a0-a0-n64"]], [0, 0])
        self.assertEqual([value % 4096 for value in address["hot-a1-a0-n64"]], [1, 0])
        source, target = address["overlap-backward-d16-n64"]
        self.assertEqual(target - source, 16)
        code, lines = self.run_pulse("calibration", "quick", "asm-dependent-add", **self.QUICK)
        self.assertEqual(code, 0, lines[-3:])
        case = next(line for line in lines if line["kind"] == "PULSE_CASE")
        self.assertNotIn(" data_", case["text"])
        self.assertFalse(any("block" in line for line in lines if line["kind"] == "PULSE_SAMPLE"))

    def test_a_dictionary_case_prints_the_storage_it_reads(self) -> None:
        # lookup-mixed-100 and churn-100 read PreparedUInt64Short, lookup-mixed-10000 PreparedUInt64Long;
        # build-reserved-100 builds its own dictionary in the loop: no prepared storage, its block per sample.
        together = ("u64-u64-build-reserved-100,u64-u64-lookup-mixed-100,u64-u64-lookup-mixed-10000,u64-u64-churn-100,"
                    "string-u64-build-grow-100")
        code, lines = self.run_pulse("dictionary", "quick", together, **self.QUICK)
        self.assertEqual(code, 0, lines[-3:])
        cases = {line["case"]: line for line in lines if line["kind"] == "PULSE_CASE"}
        short = cases["u64-u64-lookup-mixed-100"].get("data_items")
        self.assertTrue(short and int(short, 16))
        self.assertEqual(cases["u64-u64-churn-100"].get("data_items"), short)
        self.assertNotIn(cases["u64-u64-lookup-mixed-10000"].get("data_items"), (None, short))
        self.assertNotIn(" data_", cases["u64-u64-build-reserved-100"]["text"])
        # A case without data right after churn-100 in the same process prints none of churn's.
        self.assertNotIn(" data_", cases["string-u64-build-grow-100"]["text"])
        blocks = {line["block"] for line in lines
                  if line["kind"] == "PULSE_SAMPLE" and line["case"] == "u64-u64-build-reserved-100"}
        self.assertEqual(len(blocks), 1)
        self.assertTrue(int(blocks.pop()))
        # A case run alone gets its data from its own call, not from its neighbour's.
        code, lines = self.run_pulse("dictionary", "quick", "u64-u64-lookup-mixed-100", **self.QUICK)
        self.assertEqual(code, 0, lines[-3:])
        alone = next(line for line in lines if line["kind"] == "PULSE_CASE")
        self.assertTrue(int(alone["data_items"], 16))

    def test_the_tools_find_each_body_through_the_one_anchor(self) -> None:
        # A program with data links PulseRunCaseData too: anchor= stays the image's one PulseRunCase, the
        # symbol linked_image and opcache_sets look up, and body - anchor lands on the case's own procedure.
        shapes = FULL.linked_image.ImageShapes(self.executables["dictionary"])
        code, lines = self.run_pulse("dictionary", "list", "u64-u64-build-grow-100,u64-u64-lookup-mixed-100")
        self.assertEqual(code, 0, lines[-3:])
        bodies = {line["case"]: shapes.anchor + int(line["body"], 16) - int(line["anchor"], 16)
                  for line in lines if line["kind"] == "PULSE_CASEDEF"}
        for case, procedure in (("u64-u64-build-grow-100", "_CASEUINT64BUILDGROW100$"),
                                ("u64-u64-lookup-mixed-100", "_CASEUINT64LOOKUP100$")):
            with self.subTest(case):
                self.assertIn(procedure, shapes.procedures[bodies[case]][0].upper())

    def test_each_sample_prints_the_block_its_body_left(self) -> None:
        code, lines = self.run_pulse("rtl", "quick", "inttostr-int64,strtoint-int64", **self.QUICK)
        self.assertEqual(code, 0, lines[-3:])
        samples = [line for line in lines if line["kind"] == "PULSE_SAMPLE"]
        blocks = [line.get("block") for line in samples if line["case"] == "inttostr-int64"]
        self.assertEqual(len(blocks), 3)
        self.assertTrue(all(block and int(block) for block in blocks), blocks)
        # A case that leaves no block prints none, not its predecessor's.
        self.assertEqual([line.get("block") for line in samples if line["case"] == "strtoint-int64"], [None] * 3)

QUIET = {"core_cpu": 12, "core_idle": [1000, 1000], "sibling_cpu": 13, "sibling_idle": [1000, 1000]}
HALF_BUSY_SIBLING = {**QUIET, "sibling_idle": [500, 1000]}
BUSY_CORE = {**QUIET, "core_idle": [900, 1000]}


def sample(**changes: object) -> dict[str, object]:
    """One clean fixed-work PULSE_SAMPLE as the runner parses it."""
    fields = dict.fromkeys((
        "operations", "tsc_ticks", "core_cycles", "wall_ns", "process_cycles", "thread_cycles",
        "process_cpu_ns", "thread_cpu_ns", "core_enabled", "core_running", "memory_before_private",
        "memory_after_private", "memory_cooldown_private", "memory_peak_resident", "iterations",
        "sibling_idle_cycles",
    ), 100)
    fields.update(context_switches=0, sibling_cpu=-1, chain_before=0, chain_after=0, digest="1")
    fields.update(changes)
    return fields


def process(variant: str, repeat: int, runner: dict[str, object], case: str = "dep-add",
            log: str = "process.log") -> dict[str, object]:
    return {
        "program": "codegen", "case": case, "category": "single-cpu", "variant": variant, "repeat": repeat,
        "duration_ms": 6, "fixed_work": True, "iterations": 100, "log": log, "executable": f"{variant}.exe",
        "case_definition": {"oracle": "1"}, "samples": [sample() for _ in range(3)], "runner": runner,
    }


class NegativeControlImagesTests(unittest.TestCase):
    def fixture(self, directory: Path, platform: str, *, false_only: bool = False, duplicate: bool = False):
        method = FULL.method
        signature, immediate = method.CONTROL_SIGNATURES[platform]
        opcode = signature[:immediate + 4]
        data = bytearray(0x40 + 5 * 0x40)
        functions, listings, patches = [], {}, []
        for index, name in enumerate((*method.CONTROL_FUNCTIONS, "InitializeData")):
            begin, offset = 0x1000 + index * 0x40, 0x40 + index * 0x40
            functions.append((name, begin, begin + 0x40))
            # A REX-prefixed instruction contains the old global signature one byte into it.
            raw, instruction = signature, opcode
            if index == 4 or (index == 0 and false_only):
                raw, instruction = b"\x41" + signature, b"\x41" + opcode
            if index == 4 and false_only:
                raw = instruction = b"\xc3"
            data[offset:offset + len(raw)] = raw
            instructions = [(begin, instruction)]
            if index < 4 and not (index == 0 and false_only):
                patches.append(offset + immediate)
            if index == 0 and not false_only:
                extra = signature if duplicate else b"\x41" + signature
                data[offset + 0x20:offset + 0x20 + len(extra)] = extra
                instructions.append((begin + 0x20, opcode if duplicate else b"\x41" + opcode))
            listings[begin] = "\n".join(f" {address:x}:\t{raw.hex(' ')}\tmov esi,0x40"
                                         for address, raw in instructions)
        baseline, more = directory / "work64", directory / "work66"
        baseline.write_bytes(data)
        baseline.chmod(0o755)

        def command(args):
            text = (" 0 .text 00000140 00001000 00001000 00000040 2**4 CONTENTS, ALLOC, CODE"
                    if "-h" in args else listings[int(next(arg.split("=")[1] for arg in args
                                                         if arg.startswith("--start-address=")), 16)])
            return subprocess.CompletedProcess(args, 0, text)

        return baseline, more, functions, command, patches

    def test_rex_matches_inside_and_outside_control_functions_are_ignored(self) -> None:
        for platform in ("nt", "posix"):
            with self.subTest(platform=platform), tempfile.TemporaryDirectory() as temporary:
                baseline, more, functions, command, expected = self.fixture(Path(temporary), platform)
                original = baseline.read_bytes()
                self.assertEqual(original.count(FULL.method.CONTROL_SIGNATURES[platform][0]), 6)
                with (
                    mock.patch.dict(FULL.method.CONTROL_SIGNATURES,
                                    {os.name: FULL.method.CONTROL_SIGNATURES[platform]}),
                    mock.patch.object(FULL.method.code_placement, "tool", return_value="objdump"),
                    mock.patch.object(FULL.method.code_placement, "procedures", return_value=functions),
                    mock.patch.object(FULL.method, "command", side_effect=command),
                ):
                    FULL.method.patch_negative_control(baseline, more)
                changed = more.read_bytes()
                self.assertEqual(len(changed), len(original))
                self.assertEqual([index for index, (left, right) in enumerate(zip(original, changed))
                                  if left != right], expected)
                self.assertTrue(all(original[index] == 64 and changed[index] == 66 for index in expected))
                self.assertEqual(more.stat().st_mode, baseline.stat().st_mode)

    def test_global_count_four_cannot_replace_a_missing_counter_with_a_rex_match(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            baseline, more, functions, command, _ = self.fixture(Path(temporary), os.name, false_only=True)
            self.assertEqual(baseline.read_bytes().count(FULL.method.CONTROL_SIGNATURES[os.name][0]), 4)
            with (
                mock.patch.object(FULL.method.code_placement, "tool", return_value="objdump"),
                mock.patch.object(FULL.method.code_placement, "procedures", return_value=functions),
                mock.patch.object(FULL.method, "command", side_effect=command),
                self.assertRaisesRegex(RuntimeError, "expected one counter, found 0"),
            ):
                FULL.method.patch_negative_control(baseline, more)
            self.assertFalse(more.exists())

    def test_two_counters_in_one_function_are_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            baseline, more, functions, command, _ = self.fixture(Path(temporary), os.name, duplicate=True)
            with (
                mock.patch.object(FULL.method.code_placement, "tool", return_value="objdump"),
                mock.patch.object(FULL.method.code_placement, "procedures", return_value=functions),
                mock.patch.object(FULL.method, "command", side_effect=command),
                self.assertRaisesRegex(RuntimeError, "expected one counter, found 2"),
            ):
                FULL.method.patch_negative_control(baseline, more)
            self.assertFalse(more.exists())

    def test_both_builders_use_the_common_patch_and_the_control_allocator(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            baseline, _, functions, command, _ = self.fixture(directory, os.name)
            toolchain, control_mm = directory / "toolchain", directory / "control-mm.pas"
            with (
                mock.patch.object(FULL.method.code_placement, "tool", return_value="objdump"),
                mock.patch.object(FULL.method.code_placement, "procedures", return_value=functions),
                mock.patch.object(FULL.method, "command", side_effect=command),
                mock.patch.object(FULL.pulse, "build_moon", return_value=baseline) as build,
            ):
                built, before, after = FULL.method.build_images(
                    toolchain, toolchain, directory / "method", ("codegen",), control_mm_source=control_mm)
                self.assertEqual(build.call_args.kwargs["mm_source"], control_mm)
                self.assertTrue({"-gw3", "-Xs-"} <= set(build.call_args.kwargs["extra_options"]))
                copied = directory / "method/byte-copies" / baseline.name
                self.assertEqual(copied.read_bytes(), built["codegen"].read_bytes())
                full_before, full_after = FULL.build_negative_control(toolchain, control_mm, directory / "full")
                self.assertEqual(build.call_args.kwargs["mm_source"], control_mm)
                self.assertTrue({"-gw3", "-Xs-"} <= set(build.call_args.kwargs["extra_options"]))
                self.assertEqual(before.read_bytes(), full_before.read_bytes())
                self.assertEqual(after.read_bytes(), full_after.read_bytes())

    def test_method_cli_requires_its_control_allocator(self) -> None:
        arguments = ["method", "--toolchain", "current", "--control-toolchain", "frozen",
                     "--output", "result", "--machine-label", "test"]
        with mock.patch.object(sys, "argv", arguments), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as error:
                FULL.method.parse_args()
            self.assertEqual(error.exception.code, 2)
        with mock.patch.object(sys, "argv", [*arguments, "--control-mm-source", "frozen-mm.pas"]):
            self.assertEqual(FULL.method.parse_args().control_mm_source, Path("frozen-mm.pas"))


if __name__ == "__main__":
    unittest.main()
