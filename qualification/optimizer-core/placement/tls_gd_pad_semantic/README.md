# TLS GD branch pad regression

Run `run_gate.py` with a Linux x86-64 MoonCompiler built with
`-dtls_threadvars`, the RTL directory built by that same compiler,
and `objdump`. It compiles 32 `threadvar` units with 0..31 inline ASM NOPs
before the read. For every object it checks both TLSGD and PLT32 relocations
against the uninterrupted 16-byte linker pattern, then links and runs a
program using the unit. Pass `--old-compiler` and `--old-rtl` to require an old broken object
and a real `TLS transition` link failure. On a Windows cross toolchain,
`--object-only` performs the object checks without linking or running.

The product compiler is built without `tls_threadvars`: it reads threadvars
through `FPC_THREADVAR_RELOCATE` and emits no TLSGD sequence, and an RTL it
built keeps its threadvars outside `.tbss`, so a TLS program does not link
against that RTL (`undefined reference to FPC_THREADVARTABLES`, or a TLS
reference against a non-TLS definition in `system.o`). The gate reports either
mismatch before linking. Build the pair in a disposable copy of the source
tree, for example an extracted `git archive`: both steps rebuild `compiler/`
and `rtl/` in place. `ide` is the IDE profile installed by `./build compiler`.

```bash
ide=<clone>/toolchain/ide
make -C <copy> compiler FPC=$ide/bin/fpc \
  OPT="-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME -dtls_threadvars -Fu$(ls -d $ide/lib/fpc/*/units/x86_64-linux/rtl)"
make -C <copy> rtl_clean FPC=<copy>/compiler/ppcx64
make -C <copy> rtl FPC=<copy>/compiler/ppcx64 \
  OPT="-O2 -dMOONCOMPILER_PRODUCT_RUNTIME -dMOONCOMPILER_VANILLA_RUNTIME -dtls_threadvars"
python3 qualification/optimizer-core/placement/tls_gd_pad_semantic/run_gate.py \
  --compiler <copy>/compiler/ppcx64 --rtl <copy>/rtl/units/x86_64-linux
```
