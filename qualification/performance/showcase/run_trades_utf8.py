"""Compare actual RTL UTF-8 slice lookup with the same Rust trade workload."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess
from run import check

ap = argparse.ArgumentParser()
ap.add_argument("--cpu", required=True)
ap.add_argument("--label", required=True)
ap.add_argument("--pairs", type=int, default=5)
a = ap.parse_args()
root = pathlib.Path(__file__).resolve().parent
out = root / "results" / a.label
out.mkdir(parents=True, exist_ok=False)
data = root / "data"
manifest = json.loads((data / "manifest.json").read_text())
for name, item in manifest["files"].items():
    assert hashlib.file_digest((data / name).open("rb"), "sha256").hexdigest() == item["sha256"]
expected = {"markets": json.loads((data / "oracle.json").read_text()), "trade_count": manifest["trades"]}
meta = {"binaries": {n: hashlib.file_digest((root / "bin" / n).open("rb"), "sha256").hexdigest()
                     for n in ("showcase_moon", "showcase_rust")}, "manifest": manifest,
        "lscpu": subprocess.check_output(["lscpu"], text=True), "cpu": a.cpu}
(out / "host.json").write_text(json.dumps(meta, indent=2))
cases = [("moon-rtl", "showcase_moon", "trades"), ("rust", "showcase_rust", "trades")]
rows = []
for pair in range(a.pairs):
    for label, name, mode in cases[pair % len(cases):] + cases[:pair % len(cases)]:
        output = out / f"{pair}-{label}.output"
        cmd = ["taskset", "-c", a.cpu, str(root / "bin" / name), mode, str(data), "4", str(output)]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        with (out / "raw.jsonl").open("a") as f:
            f.write(json.dumps(dict(command=cmd, rc=proc.returncode, stdout=proc.stdout, stderr=proc.stderr,
                                   load=pathlib.Path('/proc/loadavg').read_text())) + "\n")
        if proc.returncode:
            raise RuntimeError(proc.stderr)
        row = json.loads(proc.stdout)
        check(row, "trades", 4, output, expected)
        row.update(engine=label, pair=pair, validated=True)
        rows.append(row)
        (out / "measurements.json").write_text(json.dumps(rows, indent=2))
summary = {label: {k: statistics.median(r[k] for r in rows if r["engine"] == label)
                   for k in ("wall_ns", "cpu_ns")} for label, _, _ in cases}
(out / "summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
