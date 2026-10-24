# Durable immutable RTTI and public contract regressions

The release metadata gate runs these checks on the installed SDK. They can also
be run separately with Python 3 and a fully expanded product configuration:

```
python qualification/build-driver/immutable_rtti_pool_gate.py --compiler /absolute/compiler --config /absolute/product.cfg --output /new/empty/path --expect-pooling --mormot-consumer
```

The output directory must not exist. All builds and logs stay there. Omit `--expect-pooling` for the baseline semantic control. On Linux add `--external-assembler` to check the explicit old-path fallback; the external build intentionally does not require shared pointers. `--mormot-consumer` requires the normal mORMot source paths in the SDK config and rebuilds actual mORMot units.

The multi-unit driver covers fresh, cached, source-free and reversed unit builds.
It also runs the public-record and mORMot consumer fixtures; a single ordinary
program invocation would not cover these compilation states.

Coverage: distinct TypeInfo/VMT identity, exact case, two legal 127-character method names differing only at the end, empty stripped names, shared result/hidden-Self/ordinary parameter descriptors, 16/32 constant alignment, PACKRECORDS 1/8, reflective Invoke through the Linux SDK's ffi.manager, source-free PPU use, reversed link-unit order. Writable LOCAL public records test var SizeInt, var TInvokeHelper, var PShortString, callback invocation, assignment and Move semantics. No test writes emitted read-only metadata.

Negative controls: the own hex-name prototype silently misreads the second long name at runtime; the narrowed StackSize SDK and property-based InvokeHelper SDK each fail the public contract at compilation. Baseline and selected pool candidate pass. This makes the tests detect the actual rejected designs rather than mirror implementation details.

Arbitrary NUL/high-byte/255-byte internal RTTI names cannot be expressed as Pascal method identifiers. Their compiler-instrumentation stress tests remain supplementary stand evidence (`pool-boundary-prepare.py`, `pool-boundary-results-win.json` and Linux runtime log), not a claim of permanent language-level coverage. The durable long-name fixture catches the actual truncation fault without instrumentation.
