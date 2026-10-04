#!/usr/bin/env python3
"""Check that internal compiler symbols do not hide or create user diagnostics."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, capture_output=True, text=True, timeout=120, check=False,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("run_id")
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    config = args.config.resolve()
    root = args.compiler_root.resolve()
    if not compiler.is_file() or not config.is_file():
        parser.error("compiler and config must exist")

    output = root / "qualification" / "suite" / "results" / "runs" / args.run_id / "compiler-diagnostics"
    if output.exists():
        parser.error(f"run already exists: {output}")
    output.mkdir(parents=True)

    sources = {
        "valid_safecall": (
            "program valid_safecall;\n"
            "{$mode delphiunicode}\n"
            "function AddResult(X: Integer): Integer; safecall;\n"
            "begin Result := X + 1; end;\n"
            "function AddAlias(X: Integer): Integer; safecall;\n"
            "begin AddAlias := X + 2; end;\n"
            "function TextResult: UnicodeString; safecall;\n"
            "begin Result := 'ok'; end;\n"
            "procedure NoResult; safecall; begin end;\n"
            "begin\n"
            "  If (AddResult(1) <> 2) or (AddAlias(1) <> 3) or (TextResult <> 'ok') then Halt(1);\n"
            "  NoResult;\n"
            "end.\n"
        ),
        "missing_safecall_result": (
            "program missing_safecall_result;\n"
            "{$mode delphiunicode}\n"
            "function Missing(X: Integer): Integer; safecall;\n"
            "begin If X = MaxInt then Halt(1); end;\n"
            "begin Halt(Missing(1)); end.\n"
        ),
        "missing_normal_result": (
            "program missing_normal_result;\n"
            "{$mode delphiunicode}\n"
            "function Missing(X: Integer): Integer;\n"
            "begin If X = MaxInt then Halt(1); end;\n"
            "begin Halt(Missing(1)); end.\n"
        ),
    }
    failures: list[str] = []
    results: dict[str, object] = {}
    common = [
        str(compiler), "-n", f"@{config}", "-B", "-Cn", "-Sew", "-vw",
        "-dMOONCOMPILER_VANILLA_RUNTIME", f"-FU{output}",
    ]
    diagnostic = "function result does not seem to be set"

    for name, text in sources.items():
        source = output / f"{name}.pas"
        source.write_text(text, encoding="utf-8")
        compiled = run([*common, str(source)], root)
        log = compiled.stdout + compiled.stderr
        (output / f"{name}.log").write_text(log, encoding="utf-8")
        has_diagnostic = diagnostic in log.lower()
        expect_success = name == "valid_safecall"
        if expect_success:
            if compiled.returncode != 0 or has_diagnostic:
                failures.append("valid safecall source produced a result warning")
        elif compiled.returncode == 0 or not has_diagnostic:
            failures.append(f"{name} did not preserve the user result warning")
        results[name] = {
            "compile_exit": compiled.returncode,
            "result_diagnostic": has_diagnostic,
        }

    manifest = {"results": results, "failures": failures}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    if failures:
        print("COMPILER_DIAGNOSTIC_FAIL: " + "; ".join(failures))
        return 1
    print("COMPILER_DIAGNOSTIC_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
