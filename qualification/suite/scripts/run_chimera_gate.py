#!/usr/bin/env python3
"""Химера: кодоформы Арбитража и MoonBot.

           Quidquid latet apparebit, nil inultum remanebit.
                           Festina lente.

Третья большая программа комплекта. У резидента предмет проверки — счёт под
нагрузкой, у завода — устройство приложения. Здесь — формы, из которых
СОСТОЯТ два живых проекта: ничего не придумано, каждый орган сшит из
настоящего куска настоящего кода.

Сверка тел идёт внутри самой программы, поэтому расхождение доказывает дефект
само по себе, без второй сборки для сравнения. Гейт добавляет к этому четыре
вещи, которых программа о себе знать не может.

**Перепись против исполнения.** `tests/chimera/INVENTORY.md` — ручной список
работ, `inventory.json` — его машиночитаемая половина. Программа при каждом
запуске печатает, какие строки переписи она отработала и какие ветви внутри
них реально исполнились. Гейт сводит три источника: строка без исполнения —
незакрытая работа; исполнение без строки — неизвестный идентификатор; ветвь с
нулём — код, который присутствует, но не работает. Всё это останавливает
прогон. Проверка не косметическая: она сразу поймала ветвь досрочного выхода,
которая не исполнялась ни разу, пока программа печатала OK.

**Незакрытые строки.** Перепись с дырой не является переписью, поэтому
`open` по умолчанию валит прогон. `--allow-open` существует только для
промежуточной разработки и честно печатает, сколько работ ещё не перенесено.

**Карта вставок.** Компилятор сообщает, какие тела он вставить отказался.
Химера нарочно держит один и тот же текст там, где вставка работает, и там,
где она мертва по положению юнита в кольце зависимостей. Разъехалась карта —
ось «вставлено против невставлено» перестала существовать, а программа
продолжает печатать OK, проверяя половину задуманного.

**Профили и ключи — по требованию.** Химера проверяет себя сама, поэтому по
умолчанию гоняется ОДИН боевой профиль: этого хватает для вердикта. Флаг
`--profiles` добавляет остальные уровни оптимизации, `--switches` — каждую
оптимизацию по отдельности. Расхождение ответа между сборками есть второй,
независимый от программы оракул: он ловит случай, когда внутренние проверки
слепы, — когда все тела сломались одинаково. Такое уже встречалось:
`Devil-0067` виден только при `-O3 -OoNOREGVAR` и ни в одном слитном профиле.
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
# Провод Арбитража стоит на настоящем AES-GCM из продуктовой линии mORMot:
# подменять шифр игрушкой значило бы проверять не ту работу.
MORMOT = ROOT.parents[1] / "qualification" / "vendor" / "mormot-product"


# На Windows mORMot подключает эти два объекта жёстким относительным путём из
# `..\static\delphi`. Они являются частью закреплённого qualification input и
# хранятся рядом с vendor source; preflight защищает от неполной копии репы.
WINDOWS_OBJECTS = ("sha512-x64sse4.obj", "crc32c64.obj")


def check_mormot_objects() -> None:
    """Fail before linking when the pinned Windows vendor is incomplete."""
    if sys.platform != "win32":
        return
    delphi = MORMOT / "static" / "delphi"
    missing = [n for n in WINDOWS_OBJECTS if not (delphi / n).is_file()]
    if not missing:
        return
    raise SystemExit(
        "incomplete pinned mORMot input: missing " + ", ".join(missing)
        + f" in {delphi}")


def mormot_options() -> list[str]:
    src = MORMOT / "src"
    static = MORMOT / "static" / ("x86_64-win64" if sys.platform == "win32"
                                  else "x86_64-linux")
    units = sorted({p.parent for p in src.rglob("*.pas")})
    # Объектные файлы подключаются в mORMot относительным путём от `src`,
    # поэтому каталог объектов обязан указывать именно на него.
    return ([f"-Fl{static}", f"-Fo{src}", f"-Fi{src}"]
            + [f"-Fu{d}" for d in units])

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

REFUSED = re.compile(r"marked as inline is not inlined")
NAMED = re.compile(r'"(?:function|procedure)\s+(\w+)')
COVER = re.compile(r"^CHI_COVER\s+(\S+)(.*)$")


def refused_names(text: str) -> set[str]:
    """Имена подпрограмм, которые компилятор вставить отказался."""
    names = set()
    for line in text.splitlines():
        if not REFUSED.search(line) or "fpcx64mm" in line:
            continue
        found = NAMED.search(line)
        if found:
            names.add(found.group(1))
    return names


def parse_coverage(text: str) -> dict[str, dict[str, int]]:
    """Что программа предъявила исполнением: строка → ветвь → сколько раз."""
    seen: dict[str, dict[str, int]] = {}
    for line in text.splitlines():
        found = COVER.match(line.strip())
        if not found:
            continue
        branches: dict[str, int] = {}
        for part in found.group(2).split():
            if "=" in part:
                name, _, count = part.partition("=")
                branches[name] = int(count)
        seen[found.group(1)] = branches
    return seen


def load_inventory() -> tuple[list[dict], list[str]]:
    """Перепись плюс расхождения между ручной и машиночитаемой половинами."""
    problems: list[str] = []
    manifest = CHIMERA / "inventory.json"
    document = CHIMERA / "INVENTORY.md"
    if not manifest.is_file():
        return [], [f"нет манифеста переписи: {manifest}"]
    rows = json.loads(manifest.read_text(encoding="utf-8")).get("rows", [])
    if not rows:
        return [], ["манифест переписи пуст"]

    if document.is_file():
        text = document.read_text(encoding="utf-8")
        in_doc = set(re.findall(r"CHI-[A-Z0-9]+-[A-Z0-9]+-\d+", text))
        in_manifest = {r["id"] for r in rows}
        for lost in sorted(in_manifest - in_doc):
            problems.append(f"{lost}: есть в манифесте, нет в INVENTORY.md")
        for lost in sorted(in_doc - in_manifest):
            problems.append(f"{lost}: есть в INVENTORY.md, нет в манифесте")
    else:
        problems.append("нет ручной переписи INVENTORY.md")
    return rows, problems


def resolve_focus(rows: list[dict], focus: str | None) -> str | None:
    """Translate any covered inventory id to the organ selected by the DPR."""
    if not focus:
        return None
    organs = {
        row.get("organ")
        for row in rows
        if row.get("status") == "covered"
        and focus in (row.get("id"), row.get("organ"),
                      (row.get("organ") or "").removeprefix("chimera_"))
    }
    organs.discard(None)
    if not organs:
        raise SystemExit(f"unknown or non-executable Chimera focus: {focus}")
    if len(organs) != 1:
        raise SystemExit(f"ambiguous Chimera focus: {focus}")
    return organs.pop().removeprefix("chimera_")


def check_inventory(rows: list[dict], seen: dict[str, dict[str, int]],
                    focus: str | None, allow_open: bool) -> list[dict]:
    """Fail-closed сверка переписи с тем, что реально исполнилось."""
    findings: list[dict] = []
    known = {r["id"] for r in rows}

    for row in rows:
        status = row.get("status", "")
        rid = row["id"]
        if status == "open":
            if not allow_open:
                findings.append({"kind": "inventory-open", "id": rid,
                                 "detail": "работа не перенесена"})
            continue
        if not (status == "covered" or status.startswith("merged-with")
                or status.startswith("excluded")):
            findings.append({"kind": "inventory-status", "id": rid,
                             "detail": f"недопустимый статус: {status!r}"})
            continue
        if status != "covered":
            continue

        # Сфокусированный прогон не обязан предъявлять чужие строки.
        if focus and focus not in (rid, row.get("organ") or "",
                                   (row.get("organ") or "").replace(
                                       "chimera_", "")):
            continue
        if not row.get("organ"):
            findings.append({"kind": "inventory-organ", "id": rid,
                             "detail": "covered без органа"})
        if rid not in seen:
            findings.append({"kind": "coverage-missing", "id": rid,
                             "detail": "строка закрыта, но не исполнялась"})
            continue
        for branch in row.get("branches", []):
            if seen[rid].get(branch, 0) <= 0:
                findings.append({"kind": "branch-dead", "id": rid,
                                 "detail": f"ветвь не исполнилась: {branch}"})

    for rid in sorted(seen):
        if rid not in known:
            findings.append({"kind": "coverage-unknown", "id": rid,
                             "detail": "исполнено, но нет строки переписи"})
    return findings


def build_and_run(out: Path, profile: str, extra: list[str], focus: str | None,
                  timeout: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    build = subprocess.run(
        tc.compile_command(CHIMERA / "chimera.dpr", out, profile,
                           search=[CHIMERA], extra=extra + mormot_options()),
        cwd=CHIMERA, capture_output=True, text=True, errors="replace",
        timeout=timeout)
    text = (build.stdout or "") + (build.stderr or "")
    (out / "compile.log").write_text(text, encoding="utf-8")
    if build.returncode != 0:
        errors = [l for l in text.splitlines() if "Error" in l or "Fatal" in l]
        return {"built": False, "errors": errors[:4]}

    command = [str(tc.executable(out, "chimera"))]
    if focus:
        command += ["--focus", focus]
    run = subprocess.run(command, cwd=CHIMERA, capture_output=True, text=True,
                         errors="replace", timeout=timeout)
    output = (run.stdout or "") + (run.stderr or "")
    (out / "run.log").write_text(output, encoding="utf-8")
    verdict = ""
    for line in output.splitlines():
        if line.startswith("CHIMERA_"):
            verdict = line.strip()
    return {"built": True, "exit": run.returncode, "output": verdict,
            "coverage": parse_coverage(output),
            "refused": sorted(refused_names(text))}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--work", type=Path,
                        default=ROOT / "results" / "runs" / "chimera-gate")
    parser.add_argument("--report", type=Path)
    parser.add_argument("--profiles", action="store_true",
                        help="все четыре уровня оптимизации, а не один боевой")
    parser.add_argument("--switches", action="store_true",
                        help="плюс каждая оптимизация по отдельности "
                             "(42 сборки, несколько минут)")
    parser.add_argument("--focus", help="один орган или один идентификатор "
                                        "переписи — для быстрой правки")
    parser.add_argument("--allow-open", action="store_true",
                        help="не валить прогон из-за незакрытых строк переписи "
                             "(только для промежуточной работы)")
    args = parser.parse_args()

    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    # Compilation runs with the Chimera source directory as cwd.  Resolve a
    # caller-supplied relative work path before handing -FU/-FE to the
    # compiler, otherwise a perfectly valid path is looked up below CHIMERA.
    args.work = args.work.resolve()
    if args.report:
        args.report = args.report.resolve()

    tc.preflight()
    check_mormot_objects()
    args.work.mkdir(parents=True, exist_ok=True)
    started = time.time()

    rows, problems = load_inventory()
    program_focus = resolve_focus(rows, args.focus)
    findings: list[dict] = [{"kind": "inventory-mismatch", "id": "-",
                             "detail": p} for p in problems]

    # По умолчанию — ОДИН боевой профиль. Химера проверяет себя сама: тела
    # сверяются между собой, оракулы независимы, векторы внешние. Для вердикта
    # хватает одного прогона, и он обязан быть быстрым.
    #
    # Прочие уровни и ключи — второй, ИНОЙ оракул: расхождение ответа между
    # сборками доказывает дефект без всякой внешней истины и ловит тот случай,
    # когда внутренние проверки слепы, — когда все тела сломались одинаково.
    # Это страховка, а не суть, поэтому она за флагом.
    plan = [("release", [])]
    if args.profiles or args.switches:
        plan = [("debug", []), ("o1", []), ("o2", []), ("release", [])]
    if args.switches and not args.focus:
        plan += [("o1", ["-Oo" + s]) for s in SWITCHES]
        plan += [("release", ["-OoNO" + s]) for s in SWITCHES]

    rowsout: list[dict] = []
    expected = None
    coverage: dict[str, dict[str, int]] = {}

    for profile, extra in plan:
        tag = profile + (("/" + extra[0]) if extra else "")
        out = args.work / ("out-" + profile
                           + ("-" + extra[0].replace("-", "") if extra else ""))
        result = build_and_run(out, profile, extra, program_focus,
                               args.timeout)
        rowsout.append({"profile": profile, "extra": extra,
                        **{k: v for k, v in result.items() if k != "coverage"}})

        if not result["built"]:
            findings.append({"kind": "build-failed", "case": tag,
                             "detail": "; ".join(result["errors"][:2])})
            print(f"СБОРКА УПАЛА   {tag}")
            for line in result["errors"][:2]:
                print("    ", line[:150])
            continue

        coverage.update(result["coverage"])
        output = result["output"]
        if not output.startswith("CHIMERA_OK"):
            findings.append({"kind": "claim-failed", "case": tag,
                             "detail": output})
            print(f"УТВЕРЖДЕНИЕ    {tag}  {output[:120]}")
            continue
        if result["exit"] != 0:
            findings.append({"kind": "run-failed", "case": tag,
                             "detail": f"exit code {result['exit']} after "
                                       "CHIMERA_OK"})
            print(f"ЗАПУСК УПАЛ    {tag}  exit={result['exit']}")
            continue

        if expected is None:
            expected = output
            print(f"эталон [{tag}]: {output}")
        elif output != expected:
            findings.append({"kind": "answer-differs", "case": tag,
                             "detail": f"{output} вместо {expected}"})
            print(f"ОТВЕТ РАЗОШЁЛСЯ {tag}  {output[:120]}")

        # Ключ AUTOINLINE выключает вставку целиком — тогда отказ от всего и
        # есть ожидаемое поведение, а не потеря оси.
        if extra and "AUTOINLINE" in extra[0]:
            continue
        refused = set(result["refused"])
        if refused != EXPECT_REFUSED:
            findings.append({
                "kind": "inline-map-changed", "case": tag,
                "detail": "вставилось лишнее: "
                          + ", ".join(sorted(EXPECT_REFUSED - refused))
                          + "; отказано лишнее: "
                          + ", ".join(sorted(refused - EXPECT_REFUSED))})
            print(f"КАРТА ВСТАВОК  {tag}")

    findings += check_inventory(rows, coverage, args.focus, args.allow_open)

    covered = sum(1 for r in rows if r.get("status") == "covered")
    opened = sum(1 for r in rows if r.get("status") == "open")
    report = {"expected": expected, "rows": rowsout, "findings": findings,
              "inventory": {"total": len(rows), "covered": covered,
                            "open": opened},
              "coverage": coverage,
              "seconds": round(time.time() - started, 1)}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False),
                               encoding="utf-8")

    print()
    print(f"перепись: {len(rows)} строк, закрыто {covered}, открыто {opened}")
    print(f"сборок: {len(rowsout)}  за {report['seconds']}с")

    if findings:
        shown = 0
        for f in findings:
            if shown >= 12:
                print(f"  ... ещё {len(findings) - shown}")
                break
            print(f"  [{f['kind']}] {f.get('id', f.get('case', ''))}"
                  f"  {f['detail'][:110]}")
            shown += 1
        print(f"CHIMERA_GATE FINDINGS findings={len(findings)}")
        return 1

    print(f"CHIMERA_GATE OK builds={len(rowsout)} covered={covered}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
