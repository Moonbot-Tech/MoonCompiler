# Memory order

The peephole optimizer of x86 moves a read of memory to the instruction which
uses the value, takes a second read of a cell from the register of the first,
merges two moves of 8 bytes into one of 16 and swaps a comparison with the move
behind it. A write which stands in between may be a write to the memory that is
read, under another name: a variable of the unit and a pointer to it, two
pointers, a field and an element, a half of a cell, a local and its address.
The gate holds both sides of the repair described in
[doc/COMPILER_FIXES.md](../../../doc/COMPILER_FIXES.md), "A read and a write of
one memory under two names".

```text
python run_memory_order_gate.py --compiler <ppcx64> --config <moon-base.cfg> --output <new-directory>
```

## Values

`generate_programs.py` writes a program of routines which read and write the
memory of the unit and one local under several names. Every routine is called
four times: with pointers which look at the cells the routine names, at their
neighbours, and elsewhere. The generator counts the values every call must give
and the sum over the memory behind it from the order of the statements: the
memory is bytes, the integer arithmetic is 64-bit and wraps, the real values are
exact binary fractions. A program prints `<NAME>_PASS` or the calls which differ.

| Family | What its routines do |
|---|---|
| `mixed` | cells of 1, 2, 4 and 8 bytes, signed and unsigned, by name and through pointers; a local read and written through its own address and through an address a called routine has kept; a 32-bit local |
| `float` | cells of `Double` by name and through pointers, integer to real and back, the bits of a real through an integer pointer |
| `step` | `Inc` and `Dec` with constants of both signs, doubling, a pointer which steps by a constant and by the value it reads |

The gate writes six programs (`mixed` 1, 2 and 11, `float` 1, `step` 1 and 2; 300
routines and 1200 calls each) to the output directory, builds them at -O1, -O2,
-O3 and -O4 and runs them. The seed of a program is its family and its number;
the same Python writes the same program.

Delphi 12.2 is not the oracle of these programs. It reads a value through a
pointer, writes the variable by its name and takes the value again from its
register; it fails calls of every family. The values of the generator are those
of -O1 of this compiler on every call.

```text
python generate_programs.py --family mixed --seed 7 --functions 300 --out <file.dpr>
```

writes one more program; a wider round is a loop over seeds.

## Shapes

`memory_order_shapes.dpr` has the routines in which the memory is certainly
another one or the order does not matter, so that the optimization stays. The
gate counts each of them in the -O3 object - instructions without padding,
calls, moves of 16 bytes - against `reference.json` of the target.

| Routine | What stays |
|---|---|
| `ShapeOtherField` | another field behind the same pointer is written: the read goes down into the multiplication |
| `ShapeOtherName` | another variable of the unit is written by its name: the same |
| `ShapeCopyRecord` | one assignment of a record of 16 bytes is a load and a store of 16 bytes |
| `THolder.WriteIfNotEmpty` | the element of an array field is read once; its index is moved to its register in front of both reads |
| `TSorter.Less` | a routine which puts its parameters into its own frame (Linux) reads the function reference from the object once |
| `ShapeReadAndStep`, `ShapeReadNumber` | a byte is read and extended by one instruction in front of the step of the pointer |

A routine that grew or lost a move of 16 bytes is red. One that shrank is
reported; `--record` writes the counts of the compiler as the reference of the
target.

## What is red

| Compiler | Result |
|---|---|
| before the repair | the values: `memory_order_mixed_1` fails 11 calls at -O3 (Win64), `memory_order_step_1` 24 at -O2 |
| the repair without the one of the mask of a value which is not used | the values: `memory_order_mixed_11` fails 5 calls at -O2 |
| the repair without the narrower conditions | the shapes: `WriteIfNotEmpty` +2, `ShapeCopyRecord` 5 instructions and no move of 16 bytes, `ShapeReadNumber` +1, on Linux `Less` +2 |
