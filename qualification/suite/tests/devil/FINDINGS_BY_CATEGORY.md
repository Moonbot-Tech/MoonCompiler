# Resident-Layer Findings — by Meaning

An analysis without implementation detail: what is substantively wrong, why it
is incorrect (by plain reasoning or compared with Delphi), and how important it
is for production code.

The measure of importance follows the project philosophy: a deviation is
tolerable when the form does not occur in MoonBot, Arbitrage, or pinned mORMot
and a repair damages more than it cures. But **silent corruption of a
calculation is never tolerable**—it is not a “difference from Delphi,” but a
wrong result.

---

## 1. The compiler discards work from a loop (dvl-0055)

**Status: fixed.** Strength reduction now rejects the invalid hoist, the
focused loop regression is permanent, and the AES/FIPS-197 Resident stages are
active again on Win64 and Linux.

**What was wrong.** If a repeated pass contained a loop that sent data through
a table, a production build ran that inner loop **only on the first pass**.
Thereafter it silently skipped the loop and passed the data through unchanged.

**Why this was incorrect.** Data differed on every pass because the preceding
pass changed it, so the result had to differ as well. The compiler decided the
work was repeated uselessly and removed it, but it was not repeated. This was not
“different from Delphi”—it is simply wrong: `debug`, `o1`, `o2`, and Delphi
compute correctly; only the production profile is wrong.

**How important it was.** Maximally. This is the sole class of defect the
project's philosophy does not forgive: the program does not crash or report an
error; it computes the wrong result. It was found in AES: the first round was
correct and later rounds were garbage. The garbage is **self-consistent**: what
we encrypted, we also decrypt, and everything appears to work until an exchange
with someone else.

The form is not exotic. It is used by every block cipher, table-based checksum,
transcoding, and state-table parser. MoonBot follows this pattern in exchange
request signing (`HmacSha256` in `nethelpers`) and in the Arbitrage protocol
checksum (`crc32c` in `ArbProto`).

> Caveat: I did not verify whether the defect reaches exactly these two sites;
> mORMot on x86-64 may use ASM paths untouched by the optimizer. It warrants a
> separate check because the cost there is an incorrect exchange request
> signature.

---

## 2. The same numeric cast gives a different answer (dvl-0047)

**What is wrong.** Casting an unsigned two-byte number to a four-byte number
gives the right answer when written `Integer(X)`, and the wrong answer when
written `System.Integer(X)`. The action is the same; the only difference is
whether the module name precedes the type name.

**Why this is incorrect.** A type name is a type name; qualifying its origin
changes neither the type nor the operation. Plain reasoning demands the two
spellings behave identically, and Delphi does. In our implementation, the
second spelling “loses unsignedness”: 65535 becomes −1.

**How important it is.** Narrow by itself: few people qualify the type name. But
the standard library writes it this way, causing a **comparison of two `Word`
values to return the wrong sign**. In practice, sorting an array or list of
`Word` no longer orders values ascending if it contains values above 32767.
Silently, without one complaint.

MoonBot has `Word` lists (packet numbers in MoonProto), but does not sort them,
so it does not fail immediately. The risk is deferred: any future `Word` sort
or binary search will get the wrong order.

---

## 3. Parsing an identifier from text does not work at all (dvl-0046)

**What is wrong.** The function that reads a GUID from a string accepts
**no** valid string. This is not a rare case or a domain edge—none, including
the zero identifier.

**Why this is incorrect.** The reverse conversion (writing an identifier as a
string) works. Half the contract therefore works and half does not: what we
write cannot be read back. Delphi accepts every same string without issue.

**How important it is.** Medium-high. Failure arrives as an exception rather
than a silent wrong value, so it is a parsing crash rather than data corruption.
But anything receiving a textual identifier fails: configuration, protocol, or
database. MoonBot itself calls this function in a patched FMX dialog module when
accessing system interfaces, so the path is live.

---

## 4. Splitting an empty string yields an extra element (dvl-0048)

**What is wrong.** Splitting an empty string by a separator yields one empty
part. Delphi yields zero parts.

**Why this is incorrect.** An empty string contains nothing, so there is nothing
to split. Zero parts is plain reasoning; one empty part is a phantom absent from
the input. Every other case (empty parts in the middle, at the edges, and
consecutively) matches Delphi—the degenerate input alone differs.

**How important it is.** Moderate but treacherous. Typical string parsing loops
over parts: for empty input Delphi enters the body zero times, while we enter
once with an empty string. The outcome depends on luck: an extra empty list
entry or an attempt to parse an empty field as a number. MoonBot has about
fifteen such parsers in live code; it manifests where input can be empty.

---

## 5. Boolean is not considered an enumeration (dvl-0049)

**What is wrong.** When object properties are traversed at runtime, a Boolean
property does not enter the same category as enumerations. Delphi treats Boolean
as a special case of enumeration; we use a separate category.

**Why it matters.** Code that traverses properties (serialization, settings
editor, scripting bridge) is usually written as “process integers and
enumerations alike.” In Delphi, Boolean enters that branch and is handled. In
our implementation it enters no branch and **silently drops out of traversal**:
it is neither saved, displayed, nor transferred.

**How important it is.** It depends on whether the product traverses properties
through type descriptions. There will be no error—some properties simply
disappear from the result, which is difficult to notice.

---

## 6. The string-list file was written without an encoding marker (dvl-0050, fixed)

**What was wrong.** Delphi places a three-byte UTF-8 marker at the beginning of
the file. Our new `TStringList` did not.

**Why this is incorrect.** Contents are identical but files differ. Checksum
comparison of builds under different compilers therefore fails, and a third-party
program recognizing encoding from the marker will read our file by guesswork.

**Repair.** The writer was correct; the default `WriteBOM=False` was wrong.
Initial state now matches Delphi. Explicit BOM disablement and the FPC mode that
preserves an input BOM remain available and are separately checked.

---

## 7. A string in a universal value receives the wrong form (dvl-0051, fixed)

**What is wrong.** When a string is placed in a universal value (`Variant`),
Delphi marks it as a “new-style wide string.” We mark it either as a
“system-style string” or—when it consists solely of Latin letters and digits—as
a **byte string**.

**Why this is incorrect.** A value's type must not depend on its contents. The
same semantic text acquired a different form based on its characters, so code
examining it behaved differently for different data.

The data itself remained intact: round-tripping text with Cyrillic and a
currency sign returned it character by character.

**Repair.** More than the tag was fixed. The compiler retains the Unicode meaning
of an ASCII literal when selecting the assignment operator, the RTL creates
`varUString`, and `VariantManager` compares and concatenates it without an
exception. The result subtype of concat is determined by the left string
operand; explicit `WideString` and `AnsiString` retain their Delphi subtypes.
Within an OLE `SAFEARRAY`, both Pascal-managed string subtypes are converted to
BSTR as in Delphi. One cross-compiler regression checks the complete chain in
O-/O2/O3; full Devil reaches `VarArrayOf`.

---

## 8. O2/O3 CSE conflated positive and negative zero (dvl-0053)

**What was wrong.** Negative zero was preserved in O-. In O2/O3 an adjacent
`+0.0` could replace `-0.0`, including the result of constant arithmetic.

**Physical cause.** Folding and emission were correct. Constant-node comparison
used mathematical equality, and `+0.0 = -0.0`. CSE consequently treated two
different bit values as one expression.

**Why this is not the earlier Known Issue.** The `-0.0 + +0.0` behavior in
`KNOWN_ISSUES` concerns the result of that arithmetic operation itself. This
bug was reuse of another already calculated constant and was removed without
changing arithmetic.

**What was done.** Without fast math, the sign bit is part of the identity of a
zero real constant. The focused Delphi/FPC regression checks both orders of
adjacent zeros, folded arithmetic, and runtime controls in O-/O2/O3. Status:
**fixed**.

---

## What was already known

One finding from the session—negating a comparison involving an unordered
number produced a wrong answer—**duplicated an already accepted deviation**
(`Negating an unordered float comparison` in
[Known Issues](../../../../doc/KNOWN_ISSUES.md), which explicitly
states that the repair was rejected because it would change general semantics
for a form unused by the product). The finding and its probes were removed and
the corresponding program checks were deleted.

Future rule: check [Known Issues](../../../../doc/KNOWN_ISSUES.md) before
documenting every finding. The
accepted-deviation list is not “known bugs”; it contains reasoned decisions, and
adding them again as new findings is noise.

---

## One-line conclusion

Of eight findings, one is genuinely expensive: **the compiler discards work
from a loop in the production profile**. This is not a Delphi difference but a
wrong calculation, the sole class project philosophy does not permit under any
qualification. The rest are either failure instead of work (identifier parsing)
or library-behavior differences whose importance depends on whether the form
occurs in the product.
