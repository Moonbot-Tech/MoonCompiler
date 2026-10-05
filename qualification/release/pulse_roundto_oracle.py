"""Prove the one known RoundTo baseline mismatch without comparing its speed."""

from __future__ import annotations

import subprocess
from functools import lru_cache
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CASE = "repairs/roundto-minus8"
CASE_SOURCE = "qualification/performance/repairs/pulse_repairs.dpr"
CASE_SOURCE_BLOB = "3ac1061eeaac9c5c792300a055a188b29e4828de"
ITERATIONS = 93260
EXE_SHA = {
    "moon-baseline": "e8ad9b3a585e23a092fb17189a83be8dfe8d7b36ae55053eb0956696fb5352be",
    "moon-candidate": "c473a370d61d57e1d8aacdc4fd4af09d95ca4b3c2c82b0512c856ed7ce5fe537",
}


@lru_cache(maxsize=2)
def model(iterations: int) -> tuple[str, str, int]:
    """Exact binary input buckets and the released invert-then-square formula."""
    scale = 1.0 / 10.0
    for _ in range(3):
        scale *= scale
    value = 123.456789
    exact = old = differences = 0
    for step in range(iterations * 64):
        number = value + (step & 15) * 0.03125
        numerator, denominator = number.as_integer_ratio()
        bucket, remainder = divmod(numerator * 100000000, denominator)
        bucket += 2 * remainder > denominator or (2 * remainder == denominator and bucket & 1)
        old_bucket = round(round(number / scale) * scale * 100000000.0)
        exact += bucket
        old += old_bucket
        differences += bucket != old_bucket
        value += 0.000001
    return f"{exact:016X}", f"{old:016X}", differences


def prove(result: dict) -> dict | None:
    mismatches = {name for name, row in result["cases"].items() if not row["final"]["semantic_match"]}
    mismatches.update(name for name, row in result["cases"].items()
                      if row.get("confirmation") and not row["confirmation"]["final"]["semantic_match"])
    if not mismatches:
        return None
    if mismatches != {CASE}:
        raise ValueError(f"unknown Pulse semantic mismatch: {sorted(mismatches)}")
    blob = subprocess.run(["git", "rev-parse", f"{result['git_head']}:{CASE_SOURCE}"],
                          cwd=ROOT, text=True, check=True, capture_output=True).stdout.strip()
    if blob != CASE_SOURCE_BLOB:
        raise ValueError("RoundTo input-stream source changed")
    row = result["cases"][CASE]
    if row.get("confirmation"):
        raise ValueError("noncomparable RoundTo work must not contribute speed confirmation")
    final = row["final"]
    records = final["records"]
    if final["valid_pairs"] != 12 or final["attempted_pairs"] != 12 or len(records) != 24:
        raise ValueError("RoundTo needs all twelve clean measured pairs")
    exact, old, differences = model(ITERATIONS)
    one_iteration, _, _ = model(1)
    if differences != 85:
        raise ValueError("RoundTo baseline difference changed")
    for repeat in range(12):
        pair = [record for record in records if record["repeat"] == repeat]
        if len(pair) != 2 or {record["variant"] for record in pair} != set(EXE_SHA):
            raise ValueError("RoundTo repeat grid changed")
        for record in pair:
            expected = exact if record["variant"] == "moon-candidate" else old
            if (record["program"] != "repairs" or record["case"] != "roundto-minus8" or
                    not record["fixed_work"] or not record["derived"]["valid"] or record["iterations"] != ITERATIONS or
                    record["sha256"] != EXE_SHA[record["variant"]] or
                    record["case_definition"]["oracle"] != one_iteration or
                    int(record["case_definition"]["iterations"]) != ITERATIONS or
                    int(record["case_definition"]["operations"]) != ITERATIONS * 64 or
                    len(record["samples"]) != 3 or
                    any(sample["digest"] != expected or sample["iterations"] != ITERATIONS or
                        sample["operations"] != ITERATIONS * 64 for sample in record["samples"])):
                raise ValueError(f"RoundTo source, work, binary, oracle or measured digest changed: repeat={repeat}")
    return {"case": CASE, "source_blob": blob, "iterations": ITERATIONS, "operations": ITERATIONS * 64,
            "candidate_exact_digest": exact, "baseline_legacy_digest": old,
            "one_iteration_oracle": one_iteration, "legacy_wrong_calls": differences,
            "executable_sha256": EXE_SHA, "speed_comparison": "excluded"}
