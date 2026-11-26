# Unleashed mode: mode markers, single-character resourcestrings, UTF-8 sources

```text
python qualification/compiler-unleashed-mode/run_gate.py \
  --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
```

| Case | What it checks |
|---|---|
| `marker-cmdline-unleashed`, `marker-cmdline-objfpc` | A program whose mode comes from `-M` on the command line uses a unit that declares `{$mode delphi}`. The program must still see its own marker (`FPC_UNLEASHED` / `FPC_OBJFPC`) and not `FPC_DELPHI`. The markers are system macros shared by all modules; a `$MODE` directive used to leave them changed for every module compiled after it. In the product profile this always happened, because the pinned memory manager unit is compiled first and declares `{$mode delphi}` |
| `marker-directive-delphi` | The reverse direction: a Delphi-mode program using an unleashed unit |
| `resourcestring-single-char`, `-fc` | A `resourcestring` of one character outside ASCII (`'예'`, `'é'`) is a WideChar constant and was rejected with "Illegal expression". Two characters and ASCII were fine |
| `utf8-unleashed-default` | Unleashed mode reads a source without BOM and without `-Fc` as UTF-8. The historical ISO-8859-1 default split a two-letter Korean literal into six characters |
| `interpolated-string-unicode` | `$'{N}건 조회했습니다.'` is ten characters. The interpolation was built in an AnsiString, so in a Unicode string profile every non-ASCII fragment went through the ANSI code page (thirteen characters, broken text) |
| `utf8-delphi-control` | Control: Delphi mode keeps its historical default unchanged |

Expected values are Unicode code points (U+C608 = 50696, U+D55C = 54620, ...),
not the current compiler's output.
