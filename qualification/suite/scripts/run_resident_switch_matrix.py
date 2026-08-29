#!/usr/bin/env python3
"""Каждая оптимизация по отдельности, а не только слитные профили.

Профили драйвера — четыре точки: `-O-`, `-O1`, `-O2`, `-O3`. Между ними
включается сразу десяток преобразований, и когда что-то ломается, виноватого
приходится искать руками. Хуже того: дефект, который живёт ровно в одном
преобразовании, виден только если это преобразование включить отдельно —
слитный профиль может его и не задействовать.

Поэтому здесь строится матрица: базовый `-O1` плюс каждая оптимизация по
одной, и боевой `-O3` минус каждая оптимизация по одной. Первая половина
отвечает на вопрос «что ломает эта оптимизация сама по себе», вторая — «без
чего боевой профиль начинает работать».

Проверяются две вещи, и обе — находки:

* **сборка**. Компилятор обязан собрать корректный исходник при любом наборе
  ключей. Падение сборки — дефект компилятора, даже если программа потом
  ничего не считает.
* **ответ**. Корень резидента не зависит ни от одной оптимизации: все они
  обязаны сохранять смысл программы.

Единственное исключение — `FASTMATH`: он сознательно разрешает переписывать
вещественную арифметику, и семейство `floatorder` ровно это и запрещает.
Для него проверяется только сборка и отсутствие падения, а расхождение ответа
ожидаемо и находкой не является.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
RESIDENT = ROOT / "tests" / "resident" / "resident.dpr"

SWITCHES = (
    "REGVAR", "STACKFRAME", "PEEPHOLE", "LOOPUNROLL", "TAILREC", "CSE", "DFA",
    "STRENGTH", "AUTOINLINE", "USERBP", "ORDERFIELDS", "REMOVEEMPTYPROCS",
    "CONSTPROP", "USELOADMODIFYSTORE", "UNUSEDPARA", "FORLOOP", "MEMINLINE",
    "EFFECTOBSERVE",
)

# Переписывает вещественную арифметику по своему усмотрению — расхождение
# ответа здесь разрешено самим смыслом ключа.
SEMANTIC_SWITCHES = ("FASTMATH",)


def build_and_run(work: Path, out: Path, extra: list[str], profile: str,
                  carriers: int, laps: int, timeout: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    started = time.time()
    build = subprocess.run(
        tc.compile_command(RESIDENT, out, profile, extra=extra),
        cwd=RESIDENT.parent, capture_output=True, text=True,
        errors="replace", timeout=timeout)
    if build.returncode != 0:
        text = (build.stdout or "") + (build.stderr or "")
        errors = [l for l in text.splitlines() if "Error" in l or "Fatal" in l]
        return {"built": False, "seconds": round(time.time() - started, 1),
                "errors": errors[:6]}

    run = subprocess.run(
        [str(tc.executable(out, "resident")), "--carriers", str(carriers),
         "--laps", str(laps)],
        cwd=RESIDENT.parent, capture_output=True, text=True,
        errors="replace", timeout=timeout)
    answers = {}
    for line in (run.stdout or "").splitlines():
        for key in ("RESIDENT_ROOT", "RESIDENT_BROKEN", "RESIDENT_STAGES",
                    "RESIDENT_FAULTS", "RESIDENT_DRIFTED", "RESIDENT_CORRUPTED"):
            if line.startswith(key + " "):
                answers[key] = line.split(" ", 1)[1].strip()
    failure = [l for l in (run.stdout or "").splitlines()
               if l.startswith("RESIDENT_FAILURE")]
    return {"built": True, "exit": run.returncode,
            "seconds": round(time.time() - started, 1),
            "answers": answers, "failure": failure[:1]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--carriers", type=int, default=4)
    parser.add_argument("--laps", type=int, default=6)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "resident-switches")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--only", help="проверить один ключ")
    args = parser.parse_args()

    tc.preflight()
    args.work.mkdir(parents=True, exist_ok=True)

    switches = SWITCHES if not args.only else tuple(
        s for s in SWITCHES + SEMANTIC_SWITCHES if s == args.only.upper())
    if args.only and not switches:
        print("unknown switch:", args.only)
        return 2

    rows: list[dict] = []
    findings: list[dict] = []

    # Эталон: боевой профиль как есть.
    base = build_and_run(args.work, args.work / "base-release", [], "release",
                         args.carriers, args.laps, args.timeout)
    if not base["built"]:
        print("BASE RELEASE DID NOT BUILD")
        for line in base["errors"]:
            print("  ", line[:160])
        return 1
    root = base["answers"].get("RESIDENT_ROOT")
    print(f"base release: root={root} broken={base['answers'].get('RESIDENT_BROKEN')} "
          f"in {base['seconds']}s")

    plan = []
    for switch in switches:
        plan.append(("o1+" + switch, "o1", ["-Oo" + switch], switch))
        plan.append(("release-" + switch, "release", ["-OoNO" + switch], switch))
    if not args.only:
        for switch in SEMANTIC_SWITCHES:
            plan.append(("o1+" + switch, "o1", ["-Oo" + switch], switch))
            plan.append(("release-" + switch, "release", ["-OoNO" + switch], switch))

    for name, profile, extra, switch in plan:
        result = build_and_run(args.work, args.work / name, extra, profile,
                               args.carriers, args.laps, args.timeout)
        row = {"case": name, "switch": switch, "profile": profile,
               "extra": extra, **result}
        rows.append(row)

        if not result["built"]:
            findings.append({"case": name, "kind": "build-failed",
                             "errors": result["errors"]})
            print(f"{name:32s} BUILD FAILED  {result['errors'][:1]}")
            continue

        broken = result["answers"].get("RESIDENT_BROKEN", "?")
        got = result["answers"].get("RESIDENT_ROOT")
        note = ""

        if result["exit"] != 0 or broken not in ("0",):
            findings.append({"case": name, "kind": "claim-broken",
                             "broken": broken, "failure": result["failure"]})
            note = "  BROKEN=" + broken

        # Оптимизация не имеет права менять ответ; исключение объявлено выше.
        if switch not in SEMANTIC_SWITCHES and got != root:
            findings.append({"case": name, "kind": "root-differs",
                             "root": got, "expected": root})
            note += "  ROOT DIFFERS"

        print(f"{name:32s} ok root={got} {result['seconds']}s{note}")

    report = {"base_root": root, "rows": rows, "findings": findings}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")

    print()
    if findings:
        print(f"RESIDENT_SWITCHES FINDINGS cases={len(rows)} findings={len(findings)}")
        return 1
    print(f"RESIDENT_SWITCHES OK cases={len(rows)} switches={len(switches)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
