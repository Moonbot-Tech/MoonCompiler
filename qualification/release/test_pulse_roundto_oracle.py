"""A proved old answer must never excuse a wrong candidate or unrelated failure."""
import copy
from types import SimpleNamespace
import unittest
from unittest import mock

from qualification.release import pulse_roundto_oracle as oracle


EXACT = "010C9D1BA2D0D398"
LEGACY = "010C9D1BA2D0D343"
SINGLE = "000000B850724F80"


def recorded_case():
    records = []
    for repeat in range(12):
        for variant, digest in (("moon-baseline", LEGACY), ("moon-candidate", EXACT)):
            records.append({
                "program": "repairs", "case": "roundto-minus8", "variant": variant,
                "repeat": repeat, "iterations": 93260, "fixed_work": True,
                "sha256": oracle.EXE_SHA[variant], "derived": {"valid": True},
                "case_definition": {"oracle": SINGLE, "iterations": "93260", "operations": "5968640"},
                "samples": [{"digest": digest, "iterations": 93260, "operations": 5968640} for _ in range(3)],
            })
    return {"git_head": "reviewed-source", "cases": {oracle.CASE: {"final": {
        "semantic_match": False, "valid_pairs": 12, "attempted_pairs": 12, "records": records,
    }}}}


class RoundToProofTests(unittest.TestCase):
    def setUp(self):
        self.source = mock.patch.object(oracle.subprocess, "run", return_value=SimpleNamespace(stdout=oracle.CASE_SOURCE_BLOB))
        self.source.start()
        self.addCleanup(self.source.stop)

    def test_exact_full_stream_matches_recorded_candidate_and_reproduces_old_error(self):
        self.assertEqual(oracle.model(93260), (EXACT, LEGACY, 85))
        self.assertEqual(oracle.model(1), (SINGLE, SINGLE, 0))
        result = recorded_case()
        unchanged = copy.deepcopy(result)
        proof = oracle.prove(result)
        self.assertEqual(proof["legacy_wrong_calls"], 85)
        self.assertEqual(proof["speed_comparison"], "excluded")
        self.assertEqual(result, unchanged)  # Never rewrite semantic_match or the measured answer.

    def test_wrong_candidate_is_not_excused_by_correct_baseline_error(self):
        result = recorded_case()
        result["cases"][oracle.CASE]["final"]["records"][1]["samples"][0]["digest"] = LEGACY
        with self.assertRaises(ValueError):
            oracle.prove(result)

    def test_changed_work_identity_or_oracle_is_rejected(self):
        mutations = [
            lambda r: r.update(sha256="0" * 64),
            lambda r: r.update(iterations=93261),
            lambda r: r.update(fixed_work=False),
            lambda r: r.update(program="other"),
            lambda r: r["derived"].update(valid=False),
            lambda r: r["samples"][0].update(operations=5968639),
            lambda r: r["samples"][0].update(iterations=93261),
            lambda r: r["case_definition"].update(oracle="0" * 16),
            lambda r: r["case_definition"].update(operations="5968639"),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                result = recorded_case()
                mutate(result["cases"][oracle.CASE]["final"]["records"][1])
                with self.assertRaises(ValueError):
                    oracle.prove(result)

    def test_wrong_input_source_is_rejected(self):
        oracle.subprocess.run.return_value.stdout = "0" * 40
        with self.assertRaisesRegex(ValueError, "source changed"):
            oracle.prove(recorded_case())

    def test_missing_or_duplicate_repeat_is_rejected(self):
        for missing in (True, False):
            with self.subTest(missing=missing):
                result = recorded_case()
                final = result["cases"][oracle.CASE]["final"]
                if missing:
                    final["records"].pop()
                else:
                    final["records"][-1]["repeat"] = 0
                with self.assertRaises(ValueError):
                    oracle.prove(result)

    def test_unrelated_mismatch_remains_an_error(self):
        result = recorded_case()
        result["cases"]["repairs/other"] = {"final": {"semantic_match": False}}
        with self.assertRaisesRegex(ValueError, "unknown Pulse semantic mismatch"):
            oracle.prove(result)

    def test_unchecked_speed_confirmation_is_not_admitted(self):
        result = recorded_case()
        row = result["cases"][oracle.CASE]
        row["confirmation"] = {"final": {"semantic_match": False}}
        with self.assertRaisesRegex(ValueError, "speed confirmation"):
            oracle.prove(result)

    def test_equal_results_need_no_exception(self):
        result = {"cases": {"ordinary/case": {"final": {"semantic_match": True}}}}
        self.assertIsNone(oracle.prove(result))
        oracle.subprocess.run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
