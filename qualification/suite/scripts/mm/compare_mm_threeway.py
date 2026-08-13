#!/usr/bin/env python3
"""Compare Delphi/FPC allocators with mimalloc on the same two hosts."""

from __future__ import annotations

import argparse
import statistics
from pathlib import Path


Key = tuple[str, int]


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    encoding = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    return raw.decode(encoding)


def parse(paths: list[Path]) -> tuple[dict[Key, float], dict[Key, str]]:
    times: dict[Key, list[float]] = {}
    digests: dict[Key, str] = {}
    for path in paths:
        seen: set[Key] = set()
        for line in read_text(path).splitlines():
            if not line.startswith("MM "):
                continue
            fields = dict(part.split("=", 1) for part in line.split()[1:])
            name = fields["name"]
            if not (name == "app-mix" or name.startswith("moonbot-")
                    or name.startswith("fixed-") or
                    name.startswith("hot-ping-") or
                    name.startswith("touch-ping-")):
                continue
            key = name, int(fields["threads"])
            if key in seen:
                raise ValueError(f"duplicate {key} in {path}")
            seen.add(key)
            if "actions" in fields:
                actions = int(fields["actions"])
            elif "rounds" in fields:
                actions = int(fields["rounds"])
            else:
                actions = int(fields["plans"]) * 10000
            times.setdefault(key, []).append(int(fields["median_ns"]) / actions)
            digest = fields["digest"]
            if key in digests and digests[key] != digest:
                raise ValueError(f"digest mismatch for {key} in {path}")
            digests[key] = digest
    if not times:
        raise ValueError("no profile/fixed MM rows found")
    for key, values in times.items():
        if len(values) != len(paths):
            raise ValueError(f"missing {key}: got {len(values)}/{len(paths)}")
    return {key: statistics.median(values) for key, values in times.items()}, digests


def ordered(keys: set[Key]) -> list[Key]:
    profiles = ["moonbot-low", "moonbot-spread", "moonbot-high"]
    result = [("app-mix", threads) for threads in (1, 4)
              if ("app-mix", threads) in keys]
    result.extend((name, threads) for threads in (1, 4) for name in profiles
                  if (name, threads) in keys)
    fixed = sorted(int(name.removeprefix("fixed-")) for name, threads in keys
                   if threads == 1 and name.startswith("fixed-"))
    result.extend((f"fixed-{size}", threads)
                  for threads in (1, 4) for size in fixed)
    hot = sorted(int(name.removeprefix("hot-ping-")) for name, threads in keys
                 if threads == 1 and name.startswith("hot-ping-"))
    result.extend((f"hot-ping-{size}", threads)
                  for threads in (1, 4) for size in hot)
    touch = sorted(int(name.removeprefix("touch-ping-"))
                   for name, threads in keys
                   if threads == 1 and name.startswith("touch-ping-"))
    result.extend((f"touch-ping-{size}", threads)
                  for threads in (1, 4) for size in touch)
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    for name in ("delphi", "fpc", "mimalloc_windows", "mimalloc_linux"):
        parser.add_argument(f"--{name.replace('_', '-')}", type=Path,
                            nargs="+", required=True)
    args = parser.parse_args()

    groups = {
        "delphi": parse(args.delphi),
        "fpc": parse(args.fpc),
        "mimalloc_windows": parse(args.mimalloc_windows),
        "mimalloc_linux": parse(args.mimalloc_linux),
    }
    keys = set(groups["delphi"][0])
    for name, (times, digests) in groups.items():
        if set(times) != keys:
            raise ValueError(f"workload set mismatch for {name}")
        for key in keys:
            if digests[key] != groups["delphi"][1][key]:
                raise ValueError(f"cross-language digest mismatch for {key}: {name}")

    print("| workload | Delphi ns/action | mimalloc Win | Delphi/mimalloc | "
          "FPC ns/action | mimalloc Linux | FPC/mimalloc |")
    print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
    for key in ordered(keys):
        d = groups["delphi"][0][key]
        f = groups["fpc"][0][key]
        mw = groups["mimalloc_windows"][0][key]
        ml = groups["mimalloc_linux"][0][key]
        print(f"| {key[0]} x{key[1]} | {d:.3f} | {mw:.3f} | {d / mw:.2f}x | "
              f"{f:.3f} | {ml:.3f} | {f / ml:.2f}x |")


if __name__ == "__main__":
    main()
