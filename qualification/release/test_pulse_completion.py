"""Portable refusal and batch-context contracts for bounded Pulse completion."""

import gzip
import hashlib
import json
import os
import platform
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pulse_completion as completion


def record(name, variant, repeat, *, valid=True, log=""):
    return {"program": "move", "case": name, "category": "memory-local", "variant": variant,
            "repeat": repeat, "iterations": 100, "duration_ms": 60, "fixed_work": True,
            "stack_phase": completion.full.stack_phase("grid", repeat), "derived": {"valid": valid},
            "sha256": variant, "affinity": [0 if variant == "moon-baseline" else 1], "log": log}


def matrix():
    names = ("hot-a0-a0-n0", "hot-a0-a0-n1")
    batch_id = hashlib.sha256(",".join(names).encode()).hexdigest()[:8]
    rows = {}
    for name in names:
        records = []
        for repeat in range(12):
            prefix = f"move-batch-{names[0]}-2-{batch_id}"
            for variant in completion.full.SYSTEMS:
                records.append(record(name, variant, repeat,
                                      valid=not (name == names[0] and repeat == 4 and variant == "moon-baseline"),
                                      log=f"/output/{prefix}-{variant}-{repeat}.log"))
        rows["move/" + name] = {"program": "move", "case": name, "category": "memory-local",
                                "final": {"records": records, "valid_pairs": 11 if name == names[0] else 12,
                                          "semantic_match": True}}
    return {"stack_phase": "grid", "cases": rows}


class CompletionContracts(unittest.TestCase):
    def test_frozen_missing_pair_replays_whole_original_move_process(self):
        raw = matrix()
        missing, counts = completion.freeze_missing(raw)
        batches, individual = completion.move_batches(raw, missing)
        self.assertEqual(set(missing), {("move/hot-a0-a0-n0", 4)})
        self.assertEqual(batches, [(["move/hot-a0-a0-n0", "move/hot-a0-a0-n1"], 4)])
        self.assertEqual(individual, [])
        self.assertEqual(counts["move", "hot-a0-a0-n0"], (100, 60))

    def test_missing_or_duplicate_repeat_refused(self):
        raw = matrix()
        records = raw["cases"]["move/hot-a0-a0-n0"]["final"]["records"]
        records[0]["repeat"] = 1
        with self.assertRaisesRegex(ValueError, "repeat grid"):
            completion.freeze_missing(raw)

    def test_valid_pair_never_replaced(self):
        raw = matrix()
        pair = [record for record in raw["cases"]["move/hot-a0-a0-n1"]["final"]["records"]
                if record["repeat"] == 4]
        with self.assertRaisesRegex(ValueError, "original valid pair"):
            completion.replacement_pair("move/hot-a0-a0-n1", 4, pair, pair, (100, 60))

    def test_dirty_replacement_does_not_complete_pair(self):
        raw = matrix()
        missing, _ = completion.freeze_missing(raw)
        old = missing["move/hot-a0-a0-n0", 4]
        with self.assertRaisesRegex(ValueError, "replacement is dirty"):
            completion.replacement_pair("move/hot-a0-a0-n0", 4, old, old, (100, 60))

    def test_changed_physical_cpu_assignment_refused(self):
        raw = matrix()
        missing, _ = completion.freeze_missing(raw)
        old = missing["move/hot-a0-a0-n0", 4]
        measured = [{**record, "derived": {"valid": True}} for record in old]
        measured[0]["affinity"] = [2]
        with self.assertRaisesRegex(ValueError, "CPU assignment differs"):
            completion.replacement_pair("move/hot-a0-a0-n0", 4, old, measured, (100, 60))

    def test_json_affinity_roundtrip_accepts_same_cpu_but_not_other_cpu(self):
        raw = matrix()
        missing, _ = completion.freeze_missing(raw)
        old = missing["move/hot-a0-a0-n0", 4]
        measured = [{**record, "affinity": tuple(record["affinity"]), "derived": {"valid": True}}
                    for record in old]
        self.assertEqual(completion.replacement_pair("move/hot-a0-a0-n0", 4, old, measured, (100, 60)), measured)
        measured[0]["affinity"] = (2,)
        with self.assertRaisesRegex(ValueError, "CPU assignment differs"):
            completion.replacement_pair("move/hot-a0-a0-n0", 4, old, measured, (100, 60))

    def test_only_the_reviewed_git_blob_pair_may_bridge_full_measurements(self):
        previous = {name: blobs[0] for name, blobs in completion.ALLOWED_METHOD_BRIDGE.items()}
        current = {name: blobs[1] for name, blobs in completion.ALLOWED_METHOD_BRIDGE.items()}
        def git(*args):
            return "" if args[0] == "status" else "completion-head"
        with (mock.patch.object(completion, "git", side_effect=git),
              mock.patch.object(completion, "measurement_blobs", side_effect=[previous, current])):
            proof = completion.verify_method("source-head")
        self.assertEqual(set(proof["changed_git_blobs"]), set(previous))
        with (mock.patch.object(completion, "git", side_effect=git),
              mock.patch.object(completion, "measurement_blobs", side_effect=[previous, {**current, "other.py": "x"}])):
            with self.assertRaisesRegex(ValueError, "build or measurement source changed"):
                completion.verify_method("source-head")
        wrong = {**current, next(iter(current)): "x"}
        with (mock.patch.object(completion, "git", side_effect=git),
              mock.patch.object(completion, "measurement_blobs", side_effect=[previous, wrong])):
            with self.assertRaisesRegex(ValueError, "build or measurement source changed"):
                completion.verify_method("source-head")

    def test_candidate_first_keeps_the_original_physical_pair(self):
        old = [record("name", "moon-candidate", 3), record("name", "moon-baseline", 3)]
        old[0]["affinity"], old[1]["affinity"] = [7], [8]
        self.assertEqual(completion.original_cpu_pair(old, "memory-local", (7, 8), (0, 2)), (7, 8))

    def test_changed_batch_context_refused(self):
        raw = matrix()
        missing, _ = completion.freeze_missing(raw)
        raw["cases"]["move/hot-a0-a0-n1"]["final"]["records"][8]["log"] = "/output/other-moon-baseline-4.log"
        with self.assertRaisesRegex(ValueError, "Move batch"):
            completion.move_batches(raw, missing)

    def test_wrong_raw_sha_host_and_semantics_refused(self):
        raw = matrix()
        raw.update({"git_head": "a" * 40, "git_status": "", "pairs": 12,
                    "scope": {"cases": "all", "programs": completion.pulse.stand_programs(True)},
                    "confirmation_required": True, "preflight": {"passed": True},
                    "confirmation_preflight": {"passed": True},
                    "l2_calibration": {"machine": "alien-host"},
                    "machine": {"platform": platform.platform(), "logical_cpus": os.cpu_count()}})
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            path = source / "result.raw.json.gz"
            path.write_bytes(gzip.compress(json.dumps(raw).encode()))
            sha = completion.sha256(path)
            (source / "result.json").write_text(json.dumps({"raw_sha256": sha}))
            with self.assertRaisesRegex(ValueError, "raw SHA"):
                completion.source_raw(source, "0" * 64, "0" * 64)
            with mock.patch.object(completion, "verify_method"):
                with self.assertRaisesRegex(ValueError, "host key"):
                    completion.source_raw(source, sha, "0" * 64)
            raw["cases"]["move/hot-a0-a0-n0"]["final"]["semantic_match"] = False
            path.write_bytes(gzip.compress(json.dumps(raw).encode()))
            sha = completion.sha256(path)
            (source / "result.json").write_text(json.dumps({"raw_sha256": sha}))
            with mock.patch.object(completion, "verify_method"):
                with self.assertRaisesRegex(ValueError, "semantic mismatch"):
                    completion.source_raw(source, sha, "0" * 64)

    def test_log_bytes_and_executable_bytes_must_match_origin(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            log = root / "source.log"
            log.write_bytes(b"original")
            manifest = root / "SOURCE_LOGS_SHA256.json"
            manifest.write_text(json.dumps({str(log): completion.sha256(log)}))
            source = {"record": {"log": str(log)}}
            self.assertEqual(completion.verify_log_manifest(source, root, completion.sha256(manifest))["path"],
                             str(manifest.resolve()))
            log.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "original log changed"):
                completion.verify_log_manifest(source, root, completion.sha256(manifest))
            left, right, calibration, mm = (root / name for name in ("left", "right", "calibration", "mm"))
            for path in (left, right, calibration, mm):
                path.write_bytes(path.name.encode())
            identity = {"same": True}
            preflight = {"analysis": {"valid_pairs": 6, "semantic_match": True,
                                      "records": [{"program": "calibration", "sha256": completion.sha256(calibration)}] * 12}}
            raw = {"baseline_toolchain": identity, "candidate_toolchain": identity,
                   "memory_managers": {name: {"sha256": completion.sha256(mm)}
                                       for name in completion.full.SYSTEMS},
                   "built": {"moon-baseline": {"demo": str(left)},
                             "moon-candidate": {"demo": str(right), "calibration": str(calibration)}},
                   "cases": {"demo/case": {"final": {"records": [
                       {"variant": "moon-baseline", "program": "demo", "sha256": completion.sha256(left)},
                       {"variant": "moon-candidate", "program": "demo", "sha256": completion.sha256(right)},
                   ]}}}, "preflight": preflight, "confirmation_preflight": preflight}
            with mock.patch.object(completion.pulse, "moon_toolchain_identity", return_value=identity):
                completion.verify_binaries(raw, root, root, mm, mm)
                right.write_bytes(b"changed")
                with self.assertRaisesRegex(ValueError, "measured executable changed"):
                    completion.verify_binaries(raw, root, root, mm, mm)

    def test_log_manifest_resolves_source_but_refuses_external_logs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            alias = source / ".." / source.name
            log = source / "case.log"
            log.write_bytes(b"original")
            manifest = source / "SOURCE_LOGS_SHA256.json"
            manifest.write_text(json.dumps({str(log): completion.sha256(log)}))
            raw = {"record": {"log": str(log)}}
            receipt = completion.verify_log_manifest(raw, alias, completion.sha256(manifest))
            self.assertEqual(receipt["path"], str(manifest.resolve()))
            outside = source / ".." / "outside.log"
            outside.write_bytes(b"outside")
            manifest.write_text(json.dumps({str(outside): completion.sha256(outside)}))
            raw = {"record": {"log": str(outside)}}
            with self.assertRaisesRegex(ValueError, "original log escapes its output"):
                completion.verify_log_manifest(raw, alias, completion.sha256(manifest))

    def test_log_manifest_creation_is_bound_to_raw_and_preserves_existing_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            log = source / "case.log"
            log.write_bytes(b"original")
            raw_path = source / "result.raw.json.gz"
            raw_path.write_bytes(gzip.compress(json.dumps({"record": {"log": str(log)}}).encode()))
            (source / "result.json").write_text(json.dumps({"raw_sha256": completion.sha256(raw_path)}))
            receipt = completion.create_log_manifest(source)
            manifest = source / "SOURCE_LOGS_SHA256.json"
            before = manifest.read_bytes()
            self.assertEqual(receipt["count"], 1)
            self.assertEqual(receipt["sha256"], completion.sha256(manifest))
            self.assertEqual(completion.create_log_manifest(source), receipt)
            self.assertEqual(manifest.read_bytes(), before)
            command = [sys.executable, str(Path(completion.__file__)), "manifest", "--source", str(source)]
            self.assertEqual(json.loads(subprocess.check_output(command, text=True)), receipt)
            log.write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "existing source log manifest differs"):
                completion.create_log_manifest(source)
            (source / "result.json").write_text(json.dumps({"raw_sha256": "0" * 64}))
            with self.assertRaisesRegex(ValueError, "compact report"):
                completion.create_log_manifest(source)


if __name__ == "__main__":
    unittest.main()
