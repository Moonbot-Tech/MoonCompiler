#!/usr/bin/env python3
"""Black-box gate: product compiler configuration, project file, profile isolation.

Tests the installed toolchain from a third-party directory, verifying:
- Product compiler uses only its own config (poisoned configs in cwd/USERPROFILE ignored)
- Debug/Release profiles produce separate PPU dirs and correct binaries
- Project options file (.mooncompiler) with relative paths works from another cwd,
  and its path lines are searched in their order, as on the command line
- -Fu/**  recursive with duplicate units produces a warning
- -Fu/**  over the Indy and MoonORMot layouts takes every source directory
  (Lib/, lib/), skips only hidden directories and build output, keeps one
  order from the command line and the project file, follows directory links
  but not back into the tree, compares directory names as the file system
  does and looks for units only where the walk saw unit files; a PPU beside
  an unrelated source cannot replace the source of another directory
- Version macros are defined and usable
- Pinned-unit from project file is rejected (only command line can re-pin)
- Win64 internal linker preserves long and quoted object/output paths and the full map script
- Source paths survive command-line and response-file input, including directories beyond 255 bytes

Arguments:
  --toolchain PATH   Toolchain root (default: <repo>/toolchain)
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

ROOT = Path(__file__).resolve().parents[2]
PASS_PREFIX = "PRODUCT_CONFIG_GATE_PASS"


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def compiler_path(toolchain: Path) -> Path:
    if os.name == "nt":
        return toolchain / "bin" / "x86_64-win64" / "ppcx64.exe"
    return toolchain / "bin" / "ppcx64"


def run_compiler(
    compiler: Path,
    args: list[str],
    cwd: Path | None = None,
    env_override: dict[str, str] | None = None,
    expect_fail: bool = False,
) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    if env_override:
        env.update(env_override)
    result = subprocess.run(
        [str(compiler)] + args,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        encoding="utf-8",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if expect_fail and result.returncode == 0:
        fail(f"expected failure but succeeded: {' '.join(args)}\n{result.stdout}")
    if not expect_fail and result.returncode != 0:
        fail(f"compiler failed: {' '.join(args)}\n{result.stdout}")
    return result


def write_probe(path: Path) -> None:
    """Write a probe program that prints runtime configuration."""
    path.write_text(
        """\
program probe;
{$IFDEF FPC}
uses SysUtils;
begin
  WriteLn('SizeOf_Char=', SizeOf(Char));
  {$IFDEF UNICODE}WriteLn('UNICODE=1');{$ELSE}WriteLn('UNICODE=0');{$ENDIF}
  {$IFDEF DEBUG}WriteLn('DEBUG=1');{$ELSE}WriteLn('DEBUG=0');{$ENDIF}
  {$IFDEF RELEASE}WriteLn('RELEASE=1');{$ELSE}WriteLn('RELEASE=0');{$ENDIF}
  {$IFDEF POSIX}WriteLn('POSIX=1');{$ELSE}WriteLn('POSIX=0');{$ENDIF}
  {$IFOPT C+}WriteLn('ASSERTIONS=1');{$ELSE}WriteLn('ASSERTIONS=0');{$ENDIF}
  {$IF defined(MOONCOMPILER_FULLVERSION)}
    {$IF MOONCOMPILER_FULLVERSION >= 10000}
  WriteLn('MOONCOMPILER_FULLVERSION=10000');
    {$ELSE}
  WriteLn('MOONCOMPILER_FULLVERSION=LOW');
    {$IFEND}
  {$ELSE}
  WriteLn('MOONCOMPILER_FULLVERSION=UNDEFINED');
  {$ENDIF}
  {$IF defined(MOONCOMPILER_VERSION)}
  WriteLn('MOONCOMPILER_VERSION=defined');
  {$ENDIF}
end.
{$ELSE}
begin
end.
{$ENDIF}
""",
        encoding="utf-8",
    )


def run_probe(
    compiler: Path,
    source: Path,
    extra_args: list[str] | None = None,
    cwd: Path | None = None,
    env_override: dict[str, str] | None = None,
) -> dict[str, str]:
    """Compile and run the probe, returning key=value pairs."""
    args = [str(source)]
    if extra_args:
        args = extra_args + args
    result = run_compiler(compiler, args, cwd=cwd, env_override=env_override)

    exe = source.with_suffix(".exe" if os.name == "nt" else "")
    if not exe.is_file():
        fail(f"probe exe not found: {exe}")
    run = subprocess.run(
        [str(exe)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    if run.returncode != 0:
        fail(f"probe crashed: {run.stdout}")
    values: dict[str, str] = {}
    for line in run.stdout.strip().splitlines():
        if "=" in line:
            k, _, v = line.partition("=")
            values[k.strip()] = v.strip()
    return values


TARGET = "x86_64-win64" if os.name == "nt" else "x86_64-linux"

# What a program and a unit compiled in each profile report about themselves.
PROFILE_DEBUG = {
    "DEBUG": "1", "RELEASE": "0", "ASSERTIONS": "1",
    "UNIT_DEBUG": "1", "UNIT_RELEASE": "0", "UNIT_ASSERTIONS": "1",
}
PROFILE_RELEASE = {
    "DEBUG": "0", "RELEASE": "1", "ASSERTIONS": "0",
    "UNIT_DEBUG": "0", "UNIT_RELEASE": "1", "UNIT_ASSERTIONS": "0",
}


def write_profile_probe(directory: Path) -> Path:
    """profprog.dpr over profunit.pas: both report the profile they were
    compiled with, so a unit reused from the wrong profile directory shows."""
    (directory / "profunit.pas").write_text(
        """\
unit profunit;
interface
function UnitDebug: Integer;
function UnitRelease: Integer;
function UnitAssertions: Integer;
implementation
function UnitDebug: Integer;
begin
  {$IFDEF DEBUG}Result := 1;{$ELSE}Result := 0;{$ENDIF}
end;
function UnitRelease: Integer;
begin
  {$IFDEF RELEASE}Result := 1;{$ELSE}Result := 0;{$ENDIF}
end;
function UnitAssertions: Integer;
begin
  {$IFOPT C+}Result := 1;{$ELSE}Result := 0;{$ENDIF}
end;
end.
""",
        encoding="utf-8",
    )
    program = directory / "profprog.dpr"
    program.write_text(
        """\
program profprog;
uses profunit;
begin
  {$IFDEF DEBUG}WriteLn('DEBUG=1');{$ELSE}WriteLn('DEBUG=0');{$ENDIF}
  {$IFDEF RELEASE}WriteLn('RELEASE=1');{$ELSE}WriteLn('RELEASE=0');{$ENDIF}
  {$IFOPT C+}WriteLn('ASSERTIONS=1');{$ELSE}WriteLn('ASSERTIONS=0');{$ENDIF}
  WriteLn('UNIT_DEBUG=', UnitDebug);
  WriteLn('UNIT_RELEASE=', UnitRelease);
  WriteLn('UNIT_ASSERTIONS=', UnitAssertions);
end.
""",
        encoding="utf-8",
    )
    return program


def check_probe(values: dict[str, str], expected: dict[str, str], label: str) -> None:
    for k, v in expected.items():
        actual = values.get(k)
        if actual != v:
            fail(f"{label}: {k} expected {v!r}, got {actual!r}")


def write_unit(path: Path, name: str, interface: str, uses: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    uses_line = f"uses {uses};\n" if uses else ""
    path.write_text(
        f"unit {name};\ninterface\n{uses_line}{interface}\nimplementation\nend.\n",
        encoding="utf-8",
    )


def write_program(path: Path, uses: str, writeln: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"program {path.stem};\nuses {uses};\nbegin\n  WriteLn({writeln});\nend.\n",
        encoding="utf-8",
    )
    return path


def run_program(compiler: Path, program: Path, args: list[str], cwd: Path) -> tuple[str, str]:
    """Compile a program (a project file beside it is read by the compiler
    itself) and run it: the compiler's output and the program's output."""
    result = run_compiler(compiler, args + [str(program)], cwd=cwd)
    exe = program.with_suffix(".exe" if os.name == "nt" else "")
    run = subprocess.run(
        [str(exe)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    if run.returncode != 0:
        fail(f"{program.name} crashed: {run.stdout}")
    return result.stdout, run.stdout.strip()


def make_dir_link(link: Path, target: Path) -> None:
    if os.name == "nt":
        subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(link), str(target)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    else:
        os.symlink(str(target), str(link))


def remove_dir_link(link: Path) -> None:
    # the link only, never what it points to
    if os.name == "nt":
        os.rmdir(link)
    else:
        link.unlink()


# ---- -Fu<dir>/** over real tree layouts ----
# A directory of the tree is never skipped for its name.  Only hidden
# directories and build output (compiled units without their sources) stay
# out; the order - a directory before its subdirectories, siblings sorted - is
# the same from the command line and from the project file; a directory link
# is followed, but not back into its own tree.


def check_tree_indy(compiler: Path, root: Path, cwd: Path) -> str:
    # upstream Indy keeps every source under Lib/, and the project file of
    # doc/PROJECT_BUILD.md names it as -Fu../Indy/**
    indy = root / "Indy"
    write_unit(indy / "Lib" / "System" / "IdGlobal.pas", "IdGlobal",
               "const ID_GLOBAL = 'System';")
    write_unit(indy / "Lib" / "Core" / "IdTCPClient.pas", "IdTCPClient",
               "const ID_CLIENT = ID_GLOBAL + '+Core';", uses="IdGlobal")
    app = write_program(root / "app" / "app.dpr", "IdTCPClient", "'INDY=', ID_CLIENT")
    (app.parent / "app.mooncompiler").write_text("-Fu../Indy/**\n", encoding="utf-8")
    _, out = run_program(compiler, app, [], cwd)
    if out != "INDY=System+Core":
        fail(f"-Fu../Indy/** over Indy/Lib: expected INDY=System+Core, got {out!r}")
    return "-Fu../Indy/** finds Indy under Lib/ OK"


def check_tree_own_mormot(compiler: Path, root: Path, cwd: Path) -> str:
    # MoonORMot keeps mormot.lib.* in its top-level lib/: a project with its
    # own mORMot in its tree builds against all of it, never mixed with the
    # mormot next to the toolchain
    proj = root / "ownmormot"
    write_unit(proj / "vendor" / "mormot" / "core" / "mormot.core.base.pas",
               "mormot.core.base", "const PROJECT_CORE = 1;")
    write_unit(proj / "vendor" / "mormot" / "lib" / "mormot.lib.z.pas",
               "mormot.lib.z", "const PROJECT_LIBZ = PROJECT_CORE + 6;",
               uses="mormot.core.base")
    prog = write_program(proj / "own.dpr", "mormot.lib.z", "'LIBZ=', PROJECT_LIBZ")
    (proj / "own.mooncompiler").write_text("-Fu./**\n", encoding="utf-8")
    _, out = run_program(compiler, prog, [], cwd)
    if out != "LIBZ=7":
        fail(f"project's own vendor/mormot/lib: expected LIBZ=7, got {out!r}")
    return "project's own mORMot, lib/ included, OK"


def check_tree_build_output(compiler: Path, root: Path, cwd: Path) -> str:
    # the default unit directories live inside the tree that -Fu./** walks;
    # the unit's directory sorts after units/, so a Release build must not
    # find the Debug PPU there first
    proj = root / "outputs"
    proj.mkdir(parents=True)
    prog = write_profile_probe(proj)
    (proj / "vendor").mkdir()
    (proj / "profunit.pas").rename(proj / "vendor" / "profunit.pas")
    (proj / "profprog.mooncompiler").write_text("-Fu./**\n", encoding="utf-8")
    check_probe(run_probe(compiler, prog, cwd=cwd), PROFILE_DEBUG, "** tree debug")
    check_probe(run_probe(compiler, prog, extra_args=["-dRELEASE"], cwd=cwd),
                PROFILE_RELEASE, "** tree release after debug")
    check_probe(run_probe(compiler, prog, cwd=cwd), PROFILE_DEBUG, "** tree debug again")
    # a user's own unit directories, named like nothing in particular, and
    # the tree from the command line
    user = root / "useroutput"
    user.mkdir(parents=True)
    prog = write_profile_probe(user)
    (user / "src").mkdir()
    (user / "profunit.pas").rename(user / "src" / "profunit.pas")
    tree = f"-Fu{user}/**"
    check_probe(run_probe(compiler, prog, extra_args=[tree, f"-FU{user / 'out' / 'dbg'}"],
                          cwd=cwd), PROFILE_DEBUG, "** tree, -FUout/dbg")
    check_probe(run_probe(compiler, prog,
                          extra_args=[tree, f"-FU{user / 'out' / 'rel'}", "-dRELEASE"],
                          cwd=cwd), PROFILE_RELEASE, "** tree, -FUout/rel after out/dbg")
    return "build output directories under ** skipped by their content OK"


def check_tree_mixed_output(compiler: Path, root: Path, cwd: Path) -> str:
    proj = root / "mixed_output"
    output = proj / "bin"
    output.mkdir(parents=True)
    seed = write_program(root / "seed" / "seed.dpr", "dupunit", "V")
    seed_unit = seed.parent / "dupunit.pas"
    project_unit = proj / "src" / "dupunit.pas"
    write_unit(seed_unit, "dupunit", "const V = 'STALE';")
    write_unit(project_unit, "dupunit", "const V = 'SOURCE';")
    for source in (seed_unit, project_unit):
        os.utime(source, (1_700_000_000, 1_700_000_000))
    run_compiler(compiler, [f"-FU{output}", str(seed)], cwd=cwd)
    write_unit(output / "other.pas", "other", "")
    prog = write_program(proj / "app.dpr", "dupunit", "V")
    (proj / "app.mooncompiler").write_text("-Fu./**\n", encoding="utf-8")
    _, explicit = run_program(compiler, prog, [f"-Fu{output}"], cwd)
    if explicit != "STALE":
        fail(f"mixed output negative control: expected STALE, got {explicit!r}")
    for args in ([], ["-dRELEASE"]):
        _, value = run_program(compiler, prog, args, cwd)
        if value != "SOURCE":
            fail(f"** took a PPU beside an unrelated source: expected SOURCE, got {value!r}")
    return "mixed source/output directory cannot replace a source through ** OK"


def check_tree_order(compiler: Path, root: Path, cwd: Path) -> str:
    proj = root / "order"
    write_unit(proj / "a" / "dupunit.pas", "dupunit", "const V = 'a';")
    write_unit(proj / "b" / "dupunit.pas", "dupunit", "const V = 'b';")
    write_unit(proj / ".cache" / "dupunit.pas", "dupunit", "const V = 'hidden';")
    write_unit(proj / "src" / "nested.pas", "nested", "const N = 'src';")
    write_unit(proj / "src" / "old" / "nested.pas", "nested", "const N = 'src/old';")
    prog = write_program(proj / "ordprog.dpr", "dupunit, nested", "V, ' ', N")
    project_file = proj / "ordprog.mooncompiler"
    for label, args in (("project file", []), ("command line", [f"-Fu{proj}/**"])):
        if not args:
            project_file.write_text("-Fu./**\n", encoding="utf-8")
        elif project_file.exists():
            project_file.unlink()
        shutil.rmtree(proj / "units", ignore_errors=True)
        output, out = run_program(compiler, prog, args, cwd)
        if out != "a src":
            fail(f"-Fu/** from the {label}: expected 'a src' (a before b, a "
                 f"directory before its subdirectories), got {out!r}")
        if "Duplicate unit" not in output:
            fail(f"-Fu/** from the {label}: no duplicate-unit warning:\n{output}")
        if ".cache" in output:
            fail(f"-Fu/** from the {label} entered a hidden directory:\n{output}")
    return "one ** order from the project file and the command line OK"


def check_project_line_order(compiler: Path, root: Path, cwd: Path) -> str:
    # the project file is written as the command line is: its first -Fu line
    # is searched first, as on the command line
    proj = root / "lines"
    write_unit(proj / "a" / "dupunit.pas", "dupunit", "const V = 'a';")
    write_unit(proj / "b" / "dupunit.pas", "dupunit", "const V = 'b';")
    prog = write_program(proj / "lineprog.dpr", "dupunit", "V")
    project_file = proj / "lineprog.mooncompiler"
    for label, args in (("project file", []),
                        ("command line", [f"-Fu{proj / 'a'}", f"-Fu{proj / 'b'}"])):
        if args:
            project_file.unlink()
        else:
            project_file.write_text("-Fu./a\n-Fu./b\n", encoding="utf-8")
        shutil.rmtree(proj / "units", ignore_errors=True)
        _, out = run_program(compiler, prog, args, cwd)
        if out != "a":
            fail(f"-Fu a then -Fu b from the {label}: expected 'a', got {out!r}")
    return "project file lines searched in their order OK"


def check_tree_case(compiler: Path, root: Path, cwd: Path) -> str:
    # on Linux Src/ and src/ are two directories; a search path compares its
    # entries as the file system does, so neither is dropped as a duplicate
    # of the other, from the command line or from the project file
    if os.name == "nt":
        return "directory names differing in case: not on a case-insensitive file system"
    proj = root / "case"
    write_unit(proj / "Src" / "upperunit.pas", "upperunit", "const U = 'Src';")
    write_unit(proj / "src" / "lowerunit.pas", "lowerunit", "const L = 'src';")
    prog = write_program(proj / "caseprog.dpr", "upperunit, lowerunit", "U, ' ', L")
    project_file = proj / "caseprog.mooncompiler"
    for label, args in (("command line", [f"-Fu{proj}/**"]), ("project file", [])):
        if args:
            if project_file.exists():
                project_file.unlink()
        else:
            project_file.write_text("-Fu./**\n", encoding="utf-8")
        shutil.rmtree(proj / "units", ignore_errors=True)
        _, out = run_program(compiler, prog, args, cwd)
        if out != "Src src":
            fail(f"-Fu/** from the {label} over Src/ and src/: expected 'Src src', got {out!r}")
    return "Src/ and src/ both searched OK"


def check_tree_nounits(compiler: Path, root: Path, cwd: Path) -> str:
    # the walk remembers the directories where it saw no unit file: a unit is
    # not looked for there (-vt names every unit file tried), while every
    # other file still is - here an include file in an include-only directory
    proj = root / "nounits"
    for index in range(8):
        (proj / "data" / f"d{index}").mkdir(parents=True)
    (proj / "data" / "d0" / "notes.txt").write_text("notes\n", encoding="utf-8")
    (proj / "inc").mkdir()
    (proj / "inc" / "nudefs.inc").write_text("const NUDEFS = 'inc';\n", encoding="utf-8")
    write_unit(proj / "src" / "nuunit.pas", "nuunit", "{$I nudefs.inc}")
    prog = write_program(proj / "nuprog.dpr", "SysUtils, nuunit", "NUDEFS")
    (proj / "nuprog.mooncompiler").write_text("-Fu./**\n-Fi./**\n", encoding="utf-8")
    output, out = run_program(compiler, prog, ["-vt"], cwd)
    if out != "inc":
        fail(f"-Fi./** over an include-only directory: expected 'inc', got {out!r}")
    data = f"{os.sep}data{os.sep}"
    tried = [line for line in output.splitlines()
             if line.startswith("Unitsearch:") and data in line]
    if tried:
        fail("a unit was looked for in directories without unit files:\n" + "\n".join(tried[:5]))
    return "units not looked for where the walk saw none OK"


def check_tree_links(compiler: Path, root: Path, cwd: Path) -> str:
    proj = root / "links"
    external = root / "external-lib"
    write_unit(proj / "src" / "cycunit.pas", "cycunit", "const C = 'cycle';")
    write_unit(external / "extunit.pas", "extunit", "const E = 'linked';")
    loop = proj / "src" / "loop"
    vendor = proj / "vendor"
    make_dir_link(loop, proj)
    make_dir_link(vendor, external)
    try:
        prog = write_program(proj / "linkprog.dpr", "cycunit, extunit", "C, ' ', E")
        (proj / "linkprog.mooncompiler").write_text("-Fu./**\n", encoding="utf-8")
        output, out = run_program(compiler, prog, [], cwd)
    finally:
        remove_dir_link(loop)
        remove_dir_link(vendor)
    if out != "cycle linked":
        fail(f"-Fu./** with directory links: expected 'cycle linked', got {out!r}")
    if "Duplicate unit" in output:
        fail(f"-Fu./** walked a directory link back into its own tree:\n{output}")
    return "directory links followed, a link back into the tree is not OK"


def check_recursive_trees(compiler: Path, root: Path, cwd: Path, results: list[str]) -> None:
    for check in (check_tree_indy, check_tree_own_mormot, check_tree_build_output,
                  check_tree_mixed_output,
                  check_tree_order, check_tree_case, check_tree_links,
                  check_tree_nounits, check_project_line_order):
        results.append(check(compiler, root, cwd))


def check_internal_linker_paths(compiler: Path, root: Path, cwd: Path) -> str:
    if os.name != "nt":
        return "internal linker path boundary: Win64 only"
    root.mkdir()
    program = root / "link_script_boundary_probe.dpr"
    program.write_text(
        "program link_script_boundary_probe;\nuses SysUtils;\nbegin\n"
        "  if SizeOf(Char) <> 2 then Halt(1);\n"
        "  {$IFDEF RELEASE}WriteLn('LINK_SCRIPT_RELEASE_OK');\n"
        "  {$ELSE}WriteLn('LINK_SCRIPT_DEBUG_OK');{$ENDIF}\nend.\n",
        encoding="utf-8",
    )
    for profile, options in (("DEBUG", []), ("RELEASE", ["-dRELEASE"])):
        for length, suffix in ((244, ""), (245, ""), (245, " space"), (254, ""), (254, " space"), (244, "~alias")):
            case = root / f"{profile}-{length}{suffix}"
            # READOBJECT plus its space is 11 bytes: a 245-byte object path
            # crosses the former 255-byte command limit, below Win32 MAX_PATH.
            # A 254-byte object path puts the .exe and .map names at 256 bytes.
            padding = length - len(str(case / program.with_suffix(".o").name)) - 1
            if padding < 1:
                fail(f"temporary path is too long for the linker boundary probe: {case}")
            units = case / ("p" * padding)
            units.mkdir(parents=True)
            obj = units / program.with_suffix(".o").name
            assert len(str(obj)) == length
            run_compiler(compiler, [*options, "-B", "-Xm", f"-FU{units}", f"-FE{units}", str(program)], cwd=cwd)
            exe = units / program.with_suffix(".exe").name
            if not exe.is_file():
                fail(f"linker did not write the requested executable: {exe}")
            run = subprocess.run([str(exe)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if run.returncode != 0 or run.stdout.strip() != f"LINK_SCRIPT_{profile}_OK":
                fail(f"long linker path {profile}/{length}/{suffix!r}: {run.stdout}")
            path = f'"{obj}"' if " " in str(obj) else str(obj)
            statement = "READOBJECT " + path
            mapfile = units / program.with_suffix(".map").name
            commands = mapfile.read_text(encoding="utf-8").splitlines()
            # Shell-sensitive names, including CI's RUNNER~1, may be quoted
            # without spaces. Require the complete path in either valid form.
            if statement not in commands and f'READOBJECT "{obj}"' not in commands:
                fail(f"map lost the full linker command: {statement}")
    return "internal linker 244/245/254-byte object paths, 256-byte outputs, quoting and both profiles OK"


def check_long_utf8_names(compiler: Path, root: Path, cwd: Path) -> str:
    if os.name != "nt":
        return "long UTF-8 filename: Win64 only (Linux limits filename bytes to 255)"
    # Both leaves are valid Windows names; their byte keys share the first
    # 255 bytes. Lookup of the shorter leaf must not pick the longer entry.
    short = "\u044f" * 125 + "a.inc"
    long = short + "b"
    assert len(short.encode("utf-8")) == 255
    assert long.encode("utf-8")[:255] == short.encode("utf-8")
    for profile in ("DEBUG", "RELEASE"):
        for reverse in (False, True):
            directory = root / f"{profile}-{reverse}"
            directory.mkdir(parents=True)
            entries = [(short, "SHORT_VALUE", 117), (long, "LONG_VALUE", 218)]
            for name, symbol, value in reversed(entries) if reverse else entries:
                (directory / name).write_text(f"const {symbol} = {value};\n", encoding="utf-8")
            source = directory / ("\u044f" * 130 + ".dpr")
            source.write_text(
                "program unicodeleaf;\n{$CODEPAGE UTF8}\n{$WARNING UNICODE_LOCATION_PROBE}\n"
                f"{{$I {short}}}\n{{$I {long}}}\n"
                "begin\n  if (SHORT_VALUE <> 117) or (LONG_VALUE <> 218) then Halt(1);\n"
                "  WriteLn('UTF8_NAMES_OK');\nend.\n", encoding="utf-8")
            out = directory / "output"
            out.mkdir()
            executable = out / "unicodeleaf.exe"
            compiled = run_compiler(compiler, ["-B", *(["-dRELEASE"] if profile == "RELEASE" else []),
                                              f"-FU{out}", f"-o{executable}", str(source)], cwd=cwd)
            if f"{source.name}(3," not in compiled.stdout:
                fail(f"diagnostic lost the full UTF-8 source name: {compiled.stdout}")
            run = subprocess.run([str(executable)], capture_output=True, text=True)
            if run.returncode != 0 or run.stdout.strip() != "UTF8_NAMES_OK":
                fail(f"long UTF-8 names {profile}/{reverse}: {run.stdout} {run.stderr}")
            if profile == "DEBUG" and not reverse:
                gcc = run_compiler(compiler, ["-B", "-Cn", "-vr", f"-FU{out}", str(source)], cwd=cwd)
                if f"{source.name}:3:" not in gcc.stdout:
                    fail(f"GCC diagnostic lost the full UTF-8 source name: {gcc.stdout}")
    return "255/256-byte colliding UTF-8 include names and 264-byte source leaf, both profiles OK"


def check_host_text(compiler: Path, root: Path, cwd: Path) -> str:
    """Paths are host Unicode; source text and legacy options keep their encoding."""
    if os.name != "nt":
        return "Windows host Unicode/ANSI boundary: Win64 only"
    frontend = compiler.with_name("fpc.exe")
    root.mkdir(parents=True)
    include = root / "\u6f22\U0001f680 space"
    include.mkdir()
    (include / "value.inc").write_text("const V=117;\n", encoding="ascii")
    source = root / "\u6f22.dpr"
    source.write_text(
        "program hosttext;\n{$I value.inc}\n"
        "const F: UnicodeString={$I %FILE%}; E: UnicodeString={$I %MC_HOST_TEXT%};\n"
        "begin\n"
        "  if (V<>117) or (Ord(F[Length(F)-4])<>$6F22) or\n"
        "     (Length(E)<>3) or (Ord(E[1])<>$6F22) or\n"
        "     (Ord(E[2])<>$D83D) or (Ord(E[3])<>$DE80) then Halt(1);\n"
        "  WriteLn('HOST_TEXT_OK');\nend.\n", encoding="ascii")
    response = root / "options.rsp"
    response.write_text(f'-Fi{include}\n', encoding="utf-8-sig")
    env_config = root / "env.cfg"
    env_config.write_text('-Fi$MC_HOST_EMPTY$$MC_HOST_INCLUDE$\n', encoding="ascii")
    environment = {"MC_HOST_INCLUDE": str(include), "MC_HOST_TEXT": "\u6f22\U0001f680", "MC_HOST_EMPTY": "",
                   "MC_HOST_OPTIONS": f'"-Fi{include}"'}

    def check(executable: Path, profile: str, label: str, options: list[str], program: Path,
              expected: str = "HOST_TEXT_OK") -> None:
        output = root / f"{executable.stem}-{profile}-{label}.exe"
        run_compiler(executable, ["-B", *(["-dRELEASE"] if profile == "RELEASE" else []),
                                 f"-o{output}", *options, str(program)], cwd=cwd, env_override=environment)
        run = subprocess.run([str(output)], text=True, capture_output=True)
        if run.returncode != 0 or run.stdout.strip() != expected:
            fail(f"host text {profile}/{label}: {run.returncode}: {run.stdout} {run.stderr}")

    # Select a non-ASCII character representable by this host's ANSI code page.
    legacy_char = next((c for c in "\u044f\u00e9\u6f22" if c.encode("mbcs", errors="replace").decode("mbcs") == c), "A")
    legacy_include = root / legacy_char
    legacy_include.mkdir()
    (legacy_include / "value.inc").write_text("const V=117;\n", encoding="ascii")
    legacy_source = root / "legacy.dpr"
    legacy_source.write_text(
        f"{{$mode delphiunicode}} program legacy; {{$I {legacy_char}/value.inc}}\n"
        f"const S:UnicodeString='{legacy_char}';\n"
        f"begin if (V<>117) or (Ord(S[1])<>{ord(legacy_char)}) then Halt(1); WriteLn('LEGACY_OK'); end.\n",
        encoding="mbcs")
    legacy_response = root / "legacy.cfg"
    legacy_response.write_text(f'-Fi{legacy_include}\n', encoding="mbcs")
    # An ACP config must actually supply an include search path, independently of source encoding.
    plain_source = root / "plain.dpr"
    plain_source.write_text("program plain; {$I value.inc} begin if V<>117 then Halt(1); WriteLn('LEGACY_OK'); end.\n",
                            encoding="ascii")
    for executable in (compiler, frontend):
        for profile in ("DEBUG", "RELEASE"):
            for label, options in (("direct", [f"-Fi{include}"]), ("response", [f"@{response}"]),
                                   ("env-config", [f"@{env_config}"]), ("env-options", ["!MC_HOST_OPTIONS"])):
                check(executable, profile, label, options, source)
            project = source.with_suffix(".mooncompiler")
            project.write_text(f'-Fi{include}\n', encoding="utf-8")
            check(executable, profile, "project", [], source)
            project.unlink()
            check(executable, profile, "ansi-source", [], legacy_source, "LEGACY_OK")
            check(executable, profile, "ansi-options", [f"@{legacy_response}"], plain_source, "LEGACY_OK")
    return "Unicode host paths/env/macros, UTF-8 project/BOM response, ANSI source/config, frontend/backend and profiles OK"


def check_long_ppu_paths(compiler: Path, root: Path, cwd: Path) -> str:
    # A truncated name can either name a directory or silently overwrite a
    # sibling PPU. Check the files themselves, then load them without sources.
    for profile in ("DEBUG", "RELEASE"):
        for length in (254, 262):
            case = root / f"{profile}-{length}"
            sources = case / "src"
            sources.mkdir(parents=True)
            units = case / "units"
            padding = length - len(str(units)) - 1
            if padding < 1:
                fail(f"temporary path is too long for the PPU boundary probe: {case}")
            while padding > 180:
                units /= "p" * 179
                padding -= 180
            units /= "p" * padding
            units.mkdir(parents=True)
            assert len(str(units)) == length
            for name, value in (("firstppu", 117), ("secondppu", 218)):
                write_unit(sources / f"{name}.pas", name, f"const {name}_value = {value};")
            program = write_program(case / "app" / "ppupath.dpr", "firstppu, secondppu",
                                    "'PPU_PATH_OK=', firstppu_value + secondppu_value")
            options = [f"-FU{units}", f"-Fu{units}", *(["-dRELEASE"] if profile == "RELEASE" else [])]
            _, output = run_program(compiler, program, ["-B", f"-Fu{sources}", *options], cwd)
            if output != "PPU_PATH_OK=335":
                fail(f"long PPU path cold {profile}/{length}: {output}")
            snapshots = {}
            for name in ("firstppu", "secondppu"):
                ppu = units / f"{name}.ppu"
                if not ppu.is_file() or not (units / f"{name}.o").is_file():
                    fail(f"full PPU/object output is missing: {ppu}")
                snapshots[ppu] = (ppu.read_bytes(), ppu.stat().st_mtime_ns)
                (sources / f"{name}.pas").rename(sources / f"{name}.hidden")
            if snapshots[units / "firstppu.ppu"][0] == snapshots[units / "secondppu.ppu"][0]:
                fail("different units produced identical PPUs")
            _, output = run_program(compiler, program, options, cwd)
            if output != "PPU_PATH_OK=335":
                fail(f"long PPU path warm {profile}/{length}: {output}")
            for ppu, before in snapshots.items():
                if (ppu.read_bytes(), ppu.stat().st_mtime_ns) != before:
                    fail(f"warm compile changed the source-free PPU: {ppu}")
    return "long PPU paths preserve distinct units and reload without sources, both profiles OK"


def check_source_input_paths(compiler: Path, root: Path, cwd: Path) -> str:
    frontend = compiler.with_name("fpc.exe" if os.name == "nt" else "fpc")
    for profile in ("DEBUG", "RELEASE"):
        for length in (255, 256, 272):
            case = root / f"{profile}-{length}{' space' if length > 255 else ''}"
            case.mkdir(parents=True)
            directory = case
            padding = length - len(str(directory / "inputprobe.dpr")) - 1
            if padding < 1:
                fail(f"temporary path is too long for the source boundary probe: {case}")
            while padding > 180:
                directory /= "p" * 179
                directory.mkdir()
                padding -= 180
            directory /= "p" * padding
            directory.mkdir()
            source = directory / "inputprobe.dpr"
            assert len(str(source)) == length
            write_unit(directory / "dep" / "inputunit.pas", "inputunit", "{$I inputvalue.inc}")
            (directory / "dep" / "inputvalue.inc").write_text("const INPUT_VALUE = 117;\n", encoding="utf-8")
            write_unit(directory / "dep2" / "secondunit.pas", "secondunit", "{$I inputvalue.inc}")
            (directory / "dep2" / "inputvalue.inc").write_text("const SECOND_VALUE = 218;\n", encoding="utf-8")
            direct_include = directory / "absolutevalue.inc"
            direct_include.write_text("const DIRECT_INCLUDE_VALUE = 337;\n", encoding="utf-8")
            if length == 272:
                assert str(directory / "dep")[:255] == str(directory / "dep2")[:255]
            source.write_text(
                "program inputprobe;\nuses SysUtils, inputunit, secondunit;\n"
                f'{{$I "{direct_include}"}}\n'
                "{$IFNDEF FROM_INPUT_PROJECT}{$ERROR Missing project options}{$ENDIF}\n"
                "var f: file; typed: file of Byte; t: Text; b: Byte; n: AnsiString; line: String;\n"
                "begin\n  if (SizeOf(Char) <> 2) or (INPUT_VALUE <> 117) or (SECOND_VALUE <> 218) or\n"
                "           (DIRECT_INCLUDE_VALUE <> 337) then Halt(1);\n"
                "  n := AnsiString(ParamStr(1));\n"
                "  Assign(f, n);\n  Rewrite(f, 1);\n  b := 117;\n  BlockWrite(f, b, 1);\n  Close(f);\n"
                "  Assign(f, UnicodeString(n));\n"
                "  if GetFullName(f) <> UnicodeString(n) then Halt(2);\n"
                "  Reset(f, 1);\n  BlockRead(f, b, 1);\n  Close(f);\n  if b <> 117 then Halt(3);\n"
                "  Assign(typed, n);\n  Reset(typed);\n  Read(typed, b);\n  Close(typed);\n  if b <> 117 then Halt(4);\n"
                "  Assign(t, UnicodeString(n));\n  Rewrite(t);\n  WriteLn(t, 'path');\n  Close(t);\n"
                "  Assign(t, n);\n  Append(t);\n  WriteLn(t, 'full');\n  Close(t);\n"
                "  Assign(t, n);\n  Reset(t);\n  ReadLn(t, line);\n  if line <> 'path' then Halt(5);\n"
                "  ReadLn(t, line);\n  Close(t);\n  if line <> 'full' then Halt(6);\n"
                "  if not DeleteFile(n) or FileExists(n) then Halt(7);\n"
                "  {$IFDEF RELEASE}WriteLn('INPUT_RELEASE_OK');"
                "{$ELSE}WriteLn('INPUT_DEBUG_OK');{$ENDIF}\nend.\n", encoding="utf-8")
            project_options = "-Fu./dep\n-Fu./dep2\n-Fi./dep\n-dFROM_INPUT_PROJECT\n"
            if profile == "RELEASE":
                project_options += "-dRELEASE\n"
            source.with_suffix(".mooncompiler").write_text(project_options, encoding="utf-8")
            entries = [("backend", compiler), ("frontend", frontend), ("response", frontend)]
            if length == 272:
                entries.append(("default-output", frontend))
            for entry, executable in entries:
                target = case / entry
                target.mkdir()
                options = ["-B", f"-FU{target}", f"-FE{target}"] if entry != "default-output" else ["-B", "-Xm"]
                if entry == "response":
                    response = target / "input.cfg"
                    response.write_text(
                        f'-dFROM_INPUT_PROJECT\n-Fu"{directory / "dep"}"\n'
                        f'-Fu"{directory / "dep2"}"\n-Fi"{directory / "dep"}"\n', encoding="utf-8")
                    options += [f"@{response}"]
                options += [str(source)]
                run_compiler(executable, options, cwd=cwd)
                image = (directory if entry == "default-output" else target) / ("inputprobe.exe" if os.name == "nt" else "inputprobe")
                if entry == "default-output":
                    object_path = directory / "units" / TARGET / profile.lower() / "inputprobe.o"
                    for output in (object_path, source.with_suffix(".map"), image):
                        if not output.is_file():
                            fail(f"default output path was not preserved: {output}")
                    if os.name == "nt":
                        # CreateProcess cannot launch this long path; keep the compiler outputs and run identical bytes.
                        copied_image = target / image.name
                        shutil.copyfile(image, copied_image)
                        assert image.read_bytes() == copied_image.read_bytes()
                        image = copied_image
                run = subprocess.run([str(image), str(directory / "inputdata1.bin")],
                                     text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                if run.returncode != 0 or run.stdout.strip() != f"INPUT_{profile}_OK":
                    fail(f"source input {profile}/{length}/{entry}: {run.stdout}")
    names = check_long_utf8_names(compiler, root / "utf8-names", cwd)
    return ("255/256/272-byte source and binary/text IO paths, distinct project/include directories, "
            "frontend/backend/response/default outputs and both profiles OK; " + names)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--toolchain",
        type=Path,
        default=ROOT / "toolchain",
        help="Toolchain root directory",
    )
    args = parser.parse_args()

    toolchain = args.toolchain.resolve()
    compiler = compiler_path(toolchain)
    if not compiler.is_file():
        fail(f"compiler not found: {compiler}")

    mormot_dir = ROOT / "mormot"

    results: list[str] = []

    temporary_root = "\\\\?\\" + tempfile.gettempdir() if os.name == "nt" else None
    with tempfile.TemporaryDirectory(prefix="moon_pcg_", dir=temporary_root) as tmpdir:
        tmp = Path(tmpdir)

        # Create junction/symlink to toolchain and mormot
        moon_dir = tmp / "moon"
        moon_dir.mkdir()
        tc_link = moon_dir / "toolchain"
        mm_link = moon_dir / "mormot"

        if os.name == "nt":
            # Windows junction
            subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(tc_link), str(toolchain)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            if mormot_dir.exists():
                subprocess.run(
                    ["cmd", "/c", "mklink", "/J", str(mm_link), str(mormot_dir)],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
        else:
            os.symlink(str(toolchain), str(tc_link))
            if mormot_dir.exists():
                os.symlink(str(mormot_dir), str(mm_link))

        linked_compiler = compiler_path(tc_link)

        # Work directory (third-party, not in the clone)
        work = tmp / "work"
        work.mkdir()

        # Write probe source
        probe = work / "probe.dpr"
        write_probe(probe)

        # ---- 1. Basic compilation: debug, release, diagnostic ----
        debug_vals = run_probe(linked_compiler, probe, cwd=work)
        check_probe(debug_vals, {
            "SizeOf_Char": "2",
            "UNICODE": "1",
            "DEBUG": "1",
            "RELEASE": "0",
            "ASSERTIONS": "1",
        }, "debug")
        # Version macros
        fullver_str = debug_vals.get("MOONCOMPILER_FULLVERSION", "UNDEFINED")
        if fullver_str == "UNDEFINED":
            fail("MOONCOMPILER_FULLVERSION not defined")
        if fullver_str == "LOW":
            fail("MOONCOMPILER_FULLVERSION too low")
        results.append(f"debug OK (MOONCOMPILER_FULLVERSION={fullver_str})")

        release_vals = run_probe(
            linked_compiler, probe, extra_args=["-dRELEASE"], cwd=work
        )
        check_probe(release_vals, {
            "DEBUG": "0",
            "RELEASE": "1",
            "ASSERTIONS": "0",
        }, "release")
        results.append("release OK")

        diag_vals = run_probe(
            linked_compiler, probe,
            extra_args=["-dFPCX64MM_DIAGNOSTIC"], cwd=work,
        )
        check_probe(diag_vals, {
            "DEBUG": "1",
            "ASSERTIONS": "1",
        }, "diagnostic")
        results.append("diagnostic OK")

        # ---- 2. Poisoned config: cwd ----
        poison_cfg = work / "fpc.cfg"
        poison_cfg.write_text(
            "-Mfpc\n#WRITE POISONED_CONFIG_READ\n",
            encoding="utf-8",
        )

        poison_vals = run_probe(linked_compiler, probe, cwd=work)
        check_probe(poison_vals, {"SizeOf_Char": "2", "UNICODE": "1"}, "poison-cwd")

        # Check that POISONED_CONFIG_READ was NOT printed
        compile_result = run_compiler(
            linked_compiler, [str(probe)], cwd=work
        )
        if "POISONED_CONFIG_READ" in compile_result.stdout:
            fail("cwd poisoned config was read by product compiler")
        results.append("poison-cwd ignored OK")
        poison_cfg.unlink()

        # ---- 3. Poisoned config: fake USERPROFILE/HOME ----
        fake_home = tmp / "fakehome"
        fake_home.mkdir()
        if os.name == "nt":
            fake_cfg = fake_home / "fpc.cfg"
        else:
            fake_cfg = fake_home / ".fpc.cfg"
        fake_cfg.write_text(
            "-Mfpc\n#WRITE POISONED_HOME_READ\n",
            encoding="utf-8",
        )

        env_override = {}
        if os.name == "nt":
            env_override["USERPROFILE"] = str(fake_home)
        else:
            env_override["HOME"] = str(fake_home)

        home_result = run_compiler(
            linked_compiler, [str(probe)], cwd=work, env_override=env_override
        )
        if "POISONED_HOME_READ" in home_result.stdout:
            fail("home poisoned config was read by product compiler")
        results.append("poison-home ignored OK")

        # ---- 4. Debug and release without -B from same dir ----
        # The default unit directories separate the profiles: a unit compiled
        # for Debug must not be reused by a Release build and vice versa, and
        # the compiled unit itself (not only the program) carries the profile.
        for cleanup_glob in ["*.exe", "*.o", "*.ppu", "*.rsj"]:
            for f in work.glob(cleanup_glob):
                f.unlink()
        prof_prog = write_profile_probe(work)
        units_dir = work / "units" / TARGET

        debug_vals = run_probe(linked_compiler, prof_prog, cwd=work)
        check_probe(debug_vals, PROFILE_DEBUG, "profile-unit debug")
        release_vals = run_probe(
            linked_compiler, prof_prog, extra_args=["-dRELEASE"], cwd=work
        )
        check_probe(release_vals, PROFILE_RELEASE, "profile-unit release")
        again_vals = run_probe(linked_compiler, prof_prog, cwd=work)
        check_probe(again_vals, PROFILE_DEBUG, "profile-unit debug again (no -B)")
        for profile in ("debug", "release"):
            for suffix in (".ppu", ".o"):
                if not (units_dir / profile / f"profunit{suffix}").is_file():
                    fail(f"debug+release: units/{TARGET}/{profile}/profunit{suffix} is missing")
        if (units_dir / "debug" / "profunit.o").read_bytes() == \
                (units_dir / "release" / "profunit.o").read_bytes():
            fail("debug+release: the Debug and Release objects of profunit are identical")
        results.append("debug+release separate unit directories OK")

        # ---- 5. Project options file (.mooncompiler) ----
        proj_dir = tmp / "project"
        proj_dir.mkdir()
        extra_dir = proj_dir / "extra"
        extra_dir.mkdir()

        # Write a helper unit in extra/
        (extra_dir / "projhelper.pas").write_text(
            "unit projhelper;\ninterface\n"
            "const FROM_PROJECT_EXTRA = True;\n"
            "implementation\nend.\n",
            encoding="utf-8",
        )

        # Write a project that uses the helper
        proj_src = proj_dir / "projtest.dpr"
        proj_src.write_text(
            "program projtest;\n"
            "uses projhelper;\n"
            "{$IFDEF FROM_PROJECT_FILE}\n"
            "begin WriteLn('PROJECT_FILE_OK');\n"
            "{$ELSE}\n"
            "begin WriteLn('NO_PROJECT_FILE');\n"
            "{$ENDIF}\n"
            "end.\n",
            encoding="utf-8",
        )

        # Write .mooncompiler with relative path and a define
        proj_cfg = proj_dir / "projtest.mooncompiler"
        proj_cfg.write_text(
            "-Fu./extra\n-dFROM_PROJECT_FILE\n",
            encoding="utf-8",
        )

        # Compile from a DIFFERENT cwd
        other_cwd = tmp / "othercwd"
        other_cwd.mkdir()
        compile_r = run_compiler(
            linked_compiler, [str(proj_src)], cwd=other_cwd
        )
        proj_exe = proj_src.with_suffix(".exe" if os.name == "nt" else "")
        if not proj_exe.is_file():
            fail(f"project file test: exe not found at {proj_exe}")
        run_result = subprocess.run(
            [str(proj_exe)], text=True, stdout=subprocess.PIPE
        )
        if "PROJECT_FILE_OK" not in run_result.stdout:
            fail(f"project file test: expected PROJECT_FILE_OK, got: {run_result.stdout}")
        results.append("project-file OK")

        # ---- 5b. -dRELEASE in the project file selects the Release profile ----
        # The project file is read before the configuration's #IFDEF RELEASE
        # block is evaluated, so its define chooses the profile exactly as a
        # command-line define does: no DEBUG, no assertions, the release unit
        # directory, and the unit compiled with the same profile.  A
        # command-line -uRELEASE still wins over the project file.
        rel_dir = tmp / "relproject"
        rel_dir.mkdir()
        rel_prog = write_profile_probe(rel_dir)
        (rel_dir / "profprog.mooncompiler").write_text(
            "-dRELEASE\n", encoding="utf-8",
        )
        rel_vals = run_probe(linked_compiler, rel_prog, cwd=other_cwd)
        check_probe(rel_vals, PROFILE_RELEASE, "project-file -dRELEASE")
        rel_units = rel_dir / "units" / TARGET
        if not (rel_units / "release" / "profunit.ppu").is_file():
            fail("project-file -dRELEASE: profunit.ppu is not in the release unit directory")
        if (rel_units / "debug").exists():
            fail("project-file -dRELEASE: a debug unit directory was created")
        over_vals = run_probe(
            linked_compiler, rel_prog, extra_args=["-uRELEASE"], cwd=other_cwd
        )
        check_probe(over_vals, PROFILE_DEBUG, "project-file -dRELEASE overridden by -uRELEASE")
        if not (rel_units / "debug" / "profunit.ppu").is_file():
            fail("-uRELEASE over the project file: profunit.ppu is not in the debug unit directory")
        results.append("project-file RELEASE profile OK")

        # ---- 6. -Fu/**  with duplicate unit names -> warning ----
        dup_dir = tmp / "duptest"
        dup_dir.mkdir()
        sub1 = dup_dir / "sub1"
        sub1.mkdir()
        sub2 = dup_dir / "sub2"
        sub2.mkdir()

        (sub1 / "dupunit.pas").write_text(
            "unit dupunit;\ninterface\nconst V=1;\nimplementation\nend.\n",
            encoding="utf-8",
        )
        (sub2 / "dupunit.pas").write_text(
            "unit dupunit;\ninterface\nconst V=2;\nimplementation\nend.\n",
            encoding="utf-8",
        )

        dup_prog = dup_dir / "dupprog.dpr"
        dup_prog.write_text(
            "program dupprog;\nuses dupunit;\nbegin WriteLn(V); end.\n",
            encoding="utf-8",
        )

        dup_result = run_compiler(
            linked_compiler,
            [f"-Fu{dup_dir}/**", str(dup_prog)],
            cwd=work,
        )
        if "Duplicate unit" not in dup_result.stdout:
            fail(f"-Fu/** with two dupunit.pas: no duplicate-unit warning:\n{dup_result.stdout}")
        results.append("duplicate-unit warning OK")

        # ---- 6b. -Fu/** walks a tree of any size ----
        # The directory list used to stop silently at 4096 entries: a unit in
        # a later directory was simply not found.  A tree wider than that,
        # with the only unit in the directory that sorts last.
        wide_dir = tmp / "widetest"
        wide_dir.mkdir()
        for index in range(4300):
            (wide_dir / f"d{index:05d}").mkdir()
        (wide_dir / "zlast").mkdir()
        (wide_dir / "zlast" / "wideunit.pas").write_text(
            "unit wideunit;\ninterface\nconst WIDE_FOUND = 1;\nimplementation\nend.\n",
            encoding="utf-8",
        )
        wide_prog = wide_dir / "wideprog.dpr"
        wide_prog.write_text(
            "program wideprog;\nuses wideunit;\nbegin WriteLn('WIDE=', WIDE_FOUND); end.\n",
            encoding="utf-8",
        )
        wide_vals = run_probe(
            linked_compiler, wide_prog, extra_args=[f"-Fu{wide_dir}/**"], cwd=work
        )
        check_probe(wide_vals, {"WIDE": "1"}, "-Fu/** over 4301 directories")
        results.append("recursive search over 4301 directories OK")

        check_recursive_trees(linked_compiler, tmp / "trees", other_cwd, results)
        results.append(check_internal_linker_paths(linked_compiler, tmp / "linker", other_cwd))
        results.append(check_source_input_paths(linked_compiler, tmp / "input", other_cwd))
        results.append(check_long_ppu_paths(linked_compiler, tmp / "ppu", other_cwd))
        results.append(check_host_text(linked_compiler, tmp / "host-text", other_cwd))
        from static_linux_gate import check as check_static_linux
        results.append(check_static_linux(linked_compiler, tmp / "static", other_cwd))

        # ---- 7. Pinned-unit from response file is rejected ----
        pin_file = tmp / "pintest.cfg"
        pin_file.write_text(
            f"--pinned-unit=mormot.core.fpcx64mm={probe}\n",
            encoding="utf-8",
        )
        pin_result = run_compiler(
            linked_compiler,
            [f"@{pin_file}", str(probe)],
            cwd=work,
            expect_fail=True,
        )
        if "Illegal parameter" in pin_result.stdout or pin_result.returncode != 0:
            results.append("pinned-unit from response file rejected OK")
        else:
            fail("pinned-unit from response file was accepted")

    # ---- Report ----
    print(f"{PASS_PREFIX} ({len(results)} checks)")
    for r in results:
        print(f"  {r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
