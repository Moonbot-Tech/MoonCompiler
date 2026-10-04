#!/usr/bin/env python3
"""Configuration contract: an installed fpc.cfg carries exactly the audited options.

Why this gate exists
--------------------
The product promise is "strictly our verified settings".  A toolchain's
fpc.cfg is read by every product build (`build.ps1 project.dpr` and `./build
project.dpr` pass `-n @fpc.cfg`), by Lazarus, and by whoever runs the
installed compiler by hand.  Before this gate the file was rendered from the
stock FPC template (utils/fpcmkcfg/fpc.cft), which carries conditional blocks
and switches that change what the compiler does without anybody asking:

    #IFDEF RELEASE  -O2 -Xs      optimisation and strip decided by a define
    #IFDEF DEBUG    -gl -Crtoi   run-time checks decided by a define
    #ELSE           -Xs          strip whenever DEBUG is not defined
    -a<x>                        assembler listing options: anything except
                                 -ap and -a- selects the external assembler
                                 in place of the product's internal one
    -A<name>                     explicit external assembler
    -Cp<cpu> / -Op<cpu>          processor target
    -CX -XX                      smart linking
    -XP<prefix>                  binutils prefix
    -Fu<user fppkg directory>    units from the user's home directory
    -FM<path>                    compile-time code page tables
    -l                           logo

The templates scripts/fpc.cfg.win64.template and scripts/fpc.cfg.linux.template
replace that: paths into the installed toolchain, the parser switches every
source has always been built with, and nothing else (the libgcc directory
every Linux program links against is found by the compiler itself at link
time, compiler/systems/t_linux.pas, so no configuration line names a host
path).  The drivers render them with `fpcmkcfg -t` and append the
profile lines (product: the Unicode ABI defines and the pinned memory manager;
IDE: the vanilla-runtime define).  This gate reads the rendered files back the
way the compiler does (options.pas, TOption.Interpret_file) and requires:

- no directive at all (#IFDEF, #IFNDEF, #ELSE, #ENDIF, #DEFINE, #UNDEF,
  #WRITE, #INCLUDE, #SECTION, #CFGDIR) - a block that fires only under some
  define is exactly the silent switch the template keeps out;
- the active option lines equal, in order, the template rendered for the
  toolchain plus the profile lines; every unit and tool path points into the
  toolchain, the pinned MM source is the one of this checkout; an unexpected
  line is reported together with the family it belongs to;
- the product compiler, given this configuration, assembles internally (no
  "Switching assembler" note, no external-assembler warning), `-ap` does not
  change that, while `-ao`, `-Aas` and `-al -Aas` deliberately select the
  external assembler and the compiler warns exactly once that the object is
  not the one its internal assembler writes: neither a configuration nor a
  command line that trades the product's assembler away can pass silently,
  and the exact distinction that once invalidated the Linux stand (`-ap` in
  the stock template taken for an external-assembler switch) stays locked
  down;
- the compiler itself defines NOPATCHRTL on x86-64: a guard program builds
  with the configuration stripped of its own -dNOPATCHRTL line, and fails
  once -uNOPATCHRTL is given (a stock mORMot compiled without the symbol
  copies its string routines over ours by stock-FPC lengths and crashes on
  the first string free; whoever takes this compiler and their own mORMot
  must be safe without knowing about the switch).

The toolchain build itself never reads any fpc.cfg: the drivers pass -n to
every compiler invocation, so a stray fpc.cfg in the user's profile,
PPC_CONFIG_PATH, ~/.fpc.cfg or /etc/fpc.cfg cannot leak into the compiler or
installed units.  Such files are listed as a note for whoever runs the bare
compiler without -n.

Usage:
    python3 config_contract_gate.py                 # toolchain
    python3 config_contract_gate.py --toolchain DIR
    python3 config_contract_gate.py --config FILE --profile product|ide
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = ROOT / "scripts" / (
    "fpc.cfg.win64.template" if os.name == "nt" else "fpc.cfg.linux.template")
PINNED_UNIT = "mormot.core.fpcx64mm"
PINNED_SOURCE_REPO = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"
TARGET = "x86_64-win64" if os.name == "nt" else "x86_64-linux"

# message 11072 (compiler/msg/errore.msg, option_w_external_assembler_no_placement)
EXTERNAL_WARNING = "Using the external assembler"
SWITCH_NOTE = "Switching assembler to default source writing assembler"

DIRECTIVES = {
    "IFDEF", "IFNDEF", "ELSE", "ENDIF", "DEFINE", "UNDEF", "WRITE",
    "INCLUDE", "SECTION", "CFGDIR",
}

PRODUCT_TAIL = [
    "-dMOONCOMPILER_UNICODE_DEFAULT",
    "-dMOONBOT_MM_PROFILE_REQUIRED",
    "-dFPCMM_BOOSTER",
    "-dFPCMM_MOONSHARD",
    "-dNOPATCHRTL",
    f"--pinned-unit={PINNED_UNIT}=",
]
IDE_TAIL = ["-dMOONCOMPILER_VANILLA_RUNTIME"]

# Families of options that must never appear in a configuration; used to
# name an unexpected line in the report.
FAMILIES = [
    (r"^-O", "optimisation"),
    (r"^-g", "debug information"),
    (r"^-C", "code generation, run-time checks or processor target"),
    (r"^-X", "linker or executable"),
    (r"^-k", "linker pass-through"),
    (r"^-ap$|^-a-$", "assembler pipe/reset (harmless, still not audited)"),
    (r"^-a", "assembler listing: selects the external assembler"),
    (r"^-A", "assembler selection"),
    (r"^-s", "skip assembling and linking: selects the external assembler"),
    (r"^-[du](RELEASE|DEBUG)$", "build-kind define"),
    (r"^-[du]", "define"),
    (r"^-M", "language mode"),
    (r"^-S", "syntax switch"),
    (r"^-[TP]", "target OS or CPU"),
    (r"^-W", "target-specific option"),
    (r"^-FM", "unicode tables path"),
    (r"^-F[ul]", "unit or library path"),
    (r"^-F", "search path"),
    (r"^-l$", "logo"),
    (r"^-v", "verbosity"),
    (r"^@", "included configuration file"),
    (r"^--pinned-unit=", "pinned unit"),
]


class GateError(Exception):
    pass


def family(line: str) -> str:
    for pattern, name in FAMILIES:
        if re.match(pattern, line):
            return name
    return "unknown option"


def remove_sep(text: str) -> str:
    return text.strip(", \t")


def read_config(path: Path) -> tuple[list[tuple[int, str]], list[str]]:
    """Active option lines (number, text) and the problems found, mirroring
    TOption.Interpret_file: ';' comments, '#' directives or comments, '-'/'@'
    options; anything else is an illegal parameter for the compiler."""
    options: list[tuple[int, str]] = []
    problems: list[str] = []
    text = path.read_text(encoding="utf-8", errors="replace")
    for number, raw in enumerate(text.splitlines(), 1):
        line = remove_sep(raw)
        if not line or line[0] == ";":
            continue
        if line[0] == "#":
            name = re.match(r"[A-Za-z0-9_-]*", line[1:]).group(0).upper()
            if name in DIRECTIVES:
                problems.append(f"line {number}: directive #{name} is not allowed: {raw.strip()}")
            continue
        if line[0] in "-@":
            options.append((number, line))
            continue
        problems.append(f"line {number}: not an option (the compiler reports an illegal parameter): {raw.strip()}")
    return options, problems


def template_lines() -> list[str]:
    options, problems = read_config(TEMPLATE)
    if problems:
        raise GateError("the template itself is not clean:\n  " + "\n  ".join(problems))
    lines = [line for _, line in options]
    if not lines or not lines[0].startswith("-Fu%basepath%/units/$fpctarget"):
        raise GateError("the template must start with the toolchain unit path")
    return lines


def same_path(a: str, b: Path) -> bool:
    try:
        return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))
    except OSError:
        return False


def expected_basepath(toolchain: Path | None, profile: str) -> Path | None:
    if toolchain is None:
        return None
    root = toolchain / "ide" if profile == "ide" else toolchain
    if os.name == "nt":
        return root
    versions = sorted(p for p in (root / "lib" / "fpc").glob("[0-9]*") if p.is_dir())
    if len(versions) != 1:
        raise GateError(f"cannot identify one compiler version under {root / 'lib' / 'fpc'}")
    return versions[0]


def check_config(path: Path, profile: str, toolchain: Path | None) -> tuple[Path, int]:
    if not path.is_file():
        raise GateError(f"configuration is missing: {path}")
    options, problems = read_config(path)
    lines = [line for _, line in options]
    if not lines:
        raise GateError(f"{path}: no option line at all")

    # Path rendering and runtime profile are independent: local stands may
    # render absolute product paths, while installed product paths relocate.
    uses_fpcbindir = "$FPCBINDIR" in lines[0]

    if uses_fpcbindir:
        # moon-base.cfg: verify expected lines as text, then the pinned-unit
        # path exists.  $FPCBINDIR is the directory of the running ppcx64:
        # on Win64 that is <toolchain>\bin\x86_64-win64, so ../../ is the
        # toolchain root; on Linux the driver keeps the real ppcx64 in
        # <toolchain>/bin and leaves a symlink in lib/fpc/<version> (the RTL
        # resolves /proc/self/exe, so $FPCBINDIR is bin/ either way): ../ is
        # the root and the units live under lib/fpc/<version>.
        if os.name == "nt":
            expected = [
                "-Fu$FPCBINDIR/../../units/$fpctarget",
                "-Fu$FPCBINDIR/../../units/$fpctarget/*",
                "-Fu$FPCBINDIR/../../units/$fpctarget/rtl",
                "-FD$FPCBINDIR",
                "-Sgic",
                "-viwn",
            ]
        else:
            version = expected_basepath(toolchain, profile)
            if version is None:
                raise GateError("--toolchain is required on Linux to name the units directory")
            units = f"-Fu$FPCBINDIR/../lib/fpc/{version.name}/units/$fpctarget"
            expected = [
                units,
                units + "/*",
                units + "/rtl",
                "-Sgic",
                "-viwn",
                # Delphi defines POSIX on Linux; the compiler itself defines only UNIX
                "-dPOSIX",
            ]
        expected += list(PRODUCT_TAIL if profile == "product" else IDE_TAIL)

        basepath = toolchain if toolchain else Path()
    else:
        # Absolute-path format from fpcmkcfg, also used by local stands.
        if profile == "product" and toolchain is not None:
            problems.append("the installed product configuration must use $FPCBINDIR-relative paths")
        match = re.match(r"^-Fu(.+)/units/\$fpctarget$", lines[0])
        if not match:
            problems.append(
                f"line {options[0][0]}: the first option must be the toolchain unit path, got: {lines[0]}")
            basepath = None
        else:
            basepath = Path(match.group(1))
            wanted = expected_basepath(toolchain, profile)
            if wanted is not None and not same_path(str(basepath), wanted):
                problems.append(f"basepath {basepath} is not the installed {profile} toolchain {wanted}")
            if not (basepath / "units" / TARGET / "rtl" / "system.ppu").is_file():
                problems.append(f"basepath {basepath} holds no installed RTL for {TARGET}")

        expected = [line.replace("%basepath%", str(basepath)) for line in template_lines()]
        expected += list(PRODUCT_TAIL if profile == "product" else IDE_TAIL)
        for number, actual in options:
            if actual.startswith(("-Fu", "-FD")) and basepath is not None:
                value = actual[3:]
                if not value.startswith(str(basepath)):
                    problems.append(f"line {number}: path leaves the toolchain: {actual}")
        basepath = basepath if basepath is not None else Path()

    if len(lines) != len(expected):
        problems.append(f"{len(lines)} option lines, expected {len(expected)}")
    for (number, actual), wanted in zip(options, expected):
        if wanted.endswith("="):
            if not actual.startswith(wanted):
                problems.append(f"line {number}: expected {wanted}<path>, got: {actual} ({family(actual)})")
                continue
            source = actual[len(wanted):]
            if "$FPCBINDIR" in source and toolchain is not None:
                fpcbindir = toolchain / "bin" / "x86_64-win64" if os.name == "nt" else toolchain / "bin"
                source = source.replace("$FPCBINDIR", str(fpcbindir))
            source = Path(os.path.normpath(source))
            if not source.is_file():
                problems.append(f"line {number}: the pinned MM source does not exist: {source}")
            elif PINNED_SOURCE_REPO.is_file() and source.read_bytes().replace(b"\r\n", b"\n") != \
                    PINNED_SOURCE_REPO.read_bytes().replace(b"\r\n", b"\n"):
                problems.append(f"line {number}: the pinned MM source differs from the repo copy")
            continue
        if actual != wanted:
            problems.append(f"line {number}: expected {wanted}, got: {actual} ({family(actual)})")
    for number, actual in options[len(expected):]:
        problems.append(f"line {number}: unexpected option {actual} ({family(actual)})")

    if problems:
        raise GateError(f"{path} violates the configuration contract:\n  " + "\n  ".join(problems))
    return basepath, len(lines)


def find_compiler(toolchain: Path) -> Path:
    if os.name == "nt":
        return toolchain / "bin" / "x86_64-win64" / "ppcx64.exe"
    return expected_basepath(toolchain, "product") / "ppcx64"


def run_compiler(compiler: Path, args: list[str], work: Path) -> tuple[int, str]:
    result = subprocess.run(
        [str(compiler)] + args, cwd=work, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, encoding="utf-8", errors="replace", timeout=300)
    return result.returncode, result.stdout


def probe_compiler(compiler: Path, config: Path) -> None:
    """The product compiler with this configuration keeps its internal
    assembler, keeps it under -ap, and says so exactly once when -ao, -Aas
    or -al -Aas trade it for an external one; NOPATCHRTL is built into the
    compiler."""
    if not compiler.is_file():
        raise GateError(f"compiler is missing: {compiler}")
    work = ROOT / ".qualification" / "build-driver" / f"config-contract-{os.getpid()}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    try:
        source = work / "config_probe.dpr"
        source.write_text(
            "program config_probe;\n"
            "var\n  i, s: Integer;\n"
            "begin\n  s := 0;\n"
            "  for i := 1 to ParamCount + 100 do\n    s := s + i;\n"
            "  If s = 0 then\n    Halt(1);\n"
            "end.\n",
            encoding="utf-8", newline="\n")
        common = ["-n", f"@{config}", "-O3", f"-FE{work}", f"-FU{work}"]

        def compile_probe(label: str, options: list[str], expect_external: bool,
                          expect_switch_note: bool) -> str:
            code, output = run_compiler(compiler, common + options + [str(source)], work)
            if code != 0:
                raise GateError(f"assembler probe {label} does not build:\n{output[-3000:]}")
            switched = SWITCH_NOTE in output
            warnings = [line for line in output.splitlines() if EXTERNAL_WARNING in line]
            if switched != expect_switch_note:
                raise GateError(f"assembler probe {label}: switch note={switched}, "
                                f"expected {expect_switch_note}:\n{output[-3000:]}")
            if len(warnings) != int(expect_external):
                raise GateError(f"assembler probe {label}: external-assembler warnings={len(warnings)}, "
                                f"expected {int(expect_external)}:\n{output[-3000:]}")
            return output

        compile_probe("default", [], False, False)
        compile_probe("-ap", ["-ap"], False, False)
        compile_probe("-ao", ["-ao"], True, True)
        compile_probe("-Aas", ["-Aas"], True, False)
        # the listing mode of the qualification gates
        compile_probe("-al -Aas", ["-al", "-Aas"], True, False)

        # NOPATCHRTL is a symbol the compiler itself defines on x86-64 (a
        # stock mORMot compiled without it copies its string routines over
        # ours by stock-FPC lengths and crashes on the first string free):
        # a program guarded by {$ifndef NOPATCHRTL}{$error}{$endif} must
        # build with the configuration stripped of its own -dNOPATCHRTL
        # line, and must not build once -uNOPATCHRTL is given explicitly
        # (the measurement switch has to keep working).
        guard = work / "nopatchrtl_probe.dpr"
        guard.write_text(
            "program nopatchrtl_probe;\n"
            "{$ifndef NOPATCHRTL}\n"
            "  {$error NOPATCHRTL is not defined: the compiler must define it on x86-64}\n"
            "{$endif}\n"
            "begin\nend.\n",
            encoding="utf-8", newline="\n")
        stripped = work / "config_without_nopatchrtl.cfg"
        stripped.write_text(
            "".join(line for line in config.read_text(encoding="utf-8").splitlines(keepends=True)
                    if line.strip() != "-dNOPATCHRTL"),
            encoding="utf-8")
        bare = ["-n", f"@{stripped}", f"-FE{work}", f"-FU{work}"]
        code, output = run_compiler(compiler, bare + [str(guard)], work)
        if code != 0:
            raise GateError("NOPATCHRTL is not built into the compiler: without the configuration's "
                            f"own -dNOPATCHRTL line the guard fires:\n{output[-3000:]}")
        code, output = run_compiler(compiler, bare + ["-uNOPATCHRTL", str(guard)], work)
        if code == 0 or "NOPATCHRTL is not defined" not in output:
            raise GateError("-uNOPATCHRTL no longer switches the built-in NOPATCHRTL off "
                            f"(the measurements against the mORMot patch need it):\n{output[-3000:]}")
    finally:
        shutil.rmtree(work, ignore_errors=True)


def shadow_notes(compiler: Path) -> list[str]:
    """Default configuration files a bare compiler (without -n) would read
    before the toolchain's own one, in the compiler's search order."""
    candidates: list[Path] = [Path.cwd() / "fpc.cfg"]
    configpath = os.environ.get("PPC_CONFIG_PATH", "")
    if os.name == "nt":
        if configpath:
            candidates.append(Path(configpath) / "fpc.cfg")
        for variable in ("USERPROFILE", "ALLUSERSPROFILE"):
            value = os.environ.get(variable, "")
            if value:
                candidates.append(Path(value) / "fpc.cfg")
    else:
        home = os.environ.get("HOME", "")
        if home:
            candidates.append(Path(home) / ".fpc.cfg")
        if configpath:
            candidates.append(Path(configpath) / "fpc.cfg")
        else:
            candidates.append(compiler.parent / ".." / "etc" / "fpc.cfg")
        candidates.append(Path("/etc/fpc.cfg"))
    return [f"note: a bare {compiler.name} without -n would read {c} (the drivers and gates always pass -n)"
            for c in candidates if c.is_file()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--toolchain", type=Path, default=ROOT / "toolchain",
                        help="installed toolchain to check (moon-base.cfg and IDE fpc.cfg)")
    parser.add_argument("--config", type=Path, help="check one rendered configuration file instead")
    parser.add_argument("--profile", choices=("product", "ide"), default="product",
                        help="which profile lines --config must carry (product = moon-base.cfg)")
    parser.add_argument("--compiler", type=Path, help="compiler for the behaviour probe (default: the toolchain's)")
    parser.add_argument("--skip-probe", action="store_true", help="only check the configuration text")
    args = parser.parse_args()

    try:
        checked = 0
        total = 0
        if args.config is not None:
            _, count = check_config(args.config.resolve(), args.profile, None)
            checked, total = 1, count
            product_config = args.config.resolve() if args.profile == "product" else None
            compiler = args.compiler
        else:
            toolchain = args.toolchain.resolve()
            if os.name == "nt":
                product_config = toolchain / "bin" / "x86_64-win64" / "moon-base.cfg"
                ide_config = toolchain / "ide" / "bin" / "x86_64-win64" / "fpc.cfg"
            else:
                product_config = toolchain / "etc" / "moon-base.cfg"
                ide_config = toolchain / "ide" / "etc" / "fpc.cfg"
            for config, profile in ((product_config, "product"), (ide_config, "ide")):
                _, count = check_config(config, profile, toolchain)
                checked += 1
                total += count
                print(f"{profile}: {config}: {count} audited option lines, no directive")
            compiler = args.compiler or find_compiler(toolchain)

        probe = "skipped"
        if not args.skip_probe and product_config is not None and compiler is not None:
            probe_compiler(compiler.resolve(), product_config)
            probe = "internal-default,-ap-internal,-ao-external,-Aas-external,external-warning,nopatchrtl-builtin"
            for note in shadow_notes(compiler.resolve()):
                print(note)
    except GateError as error:
        print(f"MOONCOMPILER_CONFIG_CONTRACT_GATE_FAIL: {error}")
        return 1

    print(f"MOONCOMPILER_CONFIG_CONTRACT_GATE_PASS configs={checked} options={total} "
          f"directives=0 probe={probe}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
