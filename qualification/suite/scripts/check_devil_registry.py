#!/usr/bin/env python3
"""Сторож реестра: находка обязана быть записана всюду, а не только найдена.

Дважды подряд получалось одинаково: находка разобрана, папка в `findings/`
заведена, стенд написан — а в журнал и в таблицу состояния она не попала,
потому что я про это забыл. Забывчивость лечится не памятью, а проверкой.

Сторож сверяет три места, которые обязаны говорить одно и то же:

  * `findings/dvl-NNNN-*/` — папка с разбором;
  * `ЖУРНАЛ-НАХОДОК.md` — сводный список, поделённый по смыслу;
  * `STATUS.md` — таблица «Найдено».

Он же ловит обратное: строку в журнале без разбора в `findings/` (значит
находка объявлена, но не разобрана) и папку без `FINDING.md`.

Запускать вместе с гейтами: он ничего не собирает и стоит доли секунды.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DEVIL = Path(__file__).resolve().parents[1] / "tests" / "devil"
ID_RE = re.compile(r"dvl-(\d{4})")


def ids_in(text: str) -> set[str]:
    return set(ID_RE.findall(text))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--devil", type=Path, default=DEVIL)
    args = p.parse_args()
    devil = args.devil.resolve()

    findings = devil / "findings"
    journal = devil / "ЖУРНАЛ-НАХОДОК.md"
    status = devil / "STATUS.md"

    folders: dict[str, Path] = {}
    for path in sorted(findings.iterdir()) if findings.is_dir() else []:
        if not path.is_dir():
            continue
        m = ID_RE.match(path.name)
        if m:
            folders[m.group(1)] = path

    problems: list[str] = []

    for number, path in folders.items():
        if not (path / "FINDING.md").is_file():
            problems.append("dvl-%s: папка без разбора (%s)" % (number, path.name))

    # находки, у которых папки нет и не будет: разбор утрачен или не нужен
    excused = devil / "findings" / "БЕЗ-РАЗБОРА.md"
    without_folder = (ids_in(excused.read_text(encoding="utf-8"))
                      if excused.is_file() else set())

    in_journal = ids_in(journal.read_text(encoding="utf-8")) if journal.is_file() else set()
    in_status = ids_in(status.read_text(encoding="utf-8")) if status.is_file() else set()

    for number in sorted(folders):
        if number not in in_journal:
            problems.append("dvl-%s: разобрана, но не вписана в журнал" % number)
        if number not in in_status:
            problems.append("dvl-%s: разобрана, но не вписана в таблицу STATUS"
                            % number)

    # id, о котором говорят доки, но разбора нет: либо забыли завести папку,
    # либо это ссылка на чужой реестр — тогда её надо убрать из списка находок
    for number in sorted(in_journal - set(folders) - without_folder):
        problems.append("dvl-%s: упомянута в журнале, разбора в findings нет"
                        % number)

    if problems:
        for line in problems:
            print("  NEW " + line)
        print("DEVIL_REGISTRY FINDINGS folders=%d problems=%d"
              % (len(folders), len(problems)))
        sys.exit(1)
    print("DEVIL_REGISTRY OK folders=%d excused=%d"
          % (len(folders), len(without_folder)))


if __name__ == "__main__":
    main()
