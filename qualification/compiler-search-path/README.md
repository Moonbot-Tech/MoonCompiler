# Search-path identity

An explicit project path contains a compiled unit returning 17 and an unrelated
source. The command line supplies the same directory through `/**`, which must
replace that entry with a source-only entry. With no source for the short name,
the compiler must find the namespaced source returning 23 beside the program.

The gate checks Debug and Release from both the project and another working
directory, plus alternate path casing on Windows. The explicit-path negative
control still returns 17. A separate working directory with `-n @config` also
checks that temporarily reading project options cannot poison the cached cwd.

```text
python qualification/compiler-search-path/run_gate.py --compiler <ppcx64> --config <product-config> --output <new-directory>
```

For a backend outside its toolchain, use a configuration with absolute paths or
set `PPC_EXEC_PATH` to the installed compiler directory. Success is
`SEARCH_PATH_IDENTITY_PASS` followed by the number of cases (10 on Windows,
6 on Linux).
