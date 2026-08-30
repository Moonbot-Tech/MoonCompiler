#!/usr/bin/env python3
"""Devil mutation stand: measure whether Devil actually kills real defects.

A test suite that never fails proves nothing.  This stand takes the semantic
repair commits of this very repository, reverts one of them at a time, rebuilds
the compiler with the defect back in place, and runs Devil against it.

A mutant that Devil does not kill is a hole in coverage, named and printed.
That number - killed / total - is the honest measure of the complex.

Usage:
    run_devil_mutation.py --list
    run_devil_mutation.py --mutants 3 --seeds 1,2,3 --cases 150
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_ROOT = Path(__file__).resolve().parents[3]   # tree these scripts live in
ROOT = SCRIPT_ROOT                                  # tree that gets mutated
SUITE = SCRIPT_ROOT / "qualification" / "suite"

# Semantic repairs in the rewritten release ancestry.  Only product paths are
# reversed: the regression and generated tests must stay present, otherwise a
# whole-commit revert would erase the instrument that is meant to kill the
# mutant.  The inventory deliberately spans independent Devil families.
MUTANT_EXCLUSIONS = [
    ("834529910", "subsumed",
     "the current deterministic 2^32/33/47/63 matrix stays correct after the "
     "old reverse diff, so that diff no longer revives an observable defect"),
    ("a5ba6ebfd", "code-shape",
     "the repair removes a spurious local-unwind call without changing runtime "
     "semantics; its witness is the Win64 assembly gate, not Devil"),
]

MUTANTS = [
    ("5d09431ad", "nested", "lang,capture,inl", "Isolate expression context in nested routine bodies"),
    ("14f3b1cb2", "capture", "capture,lang", "Preserve complex Delphi with lvalue captures"),
    ("71b8f984c", "unit", "unit,ppu,gen", "Preserve source context during generic PPU replay"),
    ("6513e5e84", "flow", "flow,opt", "Preserve runtime loop bounds through x86 peephole passes"),
    ("1520d8009", "exc", "exc,flow,opt", "Keep Win64 SEH loops safe and eligible for unrolling"),
    ("3d09f43f0", "expr", "expr,cmp,pick", "Match Delphi mixed UInt64 integer semantics"),
    ("6433f4d0b", "flow", "flow,abi,expr", "Normalize ByteBool or expressions in Delphi mode"),
    ("f7be5b75a", "chk", "chk,flow", "Preserve overflow checks when lowering Inc and Dec"),
    ("ea318b0e6", "codegen", "expr,cmp,opt", "Preserve required MOVSXD after x86 arithmetic"),
    ("9d9e8e802", "unary", "unary,expr", "Match Delphi Hi and Lo byte semantics"),
    ("911d70a32", "set", "set,abi", "Match Delphi set storage and field alignment"),
    ("3c273a696", "float", "float,flow", "Keep inclusive floating selections branch-exact"),
    ("ddca7b059", "pick", "pick,call,lang", "Rank var/out by pure addressability"),
    ("fef5b2c9b", "lang", "lang,lit,unit,rtllib", "Materialize resourcestring typed constants"),
    ("c64038380", "asm", "asm,call", "Match Delphi frames for implicit x64 asm"),
    ("858f10c27", "opt", "opt,flow", "Invalidate loop scalars across opaque effects"),
    ("b86784a61", "lang", "lang,rtllib", "Dereference custom Variant carriers consistently"),
    ("4d5a3bfae", "life", "life,call,abi", "Release open-array carriers through throwing Finalize"),
]

# Some defects only exist in a particular compilation topology.  Layers name
# the semantic surface; these switches name the topology which makes that
# surface real.  A generic PPU-replay mutant cannot be measured by compiling
# all units from source in one compiler process.
MUTANT_GATE_ARGS = {
    "71b8f984c": ("--separate-units", "--ppu-reuse"),
}

# Later causal repairs may legitimately rewrite the same source hunk, so the
# old commit's reverse diff no longer describes an applicable mutant.  Keep a
# current-tree semantic mutation for those cases instead of silently dropping
# them or counting a patch conflict as a kill.
MUTANT_PATCH_FILES = {
    "9d9e8e802": "hilo-delphi-semantics.diff",
    "858f10c27": "opaque-loop-scalar-effects.diff",
    "b86784a61": "custom-variant-carrier.diff",
    "4d5a3bfae": "openarray-finalize-throw.diff",
}

PRODUCT_PATHS = ("compiler", "rtl", "packages")


def run(
    cmd: list[str], cwd: Path, timeout: int, input_text: str | None = None
) -> tuple[int, str]:
    env = dict(os.environ, DEVIL_TOOLCHAIN_ROOT=str(ROOT))
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, input=input_text,
            timeout=timeout, env=env,
        )
    except subprocess.TimeoutExpired:
        return 124, "<timeout>"
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def git(args: list[str], timeout: int = 300) -> tuple[int, str]:
    return run(["git"] + args, ROOT, timeout)


def rebuild(build_timeout: int) -> tuple[bool, str]:
    code, log = run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                     "-File", str(ROOT / "build.ps1"), "compiler"],
                    ROOT, build_timeout)
    return code == 0, log[-2000:]


def devil_findings(
    seeds: str, cases: int, layers: str, timeout: int,
    extra: tuple[str, ...] = (),
) -> tuple[int, dict[str, dict[str, object]], str]:
    """Return every structured observation, before known/new labelling."""
    gate = ROOT / "qualification" / "suite" / "scripts" / "run_devil_gate.py"
    work = ROOT / ".mutation" / "devil-main"
    report = work / "mutation-gate-report.json"
    report.unlink(missing_ok=True)
    code, log = run([sys.executable, str(gate),
                     "--seeds", seeds, "--cases", str(cases),
                     "--layers", layers,
                     "--work", str(work), "--report", str(report), *extra],
                    ROOT, timeout)
    observations = load_observations(report) if report.is_file() else {}
    return code, observations, log


def load_observations(path: Path) -> dict[str, dict[str, object]]:
    """Flatten a gate report without allowing the known registry to hide it."""
    observations: dict[str, dict[str, object]] = {}
    for seed_row in json.loads(path.read_text(encoding="utf-8")):
        seed = seed_row["seed"]
        for collection in ("findings", "known_hits"):
            for source in seed_row.get(collection, []):
                row = {key: value for key, value in source.items()
                       if key != "known"}
                row["seed"] = seed
                key = json.dumps(row, sort_keys=True, ensure_ascii=False)
                observations[key] = row
    return observations


def apply_product_mutation(sha: str, check_only: bool = False) -> tuple[bool, str]:
    patch_name = MUTANT_PATCH_FILES.get(sha)
    if patch_name:
        patch_path = (SUITE / "tests" / "devil" / "mutations" / patch_name)
        if not patch_path.is_file():
            return False, f"missing semantic mutation patch: {patch_path}"
        command = ["git", "apply", "--whitespace=nowarn"]
        if check_only:
            command.append("--check")
        try:
            proc = subprocess.run(command + ["-"], cwd=ROOT,
                                  capture_output=True,
                                  input=patch_path.read_bytes(), timeout=300)
        except subprocess.TimeoutExpired:
            return False, "semantic mutation apply timed out"
        detail = ((proc.stdout or b"") + (proc.stderr or b"")).decode(
            "utf-8", errors="replace")
        return proc.returncode == 0, detail
    else:
        code, patch = git(["show", "--format=", "--binary", sha, "--",
                           *PRODUCT_PATHS])
        if code != 0 or not patch.strip():
            return False, "repair has no product patch"
        command = ["git", "apply", "--reverse", "--whitespace=nowarn"]
    if check_only:
        command.append("--check")
    command.append("-")
    code, detail = run(command, ROOT, 300, patch)
    return code == 0, detail


def finding_family(row: dict[str, object]) -> str:
    layer = row.get("layer")
    if isinstance(layer, str) and layer:
        return layer
    for key in ("check", "note"):
        name = row.get(key)
        if isinstance(name, str) and name.startswith("dvl-"):
            parts = name.split("-", 2)
            if len(parts) >= 2:
                return parts[1]
    return str(row.get("kind", "unknown"))


def baseline_layer_sets(
    selected: list[tuple[str, str, str, str]], all_layers: bool
) -> list[str]:
    """A structured baseline must describe the exact generated program."""
    return ["all"] if all_layers else sorted({item[2] for item in selected})


def baseline_configs(
    selected: list[tuple[str, str, str, str]], all_layers: bool
) -> list[tuple[str, tuple[str, ...]]]:
    """Every baseline matches both the generated source and build topology."""
    configs = {
        ("all" if all_layers else layers, MUTANT_GATE_ARGS.get(sha, ()))
        for sha, _family, layers, _subject in selected
    }
    return sorted(configs)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--repo", type=Path,
                   help="explicitly disposable clone to mutate")
    p.add_argument("--seeds", default="1,2,3")
    p.add_argument("--cases", type=int, default=150)
    p.add_argument("--mutants", type=int, default=len(MUTANTS))
    p.add_argument("--from-index", type=int, default=0)
    p.add_argument("--build-timeout", type=int, default=3600)
    p.add_argument("--gate-timeout", type=int, default=1800)
    p.add_argument("--report", type=Path)
    p.add_argument("--list", action="store_true")
    p.add_argument("--only", default="", help="comma separated commit shas")
    p.add_argument("--all-layers", action="store_true",
                   help="stress mode: run every Devil layer for every mutant")
    args = p.parse_args()

    if args.repo:
        global ROOT
        ROOT = args.repo.resolve()
        if not (ROOT / "build.ps1").is_file():
            raise SystemExit(f"not a compiler tree: {ROOT}")

    if args.list:
        for i, (sha, family, layers, subject) in enumerate(MUTANTS):
            print(f"{i:3d}  {sha}  {family:8s}  {layers:20s}  {subject}")
        for sha, kind, reason in MUTANT_EXCLUSIONS:
            print(f"  -  {sha}  excluded:{kind:10s}  {reason}")
        return

    if not args.repo:
        raise SystemExit(
            "--repo is required: mutation uses git revert/reset and must run "
            "in an explicitly disposable clone"
        )

    # untracked Devil files are fine; only modified tracked files would be
    # swallowed by the revert/restore cycle
    code, status = git(["status", "--porcelain", "--untracked-files=no"])
    if status.strip():
        print("working tree is dirty; mutation reverts and hard-resets the tree,"
              " which would destroy uncommitted work")
        print(status)
        sys.exit(2)

    # findings the clean compiler already produces are noise for every mutant:
    # only what a mutant adds on top of them says Devil saw the defect
    print("checking that every targeted product mutation applies cleanly")
    invalid_inventory = []
    for sha, family, layers, subject in MUTANTS:
        valid, detail = apply_product_mutation(sha, check_only=True)
        if not valid:
            invalid_inventory.append({"sha": sha, "family": family,
                                      "layers": layers,
                                      "subject": subject,
                                      "detail": detail[-300:]})
    if invalid_inventory:
        for row in invalid_inventory:
            print(json.dumps({"outcome": "invalid-conflict", **row},
                             ensure_ascii=False))
        raise SystemExit("mutation inventory contains non-applicable patches")

    print("building the clean compiler in the disposable tree")
    built, build_log = rebuild(args.build_timeout)
    if not built:
        print(build_log)
        raise SystemExit("clean compiler build failed before mutation")

    if args.only:
        wanted = [x.strip() for x in args.only.split(",") if x.strip()]
        selected = [m for m in MUTANTS if m[0] in wanted]
    else:
        selected = MUTANTS[args.from_index:args.from_index + args.mutants]
    if not selected:
        raise SystemExit("no mutants selected")
    baselines: dict[tuple[str, tuple[str, ...]],
                    dict[str, dict[str, object]]] = {}
    for layers, extra in baseline_configs(selected, args.all_layers):
        topology = ",".join(extra) or "single-process"
        print(f"measuring the clean baseline for layers={layers} "
              f"topology={topology}")
        baseline_code, baseline, baseline_log = devil_findings(
            args.seeds, args.cases, layers, args.gate_timeout, extra
        )
        if baseline_code != 0:
            print(baseline_log[-4000:])
            raise SystemExit("clean Devil baseline is not green")
        baselines[(layers, extra)] = baseline
        print(f"baseline {layers} topology={topology}: "
              f"{len(baseline)} classified observations")

    results = []
    for sha, family, target_layers, subject in selected:
        started = time.time()
        layers = "all" if args.all_layers else target_layers
        extra = MUTANT_GATE_ARGS.get(sha, ())
        row = {"sha": sha, "family": family, "layers": layers,
               "subject": subject, "gate_args": list(extra)}
        applied, detail = apply_product_mutation(sha)
        if not applied:
            row.update({"outcome": "invalid-conflict", "detail": detail[-300:]})
            results.append(row)
            print(json.dumps(row, ensure_ascii=False))
            continue

        built, build_log = rebuild(args.build_timeout)
        if not built:
            row.update({"outcome": "invalid-build", "detail": build_log[-300:]})
        else:
            gate_code, found, gate_log = devil_findings(
                args.seeds, args.cases, layers, args.gate_timeout, extra
            )
            fresh_keys = sorted(set(found) - set(baselines[(layers, extra)]))
            fresh = [found[key] for key in fresh_keys]
            if gate_code != 0 and not fresh:
                row.update({"outcome": "invalid-gate",
                            "detail": gate_log[-500:]})
            else:
                row.update({"outcome": "killed" if fresh else "survived",
                            "new_findings": fresh[:8],
                            "new_count": len(fresh),
                            "killed_by_families": sorted({
                                finding_family(item) for item in fresh
                            })})
        row["seconds"] = round(time.time() - started, 1)
        results.append(row)
        print(json.dumps(row, ensure_ascii=False))

        # a revert can delete files, so only a hard reset restores the tree;
        # untracked Devil files are left alone by it
        git(["reset", "--hard", "HEAD"])
        git(["clean", "-fdq", "compiler", "rtl", "packages"])

    # Every mutant build starts from the external FPC 3.2.2 bootstrap, not the
    # previously installed product compiler.  Rebuilding a clean toolchain
    # between mutants therefore adds no isolation; restore it once at the end.
    print("restoring the clean compiler after the last mutant")
    restored, restore_log = rebuild(args.build_timeout)
    if not restored:
        print(restore_log)
        raise SystemExit("failed to restore the clean compiler after mutation")

    usable = [r for r in results if r["outcome"] in ("killed", "survived")]
    invalid = [r for r in results if r["outcome"].startswith("invalid-")]
    killed = sum(1 for r in usable if r["outcome"] == "killed")
    family_kills: dict[str, int] = {}
    for row in results:
        for family in row.get("killed_by_families", []):
            family_kills[family] = family_kills.get(family, 0) + 1
    print(f"DEVIL_MUTATION killed={killed}/{len(usable)} "
          f"invalid={len(invalid)}")
    print("DEVIL_MUTATION_FAMILIES " +
          json.dumps(family_kills, sort_keys=True, ensure_ascii=False))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(results, indent=2, ensure_ascii=False)
                               + "\n", encoding="utf-8")
    # a surviving mutant is a coverage hole, and that is a failure of Devil
    sys.exit(0 if not invalid and usable and killed == len(usable) else 1)


if __name__ == "__main__":
    main()
