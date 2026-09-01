# Additional independent tests

`tgeneric131.pp` comes from the current upstream FPC `tests/tgeneric131.pp`.
It is a compile-only control for adjacent generic/interface logic. On Linux and
Win64 it must reproduce the exact known diagnostic about a missing GUID;
ObjFPC syntax is not considered part of the product Delphi contract.

`delphi_tb0728.pas` is the Delphi-mode variant of upstream
`tests/tbs/tb0728.pp` with the two required extensions, `stringordcast` and
`inlinevars`, explicitly enabled. It checks compile-time conversion of string
ordinal constants and their actual byte layout in typed/untyped, global, and
inline-var forms.
