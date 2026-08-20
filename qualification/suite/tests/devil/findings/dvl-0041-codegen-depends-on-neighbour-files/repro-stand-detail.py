"""Что именно в каталоге влияет: число файлов, их имена или длина имён."""

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


def build() -> str:
    out = WORK / "out-x"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    r = subprocess.run(tc.compile_command(WORK / "devil.dpr", out, "release"),
                       capture_output=True, text=True, cwd=WORK, timeout=300)
    if r.returncode:
        return "ОТКАЗ"
    digest = hashlib.sha256((out / "devil.o").read_bytes()).hexdigest()[:16]
    shutil.rmtree(out)
    return digest


def clean_extras() -> None:
    for path in WORK.glob("zz*"):
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()


def main() -> None:
    clean_extras()
    base = build()
    say("база (без посторонних):", base)

    for count in (1, 2, 3, 4):
        clean_extras()
        for i in range(count):
            (WORK / ("zz%02d.txt" % i)).write_text("x", encoding="utf-8")
        say("посторонних файлов %d:" % count, build(),
            "" if count else "")

    clean_extras()
    (WORK / "zz-short.txt").write_text("x", encoding="utf-8")
    a = build()
    clean_extras()
    (WORK / "zz-a-much-longer-file-name-here.txt").write_text("x", encoding="utf-8")
    b = build()
    say("один файл, короткое имя:", a)
    say("один файл, длинное имя :", b, "— имя влияет" if a != b else "— имя не влияет")

    clean_extras()
    (WORK / "zz-short.txt").write_text("x" * 100000, encoding="utf-8")
    say("тот же файл, но большой:", build())

    clean_extras()
    say("снова чисто            :", build())


main()
