#!/usr/bin/env python3
"""Химера: кодоформы Арбитража и MoonBot.

           Quidquid latet apparebit, nil inultum remanebit.
                           Festina lente.

Третья большая программа комплекта. У резидента предмет проверки — счёт под
нагрузкой, у завода — устройство приложения. Здесь — формы, из которых
СОСТОЯТ два живых проекта: ничего не придумано, каждый орган сшит из
настоящего куска настоящего кода.

Каждая работа живёт в химере несколькими телами сразу — от монолита с сорока
живыми значениями до дробления на вставляемые шаги — и все обязаны дать один
ответ. Сверка идёт внутри самой программы, поэтому расхождение доказывает
дефект само по себе, без второй сборки для сравнения.

Гейт добавляет к этому три вещи, которых программа о себе знать не может:

* **профили и ключи** — весь набор, включая каждую оптимизацию по отдельности:
  слитный профиль может не задействовать то преобразование, из-за которого
  форма и ломается;
* **карта вставок** — компилятор сообщает, какие тела он вставить отказался.
  Химера нарочно держит один и тот же текст в двух местах: там, где вставка
  работает, и там, где она мертва по положению юнита в кольце зависимостей.
  Если карта разъехалась с ожидаемой, ось «вставлено против невставлено»
  перестала существовать — тест продолжает печатать OK, проверяя половину
  задуманного. Молчать об этом нельзя;
* **сверка ответа между сборками** — число обязано быть одним и тем же.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc

ROOT = Path(__file__).resolve().parents[1]
CHIMERA = ROOT / "tests" / "chimera"

SWITCHES = (
    "REGVAR", "STACKFRAME", "PEEPHOLE", "LOOPUNROLL", "TAILREC", "CSE", "DFA",
    "STRENGTH", "AUTOINLINE", "USERBP", "ORDERFIELDS", "REMOVEEMPTYPROCS",
    "CONSTPROP", "USELOADMODIFYSTORE", "UNUSEDPARA", "FORLOOP", "MEMINLINE",
    "EFFECTOBSERVE", "FASTMATH",
)

# Чистые шаги прохода по ленте. Химера подключает их текст ДВАЖДЫ: из листового
# юнита, откуда вставка работает, и из юнита в кольце зависимостей, откуда она
# мертва. Значит компилятор обязан отказаться ровно от этих девяти и ни от чего
# больше — иначе одна из двух половин оси исчезла.
EXPECT_REFUSED = {
    "XAfter", "XBucket", "XDelta", "XEma", "XIsSell", "XMinuteRaw",
    "XMinuteSlot", "XNotional", "XSameSecond",
}

REFUSED = re.compile(r'marked as inline is not inlined')
NAMED = re.compile(r'"(?:function|procedure)\s+(\w+)')


def refused_names(text: str) -> set[str]:
    """Имена подпрограмм, которые компилятор вставить отказался."""
    names = set()
    for line in text.splitlines():
        if not REFUSED.search(line):
            continue
        # заметки про сам компилятор и его библиотеку памяти к делу не идут
        if "fpcx64mm" in line:
            continue
        found = NAMED.search(line)
        if found:
            names.add(found.group(1))
    return names


def build_and_run(out: Path, profile: str, extra: list[str],
                  timeout: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    build = subprocess.run(
        tc.compile_command(CHIMERA / "chimera.dpr", out, profile,
                           search=[CHIMERA], extra=extra),
        cwd=CHIMERA, capture_output=True, text=True, errors="replace",
        timeout=timeout)
    text = (build.stdout or "") + (build.stderr or "")
    if build.returncode != 0:
        errors = [l for l in text.splitlines() if "Error" in l or "Fatal" in l]
        return {"built": False, "errors": errors[:4]}
    run = subprocess.run([str(tc.executable(out, "chimera"))], cwd=CHIMERA,
                         capture_output=True, text=True, errors="replace",
                         timeout=timeout)
    lines = (run.stdout or "").strip().splitlines()
    return {"built": True, "exit": run.returncode,
            "output": lines[0] if lines else "(пусто)",
            "refused": sorted(refused_names(text))}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "chimera-gate")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--quick", action="store_true",
                        help="только четыре профиля, без перебора ключей")
    args = parser.parse_args()

    tc.preflight()
    args.work.mkdir(parents=True, exist_ok=True)
    started = time.time()

    plan = [("debug", []), ("o1", []), ("o2", []), ("release", [])]
    if not args.quick:
        plan += [("o1", ["-Oo" + s]) for s in SWITCHES]
        plan += [("release", ["-OoNO" + s]) for s in SWITCHES]

    rows: list[dict] = []
    findings: list[dict] = []
    expected = None

    for profile, extra in plan:
        tag = profile + (("/" + extra[0]) if extra else "")
        out = args.work / ("out-" + profile
                           + ("-" + extra[0].replace("-", "") if extra else ""))
        result = build_and_run(out, profile, extra, args.timeout)
        rows.append({"profile": profile, "extra": extra, **result})

        if not result["built"]:
            findings.append({"kind": "build-failed", "case": tag,
                             "errors": result["errors"]})
            print(f"СБОРКА УПАЛА   {tag}")
            for line in result["errors"][:2]:
                print("    ", line[:150])
            continue

        output = result["output"]
        if not output.startswith("CHIMERA_OK"):
            findings.append({"kind": "claim-failed", "case": tag,
                             "output": output})
            print(f"УТВЕРЖДЕНИЕ    {tag}  {output[:120]}")
            continue

        if expected is None:
            expected = output
            print(f"эталон [{tag}]: {output}")
        elif output != expected:
            findings.append({"kind": "answer-differs", "case": tag,
                             "output": output, "expected": expected})
            print(f"ОТВЕТ РАЗОШЁЛСЯ {tag}  {output[:120]}")

        # Карта вставок. Ключ AUTOINLINE выключает вставку целиком — тогда
        # отказ от всего и есть ожидаемое поведение, а не потеря оси.
        refused = set(result["refused"])
        if extra and "AUTOINLINE" in extra[0]:
            continue
        if refused != EXPECT_REFUSED:
            lost = EXPECT_REFUSED - refused
            extra_names = refused - EXPECT_REFUSED
            findings.append({"kind": "inline-map-changed", "case": tag,
                             "unexpectedly_inlined": sorted(lost),
                             "unexpectedly_refused": sorted(extra_names)})
            print(f"КАРТА ВСТАВОК  {tag}")
            if lost:
                print("     вставилось то, что не должно:", ", ".join(sorted(lost)))
            if extra_names:
                print("     отказано в том, что должно вставляться:",
                      ", ".join(sorted(extra_names)))

    report = {"expected": expected, "rows": rows, "findings": findings,
              "seconds": round(time.time() - started, 1)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")

    print()
    print(f"сборок: {len(rows)}  за {report['seconds']}с")
    if findings:
        print(f"CHIMERA_GATE FINDINGS findings={len(findings)}")
        return 1
    print(f"CHIMERA_GATE OK builds={len(rows)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
