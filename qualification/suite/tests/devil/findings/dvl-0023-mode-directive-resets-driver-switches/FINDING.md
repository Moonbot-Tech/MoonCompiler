# dvl-0023 — `{$mode}` in source resets switches supplied by the build driver

The analysis is reconstructed. This is a build-contract rule, not a code
generation defect.

## What happens

The build driver supplies a set of mode switches on the command line
(`-Mdelphi`, `-Municodestrings`, `-Minlinevars`, and others). A `{$mode ...}`
directive in the source file itself **resets** them to the default set for that
mode.

The practical consequence is that any generated or handwritten file beginning
with `{$mode delphiunicode}` loses every additional switch supplied by the
driver. For example, inline variables stop parsing even though the command line
contained `-Minlinevars`.

## Why it matters to the suite

Every generated unit must **repeat the required switches** after its `{$mode}`
directive. `STATUS.md` records this rule, and it has already caused failures:
a probe stopped at `for var K := 0 to ...` even though `-Minlinevars` was on
the command line.

## Reproduction

A file containing `{$mode delphiunicode}` followed by an inline-variable
declaration is sufficient. When built through the driver, parsing fails despite
the supplied switch. Adding an explicit `{$modeswitch INLINEVARS}` after the
directive makes it compile.

## Boundary

This is Pascal behaviour, not a defect. The journal keeps the entry in the
“questionable” section: the compiler must not be changed; the file-authoring
rule must be observed.
