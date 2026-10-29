#!/usr/bin/env python3
"""Prepare, independently verify, and measure the frozen order-book workload."""

import argparse
import copy
from decimal import Decimal, getcontext
import hashlib
import json
import math
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile

getcontext().prec = 50
ROOT = Path(__file__).resolve().parent
SOURCE_URL = "https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def prepare(directory):
    directory.mkdir(parents=True, exist_ok=True)
    manifest = []
    for scale, center in enumerate((Decimal("0.001"), Decimal("100"), Decimal("65000"))):
        for depth in (100, 1000, 5000):
            tick = center / 100000
            book = {"lastUpdateId": 900000000 + scale * 10000 + depth}
            for side, sign in (("bids", -1), ("asks", 1)):
                book[side] = [
                    [format(center + sign * tick * (index + 1), "f"),
                     format(Decimal(1 + (index * 37 + scale * 11) % 9999) / 100, ".8f")]
                    for index in range(depth)
                ]
            name = f"book-{scale}-{depth}.json"
            (directory / name).write_text(json.dumps(book, separators=(",", ":")), encoding="utf-8")
            total = sum(Decimal(p) * Decimal(q) for p, q in book["asks"])
            first = Decimal(book["asks"][0][0]) * Decimal(book["asks"][0][1])
            budgets = (first / 2, total * Decimal("0.55"), total * Decimal("1.2"))
            manifest.append("\t".join((name, *(str(b) for b in budgets))))
    (directory / "manifest.tsv").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    write_json(directory / "provenance.json", {
        "synthetic": True, "format": "Binance Spot GET /api/v3/depth",
        "reference": SOURCE_URL, "depth_per_side": [100, 1000, 5000],
        "description": "Nine varied sorted books; half-first-level, 55%-depth and insufficient-depth budgets.",
        "hashes": {p.name: sha(p) for p in sorted(directory.glob("*.json")) if p.name != "provenance.json"},
    })


def inputs(directory):
    for line in (directory / "manifest.tsv").read_text().splitlines():
        name, *budgets = line.split("\t")
        yield json.loads((directory / name).read_text()), [Decimal(b) for b in budgets]


def buy(asks, budget, cast=Decimal):
    remaining = cast(budget)
    quantity = spent = last = cast(0)
    for price, volume in asks:
        if remaining <= 0:
            break
        price, volume = cast(price), cast(volume)
        if volume == 0:
            continue
        cost = min(price * volume, remaining)
        taken = volume if price * volume <= remaining else remaining / price
        quantity += taken
        spent += cost
        last = price
        remaining -= cost
    average = spent / quantity if quantity else cast(0)
    slippage = average / cast(asks[0][0]) - 1 if quantity else cast(0)
    return quantity, spent, average, last, slippage, remaining


def expected_rows(directory):
    for index, (book, budgets) in enumerate(inputs(directory)):
        yield ["book", index, book["lastUpdateId"]]
        for side, tag in (("bids", "bid"), ("asks", "ask")):
            for price, quantity in book[side]:
                yield [tag, Decimal(price), Decimal(quantity)]
        for budget in budgets:
            yield ["fill", *buy(book["asks"], budget)]


def expected_summary(directory, passes):
    books = list(inputs(directory))
    total = {"snapshots": len(books) * passes, "levels": 0, "id_sum": 0, "level_sum": 0.0, "checksum": 0.0}
    for _ in range(passes):
        for book, budgets in books:
            total["levels"] += len(book["bids"]) + len(book["asks"])
            total["id_sum"] += book["lastUpdateId"]
            for side in ("bids", "asks"):
                for price, quantity in book[side]:
                    total["level_sum"] = total["level_sum"] + float(price) + float(quantity)
            for budget in budgets:
                for value in buy(book["asks"], budget, float):
                    total["checksum"] += value
    return total


def compare_summary(actual, expected):
    for key, value in expected.items():
        if isinstance(value, int):
            assert actual[key] == value, (key, actual[key], value)
        else:
            assert math.isclose(actual[key], value, rel_tol=2e-11, abs_tol=1e-9), (key, actual[key], value)


def invoke(binary, directory, passes, dump=None, prefix=()):
    command = [*prefix, str(binary), str(directory), str(passes)]
    if dump:
        command.append(str(dump))
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(f"{command}: exit {result.returncode}\n{result.stdout}\n{result.stderr}")
    return json.loads(result.stdout), {"command": command, "stdout": result.stdout, "stderr": result.stderr}


def verify_dump(path, expected):
    rows = path.read_text().splitlines()
    assert len(rows) == len(expected), (len(rows), len(expected))
    for index, (line, wanted) in enumerate(zip(rows, expected)):
        got = line.split("\t")
        assert len(got) == len(wanted) and got[0] == wanted[0], (index, got, wanted)
        for actual, oracle in zip(got[1:], wanted[1:]):
            if isinstance(oracle, int):
                assert int(actual) == oracle, (index, actual, oracle)
            else:
                assert math.isclose(float(actual), float(oracle), rel_tol=2e-11, abs_tol=2e-10), (index, actual, oracle)


def verify(directory, binaries):
    expected = list(expected_rows(directory))
    expected_totals = expected_summary(directory, 1)
    evidence = {"full_level_rows": len(expected), "checks": []}
    with tempfile.TemporaryDirectory(prefix="orderbook-check-") as scratch:
        scratch = Path(scratch)
        for binary in binaries:
            dump = scratch / "dump.tsv"
            actual, _ = invoke(binary, directory, 1, dump)
            compare_summary(actual, expected_totals)
            verify_dump(dump, expected)
        small = {"asks": [["10", "2"], ["11", "0"], ["12", "3"]], "bids": [["9", "5"]], "lastUpdateId": 42}
        variants = [small, {**small, "asks": []}, {**small, "asks": [["1e-3", "1e2"]]},
                    {**small, "bids": [], "asks": []}]
        documents = []
        for number, book in enumerate(variants):
            # Whitespace and reordered keys must not select another algorithm/result.
            text = json.dumps(book, indent=2)
            if number == 0:
                text = text.replace('"10"', '"\\u0031\\u0030"')
            documents.append(text)
        # Exercise direct numeric parsing and the escaped-string decoder with
        # identical values, including a long mantissa and both exponent signs.
        for value in ('1', '1.23456789', '0.00000001', '1234567890123456.125', '1e-20', '1e20', '1.25e+2'):
            book = {"lastUpdateId": 42, "bids": [["1", "0"]], "asks": [[value, "2"]]}
            text = json.dumps(book, indent=2)
            escaped = ''.join('\\u%04x' % ord(char) for char in value)
            documents.extend((text, text.replace(json.dumps(value), '"' + escaped + '"')))
        for number, text in enumerate(documents):
            (scratch / "case.json").write_text(text)
            (scratch / "manifest.tsv").write_text("case.json\t0\t20\t100\n")
            for binary in binaries:
                actual, _ = invoke(binary, scratch, 1, scratch / "dump.tsv")
                compare_summary(actual, expected_summary(scratch, 1))
                verify_dump(scratch / "dump.tsv", list(expected_rows(scratch)))
            evidence["checks"].append(f"valid-boundary-{number}")
        invalid = ["{", json.dumps({"bids": [], "asks": []})]
        for bad in (["10"], ["10", "2", "3"], [10, "2"], ["oops", "2"], ["-1", "2"], ["1", "-2"]):
            book = copy.deepcopy(small)
            book["asks"] = [bad]
            invalid.append(json.dumps(book))
        for number, text in enumerate(invalid):
            (scratch / "case.json").write_text(text)
            for binary in binaries:
                result = subprocess.run([str(binary), str(scratch), "1"], capture_output=True, timeout=5)
                assert result.returncode != 0, (binary.name, number, "accepted invalid input")
            evidence["checks"].append(f"rejected-invalid-{number}")
        # The independent verifier itself must reject corrupted parsed values.
        rows = list(expected_rows(directory))
        bad_rows = [list(row) for row in rows]
        bad_rows[1][1] += 1
        corrupted = scratch / "corrupted.tsv"
        corrupted.write_text("\n".join("\t".join(map(str, row)) for row in bad_rows))
        rejected = False
        try:
            verify_dump(corrupted, rows)
        except AssertionError:
            rejected = True
        assert rejected
        evidence["checks"].append("oracle-rejects-corrupted-level")
    write_json(ROOT / "verification.json", evidence)
    print(json.dumps(evidence))


def measure(args, binaries):
    expected = expected_summary(args.data, args.passes)
    prefix = ["nice", "-n", str(args.nice), "taskset", "-c", str(args.cpu)]
    runs = []
    # One discarded warm-up per implementation, using exactly the measured task.
    for binary in binaries:
        actual, _ = invoke(binary, args.data, args.passes, prefix=prefix)
        compare_summary(actual, expected)
    for pair in range(args.pairs):
        for binary in binaries if pair % 2 == 0 else list(reversed(binaries)):
            actual, raw = invoke(binary, args.data, args.passes, prefix=prefix)
            compare_summary(actual, expected)
            runs.append({"pair": pair, **actual, **raw})
    result = {
        "host": args.label, "platform": platform.platform(), "cpu": args.cpu, "nice": args.nice,
        "lscpu": subprocess.check_output(["lscpu"], text=True),
        "passes": args.passes, "pairs": args.pairs, "expected": expected,
        "binaries": {p.name: sha(p) for p in binaries},
        "sources": {p.name: sha(p) for p in sorted(ROOT.iterdir()) if p.suffix in (".dpr", ".rs", ".py", ".toml", ".lock", ".sh")},
        "inputs": {p.name: sha(p) for p in sorted(args.data.iterdir()) if p.is_file()},
        "runs": runs,
    }
    write_json(args.output, result)
    for language in ("Moon", "Rust"):
        rows = [row for row in runs if row["language"] == language]
        print(language, {key: statistics.median(row[key] for row in rows) for key in ("cpu_ns", "wall_ns", "peak_rss")})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "verify", "run"))
    parser.add_argument("--data", type=Path, default=ROOT / "data")
    parser.add_argument("--cpu", type=int, default=2)
    parser.add_argument("--nice", type=int, default=10)
    parser.add_argument("--passes", type=int, default=32)
    parser.add_argument("--pairs", type=int, default=5)
    parser.add_argument("--label", default=platform.node())
    parser.add_argument("--output", type=Path, default=ROOT / "results.json")
    args = parser.parse_args()
    args.data = args.data.resolve()
    binaries = [ROOT / "bin" / f"orderbook_{language}" for language in ("moon", "rust")]
    if args.mode == "prepare":
        prepare(args.data)
    elif args.mode == "verify":
        verify(args.data, binaries)
    else:
        measure(args, binaries)


if __name__ == "__main__":
    main()
