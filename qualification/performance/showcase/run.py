"""Sequential paired application benchmarks; correctness is checked before accepting every row."""

import argparse
import datetime
import hashlib
import json
import math
import pathlib
import statistics
import subprocess
import time

CASES = [
    ("trades", "rust", 4),
    ("exchange", "rust", 1),
    ("serialize", "rust", 500),
    ("analytics", "cpp", 128),
    ("timers", "cpp", 32),
    ("dict-string", "cpp", 5),
    ("dict-int-update", "cpp", 5),
    ("dict-int-update-read", "cpp", 5),
    ("ring", "cpp", 100),
]


def snapshot():
    return {
        p: pathlib.Path("/proc/" + p).read_text()
        for p in ("stat", "loadavg", "meminfo", "vmstat")
    }


def check(row, mode, passes, output, expected):
    assert row["case"] == mode and row["wall_ns"] > 0 and row["cpu_ns"] > 0, row
    if mode == "trades":
        seen = set()
        for line in output.read_text(encoding="utf-8").splitlines():
            symbol, count, price, volume = line.split("\t")
            ref = expected["markets"][symbol]
            assert symbol not in seen
            seen.add(symbol)
            assert int(count) == ref["count"] * passes, symbol
            assert math.isclose(
                float(price), float(ref["price"]), rel_tol=1e-12, abs_tol=1e-12
            ), symbol
            assert math.isclose(
                float(volume),
                float(ref["volume"]) * passes,
                rel_tol=1e-11,
                abs_tol=1e-9,
            ), symbol
        assert len(seen) == len(expected["markets"]) == row["count"]
        assert row["operations"] == expected["trade_count"] * passes
        # Historical five-field runs retain their timestamp/side witness.
        if "witness" in row:
            assert row["witness"] == expected["trade_witness_one"] * passes
    elif mode == "exchange":
        for key in ("count", "names", "filters", "input_bytes"):
            assert row[key] == expected["exchange"][key], (key, row)
    elif mode == "serialize":
        values = json.loads(output.read_bytes())
        assert len(values) == len(expected["symbols"])
        for i, (symbol, v) in enumerate(zip(expected["symbols"], values)):
            assert v == dict(
                symbol=symbol,
                status="TRADING",
                price=(i + 1) / 64,
                volume=(i + 1) / 128,
                note='market "ready"\n',
            ), (i, v)
        assert row["operations"] == len(values) * passes
    elif mode == "analytics":
        assert math.isclose(
            row["result"], expected["analytics"][str(passes)], rel_tol=2e-13
        ), row
        assert row["operations"] == passes * 4096
    elif mode == "timers":
        assert row["checksum"] == expected["timers"][str(passes)], row
    elif mode == "dict-string":
        assert row["checksum"] == expected["dict_string_one"] * passes, row
    elif mode in ("dict-int-update", "dict-int-update-read"):
        assert (
            row["final_checksum"] == expected["dict_final"][str(passes)]["checksum"]
        ), row
        assert row["final_count"] == expected["dict_final"][str(passes)]["count"], row
        if mode.endswith("-read"):
            assert (
                row["checksum"]
                == passes * 499999500000 + 1000000 * passes * (passes + 1) // 2
            ), row
    elif mode == "ring":
        assert row["operations"] == 1000 * passes and row["threads"] == 1000, row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cpu", required=True)
    ap.add_argument("--label", required=True)
    ap.add_argument("--pairs", type=int, default=5)
    ap.add_argument("--cases", default="")
    a = ap.parse_args()
    root = pathlib.Path(__file__).resolve().parent
    out = root / "results" / a.label
    out.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((root / "data/manifest.json").read_text())
    for name, item in manifest["files"].items():
        assert (
            hashlib.file_digest((root / "data" / name).open("rb"), "sha256").hexdigest()
            == item["sha256"]
        ), name
    expected = json.loads((root / "expected.json").read_text())
    expected["markets"] = json.loads((root / "data/oracle.json").read_text())
    expected["symbols"] = (root / "data/symbols.txt").read_text().splitlines()
    metadata = {
        "label": a.label,
        "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "cpu": a.cpu,
        "uname": subprocess.check_output(["uname", "-a"], text=True),
        "lscpu": subprocess.check_output(["lscpu"], text=True),
        "before": snapshot(),
        "binaries": {
            p.name: hashlib.file_digest(p.open("rb"), "sha256").hexdigest()
            for p in (root / "bin").iterdir()
            if p.is_file()
        },
        "data_manifest": manifest,
    }
    (out / "host.json").write_text(json.dumps(metadata, indent=2))
    rows = []
    for mode, competitor, passes in CASES:
        if a.cases and mode not in a.cases.split(","):
            continue
        for pair in range(a.pairs):
            order = ["moon", competitor] if pair % 2 == 0 else [competitor, "moon"]
            for engine in order:
                output = out / f"{mode}-{pair}-{engine}.output"
                binary = (
                    "ring_moon"
                    if mode == "ring" and engine == "moon"
                    else "showcase_" + engine
                )
                args = [
                    str(root / "bin" / binary),
                    mode,
                    "1000" if mode == "ring" else str(root / "data"),
                    str(passes),
                ]
                if mode in ("trades", "serialize"):
                    args.append(str(output))
                command = ["taskset", "-c", a.cpu, *args]
                before = snapshot()
                started = time.monotonic()
                proc = subprocess.run(
                    command, text=True, capture_output=True, timeout=90
                )
                log = {
                    "pair": pair,
                    "engine": engine,
                    "mode": mode,
                    "command": command,
                    "elapsed_s": time.monotonic() - started,
                    "returncode": proc.returncode,
                    "stdout": proc.stdout,
                    "stderr": proc.stderr,
                    "before": before,
                    "after": snapshot(),
                }
                with (out / "raw.jsonl").open("a") as f:
                    f.write(json.dumps(log) + "\n")
                if proc.returncode:
                    raise RuntimeError(log)
                row = json.loads(proc.stdout.strip())
                check(row, mode, passes, output, expected)
                row.update(pair=pair, engine=engine, validated=True)
                rows.append(row)
                (out / "measurements.json").write_text(json.dumps(rows, indent=2))
                print(json.dumps(row), flush=True)
                time.sleep(0.15)
    summary = []
    for mode, competitor, passes in CASES:
        selected = [r for r in rows if r["case"] == mode]
        if not selected:
            continue
        item = {
            "case": mode,
            "competitor": competitor,
            "passes": passes,
            "pairs": a.pairs,
        }
        for engine in ("moon", competitor):
            rr = [r for r in selected if r["engine"] == engine]
            item[engine] = {
                k: statistics.median(r[k] for r in rr)
                for k in rr[0]
                if k not in ("pair", "validated") and isinstance(rr[0][k], (int, float))
            }
            item[engine]["cpu_min_ns"] = min(r["cpu_ns"] for r in rr)
            item[engine]["cpu_max_ns"] = max(r["cpu_ns"] for r in rr)
        item["cpu_ratio_other_over_moon"] = (
            item[competitor]["cpu_ns"] / item["moon"]["cpu_ns"]
        )
        item["wall_ratio_other_over_moon"] = (
            item[competitor]["wall_ns"] / item["moon"]["wall_ns"]
        )
        summary.append(item)
    (out / "summary.json").write_text(json.dumps(summary, indent=2))
    (out / "host-after.json").write_text(json.dumps(snapshot(), indent=2))
    print("COMPLETE " + str(out), flush=True)


if __name__ == "__main__":
    main()
