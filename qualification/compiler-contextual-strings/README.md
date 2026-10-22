# Contextual string overload contracts

`run_gate.py --compiler <fpc> --config <moon-base.cfg> --output <new-directory>`
checks the compiler against independently compiled and executed Delphi 12.2
programs. No Delphi implementation source is included or used.

The oracle covers scalar plus open-array arguments, typed arrays, literals,
mixed element order, character and pointer forms, declaration and argument
order, three-way overloads and implicit-operator controls. The repair applies
when corresponding viable overloads differ consistently between ANSI and wide
text and an array constructor needs context. It does not rewrite constructors
or redefine general scalar conversion ranks.

`rtl_calls.dpr` additionally checks real `MatchText`, `MatchStr`, `IndexText`
and `IndexStr` results under the native codepage, CP1251 and UTF-8, in O-/O2/O3.
It also runs as a consumer of both unpacked release archives.

`oracle.json` contains 945 accepted oracle cases. Its separate
`known_differences` section preserves 37 pre-existing comparisons outside this
repair, rather than turning their MoonCompiler results into expected behavior.
Those exploratory comparisons are not acceptance cases. They include other
string-family preferences, Variant/empty-constructor ambiguity and competition
between generic and non-generic methods; the gate
does not claim complete Delphi overload compatibility.

Warning restoration is checked separately by
`qualification/suite/scripts/run_compiler_diagnostic_gate.py`. It uses an
explicit Unicode-to-ANSI conversion independent of the repaired RTL calls,
so repairing overload selection cannot hide a warning-state failure.
