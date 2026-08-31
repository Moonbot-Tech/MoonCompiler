#!/usr/bin/env python3
"""Fast Devil feedback without pretending to be the full release gate.

``light`` is a fixed broad minimax sweep.  ``impact`` runs the semantic Devil
layers and adjacent independent gates relevant to a declared repair area.
The exact focused repro remains mandatory; this runner is the next regression
ring, not a replacement for it or for ``run_devil_all.py``.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc
import generate_devil


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
ALL_LAYERS = tuple(generate_devil.LAYERS)


@dataclass(frozen=True)
class Impact:
    meaning: str
    layers: tuple[str, ...]
    stages: tuple[str, ...] = ()
    main_switches: tuple[str, ...] = ()


IMPACTS = {
    "frontend": Impact(
        "parser, declarations, overloads and compile-time diagnostics",
        ("expr", "unary", "fold", "cmp", "lang", "decl", "pick", "lit",
         "narrowpath", "chk"),
        ("reject",),
    ),
    "generics-ppu": Impact(
        "generics, aliases, unit boundaries and PPU replay",
        ("gen", "unit", "genpath", "ppu", "scope", "deliver", "meta"),
        (),
        ("--ppu-reuse", "--separate-units", "--second-program"),
    ),
    "managed-lifetime": Impact(
        "managed values, copies, finalization and ownership transfer",
        ("life", "str", "uni", "dyn", "intf", "capture", "scope", "deliver",
         "region", "exc", "init"),
        ("chimera",),
    ),
    "optimizer-codegen": Impact(
        "optimizer transforms, generated addresses, calls and inline bodies",
        ("opt", "call", "inl", "flow", "asm", "matrix", "weave",
         "composite", "expr", "float"),
        ("codegen", "asm-oracle"),
        ("--determinism",),
    ),
    "abi-asm": Impact(
        "calling conventions, aggregates, assembler and numeric ABI",
        ("abi", "asm", "call", "float", "i128", "arr", "set"),
        ("asm-oracle",),
    ),
    "exceptions": Impact(
        "raise/unwind/finally control flow and managed cleanup",
        ("exc", "region", "flow", "call", "inl", "life", "capture"),
    ),
    "threads": Impact(
        "thread handoff, shared managed state and initialization",
        ("thr", "life", "intf", "region", "init", "load"),
        ("stress",),
    ),
    "rtti-attributes": Impact(
        "RTTI materialization, attributes and metadata across units",
        ("rtti", "attr", "decl", "meta", "ppu", "unit"),
        (),
        ("--ppu-reuse",),
    ),
    "strings-unicode": Impact(
        "Unicode/ANSI/byte strings, literals, conversions and text I/O",
        ("str", "uni", "lit", "pick", "io", "rtllib", "lang"),
        ("chimera",),
    ),
    "rtl-containers": Impact(
        "RTL collections, dynamic arrays, managed elements and iteration",
        ("rtllib", "dyn", "gen", "life", "thr", "arr"),
        ("chimera",),
    ),
    "initialization": Impact(
        "unit/program startup, shutdown and resident process lifecycle",
        ("init", "life", "intf", "thr", "region", "unit"),
        ("resident",),
    ),
}


def canonical_layers(areas: list[str]) -> tuple[str, ...]:
    requested: set[str] = set()
    for area in areas:
        try:
            requested.update(IMPACTS[area].layers)
        except KeyError as error:
            raise ValueError(f"unknown impact area: {area}") from error
    return tuple(layer for layer in ALL_LAYERS if layer in requested)


def adjacent_stages(areas: list[str]) -> tuple[str, ...]:
    requested = {stage for area in areas for stage in IMPACTS[area].stages}
    return tuple(stage for stage in STAGE_ORDER if stage in requested)


def main_switches(areas: list[str]) -> tuple[str, ...]:
    requested = {
        switch for area in areas for switch in IMPACTS[area].main_switches
    }
    return tuple(switch for switch in MAIN_SWITCH_ORDER if switch in requested)


STAGE_ORDER = (
    "registry", "codegen", "asm-oracle", "main", "chimera", "stress",
    "reject", "resident",
)
MAIN_SWITCH_ORDER = (
    "--separate-units", "--second-program", "--determinism", "--ppu-reuse",
)
LIGHT_STAGES = STAGE_ORDER[:-1]


def run(command: list[str], timeout: int) -> tuple[int, str, float]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            command, cwd=tc.ROOT, capture_output=True, text=True, timeout=timeout
        )
        output = (result.stdout or "") + (result.stderr or "")
        return result.returncode, output, time.monotonic() - started
    except subprocess.TimeoutExpired as error:
        stdout = error.stdout.decode(errors="replace") if isinstance(
            error.stdout, bytes) else (error.stdout or "")
        stderr = error.stderr.decode(errors="replace") if isinstance(
            error.stderr, bytes) else (error.stderr or "")
        return 124, stdout + stderr + "\n<TIMEOUT>\n", time.monotonic() - started


def stage_command(
    name: str, run_root: Path, args: argparse.Namespace,
    layers: tuple[str, ...], switches: tuple[str, ...],
) -> list[str]:
    report = run_root / f"{name}.json"
    work = run_root / name
    base = [sys.executable]
    dcc = []
    if args.dcc and args.dcc_lib:
        dcc = ["--dcc", str(args.dcc), "--dcc-lib", str(args.dcc_lib)]
    if name == "registry":
        return base + [str(SCRIPTS / "check_devil_registry.py")]
    if name == "codegen":
        return base + [str(SCRIPTS / "run_devil_codegen_gate.py"),
                       "--work", str(work), "--report", str(report)]
    if name == "asm-oracle":
        return base + [str(SCRIPTS / "run_asm_oracle_gate.py"),
                       "--work", str(work), "--report", str(report)]
    if name == "chimera":
        return base + [str(SCRIPTS / "run_chimera_gate.py"),
                       "--work", str(work), "--report", str(report)]
    if name == "stress":
        return base + [str(SCRIPTS / "run_devil_stress_gate.py"),
                       "--cases", str(args.stress_cases),
                       "--work", str(work), "--report", str(report)]
    if name == "reject":
        return base + [str(SCRIPTS / "run_devil_reject_gate.py"), *dcc,
                       "--work", str(work), "--report", str(report)]
    if name == "resident":
        return base + [str(SCRIPTS / "run_devil_resident_gate.py"),
                       "--work", str(work), "--report", str(report),
                       "--diagnostic-subset", "--carriers", "2", "--laps", "4",
                       "--profiles", "debug,release"]
    if name == "main":
        return base + [str(SCRIPTS / "run_devil_gate.py"), *dcc,
                       "--seeds", args.seeds, "--cases", str(args.cases),
                       "--layers", ",".join(layers),
                       "--profiles", args.profiles,
                       "--program-timeout", str(args.program_timeout),
                       *switches, "--work", str(work), "--report", str(report)]
    raise ValueError(f"unknown Devil stage: {name}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_text(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=tc.ROOT, capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip() if result.returncode == 0 else "<unavailable>"


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--dcc", type=Path)
    parser.add_argument("--dcc-lib", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--program-timeout", type=int, default=120)
    parser.add_argument("--run-id")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--keep-going", action="store_true")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="mode", required=True)
    light = sub.add_parser("light", help="fixed broad sub-minute regression ring")
    add_common_arguments(light)
    light.add_argument("--seeds", default="1")
    light.add_argument("--cases", type=int, default=1)
    light.add_argument("--profiles", default="debug,release")
    light.add_argument("--stress-cases", type=int, default=10)

    impact = sub.add_parser("impact", help="repair-area-specific Devil ring")
    add_common_arguments(impact)
    impact.add_argument("--areas", required=True,
                        help="comma-separated names printed by 'list'")
    impact.add_argument("--seeds", default="1")
    impact.add_argument("--cases", type=int, default=40)
    impact.add_argument("--profiles", default="debug,o2,release")
    impact.add_argument("--stress-cases", type=int, default=16)

    sub.add_parser("list", help="show impact areas and their exact coverage")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.mode == "list":
        for name, impact in IMPACTS.items():
            print(f"{name}: {impact.meaning}")
            print("  layers=" + ",".join(impact.layers))
            if impact.stages:
                print("  adjacent=" + ",".join(impact.stages))
        return 0
    if bool(args.dcc) != bool(args.dcc_lib):
        raise SystemExit("--dcc and --dcc-lib must be supplied together")
    if args.timeout <= 0 or args.program_timeout <= 0:
        raise SystemExit("timeouts must be positive")
    tc.preflight()
    if args.dcc:
        args.dcc = args.dcc.resolve()
        args.dcc_lib = args.dcc_lib.resolve()

    if args.mode == "light":
        areas: list[str] = []
        layers = ALL_LAYERS
        stages = LIGHT_STAGES
        switches: tuple[str, ...] = ()
    else:
        areas = [item for item in args.areas.split(",") if item]
        if not areas:
            raise SystemExit("impact mode needs at least one area")
        try:
            layers = canonical_layers(areas)
            stages = ("registry", "main", *adjacent_stages(areas))
            stages = tuple(stage for stage in STAGE_ORDER if stage in stages)
            switches = main_switches(areas)
        except ValueError as error:
            raise SystemExit(str(error)) from error

    run_id = args.run_id or (
        f"devil-{args.mode}-" + time.strftime("%Y%m%d-%H%M%S")
        + "-%07x" % (time.time_ns() & 0x0FFFFFFF)
    )
    if not re.fullmatch(r"[A-Za-z0-9._-]+", run_id):
        raise SystemExit("run-id may contain only letters, digits, dot, underscore and dash")
    run_root = ROOT / "results" / "runs" / run_id
    try:
        run_root.mkdir(parents=True)
    except FileExistsError as error:
        raise SystemExit(f"run already exists: {run_root}") from error

    rows = []
    failed = []
    for name in stages:
        command = stage_command(name, run_root, args, layers, switches)
        code, output, seconds = run(command, args.timeout)
        (run_root / f"{name}.log").write_text(output, encoding="utf-8")
        terminal = [line for line in output.splitlines() if line.startswith(
            ("DEVIL_", "ASM_ORACLE_", "CHIMERA_", "RESIDENT_"))][-8:]
        rows.append({"stage": name, "code": code,
                     "seconds": round(seconds, 1), "command": command,
                     "terminal": terminal})
        print(f"=== {name}: exit {code} in {seconds:.1f}s")
        for line in terminal:
            print("    " + line)
        if code != 0:
            failed.append(name)
            if not args.keep_going:
                break

    compiler, config, _, _ = tc.toolchain()
    report = {
        "contract": "targeted regression only; not the full Devil release gate",
        "mode": args.mode,
        "areas": areas,
        "layers": list(layers),
        "main_switches": list(switches),
        "repo_head": git_text("rev-parse", "HEAD"),
        "git_status": git_text("status", "--porcelain=v1"),
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "stages": rows,
        "failed": failed,
    }
    report_path = args.report.resolve() if args.report else run_root / "report.json"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                           encoding="utf-8")
    verdict = "OK" if not failed else "FINDINGS in " + ",".join(failed)
    print(f"DEVIL_TARGETED_{args.mode.upper()} {verdict}")
    print("NOT_RELEASE_GATE: run_devil_all.py is still mandatory before release")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
