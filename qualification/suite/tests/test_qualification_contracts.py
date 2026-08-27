from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path
from unittest import mock


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import qualification_contracts as contracts


class QualificationContractsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = contracts.load_json(contracts.MANIFEST_PATH)
        cls.locks = contracts.load_json(contracts.LOCKS_PATH)

    def test_current_inventory_and_targets_are_locked(self) -> None:
        gate, focused_digest = contracts.validate_focused_gate(
            self.manifest, self.locks, "win64-repairs"
        )
        layer, resident_digest = contracts.validate_resident_layer(
            self.manifest, self.locks
        )
        pairs = contracts.planned_pairs(gate)
        self.assertTrue(pairs)
        self.assertEqual(len(pairs), len(set(pairs)))
        self.assertEqual(len(focused_digest), 64)
        self.assertEqual(len(resident_digest), 64)
        self.assertEqual(layer["shapes"]["handoff"], {"carriers": 4, "laps": 8})

    def test_manifest_mutation_does_not_update_its_lock(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        manifest["focused_gates"]["win64-repairs"]["cases"][0]["source"] += ".lost"
        with self.assertRaisesRegex(contracts.ContractError, "lock mismatch"):
            contracts.validate_focused_gate(manifest, self.locks, "win64-repairs")

    def test_manifest_paths_are_canonical_and_cannot_escape(self) -> None:
        for value in (
            ".", "../outside.py", "C:/outside.py", "tests\\outside.py",
            "./tests/a.py",
        ):
            with self.subTest(value=value):
                with self.assertRaisesRegex(contracts.ContractError, "invalid test path"):
                    contracts.require_relative_posix_path(value, "test path")
        with self.assertRaisesRegex(contracts.ContractError, "escapes the repository"):
            contracts.require_repository_file_from_suite(
                "../../../outside.py", "test reference"
            )

    def test_duplicate_case_and_actual_rows_fail_closed(self) -> None:
        manifest = copy.deepcopy(self.manifest)
        gate = manifest["focused_gates"]["win64-repairs"]
        gate["cases"].append(copy.deepcopy(gate["cases"][0]))
        with self.assertRaisesRegex(contracts.ContractError, "duplicate focused case"):
            contracts.validate_focused_gate(manifest, self.locks, "win64-repairs")

        planned = [("one", "O2"), ("two", "O2")]
        with self.assertRaisesRegex(contracts.ContractError, "duplicate actual"):
            contracts.require_exact_actual(
                planned, [("one", "O2"), ("one", "O2"), ("two", "O2")]
            )
        with self.assertRaisesRegex(contracts.ContractError, "missing=.*two"):
            contracts.require_exact_actual(planned, [("one", "O2")])

    def test_case_can_only_disappear_via_explicit_retirement(self) -> None:
        baseline = copy.deepcopy(self.manifest)
        current = copy.deepcopy(self.manifest)
        removed = current["focused_gates"]["win64-repairs"]["cases"].pop(0)
        with mock.patch.object(contracts, "_git_manifest", return_value=baseline):
            with self.assertRaisesRegex(contracts.ContractError, "deleted instead of retired"):
                contracts.require_retirement_only(current)

        current = copy.deepcopy(self.manifest)
        case = current["focused_gates"]["win64-repairs"]["cases"][0]
        case["state"] = "retired"
        case["retirement_reason"] = "covered by a stronger replacement"
        case["replacement"] = current["focused_gates"]["win64-repairs"]["cases"][1]["id"]
        with mock.patch.object(contracts, "_git_manifest", return_value=baseline):
            contracts.require_retirement_only(current)
        self.assertTrue(removed["id"])

    def test_resident_stage_order_is_complete_unique_and_independently_locked(self) -> None:
        names = contracts.parse_resident_stage_output(
            "RESIDENT_STAGES 3\n"
            "RESIDENT_STAGE 0 alpha\n"
            "RESIDENT_STAGE 1 beta\n"
            "RESIDENT_STAGE 2 gamma\n"
        )
        self.assertEqual(names, ["alpha", "beta", "gamma"])
        with self.assertRaisesRegex(contracts.ContractError, "not contiguous"):
            contracts.parse_resident_stage_output(
                "RESIDENT_STAGES 2\nRESIDENT_STAGE 0 alpha\n"
            )
        with self.assertRaisesRegex(contracts.ContractError, "not unique"):
            contracts.parse_resident_stage_output(
                "RESIDENT_STAGES 2\n"
                "RESIDENT_STAGE 0 alpha\nRESIDENT_STAGE 1 alpha\n"
            )
        layer = self.manifest["qualification_layers"]["resident"]
        with self.assertRaisesRegex(contracts.ContractError, "lock mismatch"):
            contracts.require_resident_stage_lock(
                self.locks, layer["stage_lock"], names
            )


if __name__ == "__main__":
    unittest.main()
