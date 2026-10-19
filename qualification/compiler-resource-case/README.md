# Resource filename case lookup

`$R` and `$RESOURCE` first use the exact file. After an exact miss, the compiler
accepts one ASCII-case-insensitive leaf-name match in the same directory. It
rejects multiple matches instead of relying on directory order. Directory names
and unrelated source/unit searches retain their existing rules.

```text
python qualification/compiler-resource-case/run_gate.py --compiler PATH_TO_PPC --config PATH_TO_MOON_BASE_CFG --output NEW_DIRECTORY
```

For a private backend outside its installed SDK, additionally pass
`--bindir SDK_BIN_DIRECTORY`. The gate runs Debug/Release with directory caching
enabled and disabled. It covers wildcard/explicit directives, FMX/DFM/binary RES,
relative/absolute paths, spaces, missing files, directories and current-directory
decoys. Linux additionally covers ambiguous names in opposite creation orders,
exact-name priority, symlinks, directory case and unchanged UTF-8 filename bytes.
Case folding itself is ASCII and independent of the process locale.

Successful cases load a component and require Value=42. The PPU-only case moves
the output package, hides the sources and links/runs twice. `stale_cache.py`
checks that a resource copied by an earlier unit is visible even after the
destination directory was cached. It requires generated object files as well
as PPUs, so empty units cannot bypass resource processing.

Windows uses ASCII filenames here: non-ASCII encoding in the external resource
converter's response-file path is a separate boundary, not exercised by this
case-folding gate. Ambiguity requires a case-sensitive filesystem and is checked
on Linux. A missing Linux capability fails the gate rather than skipping it.
