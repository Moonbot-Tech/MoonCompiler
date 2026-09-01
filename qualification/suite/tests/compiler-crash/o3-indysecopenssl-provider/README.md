# O3/AUTOINLINE compiler crash in a legal unit cycle

This is the reduced form of the internal compiler error that prevents the
Linux Release build of MoonBot when the IndySecOpenSSL headers are rebuilt.
The reproducer has no dependency on MoonBot, Indy, OpenSSL, or mORMot.

The three source files model a legal Pascal dependency cycle:

- `O3AutoinlineCycleB` uses `O3AutoinlineCycleA` in its interface;
- `O3AutoinlineCycleA` uses `O3AutoinlineCycleB` only in its implementation;
- the small procedure from unit B reads and writes a private `class var` and
  becomes an AUTOINLINE candidate in unit A.

After building the compiler on Linux x86-64, run from the repository root:

```bash
repro=qualification/suite/tests/compiler-crash/o3-indysecopenssl-provider
mkdir -p /tmp/mooncompiler-o2 /tmp/mooncompiler-o3

./.moonbot/toolchain/bin/fpc -n @.moonbot/toolchain/etc/fpc.cfg -B -O2 \
  -Fu"$repro" -FU/tmp/mooncompiler-o2 -FE/tmp/mooncompiler-o2 \
  "$repro/O3AutoinlineCycleCrash.dpr"

./.moonbot/toolchain/bin/fpc -n @.moonbot/toolchain/etc/fpc.cfg -B -O3 \
  -Fu"$repro" -FU/tmp/mooncompiler-o3 -FE/tmp/mooncompiler-o3 \
  "$repro/O3AutoinlineCycleCrash.dpr"
```

Observed on committed `main@b9d7e143afe91a4a95f842403fc11cffcd3a27ed`:

- `-O2`: succeeds;
- `-O2 -OoAUTOINLINE`: internal compiler error;
- `-O3`: internal compiler error;
- error: `EListError: List index exceeds bounds (-2)`.

A compiler built with line information gives this causal stack:

```text
optcall.importglobalsyms
  -> current_module.addimportedsym(sym)
  -> fmodule.pas:1456 module.symlist[sym.SymId]
```

At the failing call, `sym` is the private static class variable `THolder.FValue`,
`sym.typ=staticvarsym`, and `sym.SymId=-2`. AUTOINLINE is copying the body from
unit B into unit A while the legal interface/implementation unit cycle has not
yet assigned a serializable symbol id to that private class variable.

The full MoonBot failure is the same path: AUTOINLINE copies
`SetLegacyCallbacks` from the OpenSSL header cycle and reaches private class var
`TOpenSSLLegacyCallbacks.FCallbackList` with `SymId=-2`.

The repair must preserve Release `-O3` and AUTOINLINE. Disabling AUTOINLINE,
globally refusing this class of inlining, compiling MoonBot at `-O2`, or adding
a product workaround would only hide the compiler defect.
