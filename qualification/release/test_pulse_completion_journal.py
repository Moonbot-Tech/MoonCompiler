"""Retained measurements survive an interrupted completion without resampling."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import pulse_completion as completion
from test_pulse_completion import record


class CompletionJournalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.output = self.root / "attempt-0005/out"
        self.output.mkdir(parents=True)
        self.members = ["move/early", "move/late"]
        self.missing = {(name, 4): [record(name[5:], variant, 4, valid=False)
                                   for variant in completion.full.SYSTEMS] for name in self.members}
        self.iterations = {("move", name[5:]): (100, 60) for name in self.members}
        self.plan = {"origin": {"source": "original", "raw_sha256": "raw", "source_head": "head",
                                "logs": {"sha256": "logs"}}, "completion_head": "new",
                     "frozen_missing": [{"cpu_pair": (0, 1)}], "max_attempts": 32,
                     "frozen_move_batches": [{"members": self.members, "repeat": 4}]}
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(completion, "verify_method", return_value={}).start()
        mock.patch.object(completion.method, "record_metrics", side_effect=lambda row, *a, **k: row["derived"]).start()

    def prior(self, number, *, dirty=False, speed=10):
        folder = self.root / f"attempt-{number:04d}/out"
        folder.mkdir(parents=True)
        (folder / "COMPLETION_ORIGIN.json").write_text(json.dumps(self.plan))
        (folder / "COMPLETION_PREFLIGHT.json").write_text('{"passed": true}')
        rows = []
        for variant in completion.full.SYSTEMS:
            image = folder / (variant + ".exe")
            image.write_bytes(variant.encode())
            log = folder / (variant + ".log")
            lines = []
            for name in self.members:
                case = name[5:]
                lines.append(f"PULSE_CASE program=pulse_move case={case}")
                lines.extend(f"PULSE_SAMPLE program=pulse_move case={case} speed={speed}" for _ in range(3))
                row = record(case, variant, 4, valid=not (dirty and case == "late"), log=str(log))
                row.update(executable=str(image), sha256=completion.sha256(image),
                           case_definition={"program": "pulse_move", "case": case},
                           samples=[{"program": "pulse_move", "case": case, "speed": speed}] * 3)
                rows.append(row)
                self.missing[name, 4][completion.full.SYSTEMS.index(variant)]["sha256"] = row["sha256"]
            log.write_text("\n".join(lines + ["PULSE_END program=pulse_move status=PASS"]) + "\n")
        completion.retain_attempt(folder, self.members, 4, rows)
        return folder, rows

    def resume(self):
        return completion.resume_pairs(self.output, self.plan, self.missing, self.iterations)

    def test_first_clean_pair_wins_and_dirty_pair_can_complete_later(self):
        first, rows = self.prior(2, dirty=True, speed=100)
        self.prior(3, speed=1)
        pairs, receipts = self.resume()
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs["move/early", 4][0]["samples"][0]["speed"], 100)
        self.assertEqual(pairs["move/late", 4][0]["samples"][0]["speed"], 1)
        self.assertEqual(len(receipts), 2)
        self.assertEqual(Path(receipts[0]["journal_snapshot"]).read_bytes(),
                         (first / "COMPLETION_ATTEMPTS.jsonl").read_bytes())
        self.assertEqual(len(receipts[0]["logs"]), 2)

    def test_other_source_plan_or_failed_control_cannot_supply_pairs(self):
        folder, _ = self.prior(2)
        for key in ("origin", "frozen_missing", "frozen_move_batches", "max_attempts"):
            plan = copy.deepcopy(self.plan)
            plan[key] = {} if key == "origin" else None
            (folder / "COMPLETION_ORIGIN.json").write_text(json.dumps(plan))
            with self.subTest(key=key):
                self.assertEqual(self.resume(), ({}, []))
        (folder / "COMPLETION_ORIGIN.json").write_text(json.dumps(self.plan))
        (folder / "COMPLETION_PREFLIGHT.json").write_text('{"passed": false}')
        self.assertEqual(self.resume(), ({}, []))

    def test_changed_work_cpu_phase_binary_or_log_is_refused(self):
        folder, rows = self.prior(2)
        journal = folder / "COMPLETION_ATTEMPTS.jsonl"
        for key, value in (("iterations", 101), ("affinity", [3]), ("stack_phase", 1),
                           ("sha256", "changed"), ("case_definition", {})):
            changed = copy.deepcopy(rows)
            changed[0][key] = value
            journal.write_text(json.dumps({"members": self.members, "repeat": 4, "records": changed}) + "\n")
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.resume()
        journal.write_text(json.dumps({"members": self.members[::-1], "repeat": 4, "records": rows}) + "\n")
        with self.assertRaisesRegex(ValueError, "context"):
            self.resume()

    def test_truncated_final_append_ignored_but_corrupt_complete_line_refused(self):
        folder, _ = self.prior(2)
        journal = folder / "COMPLETION_ATTEMPTS.jsonl"
        with journal.open("ab") as stream:
            stream.write(b'{"members":')
        self.assertEqual(len(self.resume()[0]), 2)
        with journal.open("ab") as stream:
            stream.write(b'\n')
        with self.assertRaises(json.JSONDecodeError):
            self.resume()

    def test_original_clean_pair_is_never_replaced_and_outside_layout_not_scanned(self):
        self.prior(2)
        del self.missing["move/early", 4]
        self.assertEqual(set(self.resume()[0]), {("move/late", 4)})
        self.assertEqual(completion.resume_pairs(self.root / "arbitrary", self.plan,
                                                 self.missing, self.iterations), ({}, []))

    def test_raw_metric_mismatch_refused(self):
        self.prior(2)
        with mock.patch.object(completion.method, "record_metrics", return_value={"valid": False}):
            with self.assertRaisesRegex(ValueError, "raw counters"):
                self.resume()


if __name__ == "__main__":
    unittest.main()
