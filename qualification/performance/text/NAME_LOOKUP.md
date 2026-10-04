# Case-insensitive field lookup

`pulse_name_lookup` resolves eight prepared field names with `SameText`, returns the matching field index and uses it in a digest. Every lookup checks the expected result. One reported operation is one complete lookup, including the unsuccessful comparisons before a match.

The six cases keep three distinct requests visible: matching spelling, uppercase spelling, and absent names. Shape 0 uses ordinary twelve-character field names with different beginnings. Shape 1 adds a shared `ServiceConfiguration.` prefix. The absent names differ at their first character in both shapes. Inputs are prepared outside measurement; `Copy` ensures the ordinary hit also exercises equal content in separate string instances.

These cases show how early rejection and full equality compose in a small name dispatcher. They do not assign population weights to the six shapes or replace the primitive equal, folding, length and late-mismatch controls in `hot-rtl`.

Run through the normal Pulse runner with `--programs name-lookup`, or execute the built program with the usual Pulse profile and selected case.
