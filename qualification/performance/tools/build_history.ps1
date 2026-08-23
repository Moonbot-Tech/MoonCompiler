param(
  [string]$Output = (Join-Path $PSScriptRoot '..\PULSE_HISTORY.html'),
  [string]$ResultsRoot = ''
)

$ErrorActionPreference = 'Stop'
$PerformanceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($ResultsRoot) {
  $ResultsRoot = [IO.Path]::GetFullPath($ResultsRoot)
} else {
  $ResultsRoot = Join-Path $PerformanceRoot 'results\pulse'
}
$HistorySnapshotPath = Join-Path $PerformanceRoot 'evidence\history-ratios.json'
$HistorySnapshot = @{}
if (Test-Path -LiteralPath $HistorySnapshotPath) {
  $SnapshotObject = Get-Content -LiteralPath $HistorySnapshotPath -Raw | ConvertFrom-Json
  foreach ($StageProperty in $SnapshotObject.stages.PSObject.Properties) {
    $Cases = @{}
    foreach ($CaseProperty in $StageProperty.Value.PSObject.Properties) {
      $Cases[$CaseProperty.Name] = [double]$CaseProperty.Value
    }
    $HistorySnapshot[$StageProperty.Name] = $Cases
  }
}

$Stages = @(
  [ordered]@{
    id = 'baseline'
    label = 'Было: до RTL-оптимизаций'
    short = 'Было'
    note = 'Первый полный Win64 O3 medium на b02d18d7: исходная точка именно для нынешней серии оптимизаций.'
    files = @('pulse-win64-medium-final-2\summary.json')
    unstable = @()
  },
  [ordered]@{
    id = 'rtl_containers'
    label = 'Сейчас: RTL + containers'
    short = 'Сейчас'
    note = 'Текущие Win64 O3 medium замеры на 5b427091/3e2e5642; product source между этими HEAD идентичен. Каждый следующий существенный этап добавляется новой колонкой справа, старые не перезаписываются.'
    files = @(
      'pulse-current-nonrtl-medium-20260816\summary.json',
      'pulse-current-rtl-medium-20260816\summary.json',
      'rtl-collections-final-medium-20260816\summary.json'
    )
    unstable = @(
      'codegen/fillchar-4k',
      'codegen/scan-llc',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'mm/fragmented-mixed',
      'workloads/stream-add',
      'workloads/stream-triad',
      'rtl/object-create-virtual-free'
    )
  },
  [ordered]@{
    id = 'loop_codegen'
    label = 'Сейчас: + loop codegen'
    short = 'Loop codegen'
    note = 'Все прежние значения перенесены без подмены замера; threads/padded-counters-4 повторён отдельно после безопасного выноса доказанно неизменного адреса из цикла. Win64 O3 medium, 8 процессов на compiler, 37 samples на процесс, одинаковое закрепление четырёх workers по CPU.'
    inherit = 'rtl_containers'
    files = @()
    values = [ordered]@{
      'threads/padded-counters-4' = 0.500379709
    }
    unstable = @()
  },
  [ordered]@{
    id = 'exception_threads'
    label = 'Сейчас: + exception/thread roots'
    short = 'Exception + threads'
    note = 'Post-inline no-throw proof довёл dispatch/try-except-no-raise до такт-в-такт паритета. Все thread workloads повторены с persistent pinned workers; lifecycle остался только в отдельном thread-start-join case. Для padded counter сохранён более строгий отдельный 8-process A-B-B-A замер.'
    inherit = 'loop_codegen'
    files = @('threads-persistent-final-20260816\summary.json')
    values = [ordered]@{
      'dispatch/try-except-no-raise' = 0.999983309
      'threads/padded-counters-4' = 0.500379709
    }
    unstable = @()
  },
  [ordered]@{
    id = 'mm_44_classes'
    label = 'Сейчас: + MM 44 класса'
    short = 'MM 44'
    note = 'MoonShard возвращён к исходным 44 small-классам до 2600 байт при физической строке 64 cache-line/4096 байт. MM-группа повторена Win64 O3 medium; realloc-grow улучшился с 3.04x до 1.047x. alloc-free-256 помечен как process-drift и не используется как вывод этого этапа.'
    inherit = 'exception_threads'
    files = @('mm-44-padding-medium-20260816\summary.json')
    unstable = @('mm/alloc-free-256')
  },
  [ordered]@{
    id = 'gaps_block'
    label = 'Сейчас: + очередь perf-gap'
    short = 'Perf-gaps'
    note = 'Полный Win64 O3 medium на ветке perf/remaining-gaps-20260817 (PERF-005..010): Grisu digit core в FloatToDecimal, movless-инлайн managed funcret в компиляторе, snapshot console codepage на поток, format-движок без heap и widechar-in-set цепь сравнений. Устойчивый geomean 343 cases = 0.768; json/generate-64 и list-string-read инвертированы в пользу Moon. Шесть drift-пар этого прогона исключены из выводов.'
    files = @('full-medium-after-gaps-20260817\summary.json')
    unstable = @(
      'json/scan-large-4096',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'workloads/stream-add'
    )
  },
  [ordered]@{
    id = 'tail_block'
    label = 'Сейчас: + хвост таблицы и стек'
    short = 'Tail block'
    note = 'Delphi-парити дефолт стека (PERF-011) плюс шесть самых тяжёлых остатков хвоста одним заходом (PERF-012..016): pointer-bump для глобальных массивов с liveness-гейтом счётчика, post-RA расширение byte/word копий, инлайн record-параметров без самопорождённой копии, удаление мёртвых range-очисток TList. Win64 O3 medium; list-index и call-interface — доказанный code-placement, не дефект кода (PERF-016).'
    files = @('full-medium-gapblock3-20260817\summary.json')
    unstable = @(
      'codegen/fillchar-4k',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'dispatch/list-index',
      'codegen/call-interface'
    )
  },
  [ordered]@{
    id = 'wave3'
    label = 'Сейчас: + generic-list, record/ABI, managed'
    short = 'Wave 3'
    note = 'Третья волна (PERF-017..020): pointer-bump для элементов шире hardware scale, fast-path TList.Add/DoRemove без виртуальных вызовов, инлайновый кодген атомик-интринзиков x86-64 (lock xadd/xchg/cmpxchg на месте вызова), сплющенные managed-присваивания (_AddRef/_Release, fpc_dynarray_assign). Win64 O3 medium; регрессий между срезами нет.'
    files = @('full-medium-wave3-20260818\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-write-64m',
      'codegen/fillchar-4k',
      'codegen/scan-strided',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed'
    )
  },
  [ordered]@{
    id = 'wave3_followup'
    label = 'Сейчас: + добивка третьей волны'
    short = 'Wave 3+'
    note = 'Добивка (PERF-021): exit-free fast-path TList.Delete (ранний Exit в inline-методе внутри чужого exception-региона компилировался в local unwind), inline TObject.ClassInfo, GPR-копии малых блоков вместо SSE (store-to-load forwarding на прологовых копиях record-параметров), unchecked fast-path 32-битной variant-арифметики. open-array-const прошёл двухшаговый placement-тест — код бит-в-бит идентичен baseline.'
    files = @('full-medium-wave4-20260818\summary.json')
    unstable = @(
      'abi/record16-value',
      'abi/open-array-const',
      'calibration/asm-memory-write-64m',
      'codegen/fillchar-4k',
      'dispatch/try-except-no-raise',
      'managed/interface-copy-call',
      'mm/alloc-free-16',
      'mm/alloc-free-17408',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed'
    )
  },
  [ordered]@{
    id = 'wave5'
    label = 'Сейчас: + variant и bulk-insert слой'
    short = 'Variant layer'
    note = 'PERF-022: прямые конверсии variant->целое (четыре уровня вызова свёрнуты в чтение поля, фаза конверсии в паритете с Delphi) и notify-free managed InsertRange (виртуальный Notify на каждый из 2048 элементов без подписчика). dispatch/list-index — задокументированный placement-маятник PULSE-DECISION-007, код бит-в-бит неизменен.'
    files = @('full-medium-wave5-20260818\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-read-64m',
      'calibration/asm-memory-write-64m',
      'calibration/asm-mixed-integer',
      'codegen/fillchar-4k',
      'dispatch/list-index',
      'managed/interface-copy-call',
      'mm/alloc-free-1m',
      'rtl/object-create-free'
    )
  },
  [ordered]@{
    id = 'wave6'
    label = 'Сейчас: + bulk-финализация строк'
    short = 'Bulk finalize'
    note = 'PERF-023: fpc_UnicodeStr/AnsiStr_Finalize_Many — снос строкового массива одним вызовом с вынесенным multithread-гейтом вместо call на каждый элемент (делфийская UStrArrayClr-симметрия, замыкает линию PERF-001). scan-small-16 и object-create-virtual-free — межсрезовый шум, снят честным A/B (Moon/baseline 1.000/0.984).'
    files = @('full-medium-wave6-20260818\summary.json')
    unstable = @(
      'calibration/asm-memory-write-64m',
      'codegen/fillchar-4k',
      'json/scan-small-16',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'rtl/object-create-virtual-free',
      'workloads/stream-add',
      'workloads/stream-copy',
      'workloads/stream-scale',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'wave9'
    label = 'Сейчас: + bump при живом счётчике'
    short = 'Live-counter bump'
    note = 'PERF-025: pointer-bump глобальных массивов разрешён при живом счётчике, если цикл всегда добегает до конца (нет break/exit/goto) — делфийская форма обхода. Смена case-стратегии (дерево/таблица вместо цепочки) опровергнута A/B и откачена: на непредсказуемом селекторе линейная цепочка строго лучше (таблица дала 2.73x). Нестабильные пары — по drift-списку самого прогона.'
    files = @('wave9-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-write-64m',
      'codegen/fillchar-4k',
      'codegen/scan-dram',
      'loops/histogram-random',
      'managed/interface-copy-call',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed',
      'rtl-collections/list-string-add-reserved',
      'workloads/stream-add',
      'workloads/stream-scale'
    )
  },
  [ordered]@{
    id = 'wave11'
    label = 'Сейчас: + bulk-incref строк'
    short = 'Bulk incref'
    note = 'PERF-026: fpc_AnsiStr/UnicodeStr_Incr_Ref_Many — подъём refcount строкового ряда одним вызовом с вынесенным multithread-гейтом (зеркало PERF-023); fpc_addref_array маршрутизирует строки через них (выигрывают и COW-копии динмассивов), TList.InsertRange без подписчика — Move блока + один addref вместо по-элементных присваиваний. Нестабильные пары — по drift-списку прогона.'
    files = @('wave11-full\summary.json')
    unstable = @(
      'codegen/scan-llc',
      'codegen/fillchar-4k',
      'managed/interface-copy-call',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed',
      'rtl/object-create-virtual-free',
      'workloads/stream-add',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'wave13'
    label = 'Сейчас: + TStringBuilder и char-конверсии'
    short = 'StringBuilder'
    note = 'PERF-027: три слоя разрыва 5.85x у TStringBuilder.Append — прямые пути по полям вместо property-обвязки, свёртка char-констант после инлайна в компиляторе, ASCII-путь fpc_Char_To_UChar без widestringmanager (аллокация+WinAPI на каждый символ). append-literals 5.85 -> 1.14 (baseline 0.191), json/generate-64 0.85 -> 0.49. call-virtual/open-array-const — placement, доказано бит-в-бит идентичным дизасмом на тех же адресах; нестабильные пары — по drift-списку прогона.'
    files = @('wave13-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'codegen/fillchar-4k',
      'codegen/scan-dram',
      'mm/alloc-free-1m',
      'rtl/generic-list-add-reserved',
      'rtl-collections/objectlist-owned-clear',
      'rtl-collections/queue-string-steady',
      'workloads/stream-add',
      'workloads/stream-copy',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'wave15'
    label = 'Сейчас: + добивка билдера и untyped-const wrong-code'
    short = 'Builder tail'
    note = 'PERF-028: смена ёмкости билдера копирует только живой ряд (growth 1.65 -> 1.41); wrong-code фикс — untyped const аргументы всегда несут ra_addr_taken, иначе инлайн-подстановка литерала давала свёртку Move(S[1],...) в один символ (пин formal_const_address_semantic, матрица 144/144). Нестабильные пары — по drift-списку прогона.'
    files = @('wave15-full\summary.json')
    unstable = @(
      'codegen/fillchar-4k',
      'loops/histogram-random',
      'mm/alloc-free-17408',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'mm/fragmented-mixed',
      'rtl-collections/objectlist-owned-clear',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'wave18'
    label = 'Сейчас: + RTL-аудит (datetime/hex/конверсии)'
    short = 'RTL audit'
    note = 'PERF-029: восемь новых аудит-кейсов (datetime, hex, trim, replace, try-parse) + ремонты системного класса мин «посимвольные операции через widestringmanager»: Char-таблица IntToHex (7.04 -> 1.85), ASCII UpCase/LowerCase (datetime-format 2.99 -> 0.57, Moon вдвое впереди), ASCII-конверсии строк без WinAPI, поля даты без heap-строк. Нестабильные пары — по drift-списку прогона.'
    files = @('wave18-full\summary.json')
    unstable = @(
      'codegen/fillchar-4k',
      'codegen/scan-strided',
      'managed/interface-copy-call',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed'
    )
  },
  [ordered]@{
    id = 'wave21'
    label = 'Сейчас: + RTL-аудит волна 3 (streams/replace/регистры)'
    short = 'RTL audit 3'
    note = 'PERF-030 + добивка класса конверсий: инлайн ASCII-ветки fpc_Char_To_UChar (append-literals 5.85 -> 0.97, StringBuilder впереди Delphi), StringReplace одним сканом (1.77 -> 1.40), TStringStream без двойной конверсии (1.39 -> 1.03), ASCII-регистры строк одним циклом (uppercase-4k 0.75). Пять новых кейсов волны 3. Нестабильные пары — по drift-списку прогона.'
    files = @('wave21-full\summary.json')
    unstable = @(
      'abi/open-array-const',
      'codegen/fillchar-4k',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'mm/realloc-shrink',
      'rtl/inttohex-int64',
      'rtl/object-create-virtual-free'
    )
  },
  [ordered]@{
    id = 'wave31'
    label = 'Сейчас: + оптимум-проход (SWAR, парсер, replace)'
    short = 'Optimum pass'
    note = 'Оптимум-аудит всей ветки: мерило — потолок алгоритма, не Delphi. SWAR-ядра строковых операций (4 символа за шаг, 1.4 такта/символ = bandwidth-потолок), прямой целочисленный парсер с cutoff-циклом (trystrtoint 1.81 -> 1.14, edges 0.88 впереди Delphi), StringReplace инлайн-сканом без кучи до первого совпадения (0.999 паритет), два ниббла за шаг в IntToHex. Вердикты по слоям — BRANCH_AUDIT.md, секция «Оптимум-проход». Нестабильные пары — по drift-списку прогона.'
    files = @('wave31-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-read-64m',
      'codegen/scan-dram',
      'codegen/scan-strided',
      'codegen/call-interface',
      'codegen/call-virtual',
      'managed/interface-copy-call',
      'mm/alloc-free-1m'
    )
  },
  [ordered]@{
    id = 'wave33'
    label = 'Сейчас: + безусловные lock-refcount (нож IsMultithread)'
    short = 'No gate'
    note = 'PERF-031: решение владельца — продукт всегда многопоточен, гейт IsMultithread вырезан из 12 asm-мест и bulk-хелперов; ansi refcount-тройка стала asm-зеркалом юникодной (rawbytestring-assign 1.25 -> 1.01). ВНИМАНИЕ: физика managed-замеров сменилась — однопоточные цифры до этой колонки сравнивать с новыми нельзя (был no-lock путь, стал честный lock как в проде и как у Delphi). mt-кейсы совпадают с однопоточными. Открытый хвост: insertrange 1.75 (lock-ряд массовых вставок, вскрытие следующим шагом).'
    files = @('wave33-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-read-64m',
      'codegen/scan-strided',
      'json/parse-medium-custom-double',
      'managed/interface-copy-call',
      'mm/alloc-free-16',
      'mm/alloc-free-16k',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'rtl/object-create-virtual-free',
      'rtl-collections/list-string-add-reserved'
    )
  },
  [ordered]@{
    id = 'wave35'
    label = 'История: отклонённый ref=1 fast path'
    short = 'Отклонено'
    note = 'ИСТОРИЧЕСКИЙ НЕБЕЗОПАСНЫЙ СРЕЗ. PERF-032 заменял atomic increment при Ref=1 простым store. Интеграционный аудит отклонил кандидат: два конкурентных читателя единственной общей ссылки могут оба записать Ref=2 и потерять один increment. Цифры сохранены только как история эксперимента и не описывают продуктовый HEAD.'
    files = @('wave35-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-read-64m',
      'codegen/fillchar-4k',
      'codegen/scan-dram',
      'json/generate-64',
      'loops/histogram-random',
      'mm/alloc-free-16',
      'mm/alloc-free-16k',
      'mm/alloc-free-1m',
      'rtl/object-create-free',
      'rtl/object-create-virtual-free',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'wave36'
    label = 'История: dynarray-циклы поверх отклонённого ref=1'
    short = 'История B'
    note = 'ИСТОРИЧЕСКИЙ СРЕЗ С НЕБЕЗОПАСНЫМ PERF-032 В ОСНОВЕ. PERF-033 отдельно добавлял pointer induction для динамических массивов и codegen cases, но итоговые ratios нельзя считать цифрами продуктового HEAD. Безопасные изменения перенесены; их результат снимается заново после интеграции.'
    files = @('wave36-full\summary.json')
    unstable = @(
      'codegen/fillchar-4k',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'mm/fragmented-mixed',
      'workloads/linked-list-insert-sort-512'
    )
  },
  [ordered]@{
    id = 'wave37'
    label = 'История: signed mod поверх отклонённого ref=1'
    short = 'История C'
    note = 'ИСТОРИЧЕСКИЙ СРЕЗ С НЕБЕЗОПАСНЫМ PERF-032 В ОСНОВЕ. PERF-034 отдельно редуцировал signed mod константой и добавлял semantic/codegen cases. Безопасный ремонт перенесён, но ratios этой колонки не являются квалификацией продуктового HEAD.'
    files = @('wave37-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'calibration/asm-memory-read-64m',
      'codegen/fillchar-4k',
      'mm/alloc-free-1m'
    )
  },
  [ordered]@{
    id = 'wave38'
    label = 'История: TStringHelper поверх отклонённого ref=1'
    short = 'История helper'
    note = 'ИСТОРИЧЕСКИЙ СРЕЗ С НЕБЕЗОПАСНЫМ PERF-032 В ОСНОВЕ. PERF-035 отдельно проверял фасады TStringHelper и исправлял данные trim-string. Безопасные тесты и реализации перенесены, но точные ratios снимаются заново на интеграционном HEAD.'
    files = @('wave38-full\summary.json')
    unstable = @(
      'abi/record16-value',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'mm/alloc-free-2m',
      'mm/fragmented-mixed',
      'rtl/memorystream-write-small'
    )
  },
  [ordered]@{
    id = 'integration_safe'
    label = 'Текущий продукт: безопасная интеграция'
    short = 'Product HEAD'
    note = 'Точный Win64 O3 medium на c0139f0e: 390 cases, все semantic oracles MATCH. Небезопасный Ref=1 fast path отсутствует. Три cases помечены process-drift и не используются для точечных выводов; без них geomean Moon/Delphi = 0.723, 203 выигрыша, 120 паритетов, 64 проигрыша.'
    tracked = $true
    files = @('evidence\integration-current-20260820\summary.json')
    unstable = @(
      'loops/histogram-random',
      'managed/closure-create-invoke',
      'mm/alloc-free-1m'
    )
  },
  [ordered]@{
    id = 'integration_final_20260823'
    label = 'Финал: текущий main 81daffaa'
    short = 'Main 2026-08-23'
    note = 'Точный Win64 O3 medium на 81daffaa: 390/390 semantic oracles MATCH. Девять process-drift cases отмечены знаком † и исключены из агрегата; без них geomean Moon/Delphi = 0.7318, 195 выигрышей, 118 паритетов, 68 проигрышей. Allocator-группа: bundled MM / default FPC MM = 0.6179.'
    tracked = $true
    files = @('evidence\integration-final-20260823\summary.json')
    unstable = @(
      'abi/record16-value',
      'codegen/scan-llc',
      'codegen/scan-strided',
      'managed/interface-copy-call',
      'mm/alloc-free-1m',
      'rtl-collections/objectlist-owned-clear',
      'rtl-collections/stack-string-roundtrip',
      'workloads/stream-scale',
      'workloads/stream-triad'
    )
  },
  [ordered]@{
    id = 'dictionary_matrix_20260823'
    label = 'Сейчас: + размерная матрица TDictionary'
    short = 'Dictionary matrix'
    note = 'Compiler binary не менялся относительно предыдущей колонки. Добавлены 24 medium-case: UInt64/UnicodeString key/value, 100/10 000 элементов, grow/reserve/lookup/churn. 24/24 oracle MATCH; один Delphi process-pair отмечен drift. По 23 устойчивым новым cases geomean Moon/Delphi = 0.9569.'
    inherit = 'integration_final_20260823'
    tracked = $true
    files = @('evidence\dictionary-matrix-20260823\summary.json')
    unstable = @(
      'dictionary/u64-u64-build-grow-100'
    )
  }
)

function Get-CaseDescription([string]$Case) {
  $Exact = @{
    'local-pressure/empty' = 'Вызов пустой процедуры.'
    'local-pressure/unused-plain-100' = 'Процедура объявляет 100 неиспользуемых unmanaged locals.'
    'local-pressure/unused-strings-100' = 'Процедура объявляет 100 неиспользуемых строковых locals.'
    'local-pressure/unused-buffers-100' = 'Процедура объявляет 100 неиспользуемых dynamic arrays.'
    'local-pressure/unused-mixed-300' = 'Процедура объявляет 100 строк, 100 dynamic arrays и 100 plain locals, но не использует их.'
    'local-pressure/used-plain-100' = 'Процедура реально использует 100 unmanaged locals.'
    'local-pressure/used-strings-100' = 'Процедура реально использует 100 строковых locals.'
    'local-pressure/used-buffers-100' = 'Процедура реально использует 100 dynamic arrays.'
    'local-pressure/used-mixed-300' = 'Главный local-pressure: 100 строк, 100 dynamic arrays и 100 plain locals, все реально используются.'
    'dispatch/try-except-no-raise' = 'Стоимость try/except по нормальному пути, когда исключение не возникает.'
    'dispatch/raise-catch' = 'Возбуждение и перехват исключения.'
    'json/generate-64' = 'Генерация JSON-подобного текста через TStringBuilder.'
    'json/scan-small-16' = 'Byte-scan маленького RawByteString; это не JSON parser.'
    'json/scan-medium-256' = 'Byte-scan среднего RawByteString; это не JSON parser.'
    'json/scan-large-4096' = 'Byte-scan большого RawByteString; это не JSON parser.'
    'rtl-collections/list-string-read' = 'Индексное чтение UnicodeString из TList<string>.'
    'mm/realloc-grow' = 'Увеличение существующего блока через ReallocMem.'
    'mm/realloc-shrink' = 'Уменьшение существующего блока через ReallocMem.'
    'threads/padded-counters-4' = 'Четыре потока изменяют разнесённые по cache line счётчики.'
    'threads/false-sharing-4' = 'Четыре потока пишут соседние данные и создают false sharing.'
    'threads/shared-read-4' = 'Четыре потока читают общие данные.'
    'threads/thread-start-join-4' = 'Создание и ожидание четырёх потоков.'
    'threads/producer-consumer' = 'Передача элементов между producer и consumer.'
    'layout/indexed-walk' = 'Последовательный индексный обход массива.'
    'layout/pointer-walk' = 'Обход данных через указатели.'
    'loops/manual-copy-8192' = 'Ручное копирование 8192 элементов циклом.'
    'codegen/for-byte-0-255' = 'Полный for-loop со счётчиком Byte от 0 до 255.'
    'codegen/for-runtime-0-255' = 'For-loop до runtime-границы 255.'
    'codegen/for-length-string' = 'For 1 to Length(S) по UnicodeString, сумма кодов символов.'
    'codegen/for-length-array' = 'For 0 to Length(A)-1 по динамическому массиву байт.'
    'codegen/for-downto' = 'For Length(A)-1 downto 0 по динамическому массиву байт.'
    'codegen/abs-int' = 'Abs(Int32) + Abs(Int64) на знакопеременных данных.'
    'codegen/minmax-int' = 'Math.Min/Max для Int32.'
    'codegen/minmax-double' = 'Math.Min/Max для Double на случайных данных.'
    'codegen/minmax-double-special' = 'Min/Max семантика NaN/+0/-0/inf, битовый дайджест.'
    'codegen/mul-lea' = 'X*3 + X*5 + X*9 — lea-формы умножения.'
    'codegen/int32-div-const' = 'Signed Int32 div/mod константами 2/10/7.'
    'codegen/int64-div-const' = 'Signed Int64 div/mod константами 4/10/1000.'
    'codegen/uint32-div-const' = 'UInt32 div/mod константами 10/641/16.'
    'codegen/packed-odd-sizes' = 'Массивы packed record размеров 3/5/7 байт: запись и чтение полей.'
    'codegen/generic-reverse-int' = 'Реверс массива Int64 через generic TArrOps<T>.'
    'codegen/concrete-reverse-int' = 'Реверс массива Int64 рукописной конкретной процедурой.'
    'codegen/generic-reverse-rec' = 'Реверс массива 16-байтовых записей через generic TArrOps<T>.'
    'codegen/concrete-reverse-rec' = 'Реверс массива 16-байтовых записей рукописной процедурой.'
    'codegen/int64-mod-latency' = 'Зависимая цепочка x := (x mod 1000000007)*31 — латентность mod, как в хэшах.'
    'rtl/helper-startswith' = 'TStringHelper.StartsWith, попадание и промах на коротких ключах.'
    'rtl/helper-startswith-nocase' = 'StartsWith с IgnoreCase — регистронезависимый префикс.'
    'rtl/helper-endswith-nocase' = 'EndsWith с IgnoreCase — регистронезависимый суффикс.'
    'rtl/helper-indexof-string' = 'TStringHelper.IndexOf подстроки в 4К-тексте.'
    'rtl/helper-compareto' = 'TStringHelper.CompareTo — ordinal-сравнение коротких ключей.'
    'rtl/helper-split-16' = 'Split CSV-строки из 16 полей одним символом-сепаратором.'
    'rtl/sametext-short' = 'SameText на коротких строках: та же инстанция и разные.'
    'codegen/branch-predictable' = 'Полностью предсказуемое условное ветвление.'
    'managed/managed-exception-cleanup' = 'Финализация managed-значений при выходе через исключение.'
    'managed/interface-copy-call' = 'Копирование interface, refcount и вызов метода.'
    'managed/dynamic-array-assign' = 'Присваивание dynamic array с изменением refcount.'
    'managed/rawbytestring-assign' = 'Присваивание RawByteString с изменением refcount.'
    'rtl/inttostr-int64' = 'Преобразование Int64 в строку через IntToStr.'
    'rtl/strtoint-int64' = 'Преобразование строки в Int64 через StrToInt64.'
    'rtl/utf8-encode-decode-4k' = 'Полный UTF-8 encode/decode для строки около 4 KiB.'
    'rtl/unicode-concat-32' = 'Последовательная конкатенация UnicodeString.'
    'rtl/unicode-pos-4k' = 'Поиск Unicode-подстроки через Pos.'
    'rtl/format-mixed' = 'Format со смешанными строковыми и числовыми аргументами.'
  }
  if ($Exact.ContainsKey($Case)) {
    return $Exact[$Case]
  }

  $Parts = $Case -split '/', 2
  $Group = $Parts[0]
  $Name = $Parts[1]
  switch -Regex ($Case) {
    '^mm/alloc-free-(.+)$' { return "Выделение и освобождение блока размера $($Matches[1])." }
    '^threads/independent-cpu-(\d+)$' { return "Независимая CPU-работа в $($Matches[1]) потоке(ах), без общей памяти." }
    '^threads/parallel-alloc-free-(.+)$' { return "Параллельный alloc/free, профиль $($Matches[1])." }
    '^abi/record(\d+)-(value|var|const)$' { return "Передача record размером $($Matches[1]) байт, форма $($Matches[2])." }
    '^abi/return-record(\d+)$' { return "Возврат record размером $($Matches[1]) байт из функции." }
    '^layout/move-(\d+)$' { return "System.Move блока размером $($Matches[1]) байт." }
    '^layout/fill-(\d+)$' { return "FillChar блока размером $($Matches[1]) байт." }
    '^codegen/call-(.+)$' { return "Compiler codegen вызова: $($Matches[1])." }
    '^codegen/case-(.+)$' { return "Compiler codegen оператора case: $($Matches[1])." }
    '^dictionary/(.+)$' { return "TDictionary: $($Matches[1] -replace '-', ' ')." }
    '^rtl-collections/(.+)$' { return "Операция контейнерного RTL: $($Matches[1] -replace '-', ' ')." }
    '^rtl/(.+)$' { return "Операция RTL: $($Matches[1] -replace '-', ' ')." }
    '^managed/(.+)$' { return "Managed lifetime/operation: $($Matches[1] -replace '-', ' ')." }
    '^threads/(.+)$' { return "Многопоточная операция: $($Matches[1] -replace '-', ' ')." }
    '^workloads/(.+)$' { return "Составная workload: $($Matches[1] -replace '-', ' ')." }
    '^kernels/(.+)$' { return "Прикладной вычислительный kernel: $($Matches[1] -replace '-', ' ')." }
    '^algorithms/(.+)$' { return "Алгоритм на чистом Pascal: $($Matches[1] -replace '-', ' ')." }
    '^numeric/(.+)$' { return "Числовая операция: $($Matches[1] -replace '-', ' ')." }
    '^loops/(.+)$' { return "Цикл/control-flow: $($Matches[1] -replace '-', ' ')." }
    '^layout/(.+)$' { return "Memory layout/access: $($Matches[1] -replace '-', ' ')." }
    '^abi/(.+)$' { return "ABI/call shape: $($Matches[1] -replace '-', ' ')." }
    '^dispatch/(.+)$' { return "Dispatch shape: $($Matches[1] -replace '-', ' ')." }
    '^codegen/(.+)$' { return "Compiler codegen: $($Matches[1] -replace '-', ' ')." }
    '^json/(.+)$' { return "Учебная JSON/byte workload: $($Matches[1] -replace '-', ' ')." }
    '^calibration/(.+)$' { return "ASM calibrator: $($Matches[1] -replace '-', ' ')." }
    default { return "${Group}: $($Name -replace '-', ' ')." }
  }
}

$Rows = @{}
foreach ($Stage in $Stages) {
  if ($Stage.Contains('inherit')) {
    foreach ($Row in $Rows.Values) {
      if ($Row.values.Contains($Stage.inherit)) {
        $Row.values[$Stage.id] = $Row.values[$Stage.inherit]
        if ($Row.unstable -contains $Stage.inherit) {
          $Row.unstable += $Stage.id
        }
      }
    }
  }
  $LoadedCases = @{}
  $SourceRoot = if ($Stage.Contains('tracked')) { $PerformanceRoot } else { $ResultsRoot }
  $SummaryPaths = @($Stage.files | ForEach-Object { Join-Path $SourceRoot $_ })
  $UseSnapshot = @($SummaryPaths | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -ne 0
  if ($UseSnapshot) {
    if (-not $HistorySnapshot.ContainsKey($Stage.id)) {
      throw "Missing Pulse summaries and compact snapshot for stage '$($Stage.id)'"
    }
    $Summaries = @($HistorySnapshot[$Stage.id])
  } else {
    $Summaries = @($SummaryPaths | ForEach-Object {
      # Windows PowerShell 5.1 has no ConvertFrom-Json -AsHashtable
      $SummaryObject = Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json
      $Summary = @{}
      foreach ($Property in $SummaryObject.PSObject.Properties) {
        $Summary[$Property.Name] = [double]$Property.Value.candidate_over_baseline
      }
      $Summary
    })
  }
  foreach ($Summary in $Summaries) {
    foreach ($Case in $Summary.Keys) {
      if (-not $Rows.ContainsKey($Case)) {
        $Rows[$Case] = [ordered]@{
          case = $Case
          group = ($Case -split '/', 2)[0]
          description = Get-CaseDescription $Case
          values = [ordered]@{}
          unstable = @()
        }
      }
      if ($LoadedCases.ContainsKey($Case)) {
        throw "Duplicate case '$Case' in stage '$($Stage.id)'"
      }
      $LoadedCases[$Case] = $true
      $Rows[$Case].values[$Stage.id] = [double]$Summary[$Case]
      $Rows[$Case].unstable = @($Rows[$Case].unstable | Where-Object { $_ -ne $Stage.id })
      if ($Case -in $Stage.unstable) {
        $Rows[$Case].unstable += $Stage.id
      }
    }
  }
  if ($Stage.Contains('values')) {
    foreach ($Case in $Stage.values.Keys) {
      if (-not $Rows.ContainsKey($Case)) {
        throw "Explicit value references unknown case '$Case' in stage '$($Stage.id)'"
      }
      $Rows[$Case].values[$Stage.id] = [double]$Stage.values[$Case]
      $Rows[$Case].unstable = @($Rows[$Case].unstable | Where-Object { $_ -ne $Stage.id })
    }
  }
}

$Data = [ordered]@{
  generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss K')
  ratio = 'Moon Compiler + bundled MM / Delphi 12.2 + FastMM4'
  stages = @($Stages | ForEach-Object {
    [ordered]@{ id = $_.id; label = $_.label; short = $_.short; note = $_.note }
  })
  rows = @($Rows.Values | Sort-Object case)
}
$Json = $Data | ConvertTo-Json -Depth 8 -Compress

$Html = @'
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Moon Compiler Pulse — история производительности</title>
<style>
:root{color-scheme:dark;--bg:#101317;--panel:#171b21;--line:#303741;--text:#e8edf3;--muted:#9ba8b5;--good:#164b32;--bad:#66252b;--same:#343a43;--accent:#72b7ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.42 Segoe UI,Arial,sans-serif}.wrap{max-width:1800px;margin:auto;padding:22px}h1{margin:0 0 6px;font-size:25px}.lead{color:var(--muted);margin-bottom:16px}.cards{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 13px;min-width:155px}.card b{display:block;font-size:20px}.controls{display:grid;grid-template-columns:minmax(260px,2fr) minmax(170px,1fr) minmax(170px,1fr);gap:8px;margin:14px 0}input,select{width:100%;background:#11161c;color:var(--text);border:1px solid var(--line);border-radius:6px;padding:9px}.table-wrap{border:1px solid var(--line);border-radius:8px;overflow:auto;max-height:76vh}table{border-collapse:separate;border-spacing:0;width:100%;min-width:1150px}th,td{padding:7px 9px;border-right:1px solid var(--line);border-bottom:1px solid var(--line);vertical-align:top}th{position:sticky;top:0;background:#222831;z-index:2;text-align:left;cursor:pointer;white-space:nowrap}tr:hover td{filter:brightness(1.13)}td.case{font-family:Consolas,monospace;white-space:nowrap}td.desc{min-width:330px;color:#d1d9e2}.ratio{text-align:right;font-variant-numeric:tabular-nums;font-weight:650;white-space:nowrap}.good{background:var(--good)}.bad{background:var(--bad)}.same{background:var(--same)}.missing{color:#697582;text-align:center}.delta{white-space:nowrap}.unstable::after{content:' †';color:#ffd166}.legend{color:var(--muted);font-size:13px;margin:10px 0}.stage-note{margin:5px 0;color:var(--muted)}a{color:var(--accent)}@media(max-width:800px){.controls{grid-template-columns:1fr}.wrap{padding:12px}}
</style>
</head>
<body><div class="wrap">
<h1>Moon Compiler Pulse — история производительности</h1>
<div class="lead">Все значения: Moon Compiler + bundled MM / Delphi 12.2 + FastMM4. 1.00× — равная скорость; 0.75× — Moon на 25% быстрее; 1.50× — Moon на 50% медленнее. В таблице есть и выигрыши, и проигрыши.</div>
<div class="stage-note"><b>Отдельная ось MM:</b> исходный прогон содержит «наш MM / standard FPC MM», но текущий standard-MM не запускался. Поэтому несравнимые цифры в эту историю не подмешаны.</div>
<div id="stageNotes"></div><div class="cards" id="cards"></div>
<div class="controls"><input id="search" placeholder="Поиск case или смысла"><select id="group"><option value="">Все группы</option></select><select id="status"><option value="">Все результаты</option><option value="win">Moon быстрее (&lt;0.95)</option><option value="same">Паритет (0.95–1.05)</option><option value="loss">Moon медленнее (&gt;1.05)</option><option value="missing">Нет текущего замера</option></select></div>
<div class="legend">Зелёный — выигрыш Moon; серый — паритет ±5%; красный — проигрыш. † — process-drift в этом этапе. Нажмите заголовок для сортировки.</div>
<div class="table-wrap"><table><thead><tr id="head"><th data-key="case">Case</th><th data-key="description">Физический смысл</th></tr></thead><tbody id="body"></tbody></table></div>
</div><script>
const DATA=__DATA__;
const current=DATA.stages[DATA.stages.length-1].id;
let sortKey=current,sortDir=-1;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const cls=v=>v==null?'missing':v<.95?'good':v<=1.05?'same':'bad';
const fmt=v=>v==null?'—':v.toFixed(3)+'×';
const geomean=a=>Math.exp(a.reduce((s,v)=>s+Math.log(v),0)/a.length);
const head=document.getElementById('head');
const bodyEl=document.getElementById('body');
const cardsEl=document.getElementById('cards');
const stageNotesEl=document.getElementById('stageNotes');
const searchInput=document.getElementById('search');
const groupSelect=document.getElementById('group');
const statusSelect=document.getElementById('status');
for(const s of DATA.stages){const th=document.createElement('th');th.dataset.key=s.id;th.textContent=s.label;head.appendChild(th)}
const dh=document.createElement('th');dh.dataset.key='delta';dh.textContent='Сейчас относительно «было»';head.appendChild(dh);
const groups=[...new Set(DATA.rows.map(r=>r.group))].sort();for(const g of groups){groupSelect.insertAdjacentHTML('beforeend',`<option>${esc(g)}</option>`)}
stageNotesEl.innerHTML=DATA.stages.map(s=>`<div class="stage-note"><b>${esc(s.label)}:</b> ${esc(s.note)}</div>`).join('');
function currentStatus(r){const v=r.values[current];return v==null?'missing':v<.95?'win':v<=1.05?'same':'loss'}
function renderCards(){const stable=DATA.rows.filter(r=>r.values[current]!=null&&!r.unstable.includes(current)),vals=stable.map(r=>r.values[current]),drift=DATA.rows.filter(r=>r.values[current]!=null&&r.unstable.includes(current)).length;const win=vals.filter(v=>v<.95).length,same=vals.filter(v=>v>=.95&&v<=1.05).length,loss=vals.filter(v=>v>1.05).length;cardsEl.innerHTML=`<div class="card"><b>${vals.length}</b>устойчивых cases</div><div class="card"><b>${geomean(vals).toFixed(3)}×</b>текущий geomean</div><div class="card"><b>${win}</b>Moon быстрее</div><div class="card"><b>${same}</b>паритет</div><div class="card"><b>${loss}</b>Moon медленнее</div><div class="card"><b>${drift}</b>process-drift</div>`}
function delta(r){const a=r.values[DATA.stages[0].id],b=r.values[current];return a==null||b==null?null:b/a}
function render(){const q=searchInput.value.trim().toLowerCase(),g=groupSelect.value,st=statusSelect.value;let rows=DATA.rows.filter(r=>(!q||(r.case+' '+r.description).toLowerCase().includes(q))&&(!g||r.group===g)&&(!st||currentStatus(r)===st));rows.sort((a,b)=>{let av=sortKey==='delta'?delta(a):sortKey in a?a[sortKey]:a.values[sortKey],bv=sortKey==='delta'?delta(b):sortKey in b?b[sortKey]:b.values[sortKey];if(av==null&&bv==null)return a.case.localeCompare(b.case);if(av==null)return 1;if(bv==null)return-1;return(typeof av==='number'?(av-bv):String(av).localeCompare(String(bv)))*sortDir});bodyEl.innerHTML=rows.map(r=>{let cells=`<td class="case">${esc(r.case)}</td><td class="desc">${esc(r.description)}</td>`;for(const s of DATA.stages){const v=r.values[s.id],u=r.unstable.includes(s.id)?' unstable':'';cells+=`<td class="ratio ${cls(v)}${u}" title="${u?'process-drift; коэффициент требует повтора':''}">${fmt(v)}</td>`}const d=delta(r);let dt=d==null?'—':(d<1?'быстрее на ':'медленнее на ')+Math.abs((d-1)*100).toFixed(1)+'%';cells+=`<td class="delta ${d==null?'missing':d<.95?'good':d<=1.05?'same':'bad'}">${dt}</td>`;return`<tr>${cells}</tr>`}).join('')}
head.addEventListener('click',e=>{const k=e.target.dataset.key;if(!k)return;if(sortKey===k)sortDir*=-1;else{sortKey=k;sortDir=k==='case'||k==='description'?1:-1}render()});for(const el of [searchInput,groupSelect,statusSelect])el.addEventListener('input',render);renderCards();render();
</script></body></html>
'@
$Html = $Html.Replace('__DATA__', $Json)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output), $Html, [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $([IO.Path]::GetFullPath($Output)) with $($Data.rows.Count) cases and $($Stages.Count) stages"
