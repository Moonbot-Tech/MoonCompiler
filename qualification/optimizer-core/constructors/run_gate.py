#!/usr/bin/env python3
"""Check empty inherited constructor proof across a source-free PPU boundary."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXPECTED = "CONSTRUCTOR_STAGE2_PASS 8 8 9 7 8 1 1 1 1"


def run(command: list[str], directory: Path, name: str) -> str:
    completed = subprocess.run(command, cwd=directory, capture_output=True, text=True, timeout=90)
    text = completed.stdout + completed.stderr
    (directory / (name + ".log")).write_text(text, encoding="utf-8")
    (directory / (name + "-command.json")).write_text(json.dumps(command, indent=2), encoding="utf-8")
    if completed.returncode:
        raise RuntimeError(f"{name} failed ({completed.returncode}): {directory / (name + '.log')}")
    return text


def function_body(assembly: str, fragment: str) -> str:
    labels = list(re.finditer(r"^[0-9a-f]+ <([^>]+)>:", assembly, re.M))
    matches = [(index, label) for index, label in enumerate(labels) if fragment in label.group(1)]
    if len(matches) != 1:
        raise RuntimeError(f"expected one linked function matching {fragment}, found {len(matches)}")
    index, label = matches[0]
    end = labels[index + 1].start() if index + 1 < len(labels) else len(assembly)
    return assembly[label.end():end]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    binary = ROOT / "toolchain/bin"
    parser.add_argument("--compiler", type=Path, default=binary / ("x86_64-win64/ppcx64.exe" if os.name == "nt" else "fpc"))
    parser.add_argument("--config", type=Path, default=(binary / "x86_64-win64/moon-base.cfg" if os.name == "nt"
                                                     else ROOT / "toolchain/etc/moon-base.cfg"))
    parser.add_argument("--output", type=Path, default=ROOT / ".qualification/empty-constructor-gate")
    args = parser.parse_args()
    compiler, config, output = (path.resolve() for path in (args.compiler, args.config, args.output))
    output.mkdir(parents=True, exist_ok=False)
    disassembler = os.environ.get("MOON_OBJDUMP") or shutil.which("llvm-objdump" if os.name == "nt" else "objdump")
    if disassembler is None:
        raise RuntimeError("linked ASM verification requires MOON_OBJDUMP, llvm-objdump on Windows or objdump on Linux")
    rows = []
    for producer_opt, consumer_opt, checked in (
        ("O-", "O-", False), ("O2", "O2", False), ("O3", "O3", False),
        ("O2", "O3", False), ("O3", "O-", False), ("O3", "O3", True),
    ):
        directory = output / (producer_opt + "-" + consumer_opt + ("-stackcheck" if checked else ""))
        directory.mkdir()
        units = directory / "units"
        units.mkdir()
        base = directory / "contractbase.pas"
        app = directory / "contract.dpr"
        shutil.copyfile(HERE / base.name, base)
        shutil.copyfile(HERE / app.name, app)
        command = [str(compiler), "-n", "@" + str(config)]
        run(command + ["-" + producer_opt, "-B", "-FU" + str(units)] +
            (["-Ct"] if checked else []) + [str(base)], directory, "producer")
        # The consumer must use the PPU; a successful implicit source rebuild is not proof.
        base.rename(base.with_suffix(".source-hidden"))
        run(command + ["-" + consumer_opt, "-Fu" + str(units), "-FU" + str(units),
            "-FE" + str(directory), str(app)], directory, "consumer")
        executable = directory / ("contract.exe" if os.name == "nt" else "contract")
        actual = run([str(executable)], directory, "semantic").strip()
        if actual != EXPECTED:
            raise RuntimeError(f"constructor lifecycle differs: {actual!r}")
        assembly = run([disassembler, "-d", str(executable)], directory, "assembly")
        body = function_body(assembly, "_$TCHILD_$__$$_PLAIN$")
        calls = [line for line in body.splitlines()
                 if re.search(r"\bcall[q]?\s", line) and "_$TEMPTY_$__$$_EMPTY" in line]
        expected_calls = int(checked or producer_opt == "O-" or consumer_opt == "O-")
        if len(calls) != expected_calls:
            raise RuntimeError(f"inherited empty call count {len(calls)}, expected {expected_calls}: {directory}")
        for caller, callee in (("NONEMPTYPARENT", "NONEMPTY"), ("LOCAL", "MANAGEDLOCAL"),
                               ("OUTVALUE", "OUTTEXT")):
            body = function_body(assembly, "_$TCHILD_$__$$_" + caller)
            if not any(re.search(r"\bcall[q]?\s", line) and "_$TEMPTY_$__$$_" + callee in line
                       for line in body.splitlines()):
                raise RuntimeError(f"implicit or explicit constructor work removed: {caller}")
        rows.append({"producer": producer_opt, "consumer": consumer_opt, "stackcheck": checked,
                     "empty_calls": len(calls), "sha256": hashlib.sha256(executable.read_bytes()).hexdigest()})
    result = {"status": "pass", "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
              "config_sha256": hashlib.sha256(config.read_bytes()).hexdigest(), "rows": rows}
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"EMPTY_CONSTRUCTOR_GATE_PASS semantic={len(rows)} asm={len(rows)} output={output}")


if __name__ == "__main__":
    main()
