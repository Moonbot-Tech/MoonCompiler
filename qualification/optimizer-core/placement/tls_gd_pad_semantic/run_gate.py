#!/usr/bin/env python3
"""Check the ELF TLSGD linker sequence at every reachable call phase."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path

PATTERN = re.compile(rb"\x66\x48\x8d\x3d.{4}\x66\x66\x48\xe8.{4}", re.DOTALL)
BYTE_LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)", re.I)
RELOC = re.compile(r"^\s*([0-9a-f]+):\s+(R_X86_64_(?:TLSGD|PLT32))\s+(.*)", re.I)


def invoke(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, capture_output=True, text=True, timeout=120)


def source(n: int) -> str:
    nops = "\n".join("  nop" for _ in range(n))
    return ("unit tls_gd_pad_semantic;\n{$mode delphi}\ninterface\n"
            "threadvar Value: LongInt;\nfunction ReadValue: LongInt;\n"
            "implementation\nfunction ReadValue: LongInt;\nbegin\n  asm\n"
            f"{nops}\n  end;\n  Result := Value;\nend;\nend.\n")


DRIVER = ("program tls_gd_pad_driver;\n{$mode delphi}\nuses tls_gd_pad_semantic;\n"
          "begin\n  Value := 41;\n  if ReadValue <> 41 then Halt(1);\n"
          "  WriteLn('TLS_GD_OK');\nend.\n")


def object_sequences(objdump: str, obj: Path) -> tuple[int, int, set[int]]:
    proc = invoke([objdump, "-d", "-r", str(obj)])
    if proc.returncode:
        raise RuntimeError(proc.stderr)
    if "FPC_THREADVAR_RELOCATE" in proc.stdout:
        raise RuntimeError(f"{obj} reads the threadvar through FPC_THREADVAR_RELOCATE: "
                           "the compiler is built without -dtls_threadvars (see README)")
    sections: dict[str, dict[int, int]] = {}
    relocs: dict[str, list[tuple[int, str, str]]] = {}
    section = ""
    for line in proc.stdout.splitlines():
        if line.startswith("Disassembly of section "):
            section = line.removeprefix("Disassembly of section ").rstrip(":")
            sections[section] = {}
            relocs[section] = []
        if not section:
            continue
        if match := BYTE_LINE.match(line):
            offset = int(match[1], 16)
            for i, byte in enumerate(bytes.fromhex(match[2])):
                sections[section][offset + i] = byte
        elif match := RELOC.match(line):
            relocs[section].append((int(match[1], 16), match[2].upper(), match[3]))

    total = intact = 0
    phases: set[int] = set()
    for name, entries in relocs.items():
        plt = {(offset, symbol) for offset, kind, symbol in entries if kind == "R_X86_64_PLT32"}
        data = sections[name]
        for offset, kind, _ in entries:
            if kind != "R_X86_64_TLSGD":
                continue
            total += 1
            start = offset - 4
            sequence = bytes(data.get(i, 0) for i in range(start, start + 16))
            if PATTERN.fullmatch(sequence) and any(
                call == offset + 8 and "__tls_get_addr" in symbol for call, symbol in plt
            ):
                intact += 1
                phases.add((start + 11) % 32)
    return total, intact, phases


def require_tls_rtl(objdump: str, rtl: Path) -> None:
    """A -dtls_threadvars compiler puts the RTL's threadvars into .tbss."""
    proc = invoke([objdump, "-h", str(rtl / "system.o")])
    if proc.returncode:
        raise RuntimeError(proc.stderr)
    if not re.search(r"^\s*\d+\s+\.tbss", proc.stdout, re.MULTILINE):
        raise RuntimeError(f"{rtl / 'system.o'} has no .tbss section: the RTL is not built by a "
                           "-dtls_threadvars compiler, a TLS program cannot link against it (see README)")


def compile_one(compiler: Path, rtl: Path, work: Path, n: int, link: bool) -> subprocess.CompletedProcess[str]:
    src = work / ("tls_gd_pad_driver.pas" if link else "tls_gd_pad_semantic.pas")
    src.write_text(DRIVER if link else source(n), encoding="ascii")
    args = [str(compiler), "-n", "-Tlinux", "-Px86_64", "-Mdelphi", "-O3", "-OoCODEALIGN",
            "-Cg", "-CVGLOBAL-DYNAMIC", "-dMOONCOMPILER_VANILLA_RUNTIME",
            f"-Fu{rtl}", f"-Fu{work}", f"-FE{work}", f"-FU{work}"]
    if not link:
        args.append("-Cn")
    return invoke(args + [str(src)])


def check(compiler: Path, rtl: Path, objdump: str, root: Path, link: bool) -> tuple[list[int], set[int]]:
    broken: list[int] = []
    phases: set[int] = set()
    for n in range(32):
        work = root / f"n{n:02d}"
        work.mkdir(parents=True)
        proc = compile_one(compiler, rtl, work, n, False)
        if proc.returncode:
            raise RuntimeError(f"N={n} object compile failed:\n{proc.stdout}{proc.stderr}")
        obj = work / "tls_gd_pad_semantic.o"
        total, intact, found = object_sequences(objdump, obj)
        if total < 1:
            raise RuntimeError(f"N={n}: expected a TLSGD read relocation, got {total}")
        if intact != total:
            broken.append(n)
        phases.update(found)
        if link and intact == total:
            proc = compile_one(compiler, rtl, work, n, True)
            if proc.returncode:
                raise RuntimeError(f"N={n} link failed:\n{proc.stdout}{proc.stderr}")
            run = invoke([str(work / "tls_gd_pad_driver")])
            if run.returncode or run.stdout.strip() != "TLS_GD_OK":
                raise RuntimeError(f"N={n} runtime failed: {run.returncode} {run.stdout}{run.stderr}")
    return broken, phases


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--rtl", type=Path, required=True)
    parser.add_argument("--objdump", default="objdump")
    parser.add_argument("--old-compiler", type=Path)
    parser.add_argument("--old-rtl", type=Path)
    parser.add_argument("--object-only", action="store_true")
    args = parser.parse_args()
    if os.name == "nt" and not args.object_only:
        parser.error("use --object-only on Windows")
    if not args.object_only:
        require_tls_rtl(args.objdump, args.rtl)
        if args.old_compiler and args.old_rtl:
            require_tls_rtl(args.objdump, args.old_rtl)
    with tempfile.TemporaryDirectory(prefix="tls_gd_pad_") as temp:
        root = Path(temp)
        broken, phases = check(args.compiler, args.rtl, args.objdump, root / "new", not args.object_only)
        if broken:
            raise RuntimeError(f"new compiler split TLSGD at N={broken}")
        if len(phases) != 32:
            raise RuntimeError(f"NOP sweep reached only {len(phases)} of 32 call phases: {sorted(phases)}")
        print(f"new: all 32 objects intact; call phases {sorted(phases)}")
        if args.old_compiler:
            old, _ = check(args.old_compiler, args.old_rtl or args.rtl, args.objdump, root / "old", False)
            if not old:
                raise RuntimeError("old compiler produced no split TLSGD sequence")
            print(f"old: split TLSGD at N={old}")
            if not args.object_only:
                n = old[0]
                proc = compile_one(args.old_compiler, args.old_rtl or args.rtl, root / "old" / f"n{n:02d}", n, True)
                if proc.returncode == 0 or "TLS transition" not in (proc.stdout + proc.stderr):
                    raise RuntimeError(f"old N={n}: expected TLS transition link failure:\n{proc.stdout}{proc.stderr}")
                print(f"old N={n}: linker rejected split TLSGD")
    print("TLS_GD_PAD_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
