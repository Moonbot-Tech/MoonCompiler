"""Отказ линковки живой прямо сейчас — режем окружение, пока он не исчезнет.

`Undefined symbol: $unwind$P$DEVIL_$$_DVLSET000NN` означает, что компилятор
сослался на запись раскрутки для подпрограммы и не выпустил её.  Программа не
собирается вовсе, то есть это жёстче dvl-0041, где терялся один байт.

Стенд: сначала убеждаемся, что отказ устойчив, потом дельта-отладкой по составу
слоёв ищем минимальный набор, при котором он ещё живёт.  Все петли ограничены.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from pathlib import Path

SUITE = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(SUITE / "scripts"))
import devil_toolchain as tc  # noqa: E402
from generate_devil import LAYERS  # noqa: E402

WORK = (SUITE / "results" / "runs" / "devil-dvl-0042").resolve()
SEED, CASES = 24, 120


def say(*parts: object) -> None:
    print("[%s]" % time.strftime("%H:%M:%S"), *parts, flush=True)


def prepare(layers: list[str]) -> bool:
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    gen = subprocess.run([sys.executable,
                          str(SUITE / "scripts" / "generate_devil.py"),
                          "--seed", str(SEED), "--cases", str(CASES),
                          "--layers", ",".join(layers), "--out", str(WORK)],
                         capture_output=True, text=True)
    return gen.returncode == 0


def fails(layers: list[str]) -> tuple[bool, str]:
    """True, если сборка падает; вторым — текст первой ошибки."""
    if not prepare(layers):
        return False, "генератор отказал"
    out = WORK / "out"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir()
    try:
        r = subprocess.run(tc.compile_command(WORK / "devil.dpr", out, "release"),
                           capture_output=True, text=True, cwd=WORK, timeout=600)
    except subprocess.TimeoutExpired:
        return False, "таймаут"
    if r.returncode == 0:
        return False, "собралось"
    bad = [l.strip() for l in r.stdout.splitlines() if "Error" in l][:1]
    return True, (bad[0][:70] if bad else "?")


def main() -> None:
    order = list(LAYERS)
    say("проверяю устойчивость отказа на полном наборе")
    for attempt in range(3):
        bad, note = fails(order)
        say("  попытка %d: %s" % (attempt, note))
        if not bad:
            say("отказ неустойчив — резать нечего")
            return

    current = [l for l in order if l != "set"]
    keep = ["set"]
    granularity = 2
    rounds = 0
    while len(current) >= 2 and rounds < 40:
        rounds += 1
        chunk = max(1, len(current) // granularity)
        pieces = [current[i:i + chunk] for i in range(0, len(current), chunk)]
        reduced = False
        for piece in pieces:
            rest = [x for x in current if x not in piece]
            if not rest:
                continue
            trial = sorted(set(rest + keep), key=order.index)
            bad, note = fails(trial)
            say("  %-5s %d слоёв: %s" % ("живо" if bad else "нет",
                                         len(trial), note))
            if bad:
                current = rest
                granularity = max(granularity - 1, 2)
                reduced = True
                break
        if reduced:
            continue
        if granularity >= len(current):
            break
        granularity = min(len(current), granularity * 2)

    minimal = sorted(set(current + keep), key=order.index)
    say("минимальный набор:", ",".join(minimal))
    for layer in list(minimal):
        if layer in keep:
            continue
        rest = [l for l in minimal if l != layer]
        bad, _ = fails(rest)
        if not bad:
            say("  удаление %s убивает отказ" % layer)


main()
