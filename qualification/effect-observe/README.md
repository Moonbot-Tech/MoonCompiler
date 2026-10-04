# Effect-model observe gates (optimizer phase F1)

Focused proofs of the tree-layer effect model (`compiler/opteffect.pas`) and
its observe-only consumer (`-OoEFFECTOBSERVE`).  Three permanent stands:

- `run_effect_gate.py` — classification matrix: compiles `fixtures/*.pas`
  with observe on and checks the machine-stable output of the model
  against the `// EXPECT:` rows embedded in each fixture: the summary
  lines (storage classes, instruction effects, stable reason ids) AND the
  algebra lines that exercise the public queries — the exact local
  symbols collected (`rl=`/`wl=`), the `effects_conflict` self-verdict
  (`sc=`), and the `tree_effect`/`effect_union` consistency checks
  (`q=`/`un=`).  Runs every fixture under `-O2` and `-O-`, proves
  determinism of the observe output, and proves the model stays silent
  without the flag.  Routines are keyed by their unique mangled id; a
  duplicate short name inside one run is an error, never last-wins.
- `run_effect_identity.py` — off/on identity: every `identity/*.dpr`
  workload is compiled at `-O-`, `-O2`, `-O3` with and without the flag;
  all PE/ELF executable sections must be byte-identical and both executables must produce
  the same runtime output.  The generic-bearing `id_generic.pas` unit is
  additionally compiled off/off/on: the off/off pair proves the PPU is
  deterministic, the off/on pair proves the diagnostic flag leaves the
  PPU untouched (a generic declaration serializes a settings snapshot
  into the PPU; the flag is masked out of it).  A separate source is then
  copied away from the unit, compiled solely against that OFF-built PPU,
  and instantiates a fresh generic type with observation ON.  It requires
  specialization and main-routine summaries while retaining identical executable
  sections and runtime output.  Observe mode has no right to change any
  produced artifact by a single byte or to disappear during PPU replay.
- `run_effect_sabotage.py` — mutation stand: plants six named defects into
  the model (unknown node/intrinsic pure, call not a barrier, pointer
  write narrow, managed operation narrow, exact-symbol collection no-op,
  conflict predicate always-false), rebuilds the compiler, and requires
  the classification gate to fail on every one.  A sabotage removes a LAW
  of the model — every anchor of that law is patched in one mutant, because
  the front end canonicalizes some tree forms away and a law can have both
  live and currently-unreachable carriers; the corpus kills the mutant
  through the live ones.  Sabotages are applied to the working tree only
  and restored from git; they are never committed.

The gates default to the installed Win64 or Linux x86-64 toolchain under
`toolchain`; `--compiler`/`--rtl` can point them at an explicit
fresh toolchain during development.  Linux identity links in isolated `-n`
mode and therefore obtains the host GCC runtime directory explicitly,
without consuming an ambient `fpc.cfg`.
Both non-mutating gates run in release Medium and platform CI. Explicit `--rtl`
and `--help` work without an implicit toolchain next to the source checkout.

Exact EXPECT fields protect precision where the carrier is stable.
`w_contains` requires storage classes while allowing a conservative
superset. String COW retains all wide writes of the opaque helper, including the
escaped descriptor and heap payload; its unknown-block fallback may additionally
invalidate unbounded locals, but that fallback is not a precision contract.
The class-with fixture checks lexical-local identity, while the ObjFPC record-with
fixture preserves actual compiler-temp coverage. Read-only string and exact-local
neighbours still require their precise effects. Hostile checker controls run with
the release controller tests; destructive compiler sabotage remains a manual lab
step described in [release qualification](../release/README.md#optimizer-and-object-format-contracts).

Fixture discipline: every exact-safe form has a neighbouring dangerous form
(the five mandatory negative pairs live in `f_local` (call-clobber),
`f_pointer` (pointer alias), `f_byref` (by-ref alias), `f_managed` (managed
operator with observable side effects), `f_except` (exception path)).  The
expectations assert model output, never incidental compiler text.
