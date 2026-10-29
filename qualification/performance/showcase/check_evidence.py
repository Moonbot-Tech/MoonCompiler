"""Recheck saved results, prove the checks reject corrupt output, and compare binary identities."""

import copy
import json
import pathlib
import sys

from run import CASES, check

evidence = pathlib.Path(sys.argv[1])
data = pathlib.Path(sys.argv[2])
expected = json.loads((evidence / "expected.json").read_text())
expected["markets"] = json.loads((data / "oracle.json").read_text(encoding="utf-8"))
expected["symbols"] = (data / "symbols.txt").read_text(encoding="utf-8").splitlines()
hosts = list((evidence / "results").iterdir())
hashes = []
checked = 0
rejected = 0
for host in hosts:
    hashes.append(json.loads((host / "host.json").read_text())["binaries"])
    for row in json.loads((host / "measurements.json").read_text()):
        mode = row["case"]
        passes = next(p for m, c, p in CASES if m == mode)
        output = host / f"{mode}-{row['pair']}-{row['engine']}.output"
        check(row, mode, passes, output, expected)
        checked += 1
        keys = {
            "trades": ["count", "operations"],
            "exchange": ["names", "count", "filters", "input_bytes"],
            "serialize": ["operations"],
            "analytics": ["result", "operations"],
            "timers": ["checksum"],
            "dict-string": ["checksum"],
            "dict-int-update": ["final_checksum", "final_count"],
            "dict-int-update-read": ["final_checksum", "final_count", "checksum"],
            "ring": ["operations", "threads"],
        }[mode]
        if mode == "trades" and "witness" in row:
            keys.append("witness")
        for key in keys:
            bad = copy.copy(row)
            bad[key] = row[key] * 1.1 + 1
            try:
                check(bad, mode, passes, output, expected)
            except AssertionError:
                rejected += 1
            else:
                raise AssertionError(f"undetected {mode}.{key}")
    # A bad per-market volume and damaged JSON row must fail independently of the summary.
    for mode in ("trades", "serialize"):
        row = next((
            r
            for r in json.loads((host / "measurements.json").read_text())
            if r["case"] == mode
        ), None)
        if row is None:
            continue
        path = host / f"{mode}-{row['pair']}-{row['engine']}.output"

        class Corrupt:
            def read_text(self, **kw):
                lines = path.read_text(**kw).splitlines()
                parts = lines[0].split("\t")
                parts[3] = "0"
                lines[0] = "\t".join(parts)
                return "\n".join(lines)

            def read_bytes(self):
                values = json.loads(path.read_bytes())
                values[0]["price"] = 0
                return json.dumps(values).encode()

        try:
            check(
                row,
                mode,
                next(p for m, c, p in CASES if m == mode),
                Corrupt(),
                expected,
            )
        except AssertionError:
            rejected += 1
        else:
            raise AssertionError("undetected corrupt " + mode)
assert all(h == hashes[0] for h in hashes), "different binaries on hosts"
print(
    f"PASS: {checked} measured outputs rechecked; {rejected} deliberate corruptions rejected; host binary hashes identical"
)
