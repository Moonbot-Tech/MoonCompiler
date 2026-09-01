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
    label = 'Baseline: before RTL optimizations'
    short = 'Baseline'
    note = 'First full Win64 O3 medium run at b02d18d7; the baseline for this optimization series.'
    files = @('pulse-win64-medium-final-2\summary.json')
    unstable = @()
  },
  [ordered]@{
    id = 'rtl_containers'
    label = 'Current: RTL + containers'
    short = 'Current'
    note = 'Current Win64 O3 medium measurements at 5b427091/3e2e5642; product source is identical between these HEADs. Each subsequent material stage is added as a column at the right; existing columns are never rewritten.'
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
    label = 'Current: + loop codegen'
    short = 'Loop codegen'
    note = 'All earlier measurements were carried forward without replacing the run; threads/padded-counters-4 was repeated separately after safely hoisting an address proven invariant from the loop. Win64 O3 medium, 8 compiler processes, 37 samples per process, with four workers pinned to the same CPUs.'
    inherit = 'rtl_containers'
    files = @()
    values = [ordered]@{
      'threads/padded-counters-4' = 0.500379709
    }
    unstable = @()
  },
  [ordered]@{
    id = 'exception_threads'
    label = 'Current: + exception/thread roots'
    short = 'Exception + threads'
    note = 'The post-inline no-throw proof brought dispatch/try-except-no-raise to cycle-for-cycle parity. All thread workloads were repeated with persistent pinned workers; lifecycle cost remains only in the separate thread-start-join case. The padded counter retains a stricter separate 8-process A-B-B-A measurement.'
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
    label = 'Current: + 44 MM classes'
    short = 'MM 44'
    note = 'MoonShard returned to its original 44 small classes up to 2600 bytes, with a 64-cache-line / 4096-byte physical row. The MM group was repeated at Win64 O3 medium; realloc-grow improved from 3.04x to 1.047x. alloc-free-256 is marked as process drift and is not used to judge this stage.'
    inherit = 'exception_threads'
    files = @('mm-44-padding-medium-20260816\summary.json')
    unstable = @('mm/alloc-free-256')
  },
  [ordered]@{
    id = 'gaps_block'
    label = 'Current: + perf-gap queue'
    short = 'Perf-gaps'
    note = 'Full Win64 O3 medium run on perf/remaining-gaps-20260817 (PERF-005..010): Grisu digit core in FloatToDecimal, movless compiler inlining for managed function results, a per-thread console-codepage snapshot, a heap-free format engine, and a WideChar-in-set comparison chain. Stable geometric mean across 343 cases = 0.768; json/generate-64 and list-string-read flipped in Moon''s favour. Six drift pairs from this run are excluded from conclusions.'
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
    label = 'Current: + table tail and stack'
    short = 'Tail block'
    note = 'Delphi-parity default stack (PERF-011) plus six largest remaining tail cases in one pass (PERF-012..016): pointer bump for global arrays with a counter-liveness gate, post-RA widening of byte/word copies, inline record parameters without a self-generated copy, and removal of dead TList range clears. Win64 O3 medium; list-index and call-interface are proven code-placement effects, not code defects (PERF-016).'
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
    label = 'Current: + generic list, record/ABI, managed'
    short = 'Wave 3'
    note = 'Third wave (PERF-017..020): pointer bump for elements wider than the hardware scale, virtual-call-free fast paths in TList.Add/DoRemove, x86-64 atomic intrinsic codegen inlined at the call site (lock xadd/xchg/cmpxchg), and flattened managed assignments (_AddRef/_Release, fpc_dynarray_assign). Win64 O3 medium; no regressions between snapshots.'
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
    label = 'Current: + third-wave completion'
    short = 'Wave 3+'
    note = 'Completion (PERF-021): an exit-free TList.Delete fast path (an early Exit in an inline method inside the caller''s exception region had compiled into a local unwind), inline TObject.ClassInfo, GPR copies of small blocks instead of SSE (store-to-load forwarding on prologue copies of record parameters), and an unchecked 32-bit Variant-arithmetic fast path. open-array-const passed a two-step placement test: the code is bit-identical to the baseline.'
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
    label = 'Current: + Variant and bulk-insert layer'
    short = 'Variant layer'
    note = 'PERF-022: direct Variant-to-integer conversions (four call layers collapsed to a field read, bringing the conversion phase to Delphi parity) and notify-free managed InsertRange (a virtual Notify for each of 2048 elements without a subscriber). dispatch/list-index is the documented placement variation PULSE-DECISION-007; its code is bit-identical.'
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
    label = 'Current: + bulk string finalization'
    short = 'Bulk finalize'
    note = 'PERF-023: fpc_UnicodeStr/AnsiStr_Finalize_Many clears a string array with one call and a hoisted multithread gate instead of one call per element (the Delphi UStrArrayClr counterpart, completing PERF-001). scan-small-16 and object-create-virtual-free were inter-snapshot noise, eliminated by an honest A/B check (Moon/baseline 1.000/0.984).'
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
    label = 'Current: + bump with a live counter'
    short = 'Live-counter bump'
    note = 'PERF-025: pointer bump for global arrays is permitted with a live counter when the loop always reaches its end (no break/exit/goto), matching the Delphi traversal form. Replacing a case chain with a tree/table was disproven by A/B and reverted: on an unpredictable selector, the linear chain is strictly better (the table gave 2.73x). Unstable pairs follow the run''s own drift list.'
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
    label = 'Current: + bulk string incref'
    short = 'Bulk incref'
    note = 'PERF-026: fpc_AnsiStr/UnicodeStr_Incr_Ref_Many increments a string sequence''s refcounts with one call and a hoisted multithread gate (the mirror of PERF-023); fpc_addref_array routes strings through it, benefiting dynamic-array COW copies too. TList.InsertRange without a subscriber uses a block Move plus one addref instead of elementwise assignments. Unstable pairs follow the run''s drift list.'
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
    label = 'Current: + TStringBuilder and Char conversions'
    short = 'StringBuilder'
    note = 'PERF-027: three layers behind the 5.85x TStringBuilder.Append gap: direct field paths instead of property wrappers, folding Char constants after compiler inlining, and the ASCII path in fpc_Char_To_UChar without widestringmanager (an allocation plus WinAPI call per character). append-literals 5.85 -> 1.14 (baseline 0.191), json/generate-64 0.85 -> 0.49. call-virtual/open-array-const are placement effects, proven by bit-identical disassembly at the same addresses; unstable pairs follow the run''s drift list.'
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
    label = 'Current: + builder completion and untyped-const wrong code'
    short = 'Builder tail'
    note = 'PERF-028: changing builder capacity copies only the live range (growth 1.65 -> 1.41); the wrong-code fix makes untyped const actuals always carry ra_addr_taken, otherwise inlining a literal could collapse Move(S[1], ...) to one character (formal_const_address_semantic regression, 144/144 matrix). Unstable pairs follow the run''s drift list.'
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
    label = 'Current: + RTL audit (datetime/hex/conversions)'
    short = 'RTL audit'
    note = 'PERF-029: eight new audit cases (datetime, hex, trim, replace, try-parse) plus fixes for the systemic class of per-character operations through widestringmanager: a Char-table IntToHex (7.04 -> 1.85), ASCII UpCase/LowerCase (datetime-format 2.99 -> 0.57, Moon twice as fast), ASCII string conversion without WinAPI, and date fields without heap strings. Unstable pairs follow the run''s drift list.'
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
    label = 'Current: + RTL audit wave 3 (streams/replace/casing)'
    short = 'RTL audit 3'
    note = 'PERF-030 plus completion of the conversion class: inline ASCII branch in fpc_Char_To_UChar (append-literals 5.85 -> 0.97, StringBuilder ahead of Delphi), StringReplace in one scan (1.77 -> 1.40), TStringStream without a double conversion (1.39 -> 1.03), and ASCII string casing in one loop (uppercase-4k 0.75). Five new wave-3 cases. Unstable pairs follow the run''s drift list.'
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
    label = 'Current: + optimality pass (SWAR, parser, replace)'
    short = 'Optimum pass'
    note = 'Optimality audit of the whole branch: the reference is the algorithmic ceiling, not Delphi. SWAR string-operation cores (four characters per step, 1.4 cycles per character = bandwidth ceiling), a direct integer parser with a cutoff loop (trystrtoint 1.81 -> 1.14, edges 0.88 ahead of Delphi), StringReplace as an inline scan with no heap allocation before the first match (0.999 parity), and two nibbles per IntToHex step. Layer verdicts are in BRANCH_AUDIT.md, section "Optimality pass". Unstable pairs follow the run''s drift list.'
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
    label = 'Current: + unconditional locked refcounts (remove IsMultithread gate)'
    short = 'Locked refcounts'
    note = 'PERF-031: the product is always multithreaded, so the IsMultithread gate was removed from 12 ASM sites and bulk helpers; the ANSI refcount trio became an ASM mirror of the Unicode one (rawbytestring-assign 1.25 -> 1.01). WARNING: the physics of managed measurements changed: single-thread figures before this column cannot be compared to the new ones (the former no-lock path became the production- and Delphi-equivalent locked path). MT cases align with the single-thread ones. Remaining tail: insertrange 1.75 (a locked row of bulk inserts, investigated by the next stage).'
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
    label = 'History: rejected Ref=1 fast path'
    short = 'Rejected'
    note = 'UNSAFE HISTORICAL SNAPSHOT. PERF-032 replaced an atomic increment at Ref=1 with a plain store. Integration audit rejected the candidate: two concurrent readers of the sole shared reference can both write Ref=2 and lose one increment. These figures are retained only as experiment history and do not describe the product HEAD.'
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
    label = 'History: dynamic-array loops over rejected Ref=1'
    short = 'History B'
    note = 'HISTORICAL SNAPSHOT BUILT ON UNSAFE PERF-032. PERF-033 separately added pointer induction for dynamic arrays and codegen cases, but its resulting ratios are not product-HEAD figures. The safe changes were retained; their result is measured again after integration.'
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
    label = 'History: signed mod over rejected Ref=1'
    short = 'History C'
    note = 'HISTORICAL SNAPSHOT BUILT ON UNSAFE PERF-032. PERF-034 separately reduced signed mod by a constant and added semantic/codegen cases. The safe fix was retained, but this column''s ratios are not product-HEAD qualification.'
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
    label = 'History: TStringHelper over rejected Ref=1'
    short = 'Helper history'
    note = 'HISTORICAL SNAPSHOT BUILT ON UNSAFE PERF-032. PERF-035 separately tested TStringHelper facades and corrected trim-string data. The safe tests and implementations were retained, but exact ratios are measured again on the integration HEAD.'
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
    label = 'Current product: safe integration'
    short = 'Product HEAD'
    note = 'Exact Win64 O3 medium at c0139f0e: 390 cases, all semantic oracles MATCH. The unsafe Ref=1 fast path is absent. Three cases are marked process drift and are not used for case-level conclusions; without them Moon/Delphi geometric mean = 0.723, with 203 wins, 120 parity cases, and 64 losses.'
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
    label = 'Final: current main 81daffaa'
    short = 'Main 2026-08-23'
    note = 'Exact Win64 O3 medium at 81daffaa: 390/390 semantic oracles MATCH. Nine process-drift cases are marked and excluded from the aggregate; without them Moon/Delphi geometric mean = 0.7318, with 195 wins, 118 parity cases, and 68 losses. Allocator group: bundled MM / default FPC MM = 0.6179.'
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
    label = 'Current: + TDictionary size matrix'
    short = 'Dictionary matrix'
    note = 'The compiler binary is unchanged from the preceding column. Added 24 medium cases: UInt64/UnicodeString keys and values, 100/10,000 elements, grow/reserve/lookup/churn. 24/24 oracles MATCH; one Delphi process pair is marked drift. Across 23 stable new cases, Moon/Delphi geometric mean = 0.9569.'
    inherit = 'integration_final_20260823'
    tracked = $true
    files = @('evidence\dictionary-matrix-20260823\summary.json')
    unstable = @(
      'dictionary/u64-u64-build-grow-100'
    )
  },
  [ordered]@{
    id = 'dictionary_lookup_20260823'
    label = 'Current: managed removal + numeric lookup'
    short = 'Dictionary lookup'
    note = 'PERF-039..041: DoRemove without a temporary managed TPair; TryGetValue aligned with the Delphi var contract; linear probing traverses by pointer and the wrapper inlines. MM and load factor are unchanged. Exact-source Win64 O3 medium: 30/30 oracles MATCH; UInt64->UInt64 mixed 1.056 -> 0.963, UInt64->String 1.160 -> 1.007.'
    inherit = 'dictionary_matrix_20260823'
    files = @('evidence\dictionary-lookup-20260823\summary.json')
    tracked = $true
    unstable = @()
  },
  [ordered]@{
    id = 'system_move_20260824'
    label = 'Current: + full x86-64 System.Move'
    short = 'System.Move'
    note = 'PERF-042: 297-case Win64 O3 medium: fixed sizes, alignment/page offsets, same-pointer, overlap, and streaming up to 64 MiB. 297/297 oracles MATCH; Moon/Delphi geometric mean 0.936, with 124 wins, 144 parity cases, and 29 losses. AVX temporal/NT policy is tied to half of the largest deterministic cache; the old mORMot MoveFast was not imported.'
    inherit = 'dictionary_lookup_20260823'
    files = @('evidence\system-move-20260824\summary.json')
    tracked = $true
    unstable = @()
  },
  [ordered]@{
    id = 'release_final_20260830'
    label = 'Final Pulse: compiler + RTL + MM'
    short = 'Release 2026-08-30'
    note = 'Exact Win64 O3 medium at 64067c99: 757/757 semantic oracles MATCH. Without 13 unstable process cases, Moon/Delphi geometric mean 0.8310; Heartbeat 0.8185, with 18 wins, 2 parity cases, and 0 losses; bundled MM/default FPC MM in the allocator group 0.6069. The full Move matrix is included in this final snapshot and continues as a separate qualification gate.'
    tracked = $true
    files = @('evidence\release-final-20260830\summary.json')
    unstable = @(
      'calibration/asm-memory-write-64m',
      'codegen/concrete-reverse-rec',
      'json/builder-growth-64k',
      'loops/histogram-random',
      'mm/alloc-free-1m',
      'mm/fragmented-mixed',
      'workloads/stream-add',
      'workloads/stream-scale',
      'move/hot-a0-a0-n8388608',
      'threads/cross-thread-free-4',
      'threads/parallel-alloc-free-4',
      'threads/parallel-alloc-free-96-4',
      'threads/parallel-alloc-free-96-8'
    )
  }
)

function Get-CaseDescription([string]$Case) {
  $Exact = @{
    'local-pressure/empty' = 'Call to an empty procedure.'
    'local-pressure/unused-plain-100' = 'Procedure declares 100 unused unmanaged locals.'
    'local-pressure/unused-strings-100' = 'Procedure declares 100 unused string locals.'
    'local-pressure/unused-buffers-100' = 'Procedure declares 100 unused dynamic arrays.'
    'local-pressure/unused-mixed-300' = 'Procedure declares 100 strings, 100 dynamic arrays, and 100 plain locals, but does not use them.'
    'local-pressure/used-plain-100' = 'Procedure actively uses 100 unmanaged locals.'
    'local-pressure/used-strings-100' = 'Procedure actively uses 100 string locals.'
    'local-pressure/used-buffers-100' = 'Procedure actively uses 100 dynamic arrays.'
    'local-pressure/used-mixed-300' = 'Main local-pressure case: 100 strings, 100 dynamic arrays, and 100 plain locals, all actively used.'
    'dispatch/try-except-no-raise' = 'Cost of try/except on the normal path when no exception is raised.'
    'dispatch/raise-catch' = 'Raising and catching an exception.'
    'json/generate-64' = 'Generates JSON-like text through TStringBuilder.'
    'json/scan-small-16' = 'Byte-scans a short RawByteString; this is not a JSON parser.'
    'json/scan-medium-256' = 'Byte-scans a medium RawByteString; this is not a JSON parser.'
    'json/scan-large-4096' = 'Byte-scans a large RawByteString; this is not a JSON parser.'
    'rtl-collections/list-string-read' = 'Indexed UnicodeString read from TList<string>.'
    'mm/realloc-grow' = 'Grows an existing block through ReallocMem.'
    'mm/realloc-shrink' = 'Shrinks an existing block through ReallocMem.'
    'threads/padded-counters-4' = 'Four threads update counters separated by cache lines.'
    'threads/false-sharing-4' = 'Four threads write adjacent data and create false sharing.'
    'threads/shared-read-4' = 'Four threads read shared data.'
    'threads/thread-start-join-4' = 'Starts and joins four threads.'
    'threads/producer-consumer' = 'Passes items between a producer and a consumer.'
    'layout/indexed-walk' = 'Sequential indexed array traversal.'
    'layout/pointer-walk' = 'Pointer-based data traversal.'
    'loops/manual-copy-8192' = 'Manually copies 8192 elements in a loop.'
    'codegen/for-byte-0-255' = 'Complete for loop with a Byte counter from 0 through 255.'
    'codegen/for-runtime-0-255' = 'For loop with a runtime upper bound of 255.'
    'codegen/for-length-string' = 'For 1 to Length(S) over a UnicodeString, summing character code units.'
    'codegen/for-length-array' = 'For 0 to Length(A)-1 over a dynamic byte array.'
    'codegen/for-downto' = 'For Length(A)-1 downto 0 over a dynamic byte array.'
    'codegen/abs-int' = 'Abs(Int32) + Abs(Int64) over signed varying data.'
    'codegen/minmax-int' = 'Math.Min/Max for Int32.'
    'codegen/minmax-double' = 'Math.Min/Max for Double over random data.'
    'codegen/minmax-double-special' = 'Min/Max semantics for NaN/+0/-0/inf, with a bitwise digest.'
    'codegen/mul-lea' = 'X*3 + X*5 + X*9: LEA multiplication forms.'
    'codegen/int32-div-const' = 'Signed Int32 division/modulo by constants 2/10/7.'
    'codegen/int64-div-const' = 'Signed Int64 division/modulo by constants 4/10/1000.'
    'codegen/uint32-div-const' = 'UInt32 division/modulo by constants 10/641/16.'
    'codegen/packed-odd-sizes' = 'Arrays of 3/5/7-byte packed records: field writes and reads.'
    'codegen/generic-reverse-int' = 'Reverses an Int64 array through generic TArrOps<T>.'
    'codegen/concrete-reverse-int' = 'Reverses an Int64 array through a handwritten concrete procedure.'
    'codegen/generic-reverse-rec' = 'Reverses an array of 16-byte records through generic TArrOps<T>.'
    'codegen/concrete-reverse-rec' = 'Reverses an array of 16-byte records through a handwritten concrete procedure.'
    'codegen/int64-mod-latency' = 'Dependent chain x := (x mod 1000000007)*31: modulo latency, as in hashes.'
    'rtl/helper-startswith' = 'TStringHelper.StartsWith, hit and miss on short keys.'
    'rtl/helper-startswith-nocase' = 'StartsWith with IgnoreCase: case-insensitive prefix.'
    'rtl/helper-endswith-nocase' = 'EndsWith with IgnoreCase: case-insensitive suffix.'
    'rtl/helper-indexof-string' = 'TStringHelper.IndexOf a substring in 4 KiB text.'
    'rtl/helper-compareto' = 'TStringHelper.CompareTo: ordinal comparison of short keys.'
    'rtl/helper-split-16' = 'Splits a 16-field CSV string with a one-character delimiter.'
    'rtl/sametext-short' = 'SameText on short strings: same instance and different instances.'
    'codegen/branch-predictable' = 'Fully predictable conditional branch.'
    'managed/managed-exception-cleanup' = 'Finalizes managed values on exception exit.'
    'managed/interface-copy-call' = 'Copies an interface, updates refcount, and calls a method.'
    'managed/dynamic-array-assign' = 'Dynamic-array assignment with a refcount update.'
    'managed/rawbytestring-assign' = 'RawByteString assignment with a refcount update.'
    'rtl/inttostr-int64' = 'Converts Int64 to a string through IntToStr.'
    'rtl/strtoint-int64' = 'Converts a string to Int64 through StrToInt64.'
    'rtl/utf8-encode-decode-4k' = 'Full UTF-8 encode/decode for a roughly 4 KiB string.'
    'rtl/unicode-concat-32' = 'Sequential UnicodeString concatenation.'
    'rtl/unicode-pos-4k' = 'Unicode substring search through Pos.'
    'rtl/format-mixed' = 'Format with mixed string and numeric arguments.'
  }
  if ($Exact.ContainsKey($Case)) {
    return $Exact[$Case]
  }

  $Parts = $Case -split '/', 2
  $Group = $Parts[0]
  $Name = $Parts[1]
  switch -Regex ($Case) {
    '^mm/alloc-free-(.+)$' { return "Allocates and releases a $($Matches[1])-byte block." }
    '^threads/independent-cpu-(\d+)$' { return "Independent CPU work in $($Matches[1]) thread(s), with no shared memory." }
    '^threads/parallel-alloc-free-(.+)$' { return "Parallel alloc/free, $($Matches[1]) profile." }
    '^abi/record(\d+)-(value|var|const)$' { return "Passes a $($Matches[1])-byte record, $($Matches[2]) form." }
    '^abi/return-record(\d+)$' { return "Returns a $($Matches[1])-byte record from a function." }
    '^layout/move-(\d+)$' { return "System.Move of a $($Matches[1])-byte block." }
    '^move/hot-a(\d+)-a(\d+)-n(\d+)$' { return "System.Move: hot copy of $($Matches[3]) bytes, source/destination offsets $($Matches[1])/$($Matches[2])." }
    '^move/same-a(\d+)-n(\d+)$' { return "System.Move: source=destination, $($Matches[2]) bytes, offset $($Matches[1])." }
    '^move/overlap-(forward|backward)-d(\d+)-n(\d+)$' { return "System.Move: $($Matches[1]) overlap, distance $($Matches[2]), size $($Matches[3])." }
    '^move/stream-a(\d+)-a(\d+)-n(\d+)$' { return "System.Move: streaming copy of $($Matches[3]) bytes, source/destination offsets $($Matches[1])/$($Matches[2])." }
    '^layout/fill-(\d+)$' { return "FillChar of a $($Matches[1])-byte block." }
    '^codegen/call-(.+)$' { return "Compiler call codegen: $($Matches[1])." }
    '^codegen/case-(.+)$' { return "Compiler case-statement codegen: $($Matches[1])." }
    '^dictionary/(.+)$' { return "TDictionary: $($Matches[1] -replace '-', ' ')." }
    '^rtl-collections/(.+)$' { return "Collection RTL operation: $($Matches[1] -replace '-', ' ')." }
    '^rtl/(.+)$' { return "RTL operation: $($Matches[1] -replace '-', ' ')." }
    '^managed/(.+)$' { return "Managed lifetime/operation: $($Matches[1] -replace '-', ' ')." }
    '^threads/(.+)$' { return "Multithreaded operation: $($Matches[1] -replace '-', ' ')." }
    '^workloads/(.+)$' { return "Composite workload: $($Matches[1] -replace '-', ' ')." }
    '^kernels/(.+)$' { return "Application computational kernel: $($Matches[1] -replace '-', ' ')." }
    '^algorithms/(.+)$' { return "Pure Pascal algorithm: $($Matches[1] -replace '-', ' ')." }
    '^numeric/(.+)$' { return "Numeric operation: $($Matches[1] -replace '-', ' ')." }
    '^loops/(.+)$' { return "Loop/control flow: $($Matches[1] -replace '-', ' ')." }
    '^layout/(.+)$' { return "Memory layout/access: $($Matches[1] -replace '-', ' ')." }
    '^abi/(.+)$' { return "ABI/call shape: $($Matches[1] -replace '-', ' ')." }
    '^dispatch/(.+)$' { return "Dispatch shape: $($Matches[1] -replace '-', ' ')." }
    '^codegen/(.+)$' { return "Compiler codegen: $($Matches[1] -replace '-', ' ')." }
    '^json/(.+)$' { return "Synthetic JSON/byte workload: $($Matches[1] -replace '-', ' ')." }
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
  ratio = 'MoonCompiler + bundled MM / Delphi 12.2 + FastMM4'
  stages = @($Stages | ForEach-Object {
    [ordered]@{ id = $_.id; label = $_.label; short = $_.short; note = $_.note }
  })
  rows = @($Rows.Values | Sort-Object case)
}
$Json = $Data | ConvertTo-Json -Depth 8 -Compress

$Html = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MoonCompiler Pulse &mdash; performance history</title>
<style>
:root{color-scheme:dark;--bg:#101317;--panel:#171b21;--line:#303741;--text:#e8edf3;--muted:#9ba8b5;--good:#164b32;--bad:#66252b;--same:#343a43;--accent:#72b7ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.42 Segoe UI,Arial,sans-serif}.wrap{max-width:1800px;margin:auto;padding:22px}h1{margin:0 0 6px;font-size:25px}.lead{color:var(--muted);margin-bottom:16px}.cards{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0}.card{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:10px 13px;min-width:155px}.card b{display:block;font-size:20px}.controls{display:grid;grid-template-columns:minmax(260px,2fr) minmax(170px,1fr) minmax(170px,1fr);gap:8px;margin:14px 0}input,select{width:100%;background:#11161c;color:var(--text);border:1px solid var(--line);border-radius:6px;padding:9px}.table-wrap{border:1px solid var(--line);border-radius:8px;overflow:auto;max-height:76vh}table{border-collapse:separate;border-spacing:0;width:100%;min-width:1150px}th,td{padding:7px 9px;border-right:1px solid var(--line);border-bottom:1px solid var(--line);vertical-align:top}th{position:sticky;top:0;background:#222831;z-index:2;text-align:left;cursor:pointer;white-space:nowrap}tr:hover td{filter:brightness(1.13)}td.case{font-family:Consolas,monospace;white-space:nowrap}td.desc{min-width:330px;color:#d1d9e2}.ratio{text-align:right;font-variant-numeric:tabular-nums;font-weight:650;white-space:nowrap}.good{background:var(--good)}.bad{background:var(--bad)}.same{background:var(--same)}.missing{color:#697582;text-align:center}.delta{white-space:nowrap}.unstable::after{content:' \2020';color:#ffd166}.legend{color:var(--muted);font-size:13px;margin:10px 0}.stage-note{margin:5px 0;color:var(--muted)}a{color:var(--accent)}@media(max-width:800px){.controls{grid-template-columns:1fr}.wrap{padding:12px}}
</style>
</head>
<body><div class="wrap">
<h1>MoonCompiler Pulse &mdash; performance history</h1>
<div class="lead">All values: MoonCompiler + bundled MM / Delphi 12.2 + FastMM4. 1.00&times; means equal speed; 0.75&times; means Moon is 25% faster; 1.50&times; means Moon is 50% slower. The table includes both wins and losses.</div>
<div class="stage-note"><b>Separate MM axis:</b> the original run contains &ldquo;our MM / standard FPC MM&rdquo;, but the current standard MM was not run. Incomparable figures are therefore not mixed into this history.</div>
<div id="stageNotes"></div><div class="cards" id="cards"></div>
<div class="controls"><input id="search" placeholder="Search case or description"><select id="group"><option value="">All groups</option></select><select id="status"><option value="">All results</option><option value="win">Moon faster (&lt;0.95)</option><option value="same">Parity (0.95&ndash;1.05)</option><option value="loss">Moon slower (&gt;1.05)</option><option value="missing">No current measurement</option></select></div>
<div class="legend">Green: Moon win; grey: parity &plusmn;5%; red: loss. &dagger;: process drift in this stage. Click a header to sort.</div>
<div class="table-wrap"><table><thead><tr id="head"><th data-key="case">Case</th><th data-key="description">What is measured</th></tr></thead><tbody id="body"></tbody></table></div>
</div><script>
const DATA=__DATA__;
const current=DATA.stages[DATA.stages.length-1].id;
let sortKey=current,sortDir=-1;
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const cls=v=>v==null?'missing':v<.95?'good':v<=1.05?'same':'bad';
const fmt=v=>v==null?String.fromCharCode(0x2014):v.toFixed(3)+String.fromCharCode(0x00d7);
const geomean=a=>Math.exp(a.reduce((s,v)=>s+Math.log(v),0)/a.length);
const head=document.getElementById('head');
const bodyEl=document.getElementById('body');
const cardsEl=document.getElementById('cards');
const stageNotesEl=document.getElementById('stageNotes');
const searchInput=document.getElementById('search');
const groupSelect=document.getElementById('group');
const statusSelect=document.getElementById('status');
for(const s of DATA.stages){const th=document.createElement('th');th.dataset.key=s.id;th.textContent=s.label;head.appendChild(th)}
const dh=document.createElement('th');dh.dataset.key='delta';dh.textContent='Current relative to baseline';head.appendChild(dh);
const groups=[...new Set(DATA.rows.map(r=>r.group))].sort();for(const g of groups){groupSelect.insertAdjacentHTML('beforeend',`<option>${esc(g)}</option>`)}
stageNotesEl.innerHTML=DATA.stages.map(s=>`<div class="stage-note"><b>${esc(s.label)}:</b> ${esc(s.note)}</div>`).join('');
function currentStatus(r){const v=r.values[current];return v==null?'missing':v<.95?'win':v<=1.05?'same':'loss'}
function renderCards(){const stable=DATA.rows.filter(r=>r.values[current]!=null&&!r.unstable.includes(current)),vals=stable.map(r=>r.values[current]),drift=DATA.rows.filter(r=>r.values[current]!=null&&r.unstable.includes(current)).length;const win=vals.filter(v=>v<.95).length,same=vals.filter(v=>v>=.95&&v<=1.05).length,loss=vals.filter(v=>v>1.05).length;cardsEl.innerHTML=`<div class="card"><b>${vals.length}</b>stable cases</div><div class="card"><b>${geomean(vals).toFixed(3)}${String.fromCharCode(0x00d7)}</b>current geometric mean</div><div class="card"><b>${win}</b>Moon faster</div><div class="card"><b>${same}</b>parity</div><div class="card"><b>${loss}</b>Moon slower</div><div class="card"><b>${drift}</b>process drift</div>`}
function delta(r){const a=r.values[DATA.stages[0].id],b=r.values[current];return a==null||b==null?null:b/a}
function render(){const q=searchInput.value.trim().toLowerCase(),g=groupSelect.value,st=statusSelect.value;let rows=DATA.rows.filter(r=>(!q||(r.case+' '+r.description).toLowerCase().includes(q))&&(!g||r.group===g)&&(!st||currentStatus(r)===st));rows.sort((a,b)=>{let av=sortKey==='delta'?delta(a):sortKey in a?a[sortKey]:a.values[sortKey],bv=sortKey==='delta'?delta(b):sortKey in b?b[sortKey]:b.values[sortKey];if(av==null&&bv==null)return a.case.localeCompare(b.case);if(av==null)return 1;if(bv==null)return-1;return(typeof av==='number'?(av-bv):String(av).localeCompare(String(bv)))*sortDir});bodyEl.innerHTML=rows.map(r=>{let cells=`<td class="case">${esc(r.case)}</td><td class="desc">${esc(r.description)}</td>`;for(const s of DATA.stages){const v=r.values[s.id],u=r.unstable.includes(s.id)?' unstable':'';cells+=`<td class="ratio ${cls(v)}${u}" title="${u?'process drift; ratio requires a rerun':''}">${fmt(v)}</td>`}const d=delta(r);let dt=d==null?String.fromCharCode(0x2014):(d<1?'faster by ':'slower by ')+Math.abs((d-1)*100).toFixed(1)+'%';cells+=`<td class="delta ${d==null?'missing':d<.95?'good':d<=1.05?'same':'bad'}">${dt}</td>`;return`<tr>${cells}</tr>`}).join('')}
head.addEventListener('click',e=>{const k=e.target.dataset.key;if(!k)return;if(sortKey===k)sortDir*=-1;else{sortKey=k;sortDir=k==='case'||k==='description'?1:-1}render()});for(const el of [searchInput,groupSelect,statusSelect])el.addEventListener('input',render);renderCards();render();
</script></body></html>
'@
$Html = $Html.Replace('__DATA__', $Json)
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output), $Html, [Text.UTF8Encoding]::new($false))
Write-Host "Wrote $([IO.Path]::GetFullPath($Output)) with $($Data.rows.Count) cases and $($Stages.Count) stages"
