"""Bounded dictionary-layout experiment. All variants receive the same byte views."""
import argparse
import hashlib
import json
import pathlib
import statistics
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument("--cpu", required=True)
ap.add_argument("--label", required=True)
ap.add_argument("--pairs", type=int, default=5)
ap.add_argument("--binary", default="utf8_lookup_stand")
ap.add_argument("--kinds", type=int, default=6)
a = ap.parse_args()
root = pathlib.Path(__file__).resolve().parent
out = root / "results" / a.label
out.mkdir(parents=True, exist_ok=False)
binary = root / "bin" / a.binary
meta = {
    "binary_sha256": hashlib.file_digest(binary.open("rb"), "sha256").hexdigest(),
    "lscpu": subprocess.check_output(["lscpu"], text=True),
    "uname": subprocess.check_output(["uname", "-a"], text=True),
    "cpu": a.cpu,
}
(out / "host.json").write_text(json.dumps(meta, indent=2))
subprocess.run([str(binary)], check=True)
rows = []
for pair in range(a.pairs):
    for count in (3742, 100000):
        for profile in range(3):
            # Rotate implementation order, preserve every observation.
            for kind in [(k + pair) % a.kinds for k in range(a.kinds)]:
                cmd = ["taskset", "-c", a.cpu, str(binary), str(kind), str(profile), str(count), "5"]
                proc = subprocess.run(cmd, text=True, capture_output=True, timeout=60)
                with (out / "raw.jsonl").open("a") as f:
                    f.write(json.dumps(dict(command=cmd, rc=proc.returncode, stdout=proc.stdout,
                                           stderr=proc.stderr, load=pathlib.Path('/proc/loadavg').read_text())) + "\n")
                if proc.returncode:
                    raise RuntimeError(proc.stderr)
                row = json.loads(proc.stdout)
                assert row["lookup_allocations"] == row["lookup_frees"] == 0
                row["pair"] = pair
                rows.append(row)
                (out / "measurements.json").write_text(json.dumps(rows, indent=2))
summary = []
for count in (3742, 100000):
    for profile in range(3):
        selected = [r for r in rows if (r["entries"], r["profile"]) == (count, profile)]
        assert len({r["checksum"] for r in selected}) == 1
        for name in sorted({r["implementation"] for r in selected}):
            subset = [r for r in selected if r["implementation"] == name]
            r = {k: subset[0][k] for k in ("implementation", "profile", "entries", "queries")}
            for k in ("lookup_ns", "build_ns", "lookup_cpu_ns", "build_cpu_ns", "live_bytes", "peak_live_bytes", "build_allocations"):
                r[k] = statistics.median(x[k] for x in subset)
            r["lookup_min_ns"] = min(x["lookup_ns"] for x in subset)
            r["lookup_max_ns"] = max(x["lookup_ns"] for x in subset)
            r["lookup_cpu_min_ns"] = min(x["lookup_cpu_ns"] for x in subset)
            r["lookup_cpu_max_ns"] = max(x["lookup_cpu_ns"] for x in subset)
            summary.append(r)
(out / "summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
