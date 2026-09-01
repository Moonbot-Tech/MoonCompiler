# MoonCompiler Test System

The tests answer three distinct questions:

1. Is the exact defect fixed?
2. Have neighbouring language and runtime forms remained unchanged?
3. Does the result withstand a complex application, mORMot, and our memory manager?

The runner operates on the current files. A compiler, RTL, MM, or test change
does not require a commit SHA or fingerprint update.

An automatic run ID contains a UTC timestamp, stage, and random filesystem
suffix. Concurrent `fixtures`, `mega`, `mormot`, and other runner processes
therefore atomically receive separate directories. An explicit `--run-id`
remains strict and is rejected if its directory already exists.

## Product smoke

`qualification/suite/tests/smoke/build_smoke.dpr` is built from the repository
root through `build`/`build.ps1` in `debug` and `release`. It proves that the
profile applies to a real `.dpr`, that the compiler places our MM first, that
the exact source is pinned, and that the compile-time profile is in effect.
Success is `MOONBOT_BUILD_OK` in both modes.

`qualification/build-driver/project_profile_gate.py` checks not an individual
compiler switch but the complete public application-build command. It creates a
logical source view, an external Git dependency, and an alias, then builds and
runs a Unicode application in Debug/Release and Debug+diagnostic-MM. The latter
mode must pass its define into the application and use a separate unit cache
without changing normal Debug. A dirty dependency, lost logical path, missing
`System.*` aliases, or an incorrect default `String` makes the gate fail. On
Linux it also proves that a dependency root inside `.moonbot` is not lost to the
service-descendant filter and that the automatically inserted runtime prefix is
ordered `MM, cthreads, cwstring, fpmonitor`.

## Regression corpus

`fixtures/` and `tests/test/cg/` contain minimal reproductions of known defects
and negative controls. For every test, its oracle specifies the required
behaviour rather than merely repeating the current compiler's answer.

```bash
python3 runner.py fixtures \
  --compiler moonbot-compiler-beta --option O2 --option O3
```

Five deliberately deferred compile-time forms remain named expected defects:
FPC #41541, #41594, #41598, #41614, and #41679. Any other red result is a
regression.

The test may be extended freely. If the expected semantics change, the new
oracle must first be justified; a new compiler answer cannot be accepted
automatically.

`tests/corpus-extra` contains two independent neighbouring controls from the
upstream line: `tgeneric131.pp` and the Delphi-mode variant of `tb0728.pp`.
`delphi_tb0728` must pass at O2/O3. For `tgeneric131`, both platforms retain
the exact ObjFPC deviation `Interface type Intf has no valid GUID`. It is not
part of the product Delphi contract and is not represented as fixed; the runner
rejects both an unexpected success and any other diagnostic.

### Issue-tracker discovery corpus

`fixtures/tracker` is a separate discovery layer built from Quality Portal,
Stack Overflow, and internal MoonBot forms. It does not treat an external report
as ground truth: every case has its own oracle and a provenance record in
[`fixtures/tracker/PROVENANCE.md`](../fixtures/tracker/PROVENANCE.md).

```bash
python3 scripts/run_issue_tracker_corpus.py \
  --fpc ../../.moonbot/toolchain/bin/fpc \
  --fpc-config ../../.moonbot/toolchain/etc/fpc.cfg \
  --output ../../.qualification/tracker --jobs 8 --enforce
```

With `--enforce`, 67 programs must pass; `QP-03` and `QP-24` must produce their
exact expected compile-time rejections; and `QP-32`, `QP-53`, and `MB-06` must
produce the exact diagnostics of accepted Known Issues. Any other deviation
makes the runner fail. Removed `QP-39` and `MB-01` remain listed in provenance:
their oracles were disproved, so an allow-list does not mask them and they are
not presented as compiler defects.

## Original mega

`tests/mega/mega_test.pas` combines many provable code forms in one
multithreaded program: strings, arrays, closures, generics, records,
arithmetic, exceptions, and managed-type lifetime. Random data is reproducible
by seed, and the result is checked by its own invariants.

```bash
python3 runner.py mega \
  --compiler moonbot-compiler-beta --option O2 --option O3
```

Success for the accepted set is 12/12 with no new defects.

## Omni and Integrated Mega

These programs intentionally intertwine forms more heavily than minimal
fixtures and are closer to a large application. They run at O2/O3 with six
fixed seeds.

Omni checks code forms, but it does not prove completeness of the public Delphi
RTL API. A missing declaration creates no AST and is therefore invisible to the
runtime/optimizer corpus until a test explicitly calls that overload. This is
how `TThread.Create` was missed: every earlier thread family used only
`Create(True/False)`.

Every public RTL API discrepancy requires three layers: the exact form with a
Delphi oracle, neighbouring overload/default-argument forms, and real use in
Omni/integrated. The separate
[`rtl-api/rtl_api_surface.dpr`](../tests/rtl-api/rtl_api_surface.dpr) checks a
selected Delphi 12.2 API surface of supported common units: constructors,
overloads, class/static methods, properties, and default arguments. It was
selected from the actual MoonBot and Arbitrage surface; its criteria and
deliberate exclusions are recorded in
[`rtl-api/SURFACE.md`](../tests/rtl-api/SURFACE.md). The size of Omni, Devil,
or the product corpus cannot be presented as this proof.

The focused `RTL-test/run.py` additionally locks down the runtime surface that
is actually used: `task_wait_semantic`, `thread_pool_lifecycle_semantic`,
`ioutils_api_semantic`, `rtl_api_product_semantic`,
`rtti_invoke_product_semantic`, and `url_encoding_utf8_codepage_semantic`.
They run separately in Debug/O2/O3 and require an exact PASS marker; successful
package compilation does not replace these runtime oracles.

The gate builds the same source with the real product build driver in Debug and
Release, simultaneously checking namespace aliases, Unicode `String`, the
bundled MM, and the automatically inserted Linux prefix `MM, cthreads, cwstring,
fpmonitor` (`MM, fpwinmonitor` on Win64):

```bash
scripts/run_rtl_api_surface_gate.sh rtl-api-linux-001
```

```powershell
.\scripts\run_rtl_api_surface_gate.ps1 rtl-api-win64-001
```

```bash
scripts/run_forms_gate.sh \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg forms-001
```

On Win64, `scripts/run_forms_gate.ps1` runs the same exact-set contract and a
separate target-specific terminal oracle: both programs, O2/O3, and all six
seeds. This is not a reduced smoke test, but a symmetric run of the full
expanded Omni/integrated mega.

Every individual program × mode × seed must end with the exact line from
`tests/mega/forms_expected.tsv` on Linux or
`tests/mega/forms_expected_win64.tsv` on Win64. The gate checks the allow-list,
the number of executed checks, and the digest of every section. Errors from
different runs are never aggregated: an aborted, section-skipping, or incomplete
run cannot pass on the strength of the rest.

Both `forms_expected*.tsv` tables are verified oracles, not snapshots of the
candidate compiler's answer. They must not be regenerated with the binary under
test without independently comparing the reason for every change against a
stable reference/Delphi oracle.

The generated breadth layer has 15,236 checks. Its new cross-axis family has
1,280 forms: the full product of 20 value sources, 8 ordinal operators, and 8
ways to consume the result. Forms are distributed over direct, runtime-if,
single-loop, try/finally, repeat, nested function, with-record, and case branch;
the manifest checks full pairwise coverage of the fourth axis. The compiler
therefore sees not merely `UInt64 + literal`, but that result as an overload
argument, assignment, case selector, loop bound, and array index in different
AST contexts.

The MoonBot-derived `CreateAnonymousThread → TThread.Queue → Self` runs for
real: the gate waits for the worker, then the main thread explicitly drains the
queue and checks the object field change. A compile-only copy of this form is
not sufficient.

On Linux x86-64, `scripts/run_linux_psabieh_gate.sh` separately requires table-
driven unwinding without a compiler define or application switch. It runs
O-/O1/O2/O3 normal/exception/nested/managed/thread paths and checks normal
diagnostic abort, `.gcc_except_table`, the personality symbol, and the absence
of legacy frame calls. The product ABI therefore cannot silently revert to the
setjmp mechanism.

Integrated mega retains exactly nine known deviations:

- five NaN/not forms;
- `-0.0 + +0.0`;
- two anonymous variant-record layout forms;
- `Currency` with an untyped real literal.

Omni contains the same nine. The former four extended-RTTI forms for explicit
public methods now pass and are separately confirmed by a real call through
`CodeAddress`; its exact allow-list also contains nine names.

`HAS_INLINEVAR` enables the inline-var form required by our compiler.
`TRY_OLEVARIANT_UTF8`, `TRY_VARIANT_RESERVED_MEMBER`,
`TRY_VARIANT_DISTINCT_ORDINAL`, and `TRY_DELPHI_EQUALITY_COMPARER` are no
longer optional experiments: the release gate always passes them and therefore
cannot silently disable accepted forms. Other in-source `TRY_*` sections remain
exploratory and do not enter the product oracle until their semantics have been
proven separately.

The meaning of the deviations is documented in the compiler repository's
`KNOWN_ISSUES.md`.

## Additional Devil Axes

An ordinary differential case asks the compiler “is the number the same?”
These layers also vary the profile, module graph, application architecture, and
shape of the same production calculation.

**Every optimization in isolation** — `run_resident_switch_matrix.py`. Driver
profiles are four points, with roughly ten transformations enabled together
between them. When something breaks, the cause has to be found manually, and a
defect confined to one transformation may not be exercised by a merged profile.
The matrix builds Resident in 38 configurations — `-O1` plus each of 19 switches
individually, and `-O3` with each one removed individually — and requires the
same root result. There is one exception: `FASTMATH` deliberately permits
rewriting floating-point arithmetic, so only compilation is checked for it.

**Module topology** — `run_topology_gate.py`. A compiler compiles a graph of
files rather than a single file, and legal interface cycles are common in live
code. The gate exhaustively spans the space: 7 topologies × 10 symbol kinds × 3
ways to move a body; each triple is its own two-to-four-unit program, all run in
the profile matrix and with individual switches. Both a build crash and an
incorrect answer are findings.

**Application architecture** — `run_plant_gate.py` over `tests/plant`. This is
the suite's second large program: a wrapper around an external library with
callbacks and a static registry, an engine manager whose breeds register
themselves at initialization, interface services with reference counting, and
interface cycles between layers. It calculates little, but independently
recomputes the same values with flat arithmetic. It runs across profiles, every
switch individually, and four **initialization orders**: the registry is formed
before the main block, and the application must work in every legal order.

**Compositions from live products** — `run_chimera_gate.py` over
`tests/chimera`. The manual inventory ties each workload to MoonBot/Arbitrage
and its oracle, while the runtime requires execution of the line itself and of
every claimed branch. A large tape reduction also exists as a monolith, a split
form, leaf inline steps, and the same steps inside a ring of units; the gate
locks down the AUTOINLINE rejection map so the compared axis cannot disappear
behind a green verdict. JSON, package, text, and encrypted-wire combinations
use the pinned product mORMot and every required Win64 object file from this
repository. General code generation, synthetic arithmetic, and Pascal-vs-ASM
are intentionally excluded: they are the subject of Devil/Omni/Pulse, not
Chimera.

**Independent ASM code-generation oracle** — `run_asm_oracle_gate.py` over
`tests/devil/asm-oracle`. In real x86-64 mORMot, hot functions often already run
as embedded ASM or prebuilt `.obj`; a synthetic Pascal version is not the
product path and therefore does not belong in Chimera. The same pairing is
valuable at another level: MoonCompiler generates code from Pascal, while
hand-written x86-64 calculates the same answer independently. Seven families
provide 57 executable groups covering integer/memory work, hashing,
floating-point, strings, crypto, and several alternative algorithms. The gate
checks the Win64/System V ABI, execution of every declared branch, and exact
digests at O2/O3; `--profiles` adds Debug/O1.

`plant`, `chimera`, `asm-oracle`, and `topology` are part of
`run_devil_all.py`. The Resident switch matrix runs with `--with-switches`
because it takes appreciably longer. Every new signal first receives an
independent minimal reproduction and becomes a finding only after a Delphi
oracle: a large program turning red does not, by itself, explain the cause.

## Devil

Devil is a generated differential system, not a frozen corpus. The same
generated source runs in Debug/O1/O2/O3 and, on Win64, in Delphi 12.2. A Python
model supplies an independent oracle, while the manifest records which axes of
the form space are actually covered. Its complete design is described in
[`tests/devil/README.md`](../tests/devil/README.md).

The optimizer layer is augmented with a closed memory-effects matrix. It crosses
12 memory-mutation routes, 7 optimizer consumers, and 6 positions for a side
effect inside a loop: 504 mandatory critical triples. It also checks all 414
pairs combining loop kind and value width/signedness. This tests the general
invariant that a hoisted or cached value really does not change, rather than a
collection of named LICM/CSE/GVN repairs.

A separate mutation stand temporarily restores only the product part of a
selected fix and requires Devil to observe a new semantic signal against a
clean baseline with the same layers and compilation topology. A compiler that
does not build, a different generated corpus, and a change only in Known
classification do not count as a kill. For already known repair boundaries, the
generator contains mandatory deterministic matrices independent of seed and
`--cases`: the random layer searches for unknown combinations, but does not
replace the regression contract.

```bash
python qualification/suite/scripts/run_devil_gate.py \
  --layers opt --seeds 1,2,3 --cases 200
```

## Upstream compiler core suite

```bash
python3 runner.py upstream \
  --compiler moonbot-compiler-beta --option O2 --option O3
```

The FPC core suite runs with `QUICKTEST=1`. This is deliberately an isolated
compiler + base RTL check: the upstream Makefile builds tests with `-n` and its
own ANSI RTL, without the installed product package graph. The release gate
evaluates sources that explicitly enable Delphi mode. FPC/ObjFPC, tests with
FPC-only extensions, package-dependent forms without prepared package units,
and the special warning-as-error policy remain `skip` entries in the report;
they are not represented as testing our product.

`core_profile_exclusions` lists only our product regressions that cannot
physically run in this core profile: `Variants`, `Rtti`, callback aliases, and
the Unicode RTL. Their sources remain in the complete upstream report, the
reason for every exclusion is recorded in result JSONL, and focused/RTL/Omni
gates must separately test real product behaviour. An ordinary red compiler
test must never be added there: missing packages or a different ABI must be
proven by the structure of the core harness.

The upstream host utilities `createlst`/`gparmake` are built with the current
Unicode RTL and therefore receive only `-Facwstring` through separate
`host_support_options`. This does not change `TEST_OPT`, the uses clauses of
the programs under test, or the compiler-level product prefix.

The runner also honours `%TARGET`/`%SKIPTARGET`. `tcpstrconcat4.pp` is excluded
separately: its FPC-specific oracle requires a code-page-typed `AnsiString` to
retain its code page when assigned to `RawByteString`, whereas Delphi 12.2 uses
`DefaultSystemCodePage` for two typed operands. The source is not rewritten for
our answer and remains visible in the upstream report as a justified `skip`.

Two exact Delphi Known Deviations remain visible: `tw40453` and `tw41282` at
O2/O3. Their meaning is documented in the compiler repository's
`KNOWN_ISSUES.md`; any other red Delphi observation blocks the gate. A
registered Known Deviation must remain an exact red result: an unexpected pass
also makes the gate fail until its cause has been checked and the obsolete entry
removed manually. This is how `tw39744`, which passed after the
function-reference inlining fix, was removed from the list. The known O3 IDE
package-build exclusion is likewise not a release blocker.

`tmask`/`tmask2` test legacy FPC startup with unmasked floating-point
exceptions and therefore contradict the accepted Delphi 12.2 product contract,
where startup exceptions are masked. They remain visible contract exclusions;
explicit opt-in through `SetExceptionMask` and restoration by `SysResetFPU` are
tested by a separate product matrix covering main/worker threads and x87/MXCSR.

The current test set is not locked by count or digest: if the upstream tree is
edited, the runner checks the tests actually present. In a concurrent O2/O3
run, the test set must match between profiles; a truncated option-specific run
is an infrastructure error. A known red result still requires its exact oracle.

## Focused integration gates

`scripts/run_win64_repair_gate.py` closes the target-specific gap in the Linux
gate. It runs natively on Windows against the current compiler worktree,
requires exact planned/actual agreement with the sole inventory in
`runner_manifest.json`, and separately reads the generated assembly of every
optimizer branch bound in that manifest: a safe `try/finally` loop retains
unrolling; the stable address of a static-array element is calculated before
the loop; a proven non-throwing post-inline scalar tree loses its dead
handler/spill without removing real exception paths; and a read-only managed
function result is not copied through a temporary. A missing conditional body,
absent source, incomplete matrix, or unexecuted target branch makes the entire
gate fail.

The focused-gate and Resident-layer inventory changes only in
`runner_manifest.json`. An ordinary run never rewrites `contract_locks.json`;
after deliberate review of a new inventory, the lock is updated with
`python scripts/update_contract_locks.py --inventory`. The ordered
Resident-stage lock is updated with the same utility and
`--resident-exe <exact resident executable>`. Ordinary compiler, RTL, and test
source edits do not require a lock update.

`scripts/run_win64_bigobj_unwind_gate.py` separately checks Win64 COFF bigobj.
It generates 12,000 callable procedures with `try/finally`, builds them with
`-CX -XX -O2`, reads the bigobj header, requires more than 65,535 sections, and
then runs the executable. This is a permanent regression test against truncating
a 32-bit section number in the symbol table; a small object is not accepted as
proof and makes the gate fail.

`scripts/run_devil_zeroext_gate.py` locks down the shared cause of
`dvl-0001/dvl-0026/dvl-0043`. It runs seeds 1 and 24, five affected layers, and
Debug/O1/O2/O3, requiring 1,268 matching checks with no known-findings entries.
This keeps the size-sensitive form reproducible even though manual minimization
changes register allocation and hides the defective long-distance peephole.

Runtime inline `const` is covered by a separate focused test and generated Omni
family: 144 procedures and 324 checks cover scalar/typed values, dynamic-array
and literal-array lifetime, strings/interfaces, loop/nested/try contexts,
property expressions, records, generics, closures, and the exact MoonBot form
with object fields after an executable statement. Four negative controls forbid
rebinding, including a record field and string character; mutation of
dynamic-array elements remains permitted, as in Delphi.

`scripts/run_service_regressions_gate.sh` on Linux and its `.ps1` counterpart
on Win64 build Debug (`-O-`), O2, and O3 minimal forms that the large service
graph exposed in the RTL and compiler: separate `KeyNames` semantics, the
distinct-ordinal chain from Variant, an inline const array, the `TArray` facade
(all three Delphi `BinarySearch` overloads), unsigned formatting, POSIX
separator opt-in, `Char/WideChar` through late-bound Variant dispatch, dotted
Unicode comparison, namespaced paszlib, `TList<T>.arrayofT`, replaying a generic
from PPU with a unit alias, a non-distinct result alias, and Delphi `with`
targets captured by an anonymous procedure. The final oracle checks an rvalue,
ordinary and custom-managed records, an lvalue, a compound array lvalue with
single index evaluation, a `Points[Index]` variant with two lexical loads, a
dynamic-array local, a `const` dynamic-array parameter, and a closure call after
the enclosing procedure exits. The explicit callback ABI additionally has
compile-fail controls for incompatible `var` and `out`. OleVariant→UTF-8 is
checked on ASCII, Unicode, and an empty string through both a variable and a
property. The Variant gate requires its exact carrier: Delphi 12.2 and
FPC/Win64 use `varOleStr`, FPC/Linux uses `varUString`; in every case the source
text is checked. The ObjFPC-only form with a global assignment operator is not
part of the gate: it has no Delphi 12.2 oracle, and FPC extensions lie outside
the product contract.

`scripts/run_namespace_scope_gate.sh` performs 24 clean/PPU-reuse builds at
O2/O3. Besides dotted/default namespace identity, it always checks
case-sensitive `-UaFoo=Bar` together with `-FNScopeX`: an alias key may be
normalized, but `Bar.pas` must not be. A separate reverse-alias form proves
that a short import of the physical unit keeps the configured full dotted name
available without creating a second module/PPU. The same fixture specializes a
generic body from a reloaded PPU and therefore checks restoration of the module
link for both unit symbols.

`scripts/run_monitor_gate.sh` runs the complete `TMonitor` lifetime at
O-/O2/O3, protecting late finalization through the fallback manager. The test is
not delegated to the upstream runner, which legitimately excludes some
non-Delphi forms; it is an independent mandatory release gate.

`scripts/run_rtti_gettypes_gate.sh` and its `.ps1` counterpart check, on Linux
and Win64, the static catalogue of linked types, the MoonBot registry contract,
repeat/threads/DropContext, and negative scope. The separate
`scripts/run_rtti_ppu_version_gate.sh` proves that an old PPU version is not
silently accepted; it alone requires a comparison toolchain prepared by the
exact FPC 3.2.4 RC1 command from `docs/LAB_SETUP.md`.

The same RTTI gate holds cross-unit dependencies of extended-record tables under
normal and smart linking. Four specializations are used separately as a method
result, method argument, property type, and indexed-property argument. Before
the fix, smart linking lost their full RTTI and failed with an undefined symbol;
therefore a green runtime marker cannot be obtained merely by disabling smart
linking.

`scripts/run_forms_gate.sh` separately runs standalone
`tests/known/rtti_public_method_code_address.pas` at O2/O3 and requires Delphi
parity `METHOD=1/CODE=1/CALLED=1`. Public-method lookup, its `CodeAddress`, and
the actual call therefore cannot be hidden within the general Omni run.

The upstream core suite builds its host utilities `createlst`/`gparmake` with
the same Unicode RTL. The runner passes them only `-Facwstring`: it sets the
string manager for those support processes and does not change options or uses
clauses of the programs under test. It does not substitute for the compiler-
level product prefix.

## mORMot

Product mORMot now follows one Unicode application contract on Win64 and Linux.
On POSIX, `TFileName` remains `UnicodeString`; UTF-8 bytes are produced only at
filesystem, `dlopen`, process, and environment boundaries. This is neither a
mixed ABI nor removal of the former compile-time guard: all affected boundaries
are adapted as a single FPC-only layer. Delphi includes and Delphi 12.2
behaviour remain unchanged.

The complete `runner.py mormot` runs natively on Linux x86-64: its exact corpus
contains Linux static inputs and POSIX boundary probes. On another platform the
runner stops before creating result rows with a direct diagnostic, rather than
presenting compiler failures caused by `-Tlinux`, a missing static graph, or an
impossible symlink. Win64 is checked by native focused, RTL, repair,
Omni/integrated, and service gates; this Linux corpus is not presented as a
Win64 suite.

```bash
python3 runner.py mormot \
  --compiler moonbot-compiler-beta --option O2 --option O3
```

The complete `mormot2tests` checks RTL, generics, strings, JSON, crypto,
threading, and other real library forms. External DNS/LDAP and RTSP-over-HTTP
checks are classified as environment; qualification failures must be zero. Exit
code `1` is acceptable only if the final report fully reduces to those explicitly
named environmental deviations. Any unexplained nonzero code, including unit
finalization failure after the report is written, is an error.

Before the full suite, the runner executes focused mORMot probes.
`record-fields-rtti` checks record size, rejection of incomplete numeric-set
RTTI, and retention of a valid enum set. `extended-rtti-generic-property-link`
holds the real unit-boundary form `IKeyValue<Integer, Int64>`; the support-source
list and hashes are recorded automatically in result provenance.
`docvariant-implicit-unicode` reproduces the real JSON -> `TDocVariant` ->
implicit Unicode/`ContainsText` path. `runredirect-eof` requires pipe reading to
finish at EOF, while `unicode-posix-boundaries` covers non-ASCII paths, masks,
symlinks, process arguments/environment, and the working directory.

Our product snapshot contains checked sources from stable line `2.3.8832` and a
product Keccak-256 patch, but no `test` directory. The test suite corresponding
to that base line is therefore stored in `fixtures/mormot-2.3.8832/test`: it is
based on the `test` tree from upstream commit
`38874e16c03373a5275b959fdb1cc38d5597f67f`. The oracle contains only the
adaptation for the intended local contract: fractional JSON numbers remain
strings without explicit permission for `Double`; numeric-path BSON tests
explicitly enable `dvoAllowDoubleValue`. A separate probe locks down both
behaviours. The runner temporarily places the suite beside the actual
`qualification/vendor/mormot-product/src`, testing our exact sources and MM,
not a public or newer library.

The product suite alone is insufficient to check the compiler: newer mORMot
versions add different combinations of generics, managed types, RTTI, strings,
JSON, crypto, networking, and multithreading. The second independent layer,
`mormot-compiler-corpus-2026`, therefore runs the complete suite from exact
upstream commit `bc189414f1b9ea163d24029cc8e814405e8e0cb5` against its own
sources and static set. The only exception is the mandatory product MM: the
test binary receives `mormot.core.fpcx64mm` from `runtime/mm`, like every
MoonCompiler-built application. The public snapshot still forbids Unicode FPC
on POSIX and passes application `String` directly to byte APIs. After checking
the exact commit and a clean tree, the runner therefore copies only its
`src/test`, applies a versioned FPC-only Unicode-boundary diff, a versioned
test-contract diff, and moves the RTSP pair from `3999/3998` to `23999/23998`.
The source checkout is unchanged; the test-contract diff makes JSON decimal
input explicitly `Double`, because a bare Delphi decimal literal has implicit
carrier `Currency`, whereas FPC selects `Double`. That difference is locked down
by a separate Delphi oracle and is not a serializer test. The same source diff
includes the already proven product check for incomplete FPC record RTTI before
building a serializer descriptor and a one-line lifecycle repair in the corpus:
`ValueVarToVariant(nil, ...)` must release the prior managed value before setting
`varNull`. Without it, upstream `Variants` deterministically loses one 32-byte
string block; a full MM census is the regression oracle. Result provenance
records the diff path and SHA. Between base `38874e16` and this snapshot, tests
changed in 901 commits: 16 files, 15,634 lines added, and 3,961 removed. This
layer is only a broad compiler corpus; it does not update or replace our product
mORMot.

No manual clone is required. If the corpus is absent, the runner takes its URL
and commit from the manifest, fetches into a disposable sibling directory,
checks the exact HEAD and clean tree, and only then publishes it by atomic
rename. The runner never switches or cleans an existing directory: any
difference or local edit stops qualification. `qualification/prepare.*` uses
the same sole contract and remains only an explicit prefetch for autonomous
runs.

The complete new suite is retained because no one can prove in advance which
combination of forms will catch the next miscompile. If it finds a problem, its
deterministic minimal reproduction is added to the regression corpus; a
scenario dependent on intertwined forms, lifetime, or threads goes into Omni.

The layers can run separately:

```bash
python3 runner.py mormot --compiler moonbot-compiler-beta \
  --option O2 --option O3 --test mormot-current
python3 runner.py mormot --compiler moonbot-compiler-beta \
  --option O2 --option O3 --test mormot-compiler-corpus-2026
```

The full Linux suite compiles and runs in a unique short `/tmp` directory, then
copies logs and the report into `.m`. This preserves all sources and oracles
without allowing clean-clone depth to exceed the system's 108-byte
`sockaddr_un.sun_path` limit.

### Keccak-256 in product mORMot

A dedicated gate locks down a function that used to live in the
`HyperL/mormot.crypt.core.pas` copy and now belongs to the product mORMot
snapshot:

```bash
scripts/run_keccak256_gate.sh ../.. results/keccak256
```

Five independent checks cover the empty string, `abc`, `hello`, every byte in
`0..255`, and the same buffer through three streaming updates. Expected
Keccak-256 vectors are stated explicitly in the test; debug and release must
print `KECCAK256_VECTORS_OK`. The same source was separately compiled with
Delphi 12.2 and local product mORMot and produced the same result.

The pinned old mORMot lacks a support `SHA256SUMS` file. The manifest of its
Linux x86-64 static libraries is stored in the test package as
`fixtures/mormot-static/x86_64-linux.SHA256SUMS`; the runner and MM gate verify
the actual files from `qualification/vendor/mormot-product/static/x86_64-linux`
against it.

## Memory manager

The exact-source and profile contract check the root
`qualification/memory-manager/profile_contract.*`: an incomplete profile must
stop compilation; a complete profile must build and run the test.

The main correctness matrix:

```bash
scripts/mm/qualify_current_mm.sh \
  ../../.qualification/mm-full \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg \
  ../../runtime/mm/mormot.core.fpcx64mm.pas
```

It includes boundaries, three 100-process finalizer regressions, MM mega, short
structure-array `memory_massive` runs in release and diagnostic modes,
release/diagnostic chaos, large allocations, and expected negative diagnostics.
`memory_massive` passes managed/raw ownership through five threads, performs
remote realloc/free at exact small/medium/large boundaries up to 2 MiB,
saturates every MoonShard arena with forced GetMem contention, and checks both
deferred-free lists plus concurrent COW/refcount/unwind. The `quick` mode is
designed for seconds, not a prolonged soak.

`memory_massive` phase timing is diagnostic provenance only and does not decide
the correctness verdict. Unlike Pulse, this multithreaded test does not reject
scheduler migration of the controlling thread between CPUs: forbidding migration
here would randomly fail a correct MM run. Every real Pulse measurement still
uses the unchanged strict `EndPerfStamp` and rejects migration. If a CPU changes
during a diagnostic phase, its `tsc=0`; wall-clock and thread-CPU values remain
usable as provenance, while the questionable TSC delta is not published as a
measurement.

The full mORMot MM gate:

```bash
scripts/mm/run_mormot_mm_gate.sh \
  ../vendor/mormot-product ../../runtime/mm/mormot.core.fpcx64mm.pas \
  ../../.qualification/mormot-mm ../../.moonbot/toolchain/bin/fpc \
  ../../.moonbot/toolchain/etc/fpc.cfg
```

Success means all 18 classes of this version and zero failed assertions.

`scripts/mm/qualify_current_mm.sh` explicitly distinguishes two evidentiary
modes: standalone probes check internal allocator invariants without installing
the MM into the process, while product probes require the full MoonBot MM
profile. They cannot be mixed: `FPCMM_STANDALONE` is deliberately forbidden
with `MOONBOT_MM_PROFILE_REQUIRED`.

## Benchmark

```bash
python3 runner.py benchmark \
  --compiler moonbot-compiler-beta --option O3
```

The benchmark runs only after correctness. It checks each workload's digest and
measures speed separately; a faster incorrect result is not accepted.

## Operating Levels

After changing the runner itself, first check its fail-closed contracts:

```bash
python3 tests/test_runner_contracts.py
python3 tests/test_issue_tracker_runner.py
```

The quick cycle after a local fix is:

1. rebuild the compiler if the compiler/RTL changed;
2. run the exact reproduction and affected focused gate; service/RTL, namespace,
   monitor, exception capture, Linux PSABIEH, and RTTI have their own permanent
   runners;
3. run `run_devil_targeted.py light` as a fixed broad, one-minute sentinel;
4. for local risk, run `run_devil_targeted.py impact --areas ...`: the area is
   selected by the changed semantics, not the file name;
5. add fixtures O2/O3, original Mega/Omni, and product smoke according to the
   repair boundary.

Light/impact deliberately do not close the release gate. They record the exact
HEAD, dirty state, compiler/config hashes, layers, and commands in JSON, and
are explicitly marked `targeted regression only`. Publication still requires a
complete `run_devil_all.py` and the common exact-HEAD order below.

Before a general release, service regressions, namespace clean/PPU reuse
including `-Ua`, monitor O-/O2/O3, both RTTI gates, exception capture, the Win
stack-header gate, the issue-tracker corpus with `--enforce`, upstream core,
full mORMot, three MM gates, and the benchmark are mandatory. Nightly repeats
the heavy MM matrix with extra seeds and the profiles from
`docs/MEMORY_BENCHMARK.md`.

`runner.py` and every focused gate above create a new result directory and
fail closed if it already exists. This also applies to the explicitly passed
Keccak/MM gate directory: no release runner removes a user result directory.
The SHA in results only reports the sources, binaries, and configuration that
were actually used; it blocks nothing on the next edit.

## Capturing an Exception Variable in an Anonymous Procedure

MoonBot exposed a Delphi form, `on E: Exception`, where `E` is used inside an
anonymous procedure. Previously the handler's temporary symbol table fell out
of the general capture mechanism: O-/O2 ended in an internal error, while O3
could fail inside the inliner.

The fix preserves Delphi 12.2 semantics exactly:

- `E` receives one unique capture slot per lexical handler;
- every explicit read and write of `E` in the handler and its closures uses that
  slot;
- hidden ownership of the exception object is not transferred to a closure:
  Delphi destroys the object when the handler exits even if the closure survives;
- inline substitution preserves normal `nf_load_procvar` on the replacement
  function-reference load. Method/VMT/hidden-self carriers are therefore built
  from one invokable value and the callback is not called prematurely;
- capturers for unit initialization/finalization have distinct internal names and
  do not collide in the common static symbol table.

The positive gate compares exact runtime output at O-/O2/O3 and checks O3
assembly: `Invoke`, `InvokeCast`, `HasProc`, and `CopyProc` must genuinely be
inlined rather than turn green through hidden `noinline`. The matrix includes
main, an ordinary procedure, unit initialization/finalization, two closures of
one `E`, nested handlers, `E := nil`, re-raise through `raise;`, an ordinary
local next to `E`, an escaped closure without invalid reads of the destroyed
exception object, and direct/materialized/cast function references:

```bash
scripts/run_exception_capture_gate.sh \
  ../../.moonbot/toolchain/bin/fpc ../../.moonbot/toolchain/etc/fpc.cfg \
  exception-capture-001
```
