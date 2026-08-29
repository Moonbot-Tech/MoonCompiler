#!/usr/bin/env python3
"""Run the optimizer-core cold/warm PPU determinism and rejection gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "qualification" / "suite" / "tests" / "optimizer-core" / "ppu"
UNIT = SOURCE / "optcore_ppu_fixture.pas"
PROGRAM = SOURCE / "optcore_ppu_consumer.dpr"
EXPECTED_OUTPUT = "PPU_GATE_OK 877"
EXECUTABLE_NAME = PROGRAM.stem + (".exe" if os.name == "nt" else "")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def run(command: list[str], cwd: Path, log: Path) -> tuple[int, float]:
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    elapsed = time.perf_counter() - started
    log.write_text(completed.stdout, encoding="utf-8", newline="\n")
    return completed.returncode, elapsed


def compiler_command(compiler: Path, config: Path) -> list[str]:
    return [str(compiler), "-n", f"@{config}", "-Mdelphi", "-O3"]


def build(
    compiler: Path,
    config: Path,
    output: Path,
    log: Path,
    rebuild: bool,
) -> float:
    command = compiler_command(compiler, config)
    if rebuild:
        command.append("-B")
    command.extend([
        f"-Fu{SOURCE}",
        f"-FU{output}",
        f"-FE{output}",
        str(PROGRAM),
    ])
    code, elapsed = run(command, ROOT, log)
    if code != 0:
        raise RuntimeError(f"compile failed ({code}): {log}")
    return elapsed


def execute(executable: Path, log: Path) -> float:
    code, elapsed = run([str(executable)], ROOT, log)
    output = log.read_text(encoding="utf-8").strip()
    if code != 0 or output != EXPECTED_OUTPUT:
        raise RuntimeError(
            f"semantic output differs: exit={code}, output={output!r}"
        )
    return elapsed


def artifact(path: Path) -> dict[str, int | str]:
    stat = path.stat()
    return {
        "path": str(path),
        "sha256": sha256(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }


def build_artifacts(output: Path) -> dict[str, dict[str, int | str]]:
    paths = {
        "ppu": output / "optcore_ppu_fixture.ppu",
        "unit_object": output / "optcore_ppu_fixture.o",
        "program_object": output / "optcore_ppu_consumer.o",
        "executable": output / EXECUTABLE_NAME,
    }
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        raise RuntimeError("missing PPU artifacts: " + ", ".join(missing))
    return {name: artifact(path) for name, path in paths.items()}


def same_bytes(
    left: dict[str, dict[str, int | str]],
    right: dict[str, dict[str, int | str]],
) -> bool:
    return all(
        left[name]["sha256"] == right[name]["sha256"]
        and left[name]["size"] == right[name]["size"]
        for name in left
    )


def legacy_negative(
    legacy_compiler: Path,
    compiler: Path,
    config: Path,
    output: Path,
) -> dict[str, object]:
    legacy = output / "legacy-ppu"
    negative = output / "legacy-negative"
    legacy.mkdir()
    negative.mkdir()
    code, legacy_seconds = run([
        str(legacy_compiler),
        "-Mdelphi",
        "-O2",
        "-B",
        "-Cn",
        f"-FU{legacy}",
        str(UNIT),
    ], ROOT, output / "legacy-compile.log")
    if code != 0:
        raise RuntimeError("legacy PPU setup failed")
    legacy_ppu = legacy / "optcore_ppu_fixture.ppu"
    if not legacy_ppu.is_file():
        raise RuntimeError("legacy compiler did not produce a PPU")
    isolated_program = negative / PROGRAM.name
    shutil.copy2(PROGRAM, isolated_program)
    command = compiler_command(compiler, config)
    command.extend([
        f"-Fu{legacy}",
        f"-FU{negative}",
        f"-FE{negative}",
        str(isolated_program),
    ])
    code, reject_seconds = run(
        command, negative, output / "legacy-reject.log"
    )
    reject_text = (output / "legacy-reject.log").read_text(
        encoding="utf-8", errors="replace"
    ).casefold()
    clean_rejection = (
        code != 0
        and "ppu" in reject_text
        and ("version" in reject_text or "invalid" in reject_text)
    )
    if not clean_rejection:
        raise RuntimeError(
            "incompatible legacy PPU was not rejected with a PPU diagnostic"
        )
    return {
        "legacy_compiler": str(legacy_compiler),
        "legacy_compiler_sha256": sha256(legacy_compiler),
        "legacy_ppu": artifact(legacy_ppu),
        "legacy_compile_seconds": round(legacy_seconds, 6),
        "consumer_exit_code": code,
        "reject_seconds": round(reject_seconds, 6),
        "clean_rejection": clean_rejection,
        "reject_log": str(output / "legacy-reject.log"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--compiler", type=Path, default=ROOT / ".moonbot/toolchain/bin/fpc"
    )
    parser.add_argument(
        "--config", type=Path,
        default=ROOT / ".moonbot/toolchain/etc/fpc.cfg",
    )
    parser.add_argument(
        "--legacy-compiler", type=Path, default=Path("/usr/bin/fpc")
    )
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    config = args.config.resolve()
    legacy_compiler = args.legacy_compiler.resolve()

    cold_a = output / "cold-a"
    cold_b = output / "cold-b"
    cold_a.mkdir()
    cold_b.mkdir()

    cold_a_seconds = build(
        compiler, config, cold_a, output / "cold-a-compile.log", True
    )
    cold_a_run_seconds = execute(
        cold_a / EXECUTABLE_NAME, output / "cold-a-run.log"
    )
    cold_a_before_warm = build_artifacts(cold_a)
    warm_seconds = build(
        compiler, config, cold_a, output / "warm-compile.log", False
    )
    warm_run_seconds = execute(
        cold_a / EXECUTABLE_NAME, output / "warm-run.log"
    )
    warm_artifacts = build_artifacts(cold_a)
    ppu_not_rebuilt = (
        cold_a_before_warm["ppu"]["sha256"] == warm_artifacts["ppu"]["sha256"]
        and cold_a_before_warm["ppu"]["mtime_ns"] == warm_artifacts["ppu"]["mtime_ns"]
        and cold_a_before_warm["unit_object"]["mtime_ns"]
        == warm_artifacts["unit_object"]["mtime_ns"]
    )
    if not ppu_not_rebuilt:
        raise RuntimeError("warm compile unexpectedly regenerated the unit PPU/object")

    cold_b_seconds = build(
        compiler, config, cold_b, output / "cold-b-compile.log", True
    )
    cold_b_run_seconds = execute(
        cold_b / EXECUTABLE_NAME, output / "cold-b-run.log"
    )
    cold_b_artifacts = build_artifacts(cold_b)
    cold_deterministic = same_bytes(cold_a_before_warm, cold_b_artifacts)
    if not cold_deterministic:
        raise RuntimeError("independent cold PPU builds are not byte-identical")

    negative = legacy_negative(
        legacy_compiler, compiler, config, output
    )
    result = {
        "schema": 1,
        "status": "pass",
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "sources": {
            str(UNIT.relative_to(ROOT)): sha256(UNIT),
            str(PROGRAM.relative_to(ROOT)): sha256(PROGRAM),
        },
        "expected_output": EXPECTED_OUTPUT,
        "cold_a_seconds": round(cold_a_seconds, 6),
        "warm_seconds": round(warm_seconds, 6),
        "cold_b_seconds": round(cold_b_seconds, 6),
        "run_seconds": {
            "cold_a": round(cold_a_run_seconds, 6),
            "warm": round(warm_run_seconds, 6),
            "cold_b": round(cold_b_run_seconds, 6),
        },
        "cold_a": cold_a_before_warm,
        "warm": warm_artifacts,
        "cold_b": cold_b_artifacts,
        "ppu_not_rebuilt_warm": ppu_not_rebuilt,
        "cold_builds_byte_identical": cold_deterministic,
        "legacy_negative": negative,
    }
    result_path = output / "result.json"
    result_path.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"PPU_GATE_PASS {result_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
