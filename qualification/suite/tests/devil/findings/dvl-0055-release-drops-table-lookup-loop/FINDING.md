# dvl-0055 — `release` drops a table-lookup loop after the first iteration: AES encrypts incorrectly

Found by the `resident` layer, `cipher` family: an AES block disagreed with a
known answer from FIPS-197 Appendix B. Narrowing identified an optimizer defect
that silently corrupts computation **only in the production profile**.

## What happens

An array passes through a lookup table inside an outer loop. The array is
already different on each iteration, so the result must be different as well:

```pascal
for R := 1 to 3 do
begin
  for I := 0 to 15 do
    Data[I] := Table[Data[I]];      { table substitution }
  for I := 0 to 15 do
    Data[I] := Byte(Data[I] xor Byte(R));
  { print Data }
end;
```

| | second iteration |
|---|---|
| Delphi 12.2 | `63 A2 C1 00 27 66 85 C4` |
| our `debug` | `63 A2 C1 00 27 66 85 C4` |
| our `o1` | `63 A2 C1 00 27 66 85 C4` |
| our `o2` | `63 A2 C1 00 27 66 85 C4` |
| **our `release`** | **`0F 16 19 20 2B 32 35 3C`** |

The `release` result is exactly the result of the FIRST iteration with only
`xor` applied: `0C xor 3 = 0F`, `15 xor 3 = 16`, `1A xor 3 = 19`. In other
words, the substitution loop did **not run at all** from the second iteration.

The first iteration is correct in every build, so a cursory “does it work at
all?” check will not catch the defect.

## Consequences

It was found in AES-128 rather than an invented example. The key schedule is
correct for all eleven rounds, and the first round matches FIPS-197 byte for
byte: `SubBytes`, `ShiftRows`, `MixColumns`, and `AddRoundKey` are each correct
in isolation. From the second round, `SubBytes` begins returning the first
round's result:

```
round 1  input      : 19 3D E3 BE ...   ->  SubBytes: D4 27 11 AE ...
round 2  input      : A4 9C 7F F2 ...   ->  SubBytes: D4 27 11 AE ...   <- same value
                                               expected: 49 DE D2 89 ...
```

`SBox[$A4]` is `$49`, not `$D4`. The final ciphertext is
`04 AB A4 98 …` rather than the specification's `39 25 84 1D …`.

The cipher neither crashes nor reports an error, and remains reversible with
itself: data encrypted by our release build can also be decrypted by it. The
mismatch appears only when exchanging data with any other implementation or
comparing against a reference.

## Boundaries

* only **`release`**; `debug`, `o1`, and `o2` compute correctly;
* the first outer-loop iteration is always correct; later iterations fail;
* reproduces in thirty lines with no dependency other than `SysUtils`.

## Why this is costly

Table substitution inside a repeated pass is not rare; it is the basis of a
whole class of code: block ciphers, table-driven checksums, byte recoding,
table-driven finite-state machines, and parsing through character-class tables.
Wherever such a loop sits inside another loop, a release build can compute an
incorrect result.

The silent and self-consistent nature of the error is especially dangerous: the
program does not crash, results look plausible, and inverse transformations
agree with themselves. It can only be detected using an external reference,
which is how it was found.

## Reproduction

* `probe/minrep.dpr` is the thirty-line minimal reproduction;
* `probe/aes5.dpr` + `probe/aescore.inc` is AES that prints every step of two
  rounds alongside the expected FIPS-197 values.

They build with the standard driver; the profile is selected with `-O`. The
oracle is Delphi 12.2 `dcc64` with `-U<lib\win64\release> -NSSystem`.

## What this says about coverage

The defect lives in the optimizer and manifests only on a repeated pass over
changing data. A layer that evaluates short expressions cannot see it: it has
neither an outer loop nor accumulation. It was found by a program that actually
computes and compares against a number from the standard rather than against
itself.

## Result of the fix

The first broken invariant was found in loop strength reduction. After unrolling
the inner loop, the optimizer treated `Table[Data[I]]` as invariant in the outer
loop without checking that the same loop body writes a new value to `Data[I]`.
At O3, the `Table[...]` address selected from the first iteration's data was
computed once and incorrectly reused in subsequent iterations.

The fix does not disable optimization wholesale. A vector expression may be
hoisted only when the loop neither writes nor modifies the same base, neither
takes nor releases its address, and contains no opaque call/ASM or pointer
write. Safe hoisting of `StaticArray[InvariantField]` remains checked by a
separate assembly oracle.

The permanent regression is `tests/test/cg/tloopinvariantarraywrite1.pp`: three
iterations, each dependent on the preceding data. On the pre-fix compiler, O2
passes while O3 exits with code 2; on the rebuilt exact compiler, both profiles
exit with code 0. The full AES probe again matches FIPS-197, including the
second round: `SubBytes = 49 DE D2 89 ...`, round output =
`AA 8F 5F 03 61 DD E3 EF 82 D2 4A D2 68 32 46 9A`.
