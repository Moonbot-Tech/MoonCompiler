# Manual ASM layout review probe

The 2026-09-28 packet was rejected. All proposed RTL/MM/MoonORMot layouts
retain their preceding source and alignment. The compiler branch contains
measurement tools and documentation, not a new performance claim.

`probe.pas.gz` freezes the exact ASM views and drivers from the original
`stand3d.pas`, with the corrected sampler. It is a forensic fixture for this
packet, not an extractor of future product objects. For a new change, rebuild
its exact baseline and candidate objects and prove their bytes and section
alignments against the probe before measuring. Never reuse this fixture as
proof of newer product instructions.

```text
python build_probe.py --compiler <MoonCompiler-fpc> --output <empty-build-dir>
manual_layout_probe check
manual_layout_probe inproc r19-varset-contains 0 1
```

MoonORMot must be on the compiler search path (or pass `--fpc-arg=-Fu<path>`).
The probe embeds both ABI spellings and calls each through its own driver.
Every registered view must pass geometry and semantic oracle checks. Historical
release views with different oracle contracts are excluded from registration.
Every copied view is checked again after relocation before timing.

The sampler moves one routine to each of 64 offsets 0..4032, step 64, and
the identical calling driver to phases 0 and 32. Unpinned candidates and
MoonORMot baselines are tested at both entry phases 0/32. Entries and phases
remain separate observations, shuffled within each round. Defaults: seven
rounds, a calibrated 1 ms batch after an equal 1 ms warmup. A reported cycle
value is one driver sweep over all fixture rows, including call and digest
overhead; ratios compare identical drivers and input rows. The fourth argument
is the shuffle seed: use and record a different seed per fresh process. Its
state is separate from fixture-data initialization; the header records it,
the actual slot base, warmup duration and selected PMU type.

Linux: run under `taskset` on one reserved logical CPU and keep its SMT sibling
quiet. The PMU must run for at least 99% of the measured window. Hybrid Intel
cores require separate runs; set `LAYOUT_PMU_TYPE` to the integer from
`/sys/bus/event_source/devices/cpu_core/type` or `cpu_atom/type` for that core.
The Linux kernel ABI puts this selector in config[63:32]
([kernel documentation](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/tools/perf/Documentation/intel-hybrid.txt)).
Record and restore any changed perf permissions and boost controls, even on failure.

Windows: the fixture reserves CPU12; the controller must stay outside CPU12/13
and monitor CPU13. The clock is thread cycles normalized by dependent-add
chains. A busy sibling, unstable frequency or noisy A/A prevents acceptance.
Move parallel builds to other physical cores and retain their original masks.

Create the explicit manifest required by `../tools/manual_layout_judge.py`.
Its expected CPUs, processes, cases, tags, entry phases, positions and driver
phases must be decided before the run. Missing cells, duplicate samples,
failed oracle/geometry checks and rejected or incomplete processes fail closed.
Judge every position against the existing layout; include position zero and
each baseline phase separately. A/A noise is uncertainty, never permission
to erase a loss. The loss ceiling is 5%; a tradeoff needs a gain above 10%.

This finite warmed-loop matrix can disprove a layout claim. It cannot guarantee
speed in every program: other hot callers, neighbours, predictor histories,
cold caches and unrepresented input paths remain different contexts. Require
consumer checks for any accepted candidate. If the result is adverse or
unproved, preserve the existing layout. The allocator is unchanged in this packet.

Evidence and the scoped product rollback are in `REVIEW.md`.
