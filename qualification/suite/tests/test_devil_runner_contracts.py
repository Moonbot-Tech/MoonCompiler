from contextlib import redirect_stdout
import hashlib
import io
import json
import random
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
import devil_minimize
import run_devil_env_gate
import run_devil_all
import run_devil_gate
import run_devil_modes_gate
import run_devil_mutation
import run_devil_resident_gate
import run_devil_targeted
import run_chimera_gate
import run_resident_switch_matrix
import run_topology_gate
import devil_toolchain


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DevilRunnerContractsTest(unittest.TestCase):
    def test_full_stage_deadline_survives_closed_output(self) -> None:
        code, output, elapsed = run_devil_all.run(
            [sys.executable, "-c", "import os,time; os.close(1); os.close(2); time.sleep(5)"],
            1, "closed-output-control")
        self.assertEqual(code, 124)
        self.assertIn("<TIMEOUT>", output)
        self.assertLess(elapsed, 4)

    def test_closed_output_keeps_the_exit_code_within_the_deadline(self) -> None:
        for expected in (0, 73):
            with self.subTest(expected=expected):
                code, output, _ = run_devil_all.run(
                    [sys.executable, "-c", f"import os; os.close(1); os.close(2); raise SystemExit({expected})"],
                    5, "closed-output-exit")
                self.assertEqual(code, expected)
                self.assertNotIn("<TIMEOUT>", output)

    def test_silent_full_stage_obeys_wall_limit(self) -> None:
        code, output, elapsed = run_devil_all.run(
            [sys.executable, "-c", "import time; time.sleep(5)"], 1, "silent-control")
        self.assertEqual(code, 124)
        self.assertIn("<TIMEOUT>", output)
        self.assertLess(elapsed, 4)

    def test_context_failure_is_a_named_semantic_check(self) -> None:
        builder = generate_devil.FormBuilder(7, "life")
        wrapped = builder.wrap(["    Work;"], ["try-except"], "  ")
        source = "\n".join(wrapped)
        self.assertIn(
            "DevilCheckBool('dvl-life-00007-context', False);", source,
        )
        self.assertIn("dvl-life-00007-context-entered", source)
        self.assertIn("dvl-life-00007-context-completed", source)
        self.assertIn("Inc(ContextEntered", source)
        self.assertIn("Inc(ContextCompleted", source)
        self.assertNotIn("DevilFailures := High(UInt64)", source)

    def test_lifetime_exception_context_preserves_the_escape_edge(self) -> None:
        rng = mock.Mock()
        rng.choice.side_effect = ["locals-exception", 2, 1]
        e = generate_devil.Emitter()
        placeholder = generate_devil.CaseRecord(
            "dvl-life-00000", "life", {"shape": "finally-managed-result"},
        )
        with (mock.patch.object(
                generate_devil, "emit_finally_result_case",
                return_value=placeholder,
              ), mock.patch.object(
                generate_devil, "pick_contexts", return_value=["try-except"],
              )):
            generate_devil.layer_life(e, rng, 2, 0)
        source = e.text()
        self.assertIn("raise EDvlSignal.Create('dvl');", source)
        self.assertIn("on EDvlSignal do DevilTrailAdd('x');", source)
        self.assertNotIn(
            "DevilCheckBool('dvl-life-00001-context', False);", source,
        )

    def test_boolean_checks_use_the_canonical_failure_protocol(self) -> None:
        source = (DEVIL / "devil_runtime.pas").read_text(encoding="utf-8")
        implementation = source.split(
            "procedure DevilCheckBool(const Name: AnsiString; "
            "Condition: Boolean);",
        )[2].split("procedure DevilFeed", 1)[0]
        self.assertIn(
            "DevilCheckU(Name, UInt64(Ord(Condition)), 1);", implementation,
        )
        self.assertNotIn("WriteLn('DEVIL_FAILURE", implementation)

    def test_named_values_cannot_colour_the_anonymous_digest(self) -> None:
        source = (DEVIL / "devil_runtime.pas").read_text(encoding="utf-8")
        check = source.split(
            "procedure DevilCheckU(const Name: AnsiString; "
            "Actual, Expected: UInt64);",
        )[2].split("procedure DevilCheckBool", 1)[0]
        note = source.split(
            "procedure DevilNote(const Name: AnsiString; Value: UInt64);",
        )[2].split("constructor TDvlTagged.Create", 1)[0]
        self.assertIn("DevilFeedText(Name);", check)
        self.assertIn("DevilFeed(Expected);", check)
        self.assertNotIn("xor Actual", check)
        self.assertIn("DevilFeedText(Name);", note)
        self.assertNotIn("DevilFeed(Value);", note)

    def test_terminal_verdict_has_one_strict_wire_form(self) -> None:
        prefix = (
            "DEVIL_LAYERS gen\n"
            "DEVIL_CHECK dvl-gen-00001-a actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_CHECK dvl-gen-00001-b actual=0000000000000002 "
            "expected=0000000000000002\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_FINALIZATION checks=2\n"
        )
        valid = run_devil_gate.Build("release")
        valid.expected_seed = 1
        valid.parse(
            prefix + "DEVIL_PASS seed=1 checks=2 digest=0000000000000001\n"
        )
        self.assertEqual(run_devil_gate.instrument_contract_errors(valid), [])

        for summary in (
            "DEVIL_FAIL seed=1 failures=-1 checks=2 digest=0000000000000001",
            "DEVIL_FAIL seed=1 failures=0 checks=2 digest=0000000000000001",
            "DEVIL_PASS seed=1 failures=0 checks=2 digest=0000000000000001",
        ):
            broken = run_devil_gate.Build("release")
            broken.expected_seed = 1
            broken.parse(prefix + summary + "\n")
            self.assertIn(
                "terminal summaries=0",
                run_devil_gate.instrument_contract_errors(broken),
            )

        wrong_seed = run_devil_gate.Build("release")
        wrong_seed.expected_seed = 2
        wrong_seed.parse(
            prefix + "DEVIL_PASS seed=1 checks=2 digest=0000000000000001\n"
        )
        self.assertIn(
            "terminal seed=1, expected=2",
            run_devil_gate.instrument_contract_errors(wrong_seed),
        )

        for malformed_layer in (
            "DEVIL_LAYER gen=1",
            "DEVIL_LAYER gen=0000000000000001 checks=2",
        ):
            broken = run_devil_gate.Build("release")
            broken.expected_seed = 1
            broken.parse(
                prefix.replace(
                    "DEVIL_LAYER gen=0000000000000001",
                    malformed_layer,
                ) + "DEVIL_PASS seed=1 checks=2 "
                    "digest=0000000000000001\n"
            )
            self.assertIn(
                "layer digests do not match the layer inventory",
                run_devil_gate.instrument_contract_errors(broken),
            )

        for output in (
            prefix + "DEVIL_PASS seed=1 checks=2 digest=0000000000000001\n"
            "DEVIL_FAILURE broken\n",
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n" + prefix
            + "DEVIL_PASS seed=1 checks=2 digest=0000000000000001\n",
            prefix + "DEVIL_PASS seed=1 checks=2 digest=0000000000000001\n"
            "DEVIL_LAYER gen=0000000000000001\n",
        ):
            broken = run_devil_gate.Build("release")
            broken.expected_seed = 1
            broken.parse(output)
            self.assertTrue(run_devil_gate.instrument_contract_errors(broken))

        missing_failure = run_devil_gate.Build("release")
        missing_failure.expected_seed = 1
        missing_failure.parse(
            "DEVIL_LAYERS gen\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000002\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_FINALIZATION checks=1\n"
            "DEVIL_FAIL seed=1 failures=1 checks=1 "
            "digest=0000000000000001\n"
        )
        self.assertIn(
            "terminal check/failure counts are incomplete",
            run_devil_gate.instrument_contract_errors(missing_failure),
        )

    def test_failure_output_cap_can_only_make_the_run_invalid(self) -> None:
        def sample(checks: int) -> run_devil_gate.Build:
            lines = ["DEVIL_LAYERS gen"]
            for occurrence in range(checks):
                lines.append(
                    "DEVIL_CHECK dvl-gen-cap actual=0000000000000000 "
                    "expected=0000000000000001")
                if occurrence < 4096:
                    lines.append(
                        "DEVIL_FAILURE dvl-gen-cap actual=0000000000000000 "
                        "expected=0000000000000001")
            lines.extend((
                "DEVIL_FEEDS 1",
                "DEVIL_STEPS 1",
                "DEVIL_LAYER gen=0000000000000001",
                f"DEVIL_FINALIZATION checks={checks}",
                f"DEVIL_FAIL seed=1 failures={checks} checks={checks} "
                "digest=0000000000000001",
            ))
            build = run_devil_gate.Build("release")
            build.compiled = True
            build.run_exit = 0
            build.expected_seed = 1
            build.parse("\n".join(lines) + "\n")
            return build

        self.assertEqual(run_devil_gate.instrument_contract_errors(
            sample(4096)), [])
        self.assertIn("terminal check/failure counts are incomplete",
                      run_devil_gate.instrument_contract_errors(sample(4097)))

    def test_repeated_named_observations_preserve_every_value(self) -> None:
        release = run_devil_gate.Build("release")
        release.compiled = True
        release.parse(
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000002\n"
        )
        debug = run_devil_gate.Build("debug")
        debug.compiled = True
        debug.parse(
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000003\n"
        )
        self.assertEqual(
            run_devil_gate.note_sequence(release, "dvl-gen-00001-value"),
            ("0000000000000001", "0000000000000002"),
        )
        findings = run_devil_gate.compare([release, debug])
        self.assertTrue(any(
            item["kind"] == "observation-split" for item in findings
        ))

        release = run_devil_gate.Build("release")
        release.compiled = True
        release.parse(
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000003\n"
            "DEVIL_FAILURE dvl-gen-00001-value "
            "actual=0000000000000001 expected=0000000000000003\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000002 "
            "expected=0000000000000003\n"
            "DEVIL_FAILURE dvl-gen-00001-value "
            "actual=0000000000000002 expected=0000000000000003\n"
        )
        debug = run_devil_gate.Build("debug")
        debug.compiled = True
        debug.parse(
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000003\n"
            "DEVIL_FAILURE dvl-gen-00001-value "
            "actual=0000000000000001 expected=0000000000000003\n"
        )
        failures = [item for item in run_devil_gate.compare([release, debug])
                    if item["kind"] in ("model-mismatch", "check-stream-split")]
        self.assertEqual([item["kind"] for item in failures],
                         ["model-mismatch", "check-stream-split"])
        self.assertEqual(failures[1]["occurrence"], 2)
        self.assertEqual(
            failures[1]["builds"],
            {"release": ["0000000000000002", "0000000000000003"],
             "debug": "<missing>"},
        )

    def test_repeated_check_failure_cannot_move_between_occurrences(self) -> None:
        name = "dvl-abi-00001-value-1"
        expected = "0000000000000001"
        bad = "FFFFFFFFFFFFFFFF"
        debug = run_devil_gate.Build("debug")
        release = run_devil_gate.Build("release")
        debug.compiled = release.compiled = True
        debug.check_events[name] = [(bad, expected), (expected, expected)]
        release.check_events[name] = [(expected, expected), (bad, expected)]
        findings = [item for item in run_devil_gate.compare([debug, release])
                    if item["kind"] == "model-mismatch"]
        self.assertEqual([item.get("occurrence", 1) for item in findings],
                         [1, 2])
        rule = {
            "id": "known", "kind": "model-mismatch",
            "check": "^dvl-abi-[0-9]+-value-[0-9]+$",
            "failing_side": "moon", "actual": "^FFFFFFFFFFFFFFFF$",
            "expected": "^0000000000000001$",
        }
        fresh, known = run_devil_gate.classify(findings, [rule])
        self.assertEqual(fresh, findings)
        self.assertEqual(known, [])

    def test_known_model_difference_is_bound_to_side_and_values(self) -> None:
        rule = next(
            item for item in run_devil_gate.load_known(
                DEVIL / "known_findings.json"
            ) if item["id"] == "dvl-0010"
        )
        accepted = {
            "kind": "model-mismatch",
            "check": "dvl-flow-00001-case",
            "builds": {"release": "ok", "delphi": "0000000000000001"},
            "expected": "0000000000000009",
        }
        fresh, known = run_devil_gate.classify([accepted], [rule])
        self.assertEqual(fresh, [])
        self.assertEqual(known[0]["known"], "dvl-0010")

        for builds, actual, expected in (
            ({"release": "000000000000DEAD", "delphi": "ok"},
             "000000000000DEAD", "0000000000000009"),
            ({"release": "ok", "delphi": "000000000000DEAD"},
             "000000000000DEAD", "0000000000000009"),
            ({"release": "ok", "delphi": "0000000000000001"},
             "0000000000000001", "0000000000000007"),
        ):
            finding = {**accepted, "builds": builds, "expected": expected}
            fresh, known = run_devil_gate.classify([finding], [rule])
            self.assertEqual(fresh, [finding], (actual, expected))
        self.assertEqual(known, [])

    def test_disagreeing_expected_models_cannot_match_a_known_rule(self) -> None:
        rule = {
            "kind": "model-mismatch",
            "failing_side": "moon",
            "actual": "^FFFFFFFFFFFFFFFF$",
            "expected": "^0000000000000001$",
        }
        finding = {
            "kind": "model-mismatch",
            "builds": {"release": "FFFFFFFFFFFFFFFF", "delphi": "ok"},
            "expected": ["0000000000000001", "0000000000000002"],
        }
        self.assertFalse(
            run_devil_gate.known_runtime_semantics_match(rule, finding))

    def test_known_observation_requires_stable_delphi_moon_partition(self) -> None:
        rule = {
            "id": "known-note",
            "kind": "observation-split",
            "note_name": "^dvl-gen-[0-9]+-value$",
            "split": "delphi-vs-moon",
            "moon_value": "^A$",
            "delphi_value": "^B$",
        }
        accepted = {
            "kind": "observation-split",
            "note": "dvl-gen-00001-value",
            "builds": {"debug": "A", "release": "A", "delphi": "B"},
        }
        self.assertEqual(
            run_devil_gate.classify([accepted], [rule])[0], [],
        )
        broken = {**accepted,
                  "builds": {"debug": "A", "release": "C", "delphi": "B"}}
        self.assertEqual(
            run_devil_gate.classify([broken], [rule])[0], [broken],
        )

        unconstrained = {key: value for key, value in rule.items()
                         if key not in ("moon_value", "delphi_value")}
        self.assertEqual(
            run_devil_gate.classify([accepted], [unconstrained])[0],
            [accepted],
        )

    def test_shuffle_compares_every_order_independent_observation(self) -> None:
        normal = run_devil_gate.Build("release")
        shuffled = run_devil_gate.Build("shuffled")
        for build in (normal, shuffled):
            build.layers = {"gen"}
            build.checks = 2
            build.notes = {"dvl-gen-00001-value": "A"}
            build.note_occurrences = {"dvl-gen-00001-value": 1}
            build.failures = {}
            build.failure_occurrences = {}
            build.counters = {"FEEDS": 2, "STEPS": 2}
            build.layer_digests = {"gen": "11"}
        shuffled.notes = {}
        shuffled.note_occurrences = {}
        shuffled.counters["FEEDS"] = 1
        shuffled.layer_digests["gen"] = "22"
        kinds = {
            finding["kind"] for finding in
            run_devil_gate.compare_shuffled_program(normal, shuffled)
        }
        self.assertEqual(kinds, {
            "order-dependent-note",
            "order-dependent-note-count",
            "order-dependent-instrument-count",
            "order-dependent-layer-digest",
        })

    def test_extended_program_cannot_drop_a_shared_observation(self) -> None:
        first = run_devil_gate.Build("release")
        second = run_devil_gate.Build("second")
        first.notes = {"dvl-gen-00001-value": "A"}
        first.note_occurrences = {"dvl-gen-00001-value": 1}
        first.failures = {
            "dvl-gen-00002-check": ("1", "2"),
        }
        first.failure_occurrences = {"dvl-gen-00002-check": 1}
        second.notes = {}
        second.note_occurrences = {}
        second.failures = {
            "dvl-gen-00002-check": ("3", "2"),
        }
        second.failure_occurrences = {"dvl-gen-00002-check": 1}
        kinds = {
            finding["kind"] for finding in
            run_devil_gate.compare_extended_program(first, second)
        }
        self.assertEqual(kinds, {"cross-program-note", "cross-program-check"})

    def test_extended_program_requires_the_exact_execution_prefix(self) -> None:
        first = run_devil_gate.Build("release")
        second = run_devil_gate.Build("second")
        for build in (first, second):
            build.layers = {"gen"}
            build.checks = 3
            build.counters = {"FEEDS": 3, "STEPS": 3}
            build.layer_digests = {"gen": "AA"}
            build.digest = "AA"
            build.notes = {"dvl-gen-00001-value": "1"}
            build.note_occurrences = {"dvl-gen-00001-value": 3}
        first.note_events = {"dvl-gen-00001-value": ["1", "2", "1"]}
        second.note_events = {
            "dvl-gen-00001-value": ["1", "99", "1", "2", "1"],
        }
        findings = run_devil_gate.compare_extended_program(first, second)
        self.assertEqual([item["kind"] for item in findings],
                         ["cross-program-note"])

    def test_modes_compare_middle_occurrences_not_only_last_values(self) -> None:
        first = run_devil_gate.Build("baseline")
        second = run_devil_gate.Build("mode")
        first.parse(
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000002\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000001 "
            "expected=0000000000000004\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000002 "
            "expected=0000000000000004\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000001 "
            "expected=0000000000000004\n"
        )
        second.parse(
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000003\n"
            "DEVIL_NOTE dvl-gen-00001-value=0000000000000001\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000001 "
            "expected=0000000000000004\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000003 "
            "expected=0000000000000004\n"
            "DEVIL_FAILURE dvl-gen-00002-value actual=0000000000000001 "
            "expected=0000000000000004\n"
        )
        kinds = {item["kind"] for item in
                 run_devil_modes_gate.compare(first, second, "mode")}
        self.assertEqual(kinds, {
            "observation-depends-on-mode", "check-depends-on-mode",
        })

    def test_flow_always_covers_mixed_boolean_availability(self) -> None:
        e = generate_devil.Emitter()
        records = generate_devil.layer_flow(e, random.Random(1), 0, 0)
        record = next(r for r in records if r.detail.get("shape") == "mixed-boolean-availability")
        self.assertEqual(record.detail["truth_rows"], 16)
        self.assertEqual(record.detail["operators"], ["and", "or"])
        self.assertFalse(record.detail["inline_required"])
        self.assertIn("DvlFlowMixedBooleanMatrix;", e.text())
        self.assertIn("-and-15", e.text())
        self.assertIn("-or-15", e.text())

    def test_small_lifetime_corpus_reaches_result_ownership_direction(self) -> None:
        e = generate_devil.Emitter()
        records = generate_devil.layer_life(e, random.Random(1), 1, 0)
        self.assertEqual(records[0].detail["shape"], "finally-managed-result")
        self.assertIn("Result := Source.Value;", e.text())
        self.assertIn("TDvlTagged.Alive, 0", e.text())
        self.assertIn("DvlLife00000;", e.text())

    def test_managed_result_direction_crosses_types_and_exit_paths(self) -> None:
        kinds = ("AnsiString", "UnicodeString", "WideString", "IInterface",
                 "TDvlTaggedRec", "TArray<IInterface>")
        for kind in kinds:
            for mode in ("normal", "exit", "raise-body", "raise-consumer"):
                for held in (False, True):
                    rng = mock.Mock()
                    rng.choice.side_effect = [kind, mode, 2, held]
                    e = generate_devil.Emitter()
                    record = generate_devil.emit_finally_result_case(e, rng, 0)
                    self.assertEqual(record.detail["result"], kind)
                    self.assertEqual(record.detail["exit"], mode)
                    self.assertEqual(record.detail["existing_cleanup"], held)
                    self.assertIn("DvlLife00000ResultSource.Forward1", e.text())
                    self.assertIn("DvlLife00000ResultConsume(Scenario)", e.text())

    def test_small_io_corpus_reaches_every_text_builtin_type(self) -> None:
        e = generate_devil.Emitter()
        records = generate_devil.layer_io(e, random.Random(1), 1, 0)
        self.assertEqual(records[0].detail["shape"], "text-builtins")
        for kind in ("PAnsiChar", "PWideChar", "PChar", "AnsiString", "UnicodeString", "WideString"):
            self.assertIn(f"WriteLn(T, {kind}(", e.text())
        self.assertIn("builtin-text", e.text())

    def test_capture_corpus_distinguishes_produced_objects_and_records(self) -> None:
        e = generate_devil.Emitter()
        records = generate_devil.layer_capture(e, random.Random(1), 1, 0)
        shapes = {record.detail["shape"] for record in records}
        self.assertTrue({"with-produced-object", "with-produced-record"} <= shapes)
        self.assertIn("out First, Second:", e.text())
        self.assertIn("Held.Slot := 7;", e.text())
        self.assertIn("Result, 718", e.text())
        self.assertIn("Result, 213", e.text())

    def test_targeted_devil_impact_union_is_canonical(self) -> None:
        layers = run_devil_targeted.canonical_layers(
            ["strings-unicode", "exceptions"]
        )
        self.assertEqual(
            layers,
            tuple(layer for layer in run_devil_targeted.ALL_LAYERS
                  if layer in {"str", "uni", "lit", "pick", "io", "rtllib",
                               "lang", "exc", "region", "flow", "call", "inl",
                               "life", "capture"}),
        )
        self.assertEqual(len(layers), len(set(layers)))

    def test_targeted_devil_rejects_unknown_impact(self) -> None:
        with self.assertRaisesRegex(ValueError, "unknown impact area"):
            run_devil_targeted.canonical_layers(["made-up-repair"])

    def test_targeted_optimizer_enables_only_provenance_checks(self) -> None:
        self.assertEqual(
            run_devil_targeted.adjacent_stages(["optimizer-codegen"]),
            ("codegen", "asm-oracle"),
        )
        self.assertEqual(
            run_devil_targeted.main_switches(["optimizer-codegen"]),
            ("--determinism",),
        )

    def test_targeted_ppu_area_keeps_all_cross_build_checks(self) -> None:
        self.assertEqual(
            run_devil_targeted.main_switches(["generics-ppu"]),
            ("--separate-units", "--second-program", "--ppu-reuse"),
        )

    def test_targeted_stage_output_is_read_as_the_stage_wrote_it(self) -> None:
        # d0 98 is UTF-8 "И" and 0x98 is no cp1251 character: a reader in the
        # Windows code page lost the whole output of such a stage
        code, output, _ = run_devil_targeted.run(
            [sys.executable, "-c",
             "import sys; sys.stdout.buffer.write(b'\\xd0\\x98 DEVIL_REGISTRY OK\\n')"], 60)
        self.assertEqual((code, output), (0, "И DEVIL_REGISTRY OK\n"))
        code, output, _ = run_devil_targeted.run(
            [sys.executable, "-c", "print('перепись: 1 строк')"], 60)
        self.assertEqual((code, output), (0, "перепись: 1 строк\n"))

    def test_targeted_stage_passes_only_with_its_verdict_line(self) -> None:
        verdicts = dict(run_devil_targeted.STAGE_ORDER)
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            compiler = base / "fpc"
            compiler.write_text("compiler")

            def light() -> tuple[int, str]:
                printed = io.StringIO()
                with mock.patch.object(sys, "argv", ["run_devil_targeted.py", "light"]), \
                        mock.patch.object(run_devil_targeted, "ROOT", base), \
                        mock.patch.object(run_devil_targeted, "stage_command",
                                          lambda name, *rest: [name]), \
                        mock.patch.object(run_devil_targeted, "run",
                                          lambda command, timeout: (0, verdicts[command[0]] + " n=1\n", 0.1)), \
                        mock.patch.object(run_devil_targeted.tc, "preflight"), \
                        mock.patch.object(run_devil_targeted.tc, "toolchain",
                                          return_value=(compiler, compiler, [], "")), \
                        redirect_stdout(printed):
                    code = run_devil_targeted.main()
                return code, printed.getvalue()

            code, printed = light()
            self.assertEqual(code, 0)
            self.assertIn("DEVIL_TARGETED_LIGHT OK", printed)
            verdicts["codegen"] = ""  # exit code 0 and no verdict
            code, printed = light()
            self.assertEqual(code, 1)
            self.assertIn("no 'DEVIL_CODEGEN OK' line", printed)
            self.assertIn("DEVIL_TARGETED_LIGHT FINDINGS in codegen", printed)

    def test_mode_failure_keeps_the_underlying_linker_cause(self) -> None:
        log = """Error: Error while linking
Fatal: Compilation aborted
/usr/bin/ld.bfd: cannot find -lkernel32.dll: No such file or directory
"""
        detail = run_devil_modes_gate.build_failure_detail(log)
        self.assertIn("Error while linking", detail)
        self.assertIn("cannot find -lkernel32.dll", detail)

    def test_modes_reject_abnormal_or_incomplete_runtime(self) -> None:
        build = run_devil_gate.Build("mode")
        build.compiled = True
        build.run_exit = 73
        self.assertEqual(run_devil_modes_gate.runtime_failure(build),
                         "process exit=73")

        build.run_exit = 0
        self.assertIn("terminal summaries=0",
                      run_devil_modes_gate.runtime_failure(build))

    def test_modes_bind_the_runtime_summary_to_the_requested_seed(self) -> None:
        output = (
            "DEVIL_LAYERS gen\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_FINALIZATION checks=1\n"
            "DEVIL_PASS seed=1 checks=1 digest=0000000000000001\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            executable = work / "devil.exe"
            executable.write_bytes(b"")
            with (mock.patch.object(
                    run_devil_modes_gate.tc, "compile_command",
                    return_value=["compiler"],
                  ), mock.patch.object(
                    run_devil_modes_gate.tc, "executable",
                    return_value=executable,
                  ), mock.patch.object(
                    run_devil_modes_gate, "run",
                    side_effect=[(0, ""), (0, output)],
                  )):
                got, failure = run_devil_modes_gate.behaviour(
                    work, "baseline", [], "release", 30, 2)
        self.assertIsNone(got)
        self.assertIn("terminal seed=1, expected=2", failure)

    def test_topology_accepts_only_the_exact_dvl_0066_boundary(self) -> None:
        known = {
            "topology": "cycle-iface-impl",
            "symbol": "generic-holder",
            "carrier": "plain",
            "profile": "release",
            "extra": [],
            "errors": [
                "Error: Symbol T from module U1 registered with current module U0"
            ],
        }
        self.assertTrue(run_topology_gate.accepted_build_failure(known))
        self.assertFalse(run_topology_gate.accepted_build_failure({
            **known, "symbol": "private-class-var",
        }))
        self.assertFalse(run_topology_gate.accepted_build_failure({
            **known, "topology": "acyclic",
        }))
        self.assertFalse(run_topology_gate.accepted_build_failure({
            **known, "profile": "debug",
        }))
        self.assertFalse(run_topology_gate.accepted_build_failure({
            **known, "errors": ["Fatal: Internal error 123"],
        }))
        self.assertTrue(run_topology_gate.accepted_build_failure({
            **known, "profile": "o1", "extra": ["-OoAUTOINLINE"],
        }))
        self.assertTrue(run_topology_gate.accepted_build_failure({
            **known, "carrier": "explicit-inline", "profile": "debug",
        }))

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

    def test_chimera_refuses_an_incomplete_mormot_on_every_platform(self) -> None:
        # without the pinned checkout Linux Chimera reported one failed build
        # and 55 unexecuted census rows as findings instead of its missing input
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(run_chimera_gate, "MORMOT", Path(directory)):
                for platform in ("win32", "linux"):
                    with self.subTest(platform=platform):
                        with self.assertRaisesRegex(SystemExit, "incomplete pinned mORMot input"):
                            run_chimera_gate.check_mormot_objects(platform)
                        folder, names = run_chimera_gate.OBJECTS[platform]
                        (Path(directory) / folder).mkdir(parents=True)
                        for name in names:
                            (Path(directory) / folder / name).write_bytes(b"")
                        run_chimera_gate.check_mormot_objects(platform)

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

    def test_whole_program_perturbation_declares_more_but_runs_same_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = root / "base"
            enlarged = root / "enlarged"
            for argv in (
                ["generate_devil.py", "--seed", "7", "--cases", "1",
                 "--layers", "gen", "--out", str(base)],
                ["generate_devil.py", "--seed", "7", "--cases", "1",
                 "--layers", "gen", "--extra-cases-per-layer", "1",
                 "--runner-prefix-manifest", str(base / "devil_manifest.json"),
                 "--out", str(enlarged)],
            ):
                with (mock.patch.object(sys, "argv", argv),
                      redirect_stdout(io.StringIO())):
                    generate_devil.main()
            first_manifest = json.loads(
                (base / "devil_manifest.json").read_text(encoding="utf-8")
            )
            second_manifest = json.loads(
                (enlarged / "devil_manifest.json").read_text(encoding="utf-8")
            )
            self.assertGreater(second_manifest["case_count"],
                               first_manifest["case_count"])
            self.assertGreater(second_manifest["runner_call_counts"]["gen"],
                               first_manifest["runner_call_counts"]["gen"])

            def runner_calls(path: Path) -> list[str]:
                text = path.read_text(encoding="utf-8")
                body = text.split("procedure RunDevilGenLayer;", 1)[1]
                body = body.split("end;", 1)[0]
                return [line.strip() for line in body.splitlines()
                        if line.strip().startswith("Dvl")]

            self.assertEqual(runner_calls(base / "devil_gen.inc"),
                             runner_calls(enlarged / "devil_gen.inc"))

    def test_chain_reentry_is_bounded_and_exception_safe(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "3", "--cases", "200",
                    "--layers", "chain", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            manifest = json.loads((output / "devil_manifest.json").read_text())
            sibling_count = sum(
                stage == "sibling-chain"
                for case in manifest["cases"]
                for stage in case["stages"]
            )
            source = (output / "devil_chain.inc").read_text()
        self.assertGreater(sibling_count, 0)
        self.assertEqual(source.count("  Theirs := Mine;"), sibling_count)
        self.assertEqual(source.count("      Theirs := DvlLink"), sibling_count)
        self.assertGreaterEqual(source.count("    try\n"), sibling_count)
        self.assertGreaterEqual(source.count("    finally\n"), sibling_count)
    def test_unicode_concat_keeps_its_explicit_byte_destination(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "3", "--cases", "200",
                    "--layers", "uni", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            manifest = json.loads((output / "devil_manifest.json").read_text())
            source = (output / "devil_uni.inc").read_text()
        concat_cases = [case["name"] for case in manifest["cases"]
                        if case.get("shape") == "concat-codepage"]
        self.assertGreater(len(concat_cases), 0)
        self.assertNotIn("  R := A + AnsiString('z');", source)
        for name in concat_cases:
            tag = name.rsplit("-", 1)[1]
            self.assertIn("  C: TDvlCp%s;" % tag, source)
            self.assertIn("  C := A + AnsiString('z');", source)
            self.assertIn("'%s-concat-length'" % name, source)
            self.assertIn("'%s-concat-codepage', " % name, source)
            self.assertIn("UInt64(StringCodePage(C)), 1251", source)

    def test_generated_program_timeout_preserves_hang_bound(self) -> None:
        self.assertEqual(run_devil_gate.generated_program_timeout(90, 300), 90)
        self.assertEqual(run_devil_gate.generated_program_timeout(7200, 300), 300)
        self.assertEqual(run_devil_gate.generated_program_timeout(7200, 120), 120)
        with self.assertRaisesRegex(ValueError, "must be positive"):
            run_devil_gate.generated_program_timeout(7200, 0)

    def test_resident_switch_paths_are_resolved_before_cwd_changes(self) -> None:
        work, report = run_resident_switch_matrix.normalize_paths(
            Path("relative-resident-switch-work"), Path("relative-report.json"))
        self.assertEqual(work, Path.cwd() / "relative-resident-switch-work")
        self.assertEqual(report, Path.cwd() / "relative-report.json")

    def test_environment_comparison_fails_on_missing_artefact(self) -> None:
        self.assertEqual(
            run_devil_env_gate.changed_artefacts(
                {"program.o": "same", "program.exe": "old"},
                {"program.o": "same", "program.ppu": "new"},
            ),
            ["program.exe", "program.ppu"],
        )

    def test_allocator_load_has_no_scheduler_dependent_oracle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            argv = ["generate_devil.py", "--seed", "5", "--cases", "101",
                    "--layers", "load", "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            source = (output / "devil_load.inc").read_text(encoding="utf-8")
        self.assertNotIn("dvl-load-contended-240-waited", source)
        self.assertNotIn("SmallGetmemSleepCount", source)
        self.assertIn("DevilCheckBool('dvl-load-contended-240-balance'", source)
        self.assertIn("DevilCheckU('dvl-load-contended-240-owner'", source)

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

    def test_repair_boundaries_are_mandatory_not_random_luck(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            layers = ("expr,unary,flow,pick,capture,unit,chk,abi,float,lit,"
                      "asm,inl,lang,life,init")
            argv = ["generate_devil.py", "--seed", "1", "--cases", "1",
                    "--layers", layers,
                    "--out", str(output)]
            with mock.patch.object(sys, "argv", argv):
                with redirect_stdout(io.StringIO()):
                    generate_devil.main()
            sources = "\n".join(
                path.read_text(encoding="utf-8")
                for path in sorted(output.glob("devil_*.inc")))
            unit_source = (output / "devil_gen_unit.pas").read_text(
                encoding="utf-8")

        for anchor in (
            "dvl-expr-u64-mod-mask-matrix",
            "dvl-expr-signed-widen-after-arithmetic-matrix",
            "dvl-unary-delphi-hilo-matrix",
            "dvl-abi-delphi-set-layout-matrix",
            "dvl-float-branch-selection-matrix",
            "dvl-lit-resourcestring-typed-constants",
            "dvl-flow-runtime-bound-matrix",
            "dvl-flow-seh-loop-matrix",
            "dvl-flow-cbool-operator-matrix",
            "dvl-pick-mixed-uint64",
            "dvl-pick-var-addressability-matrix",
            "dvl-capture-with-composite-lvalue",
            "dvl-capture-nested-expression-new",
            "dvl-unit-generic-alias-replay",
            "dvl-chk-incdec-boundary-matrix",
            "dvl-asm-implicit-frame-matrix",
            "dvl-inl-exit-unwind-matrix",
            "dvl-lang-custom-variant-carrier-matrix",
        ):
            self.assertIn(anchor, sources)
        self.assertIn("function TDvlCarrierVariantType.RightPromotion", sources)
        self.assertIn("procedure TDvlCarrierVariantType.Compare", sources)
        self.assertIn("Ord(Value = 42)", sources)
        self.assertIn("Ord(Value < 43)", sources)
        self.assertIn("Ord(Value > 41)", sources)
        self.assertIn("CastValue := Value + 8", sources)
        self.assertIn("dvl-init-00000-class-stamps", sources)
        self.assertIn("System.Generics.Collections.TEnumerator<T>",
                      unit_source)

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

    def test_main_comparison_requires_one_complete_instrument_summary(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 0
        build.parse(
            "DEVIL_LAYERS gen\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_PASS seed=1 checks=1 "
            "digest=0000000000000001\n"
        )
        findings = run_devil_gate.compare([build])
        self.assertEqual([finding["kind"] for finding in findings],
                         ["instrument-invalid"])

        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 0
        build.parse(
            "DEVIL_LAYERS gen\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_FINALIZATION checks=1\n"
            "DEVIL_PASS seed=1 checks=1 digest=0000000000000001\n"
        )
        self.assertEqual(run_devil_gate.compare([build]), [])

        build.counter_occurrences.pop("STEPS")
        findings = run_devil_gate.compare([build])
        self.assertEqual(findings[0]["kind"], "instrument-invalid")

    def test_fpc_only_layers_do_not_claim_portable_layer_digests(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 0
        build.parse(
            "DEVIL_LAYERS gen,i128,load\n"
            "DEVIL_CHECK dvl-gen-00001-value actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_FEEDS 1\n"
            "DEVIL_STEPS 1\n"
            "DEVIL_LAYER gen=0000000000000001\n"
            "DEVIL_FINALIZATION checks=1\n"
            "DEVIL_PASS seed=1 checks=1 "
            "digest=0000000000000001\n"
        )
        self.assertEqual(run_devil_gate.compare([build]), [])

    def test_known_checks_never_absorb_the_process_exit_channel(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 1
        build.digest = "0000000000000001"
        build.checks = 1
        build.summary_occurrences = 1
        build.summary_line = 5
        build.finalization_occurrences = 1
        build.finalization_checks = 1
        build.finalization_line = 4
        build.layers = {"lang"}
        build.layers_occurrences = 1
        build.layer_digests = {"lang": build.digest}
        build.layer_digest_occurrences = {"lang": 1}
        build.counters = {"FEEDS": 1, "STEPS": 1}
        build.counter_occurrences = {"FEEDS": 1, "STEPS": 1}
        build.failures = {
            "dvl-lang-00001-type": ("0000000000000005", "0000000000000006"),
        }
        build.failure_occurrences = {"dvl-lang-00001-type": 1}
        build.reported_failures = 1
        runtime = [{
            "kind": "runtime-failed", "build": "release", "exit": 1,
            "detail": ["DEVIL_FAIL seed=1"],
        }]
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-type",
            "builds": {"release": "0000000000000005"},
            "known": "dvl-0014",
        }]

        findings, known_hits = run_devil_gate.absorb_derived_known_effects(
            runtime, known, [build])

        self.assertEqual(findings, runtime)
        self.assertEqual(known_hits, known)

        for abnormal_exit in (2, 73, 217):
            build.run_exit = abnormal_exit
            runtime[0]["exit"] = abnormal_exit
            findings, known_hits = run_devil_gate.absorb_derived_known_effects(
                runtime, known, [build])
            self.assertEqual(findings, runtime)
            self.assertEqual(known_hits, known)

    def test_known_check_absorbs_only_its_derived_failure_count_split(self) -> None:
        findings = [
            {
                "kind": "failure-count-split",
                "check": "dvl-lang-00001-known",
                "builds": {"dcc": 1, "release": 0},
            },
            {
                "kind": "failure-count-split",
                "check": "dvl-lang-00002-new",
                "builds": {"dcc": 1, "release": 0},
            },
        ]
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-known",
            "builds": {"dcc": "0000000000000005", "release": "ok"},
            "known": "dvl-0014",
        }]

        fresh, known_hits = run_devil_gate.absorb_derived_known_effects(
            findings, known, [])

        self.assertEqual(fresh, [findings[1]])
        self.assertEqual(known_hits[-1], {**findings[0], "known": "derived"})

    def test_known_check_never_absorbs_an_independent_digest_split(self) -> None:
        digest = {
            "kind": "digest-split",
            "digests": {"debug": "AA", "release": "BB"},
        }
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-known",
            "builds": {"debug": "ok", "release": "0000000000000005"},
            "known": "dvl-0014",
        }]
        fresh, known_hits = run_devil_gate.absorb_derived_known_effects(
            [digest], known, [])
        self.assertEqual(fresh, [digest])
        self.assertEqual(known_hits, known)

    def test_unparsed_failure_keeps_runtime_exit_fresh(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 2
        build.digest = "0000000000000001"
        build.failures = {
            "dvl-lang-00001-type": ("0000000000000005", "0000000000000006"),
        }
        build.failure_occurrences = {"dvl-lang-00001-type": 1}
        build.reported_failures = 2
        runtime = [{"kind": "runtime-failed", "build": "release"}]
        known = [{
            "kind": "model-mismatch",
            "check": "dvl-lang-00001-type",
            "builds": {"release": "0000000000000005"},
            "known": "dvl-0014",
        }]

        findings, known_hits = run_devil_gate.absorb_derived_known_effects(
            runtime, known, [build])

        self.assertEqual(findings, runtime)
        self.assertEqual(known_hits, known)

    def test_runtime_exit_stays_fresh_without_named_known_failures(self) -> None:
        build = run_devil_gate.Build("release")
        build.compiled = True
        build.run_exit = 217
        build.digest = "0000000000000001"
        runtime = [{"kind": "runtime-failed", "build": "release"}]

        findings, known_hits = run_devil_gate.absorb_derived_known_effects(
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

        findings, known_hits = run_devil_gate.absorb_derived_known_effects(
            runtime, known, [build])

        self.assertEqual(findings, runtime)
        self.assertEqual(known_hits, known)

    def test_main_report_keeps_known_hits(self) -> None:
        def build(_work: Path, profile: str, _defines: list[str],
                  _timeout: int, _program_timeout: int,
                  reuse: bool = False) -> run_devil_gate.Build:
            result = run_devil_gate.Build(profile + ("+reuse" if reuse else ""))
            result.compiled = True
            result.layers = {"gen"}
            result.layers_occurrences = 1
            result.layers_line = 0
            result.first_protocol_line = 0
            result.checks = 1
            result.digest = "0000000000000001"
            result.summary_occurrences = 1
            result.summary_seed = 1
            result.summary_line = 5
            result.last_nonempty_line = 5
            result.finalization_occurrences = 1
            result.finalization_checks = 1
            result.finalization_line = 4
            result.reported_failures = 0
            result.layer_digests = {"gen": result.digest}
            result.layer_digest_occurrences = {"gen": 1}
            result.counters = {"FEEDS": 1, "STEPS": 1}
            result.counter_occurrences = {"FEEDS": 1, "STEPS": 1}
            result.failures["dvl-gen-00109-nested"] = (
                "00000000FFFF8001", "0000000000008001"
            )
            result.failure_occurrences["dvl-gen-00109-nested"] = 1
            result.check_events["dvl-gen-00109-nested"] = [
                ("00000000FFFF8001", "0000000000008001"),
            ]
            result.check_event_order = [
                ("dvl-gen-00109-nested", "00000000FFFF8001",
                 "0000000000008001", 1),
            ]
            result.check_occurrences["dvl-gen-00109-nested"] = 1
            result.reported_failures = 1
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
                      "failing_side": "moon",
                      "actual": "^00000000FFFF8001$",
                      "expected": "^0000000000008001$",
                  }]),
                  mock.patch.object(run_devil_gate, "build_fpc", side_effect=build),
                  redirect_stdout(io.StringIO())):
                with self.assertRaisesRegex(SystemExit, "^0$"):
                    run_devil_gate.main()
            row = json.loads(report.read_text(encoding="utf-8"))[0]
        self.assertEqual(row["findings"], [])
        self.assertIn("dvl-0043", {hit["known"] for hit in row["known_hits"]})

    def test_minimizer_signature_requires_finalization_and_matching_exit(self) -> None:
        healthy = (
            "DEVIL_CHECK dvl-min-00001 actual=0000000000000001 "
            "expected=0000000000000001\n"
            "DEVIL_CHECK dvl-min-00002 actual=0000000000000002 "
            "expected=0000000000000002\n"
            "DEVIL_CHECK dvl-min-00003 actual=0000000000000003 "
            "expected=0000000000000003\n"
            "DEVIL_FINALIZATION checks=3\n"
            "DEVIL_MIN_PASS seed=1 checks=3 digest=0000000000000001\n"
        )
        valid, signature, error = devil_minimize.runtime_signature(0, healthy)
        self.assertTrue(valid)
        self.assertEqual(signature[0], 0)
        self.assertEqual(error, "")

        for code, output in (
            (73, healthy),
            (0, healthy.replace("DEVIL_FINALIZATION checks=3\n", "")),
        ):
            valid, _, _ = devil_minimize.runtime_signature(code, output)
            self.assertFalse(valid)

        failing = (
            "DEVIL_CHECK dvl-min-00001 actual=0000000000000001 "
            "expected=0000000000000002\n"
            "DEVIL_FAILURE dvl-min-00001 actual=0000000000000001 "
            "expected=0000000000000002\n"
            "DEVIL_CHECK dvl-min-00002 actual=0000000000000002 "
            "expected=0000000000000002\n"
            "DEVIL_CHECK dvl-min-00003 actual=0000000000000003 "
            "expected=0000000000000003\n"
            "DEVIL_FINALIZATION checks=3\n"
            "DEVIL_MIN_FAIL seed=1 failures=1 checks=3 "
            "digest=0000000000000001\n"
        )
        valid, _, _ = devil_minimize.runtime_signature(0, failing)
        self.assertTrue(valid)

        valid, _, error = devil_minimize.runtime_signature(
            0, healthy.replace("PASS", "FAIL"))
        self.assertFalse(valid)
        self.assertIn("terminal summaries=0", error)

        for malformed in (
            "DEVIL_MIN_FAIL seed=1 failures=0 checks=3 ",
            "DEVIL_MIN_FAIL seed=1 failures=-1 checks=3 ",
            "DEVIL_MIN_PASS seed=1 failures=0 checks=3 ",
        ):
            valid, _, error = devil_minimize.runtime_signature(
                0,
                "DEVIL_FINALIZATION checks=3\n" + malformed
                + "digest=0000000000000001\n",
            )
            self.assertFalse(valid)
            self.assertIn("terminal summaries=0", error)

        note_one = healthy.replace(
            "DEVIL_FINALIZATION",
            "DEVIL_NOTE dvl-min-00001-value=0000000000000001\n"
            "DEVIL_FINALIZATION",
        )
        note_other = note_one.replace("value=0000000000000001",
                                      "value=0000000000000063")
        valid_one, signature_one, _ = devil_minimize.runtime_signature(
            0, note_one, 1)
        valid_other, signature_other, _ = devil_minimize.runtime_signature(
            0, note_other, 1)
        self.assertTrue(valid_one and valid_other)
        self.assertNotEqual(signature_one, signature_other)

        valid, _, error = devil_minimize.runtime_signature(0, healthy, 2)
        self.assertFalse(valid)
        self.assertIn("terminal seed=1, expected=2", error)

        for corrupted in (
            healthy + "DEVIL_FAILURE broken\n",
            "DEVIL_BROKEN record\n" + healthy,
            healthy.replace("DEVIL_FINALIZATION checks=3\n", "")
            + "DEVIL_FINALIZATION checks=3\n",
        ):
            valid, _, _ = devil_minimize.runtime_signature(0, corrupted)
            self.assertFalse(valid)

    def test_minimizer_keeps_outer_body_after_nested_end(self) -> None:
        source = """procedure DvlFlow00008;
begin
  case Value of
    1: Value := 2;
  end;
  DevilCheckU('dvl-flow-00008-case', Value, 2);
end;

procedure DvlFlow00009;
begin
end;
"""
        spans = devil_minimize.collect_routines(source)
        _, start, end = next(span for span in spans
                             if span[0] == "DvlFlow00008")
        routine = "\n".join(source.splitlines()[start:end])
        self.assertIn("DevilCheckU('dvl-flow-00008-case'", routine)
        self.assertEqual(routine.count("end;"), 2)

    def test_minimizer_keeps_every_overload_and_forward(self) -> None:
        source = """function DvlPick00007(X: Integer): Integer; overload; forward;
function DvlPick00007(X: AnsiString): Integer; overload; forward;
function DvlPick00007(X: Integer): Integer;
begin
  Result := 1;
end;
function DvlPick00007(X: AnsiString): Integer;
begin
  Result := 2;
end;
procedure DvlDecl00007;
begin
end;
"""
        spans = [span for span in devil_minimize.collect_routines(source)
                 if "00007" in span[0]]
        self.assertEqual([span[0] for span in spans].count("DvlPick00007"), 4)
        self.assertEqual(len(spans), 5)
        lines = source.splitlines()
        self.assertIn("forward", "\n".join(lines[spans[0][1]:spans[0][2]]))
        self.assertIn("Result := 2", "\n".join(
            lines[spans[3][1]:spans[3][2]]))

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

    def test_mutation_baseline_includes_compilation_topology(self) -> None:
        selected = [
            ("fdc3fe589", "unit", "unit,ppu,gen", "ppu replay"),
            ("97d756c49", "flow", "flow,opt", "runtime bounds"),
        ]
        self.assertEqual(
            run_devil_mutation.baseline_configs(selected, False),
            [("flow,opt", ()),
             ("unit,ppu,gen", ("--separate-units", "--ppu-reuse"))],
        )

    def test_current_tree_semantic_mutations_are_tracked(self) -> None:
        mutation_dir = DEVIL / "mutations"
        self.assertEqual(
            set(run_devil_mutation.MUTANT_PATCH_FILES),
            {"0443351d9", "1dc18026c", "46517131a", "97971e5ab"},
        )
        for patch_name in run_devil_mutation.MUTANT_PATCH_FILES.values():
            patch = mutation_dir / patch_name
            self.assertTrue(patch.is_file(), patch)
            text = patch.read_text(encoding="utf-8")
            self.assertTrue(any(
                f"diff --git a/{path}/" in text
                for path in run_devil_mutation.PRODUCT_PATHS
            ))
            self.assertNotIn("diff --git a/tests/", text)

    def test_mutation_inventory_separates_semantics_from_other_evidence(self) -> None:
        mutants = {row[0]: row for row in run_devil_mutation.MUTANTS}
        exclusions = {row[0]: row for row in run_devil_mutation.MUTANT_EXCLUSIONS}
        self.assertFalse(mutants.keys() & exclusions.keys())
        self.assertIn("lit", mutants["68b22a332"][2].split(","))
        self.assertEqual(exclusions["532371a00"][1], "code-shape")

    def test_mutation_rejects_missing_or_dangling_repair_before_apply(self) -> None:
        for code, log in ((1, ""), (128, "fatal: Not a valid commit name")):
            with self.subTest(code=code), mock.patch.object(
                    run_devil_mutation, "git", return_value=(code, log)) as git:
                valid, detail = run_devil_mutation.apply_product_mutation("old-repair", check_only=True)
                self.assertFalse(valid)
                self.assertIn("old-repair is unavailable in HEAD ancestry", detail)
                git.assert_called_once_with(["merge-base", "--is-ancestor", "old-repair", "HEAD"])

    def test_mutation_check_only_never_builds_or_changes_files(self) -> None:
        with (mock.patch.object(sys, "argv", ["mutation", "--check-only"]),
              mock.patch.object(run_devil_mutation, "git") as git,
              mock.patch.object(run_devil_mutation, "rebuild") as rebuild,
              mock.patch.object(run_devil_mutation, "apply_product_mutation",
                                return_value=(True, "")) as apply,
              redirect_stdout(io.StringIO()) as output):
            run_devil_mutation.main()
        self.assertIn("applicable=18/18", output.getvalue())
        self.assertEqual(apply.call_args_list, [
            mock.call(row[0], check_only=True) for row in run_devil_mutation.MUTANTS
        ])
        git.assert_not_called()
        rebuild.assert_not_called()

    def test_mutation_check_only_reports_invalid_inventory_without_building(self) -> None:
        with (mock.patch.object(sys, "argv", ["mutation", "--check-only"]),
              mock.patch.object(run_devil_mutation, "rebuild") as rebuild,
              mock.patch.object(run_devil_mutation, "apply_product_mutation",
                                return_value=(False, "missing repair")),
              redirect_stdout(io.StringIO()) as output):
            with self.assertRaisesRegex(SystemExit, "non-applicable patches"):
                run_devil_mutation.main()
        self.assertIn("missing repair", output.getvalue())
        rebuild.assert_not_called()


if __name__ == "__main__":
    unittest.main()
