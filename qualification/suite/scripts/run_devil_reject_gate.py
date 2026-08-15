#!/usr/bin/env python3
"""Run the Devil reject layer: compile every case with every compiler and
compare the verdict against what the language requires.

Findings:
  * false-reject  - a valid program the compiler refuses;
  * false-accept  - an invalid program the compiler swallows;
  * verdict-split - our compiler and Delphi disagree about a program;
  * internal-error - the compiler crashes instead of producing a diagnostic.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REJECT = ROOT / "tests" / "devil" / "reject"
GENERATOR = ROOT / "scripts" / "generate_devil_reject.py"

DIAG_RE = re.compile(r"(?:Error|Fatal):\s*(?:\((?P<code>\w+)\)\s*)?(?P<text>.+)")


def run(cmd: list[str], cwd: Path, timeout: int) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                              timeout=timeout)
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def first_diagnostic(log: str) -> str:
    for line in log.splitlines():
        m = DIAG_RE.search(line)
        if m:
            return m.group("text").strip()[:120]
    return ""


def compile_fpc(work: Path, fpc: Path, cfg: Path, option: str, source: Path,
                timeout: int) -> tuple[bool, str, bool]:
    out = work / ("out-" + source.stem + "-" + option)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    code, log = run([str(fpc), "-n", f"@{cfg}", "-Mdelphi", f"-{option}",
                     f"-FU{out}", f"-FE{out}", source.name], work, timeout)
    ice = "nternal error" in log
    return code == 0, first_diagnostic(log), ice


def compile_delphi(work: Path, dcc: Path, lib: Path, source: Path,
                   timeout: int) -> tuple[bool, str, bool]:
    out = work / ("dout-" + source.stem)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    code, log = run([str(dcc), "-B", "-CC", f"-U{lib}", "-NSSystem",
                     f"-NU{out}", f"-E{out}", source.name], work, timeout)
    return code == 0, first_diagnostic(log), False


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--fpc", type=Path, required=True)
    p.add_argument("--fpc-config", type=Path, required=True)
    p.add_argument("--dcc", type=Path)
    p.add_argument("--dcc-lib", type=Path)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--options", default="O2")
    p.add_argument("--timeout", type=int, default=120)
    p.add_argument("--work", type=Path, default=REJECT)
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    args.fpc = args.fpc.resolve()
    args.fpc_config = args.fpc_config.resolve()
    if args.dcc:
        args.dcc = args.dcc.resolve()
    if args.dcc_lib:
        args.dcc_lib = args.dcc_lib.resolve()
    args.work = args.work.resolve()

    code, log = run([sys.executable, str(GENERATOR), "--seed", str(args.seed),
                     "--out", str(args.work)], ROOT, args.timeout)
    if code != 0:
        print("generator failed\n" + log)
        sys.exit(2)

    manifest = json.loads((args.work / "manifest.json").read_text(encoding="utf-8"))
    findings: list[dict] = []
    rows: list[dict] = []

    for case in manifest["cases"]:
        source = args.work / (case["program"] + ".dpr")
        want = case["verdict"]
        row = {"case": case["case"], "verdict": want, "builds": {}}
        for option in args.options.split(","):
            ok, diag, ice = compile_fpc(args.work, args.fpc, args.fpc_config,
                                        option, source, args.timeout)
            row["builds"][f"fpc{option}"] = {"compiled": ok, "diag": diag}
            if ice:
                findings.append({"kind": "internal-error", "case": case["case"],
                                 "build": f"fpc{option}", "diag": diag})
            elif want == "accept" and not ok:
                findings.append({"kind": "false-reject", "case": case["case"],
                                 "build": f"fpc{option}", "diag": diag})
            elif want == "reject" and ok:
                findings.append({"kind": "false-accept", "case": case["case"],
                                 "build": f"fpc{option}"})
        if args.dcc and args.dcc_lib:
            ok, diag, _ = compile_delphi(args.work, args.dcc, args.dcc_lib,
                                         source, args.timeout)
            row["builds"]["delphi"] = {"compiled": ok, "diag": diag}
            ours = row["builds"][f"fpc{args.options.split(',')[0]}"]["compiled"]
            if ok != ours:
                findings.append({
                    "kind": "verdict-split", "case": case["case"],
                    "delphi": "compiled" if ok else "rejected",
                    "ours": "compiled" if ours else "rejected",
                    "delphi_diag": diag,
                    "our_diag": row["builds"][f"fpc{args.options.split(',')[0]}"]["diag"],
                })
        rows.append(row)

    for f in findings:
        print(json.dumps(f, sort_keys=True))
    if args.report:
        args.report.write_text(json.dumps({"rows": rows, "findings": findings},
                                          indent=2, sort_keys=True) + "\n",
                               encoding="utf-8")
    print(f"DEVIL_REJECT {'OK' if not findings else 'FINDINGS'} "
          f"cases={len(rows)} findings={len(findings)}")
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
