# Приёмка ручной ASM раскладки

`../tools/manual_layout_judge.py manifest.json [--cells cells.csv] [--out report.json]` использует только стандартную библиотеку Python. Код возврата: 0 — весь объявленный пакет ACCEPT, 1 — KEEP_OLD, 2 — INVALID evidence. `python -m unittest discover -s ../tools -p test_manual_layout_judge.py` запускает негативные контроли.

Матрица задаётся **до запуска**, а не выводится из результатов. Пример сокращённой схемы (для настоящей приёмки positions содержит все 64 числа 0..4032 с шагом64, cpus — все доступные модели, processes — ожидаемые 3 запуска):

```json
{
  "schema": 1,
  "profile": "acceptance",
  "cpus": ["amd2", "intel3e"],
  "cpu_identity": {
    "amd2": {"brand": "AMD EPYC 4245P 6-Core Processor", "affinity_cpu": 5},
    "intel3e": {"brand": "13th Gen Intel(R) Core(TM) i9-13900", "affinity_cpu": 22}
  },
  "processes": ["1", "2", "3"],
  "rounds": [1, 2, 3, 4, 5, 6, 7],
  "positions": [0, 64],
  "drivers": [0, 32],
  "expected_variants": {"amd2": 296, "intel3e": 296},
  "limits": {"aa": 1, "loss": 5, "gain": 10, "counter_uncertainty": 1},
  "groups": [
    {"name": "r19-varset-contains", "cases": [0], "tags": ["h"], "refphases": [0]}
  ],
  "runs": [
    {"cpu": "amd2", "process": "1", "raw": "raw/amd2/c0-p1-a1.tsv", "cases": [0],
     "accepted": true, "exit_code": 0, "monitor_mean": 0, "monitor_peak": 0}
  ]
}
```

Это пример структуры, сам он INVALID: не содержит остальных запусков и полного списка positions. Каждая группа требует все `cpus`; `groups[].cpus`, если указан, обязан совпадать с общим списком. Cases — номера случаев стенда, а не длины в байтах. Для MoonORMot нужны `refphases: [0,32]`. Все соответствующие `refpN` и `aapN` обязательны. Один raw может содержать несколько объявленных групп/случаев. Остальные группы в нём игнорируются, но correctness failure в любом месте файла запрещает приёмку. `--cells` сверяет весь CSV с объявленным scope; предварительно отфильтрованный CSV должен содержать все его сравнения и только их.

`runs` формируется из записей действительно принятых wrapper-запусков. `process` — идентификатор независимого запуска, не номер retry; одна попытка не заменяет несколько процессов. Judge не запускает процессы и не удостоверяет честность внешнего manifest. Одинаковые пути/копии raw, дубли sample keys и двусмысленные CSV file names запрещены. Опциональный `raw_sha256` фиксирует содержимое файла. Brand и affinity обязательны в manifest, сверяются с каждым raw header; их надо задавать по inventory до замера. Проверка build hash и выбора PMU type остаётся обязанностью wrapper, который публикует identity. Произвольные найденные TSV нельзя автоматически объявлять принятыми.

Raw парсится заново: точные Oracle/Geometry counts, отсутствие FAIL, точные INPROC_DONE counts, каждый declared CPU/process/group/case/tag/position/driver/round ровно один раз. Пропуски, лишние позиции/фазы и повторенные rounds дают INVALID, даже если сумма строк совпадает. CSV не является самостоятельным доказательством; значения ref/candidate/loss/AA пересчитываются из raw и сверяются.

Для каждого отдельного положения/фазы/случая/CPU берётся median rounds внутри одного процесса. Единица — один **driver sweep**, не cycles отдельного primitive call. Фазы и CPU не усредняются. A/A >1% либо spread=(q75/q25-1)>2% у ref/control/candidate хотя бы в одной клетке запрещают ACCEPT. Inclusive quartiles пропускают один interruption outlier среди7rounds, но замечают второй существенный режим2из7. Это инженерный фильтр, не статистический доверительный интервал. Upper ratio умножается на `(1+AA/100)/(1-counter_uncertainty/100)`; для PMU, разрешающего до1% неучтённого RunningTime, default counter_uncertainty=1%. Обнулять его можно только после проверки метода счёта.

ACCEPT требует минимум3 независимых процесса, все64positions и drivers0/32. Два процесса могут дать REJECT, но никогда ACCEPT. Явный `profile: "probe"` разрешает меньшую матрицу, но также никогда ACCEPT. Во всех процессах/клетках upper loss должен быть <=5%, а gain>10% должен повториться во всех объявленных процессах **одной и той же клетки**. Если каждый upper loss<0, порог gain10% не нужен. Повторённая clean потеря сверх5% — REJECT: A/A<=1% и spread<=2% у ref/control/candidate обязательны во всех повторениях этой клетки. Шумная потеря не является доказанной регрессией; остальные не прошедшие случаи — UNPROVEN. Оба означают KEEP_OLD.

PASS доказывает только объявленные входы, позиции и caller. Даже64 положения не доказывают произвольные контексты линкера, иной окружающий код, рабочие множества данных, холодный первый вызов или все ветки процедуры. Например текущий case0 varset-contains использует лишь32байтные множества; он не покрывает ветку `<16`.
