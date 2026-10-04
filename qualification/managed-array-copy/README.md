# Managed-array copy construction

Run `python qualification/managed-array-copy/run_gate.py --compiler <compiler>
--config <product-config> --output <new-directory>` with a freshly built RTL.
The gate covers shared SetLength/Copy failures after an acquired prefix, nested
record cleanup, AddRef-only hooks and the basic guarantee of unique shrink.
It also covers Delete/Concat/append/Insert acquisition failures, unique Insert
reallocation refusal and compiler-owned Insert sources on success and unwind.
It builds 15 O-/O2/O3 images and checks 60 acquisition failures, 132 lifecycle
assertions and 8010 mutation assertions (2448 + 222 per mode). The product uses
its bundled memory manager.
