"""Interpret measured costs by useful work; never vote by benchmark count."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path
import re


PURPOSES = {
    "heartbeat": "Прикладные цепочки: JSON, рынки, стакан, запросы, таймеры, расчёты",
    "mormot-json": "Разбор и сборка JSON настоящим API mORMot",
    "zlib": "Сжатие и распаковка в формах продукта: пакеты сделок, свечи, история, websocket; zlib наш и mORMot",
    "kernels": "Законченные вычислительные алгоритмы на синтетических данных",
    "workloads": "Вычислительные нагрузки: FFT, численные циклы, обходы, память",
    "algorithms": "Сортировка, поиск, хеширование, сжатие и криптографические ядра",
    "dictionary": "Создание, поиск и обновление словарей разных типов и размеров",
    "rtl-collections": "Операции контейнеров, включая managed-значения",
    "rtl": "Строки, преобразования, потоки памяти и контейнеры",
    "hot-rtl": "Изолированная цена обычных вызовов RTL",
    "product-forms": "Горячие функции торгового сервера MoonBot с его раскладкой данных: сделки, свечи, поиск рынка",
    "repairs": "Обычные пути затронутых ремонтом операций, включая RoundTo",
    "move": "Копирование между буферами, перекрытие и потоковое копирование",
    "mm": "Аллокации, realloc и фрагментация: CPU и удержанная память",
    "threads": "Потоки и общие ресурсы: время работы и суммарный расход CPU",
    "managed": "Владение строками, массивами, интерфейсами и замыканиями",
    "dispatch": "Вызовы методов, интерфейсы, объекты и исключения",
    "json": "Сборка текста, byte scan и учебный JSON parser; это не mORMot",
    "abi": "Изолированная цена передачи аргументов и результатов",
    "codegen": "Изолированные инструкции, вызовы, ветвления и доступ к памяти",
    "numeric": "Изолированные арифметические операции и преобразования типов",
    "loops": "Отдельные формы циклов, зависимостей и обращений к памяти",
    "layout": "Отдельные формы размещения и обхода данных",
    "local-pressure": "Цена входа, работы и выхода при множестве локальных переменных",
    "calibration": "Контроль измерителя на фиксированном ASM",
}
ROLE_NAMES = {
    "workload": "Прикладные и алгоритмические нагрузки",
    "operation": "Обычные операции программ",
    "mechanism": "Изолированные формы кодогена",
    "boundary": "Граничные входы",
    "control": "Контрольные и диагностические тесты",
    "unreviewed": "Назначение ещё не определено",
}
METRICS = {
    "work_cycles_per_op": "CPU/операцию",
    "ticks_per_op": "время/операцию",
    "memory_peak_resident": "пиковая память",
    "memory_after_private": "память после работы",
    "memory_cooldown_private": "память после ожидания",
}
CASE_PURPOSES = {
    "repairs/variant-dictionary": "Поиск существующих целочисленных Variant-ключей в TDictionary",
    "hot-rtl/startstext-hit-12": "Проверка 12-символьного префикса без учёта регистра",
    "hot-rtl/ansisametext-equal-12": "Сравнение равных 12-символьных строк без учёта регистра",
    "hot-rtl/containstext-hit-32": "Поиск подстроки без учёта регистра в коротком тексте",
    "hot-rtl/stringlist-indexofname-hit": "Поиск имени в TStringList с парами имя=значение",
    "hot-rtl/stringlist-indexof-hit": "Поиск существующей строки в TStringList",
    "rtl/inttostr-int64": "IntToStr для знаковых чисел порядка 10^12: форматирование идентификаторов и счётчиков",
    "rtl/dictionary-capacity-1024": "Создать словарь и зарезервировать 1024 места; разовая подготовка, не lookup",
    "heartbeat/binary-session-pipeline": "16384 бинарных запроса: decode, хеш payload, поиск сессии, состояние и ответ",
    "workloads/linked-list-insert-sort-512": "Создать и отсортировать вставками связный список из 512 узлов, затем освободить",
    "rtl-collections/list-integer-delete-insert-range-4096": "Удалить и вставить обратно среднюю половину TList<Integer> из 4096 элементов",
}


def context(name: str, row: dict) -> tuple[str, str]:
    program, _, case = name.partition("/")
    layers = set(row.get("layer", "").split("+"))
    if layers & {"asm-reference", "calibration", "accepted-noop"} or program == "calibration":
        return "control", "Эталон/контроль; время не определяет качество сгенерированного кода"
    if (program == "move" and (case.startswith("same-") or case.endswith("-n0"))) or (
        program == "local-pressure" and case == "empty"
    ):
        return "control", "Нет полезной работы; измеряется накладная цена"
    if name == "codegen/minmax-double-special":
        return "boundary", "Min/Max на матрице NaN, бесконечностей, ±0 и обычных чисел"
    if program == "repairs" and (layers == {"codegen"} or "abi" in layers):
        return "mechanism", "Изолированная форма кодогенерации/ABI; перенос эффекта в нагрузку ещё не показан"
    if program == "json" and case.startswith("byte-scan-"):
        return "mechanism", "Проход по структурным символам JSON; диагностический цикл без разбора структуры"
    if name == "repairs/padded-counters-4" or program == "threads" and case.startswith(("false-sharing-", "padded-counters-")):
        return "mechanism", "Изолированная конкуренция за cache line; проверка размещения счётчиков"
    if program not in PURPOSES:
        return "unreviewed", "Назначение нового семейства ещё не описано"
    if program in {"heartbeat", "product-forms", "mormot-json", "zlib", "kernels",
                   "workloads", "algorithms"}:
        role = "workload"
    elif program in {"abi", "codegen", "numeric", "loops", "layout", "local-pressure"}:
        role = "mechanism"
    else:
        role = "operation"
    return role, CASE_PURPOSES.get(name, PURPOSES[program])


def family(name: str) -> str:
    """Keep size sweeps from occupying every position in the release top N."""
    program, _, case = name.partition("/")
    if program in {"hot-rtl", "rtl"} and case.startswith((
        "stringlist-indexofname", "stringlist-values", "stringlist-namevalue",
    )):
        return "TStringList/name-value-lookup"
    if program in {"hot-rtl", "rtl"} and case.startswith("stringlist-indexof"):
        return "TStringList/indexof"
    if program == "move":
        case = case.split("-a", 1)[0] if "-a" in case else case.split("-d", 1)[0]
    elif program == "repairs" and case.startswith("roundto-"):
        case = "roundto"
    else:
        case = re.sub(r"-(?:\d+|small|medium|large)$", "", case)
    return program + "/" + case


def directions(values) -> str:
    values = set(values)
    better = bool(values & {"BETTER", "TRADEOFF"})
    worse = bool(values & {"WORSE", "TRADEOFF"})
    if better and worse:
        return "TRADEOFF"
    if worse:
        return "WORSE"
    if better:
        return "BETTER"
    if values == {"SAME"}:
        return "SAME"
    return "UNRESOLVED"


def metric_decisions(row: dict) -> list[str]:
    final = row.get("final", {})
    if final.get("semantic_match") is False:
        return ["SEMANTIC_MISMATCH"]
    if final.get("semantic_match") is not True or final.get("valid_pairs", 0) < 3:
        return ["UNAVAILABLE"]
    return [confirmed_decision(row, name)
            for name in final.get("primary_metrics", [])] or ["UNAVAILABLE"]


def confirmed_decision(row: dict, metric: str) -> str:
    decision = row.get("final", {}).get("metrics", {}).get(metric, {}).get("decision", "UNAVAILABLE")
    if "confirmation" not in row:
        return decision
    repeat = row["confirmation"] or {}
    final = repeat.get("final", {})
    if final.get("semantic_match") is False:
        return "SEMANTIC_MISMATCH"
    if repeat.get("stand_preflight_failed") or final.get("semantic_match") is not True or final.get("valid_pairs", 0) < 6:
        return "UNAVAILABLE"
    repeated = final.get("metrics", {}).get(metric, {}).get("decision", "UNAVAILABLE")
    return decision if decision == repeated else "UNSTABLE"


def measurement_completed(result: dict | None) -> bool:
    if not result or not (result.get("preflight") or {}).get("passed") or not result.get("cases"):
        return False
    rows = list(result["cases"].values())
    rows.extend(row["confirmation"] for row in result["cases"].values() if row.get("confirmation"))
    return all(not row.get("stand_preflight_failed") and row.get("final", {}).get("semantic_match") is True
               and row["final"].get("valid_pairs", 0) >= 6 for row in rows)


def assess(machines: dict[str, dict | None]) -> dict:
    effects = []
    gaps = []
    semantic = []
    expected = {name: row for result in machines.values() if result for name, row in result.get("cases", {}).items()}
    for machine, result in machines.items():
        if not result or not result.get("cases"):
            gaps.append(f"{machine}: нет завершённого замера")
            continue
        stand_failed = result.get("stand_preflight_failed", False)
        if stand_failed:
            gaps.append(f"{machine}: контроль A/A не прошёл")
        for name, row in expected.items():
            if name not in result["cases"] and context(name, row)[0] != "control":
                gaps.append(f"{machine}: {name}: замер отсутствует")
        for name, row in result["cases"].items():
            if row.get("verdict") == "SEMANTIC_MISMATCH" or row.get("final", {}).get("semantic_match") is False:
                semantic.append(f"{machine}: {name}")
            if (row.get("confirmation") or {}).get("final", {}).get("semantic_match") is False:
                semantic.append(f"{machine}: {name}: независимый повтор")
            role, _ = context(name, row)
            if role == "control":
                continue
            if role == "unreviewed":
                gaps.append(f"{machine}: {name}: не определён смысл теста")
                continue
            decisions = metric_decisions(row)
            if not stand_failed:
                effects.extend(decisions)
            if any(value not in {"BETTER", "WORSE", "SAME", "TRADEOFF"} for value in decisions):
                gaps.append(f"{machine}: {name}")
    outcome = "SEMANTIC_MISMATCH" if semantic else directions(effects)
    return {
        "outcome": outcome,
        "complete": bool(effects) and not gaps and not semantic,
        "measurement_gaps": gaps,
        "semantic_mismatches": semantic,
    }


def percent(value: float) -> str:
    return f"{(value - 1) * 100:+.1f}%"


def evidence(row: dict) -> str:
    final = row.get("final", {})
    if row.get("verdict") == "SEMANTIC_MISMATCH" or final.get("semantic_match") is False:
        return "Результаты вычислений различаются; сравнение скорости недействительно"
    if not final:
        return "Нет численных данных"
    parts = []
    for name in final.get("primary_metrics", []):
        metric = final.get("metrics", {}).get(name, {})
        center, low, high = metric.get("median"), metric.get("minimum"), metric.get("maximum")
        if center is None or low is None or high is None:
            parts.append(f"{METRICS[name]}: нет замера")
            continue
        absolute = final.get("centers", {}).get(name, {})
        cost = ""
        if absolute:
            cost = f"; медианы R={absolute['moon-baseline']:.3g}, C={absolute['moon-candidate']:.3g}"
        interval = metric.get("median_interval_95")
        bounds = f"; 95% интервал медианы {percent(interval[0])}…{percent(interval[1])}" if interval else ""
        text = f"{METRICS[name]}: {percent(center)}{bounds}; все пары [{percent(low)}…{percent(high)}]{cost}"
        if metric.get("separated"):
            text += "; распределения не пересекаются: каждый процесс одной стороны дешевле каждого процесса другой"
        if metric["decision"] in {"UNSTABLE", "UNAVAILABLE"}:
            text += "; данных для уверенного вывода не хватило"
        parts.append(text)
    if final.get("valid_pairs", 0) < 3:
        parts.append("Недостаточно пригодных пар процессов")
    return "<br>".join(parts)


def ranked_changes(machines: dict, decision: str, top: int = 10) -> list[tuple]:
    changes = []
    for machine, result in machines.items():
        if not result or result.get("stand_preflight_failed"):
            continue
        for name, row in result.get("cases", {}).items():
            if result.get("confirmation_required") and "confirmation" not in row:
                continue
            if context(name, row)[0] not in {"workload", "operation"}:
                continue
            final = row.get("final", {})
            if final.get("semantic_match") is not True or final.get("valid_pairs", 0) < 3:
                continue
            for metric in final.get("primary_metrics", []):
                observed = final.get("metrics", {}).get(metric, {})
                if confirmed_decision(row, metric) == decision and observed.get("median") is not None:
                    changes.append((abs(observed["median"] - 1), name, metric, machine))
    changes.sort(key=lambda item: (-item[0], item[1:]))
    selected, seen = [], set()
    for change in changes:
        key = family(change[1])
        if key not in seen:
            seen.add(key)
            selected.append(change)
        if len(selected) == top:
            break
    return selected


def metric_text(result: dict | None, name: str, metric: str) -> str:
    if not result or result.get("stand_preflight_failed"):
        return "Нет пригодного замера"
    row = result.get("cases", {}).get(name)
    if not row:
        return "Нет замера"
    final = row.get("final", {})
    if final.get("semantic_match") is not True:
        return "Различие результатов вычисления"
    value = final.get("metrics", {}).get(metric, {})
    if value.get("median") is None:
        return "Нет замера метрики"
    interval = value.get("median_interval_95") or [value.get("minimum"), value.get("maximum")]
    bounds = ""
    if all(bound is not None for bound in interval):
        bounds = f" [{percent(interval[0])}…{percent(interval[1])}]"
    text = percent(value["median"]) + bounds
    if "confirmation" in row:
        repeat = (row["confirmation"] or {}).get("final", {}).get("metrics", {}).get(metric, {})
        if repeat.get("median") is not None:
            text += f"; повтор {percent(repeat['median'])}"
        else:
            text += "; повтор не дал пригодного замера"
    elif result.get("confirmation_required"):
        text += "; только первый проход"
    if confirmed_decision(row, metric) not in {"BETTER", "WORSE", "SAME"}:
        text += "; направление не установлено"
    return text


def write_report(output: Path, machines: dict[str, dict | None]) -> None:
    assessment = assess(machines)
    lines = ["# Pulse: материал для changelog и TODO", "",
             "Изменение затрат Current относительно Remote: **минус — дешевле, плюс — дороже**. "
             "Процент относится к указанной операции и входам, а не к скорости всех программ. "
             "В скобках — 95% интервал медианы парных отношений (у старых данных — наблюдаемый диапазон). "
             "Полные диапазоны и абсолютные цены сохранены в [CASES.md](CASES.md).", ""]
    details = ["# Все измеренные операции", "", "CPU — в единицах машины; время — TSC ticks/op; память — bytes.", ""]
    if any(result and result.get("confirmation_required") for result in machines.values()):
        lines.extend(["Пункты топа проходят отдельный повтор на 12 свежих парах после полного прохода. "
                      "В топ попадает только направление, установленное в обоих проходах. "
                      "Первый проход и повтор хранятся отдельно; неповторившиеся эффекты остаются открытыми рисками.", ""])
    for machine, result in machines.items():
        if not result:
            lines.append(f"{machine}: нет завершённого замера.")
            continue
        lines.append(f"{machine}: {result.get('machine', {}).get('cpu_work_unit', 'единицы в отчёте машины')}.")
        if result.get("elapsed_seconds"):
            lines.append(f"{machine}: проход занял {result['elapsed_seconds'] / 60:.1f} мин, из них замер "
                         f"{result.get('measurement_seconds', 0) / 60:.1f} мин (остальное — сборка программ и разбор).")
        rejections = result.get("runner_rejections")
        if rejections:
            rule = result.get("core_watch")
            watched = (f"ни один одноядерный процесс не стартовал на ядре, где за {rule['horizon_seconds']:g} с до "
                       f"него шла чужая работа (свои процессы раннера вычтены) или которое после своего "
                       f"прошлого процесса простояло меньше {rule['rest_seconds'] * 1000:g} мс"
                       if rule else "перед каждым одноядерным процессом ядро замера 2 с проверялось на простой")
            lines.append(f"{machine}: {watched}; "
                         f"отвергнуто стендом процессов {rejections['rejected']} из {rejections['processes']} "
                         f"(ядро не простаивало перед процессом — {rejections['core_not_idle']}, "
                         f"SMT-сосед был занят во время процесса — {rejections['sibling_busy']}); "
                         "отвергнутая пара повторяется в пределах трёх попыток.")
        if result.get("scope"):
            lines.append(f"Область {machine}: `{result['scope'].get('cases', 'all')}`; программы: "
                         + ", ".join(result["scope"].get("programs", [])) + ".")
            for program, systems in (result["scope"].get("left_out") or {}).items():
                lines.append(f"{machine}: программа `{program}` не сравнивалась — её не собрать "
                             f"тулчейном {', '.join(systems)} (нет юнита, например релиз до него).")
            for name, need in (result["scope"].get("unhostable") or {}).items():
                lines.append(f"{machine}: {'строка' if '/' in name else 'программа'} `{name}` не мерилась — она "
                             f"ставит {need['workers']} рабочих потоков, каждый на своё физическое ядро, а у машины "
                             f"их {need['multithread_cpus']}.")
        if result.get("reanalyzed_from"):
            lines.append(f"{machine}: повторный разбор сохранённых данных; новых измерений не было.")
        for side in ("baseline", "candidate"):
            identity = result.get(f"{side}_toolchain", {})
            if identity.get("backend_sha256"):
                details.append(f"{machine} {side}: `{identity['backend_sha256']}`.")
        if result.get("stand_preflight_failed"):
            lines.append(f"**{machine}: контроль A/A не прошёл; направление изменений здесь не доказано.**")
        if result.get("confirmation_preflight") and not result["confirmation_preflight"]["passed"]:
            lines.append(f"**{machine}: подтверждающий контроль A/A не прошёл; пункты топа не подтверждены.**")
    for decision, title in (("BETTER", "Лучше: топ-10 важных операций"), ("WORSE", "Хуже: топ-10 для TODO")):
        lines.extend(["", "## " + title, "", "Обычные операции и прикладные нагрузки. "
                      "Сортировка по относительному изменению; из одного семейства размеров — один представитель. "
                      "Это порядок разбора, а не оценка доли в настоящей программе.", ""])
        changes = ranked_changes(machines, decision)
        if not changes:
            lines.append("Уверенно установленного изменения этого направления нет.")
            continue
        lines.extend(["| Операция и входы | Что меняется | " + " | ".join(machines) + " |",
                      "| --- | --- | " + " | ".join("---" for _ in machines) + " |"])
        for _, name, metric, _ in changes:
            purpose = context(name, {})[1]
            lines.append(f"| `{name}`<br>{purpose} | {METRICS[metric]} | " +
                         " | ".join(metric_text(result, name, metric) for result in machines.values()) + " |")
    lines.extend(["", "## Размены", "",
                  "**Принят: обычный Move ценой self-copy.** Проверка равенства адресов убрана с пути "
                  "обычного копирования; цена `Move(X,X,N)` принята владельцем проекта (24.09.2026, "
                  "история `cc0291797`). Этот no-op исключён из замеров скорости, семантический тест сохранён. "
                  "Процент ускорения обычного Move зависит от размера и машины:", ""])
    move_machines = {machine: {**result, "cases": {name: row for name, row in result.get("cases", {}).items()
                                                if name.startswith("move/")}} if result else None
                     for machine, result in machines.items()}
    for _, name, metric, _ in ranked_changes(move_machines, "BETTER", 4):
        lines.append(f"- `{name}`: " + "; ".join(f"{machine} {metric_text(result, name, metric)}"
                                                for machine, result in machines.items()))
    lines.extend(["", "Другие сочетания выигрыша и потерь **не считаются автоматически принятым разменом**. "
                  "Регресс обычного Move, другая операция или потеря на другой машине остаются в TODO. "
                  "Для принятия нужны связь изменений и объяснение, почему выигрыш важнее цены.", ""])
    for machine, result in machines.items():
        if not result or result.get("stand_preflight_failed"):
            continue
        for name, row in result.get("cases", {}).items():
            if "confirmation" not in row or not {"BETTER", "WORSE"} <= set(metric_decisions(row)):
                continue
            parts = []
            for metric in row["final"]["primary_metrics"]:
                if confirmed_decision(row, metric) not in {"BETTER", "WORSE"}:
                    continue
                value = row["final"]["metrics"][metric]["median"]
                costs = row["final"].get("centers", {}).get(metric, {})
                absolute = ""
                if metric.startswith("memory_") and costs:
                    absolute = f" ({costs['moon-baseline'] / 1048576:.2f} → {costs['moon-candidate'] / 1048576:.2f} MiB)"
                parts.append(f"{METRICS[metric]} {percent(value)}{absolute}")
            lines.append(f"- **Наблюдаемый размен ресурсов**, `{machine}: {name}`: " + "; ".join(parts) +
                         ". Оба направления подтверждены; допустимость ещё не согласована. Память относится ко всему тестовому процессу.")
    # Put uncertain material costs into the engineer's TODO, never rename them SAME.
    risks = []
    grouped = defaultdict(list)
    for machine, result in machines.items():
        if not result:
            continue
        for name, row in sorted(result.get("cases", {}).items()):
            if name.startswith("move/same-"):
                continue
            role, purpose = context(name, row)
            grouped[role].append((machine, name, row, purpose))
            if result.get("stand_preflight_failed") or role not in {"workload", "operation"}:
                continue
            final = row.get("final", {})
            if final.get("semantic_match") is not True:
                continue
            for metric in final.get("primary_metrics", []):
                value = final.get("metrics", {}).get(metric, {})
                if confirmed_decision(row, metric) in {"BETTER", "WORSE", "SAME"} or value.get("median") is None:
                    continue
                interval = value.get("median_interval_95") or [value.get("minimum"), value.get("maximum")]
                if all(bound is not None for bound in interval):
                    risks.append((max(abs(bound - 1) for bound in interval), machine, name, metric))
    if risks:
        lines.extend(["## Что уточнить перед обещанием отсутствия регрессий", "",
                      "У этих полезных операций диапазон пока пересекает границу решения. "
                      "Это конкретные незакрытые риски; ни ускорение, ни равенство здесь не заявлены.", ""])
        seen = set()
        for _, machine, name, metric in sorted(risks, reverse=True):
            if (family(name), metric) in seen:
                continue
            seen.add((family(name), metric))
            lines.append(f"- `{machine}: {name}` — {METRICS[metric]}: {metric_text(machines[machine], name, metric)}")
            if len(seen) == 10:
                break
    lines.extend(["", "## Как решать о релизе", "",
                  "Подтверждённые потери выше — будущий список оптимизаций. Их нельзя списывать числом выигрышей. "
                  "Решение зависит от используемых операций и допустимой цены. "
                  "Прикладные модели и обычные операции входят в этот отчёт; изолированные формы кодогена, "
                  "граничные входы и контроли разобраны отдельно в CASES.md и не определяют релиз по числу строк. "
                  "Pulse сам по себе не заменяет проверку корректности и сборки релиза.", ""])
    if assessment["semantic_mismatches"]:
        lines.extend(["## Различия результатов вычисления — требуется исправление", "",
                      *(f"- `{name}`" for name in assessment["semantic_mismatches"]), ""])
    for role, title in ROLE_NAMES.items():
        if not grouped[role]:
            continue
        details.extend(["", "## " + title, "", "| Машина | Операция | Назначение | Измерение |", "| --- | --- | --- | --- |"])
        for machine, name, row, purpose in grouped[role]:
            details.append(f"| {machine} | `{name}` | {purpose} | {evidence(row)} |")
            if row.get("confirmation"):
                details.append(f"| {machine}, повтор | `{name}` | {purpose} | {evidence(row['confirmation'])} |")
    expected = {name: row for result in machines.values() if result for name, row in result.get("cases", {}).items()}
    for machine, result in machines.items():
        if result:
            for name, row in expected.items():
                if name not in result.get("cases", {}) and context(name, row)[0] != "control":
                    lines.append(f"{machine}: отсутствует замер `{name}`.")
    (output / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "CASES.md").write_text("\n".join(details) + "\n", encoding="utf-8")
