"""Зависит ли машинный код от постороннего содержимого каталога поиска.

Гипотеза, к которой привели все наблюдения: результат сборки меняется не
случайно, а от того, что лежит рядом с исходником — потому что каталог указан
компилятору через -Fu, и он его сканирует.  Если так, то «недетерминизм»,
который ловило зеркало, на самом деле детерминированная зависимость от мусора
по соседству: между первой и второй сборкой гейт создаёт новые подкаталоги.

Стенд ставит один и тот же исходник в одинаковые условия и меняет ровно одну
вещь за раз.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

SUITE = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(SUITE / "scripts"))
import devil_toolchain as tc  # noqa: E402

WORK = (SUITE / "results" / "runs" / "devil-dvl-0041").resolve()


def say(*parts: object) -> None:
    print("[%s]" % time.strftime("%H:%M:%S"), *parts, flush=True)


def build(tag: str) -> str:
    out = WORK / ("out-" + tag)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    r = subprocess.run(tc.compile_command(WORK / "devil.dpr", out, "release"),
                       capture_output=True, text=True, cwd=WORK, timeout=300)
    if r.returncode:
        bad = [l.strip() for l in r.stdout.splitlines() if "Error" in l][:1]
        return "ОТКАЗ: " + (bad[0][:60] if bad else "?")
    digest = hashlib.sha256((out / "devil.o").read_bytes()).hexdigest()[:16]
    shutil.rmtree(out)          # каталог вывода не должен оставаться уликой
    return digest


def main() -> None:
    if WORK.exists():
        shutil.rmtree(WORK)
    WORK.mkdir(parents=True)
    gen = subprocess.run([sys.executable,
                          str(SUITE / "scripts" / "generate_devil.py"),
                          "--seed", "23", "--cases", "120",
                          "--layers", "set", "--out", str(WORK)],
                         capture_output=True, text=True)
    if gen.returncode:
        say("генератор отказал")
        return

    say("чистый каталог      :", build("a"))
    say("он же, повторно     :", build("b"))

    (WORK / "zz-empty-dir").mkdir()
    say("+ пустой подкаталог :", build("c"))

    (WORK / "zz-note.txt").write_text("posторонний файл\n", encoding="utf-8")
    say("+ посторонний .txt  :", build("d"))

    (WORK / "zz_unused.pas").write_text(
        "unit zz_unused;\ninterface\nimplementation\nend.\n", encoding="utf-8")
    say("+ неиспользуемый pas:", build("e"))

    (WORK / "zz_unused.pas").unlink()
    (WORK / "zz-note.txt").unlink()
    shutil.rmtree(WORK / "zz-empty-dir")
    say("всё убрано обратно  :", build("f"))


main()
