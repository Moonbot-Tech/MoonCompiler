# Devil — Findings Journal

## Current conclusion

This file preserves the investigation history; the tables below are not the
current registry of open defects. After causal analysis, the present state is:

- every proven wrong-code/Delphi-semantic cluster listed below, including
  extended RTTI, both parts of dvl-0029, and open-array managed records, is
  closed by causal repairs and permanent regression tests;
- the final language-correctness cluster—dvl-0058, the move semantics of
  `Default(T)` for a static array with management operators—is closed by
  transactional heap-backed lowering; its description and boundaries are in
  [`findings/dvl-0058-class-array-field-init-table/FINDING.md`](findings/dvl-0058-class-array-field-init-table/FINDING.md);
- dvl-0057 (ownership of an operator-record value-parameter copy) and dvl-0059
  (live managed slots in TList/queues) are closed by causal lifecycle repairs
  and permanent semantic pins;
- dvl-0060 (opaque scalar-storage changes through a call, procvar, and nested
  parent frame) is closed by the shared O3 storage/effect invariant;
- dvl-0061 (`Variant/OleVariant -> Cardinal`) is closed by an unsigned
  conversion that retains the upper half of the domain;
- dvl-0062 (a cross-unit global changed by a body brought in through
  AUTOINLINE) is closed by the shared final-tree effect model, rather than yet
  another local list of forbidden node kinds;
- dvl-0064 is fixed: source constant overflow is now diagnosed in the
  operation's signed/unsigned domain, while post-AUTOINLINE runtime wrap is
  preserved;
- dvl-0069 is accepted as the release boundary for argument order; the
  language does not specify that order and no live product call with dependent
  side effects is proven;
- dvl-0070 is closed: `TArray.BinarySearch` returns the first item in a run
  of equal values, as Delphi does, rather than the midpoint of the first match;
- accepted divergences are in [Known Issues](../../../../doc/KNOWN_ISSUES.md),
  while generator development and mutation score are in the
  [Devil backlog](BACKLOG.md).

There is one list for the entire suite. Every row is checked against two sources
so known behavior or bad engineering is not reported as a finding:

- [Known Issues](../../../../doc/KNOWN_ISSUES.md)—accepted contract deviations;
- the project's engineering anti-pattern journal—a calibration catalogue of
  solution classes that formally work but are still bad engineering.

The sections answer different questions. **Problems** are what to fix.
**Known deviations** are what the project has already accepted and must not be
reported again as a finding. **Questionable** covers what is not fully proven or
whose cost is unknown. **For reference** covers cases where we differ from
Delphi in our favor or where the divergence is harmless.

Full analyses are in `findings/<id>/FINDING.md`, together with their benches
and evidence.

---

## 1. Problems

**dvl-0064 — fixed: source constant overflow is no longer accepted as a new
constant.**
The exact repro is in `findings/dvl-0064-constant-overflow-accepted`. Before
the repair, Delphi 12.2 returned E2099 while MoonCompiler printed
`9223372036854775808` in all four profiles. Runtime wrap with `{$Q-}`
remains legal and is not part of the finding. The repair checks a source fold
against the range of the chosen arithmetic type and allows wrap only after
inlining an already checked runtime operation.

**dvl-0070 — fixed: `TArray.BinarySearch` stopped in the middle of a run of
equal values.** Our helper already narrowed the right boundary as a lower-bound
search, but returned immediately on first equality. Removing that exit carries
the search through to the first equal item, as DCC64 does. The exact integer
repro, ranged form, `TBinarySearchResult`, product smoke, Omni, and the live
Chimera tape boundary lock down one causal repair. Chimera models the corrected
caller contract; a separate MoonBot application defect is not a compiler
finding.

### Fixed — nondeterminism

**dvl-0041 — fixed: set-constant padding read beyond the internal set buffer.**
The owner called this **the number-one finding to fix**: “Nondeterminism is an
extremely serious problem because our algorithms depend on reproducible machine
code. This is unequivocally a red flag.”

One source, one profile, one machine—different `devil.o` and `devil.exe`.
The **names and count** of unrelated files next to the source affect it; their
contents and sizes do not. The difference is one byte at the tail of a set
constant (`set of 200..255`), outside the domain, so the program behaves the
same while the bytes differ. The dependency is deterministic and therefore
persists in series: while the directory does not change, tens of builds remain
stable.

The first violated invariant was found exactly: `set of 200..255` has seven
logical bytes but an eight-byte Delphi ABI slot; the compiler copied eight bytes
from the internal 32-byte set at offset 25, and the final read reached index 32.
The repair copies only logical bytes and zeroes padding. It was applied across
the entire class:

- the determinism mirror retains both builds in full and maintains a source-
  fingerprint baseline so it catches a mode change **between** runs rather than
  only within one;
- a dedicated **environment gate** (`run_devil_env_gate.py`) is included in
  the suite. It perturbs everything unrelated to source itself—the count and
  names of neighboring files, their extensions, creation order, subdirectories,
  and a large file—and requires byte-for-byte identical artifacts.

Before the repair, nine of ten perturbations changed the same padding byte.
After a self-host rebuild, all 16 environment-gate variants match; a focused
test separately checks logical sizes of 5, 6, and 7 bytes and the adjacent set
base. The finding is neither hidden by an allow-list nor moved to Known Issues.

**dvl-0042 — fixed: the compiler referenced an unwind entry but did not emit
it.** `Undefined symbol: $unwind$P$DEVIL…` makes the entire build fail. A
different subroutine is lost each time (six different symbols were collected
from layers `set`, `meta`, `weave`, `composite`, and `genpath`), so the defect
is in compiler state, not in code shape. The minimal set is 13 layers; fewer do
not reproduce it. Kinship with dvl-0041 was not confirmed: the cause was an
intermediate `Word` before the 32-bit `SectionNumber` in COFF bigobj. After
widening it to `LongInt`, the permanent gate creates 72 017 sections and runs
the executable.

**dvl-0055 — fixed: loop strength reduction reused an address selected by
mutable data on the first pass.**
After unrolling the inner loop, `Table[Data[I]]` was incorrectly considered
invariant for the outer loop even though that same loop wrote a new value to
`Data[I]`. Generated O3 code retained the `Table` element address calculated on
the first pass and read it again from the second pass onward. AES therefore
silently diverged from FIPS-197 while Debug/O1/O2 remained green.

The repair neither disables unrolling nor strength reduction. An indexed
expression may now be hoisted only when the loop body neither writes nor
modifies the same base, takes and releases its address, nor contains an opaque
call/ASM or pointer write. The old regression for a safe invariant address stays
green. The new focused test checks three dependent passes: pre-fix O3 exits with
code 2, while current O2/O3 exit with code 0. A separate AES probe again agrees
with FIPS-197 intermediate values and ciphertext.

**dvl-0060 — fixed: O3 retained a scalar across an unknown memory mutation.**
For the first time, the full optimizer-effects matrix combined 12 mutation
routes, seven optimizer consumers, six side-effect positions, four loop forms,
and four integer ABIs. The first A/B produced 20/20/19 O3 mismatches over three
seeds while Debug/O1/O2 and Delphi were completely green.

The root consisted of two independent old assumptions. Strength reduction
looked only at direct DFA writes and retained a product with a global changed by
an ordinary or procvar call. Constant propagation considered initial
`Value := 4` constant inside a loop although `Value` was a non-registerable
parent-frame local and a nested routine incremented it between two uses: O3
printed `441` rather than `651`.

The repair neither bans O3 nor accepts experimental LICM. A scalar invariant is
now proven from its storage class and memory barriers; propagating a constant
through a loop is allowed only for a compiler temporary or a genuinely
registerable scalar. Focused regression covers global/call, procvar, nested
parent frame, pointer escape, mutable index, and safe local control. A separate
future-invariants test locks down the zero-trip trap, growing array length,
managed function result, inline mutation, and for-step latch—errors found only
on rejected optimizer branches. It also retains the positive nested-loop form,
the index change between repeated addresses, and the nested handler accessing a
parent-frame record—boundaries that broke the address-cache and SEH-regvar
experiments.

After the ordinary bootstrap, both focused tests pass in O-/O2/O3; Devil seed 1
has `905` checks in every Debug/O1/O2/O3, one digest
`7E04B8BF7E8F8D9E`, and findings/known = `0/0`.

**dvl-0061 — fixed: `Cardinal` failed after a round trip through `Variant`.**
The carrying `varLongWord` was created correctly, but the reverse System
operator unconditionally called signed `VarToInt`. Consequently every value
above `High(Integer)` raised overflow. Small integer carriers retain their old
fast path, exact `varLongWord` is read directly, and float/string/wide carriers
are converted immediately into the unsigned domain. The Delphi oracle and a
permanent matrix cover Variant/OleVariant, both halves of the 32-bit domain,
modulo, and rounding.

**dvl-0062 — fixed: AUTOINLINE hid a write to an external global from strength
reduction.** In the complete compilation unit, O3 replaced a cross-unit call
with its body, but the old scalar-invariance decision relied on DFA before this
tree form and a separate scan of call/ASM/pointer writes. The result was `142`
rather than `127`; `-OoNOAUTOINLINE` and the other profiles calculated
correctly. The local scan was removed. A static scalar is now checked against
the one shared `opteffect` model of the final tree, which sees an opaque call
and a direct post-inline write equally. The permanent regression is the full
Devil case: a short handwritten form does not reproduce this layout-sensitive
defect.

**dvl-0046 — fixed: one-byte GUID text is no longer read through a two-byte
pointer.**
`TGUID.FromString` accepts `ShortString`, but in the Unicode product RTL,
`PChar` arithmetic advanced by two bytes and passed pairs of adjacent ASCII
bytes to the parser as one character. `TryStringToGUID` consequently rejected
all valid values. Only the local pointer type changes to `PAnsiChar`; format,
scatter table, `TGUID` layout, and exception contract remain unchanged.

Focused regression checks upper/lowercase, zero/full GUID, direct
`TGUID.FromString`, `GUIDToString` round trip, and three independent malformed
inputs. Self-host bootstrap and the 72-row Win64 repair gate are green. The
provenance gate now hashes not only compiler/configuration but also the actually
installed `system.ppu` and `sysutils.ppu`, binding RTL proof to the exact
runtime.

**dvl-0047 — fixed: `System.Integer` no longer resolves to bootstrap
`SmallInt`.**
In object modes, ordinary `Integer` arrives from `ObjPas` and is 32 bits wide,
but qualified lookup returned a same-named 16-bit alias from the `System`
source. Consequently not only casts differed: a `System.Integer` variable had
a different size, and the ordinary `TComparer<Word>` sign-extended the upper
half of the domain.

Qualified lookup now normalizes exactly `System.Integer`, and only when `ObjPas`
is active; the global System symbol, TP/ISO, and 16-bit targets do not change.
A focused compiler test covers declarations/casts/parameters/pointers/arrays,
and an RTL-generics test covers comparer, sort, and Word binary search in
O-/O2/O3.

**dvl-0048 — fixed: an empty string is no longer treated as one field.**
Both central `TStringHelper.Split` implementations entered the shared loop when
`LastSep = Length(Self) = 0`. An early empty-source guard now returns an empty
array for char/string separators and every wrapper without touching the
non-empty hot path. Cross-compiler regression covers options/count/quotes,
empty separator arrays, and adjacent non-empty forms; Delphi, O-/O2/O3, and the
exact 74-row gate are green.

**dvl-0050 — fixed: the Delphi-default BOM is restored.** The writer already
knew how to write `Encoding.GetPreamble`; the incorrect part was the default of
a new `TStrings`: `WriteBOM=False` plus implicit `soPreserveBOM`. Initial
options now match Delphi 12.2. Explicit opt-out and FPC-only preserve remain
available. The cross-compiler test covers UTF-8/UTF-16, empty/non-empty stream,
and load/save; full self-host and the exact 74-row gate are green.

**dvl-0051 — fixed: a Unicode Variant no longer depends on string content.**
The RTL created BSTR, while the compiler lost the AST kind of an ASCII literal
when choosing an assignment operator. After those two repairs, a broad probe
found another related hole—`varUString` was absent from the common-type table
and failed during comparison. The final repair covers assign/copy/cast/compare/
concat/clear and Variant `SAFEARRAY`, preserving explicit WideString and
AnsiString. Concatenation retains the subtype of its left string operand, and
SAFEARRAY stores string elements as BSTR. Delphi/FPC regression passes in
O-/O2/O3.

**dvl-0053 — fixed: O2/O3 CSE no longer conflates `+0.0` and `-0.0`.**
The old explanation involving constant folding was wrong: O- preserved the sign
bit, while generated assembly proved that a previously loaded positive zero
replaced negative zero. Constant-node equality now distinguishes zero sign
without fast math. Focused Delphi/FPC regression covers both constant orders,
folded arithmetic, and runtime controls in O-/O2/O3.

**dvl-0001, dvl-0026, dvl-0043 — fixed by one narrow-extension repair.**
Ordinary casting, generic return, and `with` altered code layout, yet converged
on one long-distance peephole. It removed MOVZX/MOVSX and failed to normalize
the immediate of an earlier narrow `mov`. The shared byte/word/dword repair
passed seeds 1/24, five layers, and Debug/O1/O2/O3: 1 268 checks, known=0.

### Break or block production code

| id | summary | cost |
|---|---|---|
| dvl-0031 | a string literal does not materialize: refcount `-1`; writing to its buffer fails everywhere except a local variable | AV in production where Delphi works |
| dvl-0033 | a marker attribute without its own constructor does not compile in any position | primary attribute syntax—module does not compile |
| dvl-0035 | `class operator Initialize` and `Assign` are unsupported | RAII on records is unavailable |
| dvl-0036 | **fixed: both Delphi spellings map to the existing `constref` ABI** | address/read-only/ObjFPC controls |
| dvl-0032 | an attribute before a parameter, inline variable, or `class var` is not parsed | valid Delphi code does not compile |
| dvl-0021 | `varargs` without `external`: Delphi accepts, we reject | code-porting blocker |
| dvl-0019 | `TProc`, `TFunc<T>`, `TPredicate<T>` are absent from the RTL | code-porting blocker |
| dvl-0022 | a set element outside range: Delphi accepts, we fail with an assembler error | build fails |
| dvl-0017 | `Internal error 200405231`: inline of a managed procedure in `finally` | ICE in a production profile |
| dvl-0002 | ICE 200706094 on `Odd(UInt64 constant)` | ICE |
| dvl-0007 | **fixed: the product runtime installs the platform monitor manager automatically and the generated monitor shape is active again** | Win64/Linux monitor gates |

### Calculate differently from Delphi—and stay silent

| id | summary |
|---|---|
| dvl-0053 | **fixed: CSE preserves the sign bit of a zero real constant without fast math** |
| dvl-0049 | Boolean is a distinct kind, `tkBool`, not `tkEnumeration` |
| dvl-0050 | **fixed: Delphi-default `WriteBOM=True`, explicit opt-out, and preserve mode are verified** |
| dvl-0051 | **fixed: `varUString` is created and fully supported; Wide/Ansi controls are unchanged** |
| dvl-0011 | O3 sign-extends the upper half of a 128-bit result |
| dvl-0018 | `release` coalesces two calls to a side-effecting function in one expression |
| dvl-0003 | O2/O3 reverse finalization order during exception unwinding |
| dvl-0004 | comparison with a C-style Boolean is not normalized to 0/1 |
| dvl-0012 | **fixed: Unicode ASCII literal/`Chr` and `vtWideChar`** |
| dvl-0013 | **fixed: explicit cast is a storage view; assignment is transcoding** |
| dvl-0015 | an integer literal in Variant narrows by the signed type rather than the unsigned one |
| dvl-0028 | **fixed by the common signed/unsigned range rule** |
| dvl-0029 | **ASCII is fixed; non-ASCII source-codepage typing remains TODO** |
| dvl-0030 | **fixed: ASCII literal concatenation preserves UnicodeString** |
| dvl-0037 | attributes on class and record fields do not reach RTTI (part of the finding is new; see section 2) |
| dvl-0040 | `{$RTTI EXPLICIT ...}` does not control table composition: we emit what Delphi drops |
| dvl-0005 | an out-of-bounds constant array index is silently accepted |

---

## 2. Known deviations (checked against `KNOWN_ISSUES.md`)

This is what the project has already accepted. It is no longer reported as a
finding; the row remains so the next run does not reopen it.

- **Extended RTTI for public members.** `KNOWN_ISSUES` states: with
  `{$RTTI EXPLICIT METHODS([vcPublic])}`, Delphi exposes a public method while
  we publish only published. This covers my **dvl-0037** **partially**: a
  `public` property without attributes is the same deviation. But **class
  fields, record fields, and methods lose attributes even in published
  context**—that is absent from `KNOWN_ISSUES`, so this part remains a problem.
- **`Currency` with an untyped real literal.** `KNOWN_ISSUES`: a mixed
  expression is not typed as in Delphi. This includes **dvl-0016** (a real
  literal in Variant stores `Double` rather than `Currency`) and **dvl-0027**
  (`Double`/`Currency`—Delphi rejects it as ambiguous while we silently choose
  `Double`). The kinship is direct; they need no separate repair until the root
  question of typing these literals is solved.
- **dvl-0039 no longer belongs to MB-06.** Typed `Int64` versus an
  `Integer/Cardinal` pair is closed by the shared range rule for same-width
  signed/unsigned candidates. Deferred `Random(High(UInt64))` has another cause
  —an untyped constant and overload set—and is not covered by that repair.
- **dvl-0056 — order of two side-effect inline expansions.** Our compiler
  evaluates them sequentially and retains the behavior of the same non-inlined
  calls; DCC64 changes observable semantics merely by inlining. The divergence
  is deliberately retained in our favor and recorded in `KNOWN_ISSUES.md`.
- **dvl-0069 — ordinary-call argument order.** DCC64 evaluates left to right,
  Moon right to left; both construct open arrays left to right. The language
  does not promise an order, and a search through two products did not prove a
  dependency on it. Before release, do not change compiler-wide call lowering;
  the boundary and exact probes are retained in `findings/dvl-0069-*`.
- **Negation of an unordered float comparison and `-0.0 + +0.0`.** The
  divergences are accepted and closed by five red Omni names. In the same spirit,
  **dvl-0009** (`Inf-Inf` yields zero instead of NaN)—the owner expressly said
  that such a divergence is not worth a line in the report.

---

## 3. Questionable — needs resolution

- **dvl-0034** (a method name without parentheses before `reference to`) and
  **dvl-0038** (a helper name in type position) are both cases where **we accept
  what Delphi rejects**. The cost is one-way portability: a module written here
  will not compile in Delphi. The owner must decide whether Delphi strictness is
  mandatory or this is an acceptable extension.
- **dvl-0020** (`inline` with an open array), **dvl-0024** (anonymous
  `reference to` in a variable declaration), and **dvl-0025** (a constant shift
  wider than the type) are the same “we are more permissive than Delphi” class.
  None corrupt behavior; the question is whether the contract requires
  fail-closed behavior.
- **dvl-0023** — `{$mode}` in source overrides switches supplied by the driver.
  It is Pascal behavior, but a trap for our contract: any file containing
  `{$mode}` silently leaves the mode set by `build.ps1`. This more likely needs
  a driver rule than a compiler repair.

---

## 4. For reference: where we are broader or divergence is harmless

- **dvl-0044 — rejected after causal verification.** `-gl` is not pure
  metadata: the switch deliberately connects `LineInfo` and `ExeInfo` units.
  The two additional RTTI types are named exactly: `LineInfoCache` and
  `TExeFile`. These are two different unit sets, not catalogue instability.
  Modes gate now compares DWARF2 and DWARF3 with an unchanged unit graph.
- **dvl-0045 — fixed by the common narrow-extension repair.** The exact PPU
  alias passes Debug/O1/O2/O3 and PPU reuse without an allow-list.
- **dvl-0006, dvl-0008, dvl-0010** are divergences where **Delphi is wrong**:
  folding of mixed comparison, RTTI catalogue, truncation of the `Int64`
  selector in `case`. They require no repair from us and prove that the suite
  does not fit its answer to the arbiter.
- **dvl-0014** — string-type names in RTTI (`UnicodeString` versus `string`).
  This is an observation, not a defect: a consequence of `string` being an
  alias here.
- **dvl-0031, the reverse side.** Our behavior is more economical than
  Delphi's: the literal is not copied on every store. But this is exactly the
  case where “better” does not count—the compiler contract is Delphi 12.2
  behavior, not an improvement. The finding is therefore in “Problems”; this
  note only records that the win is real and worth preserving if the repair
  permits a choice.

---

## What was checked to keep this from becoming bad engineering

Checked against the internal engineering anti-pattern journal, sections
“Treating unproven problems” and
“Plausible instead of proven”:

- no row in “Problems” rests on “it could theoretically be bad”: each has either
  a reproduction bench, retained artifacts, or an exact layer check;
- the mechanism is never invented to support a conclusion: where it is not
  exposed (dvl-0042), this is stated directly, and the finding is not merged
  with one whose mechanism is known (dvl-0041), despite plausible kinship;
- divergences where the arbiter is wrong appear in a separate section rather
  than being added to our score;
- deviations already accepted by the project appear in section 2 with a link to
  `KNOWN_ISSUES.md`, so a run cannot report them as new.
