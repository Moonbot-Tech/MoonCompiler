#!/usr/bin/env python3
"""Build, pair-run and compare the MoonCompiler Pulse qualification suite."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path


PERF_ROOT = Path(__file__).resolve().parents[1]
ROOT = PERF_ROOT.parents[1]
COMMON = PERF_ROOT / "common"
RESULTS = PERF_ROOT / "results" / "pulse"
IS_WINDOWS = os.name == "nt"
PULSE_THREAD_WORKER_CPUS = 8
DCC64 = Path(r"C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe")
if IS_WINDOWS:
    MOON_FPC = ROOT / "toolchain" / "bin" / "x86_64-win64" / "fpc.exe"
    MOON_CFG = ROOT / "toolchain" / "bin" / "x86_64-win64" / "fpc.cfg"
else:
    MOON_FPC = ROOT / "toolchain" / "bin" / "fpc"
    MOON_CFG = ROOT / "toolchain" / "etc" / "fpc.cfg"
MM_SOURCE = ROOT / "runtime" / "mm" / "mormot.core.fpcx64mm.pas"

PROGRAMS = {
    name: PERF_ROOT / name / f"pulse_{name}.dpr"
    for name in (
        "calibration",
        "abi",
        "codegen",
        "numeric",
        "loops",
        "layout",
        "move",
        "dispatch",
        "managed",
        "algorithms",
        "dictionary",
        "json",
        "mormot-json",
        "zlib",
        "mm",
        "rtl",
        "rtl-collections",
        "threads",
        "workloads",
        "heartbeat",
        "kernels",
        "repairs",
        "hot-rtl",
        "product-forms",
    )
}
PROGRAMS["local-pressure"] = PERF_ROOT / "local-pressure" / "pulse_local_pressure.dpr"
PROGRAMS["record-stream"] = PERF_ROOT / "move" / "pulse_record_stream.dpr"
PROGRAMS["mm-lifetime"] = PERF_ROOT / "mm" / "pulse_mm_lifetime.dpr"
PROGRAMS["text-pipeline"] = PERF_ROOT / "text" / "pulse_text_pipeline.dpr"
PROGRAMS["name-lookup"] = PERF_ROOT / "text" / "pulse_name_lookup.dpr"
PROGRAMS["decoded-messages"] = PERF_ROOT / "text" / "pulse_decoded_messages.dpr"
PROGRAMS["timestamp-events"] = PERF_ROOT / "text" / "pulse_timestamp_events.dpr"
PROGRAMS["sorted-lookup"] = PERF_ROOT / "text" / "pulse_sorted_lookup.dpr"
PROGRAMS["ordinal-scan"] = PERF_ROOT / "dictionary" / "pulse_ordinal_scan.dpr"
MOON_ONLY_PROGRAMS = frozenset({"repairs"})
DEFAULT_PROGRAMS = tuple(name for name in PROGRAMS if name not in MOON_ONLY_PROGRAMS)
PINNED_MORMOT = ROOT / ".qualification" / "deps" / "moonormot"
MORMOT_PRODUCT = PINNED_MORMOT if PINNED_MORMOT.is_dir() else ROOT / "mormot"
PROGRAM_UNIT_PATHS = {
    "hot-rtl": [PERF_ROOT / "hot-rtl"],
    "mormot-json": [MORMOT_PRODUCT / "core"],
    "zlib": [MORMOT_PRODUCT / "core", MORMOT_PRODUCT / "lib"],
    "heartbeat": [MORMOT_PRODUCT / "core"],
    "repairs": [PERF_ROOT / "abi"],
}
# Unit directories of the Moon toolchain itself that a program needs besides
# its PROGRAM_UNIT_PATHS (Delphi takes those units from its own RTL): zlib's
# System.Zip, which each toolchain carries in runtime/mormot.
MOON_TOOLCHAIN_UNIT_PATHS = {"zlib": [Path("runtime") / "mormot"]}
# A program that needs a unit an older Moon toolchain does not have: the release
# before System.ZLib.  build() leaves such a program out for that toolchain, and
# a run compares it only between the systems that could build it.
PROGRAM_TOOLCHAIN_UNITS = {"zlib": "vcl-compat/system.zlib.ppu"}
SYSTEM_LABELS = {
    "delphi": "Delphi 12.2 + default FastMM4",
    "moon": "MoonCompiler + bundled fpcx64mm",
    "moon-default": "MoonCompiler + FPC default MM",
    "moon-baseline": "MoonCompiler baseline + bundled fpcx64mm",
    "moon-candidate": "MoonCompiler candidate + bundled fpcx64mm",
}
EXTERNAL_MOON_SYSTEMS = ("moon-baseline", "moon-candidate")
# RTL profile stand: additional Moon systems named on the command line as
# --moon-system NAME=TOOLCHAIN; every such system is built like an external
# baseline/candidate and labelled by its name.
STAND_SYSTEMS: dict[str, Path] = {}
STAND_EXTRA_OPTIONS: list[str] = []
MAX_TARGETED_RETRIES = 3
MEASUREMENT_METHOD = "fresh-image-paired-process-medians-v1"
PROCESS_TIMEOUT_SECONDS = int(os.environ.get("PULSE_PROCESS_TIMEOUT_SECONDS", "300"))


def run(
    command: list[str],
    *,
    cwd: Path = ROOT,
    capture: bool = False,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        timeout=timeout,
    )


def linux_cpu_topology(cpus: set[int]) -> dict[int, tuple[int, int]]:
    """Map Linux logical CPUs to physical package/core identities."""
    topology: dict[int, tuple[int, int]] = {}
    root = Path("/sys/devices/system/cpu")
    for cpu in sorted(cpus):
        cpu_root = root / f"cpu{cpu}" / "topology"
        try:
            package = int((cpu_root / "physical_package_id").read_text().strip())
            core = int((cpu_root / "core_id").read_text().strip())
        except (OSError, ValueError) as error:
            raise RuntimeError(
                f"Linux Pulse cannot resolve physical topology for CPU {cpu}"
            ) from error
        topology[cpu] = (package, core)
    return topology


def select_pulse_physical_cpus(
    available: set[int], topology: dict[int, tuple[int, int]], required: int = PULSE_THREAD_WORKER_CPUS + 1
) -> tuple[int, ...]:
    """Reserve distinct cores; only the selected worker cases require a wide set."""
    cpus: list[int] = []
    physical: set[tuple[int, int]] = set()
    for cpu in sorted(available):
        identity = topology.get(cpu)
        if identity is None:
            raise RuntimeError(f"Linux Pulse topology is missing CPU {cpu}")
        if identity in physical:
            continue
        physical.add(identity)
        cpus.append(cpu)
    if len(cpus) < required:
        raise RuntimeError(
            f"Linux Pulse requires {required} distinct physical cores for its "
            f"selected cases; only {len(cpus)} are available"
        )
    return tuple(cpus[:PULSE_THREAD_WORKER_CPUS + 1])


def linux_pulse_cpu_reservation(programs: list[str], selected_rows: set[str] | None) -> tuple[int, ...]:
    """A placement family needs no more cores than the work it actually runs."""
    if IS_WINDOWS:
        return ()
    if not hasattr(os, "sched_getaffinity"):
        raise RuntimeError("Linux Pulse requires sched_getaffinity")
    available = os.sched_getaffinity(0)
    required = 1
    if "threads" in programs:
        required = PULSE_THREAD_WORKER_CPUS + 1
    elif "repairs" in programs and (not selected_rows or "repairs/padded-counters-4" in selected_rows):
        required = 5
    return select_pulse_physical_cpus(available, linux_cpu_topology(available), required)


def pulse_command(
    exe: Path, mode: str, selected_case: str, reserved_cpus: tuple[int, ...],
    *, taskset: str | None = None,
) -> list[str]:
    command = [str(exe), mode, selected_case]
    if not reserved_cpus:
        return command
    taskset = taskset or shutil.which("taskset")
    if taskset is None:
        raise RuntimeError("Linux Pulse requires taskset for fixed process affinity")
    return [taskset, "--cpu-list", ",".join(str(cpu) for cpu in reserved_cpus), *command]


def pulse_execution_metadata(reserved_cpus: tuple[int, ...]) -> dict[str, object]:
    if not reserved_cpus:
        return {"method": "native thread affinity"}
    return {
        "method": "taskset process reservation + sched_setaffinity threads",
        "reserved_cpus": list(reserved_cpus),
        "physical_cores": {
            str(cpu): list(identity)
            for cpu, identity in linux_cpu_topology(set(reserved_cpus)).items()
        },
        "taskset": shutil.which("taskset"),
    }


def pulse_result_path(result_root: Path | None, tag: str) -> Path:
    """Resolve one result directory below the selected result root."""
    tag_path = Path(tag)
    if tag_path.is_absolute() or ".." in tag_path.parts:
        raise ValueError(f"tag must be a relative child path: {tag}")
    return (result_root or RESULTS).resolve() / tag_path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def output_dir(program: str, system: str) -> Path:
    return PERF_ROOT / program / f"build-{system}"


def executable(program: str, system: str) -> Path:
    suffix = ".exe" if IS_WINDOWS else ""
    return output_dir(program, system) / f"{PROGRAMS[program].stem}{suffix}"


def build_delphi(program: str) -> Path:
    if not DCC64.is_file():
        raise FileNotFoundError(f"Delphi 12.2 dcc64.exe not found: {DCC64}")
    source = PROGRAMS[program]
    target = output_dir(program, "delphi")
    target.mkdir(parents=True, exist_ok=True)
    unit_paths = [COMMON, *PROGRAM_UNIT_PATHS.get(program, [])]
    run(
        [
            str(DCC64),
            "-B",
            "-Q",
            "-$O+",
            "--inline:auto",
            "-NSSystem;Winapi;System.Win;Data;Xml",
            *(f"-U{path}" for path in unit_paths),
            *(f"-I{path}" for path in unit_paths),
            f"-E{target}",
            f"-N0{target}",
            str(source),
        ]
    )
    return executable(program, "delphi")


def moon_toolchain_paths(toolchain: Path | None = None) -> tuple[Path, Path]:
    if toolchain is None:
        return MOON_FPC, MOON_CFG
    if IS_WINDOWS:
        binary = toolchain / "bin" / "x86_64-win64"
        return binary / "fpc.exe", binary / "fpc.cfg"
    return toolchain / "bin" / "fpc", toolchain / "etc" / "fpc.cfg"


def moon_toolchain_backends(toolchain: Path) -> list[Path]:
    # A complete MoonCompiler toolchain contains a product profile at bin/ and
    # an intentionally separate vanilla-string IDE profile at ide/bin/.  Pulse
    # benchmarks the product profile selected by moon_toolchain_paths().
    product_bin = toolchain / "bin"
    return sorted(
        {
            path.resolve()
            for pattern in ("ppcx64", "ppcx64.exe")
            for path in product_bin.rglob(pattern)
            if path.is_file()
        },
        key=str,
    )


def moon_toolchain_backend(toolchain: Path) -> Path:
    backends = moon_toolchain_backends(toolchain)
    if len(backends) != 1:
        raise RuntimeError(
            f"external Moon toolchain must contain exactly one x86-64 backend: "
            f"{toolchain} has {backends}"
        )
    return backends[0]


def toolchain_units(toolchain: Path) -> Path | None:
    """The installed unit tree of a Moon toolchain, or None when it has no single one."""
    if IS_WINDOWS:
        return toolchain / "units" / "x86_64-win64"
    versions = sorted((toolchain / "lib" / "fpc").glob("[0-9]*"))
    return versions[0] / "units" / "x86_64-linux" if len(versions) == 1 else None


def missing_program_unit(program: str, toolchain: Path) -> str | None:
    """The unit of PROGRAM_TOOLCHAIN_UNITS that `toolchain` lacks for `program`, or None."""
    unit = PROGRAM_TOOLCHAIN_UNITS.get(program)
    if unit is None:
        return None
    units = toolchain_units(toolchain)
    return None if units is not None and (units / unit).is_file() else unit


def moon_toolchain_identity(toolchain: Path) -> dict[str, object]:
    moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
    backend = moon_toolchain_backend(toolchain)
    identity: dict[str, object] = {
        "root": str(toolchain.resolve()),
        "fpc": str(moon_fpc.resolve()),
        "fpc_sha256": sha256(moon_fpc),
        "config": str(moon_cfg.resolve()),
        "config_sha256": sha256(moon_cfg),
        "backend": str(backend),
        "backend_sha256": sha256(backend),
    }
    base_cfg = moon_cfg.with_name("moon-base.cfg")
    if base_cfg.is_file():
        identity["base_config_sha256"] = sha256(base_cfg)
    else:
        identity["legacy_release_config_sha256"] = sha256(Path(__file__).with_name("pulse_legacy_release.cfg"))
    profile = toolchain / "profile.txt"
    if profile.is_file():
        identity["profile"] = str(profile.resolve())
        identity["profile_sha256"] = sha256(profile)
    units = toolchain_units(toolchain)
    witnesses = {
        name: path
        for name, path in {
            "system.ppu": units / "rtl" / "system.ppu" if units else None,
            "sysutils.o": units / "rtl" / "sysutils.o" if units else None,
            "math.o": units / "rtl" / "math.o" if units else None,
            "generics.hashes.o": (
                units / "rtl-generics" / "generics.hashes.o"
            ) if units else None,
        }.items()
        if path is not None and path.is_file()
    }
    if witnesses:
        identity["unit_sha256"] = {
            name: sha256(path) for name, path in witnesses.items()
        }
    return identity


def moon_mm_options(default_mm: bool, mm_source: Path = MM_SOURCE) -> list[str]:
    if default_mm:
        return [
            "-dPULSE_DEFAULT_MM",
            "-dMOONCOMPILER_VANILLA_RUNTIME",
            "-Fafpwinmonitor" if IS_WINDOWS else "-Facthreads,cwstring,fpmonitor",
            "-uMOONBOT_MM_PROFILE_REQUIRED",
            "-uFPCMM_BOOSTER",
            "-uFPCMM_MOONSHARD",
            "-uNOPATCHRTL",
        ]
    return [
        "-uMOONCOMPILER_VANILLA_RUNTIME",
        "-dFPCMM_BOOSTER",
        "-dFPCMM_MOONSHARD",
        "-dNOPATCHRTL",
        "-dMOONBOT_MM_PROFILE_REQUIRED",
        f"--pinned-unit=mormot.core.fpcx64mm={mm_source.resolve()}",
        "--required-first-unit=mormot.core.fpcx64mm",
        f"-Fu{mm_source.resolve().parent}",
    ]


def build_moon(
    program: str,
    default_mm: bool,
    *,
    system: str | None = None,
    toolchain: Path | None = None,
    mm_source: Path = MM_SOURCE,
    extra_options: list[str] | None = None,
) -> Path:
    moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
    moon_compiler = moon_toolchain_backend(toolchain) if toolchain else moon_fpc
    if not moon_compiler.is_file() or not moon_cfg.is_file():
        raise FileNotFoundError("Moon toolchain is not built; run ./build compiler")
    system = system or ("moon-default" if default_mm else "moon")
    target = output_dir(program, system)
    target.mkdir(parents=True, exist_ok=True)
    toolchain_root = toolchain or ROOT / "toolchain"
    unit_paths = [COMMON, *PROGRAM_UNIT_PATHS.get(program, []),
                  *(toolchain_root / path for path in MOON_TOOLCHAIN_UNIT_PATHS.get(program, []))]
    args = [
        str(moon_compiler),
        "-n",
        "-dRELEASE",
        "-uDEBUG",
        f"@{moon_cfg}",
        # Before the driverless product profile, fpc.cfg was only a template.
        # The release's build/build.ps1 supplied the application's full profile.
        *([] if moon_cfg.with_name("moon-base.cfg").is_file() else
          [f"@{Path(__file__).with_name('pulse_legacy_release.cfg')}"]),
        "-B",
        *(f"-Fu{path}" for path in unit_paths),
        *(f"-Fi{path}" for path in unit_paths),
        *(f"-Fo{path}" for path in unit_paths),
        f"-FE{target}",
        f"-FU{target}",
    ]
    args.extend(extra_options or [])
    args.extend(STAND_EXTRA_OPTIONS)
    if not IS_WINDOWS:
        # Preserve static relocation metadata for code-identity checks. This
        # changes no loadable instructions or allocation/timing paths.
        args.append('-k--emit-relocs')
    args.extend(moon_mm_options(default_mm, mm_source))
    if program == 'threads' and not default_mm:
        args.extend(['-dFPCMM_SMALLPOOL_REUSE_TEST', '-dFPCMM_MEDIUMLASTFREE_TEST'])
    run(args + [str(PROGRAMS[program])])
    return executable(program, system)


def build(
    programs: list[str],
    systems: list[str],
    external_toolchains: dict[str, Path] | None = None,
    external_mm_sources: dict[str, Path] | None = None,
    external_options: dict[str, list[str]] | None = None,
    build_jobs: int = 1,
) -> dict[str, dict[str, Path]]:
    external_toolchains = external_toolchains or {}
    external_mm_sources = external_mm_sources or {}
    external_options = external_options or {}
    if build_jobs < 1:
        raise ValueError("build_jobs must be positive")
    built: dict[str, dict[str, Path]] = {system: {} for system in systems}

    def build_one(system: str, program: str) -> tuple[str, str, Path | None]:
        toolchain = None if system == "delphi" else external_toolchains.get(system, ROOT / "toolchain")
        missing = missing_program_unit(program, toolchain) if toolchain is not None else None
        if missing:
            print(f"BUILD_SKIP system={system} program={program} missing={missing}", flush=True)
            return system, program, None
        print(f"BUILD system={system} program={program}", flush=True)
        if system == "delphi":
            path = build_delphi(program)
        elif system == "moon":
            path = build_moon(program, False)
        elif system == "moon-default":
            path = build_moon(program, True)
        elif system in EXTERNAL_MOON_SYSTEMS or system in STAND_SYSTEMS:
            path = build_moon(
                program,
                False,
                system=system,
                toolchain=external_toolchains[system],
                mm_source=external_mm_sources.get(system, MM_SOURCE),
                extra_options=external_options.get(system),
            )
        else:
            raise ValueError(f"unknown system: {system}")
        print(f"BUILD_DONE system={system} program={program}", flush=True)
        return system, program, path

    work = [(system, program) for program in programs for system in systems]
    if build_jobs == 1:
        completed = (build_one(system, program) for system, program in work)
        for system, program, path in completed:
            if path is not None:
                built[system][program] = path
    else:
        with ThreadPoolExecutor(max_workers=build_jobs) as executor:
            futures = {
                executor.submit(build_one, system, program): (system, program)
                for system, program in work
            }
            for future in as_completed(futures):
                system, program, path = future.result()
                if path is not None:
                    built[system][program] = path
    return built


def buildable_everywhere(
    built: dict[str, dict[str, Path]], programs: list[str]
) -> tuple[list[str], dict[str, list[str]]]:
    """(the programs every system built, program -> the systems that could not) after build()."""
    left_out = {
        program: sorted(system for system, done in built.items() if program not in done)
        for program in programs
    }
    left_out = {program: systems for program, systems in left_out.items() if systems}
    for program, systems in left_out.items():
        print(f"PULSE_LEFT_OUT program={program} systems={','.join(systems)}", flush=True)
    return [program for program in programs if program not in left_out], left_out


def git_text(*args: str) -> str:
    try:
        return run(["git", *args], capture=True).stdout.strip()
    except subprocess.CalledProcessError:
        return "<unavailable>"


def machine_metadata() -> dict[str, object]:
    metadata = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "logical_cpu_count": os.cpu_count(),
    }
    if hasattr(os, "sched_getaffinity"):
        metadata["process_cpu_affinity"] = sorted(os.sched_getaffinity(0))
    return metadata


def qualification_input_hashes(
    external_toolchains: dict[str, Path] | None = None,
    external_mm_sources: dict[str, Path] | None = None,
) -> dict[str, str]:
    inputs: dict[str, str] = {}
    fixed = [MOON_FPC, MOON_CFG, MOON_CFG.with_name("moon-base.cfg"), MM_SOURCE]
    fixed.extend(sorted((ROOT / "toolchain").rglob("ppcx64")))
    fixed.extend(sorted((ROOT / "toolchain").rglob("ppcx64.exe")))
    if IS_WINDOWS:
        fixed.append(DCC64)
    for toolchain in (external_toolchains or {}).values():
        moon_fpc, moon_cfg = moon_toolchain_paths(toolchain)
        fixed.extend((moon_fpc, moon_cfg, moon_cfg.with_name("moon-base.cfg")))
        fixed.extend(sorted(toolchain.rglob("ppcx64")))
        fixed.extend(sorted(toolchain.rglob("ppcx64.exe")))
    fixed.extend((external_mm_sources or {}).values())
    for path in fixed:
        if path.is_file():
            resolved = path.resolve()
            key = (
                str(resolved.relative_to(ROOT))
                if resolved.is_relative_to(ROOT)
                else str(resolved)
            )
            inputs[key] = sha256(path)
    for path in sorted(PERF_ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(PERF_ROOT)
        if any(
            part == "results"
            or part == "__pycache__"
            or part.startswith("build-")
            for part in relative.parts
        ):
            continue
        inputs[str(Path("qualification/performance") / relative)] = sha256(path)
    return inputs


def discover_cases(exe: Path) -> list[str]:
    discovery = run([str(exe), "list", "all"], capture=True).stdout
    cases = [
        parse_fields(line)["case"]
        for line in discovery.splitlines()
        if line.startswith("PULSE_CASEDEF ")
    ]
    if not cases or len(cases) != len(set(cases)):
        raise RuntimeError(f"invalid case discovery from {exe}")
    return cases


def comparison_pairs(systems: list[str]) -> list[tuple[str, str]]:
    baseline, candidate = report_system_roles(systems)
    if baseline == candidate:
        return []
    pairs = [(baseline + suffix, candidate + suffix) for suffix in ("", "1", "2", "3")
             if baseline + suffix in systems and candidate + suffix in systems]
    return pairs if {s for pair in pairs for s in pair} == set(systems) else []


def process_order(systems: list[str], repeats: int) -> list[str]:
    pairs = comparison_pairs(systems)
    if pairs:
        return [system for repeat in range(0, repeats, 2) for a, b in pairs
                for system in ([a, b, b, a] if repeat + 1 < repeats else [a, b])]
    return (systems + list(reversed(systems))) * (repeats // 2) + (systems if repeats % 2 else [])


def run_fresh_image(exe: Path, mode: str, selected_case: str, reserved_cpus: tuple[int, ...],
                    expected_sha256: str) -> tuple[subprocess.CompletedProcess[str], dict[str, object]]:
    """A new file instance for every process; retries still name the canonical binary."""
    if sha256(exe) != expected_sha256:
        raise ValueError(f"benchmark executable changed: {exe}")
    with tempfile.TemporaryDirectory(prefix="pulse-image-", dir=exe.parent) as directory:
        image = Path(directory) / exe.name
        shutil.copy2(exe, image)
        if sha256(image) != expected_sha256:
            raise ValueError(f"benchmark image differs: {image}")
        command = pulse_command(image, mode, selected_case, reserved_cpus)
        completed = run(
            command, capture=True, timeout=PROCESS_TIMEOUT_SECONDS
        )
        return completed, {"executed_image": str(image), "executed_image_sha256": expected_sha256,
                           "executed_command": command}


def run_suite(
    mode: str,
    programs: list[str],
    systems: list[str],
    tag: str,
    external_toolchains: dict[str, Path] | None = None,
    external_mm_sources: dict[str, Path] | None = None,
    external_options: dict[str, list[str]] | None = None,
    result_root: Path | None = None,
    build_jobs: int = 1,
    selected_rows: set[str] | None = None,
) -> Path:
    external_toolchains = external_toolchains or {}
    external_mm_sources = external_mm_sources or {}
    external_options = external_options or {}
    reserved_cpus = linux_pulse_cpu_reservation(programs, selected_rows)
    built = build(
        programs, systems, external_toolchains, external_mm_sources,
        external_options, build_jobs,
    )
    programs, left_out = buildable_everywhere(built, programs)
    if not programs:
        raise ValueError(f"no program is built by every system: {left_out}")
    result = pulse_result_path(result_root, tag)
    result.mkdir(parents=True, exist_ok=False)
    repeats = {"quick": 2, "medium": 7, "long": 9}[mode]
    order = process_order(systems, repeats)
    binary_hashes = {path: sha256(path) for programs_built in built.values() for path in programs_built.values()}
    runs: list[dict[str, object]] = []
    schedule: list[tuple[int, str, str, str, Path]] = []
    if mode == "quick":
        if selected_rows:
            raise ValueError("--cases requires medium or long mode")
        for program in programs:
            for sequence, system in enumerate(order, 1):
                schedule.append((sequence, system, program, "all", built[system][program]))
    else:
        for program in programs:
            expected_cases: list[str] | None = None
            for system in systems:
                cases = discover_cases(built[system][program])
                if expected_cases is None:
                    expected_cases = cases
                elif cases != expected_cases:
                    raise RuntimeError(
                        f"case matrix differs for {program}: {systems[0]}={expected_cases}, "
                        f"{system}={cases}"
                    )
            assert expected_cases is not None
            for selected_case in expected_cases:
                row_name = f"{program}/{selected_case}"
                if selected_rows and row_name not in selected_rows:
                    continue
                for sequence, system in enumerate(order, 1):
                    schedule.append(
                        (sequence, system, program, selected_case, built[system][program])
                    )
    if selected_rows:
        scheduled_rows = {
            f"{program}/{case}" for _, _, program, case, _ in schedule
        }
        missing_rows = selected_rows - scheduled_rows
        if missing_rows:
            raise ValueError(
                "selected cases were not discovered: "
                + ", ".join(sorted(missing_rows))
            )

    total_runs = len(schedule)
    for run_index, (sequence, system, program, selected_case, exe) in enumerate(
        schedule, 1
    ):
        if run_index == 1 or run_index % 100 == 0 or run_index == total_runs:
            print(
                f"PULSE_PROGRESS completed={run_index - 1} total={total_runs} "
                f"program={program} case={selected_case}",
                flush=True,
            )
        suffix = "" if selected_case == "all" else f"-{selected_case}"
        log = result / f"{sequence:02d}-{system}-{program}{suffix}.log"
        print(
            f"RUN sequence={sequence} system={system} program={program} "
            f"mode={mode} case={selected_case}",
            flush=True,
        )
        try:
            command = pulse_command(exe, mode, selected_case, reserved_cpus)
            completed, image_identity = run_fresh_image(exe, mode, selected_case, reserved_cpus, binary_hashes[exe])
        except subprocess.TimeoutExpired as error:
            output = error.stdout or ""
            if isinstance(output, bytes):
                output = output.decode("utf-8", errors="replace")
            log.write_text(output, encoding="utf-8", newline="\n")
            raise RuntimeError(
                f"benchmark timed out after {PROCESS_TIMEOUT_SECONDS}s; "
                f"partial output is in {log}"
            ) from error
        except subprocess.CalledProcessError as error:
            log.write_text(error.stdout or "", encoding="utf-8", newline="\n")
            raise RuntimeError(f"benchmark failed; complete output is in {log}") from error
        log.write_text(completed.stdout, encoding="utf-8", newline="\n")
        if "PULSE_END" not in completed.stdout or "status=PASS" not in completed.stdout:
            raise RuntimeError(f"missing PASS terminal in {log}")
        runs.append(
            {
                "sequence": sequence,
                "system": system,
                "program": program,
                "case": selected_case,
                "executable": str(exe.relative_to(ROOT)),
                "executable_sha256": binary_hashes[exe],
                "command": command,
                **image_identity,
                "log": log.name,
                "log_sha256": sha256(log),
            }
        )
    manifest = {
        "schema": 1,
        "measurement_method": MEASUREMENT_METHOD,
        "input_contract": "fixed-alloc-block16384-v1",
        "case_isolation": "all cases in one process" if mode == "quick" else "one case per process",
        "project": "MoonCompiler Pulse",
        "created_unix": time.time(),
        "command": sys.argv,
        "mode": mode,
        "selected_rows": sorted(selected_rows or ()),
        "left_out": left_out,
        "git_head": git_text("rev-parse", "HEAD"),
        "git_status": git_text("status", "--porcelain=v1"),
        "machine": machine_metadata(),
        "execution_affinity": pulse_execution_metadata(reserved_cpus),
        "input_sha256": qualification_input_hashes(
            external_toolchains, external_mm_sources,
        ),
        "systems": {system: SYSTEM_LABELS.get(system, f"MoonCompiler stand {system}") for system in systems},
        "external_toolchains": {
            system: moon_toolchain_identity(toolchain)
            for system, toolchain in external_toolchains.items()
        },
        "external_memory_managers": {
            system: {
                "source": str(source.resolve()),
                "sha256": sha256(source),
            }
            for system, source in external_mm_sources.items()
        },
        "external_options": external_options,
        "runs": runs,
    }
    (result / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    write_report(result)
    print(f"PULSE_RESULT {result}")
    return result


def parse_fields(line: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in line.split()[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


@dataclass(frozen=True)
class Stats:
    mode: float
    median: float
    mean: float
    minimum: float
    maximum: float
    kept: int
    rejected: int


class UnstablePairsError(ValueError):
    def __init__(self, messages: list[str], cases: set[tuple[str, str]]) -> None:
        super().__init__("unstable process pairs: " + "; ".join(messages))
        self.cases = tuple(sorted(cases))


def observed_stats(values: list[float]) -> Stats:
    """Keep every observation: a second process mode is evidence, not an outlier to erase."""
    if not values or any(value <= 0 or not math.isfinite(value) for value in values):
        raise ValueError("expected finite positive measurements")
    center = statistics.median(values)
    return Stats(center, center, statistics.mean(values), min(values), max(values), len(values), 0)


def process_balanced_stats(
    row: dict[str, object], metric: str = "tsc"
) -> tuple[Stats, list[Stats]]:
    run_stats = [
        observed_stats([sample[metric] for sample in samples if sample[metric] > 0])
        for samples in row["run_samples"]
    ]
    return observed_stats([stats.median for stats in run_stats]), run_stats


def process_balanced_cycles(row: dict[str, object]) -> Stats | None:
    run_modes: list[float] = []
    for samples in row["run_samples"]:
        values = [sample["cycles"] for sample in samples if sample["cycles"] > 0]
        if values:
            run_modes.append(statistics.median(values))
    return observed_stats(run_modes) if run_modes else None


def metric_available(row: dict[str, object], metric: str) -> bool:
    """Return whether every process has at least one usable metric sample."""
    run_samples = row["run_samples"]
    return bool(run_samples) and all(
        any(sample[metric] > 0 for sample in samples) for samples in run_samples
    )


def select_primary_metric(
    program: str, rows: list[dict[str, object]]
) -> str:
    """Prefer scheduled cycles, with an explicit TSC fallback when unavailable."""
    if program in ("threads", "move") or any(
        "threads" in str(row.get("layer", "")).split("+") for row in rows
    ):
        return "tsc"
    return "cycles" if all(metric_available(row, "cycles") for row in rows) else "tsc"


def use_paired_process_ratios(program: str, metric: str) -> bool:
    """Pair frequency-sensitive TSC processes in the palindromic schedule."""
    return program == "move" or metric == "tsc"


def paired_ratio_stats(
    baseline: dict[str, object], candidate: dict[str, object], metric: str
) -> Stats:
    def modes_by_sequence(row: dict[str, object]) -> dict[int, float]:
        return {
            sequence: observed_stats(
                [sample[metric] for sample in samples if sample[metric] > 0]
            ).median
            for sequence, samples in zip(row["run_sequences"], row["run_samples"])
        }

    baseline_modes = modes_by_sequence(baseline)
    candidate_modes = modes_by_sequence(candidate)
    return paired_centers(baseline_modes, candidate_modes)


def paired_centers(baseline_modes: dict[int, float], candidate_modes: dict[int, float]) -> Stats:
    events = sorted(
        [(sequence, "baseline", value) for sequence, value in baseline_modes.items()]
        + [(sequence, "candidate", value) for sequence, value in candidate_modes.items()]
    )
    ratios: list[float] = []
    index = 0
    while index + 1 < len(events):
        first, second = events[index], events[index + 1]
        if (second[0] == first[0] + 1) and (first[1] != second[1]):
            values = {first[1]: first[2], second[1]: second[2]}
            ratios.append(values["candidate"] / values["baseline"])
            index += 2
        else:
            index += 1
    if not ratios:
        raise ValueError("no adjacent baseline/candidate process pairs")
    if len(ratios) != len(baseline_modes) or len(ratios) != len(candidate_modes):
        raise ValueError("incomplete adjacent baseline/candidate process pairs")
    return observed_stats(ratios)


def diagnostic_layer(layer: str) -> bool:
    return bool({"asm-reference", "calibration", "accepted-noop"} & set(layer.split("+")))


def sample_spread(row: dict, metric: str) -> float:
    """Middle-half spread exposes broad within-process variation without one-spike vetoes."""
    spreads = []
    for samples in row["run_samples"]:
        values = sorted(sample[metric] for sample in samples if sample[metric] > 0)
        if not values:
            raise ValueError(f"no {metric} samples")
        spreads.append(values[3 * len(values) // 4] / values[len(values) // 4])
    return max(spreads)


def effective_core_stats(row: dict[str, object]) -> Stats | None:
    values = [
        total["effective_cores"]
        for total in row["totals"]
        if total["effective_cores"] > 0
    ]
    return observed_stats(values) if values else None


def emitted_program_names(program: str) -> set[str]:
    """Return manifest and Pascal-identifier spellings accepted in a log."""
    names = {program}
    if program in PROGRAMS:
        stem = PROGRAMS[program].stem
        names.update((stem, stem.replace("-", "_")))
    return names


def collect(result: Path) -> tuple[dict[tuple[str, str, str], dict[str, object]], dict[str, object]]:
    manifest = json.loads((result / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("measurement_method") not in (None, MEASUREMENT_METHOD):
        raise ValueError("unsupported measurement method")
    images = set()
    systems = list(manifest["systems"])
    if not systems or len(systems) != len(set(systems)):
        raise ValueError("manifest has an empty or duplicate system list")
    repeats = {"quick": 2, "medium": 7, "long": 9}.get(manifest.get("mode"))
    if repeats is None:
        raise ValueError(f"unsupported Pulse mode in manifest: {manifest.get('mode')!r}")
    rows: dict[tuple[str, str, str], dict[str, object]] = {}
    case_sets: dict[tuple[str, str], set[str]] = {}
    programs: set[str] = set()
    for item in manifest["runs"]:
        if manifest.get("measurement_method"):
            image = item.get("executed_image")
            if not image or image in images:
                raise ValueError("missing or reused process image")
            images.add(image)
            if not item.get("executable_sha256") or item.get("executed_image_sha256") != item["executable_sha256"]:
                raise ValueError("process image hash differs from canonical executable")
        system = item["system"]
        program = item["program"]
        programs.add(program)
        if system not in systems:
            raise ValueError(f"run names an undeclared system: {system}")
        log_path = result / item["log"]
        if not log_path.is_file():
            raise ValueError(f"run log is missing: {log_path}")
        if item.get("log_sha256") and sha256(log_path) != item["log_sha256"]:
            raise ValueError(f"run log hash differs: {log_path}")
        text = log_path.read_text(encoding="utf-8")
        terminals = [
            line for line in text.splitlines()
            if line.startswith("PULSE_END ") and "status=PASS" in line
        ]
        if len(terminals) != 1:
            raise ValueError(f"{item['log']}: expected one PASS terminal, found {len(terminals)}")
        seen_cases: dict[str, int] = {}
        log_samples: dict[str, list[dict[str, float]]] = {}
        log_digests: dict[str, set[str]] = {}
        log_totals: dict[str, int] = {}
        log_workers = []
        for line in text.splitlines():
            if line.startswith(("PULSE_CASE ", "PULSE_SAMPLE ", "PULSE_TOTAL ")):
                fields = parse_fields(line)
                if fields.get('mode') != manifest['mode']:
                    raise ValueError(f"{item['log']}: log mode differs from manifest mode")
            if line.startswith('PULSE_WORKER '):
                fields = parse_fields(line)
                worker = {name: int(fields[name]) for name in ('worker', 'row')}
                worker.update({name: int(fields[name], 16) for name in
                               ('tid', 'class0', 'class1', 'class2', 'owner0', 'owner1', 'owner2')})
                if worker['row'] != ((worker['tid'] * 0x9E3779B1) & 0xFFFFFFFF) >> 27:
                    raise ValueError(f"{item['log']}: worker preferred row does not match native thread identity")
                log_workers.append(worker)
            elif line.startswith("PULSE_CASE "):
                fields = parse_fields(line)
                expected_program_names = emitted_program_names(program)
                if fields.get("program") not in expected_program_names:
                    raise ValueError(
                        f"{item['log']}: case program {fields.get('program')!r} "
                        f"does not match manifest {program!r} "
                        f"({sorted(expected_program_names)})"
                    )
                case = fields["case"]
                if case in seen_cases:
                    raise ValueError(f"{item['log']}: duplicate PULSE_CASE {case}")
                seen_cases[case] = int(fields["samples"])
                key = (system, program, fields["case"])
                row = rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": [], "run_digests": [], "bodies": [], "body_offsets": [],
                        "workers": [], "work_bodies": [], "work_body_offsets": [],
                    }
                )
                row.update({name: fields[name] for name in ("layer", "unit")})
                row["oracles"].append(fields["oracle"])
                if ("body" in fields) != ("anchor" in fields):
                    raise ValueError(f"{item['log']}: incomplete body/anchor identity for {case}")
                if "body" in fields:
                    body, anchor = int(fields["body"], 16), int(fields["anchor"], 16)
                    if body <= 0 or anchor <= 0:
                        raise ValueError(f"{item['log']}: invalid body/anchor address for {case}")
                    row["bodies"].append(body)
                    row["body_offsets"].append(body - anchor)
                    work_body = int(fields.get('workbody', '0'), 16)
                    if work_body:
                        row['work_bodies'].append(work_body)
                        row['work_body_offsets'].append(work_body - anchor)
            elif line.startswith("PULSE_SAMPLE "):
                fields = parse_fields(line)
                case = fields["case"]
                if case not in seen_cases:
                    raise ValueError(f"{item['log']}: sample precedes PULSE_CASE {case}")
                key = (system, program, case)
                operations = int(fields["operations"])
                if operations <= 0:
                    raise ValueError(f"{item['log']}: non-positive operations for {case}")
                sample = {
                    "wall": int(fields["wall_ns"]) / operations,
                    "tsc": int(fields["tsc_ticks"]) / operations,
                    "cycles": int(fields["thread_cycles"]) / operations,
                }
                rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": [], "run_digests": [],
                    }
                )["samples"].append(sample)
                log_samples.setdefault(case, []).append(sample)
                log_digests.setdefault(case, set()).add(fields["digest"])
            elif line.startswith("PULSE_TOTAL "):
                fields = parse_fields(line)
                case = fields["case"]
                if case not in seen_cases:
                    raise ValueError(f"{item['log']}: total precedes PULSE_CASE {case}")
                key = (system, program, case)
                wall = int(fields["wall_ns"])
                cpu = int(fields["process_cpu_ns"])
                rows.setdefault(
                    key, {
                        "samples": [], "run_samples": [], "run_sequences": [],
                        "totals": [], "oracles": [], "run_digests": [],
                    }
                )["totals"].append(
                    {"wall": wall, "process_cpu": cpu, "effective_cores": cpu / wall if wall else 0.0}
                )
                log_totals[case] = log_totals.get(case, 0) + 1
        selected_case = item.get("case", "all")
        expected_cases = set(seen_cases)
        if selected_case != "all" and expected_cases != {selected_case}:
            raise ValueError(
                f"{item['log']}: selected {selected_case!r}, emitted {sorted(expected_cases)}"
            )
        if not expected_cases:
            raise ValueError(f"{item['log']}: no PULSE_CASE records")
        case_sets.setdefault((system, program), set()).update(expected_cases)
        for case, expected_samples in seen_cases.items():
            samples = log_samples.get(case, [])
            if len(samples) != expected_samples:
                raise ValueError(
                    f"{item['log']}: {case} has {len(samples)}/{expected_samples} samples"
                )
            if log_totals.get(case, 0) != 1:
                raise ValueError(
                    f"{item['log']}: {case} has {log_totals.get(case, 0)} PULSE_TOTAL records"
                )
            if len(log_digests.get(case, set())) != 1:
                raise ValueError(f"{item['log']}: {case} sample digests differ")
            key = (system, program, case)
            rows[key]["run_samples"].append(samples)
            rows[key]["run_sequences"].append(int(item["sequence"]))
            rows[key]["run_digests"].append(next(iter(log_digests[case])))
            rows[key]['workers'].append(log_workers)

    for program in sorted(programs):
        reference: set[str] | None = None
        reference_system = ""
        for system in systems:
            current = case_sets.get((system, program))
            if current is None:
                raise ValueError(f"missing complete run family for {system}/{program}")
            if reference is None:
                reference = current
                reference_system = system
            elif current != reference:
                raise ValueError(
                    f"case matrix differs for {program}: "
                    f"{reference_system}={sorted(reference)}, {system}={sorted(current)}"
                )
    previously_unstable = {case for retry in manifest.get("retry_history", []) for case in retry["cases"]}
    for (system, program, case), row in rows.items():
        row["prior_instability"] = f"{program}/{case}" in previously_unstable
        if len(set(row["run_sequences"])) != len(row["run_sequences"]):
            raise ValueError(f"duplicate process sequence for {system}/{program}/{case}")
        if len(set(row["oracles"])) != 1:
            raise ValueError(f"semantic oracle varies between processes: {system}/{program}/{case}")
        if len(row["run_samples"]) != repeats:
            raise ValueError(
                f"incomplete process matrix for {system}/{program}/{case}: "
                f"{len(row['run_samples'])}/{repeats}"
            )
        if row["bodies"] and (len(row["bodies"]) != repeats or len(set(row["body_offsets"])) != 1):
            raise ValueError(f"body identity varies between processes: {system}/{program}/{case}")
        if row['work_bodies'] and (len(row['work_bodies']) != repeats or len(set(row['work_body_offsets'])) != 1):
            raise ValueError(f"worker code identity varies between processes: {system}/{program}/{case}")
        if len(row["totals"]) != repeats or len(row["oracles"]) != repeats:
            raise ValueError(
                f"incomplete totals/oracles for {system}/{program}/{case}: "
                f"totals={len(row['totals'])} oracles={len(row['oracles'])} expected={repeats}"
            )
    return rows, manifest


def report_system_roles(systems: list[str]) -> tuple[str, str]:
    families: list[str] = []
    for system in systems:
        family = (
            system[:-1]
            if system[-1:].isdigit() and system[:-1] in systems
            else system
        )
        if family not in families:
            families.append(family)
    if len(systems) > 2 and len(families) < len(systems):
        return families[0], families[-1]
    baseline = (
        "moon-baseline"
        if "moon-baseline" in systems
        else "delphi"
        if "delphi" in systems
        else "moon-default"
        if "moon-default" in systems
        else systems[0]
    )
    candidate = (
        "moon-candidate"
        if "moon-candidate" in systems
        else "moon"
        if "moon" in systems
        else systems[-1]
    )
    return baseline, candidate


def write_report(result: Path, accept_drift: bool = False) -> None:
    rows, manifest = collect(result)
    accept_drift = accept_drift or bool(manifest.get("persistent_drift_accepted"))
    systems = list(manifest["systems"])
    baseline, candidate = report_system_roles(systems)
    families = {}
    if len(comparison_pairs(systems)) > 1:
        import stand_compare
        family_cases, _, _ = stand_compare.collect_systems(result, (rows, manifest))
        families = stand_compare.family_rows(family_cases, baseline, candidate,
                                             paired=bool(manifest.get("measurement_method")))
    control = (
        "moon-default"
        if "delphi" in systems and "moon-default" in systems
        else None
    )
    cases = sorted({(program, case) for _, program, case in rows})
    details: dict[str, object] = {}
    markdown = [
        "# MoonCompiler Pulse result",
        "",
        f"Mode: `{manifest['mode']}`. Baseline: `{baseline}`. Candidate: `{candidate}`.",
        "",
        "Primary same-machine metric is actual scheduled thread cycles/op for single-thread cases;",
        "TSC ticks/op is used for multi-thread cases where one thread's cycle counter is incomplete.",
        "TSC is also used explicitly when scheduled thread cycles are unavailable for either system.",
        "",
        f"| Program | Case | Layer | Oracle | Metric | {baseline} median/mean/max | {candidate} median/mean/max | Candidate/baseline | Control/op | MM effect |",
        "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    oracle_failures: list[str] = []
    drift_failures: list[str] = []
    drift_failure_cases: set[tuple[str, str]] = set()
    drift_notes: list[str] = []
    program_ratios: dict[str, list[float]] = {}
    layer_ratios: dict[str, list[float]] = {}
    mm_program_ratios: dict[str, list[float]] = {}
    ranked_ratios: list[tuple[float, str]] = []
    for program, case in cases:
        comparison_drift: list[str] = []
        mm_drift: list[str] = []
        base = rows.get((baseline, program, case))
        cand = rows.get((candidate, program, case))
        if base is None or cand is None:
            raise ValueError(
                f"incomplete comparison for {program}/{case}: "
                f"baseline={base is not None} candidate={cand is not None}"
            )
        control_row = rows.get((control, program, case)) if control else None
        diagnostic = diagnostic_layer(str(base.get("layer", "")))
        metric_rows = [base, cand]
        if control_row is not None:
            metric_rows.append(control_row)
        family = families.get(f"{program}/{case}")
        primary_metric = family["metric"] if family is not None else select_primary_metric(program, metric_rows)
        try:
            base_primary, _ = process_balanced_stats(base, primary_metric)
            cand_primary, _ = process_balanced_stats(cand, primary_metric)
            base_tsc, _ = process_balanced_stats(base, "tsc")
            cand_tsc, _ = process_balanced_stats(cand, "tsc")
        except ValueError as error:
            raise ValueError(f"{program}/{case}: {error}") from error
        base_cycles = process_balanced_cycles(base)
        cand_cycles = process_balanced_cycles(cand)
        base_cores = effective_core_stats(base)
        cand_cores = effective_core_stats(cand)
        paired_ratio = None
        # Placement families use the same estimator as the family gate below.
        if baseline != candidate and len(systems) <= 3 and (manifest.get("measurement_method") or use_paired_process_ratios(program, primary_metric)):
            try:
                paired_ratio = paired_ratio_stats(base, cand, primary_metric)
            except ValueError as error:
                message = (
                    f"paired/{program}/{case} unavailable ({error}); "
                    "using process-balanced diagnostic ratio"
                )
                drift_notes.append(message)
                comparison_drift.append(message)
                if not diagnostic:
                    drift_failures.append(message)
                    drift_failure_cases.add((program, case))
        ratio = (
            paired_ratio.mode
            if paired_ratio is not None
            else cand_primary.mode / base_primary.mode
        )
        base_oracles = sorted(set(base["oracles"]))
        cand_oracles = sorted(set(cand["oracles"]))
        oracle_status = "MATCH" if base_oracles == cand_oracles else "DIFF"
        if oracle_status != "MATCH":
            oracle_failures.append(f"{program}/{case}")
        if paired_ratio is not None:
            if paired_ratio.minimum > 0:
                drift = paired_ratio.maximum / paired_ratio.minimum
                if drift > 1.15:
                    message = f"paired/{program}/{case} ratio drift {drift:.3f}x"
                    if diagnostic:
                        drift_notes.append(message)
                        comparison_drift.append(message)
                    else:
                        drift_failures.append(message)
                        drift_failure_cases.add((program, case))
                        comparison_drift.append(message)
        elif not families:
            for system, process_stats in (
                (baseline, base_primary),
                (candidate, cand_primary),
            ):
                if process_stats.minimum > 0:
                    drift = process_stats.maximum / process_stats.minimum
                    if drift > 1.15:
                        message = (
                            f"{system}/{program}/{case} process drift {drift:.3f}x"
                        )
                        if not diagnostic:
                            drift_failures.append(message)
                            drift_failure_cases.add((program, case))
                        comparison_drift.append(message)
        control_primary = None
        mm_effect = None
        paired_mm_effect = None
        if control_row is not None:
            try:
                control_primary, _ = process_balanced_stats(
                    control_row, primary_metric
                )
            except ValueError as error:
                raise ValueError(f"{control}/{program}/{case}: {error}") from error
            if control != candidate and (manifest.get("measurement_method") or use_paired_process_ratios(program, primary_metric)):
                try:
                    paired_mm_effect = paired_ratio_stats(
                        control_row, cand, primary_metric
                    )
                except ValueError as error:
                    message = (
                        f"paired-mm/{program}/{case} unavailable ({error}); "
                        "using process-balanced diagnostic ratio"
                    )
                    drift_notes.append(message)
                    mm_drift.append(message)
                if paired_mm_effect is not None and paired_mm_effect.minimum > 0:
                    drift = paired_mm_effect.maximum / paired_mm_effect.minimum
                    if drift > 1.15:
                        message = (
                            f"paired-mm/{program}/{case} ratio drift {drift:.3f}x"
                        )
                        drift_notes.append(message)
                        mm_drift.append(message)
            elif control_primary.minimum > 0:
                drift = control_primary.maximum / control_primary.minimum
                if drift > 1.15:
                    message = (
                        f"{control}/{program}/{case} process drift {drift:.3f}x"
                    )
                    drift_failures.append(message)
                    drift_failure_cases.add((program, case))
                    mm_drift.append(message)
            mm_effect = (
                paired_mm_effect.mode
                if paired_mm_effect is not None
                else cand_primary.mode / control_primary.mode
            )
        if family is not None:
            ratio = family["ratio"]
            if family["verdict"] in ("UNRESOLVED", "PLACEMENT-DEPENDENT"):
                message = f"{program}/{case}: {family['verdict']} " + "; ".join(family["issues"])
                comparison_drift.append(message)
                if not diagnostic:
                    drift_failures.append(message)
                    drift_failure_cases.add((program, case))
        elif max(sample_spread(base, primary_metric), sample_spread(cand, primary_metric)) > 1.15:
            message = f"{program}/{case}: broad within-process timing variation"
            comparison_drift.append(message)
            if not diagnostic:
                drift_failures.append(message)
                drift_failure_cases.add((program, case))
        if family is None and (base["prior_instability"] or cand["prior_instability"]):
            message = f"{program}/{case}: prior unstable timing remains in retry history"
            comparison_drift.append(message)
            if not diagnostic:
                drift_failures.append(message)
                drift_failure_cases.add((program, case))
        comparison_stable = not comparison_drift
        mm_stable = comparison_stable and not mm_drift
        for message in comparison_drift + mm_drift:
            if message not in drift_notes:
                drift_notes.append(message)
        if comparison_stable and not diagnostic:
            program_ratios.setdefault(program, []).append(ratio)
            for layer in str(base.get("layer", "")).split("+"):
                layer_ratios.setdefault(layer, []).append(ratio)
            ranked_ratios.append((ratio, f"{program}/{case}"))
        if mm_effect is not None and mm_stable and not diagnostic:
            mm_program_ratios.setdefault(program, []).append(mm_effect)
        ratio_text = f"{ratio:.3f}" if comparison_stable else f"DRIFT ({ratio:.3f})"
        mm_effect_text = (
            f"{mm_effect:.3f}"
            if mm_effect is not None and mm_stable
            else f"DRIFT ({mm_effect:.3f})"
            if mm_effect is not None
            else "0.000"
        )
        markdown.append(
            f"| {program} | {case} | {base.get('layer', '')} | {oracle_status} | "
            f"{primary_metric} | {base_primary.mode:.3f}/{base_primary.mean:.3f}/{base_primary.maximum:.3f} | "
            f"{cand_primary.mode:.3f}/{cand_primary.mean:.3f}/{cand_primary.maximum:.3f} | {ratio_text} | "
            f"{control_primary.mode if control_primary else 0.0:.3f} | "
            f"{mm_effect_text} |"
        )
        details[f"{program}/{case}"] = {
            "family": family,
            "scope": "diagnostic" if diagnostic else "product",
            "layer": base.get("layer"),
            "unit": base.get("unit"),
            "primary_metric": primary_metric,
            "oracle_status": oracle_status,
            "oracles": {baseline: base_oracles, candidate: cand_oracles},
            baseline: {"tsc": asdict(base_tsc), "cycles": asdict(base_cycles) if base_cycles else None},
            candidate: {"tsc": asdict(cand_tsc), "cycles": asdict(cand_cycles) if cand_cycles else None},
            "comparison_status": "STABLE" if comparison_stable else "DRIFT",
            "candidate_over_baseline": ratio if comparison_stable else None,
            "diagnostic_candidate_over_baseline": ratio,
            "paired_candidate_over_baseline": (
                asdict(paired_ratio) if paired_ratio is not None else None
            ),
            "mm_status": "STABLE" if mm_stable else "DRIFT",
            "moon_mm_over_moon_default": (
                mm_effect if mm_effect is not None and mm_stable else None
            ),
            "diagnostic_moon_mm_over_moon_default": mm_effect,
        }
        details[f"{program}/{case}"][baseline]["effective_cores"] = (
            asdict(base_cores) if base_cores else None
        )
        details[f"{program}/{case}"][candidate]["effective_cores"] = (
            asdict(cand_cores) if cand_cores else None
        )

    def geometric_mean(values: list[float]) -> float:
        return math.exp(statistics.mean(math.log(value) for value in values))

    def counts(values: list[float]) -> tuple[int, int, int]:
        faster = sum(value < 0.95 for value in values)
        parity = sum(0.95 <= value <= 1.05 for value in values)
        slower = sum(value > 1.05 for value in values)
        return faster, parity, slower

    summary = [
        "## Summary by Program",
        "",
        "`< 0.95` means faster, `0.95..1.05` is within 5%, and `> 1.05` means slower. "
        "Unresolved rows and diagnostic reference/calibration rows are excluded. "
        "For placement families the ratio uses all placements; the timing columns show the plain binaries.",
        "",
        "| Program | Cases | Geomean Moon/baseline | Faster | Within 5% | Slower | MM geomean |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for program in sorted(program_ratios):
        values = program_ratios[program]
        faster, parity, slower = counts(values)
        mm_values = mm_program_ratios.get(program, [])
        summary.append(
            f"| {program} | {len(values)} | {geometric_mean(values):.3f} | "
            f"{faster} | {parity} | {slower} | "
            f"{geometric_mean(mm_values) if mm_values else 0.0:.3f} |"
        )
    summary.extend([
        "",
        "## Summary by Physical Layer",
        "",
        "| Layer | Cases | Geomean Moon/baseline | Faster | Within 5% | Slower |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    for layer in sorted(layer_ratios):
        values = layer_ratios[layer]
        faster, parity, slower = counts(values)
        summary.append(
            f"| {layer} | {len(values)} | {geometric_mean(values):.3f} | "
            f"{faster} | {parity} | {slower} |"
        )
    summary.extend(["", "## Extreme Results", "", "### 15 Fastest", ""])
    summary.extend(
        f"- `{name}`: `{ratio:.3f}x`" for ratio, name in sorted(ranked_ratios)[:15]
    )
    summary.extend(["", "### 15 Slowest", ""])
    summary.extend(
        f"- `{name}`: `{ratio:.3f}x`"
        for ratio, name in sorted(ranked_ratios, reverse=True)[:15]
    )
    if drift_notes:
        summary.extend([
            "## Excluded Unstable Measurements",
            "",
            "These cases remain semantic checks and retain diagnostic ratios in "
            "the table, but they are excluded from aggregates and rankings. "
            "Drift never replaces a semantic failure.",
            "",
        ])
        summary.extend(f"- `{note}`" for note in drift_notes)
    summary.extend(["", "## All Cases", ""])
    markdown = markdown[:8] + summary + markdown[8:]
    (result / "REPORT.md").write_text("\n".join(markdown) + "\n", encoding="utf-8")
    (result / "summary.json").write_text(
        json.dumps(details, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if oracle_failures:
        raise ValueError(f"semantic oracle differs: {', '.join(oracle_failures)}")
    if drift_failures and not accept_drift:
        raise UnstablePairsError(drift_failures, drift_failure_cases)


def retry_unstable(result: Path, accept_persistent_drift: bool = False) -> None:
    result = result.resolve()
    try:
        write_report(result)
    except UnstablePairsError as error:
        unstable_cases = set(error.cases)
        failure_message = str(error)
    else:
        print(f"PULSE_STABLE {result}")
        return

    manifest_path = result / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["mode"] == "quick":
        raise ValueError("targeted retry requires a medium or long per-case run")
    retry_history = manifest.setdefault("retry_history", [])
    if len(retry_history) >= MAX_TARGETED_RETRIES:
        if not accept_persistent_drift:
            raise ValueError(
                "persistent drift remains unproven after "
                f"{MAX_TARGETED_RETRIES} retries: "
                + ",".join(
                    f"{program}/{case}" for program, case in sorted(unstable_cases)
                )
            )
        manifest["persistent_drift_accepted"] = [
            f"{program}/{case}" for program, case in sorted(unstable_cases)
        ]
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        write_report(result, accept_drift=True)
        print(
            f"PULSE_RESULT {result} persistent_drift="
            f"{','.join(f'{program}/{case}' for program, case in sorted(unstable_cases))}"
        )
        return
    attempt = len(retry_history) + 1
    selected_runs = [
        run_record
        for run_record in manifest["runs"]
        if (run_record["program"], run_record["case"]) in unstable_cases
    ]
    expected_runs = len(unstable_cases) * len(manifest["systems"]) * (
        {"medium": 7, "long": 9}[manifest["mode"]]
    )
    if len(selected_runs) != expected_runs:
        raise ValueError(
            f"incomplete retry matrix: expected {expected_runs}, found {len(selected_runs)}"
        )

    replacements: list[dict[str, str]] = []
    for run_record in selected_runs:
        executable = ROOT / run_record["executable"]
        old_log = result / run_record["log"]
        retry_log = result / (
            f"{old_log.stem}-retry{attempt:02d}{old_log.suffix}"
        )
        print(
            f"RETRY sequence={run_record['sequence']} system={run_record['system']} "
            f"program={run_record['program']} mode={manifest['mode']} "
            f"case={run_record['case']}",
            flush=True,
        )
        try:
            reserved = tuple(manifest.get("execution_affinity", {}).get("reserved_cpus", []))
            completed, image_identity = run_fresh_image(
                executable, manifest["mode"], run_record["case"], reserved, run_record["executable_sha256"])
        except subprocess.CalledProcessError as process_error:
            retry_log.write_text(
                process_error.stdout or "", encoding="utf-8", newline="\n"
            )
            raise RuntimeError(
                f"benchmark retry failed; complete output is in {retry_log}"
            ) from process_error
        retry_log.write_text(completed.stdout, encoding="utf-8", newline="\n")
        if "PULSE_END" not in completed.stdout or "status=PASS" not in completed.stdout:
            raise RuntimeError(f"missing PASS terminal in {retry_log}")
        replacements.append({"old_log": old_log.name, "old_log_sha256": run_record.get("log_sha256", ""),
                             "new_log": retry_log.name})
        run_record["log"] = retry_log.name
        run_record["log_sha256"] = sha256(retry_log)
        run_record.update(image_identity)

    retry_history.append({
        "attempt": attempt,
        "created_unix": time.time(),
        "reason": failure_message,
        "cases": [f"{program}/{case}" for program, case in sorted(unstable_cases)],
        "replacements": replacements,
    })
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    try:
        write_report(result)
    except UnstablePairsError as error:
        if attempt < MAX_TARGETED_RETRIES:
            raise
        if not accept_persistent_drift:
            raise ValueError(
                "persistent drift remains unproven after "
                f"{attempt} retries: "
                + ",".join(f"{program}/{case}" for program, case in error.cases)
            ) from error
        manifest["persistent_drift_accepted"] = [
            f"{program}/{case}" for program, case in error.cases
        ]
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        write_report(result, accept_drift=True)
        print(
            "PULSE_PERSISTENT_DRIFT "
            + ",".join(f"{program}/{case}" for program, case in error.cases)
        )
    print(f"PULSE_RESULT {result}")


def stand_programs(include_moon_only: bool) -> list[str]:
    """Programs of a run in list order.  The default list leaves out the programs Delphi cannot
    build (MOON_ONLY_PROGRAMS); a stand whose systems are all Moon toolchains can run those too."""
    return [name for name in PROGRAMS if include_moon_only or name not in MOON_ONLY_PROGRAMS]


def split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def validate_program_systems(programs: list[str], systems: list[str]) -> None:
    moon_only = sorted(set(programs) & MOON_ONLY_PROGRAMS)
    if moon_only and set(systems) != set(EXTERNAL_MOON_SYSTEMS) and not set(systems) <= STAND_SYSTEMS.keys():
        raise ValueError(
            f"Moon-only repair programs {moon_only} require exactly "
            f"{list(EXTERNAL_MOON_SYSTEMS)} systems"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("--mode", choices=("quick", "medium", "long"), default="quick")
    run_parser.add_argument("--programs", default=",".join(DEFAULT_PROGRAMS))
    run_parser.add_argument(
        "--cases",
        default="",
        help="comma-separated program/case rows; medium or long only",
    )
    run_parser.add_argument(
        "--systems",
        default="delphi,moon,moon-default" if IS_WINDOWS else "moon,moon-default",
    )
    run_parser.add_argument("--moon-baseline-toolchain", type=Path)
    run_parser.add_argument("--moon-candidate-toolchain", type=Path)
    run_parser.add_argument("--moon-baseline-mm-source", type=Path)
    run_parser.add_argument("--moon-candidate-mm-source", type=Path)
    run_parser.add_argument("--moon-system-mm-source", action="append", default=[],
                            help="NAME=path: pin this MM source for the stand system NAME "
                                 "(an A/B of MM layouts over placement families; the "
                                 "system's moon-base.cfg must pin the same file)")
    run_parser.add_argument("--moon-baseline-option", action="append", default=[])
    run_parser.add_argument("--moon-candidate-option", action="append", default=[])
    run_parser.add_argument("--tag")
    run_parser.add_argument("--result-root", type=Path)
    run_parser.add_argument("--moon-system", action="append", default=[],
                            help="NAME=TOOLCHAIN: extra Moon system for the RTL profile stand")
    run_parser.add_argument("--moon-extra-option", action="append", default=[],
                            help="compiler option added to every Moon build (e.g. -gw3)")
    run_parser.add_argument("--moon-system-option", action="append", default=[],
                            help="NAME=OPTION: compiler option for one stand system (e.g. C1=-Fapulse_filler_1)")
    run_parser.add_argument(
        "--build-jobs",
        type=int,
        default=1,
        help="parallel independent benchmark builds; measurement remains serial",
    )
    programs_parser = sub.add_parser(
        "programs", help="print the comma-separated program list of a run")
    programs_parser.add_argument(
        "--all", action="store_true",
        help="include the Moon-only programs (legal when every system is a Moon toolchain)")
    report_parser = sub.add_parser("report")
    report_parser.add_argument("result", type=Path)
    retry_parser = sub.add_parser("retry")
    retry_parser.add_argument("result", type=Path)
    retry_parser.add_argument(
        "--accept-persistent-drift",
        action="store_true",
        help="explicitly keep correctness-only rows after retries prove no stable timing result",
    )
    args = parser.parse_args()
    if args.command == "programs":
        print(",".join(stand_programs(args.all)))
        return
    if args.command == "run":
        programs = split_csv(args.programs)
        selected_rows = set(split_csv(args.cases))
        if any("/" not in row for row in selected_rows):
            raise ValueError("--cases entries must be program/case")
        systems = split_csv(args.systems)
        for item in args.moon_system:
            name, _, path = item.partition("=")
            if not name or not path or name in SYSTEM_LABELS:
                raise ValueError(f"bad --moon-system {item}")
            STAND_SYSTEMS[name] = Path(path).resolve()
        STAND_EXTRA_OPTIONS.extend(args.moon_extra_option)
        unknown_programs = sorted(set(programs) - PROGRAMS.keys())
        unknown_systems = sorted(set(systems) - SYSTEM_LABELS.keys() - STAND_SYSTEMS.keys())
        if not IS_WINDOWS and "delphi" in systems:
            unknown_systems.append("delphi (Windows-only)")
        if unknown_programs or unknown_systems:
            raise ValueError(f"unknown programs={unknown_programs} systems={unknown_systems}")
        validate_program_systems(programs, systems)
        external_toolchains = {
            system: path.resolve()
            for system, path in (
                ("moon-baseline", args.moon_baseline_toolchain),
                ("moon-candidate", args.moon_candidate_toolchain),
            )
            if path is not None
        }
        external_toolchains.update(
            {system: path for system, path in STAND_SYSTEMS.items() if system in systems}
        )
        external_options = {
            "moon-baseline": args.moon_baseline_option,
            "moon-candidate": args.moon_candidate_option,
        }
        for item in args.moon_system_option:
            name, _, option = item.partition("=")
            if not name or not option or name not in STAND_SYSTEMS:
                raise ValueError(f"bad --moon-system-option {item}")
            external_options.setdefault(name, []).append(option)
        external_options = {
            system: options for system, options in external_options.items()
            if options
        }
        external_mm_sources = {
            system: path.resolve()
            for system, path in (
                ("moon-baseline", args.moon_baseline_mm_source),
                ("moon-candidate", args.moon_candidate_mm_source),
            )
            if path is not None
        }
        for item in args.moon_system_mm_source:
            name, _, path = item.partition("=")
            if not name or not path or name not in STAND_SYSTEMS:
                raise ValueError(f"bad --moon-system-mm-source {item}")
            external_mm_sources[name] = Path(path).resolve()
        selected_external = set(systems) & (set(EXTERNAL_MOON_SYSTEMS) | STAND_SYSTEMS.keys())
        if (selected_external & set(EXTERNAL_MOON_SYSTEMS)) and (selected_external & set(EXTERNAL_MOON_SYSTEMS)) != set(EXTERNAL_MOON_SYSTEMS):
            raise ValueError(
                "moon-baseline and moon-candidate must be selected together"
            )
        missing_toolchains = sorted(selected_external - external_toolchains.keys())
        unused_toolchains = sorted(external_toolchains.keys() - selected_external)
        if missing_toolchains or unused_toolchains:
            raise ValueError(
                f"missing external toolchains={missing_toolchains} "
                f"unused external toolchains={unused_toolchains}"
            )
        unused_options = sorted(external_options.keys() - selected_external)
        unused_mm_sources = sorted(external_mm_sources.keys() - selected_external)
        missing_mm_sources = sorted(
            system for system, path in external_mm_sources.items()
            if not path.is_file()
        )
        if unused_options or unused_mm_sources or missing_mm_sources:
            raise ValueError(
                f"unused external options={unused_options} "
                f"unused external MM sources={unused_mm_sources} "
                f"missing external MM sources={missing_mm_sources}"
            )
        tag = args.tag or time.strftime("%Y%m%d-%H%M%S") + f"-{args.mode}"
        run_suite(
            args.mode, programs, systems, tag,
            external_toolchains, external_mm_sources, external_options,
            args.result_root.resolve() if args.result_root is not None else None,
            args.build_jobs,
            selected_rows,
        )
    elif args.command == "report":
        write_report(args.result.resolve())
    else:
        retry_unstable(args.result, args.accept_persistent_drift)


if __name__ == "__main__":
    main()
