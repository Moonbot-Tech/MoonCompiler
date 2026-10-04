# Upstream RTL corpus

`run.py` executes all non-interactive tests under `tests/test/units` with the
installed MoonCompiler toolchain and product runtime. This turns the 287 tests
already shipped in the FPC tree into an explicit MoonCompiler gate instead of
leaving them disconnected from qualification.

Quick examples:

```text
uv run python RTL-test/upstream/run.py --units math
uv run python RTL-test/upstream/run.py --modes debug o2 o3
uv run python RTL-test/upstream/run.py --compiler path/to/fresh/ppcx64.exe --units character
```

`--compiler` keeps the installed product configuration and units but replaces
the backend. It is a quick compiler-repair check before a full toolchain
rebuild; the final gate still uses the rebuilt product toolchain.

The runner honors the upstream `%OPT`, `%TARGET`, `%RESULT`, `%NORUN`, `%FILES`,
`%ARGS`, `%INTERACTIVE` and `%NEEDEDAFTER` directives. Interactive and ordered
companion tests are reported as skipped; product semantic tests cover those
contracts separately where they matter.

`expectations.json` contains only tests whose oracle contradicts an intentional
MoonCompiler product contract. Every exclusion includes the reason; unexpected
compile or runtime failures still stop the run.
