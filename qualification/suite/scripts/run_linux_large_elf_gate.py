#!/usr/bin/env python3
"""Cross ELF's reserved 16-bit section-index range with live symbols."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path


ROUTINE_COUNT = 65300
SHN_LORESERVE = 0xFF00
SHN_XINDEX = 0xFFFF
SHT_SYMTAB_SHNDX = 18


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


def elf_section_facts(path: Path) -> tuple[int, int, bool]:
    with path.open("rb") as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:4] != b"\x7fELF":
            raise ValueError("compiler did not emit an ELF object")
        if header[4:6] != b"\x02\x01":
            raise ValueError("gate expects little-endian ELF64")
        section_offset = struct.unpack_from("<Q", header, 40)[0]
        section_entry_size = struct.unpack_from("<H", header, 58)[0]
        header_count = struct.unpack_from("<H", header, 60)[0]
        header_string_index = struct.unpack_from("<H", header, 62)[0]
        if section_entry_size != 64 or section_offset == 0:
            raise ValueError("invalid ELF section table")
        stream.seek(section_offset)
        section_zero = stream.read(section_entry_size)
        if len(section_zero) != section_entry_size:
            raise ValueError("truncated ELF section table")
        section_count = header_count or struct.unpack_from("<Q", section_zero, 32)[0]
        string_index = (
            struct.unpack_from("<I", section_zero, 40)[0]
            if header_string_index == SHN_XINDEX
            else header_string_index
        )
        has_symtab_shndx = False
        for index in range(1, section_count):
            stream.seek(section_offset + index * section_entry_size + 4)
            section_type = struct.unpack("<I", stream.read(4))[0]
            if section_type == SHT_SYMTAB_SHNDX:
                has_symtab_shndx = True
                break
    return section_count, string_index, has_symtab_shndx


def source_text() -> str:
    lines = [
        "program linux_large_elf;",
        "",
        "{$mode delphiunicode}{$H+}",
        "{$Q-}{$R-}{$INLINE OFF}",
        "",
        "var",
        "  Sink: Int64;",
        "",
    ]
    for index in range(ROUTINE_COUNT):
        delta = index % 7 + 1
        lines += [
            f"procedure Probe{index:05d};",
            "begin",
            f"  Inc(Sink, {delta});",
            "end;",
            "",
        ]
    lines += [
        "begin",
        "  Sink := 1;",
        "  If Sink <> 1 then",
        "    Halt(2);",
        "  WriteLn('LINUX_LARGE_ELF_PASS');",
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
              "runs" / args.run_id / "linux-large-elf")
    if result.exists():
        parser.error(f"run already exists: {result}")
    if not compiler.is_file() or not config.is_file():
        parser.error("compiler and config must exist")
    if run([str(compiler), "-iTP"], compiler.parent, 30).stdout.strip().lower() != "x86_64":
        parser.error("compiler target processor is not x86_64")
    if run([str(compiler), "-iTO"], compiler.parent, 30).stdout.strip().lower() != "linux":
        parser.error("compiler target OS is not Linux")

    result.mkdir(parents=True)
    source = result / "linux_large_elf.pp"
    source.write_text(source_text(), encoding="utf-8")
    command = [
        str(compiler), "-n", f"@{config}", "-B", "-O2", "-CX", "-XX",
        "-Px86_64", "-Tlinux", f"-FU{result}", f"-FE{result}", str(source),
    ]
    compiled = run(command, result, 1200)
    (result / "compile.log").write_text(
        compiled.stdout + compiled.stderr, encoding="utf-8"
    )
    failures: list[str] = []
    if compiled.returncode != 0:
        failures.append(f"compile exit {compiled.returncode}")
    executable = result / "linux_large_elf"
    object_file = result / "linux_large_elf.o"
    section_count = None
    string_index = None
    has_symtab_shndx = None
    runtime = None
    if not failures:
        try:
            section_count, string_index, has_symtab_shndx = elf_section_facts(object_file)
        except (OSError, ValueError, struct.error) as error:
            failures.append(str(error))
        if section_count is not None and section_count < SHN_LORESERVE:
            failures.append(f"object has only {section_count} sections")
        if has_symtab_shndx is False:
            failures.append("object has no SHT_SYMTAB_SHNDX section")
    if not failures:
        runtime = run([str(executable)], result, 60)
        (result / "run.log").write_text(
            runtime.stdout + runtime.stderr, encoding="utf-8"
        )
        if runtime.returncode != 0 or runtime.stdout.strip() != "LINUX_LARGE_ELF_PASS":
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
        "section_string_index": string_index,
        "has_symtab_shndx": has_symtab_shndx,
        "source_sha256": sha256(source),
        "compile_exit": compiled.returncode,
        "run_exit": None if runtime is None else runtime.returncode,
        "failures": failures,
    }
    (result / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    if failures:
        print("LINUX_LARGE_ELF_FAIL: " + "; ".join(failures))
        return 1
    print(
        f"LINUX_LARGE_ELF_PASS routines={ROUTINE_COUNT} "
        f"sections={section_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
