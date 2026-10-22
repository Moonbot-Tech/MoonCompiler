# Portable RC file paths

Run `run_gate.py --compiler PATH/TO/fpc --output NEW_DIRECTORY`. The gate uses
the `fpcres` beside the compiler. `--fpcres` selects a private resource compiler;
`--config` selects an explicit configuration. Without `--config`, the installed
SDK's normal configuration is used, including in the unpacked archive checks.

The gate checks external RCDATA, custom types, bitmap, icon and cursor payloads
with an independent RES decoder. Paths cover Windows, Unix and mixed separators,
spaces, relative parents, absolute paths, macros and UTF-8 source filenames.
Quoted, nested and search-path includes have separate coverage, including
Unicode names outside the Windows ANSI repertoire. External-resource filenames
retain the bootstrap Classes ABI's native filename repertoire; this gate does
not claim to remove its pre-existing ANSI constructor limitation or add legacy
codepage converters to the Linux resource tool.
Missing and malformed includes must fail even when stdin supplies valid RC text.
Include-depth boundaries and recursive includes must fail without an access violation.
Ordinary STRINGTABLE and inline RCDATA escapes must remain unchanged.

Two fresh consumers compile RC through `-FF` in Debug and Release, with no
pre-existing RES/DRES. They run from a different directory and verify every
embedded payload byte. This checks tool discovery, RC-to-RES conversion, linking
and runtime access rather than merely the resource tool's exit status.

Windows and Linux qualification and release archive jobs run this gate. It
normally takes seconds and does not run Pulse. It does not require MoonBot,
Delphi sources or external resource fixtures.
