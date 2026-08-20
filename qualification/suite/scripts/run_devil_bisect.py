#!/usr/bin/env python3
"""Обратная минимизация: резать не кейс, а окружение вокруг него.

`devil_minimize.py` режет расхождение до отдельной маленькой программы. Для
большинства дефектов это правильно, но целый класс он этим уничтожает:
расхождение, которое живёт **только в полной программе** и исчезает, как
только окружение убрали. Такие дефекты в проде самые злые — они включаются,
когда пользовательский код догрузит программу до нужного состояния (размер
таблицы символов, порядок объявлений, соседство юнитов), и никакой
изолированный repro их не покажет.

Здесь наоборот: кейс закреплён, режется окружение. На выходе — минимальный
набор слоёв и минимальный размер среза, при которых расхождение ещё живо.
Последний элемент, чьё удаление расхождение убивает, и называет механизм.

    run_devil_bisect.py --seed 31 --target dvl-attr-published-property-readback
                        --dcc ... --dcc-lib ...
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import devil_toolchain as tc
from run_devil_gate import (DEVIL, GENERATOR, Build, build_delphi, build_fpc,
                            run)


# файлы, которые в рабочем каталоге пишет генератор; всё остальное там - чужое
GENERATED = ("devil.dpr", "devil_runtime.pas", "devil_support.inc")


def refuse_foreign(work: Path) -> None:
    """Каталог для резки принадлежит только резке.

    Этот скрипт стирает рабочий каталог между пробами. Направить его в
    каталог, где лежит что-то ещё - реестр разобранного, витрина находок,
    доки - значит стереть их. Один раз уже стёр.
    """
    if not work.exists():
        return
    foreign = [p.name for p in work.iterdir()
               if not (p.name in GENERATED
                       or p.name.startswith(("devil_", "out-")))]
    if foreign:
        raise SystemExit(
            "work directory holds files this script does not own: %s\n"
            "give --work an empty directory of its own"
            % ", ".join(sorted(foreign)[:8]))


def generate(work: Path, seed: int, cases: int, layers: list[str]) -> None:
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    code, log = run([sys.executable, str(GENERATOR), "--seed", str(seed),
                     "--cases", str(cases), "--layers", ",".join(layers),
                     "--out", str(work)], work, 600)
    if code != 0:
        raise SystemExit("generator refused:\n" + log[-2000:])


def observed(build: Build, target: str) -> str | None:
    """Что сборка сказала про целевое наблюдение или проверку.

    Прошедшая проверка не печатает ничего, поэтому её молчание — это тоже
    ответ: «сошлось». Возвращать None здесь нельзя, иначе пара «у одного
    упало, у другого прошло» выглядит как отсутствие цели.
    """
    if target in build.notes:
        return build.notes[target]
    if target in build.failures:
        return "FAIL:" + build.failures[target][0]
    layer = target.split("-")[1] if target.startswith("dvl-") else ""
    if build.layers and layer in build.layers:
        return "ok"
    return None


def alive(work: Path, seed: int, cases: int, layers: list[str],
          target: str, profile: str, dcc: Path, lib: Path,
          timeout: int) -> bool:
    """Живо ли расхождение при таком окружении."""
    try:
        generate(work, seed, cases, layers)
    except SystemExit:
        return False
    ours = build_fpc(work, profile, [], timeout)
    theirs = build_delphi(work, dcc, lib, timeout)
    if not ours.compiled:
        print("    ours did not compile", flush=True)
        return False
    if not theirs.compiled:
        print("    delphi did not compile", flush=True)
        return False
    a, b = observed(ours, target), observed(theirs, target)
    if a is None or b is None:
        print("    target missing: ours=%s delphi=%s" % (a, b), flush=True)
        return False
    return a != b


def ddmin(items: list[str], keep: list[str], probe, keep_order) -> list[str]:
    """Дельта-отладка: минимальное подмножество, на котором проба ещё истинна."""
    current = list(items)
    granularity = 2
    while len(current) >= 2:
        chunk = max(1, len(current) // granularity)
        pieces = [current[i:i + chunk] for i in range(0, len(current), chunk)]
        reduced = False
        for piece in pieces:
            rest = [x for x in current if x not in piece]
            if not rest:
                continue
            if probe(keep_order(set(rest + keep))):
                current = rest
                granularity = max(granularity - 1, 2)
                reduced = True
                break
        if reduced:
            continue
        if granularity >= len(current):
            break
        granularity = min(len(current), granularity * 2)
    return keep_order(set(current + keep))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--seed", type=int, required=True)
    p.add_argument("--cases", type=int, default=40)
    p.add_argument("--target", required=True,
                   help="name of the split observation or check")
    p.add_argument("--layers", default="all")
    p.add_argument("--profile", default="release")
    p.add_argument("--dcc", type=Path, required=True)
    p.add_argument("--dcc-lib", type=Path, required=True)
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--work", type=Path,
                   default=Path(__file__).resolve().parents[1] /
                   "results" / "runs" / "devil-bisect")
    args = p.parse_args()

    # сборка идёт с рабочим каталогом внутри work, поэтому все пути к нему
    # должны быть абсолютными до того, как туда зайдут
    args.work = args.work.resolve()
    args.dcc = args.dcc.resolve()
    args.dcc_lib = args.dcc_lib.resolve()
    # до всякой работы: пробы ловят SystemExit из генерации и считают её
    # неудачей, поэтому отказ должен случиться здесь, снаружи проб
    refuse_foreign(args.work)
    tc.preflight()
    from generate_devil import LAYERS
    # the declaration order is itself an axis: "all" means this order, and a
    # sorted copy is already a different program
    layers = (list(LAYERS) if args.layers == "all"
              else args.layers.split(","))
    order = {name: i for i, name in enumerate(layers)}
    # слой, которому принадлежит кейс, из окружения не выкидывается
    owner = args.target.split("-")[1] if args.target.startswith("dvl-") else ""
    keep = [owner] if owner in layers else []
    if not keep:
        raise SystemExit("cannot tell which layer owns %s" % args.target)

    def probe(subset: list[str]) -> bool:
        live = alive(args.work, args.seed, args.cases, subset, args.target,
                     args.profile, args.dcc, args.dcc_lib, args.timeout)
        print("  %-4s %s" % ("live" if live else "gone",
                             ",".join(subset)), flush=True)
        return live

    print("checking the split is alive on the full set")
    if not probe(layers):
        raise SystemExit("no split on the full set: nothing to cut")

    print("cutting the environment")
    def keep_order(names) -> list[str]:
        return sorted(names, key=lambda n: order[n])

    minimal = ddmin([l for l in layers if l not in keep], keep, probe,
                    keep_order)

    print("cutting the slice size")
    cases = args.cases
    while cases > 1:
        half = max(1, cases // 2)
        live = alive(args.work, args.seed, half, minimal, args.target,
                     args.profile, args.dcc, args.dcc_lib, args.timeout)
        print("  %-4s cases=%d" % ("live" if live else "gone", half),
              flush=True)
        if not live:
            break
        cases = half

    # что именно убивает расхождение: последний удаляемый элемент
    culprits = []
    for layer in minimal:
        if layer in keep:
            continue
        rest = [l for l in minimal if l != layer]
        if not alive(args.work, args.seed, cases, rest, args.target,
                     args.profile, args.dcc, args.dcc_lib, args.timeout):
            culprits.append(layer)

    result = {"target": args.target, "seed": args.seed, "cases": cases,
              "environment": minimal, "kills_when_removed": culprits}
    print("DEVIL_BISECT " + json.dumps(result, ensure_ascii=False,
                                       sort_keys=True))


if __name__ == "__main__":
    main()
