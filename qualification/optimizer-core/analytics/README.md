# Analytics optimizer regression gate

Checks the EH-aware elimination of unused incoming private-static register values and reuse of stable local/value-parameter array descriptors with EH outside the loop. Global-variable cases are separate programs: a shared helper would change the property under test.

```sh
python run_gate.py --baseline /old/ppcx64 --compiler /new/ppcx64 --config /product.cfg --output /new/output
```

Modes are O-, genuine O2, O3, and O3 with range/overflow/stack/I/O checks. Optimization switches are reset before selecting each level. Some scalar/thread controls intentionally override R/Q in source; the checked mode does not override source directives. Generated entry cases do not disable those checks.

Outputs are compared across compilers. Array and additional cases have independent oracles. `--modes checked` and `--cases entry_` support focused repeats. Output must be a new directory. Build/run logs and compiler/input/output/binary hashes are preserved; reproducible executables are removed after checking.

CI and the release matrix run `--modes O3 checked` without `--baseline`. In that mode the current compiler with optimizations disabled supplies the reference, with the same runtime checks as the candidate. Independent oracles still apply, and every result records the actual optimization flags. Supplying `--baseline` instead compares two compilers at identical optimization levels.

Independent cases run in up to four workers (`--jobs 1` selects sequential execution). Every case/compiler/mode has its own output and unit directory, so parallel compilers never write the same PPU or object. This is a correctness gate; it records no performance measurements.

`cases/` covers BSS alias observers before the first register definition, nested-thread captures, external aliases, real sibling/inner EH, guard-page exception order and FP bits/MXCSR (Double, widened Single and native Single). `cases.json` records each purpose and expected answer. Thread tests use bounded waits and close handles.

Scalar cases remain protective counterexamples: no new SSE optimization was accepted. This gate is not a full release qualification. Existing loop-base and loop-regvar gates separately check positive and negative assembly shapes.
