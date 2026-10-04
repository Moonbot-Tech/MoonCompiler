from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


TOOLS = Path(__file__).resolve().parent


def load(name: str):
    path = TOOLS / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PULSE = load("pulse")
STAND_COMPARE = load("stand_compare")
STAND_AB = load("stand_ab_gate")
PLACEMENT = load("check_placement_rules")
PROGRAM_PLACEMENT = load("check_program_placement")


def complete_provenance(root: Path) -> None:
    path = root / "manifest.json"
    manifest = json.loads(path.read_text(encoding="utf-8"))
    manifest["measurement_method"] = PULSE.MEASUREMENT_METHOD
    manifest["git_head"] = "a" * 40
    manifest["git_status"] = ""
    systems = list(manifest["systems"])
    order = PULSE.process_order(systems, {'quick': 2, 'medium': 7, 'long': 9}[manifest['mode']])
    positions = {(program, system): iter([i for i, s in enumerate(order, 1) if s == system])
                 for program in {r["program"] for r in manifest["runs"]} for system in systems}
    for run in manifest["runs"]:
        run["sequence"] = next(positions[run["program"], run["system"]])
        run["executed_image"] = run["log"] + ".exe"
        run["executable_sha256"] = run["executed_image_sha256"] = "frozen-binary"
    for identity in manifest["external_toolchains"].values():
        identity.update(
            fpc_sha256="driver",
            backend_sha256="compiler",
            config_sha256="config",
        )
    manifest['input_contract'] = 'fixed-alloc-block16384-v1'
    path.write_text(json.dumps(manifest), encoding="utf-8")


def write_result(
    root: Path,
    systems: list[str],
    cases: dict[str, list[str]],
    *,
    oracles: dict[tuple[str, str], str] | None = None,
    omit_last_run: bool = False,
    mode: str = 'quick',
) -> None:
    runs = []
    sequence = 0
    for system in systems:
        for repeat in range({'quick': 2, 'medium': 7}[mode]):
            sequence += 1
            log = root / f"{sequence:02d}-{system}.log"
            lines = []
            for case in cases[system]:
                oracle = (oracles or {}).get((system, case), "0000000000000001")
                cycles = 900 if system.startswith("T") else 1000
                lines.extend([
                    f"PULSE_CASE program=synthetic mode={mode} case={case} "
                    f"layer=codegen unit=test iterations=1 operations=1 "
                    f"samples=1 warmup_ns=1 oracle={oracle} body=4000 anchor=8000",
                    f"PULSE_SAMPLE program=synthetic mode={mode} case={case} "
                    f"sample=1 iterations=1 operations=1 wall_ns={cycles} "
                    f"thread_cpu_ns={cycles} process_cpu_ns={cycles} "
                    f"thread_cycles={cycles} tsc_ticks={cycles} "
                    f"digest={oracle}",
                    f"PULSE_TOTAL program=synthetic mode={mode} case={case} "
                    f"samples=1 operations=1 wall_ns={cycles} "
                    f"thread_cpu_ns={cycles} process_cpu_ns={cycles} "
                    f"thread_cycles={cycles} tsc_ticks={cycles}",
                ])
            lines.append("PULSE_END program=synthetic status=PASS")
            log.write_text("\n".join(lines) + "\n", encoding="utf-8")
            runs.append({
                "sequence": sequence,
                "system": system,
                "program": "synthetic",
                "case": "all",
                "log": log.name,
            })
    if omit_last_run:
        runs.pop()
    (root / "manifest.json").write_text(
        json.dumps({
            "mode": mode,
            "systems": {system: system for system in systems},
            "external_toolchains": {
                system: {
                    "profile_sha256": "profile",
                    "unit_sha256": {
                        "system.ppu": "system",
                        "sysutils.o": "sysutils",
                        "math.o": "math",
                        "generics.hashes.o": "hashes",
                    },
                }
                for system in systems
            },
            "runs": runs,
        }),
        encoding="utf-8",
    )
    complete_provenance(root)


def write_family_result(
    root: Path,
    baseline: str,
    candidate: str,
    table: dict[tuple[str, str], tuple[int, int]],
) -> None:
    """A stand result of two families of four placements over several programs.
    table maps (program, case) to the cycles of the baseline and of the candidate family."""
    systems = [family + suffix for family in (baseline, candidate) for suffix in ("", "1", "2", "3")]
    programs = sorted({program for program, _ in table})
    runs = []
    sequence = 0
    for system in systems:
        for program in programs:
            for repeat in range(7):
                sequence += 1
                log = root / f"{sequence:03d}-{system}-{program}.log"
                lines = []
                for (row_program, case), (base_cycles, cand_cycles) in sorted(table.items()):
                    if row_program != program:
                        continue
                    cycles = cand_cycles if system.startswith(candidate) else base_cycles
                    oracle = "0000000000000001"
                    lines.extend([
                        f"PULSE_CASE program={program} mode=medium case={case} "
                        f"layer=codegen unit=test iterations=1 operations=1 "
                        f"samples=1 warmup_ns=1 oracle={oracle} body=4000 anchor=8000",
                        f"PULSE_SAMPLE program={program} mode=medium case={case} "
                        f"sample=1 iterations=1 operations=1 wall_ns={cycles} "
                        f"thread_cpu_ns={cycles} process_cpu_ns={cycles} "
                        f"thread_cycles={cycles} tsc_ticks={cycles} "
                        f"digest={oracle}",
                        f"PULSE_TOTAL program={program} mode=medium case={case} "
                        f"samples=1 operations=1 wall_ns={cycles} "
                        f"thread_cpu_ns={cycles} process_cpu_ns={cycles} "
                        f"thread_cycles={cycles} tsc_ticks={cycles}",
                    ])
                lines.append(f"PULSE_END program={program} status=PASS")
                log.write_text("\n".join(lines) + "\n", encoding="utf-8")
                runs.append({
                    "sequence": sequence,
                    "system": system,
                    "program": program,
                    "case": "all",
                    "log": log.name,
                })
    (root / "manifest.json").write_text(
        json.dumps({
            "mode": "medium",
            "systems": {system: system for system in systems},
            "external_toolchains": {
                system: {
                    "profile_sha256": "profile",
                    "unit_sha256": {
                        "system.ppu": "system",
                        "sysutils.o": "sysutils",
                        "math.o": "math",
                        "generics.hashes.o": "hashes",
                    },
                }
                for system in systems
            },
            "runs": runs,
        }),
        encoding="utf-8",
    )
    complete_provenance(root)


class PulseFailClosedTests(unittest.TestCase):
    def test_relocation_preserves_the_measured_body_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ['A'], {'A': ['one']})
            log = sorted(root.glob('*.log'))[-1]
            log.write_text(log.read_text().replace('body=4000 anchor=8000', 'body=14000 anchor=18000'))
            rows, _ = PULSE.collect(root)
            self.assertEqual(rows['A', 'synthetic', 'one']['body_offsets'], [-0x4000, -0x4000])

    def test_a_moved_body_with_an_unchanged_anchor_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ['A'], {'A': ['one']})
            log = sorted(root.glob('*.log'))[-1]
            log.write_text(log.read_text().replace('body=4000', 'body=4040'))
            with self.assertRaisesRegex(ValueError, 'body identity varies'):
                PULSE.collect(root)

    def test_a_reused_image_cannot_claim_independent_launches(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A", "B"], {"A": ["one"], "B": ["one"]})
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            manifest["runs"][1]["executed_image"] = manifest["runs"][0]["executed_image"]
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, "reused process image"):
                PULSE.collect(root)

    def test_report_does_not_pair_a_system_with_itself(self) -> None:
        for systems in (["moon"], ["delphi", "moon-default"]):
            with self.subTest(systems=systems), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                write_result(root, systems, {system: ["one"] for system in systems})
                with mock.patch.object(PULSE, "paired_ratio_stats", wraps=PULSE.paired_ratio_stats) as pairs:
                    PULSE.write_report(root)
                self.assertTrue(all(call.args[0] is not call.args[1] for call in pairs.call_args_list))
                row = json.loads((root / "summary.json").read_text())["synthetic/one"]
                self.assertEqual(row["candidate_over_baseline"], 1)

    def test_missing_adjacent_pairs_cannot_make_a_successful_report(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A", "B"], {"A": ["one"], "B": ["one"]})
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            for run in manifest["runs"]:
                if run["system"] == "B":
                    run["sequence"] += 100
            path.write_text(json.dumps(manifest))
            with self.assertRaises(PULSE.UnstablePairsError):
                PULSE.write_report(root)

    def test_oracle_may_not_vary_identically_on_both_sides(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A", "B"], {"A": ["one"], "B": ["one"]})
            for name in ("02-A.log", "04-B.log"):
                path = root / name
                path.write_text(path.read_text().replace("oracle=0000000000000001", "oracle=0000000000000002"))
            with self.assertRaisesRegex(ValueError, "oracle varies between processes"):
                PULSE.collect(root)

    def test_retry_uses_canonical_executable_even_with_taskset(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            canonical = root / "benchmark"
            canonical.write_bytes(b"canonical")
            runs = [{"program": "synthetic", "case": "one", "system": system, "sequence": n,
                     "executable": str(canonical), "executable_sha256": PULSE.sha256(canonical),
                     "command": ["/usr/bin/taskset", "--cpu-list", "1,2", str(canonical), "medium", "one"],
                     "log": f"{system}-{n}.log"} for system in ("A", "B") for n in range(1, 8)]
            manifest = dict(mode="medium", systems=["A", "B"], runs=runs,
                            execution_affinity={"reserved_cpus": [1, 2]})
            (root / "manifest.json").write_text(json.dumps(manifest))
            drift = PULSE.UnstablePairsError(["timing drift"], {("synthetic", "one")})
            completed = subprocess.CompletedProcess([], 0, stdout="PULSE_END status=PASS")
            with mock.patch.object(PULSE, "write_report", side_effect=[drift, None]):
                with mock.patch.object(PULSE, "run_fresh_image", return_value=(completed, {})) as fresh:
                    PULSE.retry_unstable(root)
            self.assertEqual(fresh.call_count, 14)
            self.assertTrue(all(call.args[0] == canonical and call.args[3] == (1, 2) for call in fresh.call_args_list))

    def test_every_benchmark_process_has_a_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            exe = Path(temporary) / ("probe.exe" if os.name == "nt" else "probe")
            exe.write_bytes(b"synthetic executable")
            completed = subprocess.CompletedProcess([], 0, stdout="PULSE_END status=PASS")
            with mock.patch.object(PULSE, "run", return_value=completed) as runner:
                PULSE.run_fresh_image(
                    exe, "medium", "one", (), PULSE.sha256(exe)
                )
            self.assertEqual(
                runner.call_args.kwargs["timeout"],
                PULSE.PROCESS_TIMEOUT_SECONDS,
            )

    def test_parallel_build_only_collects_independent_outputs(self) -> None:
        def fake_build(program, default_mm, **_):
            return Path(f"{program}-{'default' if default_mm else 'product'}")

        with mock.patch.object(PULSE, "build_moon", side_effect=fake_build):
            built = PULSE.build(
                ["one", "two"],
                ["moon", "moon-default"],
                build_jobs=4,
            )
        self.assertEqual(
            built,
            {
                "moon": {
                    "one": Path("one-product"),
                    "two": Path("two-product"),
                },
                "moon-default": {
                    "one": Path("one-default"),
                    "two": Path("two-default"),
                },
            },
        )

    def test_targeted_rows_require_case_isolated_mode_and_exact_names(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            exe = root / "probe.exe"
            exe.write_bytes(b"probe")
            built = {"moon": {"alpha": exe}}
            # run_suite reserves the Linux measurement cores (nine physical) before it reads its
            # arguments; this test is about the arguments, not about the machine it runs on.
            cores = mock.patch.object(PULSE, "linux_pulse_cpu_reservation", return_value=())
            with cores, mock.patch.object(PULSE, "build", return_value=built):
                with self.assertRaisesRegex(ValueError, "requires medium or long"):
                    PULSE.run_suite(
                        "quick",
                        ["alpha"],
                        ["moon"],
                        "quick-targeted",
                        result_root=root,
                        selected_rows={"alpha/one"},
                    )
            with cores, mock.patch.object(PULSE, "build", return_value=built):
                with mock.patch.object(PULSE, "discover_cases", return_value=["one"]):
                    with self.assertRaisesRegex(ValueError, "were not discovered"):
                        PULSE.run_suite(
                            "medium",
                            ["alpha"],
                            ["moon"],
                            "missing-targeted",
                            result_root=root,
                            selected_rows={"alpha/two"},
                        )

    def test_stand_program_list_holds_the_moon_only_programs(self) -> None:
        # pulse.py's default list is made for a run with Delphi; a stand of Moon
        # toolchains asks for the full list and must get repairs with it
        self.assertNotIn("repairs", PULSE.stand_programs(False))
        self.assertIn("repairs", PULSE.stand_programs(True))
        self.assertEqual(
            set(PULSE.stand_programs(True)) - set(PULSE.stand_programs(False)),
            set(PULSE.MOON_ONLY_PROGRAMS),
        )

    def test_complete_quick_matrix_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A", "B"], {"A": ["one"], "B": ["one"]})
            rows, _ = PULSE.collect(root)
            self.assertEqual(len(rows), 2)

    def test_missing_case_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A", "B"], {"A": ["one", "two"], "B": ["one"]})
            with self.assertRaisesRegex(ValueError, "case matrix differs"):
                PULSE.collect(root)

    def test_missing_process_run_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(
                root, ["A", "B"], {"A": ["one"], "B": ["one"]},
                omit_last_run=True,
            )
            with self.assertRaisesRegex(ValueError, "incomplete process matrix"):
                PULSE.collect(root)

    def test_truncated_sample_set_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, ["A"], {"A": ["one"]})
            log = root / "01-A.log"
            text = log.read_text(encoding="utf-8").replace(
                "samples=1 warmup_ns=1", "samples=2 warmup_ns=1", 1
            )
            log.write_text(text, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "has 1/2 samples"):
                PULSE.collect(root)

    def test_persistent_drift_requires_explicit_acceptance(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = {
                "mode": "medium",
                "systems": {"A": "A", "B": "B"},
                "runs": [],
                "retry_history": [{}, {}, {}],
            }
            (root / "manifest.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )
            error = PULSE.UnstablePairsError(
                ["synthetic drift"], {("synthetic", "one")}
            )
            with mock.patch.object(PULSE, "write_report", side_effect=error):
                with self.assertRaisesRegex(ValueError, "remains unproven"):
                    PULSE.retry_unstable(root)

    def test_explicit_persistent_drift_acceptance_is_recorded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = {
                "mode": "medium",
                "systems": {"A": "A", "B": "B"},
                "runs": [],
                "retry_history": [{}, {}, {}],
            }
            path = root / "manifest.json"
            path.write_text(json.dumps(manifest), encoding="utf-8")
            error = PULSE.UnstablePairsError(
                ["synthetic drift"], {("synthetic", "one")}
            )
            with mock.patch.object(
                PULSE, "write_report", side_effect=[error, None]
            ):
                PULSE.retry_unstable(root, accept_persistent_drift=True)
            updated = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                updated["persistent_drift_accepted"], ["synthetic/one"]
            )


class StandAcceptanceFailClosedTests(unittest.TestCase):
    def setUp(self):
        # Statistics fixtures are not executable images. Binary provenance is
        # tested separately below; there is no bypass in the production checker.
        patcher = mock.patch.object(STAND_AB.check_program_placement, 'check', return_value=[])
        patcher.start()
        self.addCleanup(patcher.stop)
    SYSTEMS = [
        "C", "C1", "C2", "C3",
        "T", "T1", "T2", "T3",
    ]

    def invoke(self, root: Path) -> int:
        argv = [
            "stand_ab_gate.py", str(root),
            "--baseline", "C", "--candidate", "T",
        ]
        with mock.patch.object(sys, "argv", argv):
            return STAND_AB.main()

    def invoke_with(self, root: Path, *options: str) -> tuple[int, str]:
        argv = [
            "stand_ab_gate.py", str(root),
            "--baseline", "C", "--candidate", "T", *options,
        ]
        output = io.StringIO()
        with mock.patch.object(sys, "argv", argv), contextlib.redirect_stdout(output):
            code = STAND_AB.main()
        return code, output.getvalue()

    def test_unstable_nonexpected_row_cannot_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 1000)})
            manifest = json.loads((root / "manifest.json").read_text())
            for run in manifest["runs"]:
                if run["system"].startswith("T") and run["sequence"] % 4 == 2:
                    path = root / run["log"]
                    path.write_text(path.read_text().replace("=1000", "=1400"))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 2, output)
            self.assertIn("product measured 0/1", output)
            self.assertNotIn("STAND_AB_GATE_PASS", output)

    def test_common_drift_is_retained_but_does_not_fake_a_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 1000)})
            manifest = json.loads((root / "manifest.json").read_text())
            for run in manifest["runs"]:
                if run["sequence"] % 4 in (0, 3):
                    path = root / run["log"]
                    path.write_text(path.read_text().replace("=1000", "=1400"))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 0, output)
            PULSE.write_report(root)
            summary = json.loads((root / "summary.json").read_text())["alpha/one"]
            self.assertEqual(summary["candidate_over_baseline"], 1)
            self.assertEqual(max(summary["family"]["run_spreads"].values()), 1.4)

    def test_complete_quick_family_remains_diagnostic(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, self.SYSTEMS, {system: ['one'] for system in self.SYSTEMS})
            code, output = self.invoke_with(root)
            self.assertEqual(code, 2, output)
            self.assertIn('quick is diagnostic only', output)

    def test_dirty_measurement_source_cannot_pass(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(
                root, "C", "T", {("alpha", "one"): (1000, 1000)}
            )
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            manifest["git_status"] = " M compiler/psub.pas"
            path.write_text(json.dumps(manifest))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 1, output)
            self.assertIn("measurement source tree is dirty", output)

    def test_composite_work_still_blocks_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, 'C', 'T', {('alpha', 'whole-operation'): (1000, 1300)})
            for log in root.glob('*.log'):
                log.write_text(log.read_text().replace('layer=codegen', 'layer=composite+rtl'))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 1, output)
            self.assertIn('product measured 1/1, diagnostic 0', output)

    def test_equal_sorted_residues_do_not_hide_mispaired_placements(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, 'C', 'T', {('alpha', 'one'): (1000, 1000)})
            for run in json.loads((root / 'manifest.json').read_text())['runs']:
                system = run['system']
                # Baseline 0,16,32,48; candidate 16,0,32,48. The sorted sets
                # agree, but the first two measured process pairs do not.
                slot = int(system[-1]) if system[-1].isdigit() else 0
                residue = ([16, 0, 32, 48] if system.startswith('T') else [0, 16, 32, 48])[slot]
                log = root / run['log']
                log.write_text(log.read_text().replace('body=4000', f'body={0x4000 + residue:x}'))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 2, output)
            self.assertIn('measured body residues differ', output)

    def test_quiet_retry_does_not_erase_prior_instability(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 1000)})
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            manifest["retry_history"] = [{"cases": ["alpha/one"], "reason": "two modes in the original run"}]
            path.write_text(json.dumps(manifest))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 2, output)
            self.assertIn("prior unstable timing", output)
            with self.assertRaises(PULSE.UnstablePairsError):
                PULSE.write_report(root)
            row = json.loads((root / "summary.json").read_text())["alpha/one"]
            self.assertEqual(row["comparison_status"], "DRIFT")
            self.assertIsNone(row["candidate_over_baseline"])

    def test_explicit_three_percent_target_is_not_replaced_by_five_percent_policy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 965)})
            self.assertEqual(self.invoke_with(root, "--expect-faster", "alpha/one")[0], 0)

    def test_reference_slowdown_is_diagnostic_not_product_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "product"): (1000, 1000), ("reference", "one"): (1000, 1400)})
            for run in json.loads((root / "manifest.json").read_text())["runs"]:
                if run["program"] == "reference":
                    path = root / run["log"]
                    path.write_text(path.read_text().replace("layer=codegen", "layer=asm-reference"))
            code, output = self.invoke_with(root)
            self.assertEqual(code, 0, output)
            self.assertIn("product measured 1/1, diagnostic 1", output)

    def test_legacy_baseline_requires_explicit_revision_and_all_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 900)})
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            for system, identity in manifest["external_toolchains"].items():
                if system.startswith("C"):
                    del identity["profile_sha256"]
            manifest["external_memory_managers"] = {system: {"sha256": "mm"} for system in self.SYSTEMS}
            path.write_text(json.dumps(manifest))
            self.assertEqual(self.invoke_with(root)[0], 1)
            self.assertEqual(self.invoke_with(root, "--legacy-baseline-revision", "ccaa5fbaf")[0], 0)
            del manifest["external_memory_managers"]["C"]["sha256"]
            path.write_text(json.dumps(manifest))
            self.assertEqual(self.invoke_with(root, "--legacy-baseline-revision", "ccaa5fbaf")[0], 1)

    def test_legacy_flag_does_not_exempt_candidate_profile(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {("alpha", "one"): (1000, 900)})
            path = root / "manifest.json"
            manifest = json.loads(path.read_text())
            del manifest["external_toolchains"]["T"]["profile_sha256"]
            path.write_text(json.dumps(manifest))
            self.assertEqual(self.invoke_with(root, "--legacy-baseline-revision", "ccaa5fbaf")[0], 1)

    def test_complete_semantic_family_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(root, self.SYSTEMS, {
                system: ["one"] for system in self.SYSTEMS
            }, mode='medium')
            self.assertEqual(self.invoke(root), 0)

    def test_same_case_name_in_two_programs_keeps_both_rows(self) -> None:
        # alpha/one is 30% slower, beta/one is faster.  Keyed by the case name
        # alone the later row replaced the earlier one and the gate passed.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {
                ("alpha", "one"): (1000, 1300),
                ("beta", "one"): (1000, 900),
            })
            code, output = self.invoke_with(root)
            self.assertEqual(code, 1)
            self.assertIn("alpha/one", output)
            self.assertIn("cases 2,", output)

    def test_ambiguous_bare_expectation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {
                ("alpha", "one"): (1000, 1000),
                ("beta", "one"): (1000, 900),
            })
            code, output = self.invoke_with(root, "--expect-faster", "one")
            self.assertEqual(code, 1)
            self.assertIn("ambiguous", output)

    def test_qualified_and_unique_expectations_are_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {
                ("alpha", "one"): (1000, 1000),
                ("beta", "one"): (1000, 900),
                ("beta", "two"): (1000, 900),
            })
            code, output = self.invoke_with(root, "--expect-faster", "beta/one,two")
            self.assertEqual(code, 0, output)
            self.assertIn("beta/one: 0.900", output)
            self.assertIn("beta/two: 0.900", output)

    def test_expectation_of_the_wrong_program_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {
                ("alpha", "one"): (1000, 1000),
                ("beta", "one"): (1000, 900),
            })
            code, output = self.invoke_with(root, "--expect-faster", "alpha/one")
            self.assertEqual(code, 1)
            self.assertIn("alpha/one: expected faster", output)

    def test_asked_program_without_rows_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, "C", "T", {
                ("alpha", "one"): (1000, 1000),
                ("beta", "one"): (1000, 900),
            })
            code, output = self.invoke_with(root, "--programs", "alpha,beta,gamma")
            self.assertEqual(code, 1)
            self.assertIn("program gamma was asked for", output)
            code, _ = self.invoke_with(root, "--programs", "alpha,beta")
            self.assertEqual(code, 0)

    def test_missing_family_member_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            systems = self.SYSTEMS[:-1]
            write_result(root, systems, {system: ["one"] for system in systems})
            self.assertEqual(self.invoke(root), 1)

    def test_semantic_oracle_substitution_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_result(
                root,
                self.SYSTEMS,
                {system: ["one"] for system in self.SYSTEMS},
                oracles={("T3", "one"): "0000000000000002"},
            )
            self.assertEqual(self.invoke(root), 1)


FAMILY_SCRIPT = TOOLS.parents[2] / "scripts" / "Pulse-Family.ps1"
UV = next(
    (candidate for candidate in (r"C:\files\utils\python\uv.exe", shutil.which("uv")) if candidate and Path(candidate).is_file()),
    None,
)


@unittest.skipUnless(os.name == "nt" and UV and shutil.which("powershell"), "needs Windows PowerShell and uv")
class FamilyScriptExitCodeTests(unittest.TestCase):
    """Pulse-Family.ps1 must hand its verdict to the caller: the script judges a finished result with
    -Result, so the exit code is checked without running Pulse."""

    def judge(self, table: dict, *options: str, pulse_log: str | None = None) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "family-synthetic"
            root.mkdir()
            write_family_result(root, "B", "C", table)
            # Exercise the real wrapper and estimator, with the binary reader
            # replaced only in this private test copy. Synthetic logs have no PE.
            workspace = Path(temporary) / 'workspace'
            test_tools = workspace / 'qualification/performance/tools'
            test_tools.mkdir(parents=True)
            for source in TOOLS.glob('*.py'):
                shutil.copyfile(source, test_tools / source.name)
            (test_tools / 'check_program_placement.py').write_text(
                'def check(result, families):\n    return []\n', encoding='utf-8')
            script = workspace / 'scripts/Pulse-Family.ps1'
            script.parent.mkdir()
            shutil.copyfile(FAMILY_SCRIPT, script)
            extra = list(options)
            if pulse_log is not None:
                log = Path(temporary) / "pulse.log"
                log.write_text(pulse_log, encoding="utf-8")
                extra += ["-PulseExit", "1", "-PulseLog", str(log)]
            done = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script),
                 "-Result", str(root), "-Uv", UV, *extra],
                capture_output=True, text=True, errors="replace", timeout=600,
            )
            return done.returncode, done.stdout + done.stderr

    def test_failed_pulse_is_not_judged(self) -> None:
        code, output = self.judge(
            {("alpha", "one"): (1000, 900)}, "-Programs", "alpha",
            pulse_log="Fatal: Compilation aborted")
        self.assertEqual(code, 1, output)
        self.assertIn("not judged", output)
        self.assertNotIn("STAND_AB_GATE", output)

    def test_unstable_pairs_are_judged_but_never_accepted(self) -> None:
        # every run is there, Pulse only saw two runs of one executable apart: the verdict is
        # shown, the script still says "repeat" - a green gate must not come out as 0
        code, output = self.judge(
            {("alpha", "one"): (1000, 900)}, "-Programs", "alpha",
            pulse_log="UnstablePairsError: unstable process pairs: B/alpha/one process drift 1.445x")
        self.assertEqual(code, 2, output)
        self.assertIn("STAND_AB_GATE_PASS", output)
        self.assertIn("repeat the run", output)

    def test_green_result_returns_zero(self) -> None:
        code, output = self.judge(
            {("alpha", "one"): (1000, 1000), ("beta", "one"): (1000, 900)},
            "-Programs", "alpha,beta")
        self.assertEqual(code, 0, output)
        self.assertIn("STAND_AB_GATE_PASS", output)

    def test_red_result_returns_nonzero(self) -> None:
        code, output = self.judge(
            {("alpha", "one"): (1000, 1300), ("beta", "one"): (1000, 900)},
            "-Programs", "alpha,beta")
        self.assertEqual(code, 1, output)
        self.assertIn("STAND_AB_GATE_FAIL", output)

    def test_default_program_list_requires_representative_placements(self) -> None:
        # The default list still includes repairs; missing ABI/loop evidence is
        # rejected by the placement check before an aggregate can be accepted.
        code, output = self.judge({("alpha", "one"): (1000, 1000)})
        self.assertEqual(code, 1, output)
        self.assertRegex(output, r"programs: .*\brepairs\b")
        self.assertIn("was asked for and has no judged row", output)
        self.assertNotIn("STAND_AB_GATE_PASS", output)


class PlacementAssertionFailClosedTests(unittest.TestCase):
    def test_distinct_addresses_do_not_fake_effective_placement_coverage(self):
        def placement(begin: int) -> dict:
            return {
                "body": {
                    "begin": begin,
                    "loops": [{"target_mod64": (begin + 8) % 64}],
                },
                "direct_callees": [
                    {"name": "HOT", "begin": begin + 64, "loops": []}
                ],
            }

        collapsed = [
            PROGRAM_PLACEMENT.effective_signature(placement(0x1000 + offset))
            for offset in (0, 4096, 8192, 12288)
        ]
        self.assertEqual(len(set(collapsed)), 1)
        aligned_lines = [
            PROGRAM_PLACEMENT.effective_signature(placement(0x1000 + offset))
            for offset in (0, 64, 128, 192)
        ]
        self.assertEqual(len(set(aligned_lines)), 4)
        covered = [
            PROGRAM_PLACEMENT.effective_signature(placement(0x1000 + offset))
            for offset in (0, 16, 32, 48)
        ]
        self.assertEqual(len(set(covered)), 4)

    def test_allocator_signature_compares_graphs_not_virtual_addresses(self):
        workers = [{'worker': i, 'row': i, **{f'{kind}{size}': 100 + i * 3 + size
                    for kind in ('class', 'owner') for size in range(3)}} for i in range(8)]
        relocated = [{key: value + 0x10000 if key.startswith(('class', 'owner')) else value
                      for key, value in worker.items()} for worker in workers]
        row = {'workers': [workers, relocated]}
        signature = STAND_COMPARE.allocator_signature('threads', 'parallel-alloc-free-8', row)
        self.assertEqual(signature['rows'], list(range(8)))
        relocated[7]['owner2'] = relocated[0]['owner0']
        self.assertIn('varies', STAND_COMPARE.allocator_signature('threads', 'parallel-alloc-free-8', row)['error'])

    def test_missing_binary_identity_is_rejected_for_every_program(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, 'C', 'T', {('alpha', 'one'): (1000, 1000)})
            with self.assertRaisesRegex(ValueError, 'missing or inconsistent executable identity'):
                STAND_AB.check_program_placement.check(root, ['C', 'T'])

    def test_stale_binary_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            write_family_result(root, 'C', 'T', {('alpha', 'one'): (1000, 1000)})
            exe = root / 'image.exe'
            exe.write_bytes(b'current image')
            manifest_path = root / 'manifest.json'
            manifest = json.loads(manifest_path.read_text())
            for run in manifest['runs']:
                run['executable'] = str(exe)
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'executable missing or changed'):
                STAND_AB.check_program_placement.check(root, ['C', 'T'])

    def test_only_explicit_accepted_noop_is_diagnostic(self):
        self.assertTrue(PULSE.diagnostic_layer('rtl+memory+accepted-noop'))
        self.assertFalse(PULSE.diagnostic_layer('composite+rtl+memory'))

    def test_assertion_rejects_zero_selected_procedures(self) -> None:
        result = {"procedures": 0, "R4_violations": []}
        self.assertIn(
            "no-procedures-selected",
            PLACEMENT.assertion_failures(result, "R4", []),
        )

    def test_ceiling_cannot_substitute_an_unrelated_violation(self) -> None:
        result = {
            "procedures": 2,
            "RT_violations": [
                ("TUNICODESTRINGHELPER_SPLIT", 0, 0, 59),
                ("UNRELATED_NEW_ROUTINE", 0, 0, 60),
            ],
        }
        failures = PLACEMENT.assertion_failures(
            result,
            "RT=2",
            [
                "RT=TUNICODESTRINGHELPER.*SPLIT",
                "RT=TWIDESTRINGHELPER.*SPLIT",
            ],
        )
        self.assertTrue(any("TWIDESTRINGHELPER" in item for item in failures))


if __name__ == "__main__":
    unittest.main()
