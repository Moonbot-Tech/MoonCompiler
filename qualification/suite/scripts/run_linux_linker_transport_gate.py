#!/usr/bin/env python3
"""Prove that long linker metadata reaches the emitted ELF unchanged."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import subprocess
from pathlib import Path


def run(
    command: list[str], cwd: Path, timeout: int = 120,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, capture_output=True, text=True, timeout=timeout,
        check=False, env=environment,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def compile_command(
    compiler: Path, config: Path, source: Path, output: Path, *extra: str,
) -> list[str]:
    return [
        str(compiler), "-n", f"@{config}", "-B", "-O2", "-Px86_64",
        "-Tlinux", f"-FU{output}", f"-FE{output}", *extra, str(source),
    ]


def find_interpreter() -> Path:
    for candidate in (
        Path("/lib64/ld-linux-x86-64.so.2"),
        Path("/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"),
    ):
        if candidate.is_file():
            return candidate
    raise FileNotFoundError("x86-64 Linux dynamic interpreter was not found")


def elf_interpreter(path: Path) -> bytes | None:
    """Read PT_INTERP itself: readelf may truncate even its wide display."""
    with path.open("rb") as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:6] != b"\x7fELF\x02\x01":
            raise ValueError("gate expects little-endian ELF64")
        program_offset = struct.unpack_from("<Q", header, 32)[0]
        entry_size, count = struct.unpack_from("<HH", header, 54)
        if entry_size != 56:
            raise ValueError("invalid ELF program header size")
        for index in range(count):
            stream.seek(program_offset + index * entry_size)
            entry = struct.unpack("<IIQQQQQQ", stream.read(entry_size))
            if entry[0] != 3:  # PT_INTERP
                continue
            stream.seek(entry[2])  # p_offset
            payload = stream.read(entry[5])  # p_filesz
            if len(payload) != entry[5] or not payload.endswith(b"\0") or b"\0" in payload[:-1]:
                raise ValueError("invalid PT_INTERP string")
            return payload[:-1]
    return None


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
    output = root / "qualification" / "suite" / "results" / "runs" / args.run_id / "linux-linker-transport"
    if output.exists():
        parser.error(f"run already exists: {output}")
    if not compiler.is_file() or not config.is_file():
        parser.error("compiler and config must exist")
    if run([str(compiler), "-iTO"], root, 30).stdout.strip().lower() != "linux":
        parser.error("compiler target OS is not Linux")
    output.mkdir(parents=True)

    failures: list[str] = []
    report: dict[str, object] = {
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
    }

    library_name = "libmoon_linker_" + "s" * 112 + ".so"
    library_source = output / "long_soname_library.pas"
    library_source.write_text(
        "library long_soname_library;\n"
        "function LinkerValue: LongInt; cdecl; begin LinkerValue:=42; end;\n"
        "exports LinkerValue;\n"
        "begin end.\n",
        encoding="utf-8",
    )
    library_command = compile_command(
        compiler, config, library_source, output, f"-o{output / library_name}",
    )
    library_build = run(library_command, output)
    (output / "soname-library.log").write_text(
        library_build.stdout + library_build.stderr, encoding="utf-8",
    )
    soname_readelf = None
    client_build = None
    client_run = None
    if library_build.returncode == 0:
        soname_readelf = run(["readelf", "-d", str(output / library_name)], output)
        (output / "soname-readelf.log").write_text(
            soname_readelf.stdout + soname_readelf.stderr, encoding="utf-8",
        )
        if f"Library soname: [{library_name}]" not in soname_readelf.stdout:
            failures.append("long SONAME was not preserved")
        client_source = output / "long_soname_client.pas"
        client_source.write_text(
            "program long_soname_client;\n"
            f"function LinkerValue: LongInt; cdecl; external '{library_name}' name 'LinkerValue';\n"
            "begin If LinkerValue<>42 then Halt(1); WriteLn('SONAME_OK'); end.\n",
            encoding="utf-8",
        )
        client_command = compile_command(
            compiler, config, client_source, output, f"-Fl{output}",
        )
        client_build = run(client_command, output)
        (output / "soname-client.log").write_text(
            client_build.stdout + client_build.stderr, encoding="utf-8",
        )
        if client_build.returncode == 0:
            environment = os.environ.copy()
            environment["LD_LIBRARY_PATH"] = str(output)
            client_run = run(
                [str(output / "long_soname_client")], output, 30, environment,
            )
            (output / "soname-run.log").write_text(
                client_run.stdout + client_run.stderr, encoding="utf-8",
            )
            if client_run.returncode != 0 or client_run.stdout.strip() != "SONAME_OK":
                failures.append("program linked through long SONAME did not run")
        else:
            failures.append(f"long SONAME client compile exit {client_build.returncode}")
    else:
        failures.append(f"long SONAME library compile exit {library_build.returncode}")

    interpreter_dir = output / "interpreter"
    interpreter_dir.mkdir()
    desired_length = max(320, len(str(interpreter_dir)) + 80)
    interpreter = interpreter_dir / ("i" * (desired_length - len(str(interpreter_dir)) - 1))
    interpreter.symlink_to(find_interpreter())
    interpreter_source = output / "long_interpreter.pas"
    interpreter_source.write_text(
        "program long_interpreter; begin WriteLn('INTERPRETER_OK'); end.\n",
        encoding="utf-8",
    )
    # The x86-64 Linux target has no internal linker; -Xi falls back to -Xe.
    executable = output / "long_interpreter_external"
    interpreter_command = compile_command(
        compiler, config, interpreter_source, output,
        "-Xe", f"-FL{interpreter}", f"-o{executable}",
    )
    interpreter_build = run(interpreter_command, output)
    (output / "interpreter-external-compile.log").write_text(
        interpreter_build.stdout + interpreter_build.stderr, encoding="utf-8",
    )
    interpreter_readelf = None
    interpreter_run = None
    if interpreter_build.returncode == 0:
        interpreter_readelf = run(["readelf", "-l", str(executable)], output)
        (output / "interpreter-external-readelf.log").write_text(
            interpreter_readelf.stdout + interpreter_readelf.stderr, encoding="utf-8",
        )
        try:
            preserved = elf_interpreter(executable) == os.fsencode(interpreter)
        except (OSError, ValueError, struct.error) as error:
            failures.append(str(error))
            preserved = False
        if not preserved:
            failures.append("long PT_INTERP path was not preserved by external linker")
        else:
            interpreter_run = run([str(executable)], output, 30)
            (output / "interpreter-external-run.log").write_text(
                interpreter_run.stdout + interpreter_run.stderr, encoding="utf-8",
            )
            if interpreter_run.returncode != 0 or interpreter_run.stdout.strip() != "INTERPRETER_OK":
                failures.append("program with long PT_INTERP from external linker did not run")
    else:
        failures.append(f"long interpreter external compile exit {interpreter_build.returncode}")
    interpreter_results = {
        "external": {
            "compile_exit": interpreter_build.returncode,
            "readelf_exit": None if interpreter_readelf is None else interpreter_readelf.returncode,
            "run_exit": None if interpreter_run is None else interpreter_run.returncode,
        }
    }

    report.update({
        "soname_length": len(library_name),
        "soname_library_compile_exit": library_build.returncode,
        "soname_readelf_exit": None if soname_readelf is None else soname_readelf.returncode,
        "soname_client_compile_exit": None if client_build is None else client_build.returncode,
        "soname_run_exit": None if client_run is None else client_run.returncode,
        "interpreter_length": len(str(interpreter)),
        "interpreter_linkers": interpreter_results,
        "failures": failures,
    })
    (output / "manifest.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8",
    )
    if failures:
        print("LINUX_LINKER_TRANSPORT_FAIL: " + "; ".join(failures))
        return 1
    print(
        f"LINUX_LINKER_TRANSPORT_PASS soname={len(library_name)} "
        f"interpreter={len(str(interpreter))}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
