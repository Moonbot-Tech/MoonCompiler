"""Managed-value assignment and exception ownership: values, destruction and MM balance."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import shutil


CASES = {
    "RttiManagedFieldContract": ([["--direct"], ["--rtti"]], "RTTI_MANAGED_FIELD_VALUES_PASS"),
    "RttiManagedNeighbors": ([[x] for x in ["Ref", "Items", "Data", "V"]], "VALUES_PASS"),
    "RttiLifetimeAudit": ([[x] for x in ["field", "record", "custom", "property", "staticprop", "recordprop", "callback", "callbackresult", "virtual", "fresh"]], "AUDIT_PASS"),
    "AcquiredExceptionContract": ([["--direct"], ["--acquire"]], "ACQUIRED_EXCEPTION_LIFETIME_PASS"),
    "StackOwnershipContract": ([[x] + trace for x in ["--direct", "--acquire"] for trace in [[], ["--trace"]]], "STALE_RAISE_LIST_ENTRIES=0"),
    "ExceptionOwnership": ([[mode, trace] for mode in ["balanced", "multi", "nested", "reraise", "saved-raise", "replacement", "finally-replace", "thread", "fatal"] for trace in ["plain", "trace"]], "EXCEPTION_OWNERSHIP_PASS"),
    "StaticPropertyAudit": ([[]], "AUDIT_PASS"),
    "FinallyNeighbors": ([[m] for m in ["nested", "local-catch", "outer-catch", "local-handled", "av-replacement", "replacement-av", "av-outer-catch"]], "PASS "),
    "SEHLocalUnwindAudit": ([[mode] for mode in ["exit", "break", "continue"]], "PASS"),
    "ExceptionLifetimeAudit": ([[mode, trace] for mode in ["exit", "break", "continue", "recapture", "active-saved-raise", "nested-balanced", "caught-finally"] for trace in ["plain", "trace"]], "AUDIT_PASS"),
}


def passed(returncode, output, marker):
    counts = re.findall(r"FPCX64MM_DIAGNOSTIC live-blocks=(\d+)", output)
    return returncode == 0 and marker in output and counts == ["0"]


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, default=root / ("toolchain/bin/x86_64-win64/fpc.exe" if os.name == "nt" else "toolchain/bin/fpc"))
    parser.add_argument("--output", type=Path, default=root / ".qualification/rtl-ownership")
    parser.add_argument("--unit-dir", type=Path, action="append", default=[])
    parser.add_argument("--profiles", nargs="+", choices=["debug", "O2", "O3"], default=["debug", "O2", "O3"])
    parser.add_argument("--group", choices=["all", "rtti", "exception"], default="all")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--bindir", type=Path)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    if os.name == "nt":
        ctypes.windll.kernel32.SetErrorMode(3)
    prefix = [str(compiler)]
    if args.config:
        prefix += ["-n", "@" + str(args.config.resolve())]
    if args.bindir:
        prefix += ["-FD" + str(args.bindir.resolve())]
    rows = []
    for profile in args.profiles:
        flags = ["-O-"] if profile == "debug" else ["-dRELEASE", "-" + profile]
        for name, (cases, marker) in CASES.items():
            if name == "SEHLocalUnwindAudit" and os.name != "nt":
                continue
            if args.group != "all" and (name.startswith("Rtti") or name == "StaticPropertyAudit") != (args.group == "rtti"):
                continue
            out = (args.output / profile / name).resolve()
            out.mkdir(parents=True, exist_ok=True)
            source = Path(__file__).resolve().parent / "cases" / (name + ".dpr")
            command = [*prefix, "-B", *flags, "-dFPCX64MM_DIAGNOSTIC", "-dFPCMM_REPORTMEMORYLEAKS", "-FU" + str(out), "-FE" + str(out)]
            command += ["-Fu" + str(unit.resolve()) for unit in args.unit_dir]
            if name == "StaticPropertyAudit":
                isolated = out / "unit-source"
                isolated.mkdir(exist_ok=True)
                unit = isolated / "StaticPropertyTypes.pas"
                shutil.copyfile(source.with_name(unit.name), unit)
                unit_build = subprocess.run(command + [str(unit)], cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
                (out / "unit-build.log").write_bytes(unit_build.stdout)
                if unit_build.returncode:
                    raise RuntimeError(f"Unit build failed: {out / 'unit-build.log'}")
                unit.replace(unit.with_suffix(".hidden"))
                target = out / source.name
                shutil.copyfile(source, target)
                source = target
                command.remove("-B")
                command += ["-Fu" + str(out)]
            command.append(str(source))
            build = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            (out / "build.log").write_bytes((repr(command) + "\n").encode() + build.stdout)
            if build.returncode:
                raise RuntimeError(f"Build failed: {out / 'build.log'}")
            for index, case in enumerate(cases):
                exe = out / (name + (".exe" if os.name == "nt" else ""))
                result = subprocess.run([str(exe), *case], cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
                output = result.stdout.decode("utf-8", errors="replace")
                (out / f"{index:02d}.log").write_text(output, encoding="utf-8")
                ok = passed(result.returncode, output, marker)
                if name == "RttiManagedNeighbors" and case == ["Ref"]:
                    ok = ok and "destroyed=64" in output
                rows.append(dict(profile=profile, source=name, args=case, passed=ok, returncode=result.returncode))
                if not ok:
                    print(f"FAIL {profile} {name} {case}: {out / f'{index:02d}.log'}", flush=True)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "results.json").write_text(json.dumps(dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), rows=rows), indent=2), encoding="utf-8")
    print(f"RTL_OWNERSHIP {'PASS' if all(row['passed'] for row in rows) else 'FAIL'} {sum(row['passed'] for row in rows)}/{len(rows)}", flush=True)
    return int(not all(row['passed'] for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
