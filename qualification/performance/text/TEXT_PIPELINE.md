# Text pipeline model

`pulse_text_pipeline.dpr` processes a fixed trace of 256 records. Each record
trims an input key, finds it in a 16-key dictionary with `CompareText`, splits
a comma-separated payload, trims the fields, encodes the last field as UTF-8,
and reads every key, field and output byte into an observable digest.

The three dictionaries have different beginnings, four groups of shared
prefixes, or one long shared prefix. Payloads contain 4, 16 or 64 fields and
a non-ASCII character. Clean mode uses canonical keys and fields. Mixed mode
alternates clean inputs with uppercase, padded keys and padded fields.
Retention is either zero or a 64-record window; retained fields and encoded
outputs are consumed before replacement and at the end of each trace.
The fixed trace keeps startup and teardown work per record independent of
the harness's calibration iteration count.

Preparation independently constructs the expected fields and UTF-8 bytes.
Before timing, a complete trace checks identities, all contents and the final
digest. Timed traces consume the same data. The model calls the linked public
RTL; it contains no machine-code clones, address relocation or CPU dispatch.

Pulse registers the program as `text-pipeline`. `list` exposes 36 modes, for
example `shape1-fields16-mixed1-retain64`. One reported operation is one complete
record. ASCII key folding is common to Moon and Delphi; non-ASCII payloads are
checked by value. This model is not an assertion that their complete Unicode
case-folding APIs have identical semantics.
