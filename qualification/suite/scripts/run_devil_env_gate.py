#!/usr/bin/env python3
"""Гейт окружения: машинный код не должен зависеть ни от чего, кроме исходника.

dvl-0041 показала, что результат сборки меняется от посторонних файлов рядом с
исходником — имена и количество соседей доезжают до байтов в образе. Найдено это
было случайно: зеркало детерминизма сравнило две сборки, между которыми гейт
успел создать каталог.

Разовый ремонт того случая не сделает компилятор детерминированным: он уберёт
один путь, которым посторонний контекст доезжает до кода. Поэтому здесь стоит
не проверка того случая, а **ловушка на весь класс**: один и тот же исходник
собирается много раз, и между сборками намеренно трясётся всё, что к исходнику
не относится. Артефакты обязаны совпадать байт в байт.

Возмущения подобраны так, чтобы ни одно из них не меняло смысл программы:

  * ничего (контроль — две сборки подряд);
  * посторонний файл рядом, короткое имя;
  * посторонний файл рядом, длинное имя;
  * два, три, четыре посторонних файла;
  * посторонний подкаталог;
  * файл с тем же именем, но другим расширением;
  * файл размером в сто килобайт;
  * порядок создания файлов обратный.

Расхождение на любом из них - находка того же класса, что dvl-0041, и гейт
сохраняет обе сборки целиком, чтобы разбирать было что.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import devil_toolchain as tc
from run_devil_gate import DEVIL, GENERATOR, run

ROOT = Path(__file__).resolve().parents[1]


def say(*parts: object) -> None:
    print("[%s]" % time.strftime("%H:%M:%S"), *parts, flush=True)


def artefacts(out: Path) -> dict[str, str]:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(out.iterdir())
            if p.suffix.lower() in (".o", ".ppu", ".exe")}


def clean_noise(work: Path) -> None:
    for path in work.glob("zz*"):
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()


# каждое возмущение обязано быть безразличным для программы
DISTURBANCES = (
    ("untouched", ()),
    ("one-file", ("zz1.txt",)),
    ("long-name", ("zz-a-considerably-longer-neighbour-name.txt",)),
    ("two-files", ("zz1.txt", "zz2.txt")),
    ("three-files", ("zz1.txt", "zz2.txt", "zz3.txt")),
    ("four-files", ("zz1.txt", "zz2.txt", "zz3.txt", "zz4.txt")),
    ("other-suffix", ("zz1.dat",)),
    ("reverse-order", ("zz4.txt", "zz3.txt", "zz2.txt", "zz1.txt")),
    ("subdir", ("zz-dir/",)),
    ("big-file", ("zz-big.txt",)),
)


def disturb(work: Path, names: tuple[str, ...]) -> None:
    clean_noise(work)
    for name in names:
        if name.endswith("/"):
            (work / name.rstrip("/")).mkdir()
        elif "big" in name:
            (work / name).write_text("x" * 100_000, encoding="utf-8")
        else:
            (work / name).write_text("x", encoding="utf-8")


def build(work: Path, profile: str, timeout: int, *,
          out_name: str = "out-env", cwd: Path | None = None,
          env_extra: dict[str, str] | None = None,
          tail: list[str] = ()) -> tuple[dict[str, str], str]:
    out = work / out_name
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cmd = tc.compile_command(work / "devil.dpr", out, profile)
    if tail:
        cmd = cmd[:-1] + list(tail) + [cmd[-1]]
    env = None
    if env_extra:
        env = dict(os.environ)
        env.update(env_extra)
    try:
        proc = subprocess.run(cmd, cwd=str(cwd or work), capture_output=True,
                              text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return {}, "REJECTED: timeout"
    if proc.returncode != 0:
        log = (proc.stdout or "") + (proc.stderr or "")
        bad = [l.strip() for l in log.splitlines()
               if "Error" in l or "Fatal" in l][:1]
        return {}, "REJECTED: " + (bad[0][:70] if bad else "?")
    return artefacts(out), ""


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--seed", type=int, default=23)
    p.add_argument("--cases", type=int, default=60)
    p.add_argument("--layers", default="set,meta,weave,composite")
    p.add_argument("--profile", default="release")
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--work", type=Path, default=ROOT / "work-env")
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
    reference: dict[str, str] = {}
    evidence = work / "evidence"

    for label, names in DISTURBANCES:
        disturb(work, names)
        got, failure = build(work, args.profile, args.timeout)
        if failure:
            say("%-18s %s" % (label, failure))
            findings.append({"kind": "build-failed-under-disturbance",
                             "disturbance": label, "detail": failure})
            continue
        if not reference:
            reference = got
            shutil.copytree(work / "out-env", evidence / "reference",
                            dirs_exist_ok=True)
            say("%-18s reference taken (%d artefacts)" % (label, len(got)))
            continue
        moved = sorted(name for name in set(reference) & set(got)
                       if reference[name] != got[name])
        if moved:
            room = evidence / ("differs-" + label.replace(" ", "-"))
            shutil.copytree(work / "out-env", room, dirs_exist_ok=True)
            say("%-18s DIFFERS: %s" % (label, ", ".join(moved)))
            findings.append({"kind": "codegen-depends-on-environment",
                             "disturbance": label, "artefacts": moved})
        else:
            say("%-18s same" % label)

    clean_noise(work)

    # то же самое, но трогаем не каталог, а всё остальное постороннее
    others = (
        ("other-out-dir", dict(out_name="out-env-elsewhere")),
        ("deep-out-dir", dict(out_name="out-env-" + "d" * 60)),
        ("cwd-elsewhere", dict(cwd=work.parent)),
        ("env-var-added", dict(env_extra={"DEVIL_ENV_PROBE": "1"})),
        ("env-var-long", dict(env_extra={"DEVIL_ENV_PROBE": "x" * 4000})),
        ("extra-search-path", dict(tail=["-Fu" + str(work)])),
    )
    for label, kwargs in others:
        got, failure = build(work, args.profile, args.timeout, **kwargs)
        if failure:
            say("%-18s %s" % (label, failure))
            findings.append({"kind": "build-failed-under-disturbance",
                             "disturbance": label, "detail": failure})
            continue
        moved = sorted(name for name in set(reference) & set(got)
                       if reference[name] != got[name])
        if moved:
            say("%-18s DIFFERS: %s" % (label, ", ".join(moved)))
            findings.append({"kind": "codegen-depends-on-environment",
                             "disturbance": label, "artefacts": moved})
        else:
            say("%-18s same" % label)

    if args.report:
        args.report.write_text(json.dumps(findings, ensure_ascii=False,
                                          indent=2), encoding="utf-8")
    if findings:
        for f in findings:
            print("  NEW " + json.dumps(f, ensure_ascii=False, sort_keys=True))
        print("DEVIL_ENV FINDINGS disturbances=%d findings=%d"
              % (len(DISTURBANCES) + 6, len(findings)))
        raise SystemExit(1)
    print("DEVIL_ENV OK disturbances=%d" % (len(DISTURBANCES) + 6))


if __name__ == "__main__":
    main()
