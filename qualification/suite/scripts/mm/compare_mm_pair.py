#!/usr/bin/env python3
"""Compare two allocators running the same MM workloads on one host."""

from __future__ import annotations

import argparse
from pathlib import Path

from compare_mm_threeway import ordered, parse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--left", type=Path, nargs="+", required=True)
    parser.add_argument("--right", type=Path, nargs="+", required=True)
    parser.add_argument("--left-label", required=True)
    parser.add_argument("--right-label", required=True)
    args = parser.parse_args()

    left, left_digests = parse(args.left)
    right, right_digests = parse(args.right)
    if left.keys() != right.keys():
        raise ValueError("workload set mismatch")
    for key, digest in left_digests.items():
        if right_digests[key] != digest:
            raise ValueError(f"allocator digest mismatch for {key}")

    print(f"| workload | {args.left_label} ns/action | "
          f"{args.right_label} ns/action | {args.left_label}/{args.right_label} |")
    print("| --- | ---: | ---: | ---: |")
    for key in ordered(set(left)):
        print(f"| {key[0]} x{key[1]} | {left[key]:.3f} | {right[key]:.3f} | "
              f"{left[key] / right[key]:.2f}x |")


if __name__ == "__main__":
    main()
