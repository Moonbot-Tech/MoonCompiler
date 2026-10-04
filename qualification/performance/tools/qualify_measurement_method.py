#!/usr/bin/env python3
"""Qualify the fast Pulse measurement method before it is used by Pulse.

The test pins the machine, checks TSC against the available work-cycle counter,
runs noisy cases as same-file A/A (original plus byte-for-byte copy) in fresh
processes, and proves that a known 3.125% work increase is visible. Settings are
restored in a finally block.
"""

from __future__ import annotations

import argparse
import bisect
import ctypes
import functools
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
import threading
import time
import traceback
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path


TOOLS = Path(__file__).resolve().parent
PERF = TOOLS.parent
ROOT = PERF.parents[1]
sys.path.insert(0, str(TOOLS))
import pulse  # noqa: E402
import code_placement  # noqa: E402


SINGLE_CASES = (
    ("repairs", "fp-runtime", "single-cpu"),
    ("repairs", "round-normal", "single-cpu"),
    ("repairs", "unicode-cow", "single-cpu"),
    ("repairs", "ring-64", "single-cpu"),
    ("repairs", "ring-256", "single-cpu"),
    ("repairs", "ring-1024", "single-cpu"),
    ("repairs", "utf8-decode", "single-cpu"),
    ("repairs", "utf8-raw", "single-cpu"),
    ("hot-rtl", "comparetext-equal-12", "single-cpu"),
    ("codegen", "dep-add", "single-cpu"),
    ("codegen", "generic-reverse-rec", "single-cpu"),
    ("codegen", "generic-reverse-int", "single-cpu"),
    ("codegen", "int32-mixed", "single-cpu"),
    ("codegen", "scan-dram", "memory"),
    ("move", "stream-a0-a0-n67108864", "memory"),
    ("mm", "realloc-shrink", "memory-manager"),
    ("mm", "fragmented-mixed", "fragmentation"),
)
MULTITHREAD_CASES = (
    ("threads", "thread-start-join-4", "multithread"),
    ("threads", "independent-cpu-1", "multithread"),
    ("threads", "independent-cpu-2", "multithread"),
    ("threads", "independent-cpu-4", "multithread"),
    ("threads", "independent-cpu-8", "multithread"),
    ("threads", "shared-read-4", "multithread"),
    ("threads", "locked-increment-4", "multithread"),
    ("threads", "false-sharing-4", "multithread"),
    ("threads", "padded-counters-4", "multithread"),
    ("threads", "parallel-alloc-free-1", "multithread"),
    ("threads", "parallel-alloc-free-2", "multithread"),
    ("threads", "parallel-alloc-free-4", "multithread"),
    ("threads", "parallel-alloc-free-8", "multithread"),
    ("threads", "parallel-alloc-free-96-4", "multithread"),
    ("threads", "parallel-alloc-free-96-8", "multithread"),
    ("threads", "cross-thread-free-4", "multithread"),
    ("threads", "producer-consumer", "multithread"),
    ("repairs", "padded-counters-4", "multithread"),
)
CASES_BY_SUITE = {
    "single": SINGLE_CASES,
    "multithread": MULTITHREAD_CASES,
}
CONTROL_SIGNATURES = {
    "nt": (bytes.fromhex("be400000006666660f1f840000000000"), 1),
    "posix": (bytes.fromhex("41bc400000006666660f1f840000000000"), 2),
}
CONTROL_FUNCTIONS = tuple(
    f"P$PULSE_REPAIRS_$$_{name}$LONGINT$$QWORD"
    for name in ("CASEMEAN4", "CASEMEANINT64_4", "CASEVARIANCE4", "CASESTDDEV4")
)
CONTROL_SECTION = re.compile(
    r"^\s*\d+\s+\S+\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+[0-9a-fA-F]+"
    r"\s+([0-9a-fA-F]+)\s+2\*\*\d+\s+(.+)$"
)
CONTROL_BASE_INNER_COUNT = 64
CONTROL_MORE_INNER_COUNT = 66
CONTROL_EXPECTED_EFFECT_PERCENT = (
    CONTROL_MORE_INNER_COUNT / CONTROL_BASE_INNER_COUNT - 1.0
) * 100.0
XPERF = Path(
    r"C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe"
)
POWER_SUBGROUP = "SUB_PROCESSOR"
POWER_SETTINGS = ("PROCTHROTTLEMIN", "PROCTHROTTLEMAX", "PERFBOOSTMODE")
PROCESS_REPEATS = 5
CREATE_SUSPENDED = 0x00000004
PROCESS_SET_INFORMATION = 0x0200
PROCESS_SUSPEND_RESUME = 0x0800
# Set per benchmark process by the runner; an inherited value must not leak in.
# PULSE_RAW_CONFIGS is not one: the operator selects the raw events of a run in
# the runner's own environment, and every process inherits them.
PROCESS_ENVIRONMENT = (
    "PULSE_ITERATIONS",
    "PULSE_ITERATION_COUNTS",
    "PULSE_START_FILE",
    "PULSE_READY_FILE",
    "PULSE_SIBLING_CPU",
    "PULSE_STACK_PHASE",
)
MINIMUM_SAMPLES_PER_PROCESS = 5
MINIMUM_SIBLING_IDLE_RATIO = 0.99
RUNNER_AFFINITY_LOCK = threading.Lock()
# What ran on a core just before a process sets its level (Sol 19: a
# PowerShell before main -> the slow aos level, 2 s of idle -> the fast one):
# no single-CPU process starts on a core that ran foreign work in the last
# MEASUREMENT_CORE_IDLE_SECONDS, or whose own last process ended less than
# MEASUREMENT_CORE_REST_SECONDS before, the core idle since.  The runner's own
# processes are not foreign: their CPU time is known and taken out of the window.
MEASUREMENT_CORE_IDLE_SECONDS = 2.0
MEASUREMENT_CORE_IDLE_RATIO = 0.95
MEASUREMENT_CORE_REST_SECONDS = 0.05
# The watch reads the idle of every CPU this often; a window starts at a read.
CORE_WATCH_INTERVAL_SECONDS = 0.01
# An idle read is 5-45 us between its TSC reads (p50-p99, 25.09): 400000 ticks
# (100 us at 4 GHz) keep a window's error under 0.05% of 100 ms.
IDLE_READ_TICKS = 400_000
# perf_clock.PerfChainCycles: the dependent adds behind chain_before/after.
CHAIN_CYCLES = 65536
# The unit of work_cycles_per_op as sample_metrics computes it: a result carries
# it, and its reports print the one it carries.
CPU_WORK_UNIT = (
    "process-cycles/op for multithread, core-cycles/op otherwise (thread cycles at the sample's chain clock)"
    if os.name == "nt"
    else "process-cpu-ns/op for multithread, hardware-cycles/op otherwise"
)


SHA256_CACHE: dict[tuple[str, int, int], str] = {}


def sha256(path: Path) -> str:
    """The file's SHA-256, read once per path, size and modification time: a
    Pulse image is hashed after every process that ran it, 15 MB each on Linux."""
    status = path.stat()
    key = (str(path), status.st_size, status.st_mtime_ns)
    cached = SHA256_CACHE.get(key)
    if cached is not None:
        return cached
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    SHA256_CACHE[key] = digest.hexdigest()
    return SHA256_CACHE[key]


def command(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        check=check,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def fields(line: str) -> dict[str, str]:
    return dict(part.split("=", 1) for part in line.split()[1:] if "=" in part)


def spread(values: list[float]) -> float:
    center = statistics.median(values)
    if center:
        return (max(values) - min(values)) / center * 100.0
    return 0.0 if max(values) == min(values) == 0.0 else 1e9


def relative_difference(left: list[float], right: list[float]) -> float:
    numerator = statistics.median(left)
    denominator = statistics.median(right)
    if denominator:
        return abs(numerator / denominator - 1.0) * 100.0
    return 0.0 if numerator == 0.0 else 1e9


def patch_negative_control(baseline: Path, more_work: Path) -> None:
    """Change one decoded inner-counter instruction in each of the four control functions."""
    original = baseline.read_bytes()
    data = bytearray(original)
    signature, immediate_offset = CONTROL_SIGNATURES[os.name]
    sections = []
    listing = command([code_placement.tool("objdump"), "-h", "-w", str(baseline)]).stdout
    for line in listing.splitlines():
        row = CONTROL_SECTION.match(line)
        if row and {"CODE", "CONTENTS"} <= set(row.group(4).split(", ")):
            size, begin, offset = (int(row.group(index), 16) for index in (1, 2, 3))
            sections.append((begin, begin + size, offset))
    functions = code_placement.procedures(baseline)
    patch_offsets = []
    for name in CONTROL_FUNCTIONS:
        ranges = [(begin, end) for symbol, begin, end in functions if symbol == name]
        if len(ranges) != 1:
            raise RuntimeError(f"negative-control function {name}: expected one range, found {len(ranges)}")
        begin, end = ranges[0]
        mappings = [offset - start for start, stop, offset in sections if start <= begin < end <= stop]
        if len(mappings) != 1:
            raise RuntimeError(f"negative-control function {name}: no unique code-section mapping")
        delta = mappings[0]
        listing = command([
            code_placement.tool("objdump"), "-d", "-M", "intel", "-w",
            f"--start-address=0x{begin:x}", f"--stop-address=0x{end:x}", str(baseline),
        ]).stdout
        offsets = [
            address + delta + immediate_offset
            for address, (_, _, raw) in code_placement.parse_instructions(listing).items()
            if begin <= address and address + len(signature) <= end
            and raw == signature[:immediate_offset + 4]
            and original[address + delta:address + delta + len(signature)] == signature
        ]
        if len(offsets) != 1:
            raise RuntimeError(f"negative-control function {name}: expected one counter, found {len(offsets)}")
        patch_offsets.extend(offsets)
    for offset in patch_offsets:
        data[offset] = CONTROL_MORE_INNER_COUNT
    more_work.write_bytes(data)
    shutil.copymode(baseline, more_work)
    modified = more_work.read_bytes()
    if len(original) != len(modified):
        raise RuntimeError("negative-control patch changed executable size")
    differences = [index for index, (left, right) in enumerate(zip(original, modified)) if left != right]
    if differences != sorted(patch_offsets):
        raise RuntimeError(f"negative-control patch differs at {differences}")


def build_images(
    toolchain: Path,
    control_toolchain: Path,
    output: Path,
    programs: tuple[str, ...],
    *,
    control_mm_source: Path,
) -> tuple[dict[str, Path], Path, Path]:
    system = "method-qualification"

    def build_program(program: str) -> tuple[str, Path]:
        return program, pulse.build_moon(
            program, False, system=system, toolchain=toolchain
        )

    built: dict[str, Path] = {}
    with ThreadPoolExecutor(max_workers=min(4, len(programs))) as executor:
        for program, executable in executor.map(build_program, programs):
            built[program] = executable

    copies = output / "byte-copies"
    copies.mkdir(parents=True, exist_ok=True)
    for program, executable in built.items():
        copied = copies / executable.name
        shutil.copyfile(executable, copied)
        shutil.copymode(executable, copied)
        if sha256(executable) != sha256(copied):
            raise RuntimeError(f"byte copy differs: {copied}")

    control = pulse.build_moon(
        "repairs",
        False,
        system="method-negative-control",
        toolchain=control_toolchain,
        mm_source=control_mm_source,
        extra_options=["-dPULSE_FILLER_3", "-gw3", "-Xs-"],
    )
    control_dir = output / "negative-control"
    control_dir.mkdir(parents=True, exist_ok=True)
    suffix = ".exe" if os.name == "nt" else ""
    baseline = control_dir / f"pulse_repairs_work64{suffix}"
    more_work = control_dir / f"pulse_repairs_work66{suffix}"
    shutil.copyfile(control, baseline)
    shutil.copymode(control, baseline)
    patch_negative_control(baseline, more_work)
    return built, baseline, more_work


def windows_power_query(scheme: str, setting: str) -> tuple[int, int]:
    output = command(["powercfg", "/q", scheme, POWER_SUBGROUP, setting]).stdout
    values = re.findall(r"0x([0-9a-fA-F]{8})", output)
    if len(values) < 2:
        raise RuntimeError(f"cannot read power setting {setting}")
    return int(values[-2], 16), int(values[-1], 16)


def windows_power_set(scheme: str, setting: str, ac: int, dc: int) -> None:
    command(["powercfg", "-setacvalueindex", scheme, POWER_SUBGROUP, setting, str(ac)])
    command(["powercfg", "-setdcvalueindex", scheme, POWER_SUBGROUP, setting, str(dc)])


@contextmanager
def windows_machine_settings() -> dict[str, object]:
    active = command(["powercfg", "/getactivescheme"]).stdout
    match = re.search(r"[0-9a-fA-F-]{36}", active)
    if not match:
        raise RuntimeError("cannot read active power scheme")
    scheme = match.group(0)
    boost_query = command(
        ["powercfg", "/q", scheme, POWER_SUBGROUP, "PERFBOOSTMODE"]
    ).stdout
    boost_hidden = "PERFBOOSTMODE" not in boost_query
    if boost_hidden:
        command(["powercfg", "-attributes", POWER_SUBGROUP, "PERFBOOSTMODE", "-ATTRIB_HIDE"])
    saved = {setting: windows_power_query(scheme, setting) for setting in POWER_SETTINGS}
    state = {"scheme": scheme, "saved": saved, "boost_was_hidden": boost_hidden}
    try:
        windows_power_set(scheme, "PROCTHROTTLEMIN", 100, 100)
        windows_power_set(scheme, "PROCTHROTTLEMAX", 100, 100)
        windows_power_set(scheme, "PERFBOOSTMODE", 0, 0)
        command(["powercfg", "-setactive", scheme])
        yield state
    finally:
        for setting, (ac, dc) in saved.items():
            windows_power_set(scheme, setting, ac, dc)
        command(["powercfg", "-setactive", scheme])
        if boost_hidden:
            command(["powercfg", "-attributes", POWER_SUBGROUP, "PERFBOOSTMODE", "+ATTRIB_HIDE"])


def linux_write(path: Path, value: str) -> None:
    completed = subprocess.run(
        ["sudo", "-n", "tee", str(path)],
        input=value + "\n",
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if completed.returncode:
        raise RuntimeError(f"cannot write {path}: {completed.stdout.strip()}")


@contextmanager
def linux_machine_settings() -> dict[str, object]:
    command(["sudo", "-n", "true"])
    paths = [Path("/proc/sys/kernel/perf_event_paranoid")]
    optional = (
        Path("/sys/devices/system/cpu/intel_pstate/no_turbo"),
        Path("/sys/devices/system/cpu/intel_pstate/min_perf_pct"),
        Path("/sys/devices/system/cpu/intel_pstate/max_perf_pct"),
    )
    paths.extend(path for path in optional if path.exists())
    governors = sorted(Path("/sys/devices/system/cpu/cpufreq").glob("policy*/scaling_governor"))
    paths.extend(governors)
    saved = {str(path): path.read_text(encoding="ascii").strip() for path in paths}
    state = {"saved": saved}
    try:
        linux_write(Path("/proc/sys/kernel/perf_event_paranoid"), "1")
        for path in governors:
            linux_write(path, "performance")
        for path, value in (
            (Path("/sys/devices/system/cpu/intel_pstate/no_turbo"), "1"),
            (Path("/sys/devices/system/cpu/intel_pstate/min_perf_pct"), "100"),
            (Path("/sys/devices/system/cpu/intel_pstate/max_perf_pct"), "100"),
        ):
            if path.exists():
                linux_write(path, value)
        yield state
    finally:
        for name, value in reversed(list(saved.items())):
            linux_write(Path(name), value)


def cpu_list(text: str) -> set[int]:
    """The CPUs of a sysfs list such as 0-15,32."""
    cpus: set[int] = set()
    for part in text.strip().split(","):
        if "-" in part:
            first, last = map(int, part.split("-", 1))
            cpus.update(range(first, last + 1))
        elif part:
            cpus.add(int(part))
    return cpus


def linux_measurement_cpus() -> set[int]:
    """The CPUs a Pulse process may be measured on.  On a hybrid CPU (Raptor
    Lake: cpu_core and cpu_atom PMUs) only the big cores: the harness's cycle
    counter is the cpu_core PMU's, on an E-core it never runs (running = 0), and
    the two kinds of core do not give one cost of one code."""
    allowed = os.sched_getaffinity(0)
    big = Path("/sys/devices/cpu_core/cpus")
    small = Path("/sys/devices/cpu_atom/cpus")
    if big.is_file() and small.is_file() and cpu_list(small.read_text()):
        allowed = allowed & cpu_list(big.read_text())
    return allowed


def linux_physical_cpus(limit: int | None = 9) -> tuple[int, ...]:
    allowed = linux_measurement_cpus()
    identities: set[tuple[int, int]] = set()
    selected: list[int] = []
    for cpu in sorted(allowed):
        topology = Path(f"/sys/devices/system/cpu/cpu{cpu}/topology")
        package = int((topology / "physical_package_id").read_text())
        core = int((topology / "core_id").read_text())
        identity = package, core
        if identity in identities:
            continue
        identities.add(identity)
        selected.append(cpu)
        if limit is not None and len(selected) == limit:
            break
    if limit is not None and len(selected) < limit:
        raise RuntimeError(f"need {limit} physical CPUs, found {selected}")
    return tuple(selected)


def windows_physical_cpus(limit: int | None = 9) -> tuple[int, ...]:
    relation_processor_core = 0
    length = ctypes.c_ulong(0)
    kernel32 = ctypes.windll.kernel32
    kernel32.GetLogicalProcessorInformationEx(
        relation_processor_core, None, ctypes.byref(length)
    )
    buffer = ctypes.create_string_buffer(length.value)
    if not kernel32.GetLogicalProcessorInformationEx(
        relation_processor_core, buffer, ctypes.byref(length)
    ):
        raise ctypes.WinError()
    cores: list[list[int]] = []
    offset = 0
    pointer_size = ctypes.sizeof(ctypes.c_size_t)
    while offset < length.value:
        size = int.from_bytes(buffer[offset + 4 : offset + 8], "little")
        group_count = int.from_bytes(buffer[offset + 30 : offset + 32], "little")
        if group_count != 1:
            raise RuntimeError("processor groups are unsupported by this Pulse probe")
        mask = int.from_bytes(buffer[offset + 32 : offset + 32 + pointer_size], "little")
        group = int.from_bytes(
            buffer[offset + 32 + pointer_size : offset + 34 + pointer_size], "little"
        )
        if group != 0 or mask == 0:
            raise RuntimeError("unexpected Windows processor-group topology")
        cores.append([cpu for cpu in range(pointer_size * 8) if mask & (1 << cpu)])
        offset += size
    # Only the cores the process may run on, as taskset gives them on Linux:
    # started under a mask, Pulse measures inside it.
    allowed = windows_allowed_cpus()
    selected = [
        next(cpu for cpu in core if cpu in allowed)
        for core in cores
        if any(cpu in allowed for cpu in core)
    ]
    if not selected:
        raise RuntimeError("no physical CPUs found")
    return tuple(selected if limit is None else selected[:limit])


def windows_allowed_cpus() -> set[int]:
    """The CPUs of this process's affinity mask."""
    kernel32 = ctypes.windll.kernel32
    kernel32.GetCurrentProcess.restype = ctypes.c_void_p
    kernel32.GetProcessAffinityMask.argtypes = [
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_size_t),
        ctypes.POINTER(ctypes.c_size_t),
    ]
    mask = ctypes.c_size_t()
    system = ctypes.c_size_t()
    if not kernel32.GetProcessAffinityMask(
        kernel32.GetCurrentProcess(), ctypes.byref(mask), ctypes.byref(system)
    ):
        raise ctypes.WinError()
    return {cpu for cpu in range(ctypes.sizeof(ctypes.c_size_t) * 8) if mask.value & (1 << cpu)}


def processor_sibling(cpu: int) -> int | None:
    if os.name == "nt":
        relation_processor_core = 0
        length = ctypes.c_ulong(0)
        kernel32 = ctypes.windll.kernel32
        kernel32.GetLogicalProcessorInformationEx(
            relation_processor_core, None, ctypes.byref(length)
        )
        buffer = ctypes.create_string_buffer(length.value)
        if not kernel32.GetLogicalProcessorInformationEx(
            relation_processor_core, buffer, ctypes.byref(length)
        ):
            raise ctypes.WinError()
        offset = 0
        pointer_size = ctypes.sizeof(ctypes.c_size_t)
        while offset < length.value:
            size = int.from_bytes(buffer[offset + 4 : offset + 8], "little")
            mask = int.from_bytes(buffer[offset + 32 : offset + 32 + pointer_size], "little")
            siblings = [index for index in range(pointer_size * 8) if mask & (1 << index)]
            if cpu in siblings:
                return next((index for index in siblings if index != cpu), None)
            offset += size
        raise RuntimeError(f"logical CPU {cpu} is missing from Windows topology")
    siblings_path = Path(
        f"/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list"
    )
    siblings: list[int] = []
    for part in siblings_path.read_text().strip().split(","):
        if "-" in part:
            first, last = map(int, part.split("-", 1))
            siblings.extend(range(first, last + 1))
        else:
            siblings.append(int(part))
    return next((index for index in siblings if index != cpu), None)


def read_processor_idle_cycles(cpu: int) -> int:
    """Idle of a logical CPU so far: Windows counts it in TSC ticks
    (QueryIdleProcessorCycleTime), Linux in clock ticks (/proc/stat idle plus
    iowait, as the harness reads its sibling)."""
    if os.name == "nt":
        kernel32 = ctypes.windll.kernel32
        buffer_length = ctypes.c_ulong(64 * 8)
        buffer = (ctypes.c_uint64 * 64)()
        if not kernel32.QueryIdleProcessorCycleTime(
            ctypes.byref(buffer_length), ctypes.byref(buffer)
        ):
            raise ctypes.WinError()
        count = buffer_length.value // 8
        if cpu >= count:
            raise RuntimeError(f"CPU {cpu} out of range (max {count - 1})")
        return int(buffer[cpu])
    with open("/proc/stat", encoding="ascii") as stream:
        for line in stream:
            if line.startswith(f"cpu{cpu} "):
                # cpuN user nice system idle iowait irq softirq ...
                counters = line.split()
                return int(counters[4]) + int(counters[5])
    raise RuntimeError(f"CPU {cpu} not found in /proc/stat")


@functools.cache
def tsc_reader() -> Callable[[], int]:
    """rdtscp; shl rdx, 32; or rax, rdx; ret: the TSC now, read by the runner."""
    kernel32 = ctypes.windll.kernel32
    kernel32.VirtualAlloc.restype = ctypes.c_void_p
    kernel32.VirtualAlloc.argtypes = [
        ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_uint32
    ]
    code = bytes.fromhex("0f01f9" "48c1e220" "4809d0" "c3")
    memory = kernel32.VirtualAlloc(None, len(code), 0x3000, 0x40)
    if not memory:
        raise ctypes.WinError()
    ctypes.memmove(memory, code, len(code))
    return ctypes.CFUNCTYPE(ctypes.c_uint64)(memory)


def idle_mark(cpu: int) -> tuple[int, float]:
    """(idle of `cpu`, the clock that idle is counted in) now.  Windows: a runner
    preempted between its TSC read and the idle query shifts the window by the
    gap (up to 2.4 ms seen on a loaded CPU): the query sits between two TSC reads
    at most IDLE_READ_TICKS apart, their midpoint is its clock."""
    if os.name != "nt":
        return read_processor_idle_cycles(cpu), time.monotonic() * os.sysconf("SC_CLK_TCK")
    tsc = tsc_reader()
    while True:
        before = tsc()
        idle = read_processor_idle_cycles(cpu)
        after = tsc()
        if after - before <= IDLE_READ_TICKS:
            return idle, (before + after) / 2


def idle_since(cpu: int, mark: tuple[int, float]) -> list[float]:
    """[idle, elapsed] of `cpu` since `mark`, both in that clock."""
    idle, clock = idle_mark(cpu)
    return [idle - mark[0], clock - mark[1]]


def idle_enough(window: list[float] | None, minimum: float) -> bool:
    """`window` idle for at least `minimum` of it.  Linux moves idle in whole
    clock ticks: one tick of the window is not held against it."""
    if window is None:
        return True
    idle, elapsed = window
    return elapsed > 0 and idle + (0 if os.name == "nt" else 1) >= minimum * elapsed


def read_all_idle() -> dict[int, int]:
    """The idle of every logical CPU in one read, in the units of
    read_processor_idle_cycles."""
    if os.name == "nt":
        kernel32 = ctypes.windll.kernel32
        buffer_length = ctypes.c_ulong(64 * 8)
        buffer = (ctypes.c_uint64 * 64)()
        if not kernel32.QueryIdleProcessorCycleTime(
            ctypes.byref(buffer_length), ctypes.byref(buffer)
        ):
            raise ctypes.WinError()
        return {cpu: int(buffer[cpu]) for cpu in range(buffer_length.value // 8)}
    idle: dict[int, int] = {}
    with open("/proc/stat", encoding="ascii") as stream:
        for line in stream:
            if line.startswith("cpu") and line[3].isdigit():
                counters = line.split()
                idle[int(counters[0][3:])] = int(counters[4]) + int(counters[5])
            elif idle:
                break
    return idle


def all_idle_mark() -> tuple[float, float, dict[int, int]]:
    """(perf_counter seconds, idle clock, idle of every CPU) now; the idle clock
    as idle_mark keeps it."""
    if os.name != "nt":
        seconds = time.monotonic()
        return seconds, seconds * os.sysconf("SC_CLK_TCK"), read_all_idle()
    tsc = tsc_reader()
    while True:
        before = tsc()
        idle = read_all_idle()
        after = tsc()
        if after - before <= IDLE_READ_TICKS:
            return time.monotonic(), (before + after) / 2, idle


class CoreWatch:
    """What ran on each measurement core before a process: the idle of every CPU,
    read every CORE_WATCH_INTERVAL_SECONDS, and the runner's own processes on the
    core, each with the CPU time it spent there.

    A process may start on a core when (1) the last `rest` seconds before it held
    no own process and the core idle, and (2) the window of
    MEASUREMENT_CORE_IDLE_SECONDS before it held no foreign work: its busy time
    less the CPU time of the own processes inside it is within 1 - ratio of it.
    The window starts at a read no later than the horizon before the process and
    never inside an own process, which then lies whole inside or outside it.
    That is the 2 s watch of every process without a 2 s sleep before each: the
    same foreign work before a process is seen, and the sleep after the runner's
    own process is the rest, not the horizon.  Idle and CPU time are in the OS
    clock of idle_mark (TSC ticks on Windows, clock ticks on Linux)."""

    def __init__(
        self,
        horizon: float | None = None,
        interval: float | None = None,
        reader: Callable[[], tuple[float, float, dict[int, int]]] | None = None,
        sleeper: Callable[[float], None] | None = None,
    ) -> None:
        self.horizon = MEASUREMENT_CORE_IDLE_SECONDS if horizon is None else horizon
        self.interval = CORE_WATCH_INTERVAL_SECONDS if interval is None else interval
        self.reader = reader or all_idle_mark
        self.sleeper = sleeper or time.sleep
        self.lock = threading.Lock()
        self.reads: list[tuple[float, float, dict[int, int]]] = []
        # cpu -> [(start read, end read, own CPU time)] of the runner's processes
        self.own: dict[int, list[tuple[tuple[float, float, int], tuple[float, float, int], float]]] = {}
        self.thread: threading.Thread | None = None

    def sample(self) -> tuple[float, float, dict[int, int]]:
        read = self.reader()
        with self.lock:
            # Two threads may read in one order and store in the other.
            bisect.insort(self.reads, read, key=lambda item: item[0])
            keep = self.reads[-1][0] - self.horizon - 1.0
            while len(self.reads) > 2 and self.reads[1][0] <= keep:
                self.reads.pop(0)
        return read

    def ensure_started(self) -> None:
        with self.lock:
            if self.thread is not None:
                return
            self.thread = threading.Thread(target=self.run, name="pulse-core-watch", daemon=True)
            self.thread.start()

    def run(self) -> None:
        while True:
            self.sample()
            self.sleeper(self.interval)

    def mark(self, cpu: int) -> tuple[float, float, int]:
        seconds, clock, idle = self.sample()
        return seconds, clock, idle[cpu]

    def history(self, cpu: int) -> tuple[list[tuple[float, float, int]], list[tuple]]:
        """The watch's reads of `cpu` and its own processes, oldest first."""
        with self.lock:
            reads = [(seconds, clock, idle[cpu]) for seconds, clock, idle in self.reads if cpu in idle]
            spans = list(self.own.get(cpu, ()))
        return reads, spans

    def window(self, cpu: int, now: tuple[float, float, int]) -> dict[str, float] | None:
        """The horizon before `now` on `cpu`: from the latest read at least the
        horizon back, or from the start of the own process that read falls in.
        None while the watch has not read that far back."""
        reads, spans = self.history(cpu)
        starts = [read for read in reads if read[0] <= now[0] - self.horizon]
        if not starts:
            return None
        start = starts[-1]
        for began, ended, _ in spans:
            if began[0] < start[0] < ended[0]:
                start = began
        own = sum(busy for began, ended, busy in spans if began[0] >= start[0] and ended[0] <= now[0])
        elapsed = now[1] - start[1]
        idle = now[2] - start[2]
        return {
            "seconds": now[0] - start[0],
            "elapsed": elapsed,
            "idle": idle,
            "own": own,
            "foreign": elapsed - idle - own,
        }

    def rest_window(self, cpu: int, now: tuple[float, float, int], rest: float) -> list[float] | None:
        """[idle, elapsed, seconds] of the last `rest` before `now`: from the latest
        read at least `rest` back, or from the end of the core's own last process
        when that is later.  None while the own process is nearer than `rest`."""
        reads, spans = self.history(cpu)
        if spans and spans[-1][1][0] > now[0] - rest:
            return None
        starts = [read for read in reads if read[0] <= now[0] - rest]
        start = starts[-1] if starts else None
        if spans and (start is None or spans[-1][1][0] > start[0]):
            start = spans[-1][1]
        if start is None:
            return None
        return [now[2] - start[2], now[1] - start[1], now[0] - start[0]]

    def quiet(self, cpu: int, sibling: int | None) -> bool:
        """Whether `cpu` is clean at the watch's last read: no foreign work in the
        horizon before it and, over the last second, its SMT sibling idle.  A
        hint for choosing among cores; `before` and the records still judge
        every process.  True while the watch knows nothing yet."""
        reads, _ = self.history(cpu)
        if not reads:
            return True
        window = self.window(cpu, reads[-1])
        if window is not None and not idle_enough(
                [window["elapsed"] - max(0.0, window["foreign"]), window["elapsed"]], MEASUREMENT_CORE_IDLE_RATIO):
            return False
        if sibling is None:
            return True
        reads, _ = self.history(sibling)
        starts = [read for read in reads if read[0] <= reads[-1][0] - 1.0] if reads else []
        if not starts:
            return True
        return idle_enough([reads[-1][2] - starts[-1][2], reads[-1][1] - starts[-1][1]], MINIMUM_SIBLING_IDLE_RATIO)

    def before(self, cpu: int, rest: float | None = None) -> dict[str, object]:
        """Wait until a process may start on `cpu`; the runner fields of that
        decision.  A core that stays busy is not waited for longer than the
        horizon after the rest: the process then starts and its record carries
        the dirty window, which rejects it."""
        rest = MEASUREMENT_CORE_REST_SECONDS if rest is None else rest
        self.ensure_started()
        started = None
        while True:
            now = self.mark(cpu)
            started = now[0] if started is None else started
            _, spans = self.history(cpu)
            wait = rest - (now[0] - spans[-1][1][0]) if spans else 0.0
            if wait > 0:
                self.sleeper(max(self.interval, min(wait, self.horizon)))
                continue
            window = self.window(cpu, now)
            rested = self.rest_window(cpu, now, rest) if rest > 0 else None
            if window is None or (rest > 0 and rested is None):
                self.sleeper(self.interval)
                continue
            foreign = max(0.0, window["foreign"])
            result: dict[str, object] = {
                "core_idle": [window["elapsed"] - foreign, window["elapsed"]],
                "core_window": window,
            }
            if rested is not None:
                result["core_rest"] = rested[:2]
                result["core_rest_seconds"] = rested[2]
            clean = idle_enough(result["core_idle"], MEASUREMENT_CORE_IDLE_RATIO) and idle_enough(
                result.get("core_rest"), MEASUREMENT_CORE_IDLE_RATIO)
            if clean or now[0] - started >= self.horizon + rest + 1.0:
                return result
            self.sleeper(self.interval)

    def after(self, cpu: int, began: tuple[float, float, int], busy: float) -> None:
        """An own process ran on `cpu` from `began` to now using `busy` CPU time."""
        ended = self.mark(cpu)
        with self.lock:
            spans = self.own.setdefault(cpu, [])
            spans.append((began, ended, busy))
            keep = ended[0] - self.horizon - 1.0
            while len(spans) > 1 and spans[0][1][0] <= keep:
                spans.pop(0)


CORE_WATCH = CoreWatch()


def keep_runner_off(cpu: int) -> None:
    """The runner never runs on a measurement core or on its SMT sibling."""
    banned = {cpu}
    sibling = processor_sibling(cpu)
    if sibling is not None:
        banned.add(sibling)
    with RUNNER_AFFINITY_LOCK:
        if os.name == "nt":
            kernel32 = ctypes.windll.kernel32
            kernel32.GetCurrentProcess.restype = ctypes.c_void_p
            kernel32.GetProcessAffinityMask.argtypes = [
                ctypes.c_void_p,
                ctypes.POINTER(ctypes.c_size_t),
                ctypes.POINTER(ctypes.c_size_t),
            ]
            kernel32.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
            process = kernel32.GetCurrentProcess()
            mask = ctypes.c_size_t()
            system = ctypes.c_size_t()
            if not kernel32.GetProcessAffinityMask(
                process, ctypes.byref(mask), ctypes.byref(system)
            ):
                raise ctypes.WinError()
            allowed = mask.value & ~sum(1 << index for index in banned)
            if allowed == mask.value:
                return
            if not allowed:
                raise RuntimeError(f"no CPU is left for the runner off {sorted(banned)}")
            if not kernel32.SetProcessAffinityMask(process, allowed):
                raise ctypes.WinError()
            return
        # Linux keeps an affinity per thread: every runner thread leaves them.
        for task in os.listdir("/proc/self/task"):
            try:
                allowed = os.sched_getaffinity(int(task)) - banned
                if not allowed:
                    raise RuntimeError(f"no CPU is left for the runner off {sorted(banned)}")
                os.sched_setaffinity(int(task), allowed)
            except ProcessLookupError:
                continue


def spawn_benchmark(args: list[str], env: dict[str, str], affinity: tuple[int, ...]) -> subprocess.Popen[str]:
    """Start a benchmark on `affinity` from its first instruction, the runner
    staying where it is: Windows creates it suspended, sets its mask and resumes
    it; Linux execs it through taskset."""
    if os.name != "nt":
        return subprocess.Popen(
            ["taskset", "-c", ",".join(map(str, affinity)), *args],
            env=env,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    child = subprocess.Popen(
        args,
        env=env,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        creationflags=subprocess.HIGH_PRIORITY_CLASS | CREATE_SUSPENDED,
    )
    kernel32 = ctypes.windll.kernel32
    kernel32.OpenProcess.restype = ctypes.c_void_p
    kernel32.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
    kernel32.SetProcessAffinityMask.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    ntdll = ctypes.windll.ntdll
    ntdll.NtResumeProcess.argtypes = [ctypes.c_void_p]
    handle = kernel32.OpenProcess(PROCESS_SET_INFORMATION | PROCESS_SUSPEND_RESUME, False, child.pid)
    try:
        if not handle or not kernel32.SetProcessAffinityMask(
            handle, sum(1 << cpu for cpu in affinity)
        ):
            raise ctypes.WinError()
        status = ntdll.NtResumeProcess(handle)
        if status:
            raise OSError(f"NtResumeProcess returned {status & 0xFFFFFFFF:#010x}")
    except BaseException:
        child.kill()
        child.communicate()
        raise
    finally:
        if handle:
            kernel32.CloseHandle(handle)
    return child


def finish(child: subprocess.Popen[str], timeout: float) -> tuple[str, float]:
    """The child's whole output and the CPU time it used, in the clock idle is
    counted in: TSC ticks on Windows (QueryProcessCycleTime), clock ticks on Linux
    (its rusage).  subprocess.TimeoutExpired, the child killed and reaped, when it
    runs longer than `timeout`."""
    if os.name == "nt":
        try:
            output, _ = child.communicate(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            child.kill()
            child.communicate()
            raise error
        kernel32 = ctypes.windll.kernel32
        kernel32.QueryProcessCycleTime.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64)]
        cycles = ctypes.c_uint64()
        if not kernel32.QueryProcessCycleTime(int(child._handle), ctypes.byref(cycles)):
            raise ctypes.WinError()
        return output, float(cycles.value)
    # Popen would reap the child without its rusage: read to the end, reap it here.
    expired = threading.Event()
    timer = threading.Timer(timeout, lambda: (expired.set(), child.kill()))
    timer.start()
    try:
        output = child.stdout.read()
    finally:
        timer.cancel()
    _, status, usage = os.wait4(child.pid, 0)
    child.returncode = os.waitstatus_to_exitcode(status)
    child.stdout.close()
    if expired.is_set() and os.WIFSIGNALED(status):
        raise subprocess.TimeoutExpired(child.args, timeout, output)
    return output, (usage.ru_utime + usage.ru_stime) * os.sysconf("SC_CLK_TCK")


def benchmark_environment(
    category: str,
    affinity: tuple[int, ...],
    duration_ms: int,
    samples_per_process: int,
    warmup_ms: int,
    stack_phase: int | None,
    raw_configs: str,
    start_gate: Path | None,
    ready_file: Path | None,
    gate_barrier: threading.Barrier | None,
) -> dict[str, str]:
    environment = dict(os.environ)
    for name in PROCESS_ENVIRONMENT:
        environment.pop(name, None)
    environment.update(
        PULSE_METHOD_QUALIFICATION="1",
        PULSE_CHAIN="1",
        PULSE_SAMPLES=str(samples_per_process),
        PULSE_BATCH_US=str(duration_ms * 1000 // samples_per_process),
        PULSE_WARMUP_MS=str(warmup_ms),
    )
    if stack_phase is not None:
        environment["PULSE_STACK_PHASE"] = str(stack_phase)
    if raw_configs:
        environment["PULSE_RAW_CONFIGS"] = raw_configs
    if start_gate is not None or ready_file is not None or gate_barrier is not None:
        if start_gate is None or ready_file is None or gate_barrier is None:
            raise ValueError("start gate, ready file and barrier must be provided together")
        environment["PULSE_START_FILE"] = str(start_gate)
        environment["PULSE_READY_FILE"] = str(ready_file)
        environment["PULSE_GATE_TIMEOUT_MS"] = "10000"
    if category != "multithread" and len(affinity) == 1:
        sibling = processor_sibling(affinity[0])
        if sibling is not None:
            environment["PULSE_SIBLING_CPU"] = str(sibling)
    return environment


def launch(
    executable: Path,
    selected: str,
    environment: dict[str, str],
    category: str,
    affinity: tuple[int, ...],
    timeout_seconds: float,
    start_gate: Path | None,
    ready_file: Path | None,
    gate_barrier: threading.Barrier | None,
    label: str,
) -> tuple[str, int, int, float, dict[str, object]]:
    """Run one benchmark process: (output, exit code, pid, seconds, runner).

    A single-CPU process starts when CORE_WATCH lets it: the runner off the core
    and its SMT sibling, no foreign work on the core in the
    MEASUREMENT_CORE_IDLE_SECONDS before it, and the core idle since its own last
    process for MEASUREMENT_CORE_REST_SECONDS.  `runner` keeps that decision and
    the sibling's idle over the process's life, each as [idle, elapsed] in the
    clock the OS counts idle in, and the CPU time the process spent on its core."""
    runner: dict[str, object] = {}
    sibling = None
    cpu = None
    if category != "multithread" and len(affinity) == 1:
        cpu = affinity[0]
        keep_runner_off(cpu)
        runner.update(core_cpu=cpu, **CORE_WATCH.before(cpu))
        sibling = processor_sibling(cpu)
        if sibling is not None:
            runner["sibling_cpu"] = sibling
            sibling_mark = idle_mark(sibling)
        began = CORE_WATCH.mark(cpu)
    started = time.perf_counter()
    child = spawn_benchmark([str(executable), "quick", selected], environment, affinity)
    own = 0.0
    try:
        if ready_file is not None:
            ready_deadline = time.monotonic() + 10.0
            while not ready_file.exists():
                if child.poll() is not None:
                    output, _ = child.communicate()
                    raise RuntimeError(
                        f"benchmark exited before start gate: {label}\n{output[-1000:]}"
                    )
                if time.monotonic() >= ready_deadline:
                    raise RuntimeError(f"benchmark did not reach start gate: {label}")
                time.sleep(0.001)
            if gate_barrier.wait(timeout=10.0) == 0:
                start_gate.touch()
        output, own = finish(child, timeout_seconds)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"benchmark timed out after {timeout_seconds:.1f}s: {label}")
    except threading.BrokenBarrierError:
        child.kill()
        child.communicate()
        raise RuntimeError(f"benchmark timed out after {timeout_seconds:.1f}s: {label}")
    except Exception:
        if child.returncode is None:
            if child.poll() is None:
                child.kill()
            child.communicate()
        raise
    finally:
        # A process that failed counts as foreign work: the next one waits it out.
        if cpu is not None:
            CORE_WATCH.after(cpu, began, own)
    elapsed = time.perf_counter() - started
    if cpu is not None:
        runner["own_busy"] = own
    if sibling is not None:
        runner["sibling_idle"] = idle_since(sibling, sibling_mark)
    return output, child.returncode, child.pid, elapsed, runner


def parse_measurement_output(
    output: str, program: str, cases: list[str], samples_per_process: int, log: Path,
) -> tuple[dict[str, dict[str, str]], dict[str, list[dict[str, object]]]]:
    lines = output.splitlines()
    samples = [fields(line) for line in lines if line.startswith("PULSE_SAMPLE ")]
    case_lines = [fields(line) for line in lines if line.startswith("PULSE_CASE ")]
    endings = [fields(line) for line in lines if line.startswith("PULSE_END ")]
    # The negative control patches pulse_repairs; its report label is repairs-control.
    programs = pulse.emitted_program_names("repairs" if program == "repairs-control" else program)
    if (len(endings) != 1 or endings[0].get("status") != "PASS"
            or any(row.get("program") not in programs for row in samples + case_lines + endings)
            or len(samples) != samples_per_process * len(cases) or len(case_lines) != len(cases)):
        raise RuntimeError(f"invalid benchmark output: {log}")
    definitions = {row.get("case"): row for row in case_lines}
    samples_by_case = {
        name: [{key: int(value) if value.isdigit() else value for key, value in sample.items()}
               for sample in samples if sample.get("case") == name]
        for name in cases
    }
    if set(definitions) != set(cases) or any(len(rows) != samples_per_process for rows in samples_by_case.values()):
        raise RuntimeError(f"case matrix differs in benchmark output: {log}")
    return definitions, samples_by_case


def run_one(
    executable: Path,
    program: str,
    case: str,
    variant: str,
    repeat: int,
    duration_ms: int,
    category: str,
    affinity: tuple[int, ...],
    log_dir: Path,
    fixed_iterations: int | None = None,
    samples_per_process: int = MINIMUM_SAMPLES_PER_PROCESS,
    warmup_ms: int = 5,
    timeout_seconds: float = 300.0,
    start_gate: Path | None = None,
    ready_file: Path | None = None,
    gate_barrier: threading.Barrier | None = None,
    stack_phase: int | None = None,
    raw_configs: str = "",
) -> dict[str, object]:
    environment = benchmark_environment(
        category, affinity, duration_ms, samples_per_process, warmup_ms, stack_phase,
        raw_configs, start_gate, ready_file, gate_barrier,
    )
    if fixed_iterations is not None:
        if fixed_iterations <= 0:
            raise ValueError("fixed_iterations must be positive")
        environment["PULSE_ITERATIONS"] = str(fixed_iterations)
    if category in ("memory-manager", "fragmentation"):
        environment["PULSE_MEMORY_COOLDOWN_MS"] = "50"
    output, returncode, pid, elapsed, runner = launch(
        executable, case, environment, category, affinity, timeout_seconds,
        start_gate, ready_file, gate_barrier, f"{program}/{case} {variant}",
    )
    log = log_dir / f"{program}-{case}-{variant}-{repeat}.log"
    log.write_text(output, encoding="utf-8", newline="\n")
    if returncode:
        raise RuntimeError(f"benchmark failed ({returncode}): {log}\n{output[-1000:]}")
    definitions, samples = parse_measurement_output(output, program, [case], samples_per_process, log)
    return {
        "program": program,
        "case": case,
        "category": category,
        "affinity": affinity,
        "variant": variant,
        "repeat": repeat,
        "duration_ms": duration_ms,
        "pid": pid,
        "process_seconds": elapsed,
        "executable": str(executable),
        "sha256": sha256(executable),
        "log": str(log),
        "case_definition": definitions[case],
        "samples": samples[case],
        "iterations": int(samples[case][0]["iterations"]),
        "fixed_work": fixed_iterations is not None,
        "stack_phase": stack_phase,
        "runner": runner,
    }


def run_many(
    executable: Path,
    program: str,
    cases: list[str],
    variant: str,
    repeat: int,
    duration_ms: int,
    category: str,
    affinity: tuple[int, ...],
    log_dir: Path,
    samples_per_process: int,
    warmup_ms: int,
    timeout_seconds: float = 300.0,
    start_gate: Path | None = None,
    ready_file: Path | None = None,
    gate_barrier: threading.Barrier | None = None,
    fixed_iterations: dict[str, int] | None = None,
    stack_phase: int | None = None,
) -> list[dict[str, object]]:
    if not cases:
        raise ValueError("run_many requires at least one case")
    selected = ",".join(cases)
    environment = benchmark_environment(
        category, affinity, duration_ms, samples_per_process, warmup_ms, stack_phase,
        "", start_gate, ready_file, gate_barrier,
    )
    if fixed_iterations is not None:
        if set(fixed_iterations) != set(cases) or any(value <= 0 for value in fixed_iterations.values()):
            raise ValueError("fixed iteration counts must cover the batch")
        environment["PULSE_ITERATION_COUNTS"] = ",".join(f"{name}={value}" for name, value in fixed_iterations.items())
    output, returncode, pid, elapsed, runner = launch(
        executable, selected, environment, category, affinity, timeout_seconds,
        start_gate, ready_file, gate_barrier, f"{program}/{selected} {variant}",
    )
    suffix = hashlib.sha256(selected.encode()).hexdigest()[:8]
    selection_tag = f"batch-{cases[0]}-{len(cases)}-{suffix}"
    log_dir.mkdir(parents=True, exist_ok=True)
    log = log_dir / f"{program}-{selection_tag}-{variant}-{repeat}.log"
    log.write_text(output, encoding="utf-8", newline="\n")
    if returncode:
        raise RuntimeError(
            f"benchmark failed ({returncode}): {log}\n{output[-1000:]}"
        )
    definitions, samples_by_case = parse_measurement_output(output, program, cases, samples_per_process, log)
    executable_sha256 = sha256(executable)
    return [
        {
            "program": program,
            "case": name,
            "category": category,
            "affinity": affinity,
            "variant": variant,
            "repeat": repeat,
            "duration_ms": duration_ms,
            "pid": pid,
            "process_seconds": elapsed,
            "executable": str(executable),
            "sha256": executable_sha256,
            "log": str(log),
            "case_definition": definitions[name],
            "samples": samples_by_case[name],
            "iterations": int(samples_by_case[name][0]["iterations"]),
            "fixed_work": fixed_iterations is not None,
            "stack_phase": stack_phase,
            # The batch is one process: its core and sibling judge every case.
            "runner": runner,
        }
        for name in cases
    ]


def xperf_start(etl: Path, counters: tuple[str, ...] = ("TotalCycles",)) -> None:
    command([str(XPERF), "-SetProfInt", "1221"])
    command(
        [
            str(XPERF),
            "-on",
            "PROC_THREAD+LOADER+PROFILE+CSWITCH",
            "-Pmc",
            ",".join(counters),
            "Profile",
            "strict",
            "-f",
            str(etl),
        ]
    )


def xperf_stop(etl: Path) -> Path:
    try:
        command([str(XPERF), "-stop"])
    finally:
        command([str(XPERF), "-SetProfInt", "10000"], check=False)
    dump = etl.with_suffix(".txt")
    command([str(XPERF), "-i", str(etl), "-o", str(dump), "-a", "dumper"])
    return dump


def attach_windows_core_cycles(dump: Path, records: list[dict[str, object]]) -> None:
    by_pid: dict[int, list[dict[str, object]]] = {}
    for record in records:
        by_pid.setdefault(int(record["pid"]), []).append(record)
    trace_start = None
    relevant: dict[tuple[int, int], set[int]] = {
        (id(record), index): set()
        for record in records
        for index, _ in enumerate(record["samples"])
    }
    process_pattern = re.compile(r"\(\s*(\d+)\)")
    with dump.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if trace_start is None:
                match = re.search(r"Trace Start:\s*(\d+)", line)
                if match:
                    trace_start = int(match.group(1))
            stripped = line.strip()
            if not stripped.startswith("SampledProfile,"):
                continue
            parts = [part.strip() for part in stripped.split(",")]
            if len(parts) < 4 or not parts[1].isdigit():
                continue
            match = process_pattern.search(parts[2])
            if not match:
                continue
            pid = int(match.group(1))
            if pid not in by_pid or trace_start is None:
                continue
            timestamp = int(parts[1])
            tid = int(parts[3])
            for record in by_pid[pid]:
                for index, sample in enumerate(record["samples"]):
                    start_us = (int(sample["trace_start_100ns"]) - trace_start) / 10.0
                    stop_us = (int(sample["trace_stop_100ns"]) - trace_start) / 10.0
                    if start_us <= timestamp <= stop_us:
                        relevant[id(record), index].add(tid)
    if trace_start is None:
        raise RuntimeError(f"trace start is missing from {dump}")
    context_switches: dict[tuple[int, int], int] = {key: 0 for key in relevant}
    switch_windows: dict[int, list[tuple[tuple[int, int], float, float]]] = {}
    for record in records:
        for index, sample in enumerate(record["samples"]):
            key = id(record), index
            start_us = (int(sample["trace_start_100ns"]) - trace_start) / 10.0
            stop_us = (int(sample["trace_stop_100ns"]) - trace_start) / 10.0
            for tid in relevant[key]:
                switch_windows.setdefault(tid, []).append((key, start_us, stop_us))
    with dump.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            stripped = line.strip()
            if not stripped.startswith("CSwitch,"):
                continue
            parts = [part.strip() for part in stripped.split(",")]
            if len(parts) < 13 or not parts[1].isdigit() or not parts[9].isdigit():
                continue
            timestamp = int(parts[1])
            old_tid = int(parts[9])
            if parts[12] != "Ready" or old_tid not in switch_windows:
                continue
            for key, start_us, stop_us in switch_windows[old_tid]:
                if start_us <= timestamp <= stop_us:
                    context_switches[key] += 1
    wanted_tids = set().union(*relevant.values()) if relevant else set()
    names: list[str] = []
    pmc: dict[int, list[tuple[int, list[int]]]] = {tid: [] for tid in wanted_tids}
    with dump.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            stripped = line.strip()
            if not stripped.startswith("Pmc,"):
                continue
            parts = [part.strip() for part in stripped.split(",")]
            if len(parts) >= 4 and parts[1] == "TimeStamp":
                names = parts[3:]
                continue
            if len(parts) < 4 or not parts[1].isdigit():
                continue
            tid = int(parts[2])
            if tid in pmc:
                pmc[tid].append((int(parts[1]), [int(value) for value in parts[3:]]))
    cycles_column = names.index("TotalCycles") if "TotalCycles" in names else 0

    def counter_at(rows: list[tuple[int, list[int]]], timestamp: float, column: int) -> float:
        stamps = [row[0] for row in rows]
        right = bisect.bisect_left(stamps, timestamp)
        if right == 0:
            return float(rows[0][1][column])
        if right == len(rows):
            return float(rows[-1][1][column])
        left_stamp, left_values = rows[right - 1]
        right_stamp, right_values = rows[right]
        left_value, right_value = left_values[column], right_values[column]
        if right_value < left_value or right_stamp == left_stamp:
            return float(left_value)
        fraction = (timestamp - left_stamp) / (right_stamp - left_stamp)
        return left_value + (right_value - left_value) * fraction

    for record in records:
        record["pmc_points"] = []
        record_start_us = (
            int(record["samples"][0]["trace_start_100ns"]) - trace_start
        ) / 10.0
        record_stop_us = (
            int(record["samples"][-1]["trace_stop_100ns"]) - trace_start
        ) / 10.0
        for index, sample in enumerate(record["samples"]):
            start_us = (int(sample["trace_start_100ns"]) - trace_start) / 10.0
            stop_us = (int(sample["trace_stop_100ns"]) - trace_start) / 10.0
            counts = [0] * len(names)
            points = 0
            for tid in relevant[id(record), index]:
                # A Windows TID may be reused by a later fresh process.
                all_rows = [
                    row
                    for row in pmc[tid]
                    if record_start_us - 1000 <= row[0] <= record_stop_us + 1000
                ]
                rows = [row for row in all_rows if start_us <= row[0] <= stop_us]
                points += len(rows)
                if len(all_rows) >= 2:
                    for column in range(len(names)):
                        counts[column] += round(
                            counter_at(all_rows, stop_us, column)
                            - counter_at(all_rows, start_us, column)
                        )
            cycles = counts[cycles_column] if counts else 0
            sample["pmc"] = {
                name: count
                for column, (name, count) in enumerate(zip(names, counts))
                if column != cycles_column
            }
            if cycles <= 0:
                if record["category"] != "multithread":
                    raise RuntimeError(
                        f"no xperf TotalCycles for pid={record['pid']} "
                        f"{record['program']}/{record['case']} sample={index + 1}"
                    )
                cycles = 0
            sample["core_cycles"] = cycles
            sample["context_switches"] = context_switches[id(record), index]
            record["pmc_points"].append(points)


def run_batch(
    items: list[tuple[Path, str, str, str, int, str, int]],
    duration_ms: int,
    affinity: tuple[int, ...],
    output: Path,
    tag: str,
    enable_xperf: bool | None = None,
) -> list[dict[str, object]]:
    log_dir = output / "logs" / tag
    log_dir.mkdir(parents=True, exist_ok=True)
    etl = output / f"{tag}.etl"
    if enable_xperf is None:
        use_xperf = os.name == "nt" and any(item[5] != "multithread" for item in items)
    else:
        use_xperf = os.name == "nt" and enable_xperf
    if use_xperf:
        xperf_start(etl)
    records: list[dict[str, object]] = []

    def launch(
        item: tuple[Path, str, str, str, int, str, int], reserved: tuple[int, ...]
    ) -> dict[str, object]:
        executable, program, case, variant, repeat, category, _ = item
        return run_one(
            executable,
            program,
            case,
            variant,
            repeat,
            duration_ms,
            category,
            reserved,
            log_dir,
            # Method controls hold the case's stack address constant across fresh
            # processes: ASLR can otherwise create a 4 KiB store/load alias in A/A.
            stack_phase=0 if category != "multithread" else None,
        )

    try:
        if os.name == "nt":
            single_cpus = tuple(reversed(affinity[-min(4, len(affinity)) :]))
        else:
            single_cpus = affinity[: min(6, len(affinity))]
        for repeat in range(PROCESS_REPEATS):
            paired_phases = [
                [
                    item
                    for item in items
                    if item[5] == "single-cpu" and item[6] == repeat * 2 + position
                ]
                for position in range(2)
            ]
            for start in range(0, len(paired_phases[0]), len(single_cpus)):
                for phase_items in paired_phases:
                    chunk = phase_items[start : start + len(single_cpus)]
                    with ThreadPoolExecutor(max_workers=len(chunk)) as executor:
                        futures = [
                            executor.submit(launch, item, (single_cpus[index],))
                            for index, item in enumerate(chunk)
                        ]
                        records.extend(future.result() for future in futures)
        for item in items:
            if item[5] == "single-cpu":
                continue
            reserved = affinity if item[5] == "multithread" else (affinity[0],)
            records.append(launch(item, reserved))
    finally:
        if use_xperf:
            dump = xperf_stop(etl)
    if use_xperf:
        attach_windows_core_cycles(dump, records)
    return records


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int((len(ordered) - 1) * fraction + 0.999999))]


def sample_metrics(
    sample: dict[str, object], multithread: bool, expected_duration_ms: float, fixed_work: bool = False
) -> dict[str, float | bool]:
    operations = int(sample["operations"])
    tsc = int(sample["tsc_ticks"])
    core = int(sample["core_cycles"])
    wall = int(sample["wall_ns"])
    process_cycles = int(sample["process_cycles"])
    thread_cycles = int(sample["thread_cycles"])
    process_cpu = int(sample["process_cpu_ns"])
    thread_cpu = int(sample["thread_cpu_ns"])
    if os.name == "nt":
        execution_ratio = process_cycles / tsc if multithread else thread_cycles / tsc
    else:
        execution_ratio = process_cpu / wall if multithread else thread_cpu / wall
    enabled = int(sample["core_enabled"])
    running = int(sample["core_running"])
    context_switch_count = int(sample["context_switches"])
    memory_before = int(sample["memory_before_private"])
    memory_after = int(sample["memory_after_private"])
    memory_cooldown = int(sample["memory_cooldown_private"])
    page_faults = int(sample.get("page_faults", 0))
    sibling_idle_cycles = int(sample.get("sibling_idle_cycles", 0))
    sibling_counter_present = int(sample.get("sibling_cpu", -1)) >= 0
    if sibling_counter_present and os.name == "nt":
        sibling_idle_ratio = sibling_idle_cycles / tsc
    elif sibling_counter_present:
        sibling_idle_ratio = (
            sibling_idle_cycles * 1e9 / (os.sysconf("SC_CLK_TCK") * wall)
        )
    else:
        sibling_idle_ratio = 0.0
    multiplex_ratio = running / enabled if enabled else 1.0
    # PULSE_CHAIN: TSC ticks of 65536 dependent adds before and after the sample
    # (0 without the chain). An interrupt inside one only lengthens it: the
    # shorter is the sample's core clock.
    chain = min(int(sample.get("chain_before", 0)), int(sample.get("chain_after", 0)))
    if multithread and os.name == "nt":
        work_cycles = process_cycles
        frequency_ratio = 1.0
    elif multithread:
        work_cycles = process_cpu
        frequency_ratio = 1.0
    elif os.name == "nt":
        # Thread cycles are TSC ticks the thread ran; at the core clock the chain
        # measured they are its core cycles, as the PMU counts them on Linux.
        work_cycles = thread_cycles * CHAIN_CYCLES / chain if chain else thread_cycles
        frequency_ratio = thread_cycles / tsc
    else:
        work_cycles = core
        frequency_ratio = core / tsc
    duration_ratio = wall / (expected_duration_ms * 1e6)
    counter_valid = (
        work_cycles > 0
        and multiplex_ratio >= 0.999
        and (
            fixed_work or 0.25 <= duration_ratio <= 4.00
            or int(sample["iterations"]) == 1
        )
    )
    valid = counter_valid
    if not multithread:
        valid = valid and execution_ratio >= 0.98 and abs(frequency_ratio - 1.0) <= 0.02
    return {
        "work_cycles_per_op": work_cycles / operations,
        "core_per_op": core / operations,
        "ticks_per_op": tsc / operations,
        "process_cycles_per_op": process_cycles / operations,
        "thread_cycles_per_op": thread_cycles / operations,
        "process_cpu_per_op": process_cpu / operations,
        "operations_per_second": operations * 1e9 / wall,
        "latency_ns": wall / operations,
        "effective_cores": (
            process_cycles / tsc
            if multithread and os.name == "nt"
            else process_cpu / wall
        ),
        "frequency_ratio": frequency_ratio,
        "chain_frequency_ratio": CHAIN_CYCLES / chain if chain else 0.0,
        "execution_ratio": execution_ratio,
        "multiplex_ratio": multiplex_ratio,
        "context_switches": context_switch_count,
        "memory_after_private": memory_after,
        "memory_cooldown_private": memory_cooldown,
        "memory_retained_delta": memory_after - memory_before,
        "memory_cooldown_delta": memory_cooldown - memory_before,
        "memory_peak_resident": int(sample["memory_peak_resident"]),
        "page_faults": page_faults,
        "sibling_idle_ratio": sibling_idle_ratio,
        "sibling_idle_units": sibling_idle_cycles,
        "sibling_counter_present": sibling_counter_present,
        "wall_ns": wall,
        "duration_ratio": duration_ratio,
        "counter_valid": counter_valid,
        "valid": valid,
    }


def record_metrics(
    record: dict[str, object], multithread: bool, work_only: bool = False
) -> dict[str, object]:
    expected = int(record["duration_ms"]) / len(record["samples"])
    samples = [sample_metrics(sample, multithread, expected, record.get("fixed_work", False)) for sample in record["samples"]]
    accepted = [
        sample
        for sample in samples
        if bool(sample["counter_valid"] if work_only else sample["valid"])
    ]
    minimum_accepted = max(2, math.ceil(len(samples) * 0.60))
    usable = accepted if len(accepted) >= minimum_accepted else samples

    def median(name: str) -> float:
        return statistics.median(float(sample[name]) for sample in usable)

    latencies = [float(sample["latency_ns"]) for sample in usable]
    total_wall_ns = sum(int(sample["wall_ns"]) for sample in samples)
    sibling_counter_present = any(bool(sample["sibling_counter_present"]) for sample in samples)
    sibling_idle_units = sum(int(sample["sibling_idle_units"]) for sample in samples)
    sibling_idle_observable = total_wall_ns >= 50_000_000
    if not sibling_counter_present:
        sibling_idle_ratio = 1.0
        sibling_idle_valid = True
    elif not sibling_idle_observable:
        # Idle counters move in clock ticks (Linux) or at idle exits (Windows): a
        # shorter process leaves the sibling not observed, which is not idle.
        sibling_idle_ratio = None
        sibling_idle_valid = True
    elif os.name == "nt":
        total_tsc = sum(int(record_sample["tsc_ticks"]) for record_sample in record["samples"])
        sibling_idle_ratio = sibling_idle_units / total_tsc if total_tsc else 0.0
        sibling_idle_valid = sibling_idle_ratio >= MINIMUM_SIBLING_IDLE_RATIO
    else:
        # Each sample reads the sibling's idle twice in whole clock ticks: an idle
        # sibling can come out a tick short in every sample, not once a process
        # (json/parse-large-custom-double on HEL1: 8 ticks of 9.7 in five 19.4 ms
        # samples of an idle sibling).
        clock_tick_ns = 1e9 / os.sysconf("SC_CLK_TCK")
        sibling_idle_ratio = sibling_idle_units * clock_tick_ns / total_wall_ns
        quantized_threshold = max(0.0, MINIMUM_SIBLING_IDLE_RATIO - len(samples) * clock_tick_ns / total_wall_ns)
        sibling_idle_valid = sibling_idle_units > 0 and sibling_idle_ratio >= quantized_threshold
    wall_valid = len(accepted) >= minimum_accepted and (
        multithread
        or (
            median("execution_ratio") >= 0.98
            and abs(median("frequency_ratio") - 1.0) <= 0.01
            and sibling_idle_valid
        )
    )
    # The runner's view of the core, for CPU work as well: a busy SMT sibling
    # costs the work itself x1.6-2.05, and so can what ran on the core before.
    runner = record.get("runner") or {}
    core_idle_valid = idle_enough(runner.get("core_idle"), MEASUREMENT_CORE_IDLE_RATIO) and idle_enough(
        runner.get("core_rest"), MEASUREMENT_CORE_IDLE_RATIO)
    lifetime_sibling_valid = idle_enough(runner.get("sibling_idle"), MINIMUM_SIBLING_IDLE_RATIO)
    valid = (
        len(accepted) >= minimum_accepted
        and (work_only or wall_valid)
        and core_idle_valid
        and lifetime_sibling_valid
    )
    return {
        "work_cycles_per_op": median("work_cycles_per_op"),
        "core_per_op": median("core_per_op"),
        "ticks_per_op": median("ticks_per_op"),
        "process_cycles_per_op": median("process_cycles_per_op"),
        "thread_cycles_per_op": median("thread_cycles_per_op"),
        "process_cpu_per_op": median("process_cpu_per_op"),
        "operations_per_second": median("operations_per_second"),
        "latency_median_ns": statistics.median(latencies),
        "latency_p99_ns": percentile(latencies, 0.99),
        "effective_cores": median("effective_cores"),
        "frequency_ratio": median("frequency_ratio"),
        "chain_frequency_ratio": median("chain_frequency_ratio"),
        "execution_ratio": median("execution_ratio"),
        "multiplex_ratio": median("multiplex_ratio"),
        "context_switches": sum(int(sample["context_switches"]) for sample in samples),
        "memory_after_private": median("memory_after_private"),
        "memory_cooldown_private": float(samples[-1]["memory_cooldown_private"]),
        "memory_retained_delta": median("memory_retained_delta"),
        "memory_cooldown_delta": float(samples[-1]["memory_cooldown_delta"]),
        "memory_peak_resident": max(float(sample["memory_peak_resident"]) for sample in samples),
        "page_faults": sum(int(sample["page_faults"]) for sample in samples),
        "sibling_idle_ratio": sibling_idle_ratio,
        "sibling_idle_valid": sibling_idle_valid,
        "sibling_idle_observable": sibling_idle_observable,
        "core_idle_valid": core_idle_valid,
        "lifetime_sibling_valid": lifetime_sibling_valid,
        "measurement_seconds": sum(int(sample["wall_ns"]) for sample in record["samples"]) / 1e9,
        "accepted_samples": len(accepted),
        "sample_count": len(samples),
        "valid": valid,
        "wall_valid": wall_valid,
        "samples": samples,
    }


def rejection_reason(metrics: dict[str, object]) -> str:
    """Why record_metrics found a process invalid, in its own checks' words."""
    reasons = []
    if not metrics.get("core_idle_valid", True):
        reasons.append("core-not-clean-before")
    if not metrics.get("lifetime_sibling_valid", True):
        reasons.append("sibling-busy")
    if metrics.get("accepted_samples", 0) < max(2, math.ceil(metrics.get("sample_count", 0) * 0.60)):
        reasons.append("samples")
    elif not metrics.get("wall_valid", True):
        reasons.append("wall")
    return ",".join(reasons) or "none"


def analyze_aa(records: list[dict[str, object]], category: str) -> dict[str, object]:
    multithread = category == "multithread"
    rows = [(record, record_metrics(record, multithread)) for record in records]
    required_processes = min(5, PROCESS_REPEATS)
    valid_rows = [(record, metrics) for record, metrics in rows if metrics["valid"]]
    valid_left = [metrics for record, metrics in valid_rows if record["variant"] == "A"]
    valid_right = [metrics for record, metrics in valid_rows if record["variant"] == "B"]
    valid = len(valid_left) >= required_processes and len(valid_right) >= required_processes
    usable_rows = valid_rows if valid else rows
    left = [metrics for record, metrics in usable_rows if record["variant"] == "A"]
    right = [metrics for record, metrics in usable_rows if record["variant"] == "B"]
    core_left = [float(row["core_per_op"]) for row in left]
    core_right = [float(row["core_per_op"]) for row in right]
    work_left = [float(row["work_cycles_per_op"]) for row in left]
    work_right = [float(row["work_cycles_per_op"]) for row in right]
    tick_left = [float(row["ticks_per_op"]) for row in left]
    tick_right = [float(row["ticks_per_op"]) for row in right]
    core_spread = spread(core_left + core_right)
    tick_spread = spread(tick_left + tick_right)
    core_copy = relative_difference(core_left, core_right)
    tick_copy = relative_difference(tick_left, tick_right)
    work_spread = spread(work_left + work_right)
    work_copy = relative_difference(work_left, work_right)
    stability = work_spread, tick_spread, work_copy, tick_copy
    passed = valid and max(stability) <= 1.0
    processes = []
    for record, metrics in rows:
        definition = record.get("case_definition", {})
        processes.append(
            {
                "variant": record["variant"],
                "repeat": record["repeat"],
                "pid": record["pid"],
                "sha256": record["sha256"],
                "body": definition.get("body", ""),
                "anchor": definition.get("anchor", ""),
                "iterations": int(record["samples"][0]["iterations"]),
                "operations": int(record["samples"][0]["operations"]),
                "work_cycles_per_op": metrics["work_cycles_per_op"],
                "ticks_per_op": metrics["ticks_per_op"],
                "thread_cycles_per_op": metrics["thread_cycles_per_op"],
                "process_cpu_per_op": metrics["process_cpu_per_op"],
                "operations_per_second": metrics["operations_per_second"],
                "frequency_ratio": metrics["frequency_ratio"],
                "execution_ratio": metrics["execution_ratio"],
                "page_faults": metrics["page_faults"],
                "sibling_idle_ratio": metrics["sibling_idle_ratio"],
                "measurement_seconds": metrics["measurement_seconds"],
                "process_seconds": record["process_seconds"],
                "accepted_samples": metrics["accepted_samples"],
                "valid": metrics["valid"],
            }
        )
    return {
        "passed": passed,
        "valid": valid,
        "valid_left_processes": len(valid_left),
        "valid_right_processes": len(valid_right),
        "core_spread_percent": core_spread,
        "tick_spread_percent": tick_spread,
        "core_copy_percent": core_copy,
        "tick_copy_percent": tick_copy,
        "work_spread_percent": work_spread,
        "work_copy_percent": work_copy,
        "median_work_cycles_per_op": statistics.median(work_left + work_right),
        "median_core_per_op": statistics.median(core_left + core_right),
        "median_ticks_per_op": statistics.median(tick_left + tick_right),
        "median_frequency_ratio": statistics.median(float(row["frequency_ratio"]) for _, row in rows),
        "median_effective_cores": statistics.median(float(row["effective_cores"]) for _, row in rows),
        "median_context_switches": statistics.median(float(row["context_switches"]) for _, row in rows),
        "median_process_seconds": statistics.median(float(record["process_seconds"]) for record, _ in rows),
        "median_measurement_seconds": statistics.median(
            float(row["measurement_seconds"]) for _, row in rows
        ),
        "median_process_cpu_per_op": statistics.median(
            float(row["process_cpu_per_op"]) for _, row in rows
        ),
        "median_operations_per_second": statistics.median(
            float(row["operations_per_second"]) for _, row in rows
        ),
        "median_latency_ns": statistics.median(float(row["latency_median_ns"]) for _, row in rows),
        "p99_latency_ns": max(float(row["latency_p99_ns"]) for _, row in rows),
        "median_memory_retained": statistics.median(
            float(row["memory_retained_delta"]) for _, row in rows
        ),
        "median_memory_cooldown": statistics.median(
            float(row["memory_cooldown_delta"]) for _, row in rows
        ),
        "peak_resident_bytes": max(float(row["memory_peak_resident"]) for _, row in rows),
        "metrics": [metrics for _, metrics in rows],
        "processes": processes,
    }


def analyze_control(records: list[dict[str, object]]) -> dict[str, object]:
    rows = [(record, record_metrics(record, False)) for record in records]
    required_processes = min(5, PROCESS_REPEATS)
    valid_rows = [(record, metrics) for record, metrics in rows if metrics["valid"]]
    valid_baseline = [metrics for record, metrics in valid_rows if record["variant"] == "work64"]
    valid_more_work = [metrics for record, metrics in valid_rows if record["variant"] == "work66"]
    valid = len(valid_baseline) >= required_processes and len(valid_more_work) >= required_processes
    usable_rows = valid_rows if valid else rows
    baseline = [metrics for record, metrics in usable_rows if record["variant"] == "work64"]
    more_work = [metrics for record, metrics in usable_rows if record["variant"] == "work66"]
    ratios = []
    for repeat in range(PROCESS_REPEATS):
        paired = [
            metrics
            for record, metrics in valid_rows
            if record["repeat"] == repeat
        ]
        if len(paired) != 2:
            continue
        left = next(
            metrics
            for record, metrics in valid_rows
            if record["variant"] == "work66" and record["repeat"] == repeat
        )
        right = next(
            metrics
            for record, metrics in valid_rows
            if record["variant"] == "work64" and record["repeat"] == repeat
        )
        ratios.append(
            float(left["work_cycles_per_op"]) / float(right["work_cycles_per_op"]) - 1.0
        )
    effect = (
        statistics.median(float(row["work_cycles_per_op"]) for row in more_work)
        / statistics.median(float(row["work_cycles_per_op"]) for row in baseline)
        - 1.0
    ) * 100.0
    passed = (
        valid
        and len(ratios) >= required_processes
        and spread([float(row["work_cycles_per_op"]) for row in baseline]) <= 1.0
        and spread([float(row["work_cycles_per_op"]) for row in more_work]) <= 1.0
        and 2.0 <= effect <= 4.0
        and min(ratios) >= 0.015
        and max(ratios) <= 0.045
    )
    return {
        "passed": passed,
        "expected_effect_percent": CONTROL_EXPECTED_EFFECT_PERCENT,
        "effect_percent": effect,
        "minimum_pair_effect_percent": min(ratios) * 100.0 if ratios else 0.0,
        "valid_baseline_processes": len(valid_baseline),
        "valid_more_work_processes": len(valid_more_work),
        "valid_pairs": len(ratios),
        "baseline_spread_percent": spread(
            [float(row["work_cycles_per_op"]) for row in baseline]
        ),
        "more_work_spread_percent": spread(
            [float(row["work_cycles_per_op"]) for row in more_work]
        ),
    }


def write_sweep_tables(output: Path, result: dict[str, object]) -> None:
    summary = [
        "duration_ms\tvalid\tpassed\twork_spread_percent\ttick_spread_percent\t"
        "work_copy_percent\ttick_copy_percent\tmedian_work_cycles_per_op\t"
        "median_ticks_per_op\tmedian_frequency_ratio"
    ]
    processes = [
        "duration_ms\tvariant\trepeat\tpid\tsha256\tbody\tanchor\titerations\toperations\t"
        "work_cycles_per_op\tticks_per_op\tthread_cycles_per_op\tprocess_cpu_per_op\t"
        "operations_per_second\tfrequency_ratio\texecution_ratio\tpage_faults\t"
        "measurement_seconds\tprocess_seconds\tsibling_idle_ratio\taccepted_samples\tvalid"
    ]
    row = next(iter(result["cases"].values()))
    for duration_text, attempt in sorted(row["attempts"].items(), key=lambda item: int(item[0])):
        summary.append(
            "\t".join(
                (
                    duration_text,
                    str(int(bool(attempt["valid"]))),
                    str(int(bool(attempt["passed"]))),
                    f"{attempt['work_spread_percent']:.9f}",
                    f"{attempt['tick_spread_percent']:.9f}",
                    f"{attempt['work_copy_percent']:.9f}",
                    f"{attempt['tick_copy_percent']:.9f}",
                    f"{attempt['median_work_cycles_per_op']:.9f}",
                    f"{attempt['median_ticks_per_op']:.9f}",
                    f"{attempt['median_frequency_ratio']:.9f}",
                )
            )
        )
        for process in attempt["processes"]:
            processes.append(
                "\t".join(
                    (
                        duration_text,
                        str(process["variant"]),
                        str(process["repeat"]),
                        str(process["pid"]),
                        str(process["sha256"]),
                        str(process["body"]),
                        str(process["anchor"]),
                        str(process["iterations"]),
                        str(process["operations"]),
                        f"{process['work_cycles_per_op']:.9f}",
                        f"{process['ticks_per_op']:.9f}",
                        f"{process['thread_cycles_per_op']:.9f}",
                        f"{process['process_cpu_per_op']:.9f}",
                        f"{process['operations_per_second']:.9f}",
                        f"{process['frequency_ratio']:.9f}",
                        f"{process['execution_ratio']:.9f}",
                        str(process["page_faults"]),
                        f"{process['measurement_seconds']:.9f}",
                        f"{process['process_seconds']:.9f}",
                        "not observed"
                        if process["sibling_idle_ratio"] is None
                        else f"{process['sibling_idle_ratio']:.9f}",
                        str(process["accepted_samples"]),
                        str(int(bool(process["valid"]))),
                    )
                )
            )
    (output / "SWEEP.tsv").write_text("\n".join(summary) + "\n", encoding="utf-8")
    (output / "SWEEP_PROCESSES.tsv").write_text(
        "\n".join(processes) + "\n", encoding="utf-8"
    )


def write_report(output: Path, result: dict[str, object]) -> None:
    multithread = result["suite"] == "multithread"
    maximum_duration = max(result["durations_ms"])

    def counter_ratio(attempt: dict[str, object]) -> str:
        value = float(attempt["median_frequency_ratio"])
        return "n/a" if multithread and value == 0.0 else f"{value:.4f}"

    lines = [
        "# Pulse measurement-method qualification",
        "",
        f"Machine: `{result['machine_label']}`",
        "",
        f"Suite: `{result['suite']}`; primary work counter: `{result['work_counter']}`.",
        "",
        f"Verdict: **{'PASS' if result['passed'] else 'FAIL'}**",
        "",
        "| Case | Chosen ms | CPU work/op | Work spread | Time spread | Work copy delta | Time copy delta | CPU ns/op | Ops/s | Effective cores | Verdict |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for name, row in result["cases"].items():
        chosen = row.get("chosen_duration_ms", 0)
        attempt = row["attempts"][str(chosen)] if chosen else row["attempts"][str(max(map(int, row["attempts"])))]
        lines.append(
            f"| {name} | {chosen or 'none'} | {attempt['median_work_cycles_per_op']:.3f} | "
            f"{attempt['work_spread_percent']:.3f}% | {attempt['tick_spread_percent']:.3f}% | "
            f"{attempt['work_copy_percent']:.3f}% | {attempt['tick_copy_percent']:.3f}% | "
            f"{attempt['median_process_cpu_per_op']:.3f} | {attempt['median_operations_per_second']:.0f} | "
            f"{attempt['median_effective_cores']:.3f} | "
            f"{'PASS' if row.get('passed') else 'FAIL'} |"
        )
    lines.extend(
        [
            "",
            "## Every attempted duration",
            "",
            "| Case | ms | Valid | CPU work/op | Work spread | Time spread | Work copy | Time copy | Counter ratio | Measured s | Verdict |",
            "| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
        ]
    )
    for name, row in result["cases"].items():
        for duration_text, attempt in row["attempts"].items():
            lines.append(
                f"| {name} | {duration_text} | {'yes' if attempt['valid'] else 'no'} | "
                f"{attempt['median_work_cycles_per_op']:.3f} | {attempt['work_spread_percent']:.3f}% | "
                f"{attempt['tick_spread_percent']:.3f}% | {attempt['work_copy_percent']:.3f}% | "
                f"{attempt['tick_copy_percent']:.3f}% | {counter_ratio(attempt)} | "
                f"{attempt['median_measurement_seconds']:.3f} | {'PASS' if attempt['passed'] else 'RETRY' if int(duration_text) < maximum_duration else 'FAIL'} |"
            )
    if multithread:
        lines.extend(
            [
                "",
                "## Multithread diagnostics",
                "",
                "| Case | CPU ns/op | Ops/s | Latency median ns | Latency p99 ns | Effective cores | Counter ratio |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
            ]
        )
        for name, row in result["cases"].items():
            chosen = row.get("chosen_duration_ms", 0)
            attempt = row["attempts"][str(chosen)] if chosen else row["attempts"][str(max(map(int, row["attempts"])))]
            lines.append(
                f"| {name} | {attempt['median_process_cpu_per_op']:.3f} | "
                f"{attempt['median_operations_per_second']:.0f} | {attempt['median_latency_ns']:.3f} | "
                f"{attempt['p99_latency_ns']:.3f} | {attempt['median_effective_cores']:.3f} | "
                f"{counter_ratio(attempt)} |"
            )
    memory_rows = [
        (name, row)
        for name, row in result["cases"].items()
        if row["category"] in ("memory-manager", "fragmentation")
    ]
    if memory_rows:
        lines.extend(
            [
                "",
                "## Memory-manager metrics",
                "",
                "| Case | Peak resident MiB | Retained after work MiB | Retained after cooldown MiB |",
                "| --- | ---: | ---: | ---: |",
            ]
        )
        for name, row in memory_rows:
            chosen = row.get("chosen_duration_ms", 0)
            attempt = row["attempts"][str(chosen)] if chosen else row["attempts"][str(max(map(int, row["attempts"])))]
            lines.append(
                f"| {name} | {attempt['peak_resident_bytes'] / 1048576:.3f} | "
                f"{attempt['median_memory_retained'] / 1048576:.3f} | "
                f"{attempt['median_memory_cooldown'] / 1048576:.3f} |"
            )
    control = result["negative_control"]
    lines.extend(
        [
            "",
            "## Negative control",
            "",
            f"Chosen duration: `{control.get('chosen_duration_ms', 'none')} ms`; "
            f"66 vs 64 inner operations: `{control['final']['effect_percent']:.3f}%` "
            f"(expected `{control['final']['expected_effect_percent']:.3f}%`); "
            f"weakest paired effect: `{control['final']['minimum_pair_effect_percent']:.3f}%`; "
            f"verdict: **{'PASS' if control.get('passed') else 'FAIL'}**.",
            "",
            f"The run is A/A of one executable and its byte-for-byte copy: {PROCESS_REPEATS} fresh processes per side. "
            "A case passes only when primary CPU-work and elapsed-tick process-center spreads and both copy deltas are all at most 1%.",
            f"A Windows single-thread sample is rejected when its SMT sibling was less than "
            f"{MINIMUM_SIBLING_IDLE_RATIO * 100:.1f}% idle when observable; a process needs at least 60% of samples (minimum two) clean.",
            f"Every single-CPU process starts after its core was watched for {MEASUREMENT_CORE_IDLE_SECONDS:g} s "
            f"and is rejected when that core was less than {MEASUREMENT_CORE_IDLE_RATIO * 100:.0f}% idle then, "
            f"or its SMT sibling less than {MINIMUM_SIBLING_IDLE_RATIO * 100:.0f}% idle over the process's life.",
            "For multithread cases the counter ratio is diagnostic only. Windows uses QueryThreadCycleTime for "
            "single-thread work and QueryProcessCycleTime for process work without tracing during the measurement; "
            "Linux reports the perf-cycle frequency relative "
            "to TSC and process CPU time.",
        ]
    )
    (output / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if result.get("diagnostic_sweep"):
        write_sweep_tables(output, result)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--toolchain", type=Path, required=True)
    parser.add_argument("--control-toolchain", type=Path, required=True)
    parser.add_argument("--control-mm-source", type=Path, required=True,
                        help="control allocator source, compatible with the control toolchain's configured pin")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--machine-label", required=True)
    parser.add_argument("--suite", choices=tuple(CASES_BY_SUITE), default="single")
    parser.add_argument("--durations", default="50,200,1000")
    parser.add_argument(
        "--diagnostic-sweep",
        action="store_true",
        help="run every requested duration for exactly one Windows single-thread case",
    )
    parser.add_argument(
        "--cases",
        default="",
        help="optional comma-separated program/case subset of the qualification matrix",
    )
    return parser.parse_args()


def main() -> int:
    global PROCESS_REPEATS
    args = parse_args()
    if args.suite == "single":
        PROCESS_REPEATS = 5
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    durations = [int(value) for value in args.durations.split(",")]
    if args.diagnostic_sweep and (args.suite != "single" or os.name != "nt"):
        raise ValueError("diagnostic sweep requires the Windows single-thread suite")
    maximum_duration = 10000 if args.suite == "multithread" or args.diagnostic_sweep else 1000
    if durations != sorted(set(durations)) or not durations or durations[-1] > maximum_duration:
        raise ValueError(
            f"durations must be unique, increasing, and no longer than {maximum_duration} ms"
        )
    suite_cases = CASES_BY_SUITE[args.suite]
    requested = {value.strip() for value in args.cases.split(",") if value.strip()}
    known = {f"{program}/{case}" for program, case, _ in suite_cases}
    unknown = requested - known
    if unknown:
        raise ValueError(f"unknown qualification cases: {sorted(unknown)}")
    cases = tuple(
        item for item in suite_cases if not requested or f"{item[0]}/{item[1]}" in requested
    )
    if args.diagnostic_sweep and len(cases) != 1:
        raise ValueError("diagnostic sweep requires exactly one --cases program/case")
    programs = tuple(dict.fromkeys(("codegen", *(program for program, _, _ in cases))))
    built, control_baseline, control_more_work = build_images(
        args.toolchain.resolve(), args.control_toolchain.resolve(), output, programs,
        control_mm_source=args.control_mm_source.resolve(),
    )
    copies = output / "byte-copies"
    affinity = windows_physical_cpus() if os.name == "nt" else linux_physical_cpus()
    settings = windows_machine_settings if os.name == "nt" else linux_machine_settings
    result: dict[str, object] = {
        "machine_label": args.machine_label,
        "suite": args.suite,
        "diagnostic_sweep": args.diagnostic_sweep,
        "work_counter": (
            "QueryThreadCycleTime" if os.name == "nt" and args.suite == "single"
            else
            "QueryProcessCycleTime" if args.suite == "multithread" and os.name == "nt"
            else "summed perf CPU cycles" if args.suite == "multithread"
            else "xperf TotalCycles" if os.name == "nt"
            else "perf CPU cycles"
        ),
        "platform": platform.platform(),
        "toolchain": str(args.toolchain.resolve()),
        "toolchain_sha256": sha256(pulse.moon_toolchain_backend(args.toolchain.resolve())),
        "control_toolchain": str(args.control_toolchain.resolve()),
        "control_toolchain_sha256": sha256(pulse.moon_toolchain_backend(args.control_toolchain.resolve())),
        "control_mm_source": str(args.control_mm_source.resolve()),
        "control_mm_source_sha256": sha256(args.control_mm_source.resolve()),
        "affinity": affinity,
        "durations_ms": durations,
        "minimum_samples_per_process": MINIMUM_SAMPLES_PER_PROCESS,
        "processes_per_side": PROCESS_REPEATS,
        "minimum_sibling_idle_ratio": MINIMUM_SIBLING_IDLE_RATIO,
        "cases": {
            f"{program}/{case}": {"category": category, "attempts": {}, "passed": False}
            for program, case, category in cases
        },
        "negative_control": {"attempts": {}, "passed": False},
    }
    all_records: list[dict[str, object]] = []
    with settings() as machine_state:
        result["machine_settings"] = machine_state
        preflight = run_batch(
            [(built["codegen"], "codegen", "dep-add", "preflight", 0, "single-cpu", 0)],
            200,
            affinity,
            output,
            "preflight",
            enable_xperf=False if os.name == "nt" and args.suite == "single" else None,
        )
        if os.name == "nt" and args.suite == "single":
            for sample in preflight[0]["samples"]:
                sample["core_cycles"] = sample["thread_cycles"]
                sample["core_enabled"] = 1
                sample["core_running"] = 1
        preflight_metrics = record_metrics(preflight[0], False)
        result["preflight"] = preflight_metrics
        all_records.extend(preflight)
        if not preflight_metrics["valid"]:
            raise RuntimeError(f"frequency/counter preflight failed: {preflight_metrics}")

        pending = {(program, case) for program, case, _ in cases}
        control_pending = True
        for duration in durations:
            print(
                f"PULSE_METHOD_STAGE duration_ms={duration} "
                f"pending_cases={len(pending)} control_pending={int(control_pending)}",
                flush=True,
            )
            items: list[tuple[Path, str, str, str, int, str, int]] = []
            for program, case, category in cases:
                if (program, case) not in pending:
                    continue
                canonical = built[program]
                copied = copies / canonical.name
                for repeat in range(PROCESS_REPEATS):
                    variants = (("A", canonical), ("B", copied))
                    if repeat % 2:
                        variants = tuple(reversed(variants))
                    for position, (variant, executable) in enumerate(variants):
                        items.append(
                            (executable, program, case, variant, repeat, category, repeat * 2 + position)
                        )
            if control_pending:
                for repeat in range(PROCESS_REPEATS):
                    variants = (("work66", control_more_work), ("work64", control_baseline))
                    if repeat % 2:
                        variants = tuple(reversed(variants))
                    for position, (variant, executable) in enumerate(variants):
                        items.append(
                            (
                                executable,
                                "repairs-control",
                                "stddev-4",
                                variant,
                                repeat,
                                "control",
                                repeat * 2 + position,
                            )
                        )
            control_items = [item for item in items if item[5] == "control"]
            if args.suite == "multithread" or args.diagnostic_sweep:
                items = [item for item in items if item[5] != "control"]
            records = run_batch(
                items,
                duration,
                affinity,
                output,
                f"duration-{duration}ms",
                enable_xperf=False if os.name == "nt" and args.suite == "single" else None,
            )
            if os.name == "nt" and args.suite == "single":
                for record in records:
                    for sample in record["samples"]:
                        sample["core_cycles"] = sample["thread_cycles"]
                        sample["core_enabled"] = 1
                        sample["core_running"] = 1
            if (args.suite == "multithread" or args.diagnostic_sweep) and control_items:
                records.extend(
                    run_batch(
                        control_items,
                        duration,
                        affinity,
                        output,
                        f"control-duration-{duration}ms",
                        enable_xperf=False if os.name == "nt" and args.suite == "single" else None,
                    )
                )
                if os.name == "nt" and args.suite == "single":
                    for record in records:
                        if record["program"] != "repairs-control":
                            continue
                        for sample in record["samples"]:
                            sample["core_cycles"] = sample["thread_cycles"]
                            sample["core_enabled"] = 1
                            sample["core_running"] = 1
            all_records.extend(records)
            for program, case, category in cases:
                if (program, case) not in pending:
                    continue
                selected = [record for record in records if record["program"] == program and record["case"] == case]
                analysis = analyze_aa(selected, category)
                row = result["cases"][f"{program}/{case}"]
                row["attempts"][str(duration)] = analysis
                if analysis["passed"]:
                    row["passed"] = True
                    if "chosen_duration_ms" not in row:
                        row["chosen_duration_ms"] = duration
                    if not args.diagnostic_sweep:
                        pending.remove((program, case))
                    print(
                        f"PULSE_METHOD_CASE case={program}/{case} "
                        f"duration_ms={duration} work_spread={analysis['work_spread_percent']:.3f}% "
                        f"time_spread={analysis['tick_spread_percent']:.3f}% verdict=PASS",
                        flush=True,
                    )
                else:
                    print(
                        f"PULSE_METHOD_CASE case={program}/{case} "
                        f"duration_ms={duration} work_spread={analysis['work_spread_percent']:.3f}% "
                        f"time_spread={analysis['tick_spread_percent']:.3f}% verdict="
                        f"{'FAIL' if duration == durations[-1] else 'RETRY'}",
                        flush=True,
                    )
            if control_pending:
                selected = [record for record in records if record["program"] == "repairs-control"]
                analysis = analyze_control(selected)
                result["negative_control"]["attempts"][str(duration)] = analysis
                result["negative_control"]["final"] = analysis
                if analysis["passed"]:
                    result["negative_control"]["passed"] = True
                    result["negative_control"]["chosen_duration_ms"] = duration
                    control_pending = False
                print(
                    f"PULSE_METHOD_CONTROL duration_ms={duration} verdict="
                    f"{'PASS' if analysis['passed'] else ('FAIL' if duration == durations[-1] else 'RETRY')}",
                    flush=True,
                )
            if not args.diagnostic_sweep and not pending and not control_pending:
                break
    if args.diagnostic_sweep:
        for row in result["cases"].values():
            attempts = sorted(
                ((int(duration), attempt) for duration, attempt in row["attempts"].items()),
                key=lambda item: item[0],
            )
            stable_duration = None
            if len(attempts) == 1:
                if attempts[0][1]["passed"]:
                    stable_duration = attempts[0][0]
            else:
                for index, (duration, _) in enumerate(attempts[:-1]):
                    if all(attempt["passed"] for _, attempt in attempts[index:]):
                        stable_duration = duration
                        break
            row["passed"] = stable_duration is not None
            if stable_duration is None:
                row.pop("chosen_duration_ms", None)
            else:
                row["chosen_duration_ms"] = stable_duration
    result["passed"] = (
        all(bool(row["passed"]) for row in result["cases"].values())
        and bool(result["negative_control"]["passed"])
    )
    (output / "records.json").write_text(json.dumps(all_records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_report(output, result)
    print(f"PULSE_METHOD_RESULT {'PASS' if result['passed'] else 'FAIL'} {output}")
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        failure = traceback.format_exc()
        try:
            output_index = sys.argv.index("--output") + 1
            Path(sys.argv[output_index] + ".failure.log").write_text(
                failure, encoding="utf-8"
            )
        except Exception:
            pass
        sys.stderr.write(failure)
        raise
