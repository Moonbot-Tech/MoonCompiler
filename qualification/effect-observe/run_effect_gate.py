#!/usr/bin/env python3
"""Focused classification gate of the tree-layer effect model (phase F1).

Compiles every fixture under qualification/effect-observe/fixtures with the
observe flag (-OoEFFECTOBSERVE -vd) and checks the machine-stable summary
lines of the model against the EXPECT rows embedded in the fixtures.  The
gate tests the model OUTPUT (classes, instruction effects, reason ids), not
incidental compiler text.

EXPECT grammar (fixture line comments):

    // EXPECT: proc=Name key=value ...      exact-match fields of the summary
    // EXPECT-NOT: proc=Name reason=id      the reason must be absent

Exact-match keys: r, w, ie, temps, nodes, reasons.  The key reason=id asserts
presence (count > 0) of one reason.  Unlisted fields are unchecked.

Every fixture runs under -O2 and -O- with the same expectations, plus one
run without the flag that must emit no observe lines, plus a repeated -O2
run that must produce byte-identical observe output (determinism).

Usage:
    run_effect_gate.py [--compiler PATH] [--rtl PATH] [-v]
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
FIXTURES = HERE / "fixtures"

SUMMARY_RE = re.compile(
    r"effect-observe-summary: proc=(\S+) mid=(\S+) nodes=(\d+) r=(\S+) w=(\S+)"
    r" ie=(\S+) temps=(\d+) reasons=(\S+)"
)
ALGEBRA_RE = re.compile(
    r"effect-observe-algebra: proc=(\S+) mid=(\S+) rl=(\S+) wl=(\S+)"
    r" sc=(\d) q=(\S+) un=(\S+)"
)
EXPECT_RE = re.compile(r"//\s*(EXPECT|EXPECT-NOT):\s*(.*)$")
OBSERVE_LINE = re.compile(r"effect-observe(?:-summary|-algebra)?: (?:reason=|proc=)")


def default_compiler() -> Path:
    if os.name == "nt":
        return ROOT / ".moonbot" / "toolchain" / "bin" / "x86_64-win64" / "ppcx64.exe"
    return ROOT / ".moonbot" / "toolchain" / "bin" / "ppcx64"


def default_rtl() -> Path:
    if os.name == "nt":
        return ROOT / ".moonbot" / "toolchain" / "units" / "x86_64-win64" / "rtl"
    roots = sorted((ROOT / ".moonbot" / "toolchain" / "lib" / "fpc").glob(
        "*/units/x86_64-linux/rtl"))
    if len(roots) != 1:
        raise SystemExit("cannot uniquely locate the installed Linux RTL; pass --rtl")
    return roots[0]


def parse_expectations(path: Path):
    """Returns a list of (kind, dict) read from // EXPECT lines."""
    out = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        m = EXPECT_RE.search(line)
        if not m:
            continue
        kind, body = m.group(1), m.group(2).strip()
        fields = {}
        reasons = []
        for tok in body.split():
            if "=" not in tok:
                raise SystemExit(f"{path.name}:{lineno}: malformed EXPECT token {tok!r}")
            k, v = tok.split("=", 1)
            if k == "reason":
                reasons.append(v)
            else:
                fields[k] = v
        if "proc" not in fields:
            raise SystemExit(f"{path.name}:{lineno}: EXPECT without proc=")
        out.append((kind, fields, reasons, lineno))
    return out


def compile_fixture(compiler: Path, rtl: Path, fixture: Path, outdir: Path,
                    opt: str, observe: bool) -> tuple[int, str]:
    cmd = [
        str(compiler), "-Mdelphi", opt, "-n",
        f"-Fu{rtl}", f"-Fu{FIXTURES}",
        f"-FE{outdir}", f"-FU{outdir}",
        "-vd",
    ]
    if observe:
        cmd.insert(3, "-OoEFFECTOBSERVE")
    cmd.append(str(fixture))
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def collect_summaries(output: str, failures: list, tag: str):
    """proc name -> merged summary+algebra dict, keyed by the unique
    mangled id underneath; a duplicate short name inside one run is an
    error (never last-wins - review F-04)."""
    by_mid = {}
    for m in SUMMARY_RE.finditer(output):
        proc, mid, nodes, r, w, ie, temps, reasons = m.groups()
        rmap = {}
        if reasons != "-":
            for item in reasons.split(","):
                name, cnt = item.rsplit(":", 1)
                rmap[name] = int(cnt)
        by_mid[mid] = {
            "proc": proc, "nodes": nodes, "r": r, "w": w, "ie": ie,
            "temps": temps, "reasons": reasons, "reason_map": rmap,
        }
    for m in ALGEBRA_RE.finditer(output):
        proc, mid, rl, wl, sc, q, un = m.groups()
        entry = by_mid.setdefault(mid, {"proc": proc})
        entry.update({"rl": rl, "wl": wl, "sc": sc, "q": q, "un": un})
    res = {}
    for mid, entry in by_mid.items():
        proc = entry["proc"]
        if proc in res:
            failures.append(
                f"{tag}: duplicate routine name {proc} in one run "
                f"(overloads?) - fixture names must be unique")
            continue
        res[proc] = entry
    return res


def observe_lines(output: str) -> list[str]:
    return [ln.strip() for ln in output.splitlines() if OBSERVE_LINE.search(ln)]


def check_fixture(fixture: Path, summaries: dict, mode: str, failures: list):
    for kind, fields, reasons, lineno in parse_expectations(fixture):
        proc = fields["proc"]
        tag = f"{fixture.name}:{lineno} [{mode}] proc={proc}"
        summ = summaries.get(proc)
        if summ is None:
            failures.append(f"{tag}: no summary emitted for this routine")
            continue
        if kind == "EXPECT-NOT":
            for reason in reasons:
                if reason in summ["reason_map"]:
                    failures.append(
                        f"{tag}: reason {reason} present "
                        f"({summ['reasons']}) but must be absent")
            continue
        for key, want in fields.items():
            if key == "proc":
                continue
            got = summ.get(key)
            if got != want:
                failures.append(f"{tag}: {key}={got} expected {want}")
        for reason in reasons:
            if reason not in summ["reason_map"]:
                failures.append(
                    f"{tag}: reason {reason} absent (reasons={summ['reasons']})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--compiler", type=Path, default=default_compiler())
    ap.add_argument("--rtl", type=Path, default=default_rtl())
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    if not args.compiler.exists():
        raise SystemExit(f"compiler not found: {args.compiler}")
    if not (args.rtl / "system.ppu").exists():
        raise SystemExit(f"rtl units not found: {args.rtl}")

    fixtures = sorted(FIXTURES.glob("f_*.pas"))
    if not fixtures:
        raise SystemExit("no fixtures found")

    failures: list[str] = []
    rows = 0
    tmp = Path(tempfile.mkdtemp(prefix="effect_gate_"))
    try:
        for fixture in fixtures:
            per_mode_observe: dict[str, list[str]] = {}
            for mode in ("-O2", "-O-"):
                outdir = tmp / f"{fixture.stem}_{mode.strip('-') or 'O0'}"
                outdir.mkdir(parents=True, exist_ok=True)
                code, out = compile_fixture(
                    args.compiler, args.rtl, fixture, outdir, mode, True)
                if code != 0:
                    failures.append(f"{fixture.name} [{mode}]: compile failed\n{out[-2000:]}")
                    continue
                per_mode_observe[mode] = observe_lines(out)
                summaries = collect_summaries(out, failures, f"{fixture.name} [{mode}]")
                if args.verbose:
                    for proc, s in summaries.items():
                        print(f"  {fixture.name} [{mode}] {proc}: {s}")
                check_fixture(fixture, summaries, mode, failures)
            rows += len(parse_expectations(fixture))

            # observe output must be deterministic: a second -O2 run emits
            # byte-identical observe lines
            outdir = tmp / f"{fixture.stem}_repeat"
            outdir.mkdir(parents=True, exist_ok=True)
            code, out = compile_fixture(
                args.compiler, args.rtl, fixture, outdir, "-O2", True)
            if code == 0 and "-O2" in per_mode_observe:
                if observe_lines(out) != per_mode_observe["-O2"]:
                    failures.append(f"{fixture.name}: observe output not deterministic")

            # without the flag the model must stay silent
            outdir = tmp / f"{fixture.stem}_off"
            outdir.mkdir(parents=True, exist_ok=True)
            code, out = compile_fixture(
                args.compiler, args.rtl, fixture, outdir, "-O2", False)
            if code != 0:
                failures.append(f"{fixture.name} [off]: compile failed\n{out[-2000:]}")
            elif observe_lines(out):
                failures.append(f"{fixture.name}: observe lines emitted without the flag")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"EFFECT GATE: FAIL ({len(failures)} problems, "
              f"{rows} expectation rows x 2 modes)")
        for f in failures:
            print(" *", f)
        return 1
    print(f"EFFECT GATE: PASS ({rows} expectation rows x 2 modes "
          f"over {len(fixtures)} fixtures)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
