# Preserved integer relations

Release can remove a repeated conditional branch after the same integer comparison
when the earlier branch was not taken and neither operand changed. Floating point
instructions between comparisons may change FLAGS. The later CMP remains: other
instructions can still consume its flags.

The local proof admits only joins whose references all come from earlier branches
inside the proven region. Taken entry from the first comparison, outside entries,
back edges, opaque assembly, calls, partial/implicit register writes and offset
targets stop the proof. The bounded scan adds no runtime guard or padding.

`relation_semantic.dpr` uses an independent integer-rank oracle, including NaN,
infinities, signed zeros, empty ranges, repeated scans, an external join and a byte
write. `ScanBatch` exercises the optimized form through an actual floating point
comparison and parity branch; its object must have only one integer JLE. The
documented NaN comparison-negation limitation is avoided with direct ordered
comparisons, without removing unordered test inputs.

Run against an installed product runtime, using its resolved configuration:

```text
python qualification/optimizer-core/value-relations/run_gate.py --compiler <ppcx64> --config <resolved-product.cfg> --output <new-directory>
```

The gate runs O-/O2/O3 and Linux PIC. It records compiler/config/source/executable
hashes, arguments and logs. No runtime discovery occurs before argument parsing.
The previous compiler passes semantics but fails the redundant-branch check.

The source IR gate builds fresh compiler dependencies with the ordinary IDE
bootstrap and configuration. It checks all 900 condition pairs against flags
derived independently from 8-bit subtraction, requires equal-condition folds, and
exercises joins, writes, opaque markers, metadata, label reference counts and live
CMP flags. These controls define the optimizer's IR contract; they do not claim
that every hostile instruction sequence is produced by ordinary Pascal.

```text
python qualification/optimizer-core/value-relations/run_ir_gate.py --compiler <ide-ppcx64> --config <ide-fpc.cfg> --output <directory>
```

Success markers: `VALUE RELATION GATE: PASS`, `VALUE RELATION IR GATE: PASS`.
These are correctness/code-shape gates, not performance measurements.
