#!/usr/bin/env python3
"""RTL profile contract: the installed RTL objects were built with the declared profile.

The product Unicode RTL and the application-facing packages are compiled
with one profile, declared in scripts/rtl-profile.txt and put in front of
the ABI defines by both build drivers.  A command line is not evidence that
the installed units carry it (the stand of 2026-09-14 found the product RTL
at -O2 under applications built at -O3, and nothing had said so), so this
gate proves it from the objects:

1. the driver records the exact OPT string of the RTL and package compiles
   in <toolchain>/profile.txt (rtl_packages_opt=OPT=...); the recorded
   options must start with the declared profile (unless --no-declared: a
   stand variant records its own profile and only the second check applies);
   next to it the driver records whether the code placement draft of the
   internal assembler was on for those compiles (placement_draft=0 or 1: the
   draft is switched by the environment, MOONCOMPILER_PLACEMENT=1, not by an
   option), and the witnesses below are compiled in that mode whatever the
   environment of the gate's caller says;
2. witness units are rebuilt with the recorded options and the exact
   command line the RTL make uses (`make -n -B` prints it; the unit
   directory is a copy of the installed RTL units so that nothing else is
   recompiled), from the same source tree and working directory, and every
   object the witness compile produces must equal the installed object byte
   for byte.  A different optimisation level, define or debug format changes
   the code or the DWARF and fails here; the compiler's output is
   deterministic for the same input (checked: types, sysutils, math twice).
   One thing is not an input of the profile: a type of another unit is a
   local DWARF copy when that unit was compiled in the same compiler run and
   an external DBG_ reference when it was loaded from its PPU, so the debug
   info depends on what the make had already compiled when the unit's turn
   came (Linux math.o: Types is compiled on the way, 55 bytes of .debug_info
   and one undefined DBG_ symbol).  An object that differs is therefore
   compared once more without its debug info (binutils objdump): the contents
   and the relocation records of every non-debug section and the symbols
   outside the debug sections must be the same, and both objects must carry
   .debug_info of the same DWARF version.
3. `Generics.Hashes` is rebuilt directly against the installed RTL/package
   set with the same recorded profile. Its non-debug sections, relocations
   and symbols must equal the installed package object. The profile record's
   compiler, RTL witness and package witness hashes are mandatory.

The witnesses are the units of types.pp, sysutils.pp and math.pp, plus
classes.pp where the RTL make compiles it on its own (Linux; on Win64 it
is part of buildrtl.pp, whose bundle compile cannot be repeated into a
unit copy - the compiler wants to recompile System from there); a witness
the RTL make of the host does not compile is skipped.

Usage:
    python3 rtl_profile_gate.py                    # toolchain
    python3 rtl_profile_gate.py --toolchain DIR [--no-declared]
    python3 rtl_profile_gate.py --make PATH        # GNU make (default: MOONBOT_MAKE,
                                                   # next to MOONBOT_BOOTSTRAP_FPC, PATH)
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
DECLARED = ROOT / "scripts" / "rtl-profile.txt"
WITNESSES = ("types", "sysutils", "math", "classes")
if os.name == "nt":
    OS_DIR = "win64"
    TARGET = "x86_64-win64"
    MAKE_TARGET = ["CPU_TARGET=x86_64", "OS_TARGET=win64"]
    # what packages/Makefile adds to every package compile of the target
    PACKAGE_TARGET_OPTIONS: list[str] = []
else:
    OS_DIR = "linux"
    TARGET = "x86_64-linux"
    MAKE_TARGET = []
    # packages/Makefile compiles every package of x86_64 on Linux (and the BSDs,
    # Solaris) position independent: `override FPCOPT+=-Cg`.  PIC code reaches
    # the globals of generics.hashes through the GOT, so a witness built without
    # it is a different object, not a different profile.
    PACKAGE_TARGET_OPTIONS = ["-Cg"]


class GateError(Exception):
    pass


def declared_profile(path: Path) -> list[str]:
    options: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            options += line.split()
    if not options:
        raise GateError(f"{path} declares no option")
    return options


def read_record(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise GateError(f"the toolchain carries no profile record: {path}")
    record: dict[str, str] = {}
    key = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            record[key.strip()] = value.strip()
            key = key.strip()
        elif key and not record[key] and line.strip():
            # the Win64 stand script writes some values on the next line
            record[key] = line.strip()
    if "rtl_packages_opt" not in record:
        raise GateError(f"{path} records no rtl_packages_opt line")
    return record


def toolchain_layout(toolchain: Path) -> tuple[Path, Path]:
    """(compiler, installed rtl units directory)."""
    if os.name == "nt":
        return (toolchain / "bin" / "x86_64-win64" / "ppcx64.exe",
                toolchain / "units" / TARGET / "rtl")
    versions = sorted(p for p in (toolchain / "lib" / "fpc").glob("[0-9]*") if p.is_dir())
    if len(versions) != 1:
        raise GateError(f"cannot identify one compiler version under {toolchain / 'lib' / 'fpc'}")
    return versions[0] / "ppcx64", versions[0] / "units" / TARGET / "rtl"


def toolchain_config(toolchain: Path) -> Path:
    if os.name == "nt":
        return toolchain / "bin" / "x86_64-win64" / "moon-base.cfg"
    return toolchain / "etc" / "moon-base.cfg"


def find_make(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    env = os.environ.get("MOONBOT_MAKE")
    if env:
        if not Path(env).is_file():
            raise GateError(f"MOONBOT_MAKE names no file: {env}")
        return Path(env)
    bootstrap = os.environ.get("MOONBOT_BOOTSTRAP_FPC")
    if bootstrap:
        candidate = Path(bootstrap).parent / ("make.exe" if os.name == "nt" else "make")
        if candidate.is_file():
            return candidate
    if os.name == "nt":
        local = os.environ.get("LOCALAPPDATA", "")
        candidate = Path(local) / "MoonCompiler" / "bootstrap" / "3.2.2" / "bin" / "i386-win32" / "make.exe"
        if local and candidate.is_file():
            return candidate
    found = shutil.which("make")
    # Delphi puts its own MAKE on PATH; it answers --version with its usage and exit code 0
    if found and subprocess.run([found, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, errors="replace", timeout=60).stdout.startswith("GNU Make"):
        return Path(found)
    raise GateError("GNU make was not found: pass --make, set MOONBOT_MAKE or MOONBOT_BOOTSTRAP_FPC")


def make_lines(make: Path, compiler: Path, opt: str) -> list[str]:
    env = dict(os.environ)
    env["PATH"] = str(make.parent) + os.pathsep + env.get("PATH", "")
    command = [str(make), "-n", "-B", "-C", str(ROOT / "rtl" / OS_DIR), "all",
               f"FPC={compiler}", f"OPT={opt}", *MAKE_TARGET]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            encoding="utf-8", errors="replace", env=env, timeout=600)
    if result.returncode != 0:
        raise GateError(f"make -n failed ({result.returncode}):\n{result.stdout[-3000:]}")
    lines = [line.strip() for line in result.stdout.splitlines() if "ppcx64" in line]
    if not lines:
        raise GateError(f"make -n printed no compiler line:\n{result.stdout[-3000:]}")
    return lines


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dwarf_version(path: Path) -> int | None:
    """DWARF version of the first unit of .debug_info in an ELF64 object; None when there is none
    (or the object is not ELF64: COFF objects have been byte-identical so far)."""
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        return None
    shoff = int.from_bytes(data[0x28:0x30], "little")
    shentsize = int.from_bytes(data[0x3A:0x3C], "little")
    shnum = int.from_bytes(data[0x3C:0x3E], "little")
    shstrndx = int.from_bytes(data[0x3E:0x40], "little")

    def header(index: int) -> tuple[int, int, int]:
        base = shoff + index * shentsize
        return (int.from_bytes(data[base:base + 4], "little"),
                int.from_bytes(data[base + 0x18:base + 0x20], "little"),
                int.from_bytes(data[base + 0x20:base + 0x28], "little"))

    _, names_at, _ = header(shstrndx)
    for index in range(shnum):
        name_at, offset, size = header(index)
        end = data.index(b"\0", names_at + name_at)
        if data[names_at + name_at:end] == b".debug_info" and size >= 6:
            return int.from_bytes(data[offset + 4:offset + 6], "little")
    return None


def debug_sections(path: Path, objdump: str) -> tuple[str, ...]:
    result = subprocess.run(
        [objdump, "-h", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        return ()
    return tuple(sorted({
        fields[1]
        for line in result.stdout.splitlines()
        for fields in [line.split()]
        if len(fields) >= 2 and fields[0].isdigit()
        and fields[1].startswith(".debug")
    }))


def without_debug(path: Path, objdump: str) -> tuple[list[str], list[str], list[str]] | str:
    """(section contents, relocation records, symbols) of an object outside its debug info."""
    def run(option: str) -> list[str] | None:
        result = subprocess.run([objdump, option, str(path)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace")
        return result.stdout.splitlines() if result.returncode == 0 else None

    def blocks(lines: list[str], head: re.Pattern[str]) -> list[str]:
        kept: list[str] = []
        keep = False
        for line in lines:
            match = head.match(line)
            if match:
                keep = not match.group(1).startswith(".debug")
            if keep:
                kept.append(line)
        return kept

    contents, relocations, table = run("-s"), run("-r"), run("-t")
    if contents is None or relocations is None or table is None:
        return f"objdump cannot read {path.name}"
    symbols = []
    for line in table:
        fields = line.split()
        if len(fields) < 4 or not re.fullmatch(r"[0-9a-f]{8,16}", fields[0]):
            continue
        name = fields[-1]
        section = fields[-3] if len(fields) >= 5 else ""
        if section.startswith(".debug") or name.startswith(("DBG_", "DBGREF_", "DBG2_")):
            continue
        symbols.append(" ".join(fields[1:]) if section != "*UND*" else f"UND {name}")
    return (blocks(contents, re.compile(r"Contents of section (\S+):")),
            blocks(relocations, re.compile(r"RELOCATION RECORDS FOR \[(\S+)\]:")),
            sorted(symbols))


def same_apart_from_debug(produced: Path, installed: Path, make: Path, work: Path) -> str | None:
    """None when the two objects are the same outside their debug info and both carry debug info
    of the same DWARF version; otherwise the reason."""
    objdump = shutil.which("objdump") or shutil.which("objdump", path=str(make.parent))
    if not objdump:
        return "binutils objdump was not found for the comparison without debug info"
    sides = [without_debug(produced, objdump), without_debug(installed, objdump)]
    for side in sides:
        if isinstance(side, str):
            return side
    for index, what in enumerate(("section contents", "relocation records", "symbols")):
        if sides[0][index] != sides[1][index]:
            return f"{what} outside the debug info differ"
    versions = (dwarf_version(produced), dwarf_version(installed))
    if versions[0] != versions[1]:
        return f"debug info differs in kind (DWARF version rebuilt {versions[0]}, installed {versions[1]})"
    if versions[0] is None:
        sections = (debug_sections(produced, objdump), debug_sections(installed, objdump))
        if not sections[0] or sections[0] != sections[1]:
            return (
                "debug info differs in kind "
                f"(rebuilt sections {sections[0]}, installed {sections[1]})"
            )
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--toolchain", type=Path, default=ROOT / "toolchain")
    parser.add_argument("--declared", type=Path, default=DECLARED,
                        help="the declared profile file (scripts/rtl-profile.txt)")
    parser.add_argument("--no-declared", action="store_true",
                        help="a stand variant: check only that the recorded profile built the objects")
    parser.add_argument("--make", type=Path, help="GNU make")
    parser.add_argument("--witness", default=",".join(WITNESSES),
                        help="comma-separated unit names rebuilt as witnesses")
    args = parser.parse_args()

    started = time.time()
    try:
        toolchain = args.toolchain.resolve()
        record = read_record(toolchain / "profile.txt")
        if record.get("placement_draft") not in ("0", "1"):
            raise GateError("the RTL profile must record placement_draft=0 or 1")
        # Reproduce the compiler's effective switch, independently of the caller's environment.
        build_env = dict(os.environ, MOONCOMPILER_PLACEMENT=record["placement_draft"], MOONCOMPILER_NO_PLACEMENT="")
        recorded = record["rtl_packages_opt"]
        if not recorded.startswith("OPT="):
            raise GateError(f"rtl_packages_opt does not start with OPT=: {recorded}")
        opt = recorded[len("OPT="):].strip()
        declared = None
        if not args.no_declared:
            declared = declared_profile(args.declared)
            if opt.split()[:len(declared)] != declared:
                raise GateError(f"the recorded profile {opt!r} does not start with the declared "
                                f"{' '.join(declared)!r} ({args.declared})")

        compiler, units = toolchain_layout(toolchain)
        config = toolchain_config(toolchain)
        package_units = units.parent / "rtl-generics"
        package_object = package_units / "generics.hashes.o"
        required_record = (
            "compiler_sha256",
            "sysutils_o_sha256",
            "generics_hashes_o_sha256",
        )
        missing_record = [name for name in required_record if name not in record]
        if missing_record:
            raise GateError(
                f"{toolchain / 'profile.txt'} lacks required fields: "
                + ", ".join(missing_record)
            )
        for required in (
            compiler,
            config,
            units / "system.ppu",
            units / "sysutils.o",
            package_object,
        ):
            if not required.is_file():
                raise GateError(f"the toolchain is incomplete: {required}")
        if sha256(compiler) != record["compiler_sha256"]:
            raise GateError("the compiler is not the one recorded by the RTL profile")
        if sha256(units / "sysutils.o") != record["sysutils_o_sha256"]:
            raise GateError("the installed sysutils.o is not the one the record was written for")
        if sha256(package_object) != record["generics_hashes_o_sha256"]:
            raise GateError(
                "the installed generics.hashes.o is not the package object "
                "recorded by the RTL profile"
            )

        make = find_make(args.make)
        lines = make_lines(make, compiler, opt)
        witnesses = [w for w in args.witness.split(",") if w]
        chosen: list[tuple[str, list[str]]] = []
        for witness in witnesses:
            pattern = re.compile(rf"[/ ]{re.escape(witness)}\.pp$")
            for line in lines:
                if pattern.search(line):
                    chosen.append((witness, line.split()[1:]))
                    break
        if not chosen:
            raise GateError(f"none of the witnesses {witnesses} is compiled by the RTL make")

        work = ROOT / ".qualification" / "build-driver" / f"rtl-profile-{os.getpid()}"
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir(parents=True)
        try:
            for source in units.iterdir():
                if source.suffix in (".ppu", ".o"):
                    shutil.copy2(source, work / source.name)
            compiled = []
            objects = []
            different = []
            debug_only = []
            for witness, arguments in chosen:
                arguments = [f"-FE{work}" if a == "-FE." else (f"-FU{work}" if a.startswith("-FU") else a)
                             for a in arguments]
                compiled_at = time.time()
                result = subprocess.run([str(compiler)] + arguments, cwd=ROOT / "rtl" / OS_DIR, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        encoding="utf-8", errors="replace", timeout=900, env=build_env)
                if result.returncode != 0:
                    raise GateError(f"the witness {witness} does not build with the recorded profile:\n"
                                    f"{result.stdout[-3000:]}")
                compiled.append(witness)
                # judge every object right behind its compile: a witness built with other options
                # changes its interface checksum and the next witness would only fail to build
                for produced in sorted(q for q in work.glob("*.o") if q.stat().st_mtime >= compiled_at - 1
                                       and q not in objects):
                    objects.append(produced)
                    installed = units / produced.name
                    if not installed.is_file():
                        different.append(f"{produced.name}: not installed")
                    elif produced.read_bytes() != installed.read_bytes():
                        reason = same_apart_from_debug(produced, installed, make, work)
                        if reason is None:
                            debug_only.append(produced.name)
                        else:
                            different.append(f"{produced.name}: {produced.stat().st_size} bytes rebuilt, "
                                             f"{installed.stat().st_size} installed ({reason})")
                if different:
                    break
            package_work = work / "package"
            package_work.mkdir()
            package_source = (
                ROOT / "packages" / "rtl-generics" / "src"
                / "generics.hashes.pas"
            )
            package_command = [
                str(compiler),
                "-n",
                f"@{config}",
                *shlex.split(opt, posix=os.name != "nt"),
                *PACKAGE_TARGET_OPTIONS,
                f"-Fu{package_units}",
                f"-FU{package_work}",
                f"-FE{package_work}",
                str(package_source),
            ]
            package_result = subprocess.run(
                package_command,
                cwd=package_source.parent,
                env=build_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                encoding="utf-8",
                errors="replace",
                timeout=900,
            )
            produced_package = package_work / "generics.hashes.o"
            if package_result.returncode != 0 or not produced_package.is_file():
                raise GateError(
                    "the package witness generics.hashes does not build with "
                    f"the recorded profile:\n{package_result.stdout[-3000:]}"
                )
            objects.append(produced_package)
            compiled.append("generics.hashes(package)")
            if produced_package.read_bytes() != package_object.read_bytes():
                reason = same_apart_from_debug(
                    produced_package, package_object, make, package_work
                )
                if reason is None:
                    debug_only.append("generics.hashes.o")
                else:
                    different.append(
                        "generics.hashes.o: "
                        f"{produced_package.stat().st_size} bytes rebuilt, "
                        f"{package_object.stat().st_size} installed ({reason})"
                    )
            if not objects:
                raise GateError("the witness compiles produced no object")
            if different:
                raise GateError("the installed objects were not built with the recorded profile:\n  "
                                + "\n  ".join(different))
        finally:
            shutil.rmtree(work, ignore_errors=True)
    except GateError as error:
        print(f"RTL_PROFILE_GATE_FAIL: {error}")
        return 1

    names = ",".join(p.name for p in objects)
    note = f" debug-order-only={','.join(debug_only)}" if debug_only else ""
    print(f"RTL_PROFILE_GATE_PASS toolchain={toolchain} profile={' '.join(declared) if declared else '(recorded)'} "
          f"opt={opt!r} witnesses={','.join(compiled)} objects={len(objects)} identical ({names}){note} "
          f"{time.time() - started:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
