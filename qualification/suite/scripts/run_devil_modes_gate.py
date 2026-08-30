#!/usr/bin/env python3
"""Гейт режимов: ключи сборки не должны менять поведение программы.

Основной гейт варьирует уровень оптимизации — это ось, где расхождение
ожидаемо и интересно. Но у сборки есть и другие ручки, которые **не имеют права**
влиять ни на что: формат отладочной информации, умная компоновка, срезание
символов, многословность, порядок ключей в командной строке, пересборка с нуля
против сборки поверх готовых PPU.

Каждая из них меняет содержимое артефактов совершенно законно (в образе больше
или меньше данных), поэтому здесь сравниваются **не байты, а поведение**:
корневой дайджест программы, число проверок, число вливаний и шагов, весь набор
наблюдений. Расхождение означает, что решение компилятора о коде зависит от
ручки, которая к коду отношения не имеет.

Разница с гейтом окружения: там трясут то, что снаружи исходника, и требуют
побайтового совпадения; здесь трясут сами ключи и требуют совпадения смысла.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc
from run_devil_gate import Build, DEVIL, GENERATOR, run

ROOT = Path(__file__).resolve().parents[1]

# ручки, которым запрещено влиять на поведение
MODES = (
    ("baseline", []),
    # -gl is not metadata-only: FPC deliberately links the LineInfo unit.
    # Compare DWARF formats while keeping the linked unit graph unchanged.
    ("dwarf-v2", ["-gw2"]),
    ("smart-linking", ["-CX", "-XX"]),
    ("strip-symbols", ["-Xs"]),
    ("quiet", ["-vw-", "-vn-", "-vh-"]),
    ("verbose", ["-vwnhi"]),
    ("assertions-off", ["-Sa-"]),
    ("no-rebuild", []),          # без -B: поверх готовых PPU
)


def say(*parts: object) -> None:
    print("[%s]" % time.strftime("%H:%M:%S"), *parts, flush=True)


def build_failure_detail(log: str) -> str:
    """Keep the linker/compiler cause, not only FPC's final wrapper error."""
    selected: list[str] = []
    for line in log.splitlines():
        stripped = line.strip()
        if ("Error" in stripped or "Fatal" in stripped or
                "cannot find" in stripped or "undefined reference" in stripped):
            if stripped not in selected:
                selected.append(stripped)
        if len(selected) == 4:
            break
    return " | ".join(selected)[:500] if selected else "?"


def behaviour(work: Path, label: str, extra: list[str], profile: str,
              timeout: int, rebuild: bool = True) -> tuple[Build | None, str]:
    """Собрать с добавленными ключами и снять поведение программы."""
    build = Build(label)
    out = work / ("out-mode-" + label)
    if rebuild and out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    cmd = tc.compile_command(work / "devil.dpr", out, profile, extra=extra)
    if not rebuild:
        cmd = [c for c in cmd if c != "-B"]
    code, log = run(cmd, work, timeout)
    if code != 0:
        return None, "REJECTED: " + build_failure_detail(log)
    exe = tc.executable(out, "devil")
    if not exe.exists():
        return None, "REJECTED: no executable"
    code, output = run([str(exe)], work, min(timeout, 300))
    if code == 124:
        return None, "REJECTED: timeout while running"
    build.compiled = True
    build.parse(output)
    return build, ""


def compare(reference: Build, other: Build, label: str) -> list[dict]:
    findings: list[dict] = []
    if reference.digest != other.digest:
        findings.append({"kind": "behaviour-depends-on-mode", "mode": label,
                         "what": "digest",
                         "builds": {"baseline": reference.digest,
                                    label: other.digest}})
    if reference.checks != other.checks:
        findings.append({"kind": "behaviour-depends-on-mode", "mode": label,
                         "what": "checks",
                         "builds": {"baseline": reference.checks,
                                    label: other.checks}})
    for what in ("FEEDS", "STEPS"):
        a = reference.counters.get(what, -1)
        b = other.counters.get(what, -1)
        if a != b:
            findings.append({"kind": "behaviour-depends-on-mode", "mode": label,
                             "what": what.lower(),
                             "builds": {"baseline": a, label: b}})
    names = set(reference.notes) | set(other.notes)
    split = sorted(n for n in names
                   if reference.notes.get(n) != other.notes.get(n))
    if split:
        findings.append({"kind": "observation-depends-on-mode", "mode": label,
                         "notes": split[:8], "count": len(split)})
    fresh = sorted(set(other.failures) - set(reference.failures))
    if fresh:
        findings.append({"kind": "check-fails-only-in-mode", "mode": label,
                         "checks": fresh[:8], "count": len(fresh)})
    return findings


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--seed", type=int, default=17)
    p.add_argument("--cases", type=int, default=60)
    p.add_argument("--layers", default="all")
    p.add_argument("--profile", default="release")
    p.add_argument("--timeout", type=int, default=900)
    p.add_argument("--work", type=Path, default=ROOT / "work-modes")
    p.add_argument("--report", type=Path)
    args = p.parse_args()

    tc.preflight()
    work = args.work.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    shutil.copy(DEVIL / "devil_runtime.pas", work / "devil_runtime.pas")

    code, log = run([sys.executable, str(GENERATOR), "--seed", str(args.seed),
                     "--cases", str(args.cases), "--layers", args.layers,
                     "--out", str(work)], ROOT, args.timeout)
    if code != 0:
        say("generator refused:", log[-300:])
        raise SystemExit(2)
    say("source ready: seed", args.seed, "layers", args.layers)

    findings: list[dict] = []
    reference: Build | None = None
    for label, extra in MODES:
        rebuild = label != "no-rebuild"
        got, failure = behaviour(work, label, extra, args.profile,
                                 args.timeout, rebuild)
        if got is None:
            say("%-16s %s" % (label, failure))
            findings.append({"kind": "build-failed-in-mode", "mode": label,
                             "detail": failure})
            continue
        if reference is None:
            reference = got
            say("%-16s reference: %d checks, digest %s"
                % (label, got.checks, got.digest))
            continue
        fresh = compare(reference, got, label)
        if fresh:
            say("%-16s DIFFERS: %s"
                % (label, ", ".join(sorted({f["kind"] for f in fresh}))))
            findings += fresh
        else:
            say("%-16s same behaviour" % label)

    if args.report:
        args.report.write_text(json.dumps(findings, ensure_ascii=False,
                                          indent=2), encoding="utf-8")
    if findings:
        for f in findings:
            print("  NEW " + json.dumps(f, ensure_ascii=False, sort_keys=True))
        print("DEVIL_MODES FINDINGS modes=%d findings=%d"
              % (len(MODES), len(findings)))
        raise SystemExit(1)
    print("DEVIL_MODES OK modes=%d" % len(MODES))


if __name__ == "__main__":
    main()
