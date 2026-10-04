#!/usr/bin/env python3
"""Compare the layout of the same procedures across stand builds.

hotdiff.py summary  EXE... --match REGEX   per procedure: entry mod 64, size,
                                          loops (head, length, head mod 64,
                                          64-byte lines touched, end mod 64),
                                          taken-branch targets and their
                                          offset inside the 64-byte line
hotdiff.py dump EXE --match REGEX          annotated disassembly with line marks
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import code_placement  # noqa: E402


def load(exe: Path):
    insns = code_placement.disassemble(exe)
    procs = code_placement.procedures(exe)
    return insns, procs


def select(procs, pattern):
    rx = re.compile(pattern, re.IGNORECASE)
    return [(n, b, e) for n, b, e in procs if rx.search(n)]


def loops_of(insns, begin, end):
    addrs = [a for a in range(begin, end) if a in insns]
    loops = {}
    targets = []
    for a in addrs:
        m, ops, raw = insns[a]
        if m.startswith("j"):
            t = code_placement.BRANCH_TARGET.match(ops)
            if t:
                target = int(t.group(1), 16)
                if begin <= target < end:
                    targets.append((a, target, m))
                if begin <= target < a:
                    stop = a + len(raw)
                    if target not in loops or stop > loops[target]:
                        loops[target] = stop
    return loops, targets


def summary(exes, pattern):
    data = [(exe.name if exe.parent.name == "" else exe.parent.name, *load(exe)) for exe in exes]
    names = set()
    for _, _, procs in data:
        names.update(n for n, _, _ in select(procs, pattern))
    for name in sorted(names):
        print(f"\n## {name}")
        for label, insns, procs in data:
            hits = [(n, b, e) for n, b, e in procs if n == name]
            if not hits:
                print(f"  {label}: (absent)")
                continue
            n, b, e = hits[0]
            size = e - b
            insn_count = sum(1 for a in range(b, e) if a in insns)
            nops = sum(len(insns[a][2]) for a in range(b, e) if a in insns and code_placement.is_padding(insns[a][0], insns[a][1]))
            prefixes = sum(1 for a in range(b, e) if a in insns and insns[a][2][:1] == b"\x3e")
            loops, targets = loops_of(insns, b, e)
            print(f"  {label}: entry {b:#x} mod64={b % 64:2d} mod32={b % 32:2d} size={size} insns={insn_count} nopbytes={nops} dsprefixed={prefixes}")
            for head, stop in sorted(loops.items()):
                length = stop - head
                lines = (stop - 1) // 64 - head // 64 + 1
                inner = [t for t in targets if head <= t[1] < stop and t[1] != head]
                inner_desc = " ".join(f"{m}->+{t - head}@{t % 64}" for a, t, m in inner)
                print(f"    loop head +{head - b} (mod64={head % 64:2d}) len={length} lines={lines} end_mod64={(stop - 1) % 64:2d} {'SHORT' if length <= 64 else 'LONG'} inner_targets: {inner_desc}")
            # calls inside the procedure
            calls = [(a, insns[a][1]) for a in range(b, e) if a in insns and insns[a][0] == "call"]
            if calls and len(calls) <= 12:
                print("    calls: " + ", ".join(re.sub(r"^[0-9a-f]+ <(.*?)>.*", r"\1", ops)[:40] for a, ops in calls))


def dump(exe, pattern):
    insns, procs = load(exe)
    for n, b, e in select(procs, pattern):
        print(f"\n## {n} entry={b:#x} mod64={b % 64} size={e - b}")
        loops, targets = loops_of(insns, b, e)
        heads = set(loops)
        tgt = {t for _, t, _ in targets}
        for a in range(b, e):
            if a not in insns:
                continue
            m, ops, raw = insns[a]
            mark = ""
            if a % 64 == 0:
                mark += " <=== 64B line"
            elif a % 32 == 0:
                mark += " <-- 32B"
            if a in heads:
                mark += f"  [LOOP HEAD len={loops[a] - a}]"
            elif a in tgt:
                mark += "  [target]"
            crossing = (a // 64) != ((a + len(raw) - 1) // 64)
            if crossing:
                mark += "  !crosses line!"
            print(f"  +{a - b:4d} @{a % 64:2d} {raw.hex():<18} {m:8s} {ops[:60]}{mark}")


def main():
    cmd = sys.argv[1]
    args = sys.argv[2:]
    pattern = args[args.index("--match") + 1]
    exes = [Path(x) for x in args[: args.index("--match")]]
    if cmd == "summary":
        summary(exes, pattern)
    elif cmd == "dump":
        dump(exes[0], pattern)


if __name__ == "__main__":
    main()
