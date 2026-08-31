#!/usr/bin/env python3
"""Вторая большая программа: проверка устройства, а не счёта.

`plant` собрана так, как собирают настоящие приложения: обёртка над чужой
библиотекой с обратными вызовами и статическим реестром, менеджер движков с
породами, которые сами вписываются в реестр при инициализации, слой сервисов
на интерфейсах со счётчиком ссылок, и легальные циклы заголовков между слоями.
Считает она немного, зато ответ известен точно — те же величины пересчитаны
внутри неё плоской арифметикой.

Гейт гоняет её по трём осям сразу:

* **профили** — все четыре, от `-O-` до `-O3`;
* **отдельные ключи** — каждый включается поверх `-O1` и выключается из `-O3`,
  потому что слитный профиль может не задействовать то преобразование, из-за
  которого форма и ломается;
* **порядок инициализации** — юниты переставляются в списке `uses` главной
  программы. Состав реестра движков складывается до входа в главный блок, и
  приложение обязано работать при любом законном порядке.

Находкой считается и падение сборки, и любой вывод, кроме ожидаемого.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
PLANT = ROOT / "tests" / "plant"

SWITCHES = (
    "REGVAR", "STACKFRAME", "PEEPHOLE", "LOOPUNROLL", "TAILREC", "CSE", "DFA",
    "STRENGTH", "AUTOINLINE", "USERBP", "ORDERFIELDS", "REMOVEEMPTYPROCS",
    "CONSTPROP", "USELOADMODIFYSTORE", "UNUSEDPARA", "FORLOOP", "MEMINLINE",
    "EFFECTOBSERVE", "FASTMATH",
)

# Юниты, порядок которых в списке главной программы можно менять: от него
# зависит порядок секций инициализации, а значит и состав реестра.
SHUFFLED = ["plant_api", "plant_types", "plant_glue", "plant_engine",
            "plant_factory", "plant_engine_mixer", "plant_engine_sink",
            "plant_service", "plant_app"]

ORDERS = {
    "as-written": SHUFFLED,
    "reversed": list(reversed(SHUFFLED)),
    "породы-первыми": ["plant_engine_mixer", "plant_engine_sink", "plant_app",
                       "plant_service", "plant_factory", "plant_engine",
                       "plant_glue", "plant_types", "plant_api"],
    "приложение-первым": ["plant_app", "plant_engine_sink", "plant_engine_mixer",
                          "plant_service", "plant_glue", "plant_factory",
                          "plant_engine", "plant_types", "plant_api"],
}


def make_variant(work: Path, name: str, order: list[str]) -> Path:
    """Копия программы с переставленным списком юнитов."""
    case = work / ("order-" + name)
    if case.exists():
        shutil.rmtree(case)
    case.mkdir(parents=True)
    for src in PLANT.glob("*.pas"):
        shutil.copy2(src, case / src.name)

    text = (PLANT / "plant.dpr").read_text(encoding="utf-8")
    block = re.search(r"  SysUtils,\n(?:  plant_\w+[,;]\n)+", text)
    if block is None:
        raise SystemExit("не нашёл список юнитов в plant.dpr")
    listing = "  SysUtils,\n" + ",\n".join("  " + u for u in order) + ";\n"
    text = text[:block.start()] + listing + text[block.end():]
    # хвостовая точка с запятой могла остаться от прежнего последнего юнита
    text = text.replace(";\n\nconst", ";\n\nconst")
    (case / "plant.dpr").write_text(text, encoding="utf-8")
    return case


def build_and_run(case: Path, out: Path, profile: str, extra: list[str],
                  timeout: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    build = subprocess.run(
        tc.compile_command(case / "plant.dpr", out, profile, search=[case],
                           extra=extra),
        cwd=case, capture_output=True, text=True, errors="replace",
        timeout=timeout)
    if build.returncode != 0:
        text = (build.stdout or "") + (build.stderr or "")
        errors = [l for l in text.splitlines() if "Error" in l or "Fatal" in l]
        return {"built": False, "errors": errors[:4]}
    run = subprocess.run([str(tc.executable(out, "plant"))], cwd=case,
                         capture_output=True, text=True, errors="replace",
                         timeout=timeout)
    line = (run.stdout or "").strip().splitlines()
    return {"built": True, "exit": run.returncode,
            "output": line[0] if line else "(пусто)"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "plant-gate")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--quick", action="store_true",
                        help="только профили и порядки, без перебора ключей")
    args = parser.parse_args()

    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    tc.preflight()
    args.work = args.work.resolve()
    if args.report:
        args.report = args.report.resolve()
    args.work.mkdir(parents=True, exist_ok=True)
    started = time.time()

    cases = {name: make_variant(args.work, name, order)
             for name, order in ORDERS.items()}

    plan = [("debug", []), ("o1", []), ("o2", []), ("release", [])]
    if not args.quick:
        plan += [("o1", ["-Oo" + s]) for s in SWITCHES]
        plan += [("release", ["-OoNO" + s]) for s in SWITCHES]

    rows: list[dict] = []
    findings: list[dict] = []
    expected = None

    for order_name, case in cases.items():
        for profile, extra in plan:
            tag = f"{order_name}/{profile}{('/' + extra[0]) if extra else ''}"
            out = case / ("out-" + profile + ("-" + extra[0].replace("-", "")
                                              if extra else ""))
            result = build_and_run(case, out, profile, extra, args.timeout)
            rows.append({"order": order_name, "profile": profile,
                         "extra": extra, **result})

            if not result["built"]:
                findings.append({"kind": "build-failed", "case": tag,
                                 "errors": result["errors"]})
                print(f"BUILD FAILED  {tag}")
                for line in result["errors"][:2]:
                    print("    ", line[:150])
                continue

            output = result["output"]
            if not output.startswith("PLANT_OK"):
                findings.append({"kind": "wrong-answer", "case": tag,
                                 "output": output})
                print(f"WRONG ANSWER  {tag}  {output[:110]}")
                continue

            # Числа обязаны совпадать у всех сборок и всех порядков.
            if expected is None:
                expected = output
                print(f"эталон [{tag}]: {output}")
            elif output != expected:
                findings.append({"kind": "numbers-differ", "case": tag,
                                 "output": output, "expected": expected})
                print(f"NUMBERS DIFFER  {tag}  {output[:110]}")

    report = {"expected": expected, "rows": rows, "findings": findings,
              "seconds": round(time.time() - started, 1)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")

    print()
    print(f"сборок: {len(rows)}  порядков: {len(cases)}  за {report['seconds']}с")
    if findings:
        print(f"PLANT_GATE FINDINGS findings={len(findings)}")
        return 1
    print(f"PLANT_GATE OK builds={len(rows)} orders={len(cases)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
