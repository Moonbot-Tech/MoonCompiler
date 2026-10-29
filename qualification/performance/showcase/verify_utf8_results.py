"""Recheck archived lookup/trade outputs against independent values, including negative controls."""
import copy
import json
import pathlib
import sys
from run import check

evidence = pathlib.Path(sys.argv[1])
expected = {"markets": json.loads((evidence / "oracle.json").read_text(encoding="utf-8")),
            "trade_count": json.loads((evidence / "manifest.json").read_text())["trades"]}
checksums = {}
for count in (3742, 100000):
    state = 123456789
    total = 0
    for _ in range(200000):
        state = (state * 1664525 + 1013904223) & 0xffffffff
        index = state % (count + count // 9)
        if index < count:
            total += index * 17 + 3
    checksums[count] = total * 5
checked = rejected = 0
lookup_hashes, trade_hashes = [], []
for host in ("hel1", "amd"):
    lookup = evidence / f"{host}-final-v2"
    lookup_hashes.append(json.loads((lookup / "host.json").read_text())["binary_sha256"])
    rows = json.loads((lookup / "measurements.json").read_text())
    assert len(rows) == 5 * 2 * 3 * 6
    for r in rows:
        assert r["checksum"] == checksums[r["entries"]]
        assert r["lookup_allocations"] == r["lookup_frees"] == 0
        assert r["lookup_cpu_ns"] > 0 and r["queries"] == 1000000
        checked += 1
    trades = evidence / f"{host}-trades-v2"
    trade_hashes.append(json.loads((trades / "host.json").read_text())["binaries"])
    rows = json.loads((trades / "measurements.json").read_text())
    assert len(rows) == 5 * 4
    for r in rows:
        output = trades / f"{r['pair']}-{r['engine']}.output"
        check(r, "trades", 4, output, expected)
        checked += 1
        for key in ("count", "operations"):
            bad = copy.copy(r)
            bad[key] += 1
            try:
                check(bad, "trades", 4, output, expected)
            except AssertionError:
                rejected += 1
            else:
                raise AssertionError("Bad summary accepted")

        class BadTurnover:
            def read_text(self, **kw):
                lines = output.read_text(**kw).splitlines()
                fields = lines[0].split("\t")
                fields[3] = "0"
                lines[0] = "\t".join(fields)
                return "\n".join(lines)

        try:
            check(r, "trades", 4, BadTurnover(), expected)
        except AssertionError:
            rejected += 1
        else:
            raise AssertionError("Bad market turnover accepted")
assert lookup_hashes[0] == lookup_hashes[1]
assert trade_hashes[0] == trade_hashes[1]
print(f"PASS: {checked} outputs, {rejected} rejected corruptions, identical binaries across hosts")
