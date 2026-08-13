#!/usr/bin/env python3
"""Normalize mm_crossmachine results from two machines."""

from __future__ import annotations

import argparse
import math
import statistics
from pathlib import Path


Key = tuple[str, str, int]


def parse_line(line: str) -> tuple[Key, int, str] | None:
    if not (line.startswith("CAL ") or line.startswith("MM ")):
        return None
    fields = dict(part.split("=", 1) for part in line.split()[1:])
    kind = line[:3].strip()
    key = (kind, fields["name"], int(fields["threads"]))
    return key, int(fields["median_ns"]), fields["digest"]


def parse_files(paths: list[Path]) -> tuple[dict[Key, float], dict[Key, str]]:
    values: dict[Key, list[int]] = {}
    digests: dict[Key, str] = {}
    for path in paths:
        seen: set[Key] = set()
        raw = path.read_bytes()
        encoding = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
        for line in raw.decode(encoding).splitlines():
            parsed = parse_line(line)
            if parsed is None:
                continue
            key, elapsed, digest = parsed
            if key in seen:
                raise ValueError(f"duplicate {key} in {path}")
            seen.add(key)
            if key in digests and digests[key] != digest:
                raise ValueError(f"digest mismatch for {key} in {path}")
            digests[key] = digest
            values.setdefault(key, []).append(elapsed)
    if not values:
        raise ValueError("no benchmark rows found")
    expected = len(paths)
    for key, samples in values.items():
        if len(samples) != expected:
            raise ValueError(f"missing {key}: got {len(samples)}/{expected} rows")
    return {key: statistics.median(samples) for key, samples in values.items()}, digests


def coefficient(local: dict[Key, float], server: dict[Key, float],
                name: str, threads: int) -> float:
    key = ("CAL", name, threads)
    return server[key] / local[key]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local", type=Path, nargs="+", required=True)
    parser.add_argument("--server", type=Path, nargs="+", required=True)
    args = parser.parse_args()

    local, local_digests = parse_files(args.local)
    server, server_digests = parse_files(args.server)
    if local.keys() != server.keys():
        raise ValueError("local/server benchmark sets differ")
    for key, digest in local_digests.items():
        if server_digests[key] != digest:
            raise ValueError(f"cross-machine digest mismatch for {key}")

    cpu: dict[int, tuple[float, float, float]] = {}
    for threads in (1, 4):
        serial = coefficient(local, server, "cpu-serial", threads)
        ilp = coefficient(local, server, "cpu-ilp4", threads)
        cpu[threads] = serial, ilp, math.sqrt(serial * ilp)
        print(f"K_CPU{threads} serial={serial:.6f} ilp={ilp:.6f} "
              f"geometric={cpu[threads][2]:.6f}")

    slab_key = ("CAL", "slab-copy", 1)
    slab = server[slab_key] / local[slab_key]
    print(f"K_RAM_TIME={slab:.6f} server_bandwidth_ratio={1 / slab:.6f}")
    print()
    print("| workload | Delphi ms | server raw ms | server normalized ms | verdict |")
    print("| --- | ---: | ---: | ---: | ---: |")
    for name, threads in (("mix", 1), ("small", 1), ("mix", 4), ("small", 4)):
        key = ("MM", name, threads)
        serial, ilp, central = cpu[threads]
        normalized = server[key] / central
        ratio = normalized / local[key]
        change = (ratio - 1) * 100
        low = server[key] / max(serial, ilp)
        high = server[key] / min(serial, ilp)
        verdict = f"{abs(change):.1f}% {'slower' if change > 0 else 'faster'}"
        print(f"| {name} x{threads} | {local[key] / 1e6:.3f} | "
              f"{server[key] / 1e6:.3f} | {normalized / 1e6:.3f} "
              f"({low / 1e6:.3f}..{high / 1e6:.3f}) | {verdict} |")


if __name__ == "__main__":
    main()
