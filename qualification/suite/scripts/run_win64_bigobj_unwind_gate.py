#!/usr/bin/env python3
"""Cross the 16-bit COFF section boundary with live Win64 unwind records."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path


ROUTINE_COUNT = 12000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], cwd: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def bigobj_section_count(path: Path) -> int:
    with path.open("rb") as stream:
        header = stream.read(56)
    if len(header) != 56 or struct.unpack_from("<HHH", header) != (0, 0xFFFF, 2):
        raise ValueError("compiler did not emit a COFF bigobj object")
    return struct.unpack_from("<I", header, 44)[0]


def source_text() -> str:
    lines = [
        "program win64_bigobj_unwind;",
        "",
        "{$mode delphiunicode}{$H+}",
        "{$APPTYPE CONSOLE}",
        "{$Q-}{$R-}",
        "",
        "var",
        "  Sink: Int64;",
        "",
    ]
    for index in range(ROUTINE_COUNT):
        lines += [
            f"procedure Probe{index:05d};",
            "begin",
            "  try",
            "    Inc(Sink);",
            "  finally",
            "    Inc(Sink);",
            "  end;",
            "end;",
            "",
        ]
    lines += ["begin"]
    lines += [f"  Probe{index:05d};" for index in range(ROUTINE_COUNT)]
    lines += [
        f"  If Sink <> {ROUTINE_COUNT * 2} then",
        "    Halt(2);",
        "  WriteLn('WIN64_BIGOBJ_UNWIND_PASS');",
        "end.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("run_id")
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    config = args.config.resolve()
    compiler_root = args.compiler_root.resolve()
    result = (compiler_root / "qualification" / "suite" / "results" /
              "runs" / args.run_id / "win64-bigobj-unwind")
    if result.exists():
        parser.error(f"run already exists: {result}")
    if not compiler.is_file() or not config.is_file():
        parser.error("compiler and config must exist")
    if run([str(compiler), "-iTP"], compiler.parent, 30).stdout.strip().lower() != "x86_64":
        parser.error("compiler target processor is not x86_64")
    if run([str(compiler), "-iTO"], compiler.parent, 30).stdout.strip().lower() != "win64":
        parser.error("compiler target OS is not Win64")

    result.mkdir(parents=True)
    source = result / "win64_bigobj_unwind.pp"
    source.write_text(source_text(), encoding="utf-8")
    command = [
        str(compiler), "-n", f"@{config}", "-B", "-O2", "-CX", "-XX",
        "-Px86_64", "-Twin64", f"-FU{result}", f"-FE{result}", str(source),
    ]
    compiled = run(command, result, 900)
    (result / "compile.log").write_text(
        compiled.stdout + compiled.stderr, encoding="utf-8"
    )
    failures: list[str] = []
    if compiled.returncode != 0:
        failures.append(f"compile exit {compiled.returncode}")
    executable = result / "win64_bigobj_unwind.exe"
    object_file = result / "win64_bigobj_unwind.o"
    section_count = None
    runtime = None
    if not failures:
        try:
            section_count = bigobj_section_count(object_file)
        except (OSError, ValueError) as error:
            failures.append(str(error))
        if section_count is not None and section_count <= 0xFFFF:
            failures.append(f"object has only {section_count} sections")
    if not failures:
        runtime = run([str(executable)], result, 60)
        (result / "run.log").write_text(
            runtime.stdout + runtime.stderr, encoding="utf-8"
        )
        if runtime.returncode != 0 or runtime.stdout.strip() != "WIN64_BIGOBJ_UNWIND_PASS":
            failures.append(
                f"runtime exit {runtime.returncode}: {runtime.stdout.strip()!r}"
            )
    manifest = {
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "routine_count": ROUTINE_COUNT,
        "object_section_count": section_count,
        "source_sha256": sha256(source),
        "compile_exit": compiled.returncode,
        "run_exit": None if runtime is None else runtime.returncode,
        "failures": failures,
    }
    (result / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    if failures:
        print("WIN64_BIGOBJ_UNWIND_FAIL: " + "; ".join(failures))
        return 1
    print(
        f"WIN64_BIGOBJ_UNWIND_PASS routines={ROUTINE_COUNT} "
        f"sections={section_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
