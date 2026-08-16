param(
  [string]$Output = (Join-Path $PSScriptRoot '..\PULSE_HISTORY.html')
)

$ErrorActionPreference = 'Stop'
$PerformanceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$ResultsRoot = Join-Path $PerformanceRoot 'results\pulse'

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
  foreach ($RelativeFile in $Stage.files) {
    $SummaryPath = Join-Path $ResultsRoot $RelativeFile
    if (-not (Test-Path -LiteralPath $SummaryPath)) {
      throw "Missing Pulse summary: $SummaryPath"
    }
    $Summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json -AsHashtable
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
      $Rows[$Case].values[$Stage.id] = [double]$Summary[$Case].candidate_over_baseline
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
function renderCards(){const vals=DATA.rows.map(r=>r.values[current]).filter(v=>v!=null);const win=vals.filter(v=>v<.95).length,same=vals.filter(v=>v>=.95&&v<=1.05).length,loss=vals.filter(v=>v>1.05).length;cardsEl.innerHTML=`<div class="card"><b>${vals.length}</b>текущих cases</div><div class="card"><b>${geomean(vals).toFixed(3)}×</b>текущий geomean</div><div class="card"><b>${win}</b>Moon быстрее</div><div class="card"><b>${same}</b>паритет</div><div class="card"><b>${loss}</b>Moon медленнее</div>`}
function delta(r){const a=r.values[DATA.stages[0].id],b=r.values[current];return a==null||b==null?null:b/a}
function render(){const q=searchInput.value.trim().toLowerCase(),g=groupSelect.value,st=statusSelect.value;let rows=DATA.rows.filter(r=>(!q||(r.case+' '+r.description).toLowerCase().includes(q))&&(!g||r.group===g)&&(!st||currentStatus(r)===st));rows.sort((a,b)=>{let av=sortKey==='delta'?delta(a):sortKey in a?a[sortKey]:a.values[sortKey],bv=sortKey==='delta'?delta(b):sortKey in b?b[sortKey]:b.values[sortKey];if(av==null&&bv==null)return a.case.localeCompare(b.case);if(av==null)return 1;if(bv==null)return-1;return(typeof av==='number'?(av-bv):String(av).localeCompare(String(bv)))*sortDir});bodyEl.innerHTML=rows.map(r=>{let cells=`<td class="case">${esc(r.case)}</td><td class="desc">${esc(r.description)}</td>`;for(const s of DATA.stages){const v=r.values[s.id],u=r.unstable.includes(s.id)?' unstable':'';cells+=`<td class="ratio ${cls(v)}${u}" title="${u?'process-drift; коэффициент требует повтора':''}">${fmt(v)}</td>`}const d=delta(r);let dt=d==null?'—':(d<1?'быстрее на ':'медленнее на ')+Math.abs((d-1)*100).toFixed(1)+'%';cells+=`<td class="delta ${d==null?'missing':d<.95?'good':d<=1.05?'same':'bad'}">${dt}</td>`;return`<tr>${cells}</tr>`}).join('')}
head.addEventListener('click',e=>{const k=e.target.dataset.key;if(!k)return;if(sortKey===k)sortDir*=-1;else{sortKey=k;sortDir=k==='case'||k==='description'?1:-1}render()});for(const el of [searchInput,groupSelect,statusSelect])el.addEventListener('input',render);renderCards();render();
</script></body></html>
'@
$Html = $Html.Replace('__DATA__', $Json)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output), $Html, [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $([IO.Path]::GetFullPath($Output)) with $($Data.rows.Count) cases and $($Stages.Count) stages"
