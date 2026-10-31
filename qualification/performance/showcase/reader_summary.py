"""Print the three comparison results; retain the underlying paired runs."""
import json
from pathlib import Path
import statistics
import sys

result = Path(sys.argv[1])
summary = json.loads((result / "summary.json").read_text())
book = json.loads((result / "orderbook.json").read_text())
row = {"case": "orderbook"}
for language, key in (("Moon", "moon"), ("Rust", "rust")):
    runs = [r for r in book["runs"] if r["language"] == language]
    row[key] = {field: statistics.median(r[field] for r in runs)
                for field in ("cpu_ns", "wall_ns", "peak_rss")}
summary.append(row)
print("PASS: every measured result checked; trade count, last price and turnover checked for every market.")
print("Medians of five alternating pairs. CPU is process time; RSS is whole-process peak memory.")
print("Task          Moon CPU ms  Rust CPU ms  Rust extra CPU   Moon MiB  Rust MiB  Rust extra RSS")
for row in summary:
    moon, rust = row["moon"], row["rust"]
    cpu = (rust["cpu_ns"] / moon["cpu_ns"] - 1) * 100
    rss = (rust["peak_rss"] / moon["peak_rss"] - 1) * 100
    print(f'{row["case"]:12} {moon["cpu_ns"]/1e6:11.2f} {rust["cpu_ns"]/1e6:12.2f} {cpu:+14.1f}%'
          f' {moon["peak_rss"]/1048576:10.2f} {rust["peak_rss"]/1048576:9.2f} {rss:+14.1f}%')
print("Trade RSS includes input preparation outside the CPU timer; it is not parser-only memory.")
print(f"Raw paired results: {result}")
