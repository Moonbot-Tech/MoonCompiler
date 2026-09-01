# F6 / FFT / exception: exact producer diagnostics

The baseline, toolchain, and Pulse commands are recorded in `EVIDENCE.md`.
Every pair below was built from the same source, Delphi 12.2, and Moon backend
exact `4f5c6927b`; the semantic digest matches in every case.

## 1. `managed-exception-cleanup` — the name was misleading

The focused matrix separated four physical paths:

| Case | Delphi cycles/op | Moon cycles/op | Moon/Delphi |
|---|---:|---:|---:|
| managed assignment without EH | 68.792 | 58.441 | `0.850x` |
| same assignment inside try, no exception | 81.365 | 72.002 | `0.885x` |
| one raise/catch per 8 operations, no managed locals | 514.372 | 777.962 | `1.512x` |
| original complete form | 623.360 | 855.440 | `1.372x` |

Moon with the default FPC MM: assign `55.684`, raise-only `764.831`, full
`848.341` cycles/op. Therefore, the bundled MM does not create the gap.

ASM confirms the causal boundary. Moon's normal assignment path is more compact
and faster than DCC. On an exception, Moon calls `fpc_raiseexception`, then
`FPC_DONEEXCEPTION`; final managed cleanup is one short funclet with
`fpc_dynarray_clear` and `fpc_unicodestr_decr_ref`. DCC has more stack traffic
on the normal path, but its exception runtime is substantially faster.

Verdict: this is not a LICM/GVN/RA consumer and does not prove blanket SEH
regvar suppression. The open work is shared `raise/catch` runtime after the
release.

## 2. FFT — addresses and trig are independent roots

The diagnostic program `qualification/performance/diagnostics/
pulse_fft_codegen.dpr` uses one radix-2 butterfly in three ways. Each transform
refills 1,024 complex records; fill is measured separately and does not change
the conclusion.

| Case | Delphi cycles/butterfly | Moon cycles/butterfly | Moon/Delphi |
|---|---:|---:|---:|
| indexed + actual Sin/Cos | 24.925 | 28.055 | `1.126x` |
| indexed + prepared twiddle | 11.430 | 10.216 | `0.894x` |
| pointer-carried + prepared twiddle | 7.703 | 6.906 | `0.897x` |
| fill control, cycles/record | 3.700 | 3.045 | `0.823x` |

Consequences:

1. Moon's bare FP butterfly is already faster than Delphi in both indexed and
   pointer form. It has no general “bad RA”.
2. Manually converting indices into two advancing pointers speeds Moon up by
   `3.310` cycles/butterfly (`10.216→6.906`). This is a real consumer of
   alias-safe address reuse / strength reduction.
3. Angle arithmetic separately has `0.999x` parity.
4. Sin/Cos on the exact FFT-angle distribution takes `77.634` versus `93.713`
   cycles/pair, so Moon is `1.207x` slower. The positive-only control also loses
   (`1.186x`). This is RTL math/runtime, not address-GVN or LICM.

Broad `codegen/math-transcendentals` on the same HEAD shows `0.903x`, but it
mixes Sin, Cos, Sqrt, and ArcTan over a different range of arguments. Therefore,
the old conclusion “Sin/Cos is already faster than Delphi” was too broad.

## 3. What exact ASM shows

In the original Heartbeat FFT hot butterfly, Moon:

- has no stack spill/reload inside the butterfly;
- keeps the array base in a register;
- independently materializes index/scale for every vec access;
- performs 10 XMM `movapd` per butterfly versus 8 in DCC;
- saves XMM6..XMM12 in the prologue, while DCC saves XMM6..XMM7; this cost is
  paid once per complete FFT and is secondary to the inner loop.

Moon is faster than DCC in prepared-twiddle pointer form, so there is no basis
to change the allocator “wholesale for FFT”. Proven owners:

- address lowering / absent reuse — purchased by measurement;
- two-address coalescing — two extra XMM moves, a separate narrow candidate;
- `select_spill`, `do_spill_read`, rematerialization, and split — received no
  consumer in this form;
- FFT trig runtime — a separate RTL cluster.

## 4. Decision for subsequent phases

- F1 effect model remains the foundation of safe LICM and memory reuse.
- F2 LICM is accepted only on its own invariant consumers.
- F5 address reuse has an open gate and a separate alias-safe specification.
- F6 RA mechanism is not created without a new line where exact ASM proves a
  spill, failed coalesce, or call-live producer.
- F4 SEH-live is proved by its own hot-loop A/B with irrelevant `try`, not by
  `managed-exception-cleanup`.
