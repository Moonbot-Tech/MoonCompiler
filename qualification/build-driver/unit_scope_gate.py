#!/usr/bin/env python3
"""Delphi's short unit names reach the units Delphi gives them.

Delphi 12.2 finds `uses ZLib` through the unit scope names of the project:
no unit is called ZLib, so System.ZLib is the one it gets.  This compiler
looks a name up as it is first and with the namespaces of -FN after, as Delphi
does - but the toolchain also installs FPC packages whose units have such
short names: the binding of an external zlib (packages/zlib, unit zlib:
zlib1.dll on Windows, libz on Linux) and paszlib's zip.  So `uses zLib` in
MoonBot's MoonTrades and the `zlib` of the websocket client's FPC branch took
the FPC binding instead of System.ZLib: another zlib than the one the product
ships, and on Windows a zlib1.dll the program needed next to it.

The rule: a unit the product ships under a namespace of -FN (System.X: the
Delphi surface of vcl-compat and runtime/*) is what `uses X` reaches, unless
the program has a unit X of its own - Delphi takes that one, by the name as
written, before it tries the unit scopes.  A unit named X on the toolchain's
unit path takes the name first, so it is a capture unless the configuration
aliases the name (-UaX=System.X); the compiler lets such an alias step over
only the toolchain's own units (fppu.programunitexists: a unit of the program
- beside it, in its output directory, in a unit path of its command line or
project options file - wins, found by the rules the search itself follows: a
** tree gives sources, never a PPU another build left in it).  An alias acts
on the uses clause of a source only: a precompiled unit that depends on the
FPC unit (libpng on zlib) keeps loading it by the name its PPU records.

The gate:
1. asks the compiler, with the product configuration (fpc.cfg and what it
   includes), for its unit path (-vt: "Using unit path"), reads -FN and -Ua
   from the configuration, and reports every capture - after checking itself
   on a tree with one capture and one aliased name, which must give exactly
   the capture;
2. builds unit_scope_probe.dpr, written as Delphi code is written
   (`uses zLib, Zip` with TZDecompressionStream and TZipFile, which exist in
   no other unit of these names), runs it, and requires that it carries one
   zlib, the one System.ZLib reports: it imports no zlib library (Windows:
   no DLL, Linux: no libz among the NEEDED of the image), and every zlib
   build compiled into it identifies itself with that version (zlib keeps
   " deflate 1.3.1 Copyright ..." in the image for that purpose).  System.Zip
   compresses through mORMot's mormot.lib.z, which took its own static zlib
   1.2.11 on Win64 and the system libz on Linux before the compiler told it
   to use System.ZLib (MOONCOMPILER_SYSTEM_ZLIB); the probe is the first
   program in which a second zlib would show;
3. builds unit_scope_own_probe.dpr, a program with units named ZLib and Zip
   of its own, four times - the units beside it, in a -Fu of the command
   line, in a -Fu of its project options file, in a subdirectory of the
   project's ** tree (-Fu./**) - and requires that it runs with its own
   units, not System.ZLib and System.Zip;
4. builds unit_scope_probe.dpr once more with -Fu./** in its project options
   file, in a tree that holds compiled units zlib.ppu and zip.ppu of another
   build and no source of them (one in a directory with an unrelated source,
   one in a directory of compiled units only), and requires that it still
   gets System.ZLib and System.Zip: the ** tree takes no PPU from those
   directories, so they are no unit of the program the aliases give way to.

Usage: python3 unit_scope_gate.py [--toolchain DIR] [--objdump PATH]
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from multiple_alias_gate import multiple_alias_scope
from winapi_scope_gate import alias_scope, winapi_scope
from json_scope_gate import json_scope
from pcre2_static_gate import static_regex

ROOT = Path(__file__).resolve().parents[2]
PROBE = Path(__file__).resolve().with_name("unit_scope_probe.dpr")
OWN_PROBE = Path(__file__).resolve().with_name("unit_scope_own_probe.dpr")
# the program's own units of the probe: the names of System.ZLib and System.Zip (the files in
# lower case, which FPC finds on a case-sensitive file system for any spelling in the uses)
OWN_UNITS = {
    f"{unit.lower()}.pas": (f"unit {unit};\ninterface\nfunction Project{unit}Marker: Integer;\nimplementation\n"
                    f"function Project{unit}Marker: Integer;\nbegin\n  Result := {value};\nend;\nend.\n")
    for unit, value in (("ZLib", 1950), ("Zip", 1951))
}
OWN_PLACES = {
    "program": "beside the program",
    "command-line": "in a -Fu of the command line",
    "project-file": "in a -Fu of the project options file",
    "tree": "in a subdirectory of the project's ** tree",
}
IS_WINDOWS = os.name == "nt"
UNIT_SUFFIXES = (".ppu", ".pp", ".pas", ".p")
# zlib's own mark of a build in the image (deflate.c, inftrees.c)
ZLIB_IDENTITY = re.compile(rb" (deflate|inflate) ([0-9]+(?:\.[0-9]+)+) Copyright ")


class GateError(Exception):
    pass


def toolchain_files(toolchain: Path) -> tuple[Path, Path, Path]:
    """(the fpc driver, the product configuration, $FPCBINDIR of that configuration)."""
    if IS_WINDOWS:
        binary = toolchain / "bin" / "x86_64-win64"
        return binary / "fpc.exe", binary / "fpc.cfg", binary
    return toolchain / "bin" / "fpc", toolchain / "etc" / "fpc.cfg", toolchain / "bin"


def option_lines(config: Path, bindir: Path, depth: int = 0) -> list[str]:
    """The option lines of a configuration and of what it #INCLUDEs; the lines
    of #IFDEF blocks are taken too (no unit option stands in one)."""
    if depth > 8:
        raise GateError(f"#INCLUDE nests too deep at {config}")
    lines: list[str] = []
    for raw in config.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if line.upper().startswith("#INCLUDE"):
            target = line.split(None, 1)[1].replace("$FPCBINDIR", str(bindir))
            lines += option_lines(Path(target), bindir, depth + 1)
        elif line.startswith("-"):
            lines.append(line)
    return lines


def scope(lines: list[str]) -> tuple[list[str], dict[str, str]]:
    """(the namespaces of -FN, lower case; the aliases of -Ua, old -> new, lower case)."""
    namespaces: list[str] = []
    aliases: dict[str, str] = {}
    for line in lines:
        if line.startswith("-FN"):
            namespaces += [name.lower() for name in line[3:].split(";") if name]
        elif line.startswith("-Ua") and "=" in line:
            old, new = line[3:].split("=", 1)
            aliases[old.lower()] = new.lower()
    return namespaces, aliases


def units_on(paths: list[Path]) -> dict[str, list[Path]]:
    """unit name (lower case) -> the files that give it, over the unit path."""
    units: dict[str, list[Path]] = {}
    for directory in paths:
        if not directory.is_dir():
            continue
        for item in directory.iterdir():
            if item.suffix.lower() in UNIT_SUFFIXES and item.is_file():
                units.setdefault(item.stem.lower(), []).append(item)
    return units


def captures(units: dict[str, list[Path]], namespaces: list[str],
             aliases: dict[str, str]) -> list[tuple[str, str]]:
    """(short name, the namespaced unit it takes from `uses <short name>`)."""
    found = []
    for name in sorted(units):
        for namespace in namespaces:
            if name.startswith(namespace + "."):
                short = name[len(namespace) + 1:]
                if short in units and aliases.get(short) != name:
                    found.append((short, name))
    return found


def self_check() -> None:
    fake = {name: [Path(name + ".ppu")] for name in ("foo", "system.foo", "bar", "system.bar", "system.baz")}
    got = captures(fake, ["system"], {"bar": "system.bar"})
    if got != [("foo", "system.foo")]:
        raise GateError(f"the capture check does not see what it must: {got}")


def compile_probe(fpc: Path, config: Path, work: Path) -> tuple[list[Path], Path]:
    """(the unit path the compiler reports, the probe executable)."""
    result = subprocess.run([str(fpc), "-n", f"@{config}", "-vt", f"-FE{work}", f"-FU{work}", str(PROBE)],
                            cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace", timeout=900)
    paths = [Path(match.group(1).strip()) for match in
             re.finditer(r"^Using unit path: (.+)$", result.stdout, re.MULTILINE)]
    executable = work / ("unit_scope_probe.exe" if IS_WINDOWS else "unit_scope_probe")
    if result.returncode != 0 or not executable.is_file():
        errors = "\n".join(line for line in result.stdout.splitlines() if "Error" in line or "Fatal" in line)
        raise GateError(f"the probe written as Delphi code does not build with the product "
                        f"configuration:\n{errors or result.stdout[-3000:]}", paths)
    return paths, executable


def carried_zlibs(executable: Path, output: str, objdump: str) -> tuple[list[str], str]:
    """(what shows a second zlib in the probe, the zlib builds it carries)."""
    reported = re.search(r"\bzlib=(\S+)", output)
    if not reported:
        return ["the probe does not report the version of System.ZLib's zlib"], ""
    version = reported.group(1)
    problems: list[str] = []
    found = sorted({(kind.decode(), number.decode())
                    for kind, number in ZLIB_IDENTITY.findall(executable.read_bytes())})
    others = [f"{kind} {number}" for kind, number in found if number != version]
    if others:
        problems.append(f"the probe carries a zlib build other than System.ZLib's {version}: {', '.join(others)}")
    dump = subprocess.run([objdump, "-p", str(executable)], capture_output=True, text=True, errors="replace")
    if dump.returncode:
        problems.append(f"cannot inspect the probe's imports: {dump.stderr[-500:]}")
    else:
        pattern = r"DLL Name: (\S+)" if IS_WINDOWS else r"^\s*NEEDED\s+(\S+)"
        imports = re.findall(pattern, dump.stdout, re.MULTILINE)
        external = [name for name in imports if "zlib" in name.lower() or "libz" in name.lower()]
        if external:
            problems.append(f"the probe imports {', '.join(external)}")
    return problems, ", ".join(f"{kind} {number}" for kind, number in found) or f"zlib {version}"


def own_units_win(fpc: Path, root: Path) -> list[str]:
    """What fails of: the program's own units ZLib and Zip, wherever it keeps them, are the ones it gets.
    Built as an application is built: `fpc probe.dpr`, the toolchain reading its own configuration first,
    then the project options file and the command line (-n @config would read the configuration last and
    put the toolchain's paths ahead of the project's)."""
    failures: list[str] = []
    for place, words in OWN_PLACES.items():
        work = root / f"own-{place}"
        units = {"program": work, "tree": work / "lib" / "compression"}.get(place, work / "units")
        units.mkdir(parents=True, exist_ok=True)
        (work / "out").mkdir()
        for name, text in OWN_UNITS.items():
            (units / name).write_text(text, encoding="ascii")
        probe = work / OWN_PROBE.name
        probe.write_bytes(OWN_PROBE.read_bytes())
        extra = [f"-Fu{units}"] if place == "command-line" else []
        if place == "project-file":
            probe.with_suffix(".mooncompiler").write_text("-Fuunits\n", encoding="ascii")
        if place == "tree":
            probe.with_suffix(".mooncompiler").write_text("-Fu./**\n", encoding="ascii")
        result = subprocess.run([str(fpc), *extra, f"-FE{work}", f"-FU{work / 'out'}", str(probe)],
                                cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                encoding="utf-8", errors="replace", timeout=900)
        executable = work / ("unit_scope_own_probe.exe" if IS_WINDOWS else "unit_scope_own_probe")
        if result.returncode != 0 or not executable.is_file():
            errors = "\n".join(line for line in result.stdout.splitlines() if "Error" in line or "Fatal" in line)
            failures.append(f"a program with its own units ZLib and Zip {words} does not build with them:\n"
                            f"{errors or result.stdout[-2000:]}")
            continue
        run = subprocess.run([str(executable)], cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, encoding="utf-8", errors="replace", timeout=300)
        if run.returncode != 0 or "UNIT_SCOPE_OWN_PASS zlib=1950 zip=1951" not in run.stdout:
            failures.append(f"a program with its own units ZLib and Zip {words} does not run with them "
                            f"(exit {run.returncode}):\n{run.stdout[-1000:]}")
    return failures


def stale_units_ignored(fpc: Path, root: Path) -> list[str]:
    """What fails of: PPUs named zlib and zip that another build left in the project's ** tree, with no source,
    are no unit of the program - `uses zLib, Zip` still reaches System.ZLib and System.Zip.  The ** tree gives
    sources only; were the aliases to give way to such a PPU, the name would then be searched for without it,
    and the toolchain's own zlib (FPC's binding) would take it."""
    work = root / "stale-tree"
    other = work / "stale-build"
    other.mkdir(parents=True)
    for name, text in OWN_UNITS.items():
        (other / name).write_text(text, encoding="ascii")
    mixed, compiled = work / "old", work / "bin"
    mixed.mkdir()
    compiled.mkdir()
    (mixed / "helpers.pas").write_text("unit helpers;\ninterface\nimplementation\nend.\n", encoding="ascii")
    for name, target in (("zlib.pas", mixed), ("zip.pas", compiled)):
        result = subprocess.run([str(fpc), f"-FU{target}", str(other / name)], cwd=other, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                timeout=900)
        if result.returncode != 0 or not (target / (Path(name).stem + ".ppu")).is_file():
            return [f"cannot compile the stale unit {name} of another build:\n{result.stdout[-2000:]}"]
    shutil.rmtree(other)
    (work / "out").mkdir()
    probe = work / PROBE.name
    probe.write_bytes(PROBE.read_bytes())
    probe.with_suffix(".mooncompiler").write_text("-Fu./**\n", encoding="ascii")
    result = subprocess.run([str(fpc), f"-FE{work}", f"-FU{work / 'out'}", str(probe)], cwd=work,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                            errors="replace", timeout=900)
    executable = work / ("unit_scope_probe.exe" if IS_WINDOWS else "unit_scope_probe")
    words = "with zlib.ppu and zip.ppu of another build in its ** tree"
    if result.returncode != 0 or not executable.is_file():
        errors = "\n".join(line for line in result.stdout.splitlines() if "Error" in line or "Fatal" in line)
        return [f"`uses zLib, Zip` {words} does not build against System.ZLib and System.Zip:\n"
                f"{errors or result.stdout[-2000:]}"]
    run = subprocess.run([str(executable)], cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", timeout=300)
    if run.returncode != 0 or "UNIT_SCOPE_PROBE_PASS" not in run.stdout:
        return [f"`uses zLib, Zip` {words} does not run (exit {run.returncode}):\n{run.stdout[-1000:]}"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--toolchain", type=Path, default=ROOT / "toolchain")
    parser.add_argument("--objdump", default=None,
                        help="objdump that reads the image (default: the toolchain's on Windows, objdump on Linux)")
    args = parser.parse_args()
    toolchain = args.toolchain.resolve()
    fpc, config, bindir = toolchain_files(toolchain)
    objdump = args.objdump or (str(toolchain / "bin" / "x86_64-win64" / "objdump.exe") if IS_WINDOWS else "objdump")
    failures: list[str] = []
    try:
        self_check()
        namespaces, aliases = scope(option_lines(config, bindir))
        if not namespaces:
            raise GateError(f"{config} names no namespace (-FN)")
        with tempfile.TemporaryDirectory(prefix="unit-scope-") as temporary:
            work = Path(temporary)
            paths: list[Path] = []
            try:
                paths, executable = compile_probe(fpc, config, work)
            except GateError as error:
                failures.append(str(error.args[0]))
                paths = error.args[1] if len(error.args) > 1 else []
                executable = None
            units = units_on(paths)
            if not units:
                raise GateError("the compiler reported no unit path")
            for short, target in captures(units, namespaces, aliases):
                where = ", ".join(str(item.relative_to(toolchain)) if item.is_relative_to(toolchain) else str(item)
                                  for item in units[short])
                failures.append(f"`uses {short}` takes {where}, not {target}: alias it (-Ua{short}={target}) "
                                f"or take the unit off the product path")
            if executable is not None:
                run = subprocess.run([str(executable)], cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                     text=True, encoding="utf-8", errors="replace", timeout=300)
                if run.returncode != 0 or "UNIT_SCOPE_PROBE_PASS" not in run.stdout:
                    failures.append(f"the probe does not run (exit {run.returncode}):\n{run.stdout[-2000:]}")
                problems, zlibs = carried_zlibs(executable, run.stdout, objdump)
                failures += problems
            failures += own_units_win(fpc, work)
            failures += stale_units_ignored(fpc, work)
            try:
                alias_scope(fpc, work)
                multiple_alias_scope([str(fpc)], work)
                json_scope(fpc, work)
                static_regex(fpc, objdump, work)
            except RuntimeError as error:
                failures.append(str(error))
            if IS_WINDOWS:
                try:
                    winapi_scope(fpc, work)
                except RuntimeError as error:
                    failures.append(str(error))
        system_units = sum(1 for name in units if any(name.startswith(n + ".") for n in namespaces))
    except GateError as error:
        failures.append(str(error.args[0]))
        system_units = 0
    if failures:
        print("UNIT SCOPE GATE: FAIL")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"UNIT SCOPE GATE: PASS ({len(units)} units on the product path, {system_units} under "
          f"{', '.join(namespaces)}, {len(aliases)} aliases; `uses zLib, Zip` builds and runs with one zlib "
          f"({zlibs}), no zlib library imported; a program's own ZLib and Zip win "
          f"{', '.join(OWN_PLACES.values())}; stale zlib.ppu and zip.ppu in a ** tree do not)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
