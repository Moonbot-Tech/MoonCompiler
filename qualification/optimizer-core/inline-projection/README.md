# Borrowed fields and elements in an inline procedure

Build `tests/test/cg/tinlineborrowedprojection1.pp` with the product configuration
at `-O-`, `-O2` and `-O3` and run each executable. It prints
`INLINE_BORROWED_PROJECTION_OK`. For the native `-O3` object:

```text
objdump -dr --no-show-raw-insn tinlineborrowedprojection1.o > projection.txt
python qualification/optimizer-core/inline-projection/check_projection_object.py projection.txt
```

Use the supplied objdump on Win64, GNU objdump on Linux. Both native object
formats are covered. The ordinary field, array element, pointer and record
field reads must inline without calls, like the plain string parameter.
Before the repair, each projection falsely implied a new managed temporary
and prevented inlining into a caller without a cleanup frame.

A projection can also read from an owning function result. `OwnRecord` and
`OwnArray` must retain their existing call boundary: the scan must visit the
expression below the field or element. A compiler with that recursive visit
removed fails the object check even when this small program returns the right
values. Managed cleanup and exceptions are additionally exercised by
`tinlinefallbackbyref1.pp` and `tmoonfinallymanagedresults1.pp`.
