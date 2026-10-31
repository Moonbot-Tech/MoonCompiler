"""Independent oracles and full document validation. Run separately from measurement processes."""

import argparse
import json
import math
import pathlib
import subprocess

from audit_timer_oracle import timer_checksum

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--json-only", action="store_true", help="Check only the applied JSON examples")
args = parser.parse_args()

root = pathlib.Path(__file__).resolve().parent
data = root / "data"
out = root / "validation"
out.mkdir(exist_ok=True)
info = json.loads((data / "exchangeInfo.json").read_bytes())
expected = {
    "trade_count": json.loads((data / "manifest.json").read_text())["trades"],
    "exchange": {
        "count": len(info["symbols"]),
        "names": sum(len(x["symbol"].encode()) for x in info["symbols"]),
        "filters": sum(len(x["filters"]) for x in info["symbols"]),
        "input_bytes": (data / "exchangeInfo.json").stat().st_size,
    },
}


def same(a, b, path="root"):
    assert type(a) == type(b) or type(a) in (int, float) and type(b) in (int, float), (
        path
    )
    if isinstance(a, dict):
        assert a.keys() == b.keys(), path
        for k in a:
            same(a[k], b[k], path + "." + k)
    elif isinstance(a, list):
        assert len(a) == len(b), path
        for i, (x, y) in enumerate(zip(a, b)):
            same(x, y, path + f"[{i}]")
    elif isinstance(a, float):
        assert math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-14), path
    else:
        assert a == b, (path, a, b)


for engine in ("moon", "rust"):
    target = out / f"exchange-{engine}.json"
    subprocess.run(
        [
            str(root / "bin" / ("showcase_" + engine)),
            "exchange",
            str(data),
            "1",
            str(target),
        ],
        check=True,
    )
    same(info, json.loads(target.read_bytes()))
print("FULL_EXCHANGE_DOCUMENT_PASS", flush=True)
del info
if args.json_only:
    (root / "expected.json").write_text(json.dumps(expected, indent=2))
    raise SystemExit(0)

prefix_b = [0.0]
prefix_s = [0.0]
prefix_q = [0.0]
for i in range(262144):
    p = (i % 10000 + 1) / 64
    q = (i % 100 + 1) / 128
    prefix_b.append(prefix_b[-1] + (p * q if i % 2 == 0 else 0))
    prefix_s.append(prefix_s[-1] + (p * q if i % 2 else 0))
    prefix_q.append(prefix_q[-1] + q)
expected["analytics"] = {}
for passes in (1, 128):
    total = 0.0
    for j in range(passes * 4096):
        k = 512 + (j * 7919) % (262144 - 512)
        n = 64 + j % 449
        lo = k - n
        b = prefix_b[k] - prefix_b[lo]
        s = prefix_s[k] - prefix_s[lo]
        q = prefix_q[k] - prefix_q[lo]
        maximum = (
            10000 / 64
            if lo // 10000 != (k - 1) // 10000
            else ((k - 1) % 10000 + 1) / 64
        )
        total += b + s + maximum + (b + s) / q
    expected["analytics"][str(passes)] = total

expected["timers"] = {
    str(passes): timer_checksum(passes * 100000) for passes in (1, 32)
}
state = 123456789
check = 0
final = {i: i * 17 + 3 for i in range(100000)}
for i in range(1000000):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    q = state % 111111
    if q < 100000:
        check += q * 17 + 3
    final[q] = i + 5
expected["dict_string_one"] = check
expected["dict_final"] = {"5": {"count": len(final), "checksum": sum(final.values())}}
(root / "expected.json").write_text(json.dumps(expected, indent=2))
print("INDEPENDENT_ORACLES_PASS", flush=True)
