#!/usr/bin/env python3
"""The product's zlib is not slower than Delphi 12.2's on the product's forms (Win64).

The Pulse program zlib makes the calls MoonBot makes: a trade packet and the
candle blob deflated and inflated through TZCompressionStream and
TZDecompressionStream, the history of a market, 256 permessage-deflate frames of
an exchange websocket on one inflate stream, a market's data zipped into an
archive in memory and read back through System.Zip.  On Win64 System.ZLib links
zlib 1.3.1 built by the toolchain (packages/vcl-compat/native/zlib), and
System.Zip compresses through it too (mormot.lib.z under
MOONCOMPILER_SYSTEM_ZLIB); a build that copies a byte a step made the websocket
1.25 times as slow as Delphi and passed every test.  zlib_objects_gate.py knows
that one defect by its bytes; this gate asks the question itself, on every
form.

A row is judged by all its process pairs (the Moon process over the adjacent
Delphi process, seven pairs in medium mode, the order of the two sides
alternating): slower when every pair is above 1.05, not slower when every pair
is at or below it.  Noise of a busy machine widens the spread of the pairs, so
it can leave a row undecided, but a verdict needs every pair on one side: noise
that is not the same in every pair cannot make one.  Pulse's own stability rule
is not the question here - a stream inflate whose pairs spread from 0.46 to 0.57
is unstable for a ratio and plainly not slower.  An undecided row is measured
again; still undecided, it fails as UNRESOLVED - a machine that was not quiet,
not a slower product.

Usage (Windows, Delphi 12.2 installed where pulse.py expects dcc64):
    zlib_delphi_gate.py --output DIR [--toolchain DIR]   # measure and judge
    zlib_delphi_gate.py --judge RESULT_DIR                # judge a Pulse result
--toolchain names another Moon toolchain (e.g. one with older zlib objects);
--rows narrows the product rows (a result measured for some of them).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[2]
PRODUCT_ROWS = ("stream-deflate-trades-4k", "stream-inflate-trades-4k", "stream-deflate-candles-1m",
                "stream-inflate-candles-1m", "stream-deflate-history-fastest", "websocket-inflate-256",
                "zip-add-history", "zip-read-history")
LIMIT = 1.05  # Pulse's line for "slower" (doc/PERFORMANCE_QUALIFICATION.md)
ATTEMPTS = 3


def verdicts(result: Path, names: list[str]) -> dict[str, str]:
    """PASS, SLOWER, UNRESOLVED or a failure of the run itself, per product row of a Pulse result."""
    summary = json.loads((result / "summary.json").read_text(encoding="utf-8"))
    rows = {}
    for name in names:
        detail = summary.get(f"zlib/{name}")
        pairs = (detail or {}).get("paired_candidate_over_baseline")
        if detail is None:
            rows[name] = "MISSING"
        elif detail["oracle_status"] != "MATCH":
            rows[name] = "SEMANTIC_MISMATCH"
        elif not pairs:
            rows[name] = "UNRESOLVED no process pairs"
        elif pairs["maximum"] <= LIMIT:
            rows[name] = f"PASS pairs {pairs['minimum']:.3f}..{pairs['maximum']:.3f}"
        elif pairs["minimum"] > LIMIT:
            rows[name] = f"SLOWER pairs {pairs['minimum']:.3f}..{pairs['maximum']:.3f} x Delphi"
        else:
            rows[name] = f"UNRESOLVED pairs {pairs['minimum']:.3f}..{pairs['maximum']:.3f} cross {LIMIT}"
    return rows


def measure(output: Path, rows: list[str], toolchain: Path | None, attempt: int) -> Path:
    tag = f"zlib-delphi-{attempt}"
    system = "moon" if toolchain is None else "zlibgate"
    command = [sys.executable, str(TOOLS / "pulse.py"), "run", "--mode", "medium", "--programs", "zlib",
               "--cases", ",".join(f"zlib/{row}" for row in rows), "--systems", f"delphi,{system}",
               "--tag", tag, "--result-root", str(output)]
    if toolchain is not None:
        command += ["--moon-system", f"{system}={toolchain.resolve()}"]
    with (output / f"{tag}.log").open("w", encoding="utf-8") as log:
        # A row whose pairs drift makes pulse.py exit 1 after it wrote summary.json: the pairs still judge.
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=False)
    result = output / tag
    if not (result / "summary.json").is_file():
        raise RuntimeError(f"Pulse wrote no summary: {output / f'{tag}.log'}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--toolchain", type=Path)
    parser.add_argument("--judge", type=Path)
    parser.add_argument("--rows", default=",".join(PRODUCT_ROWS))
    args = parser.parse_args()
    names = [row for row in args.rows.split(",") if row]
    if not names or set(names) - set(PRODUCT_ROWS):
        parser.error(f"--rows takes product rows: {', '.join(PRODUCT_ROWS)}")
    if args.judge:
        final = verdicts(args.judge, names)
    elif args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        final = {}
        pending = names
        for attempt in range(1, ATTEMPTS + 1):
            try:
                rows = verdicts(measure(args.output, pending, args.toolchain, attempt), pending)
            except (OSError, RuntimeError, ValueError) as error:
                print(f"ZLIB_DELPHI_GATE_FAIL {error}")
                return 1
            final.update({row: rows[row] for row in pending})
            pending = [row for row in pending if final[row].startswith("UNRESOLVED")]
            if not pending:
                break
    else:
        parser.error("--output or --judge is required")
    for row, verdict in final.items():
        print(f"ZLIB_DELPHI zlib/{row} {verdict}")
    failed = [row for row, verdict in final.items() if not verdict.startswith("PASS")]
    print(f"ZLIB_DELPHI_GATE_{'FAIL' if failed else 'PASS'} rows={len(final)} failed={len(failed)}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
