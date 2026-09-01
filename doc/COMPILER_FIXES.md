# MoonCompiler Fixes

This is a human-readable catalogue of MoonCompiler compiler and RTL repairs.
Each independent
repair answers four questions: what failed, where the root cause was, why the
narrow repair was selected, and which permanent repro protects it. The catalogue
is grouped by subsystem; each subsection or table row describes a separate
problem and a separate semantic commit. Links are relative and open directly in
GitHub.

Packaging and documentation changes are not listed here: they do not change
compiler semantics.
AUTOINLINE remains enabled in Release; the related defects were repaired at
their specific producer, optimizer, and lifetime sites.

## Preserving the result with an inherited Exit

An inline block temporarily hid fc_exit, because its own Exit jumps to a local
label. Consequently, SSA checks stopped seeing the caller function's
pre-existing exit and could treat a later inline path as the sole definition of
the return register.

The compiler now separately retains the inherited exit and considers it when
moving both register and reference results. This narrowly fixes root cause
#41558 without changing ordinary Exit handling.

Permanent regression tests:

- [tests/webtbs/tw41558.pp](../tests/webtbs/tw41558.pp)

## Domain of folded UInt64 arithmetic

An explicit UInt64(...) cast preserves the unsigned type, but arithmetic on two
explicitly typed UInt64 constants is folded in the signed Int64 domain—as
Delphi 12.2 does: an independent overload probe resolves UInt64*UInt64 to the
Int64 overload. An early repair preserved UInt64 through folding in every mode
and was disproved by that probe; preservation was removed for 64-bit types and
retained only for Int128/UInt128, which have no Delphi domain. The regression
locks down the restored Delphi behavior through RTTI for both forms.

Permanent regression tests:

- [tests/webtbs/tw41827.pp](../tests/webtbs/tw41827.pp)

## Respecting disabled range checks in for bounds

Constant for bounds are checked only when range checking is enabled. Under
{$R-}, explicit enum values outside the declared range remain valid, and the
loop must use the requested ordinal bounds. The regression contains all three
bound forms.

Permanent regression tests:

- [tests/webtbs/tw41678.pp](../tests/webtbs/tw41678.pp)

## Respecting disabled range checks while folding Succ

Folding Succ for enums, Char, and Boolean now carries the active range checking
state into the ordinal constant. This is the same language boundary as for for,
but a separate repair in a different compiler stage.

Permanent regression tests:

- [tests/webtbs/tw41678.pp](../tests/webtbs/tw41678.pp)

## Determining memory size after dereferencing a register parameter

A register parameter is first converted to a reference, and only then is the
width of the addressable memory determined. The address-register size is reset
only when no explicit data type exists; the ordinary instruction reader then
derives the actual operand size. This is a general invariant rather than a
one-off MOVSS patch.

Permanent regression tests:

- [tests/webtbs/tw41630.pp](../tests/webtbs/tw41630.pp)

## Constant expressions for constref

A formal constref, like an ordinary const, may bind to a constant expression.
Only valid_const was added to the existing assignment check; the absolute-view
regression passes such a source through nested constref calls.

Permanent regression tests:

- [tests/webtbs/tw41766.pp](../tests/webtbs/tw41766.pp)

## Immediate normalization when narrowing x86 operations

Arithmetic folds with MOV/MOVZX narrowed the byte/word operand, but did not
convert the constant to the new immediate domain. Under O2/O3 the assembler
received a number that did not fit the narrowed encoding.

Three equivalent paths are unified in one helper that masks only a constant and
only on actual narrowing. Equal width, widening, and register paths are
unchanged; the short machine operation is retained.

Permanent regression tests:

- [tests/test/cg/tnarrowimm1.pp](../tests/test/cg/tnarrowimm1.pp)
- [tests/webtbs/tw41480.pp](../tests/webtbs/tw41480.pp)

## Excluding generic methods from legacy VMT RTTI

A published open-generic method has no callable unspecialized body, yet the
legacy writer counted and wrote it into the method table. The VMT then contained
a reference to a nonexistent generic-template symbol, and a valid Delphi class
failed at link time.

The counting and writing predicates are now symmetric and exclude
tprocdef.is_generic, as the extended-RTTI filters already do. Ordinary
published methods and actually created specializations are unaffected.

Permanent regression tests:

- [tests/webtbs/tw41410.pp](../tests/webtbs/tw41410.pp)

## Initializing static aggregates with a custom lifecycle

Implicit finalization already handled managed static variables, but the paired
initialization callback accepted only a top-level record/object. A fixed array
of advanced records could therefore receive Finalize without Initialize.

Allowing all managed arrays would add a useless startup walk over ordinary BSS
string arrays and still miss wrappers. A single value-storage predicate was
introduced, recursive only for records, fixed arrays, and old-style objects.
Reference class/interface types are deliberately excluded. An assembly negative
control proves that a large static string array is still initialized by one
zero-fill.

Permanent regression tests:

- [tests/test/cg/tarrayinit1.pp](../tests/test/cg/tarrayinit1.pp)
- [tests/test/cg/uarrayinit1.pp](../tests/test/cg/uarrayinit1.pp)
- [tests/webtbs/tw41451.pp](../tests/webtbs/tw41451.pp)

## Preserving distinct-type identity in helper keys

The key for a record/object helper was always built from the base structure's
symbol table. Several distinct record aliases shared one key, and lookup chose
the last helper registered for any one of them.

With df_unique, the key now uses the distinct type's own identity; ordinary
aliases continue to share the structural key. Registration during parsing and
lookup use one common builder, so the second diverging producer was removed.

Permanent regression tests:

- [tests/webtbs/tw41564.pp](../tests/webtbs/tw41564.pp)

## Materializing a helper instance that is not an lvalue

A record-valued field property was marked nf_no_lvalue, but helper lookup passed
the backing field directly as hidden Self. A mutating helper could then alter
the result of reading a property, whereas an equivalent getter created a value.

The existing materialization of constants/addresses was moved into the common
consumer do_member_read and accepts nf_no_lvalue. A genuine lvalue keeps its
address; a non-lvalue follows the normal assignment into a temporary value and
normal cleanup, including managed types.

Permanent regression tests:

- [tests/webtbs/tw41589.pp](../tests/webtbs/tw41589.pp)

## Preserving the with instance during generic specialization

Implicit specialization retains the actual with target, so hidden Self is not
incorrectly rebuilt from the enclosing method. One regression covers
member-scope and global with calls.

Permanent regression tests:

- [tests/webtbs/tw41711.pp](../tests/webtbs/tw41711.pp)
- [tests/webtbs/tw41712.pp](../tests/webtbs/tw41712.pp)

## Generic-type constraints in an implementation header

A Delphi-style implementation generic routine does not repeat constraints from
the member/interface declaration. While its implementation signature is parsed,
the fresh type parameter has undefineddef, and the old check rejected it before
matching it with the already validated declaration.

Deferral is permitted only for undefined generic parameters in an implementation
header when a generic declaration with the same name and arity exists. Complete
header matching remains required; standalone unconstrained generics, generic
bodies, forwards, and mismatched headers are still rejected.

Permanent regression tests:

- [tests/webtbs/tw41770.pp](../tests/webtbs/tw41770.pp)

## Deferred VMT for partial generic specialization

A specialization whose arguments still contain enclosing-generic parameters has
no generated method bodies. Phase 2 already did not place such a definition in
pending specializations, but ncgvmt still emitted a VMT with references to
nonexistent bodies.

The existing unresolved-parameters predicate was applied to tstoreddef and uses
the same invariant to defer VMT emission. VMT layout is still built to validate
overrides in partial descendants; concrete specializations and the remaining
generic paths are unchanged.

Permanent regression tests:

- [tests/webtbs/tw41788.pp](../tests/webtbs/tw41788.pp)

## An implicit generic call under unary not

In Delphi implicit-generics mode, the parser left a generic-method name as a
bare specialization, and unary not wrapped it before parsing <T>. The angle
brackets were read as comparisons, and the valid call failed at the comma.

The ordinary factor path is unchanged. Only a bare specialization before < or [
is resolved at the same precedence level before wrapping in not; the postfix
call is also completed before the next binary operator. This preserves
not/call/and grouping and does not alter non-generic not.

Permanent regression tests:

- [tests/webtbs/tw41612b.pp](../tests/webtbs/tw41612b.pp)

## Nested implicit generic specializations

The first type argument of an inline specialization remained a bare
specialization. If it was itself generic, the parent checked an incomplete node
and the adjacent >> was read by the scanner as a shift.

Before checking the parent, only that nested bare specialization is resolved,
and it uses the same temporary type context as ordinary parsing of generic
arguments. Comparisons and shifts retain their old parsing, while nested
class/array types become valid.

Permanent regression tests:

- [tests/webtbs/tw41612c.pp](../tests/webtbs/tw41612c.pp)

## Preserving absolute storage through constant propagation

An absolute conversion is a view of backing storage. Constant propagation
entered the conversion and replaced only the backing node, turning a constant
inline argument into a numeric address instead of materialized memory.

Propagation stops at the absolute boundary, as CSE already does. This preserves
the defining assignment; ordinary temporary constants and all non-absolute
conversions remain optimization candidates.

Permanent regression tests:

- [tests/test/cg/tabsolute2.pp](../tests/test/cg/tabsolute2.pp)

## Keeping distinct absolute views in memory

An absolute variable and its backing symbol can have one register class but
different field layouts. If both are held as independent register variables,
inline partial writes operate on different snapshots and lose fields.

Different type definitions are now considered incompatible for register
promotion, and the shared storage remains in memory. The other absolute paths
are unchanged.

Permanent regression tests:

- [tests/test/cg/tabsolute1.pp](../tests/test/cg/tabsolute1.pp)

## Signed constant division below `aWord` width

When calculating the magic value for signed division, the sign contribution
remains in the operand's actual N-bit domain. The deterministic regression
checks div, mod, and reverse recomposition.

Permanent regression tests:

- [tests/test/cg/tmoddiv7.pp](../tests/test/cg/tmoddiv7.pp)

## Preserving a record field whose address escapes to an external call

A field passed as var, out, or constref is excluded from O3 field promotion: the
call needs the original storage address; otherwise it receives a temporary while
the loop continues reading a stale register.

Storage-preserving conversions are tracked by the canonical
TTypeConvNode.retains_value_location, rather than a new copy of the type
comparison. This covers same-size views and provenance after inlining without a
separate exception list.

Permanent regression tests:

- [tests/test/cg/tconstrefvirt.pp](../tests/test/cg/tconstrefvirt.pp)
- [tests/test/cg/trecordloop1.pp](../tests/test/cg/trecordloop1.pp)
- [tests/test/cg/trecordloop2.pp](../tests/test/cg/trecordloop2.pp)

## Delphi width for floating-point calculations

Floating expressions are evaluated at the target Delphi width, explicitly wider
operands are retained, untyped real literals receive Delphi width, and
intrinsics follow the measured result rules. This is a separate model of
floating-point computation; the Abs(Currency) repair is not mixed into it.

Permanent regression tests:

- [tests/test/cg/taddreal4.pp](../tests/test/cg/taddreal4.pp)
- [tests/test/cg/tintrinsicwidth1.pp](../tests/test/cg/tintrinsicwidth1.pp)

## Abs(Currency) over a scaled integer

Abs commutes with the scale of Currency, so the operation is performed directly
on the exact scaled Int64, without an intermediate floating-point value. The
same commit contains an exact model over 100000 values.

Permanent regression tests:

- [tests/test/cg/tabscurrency1.pp](../tests/test/cg/tabscurrency1.pp)

## BSF/BSR semantics for zero input

For a possibly zero input, the result no longer depends on whether a preloaded
destination survived register allocation: a zero-flag fallback is used. For a
proven nonzero input, the scan remains one instruction.

Permanent regression tests:

- [tests/test/cg/tbsx3.pp](../tests/test/cg/tbsx3.pp)

## Managed and aliased semantics during inlining

A call is not inlined when a managed by-value argument requires its own copy:
an ordinary inline temporary lives as the caller, not as the callee. Safe
read-only managed parameters remain permitted.

Ordinary managed locals (String, interface, dynamic array, and records without
custom Initialize) may be inlined: they become caller temporaries, and their
reverse-order cleanup wraps exactly the inlined body and runs on normal/Exit/
exception paths at the callee return point. A custom managed record with custom
Initialize remains outside the inliner. A native temporary is initialized in
the caller prologue, so inlining would otherwise observably move Initialize
ahead of statements before the call. This is a narrow boundary, not a general
AUTOINLINE ban for managed locals.

A const-by-reference call with non-local storage remains a call because current
CSE cannot retain that alias across mutation inside the callee. Focused tests
lock down lifecycle and aliasing.

Permanent regression tests:

- [tests/test/cg/tautoinline1.pp](../tests/test/cg/tautoinline1.pp)
- [tests/test/cg/tautoinline3.pp](../tests/test/cg/tautoinline3.pp)
- [RTL-test/semantic/inline_managed_locals_semantic.dpr](../RTL-test/semantic/inline_managed_locals_semantic.dpr)

## Wrapping folded integer arithmetic with overflow checking disabled

After AUTOINLINE, constant propagation could see a wider intermediate and report
a compile-time overflow even though unchecked runtime arithmetic must truncate
to the declared result width.

For integers under {$Q-}, the low bits are retained and a typed constant is
created; ordinary range adaptation performs the same wrap. Checked arithmetic,
pointers, and non-integer ordinals are unchanged. The regression covers +, -,
and *.

Permanent regression tests:

- [tests/test/cg/tautoinline2.pp](../tests/test/cg/tautoinline2.pp)

## Retaining an untyped storage view through inlining

An assignment-side cast from untyped var/out is a view of caller storage, so the
declared parameter size need not match the view type. AUTOINLINE replaced the
formal load with the actual argument and lost provenance; repeated type checking
then rejected valid low-level Delphi code.

A narrow flag is stored on the conversion node, copied and serialized by the
standard PPU mechanism, and considered only where formal storage already retains
the same lvalue. Typed parameters still use ordinary size checking; the O3 test
also proves that the call did not become noinline.

Permanent regression tests:

- [tests/test/cg/tautoinline4.pp](../tests/test/cg/tautoinline4.pp)

## Replacing inline parameters in hidden receiver nodes

Cross-unit autoinlining copied a qualified method call together with
call_self_node/call_vmt_node, but the common AST walker does not visit these
cached hidden trees. The consumer PPU retained the producer Self symbol without
a location, causing internal error 200109092.

During parameter replacement, only the two hidden receiver trees are visited;
the global optimizer walker is unchanged. The two-pass PPU regression is
mandatory: building in one process kept the producer symbol table alive and
masked the defect.

Permanent regression tests:

- [tests/test/cg/lab_002_unicode_const_pointer_unit.pas](../tests/test/cg/lab_002_unicode_const_pointer_unit.pas)
- [tests/test/cg/tautoinline5.pp](../tests/test/cg/tautoinline5.pp)

## x86 comparison semantics when removing a mask

The AND/CMP peephole always narrowed CMP to mask width. That is valid for
equality, but changes SF/OF/CF for relational consumers; an already narrow CMP
was also rewritten unnecessarily. The observable result was incorrect byte
extraction from a returned record with AUTOINLINE disabled.

If the original width is already covered by the mask, it is preserved. A wider
comparison is narrowed only for a nonnegative constant and only when every live
flags consumer tests equality. Otherwise AND+CMP remains; the proven fast
cmpb/cmpw/cmpl optimization is retained.

Permanent regression tests:

- [tests/test/cg/tandcmp1.pp](../tests/test/cg/tandcmp1.pp)

## Retaining the source-register definition for CMOV

In #41781, O3 silently lost every path argument: OptPass2CMOVcc replaced a late
CMOV with a constant MOV and removed its defining MOV after checking uses only
after replacement, so it missed an earlier CMOV between them.

Removal is allowed only when the source register is unused both between the
defining MOV and the transformed CMOV and afterwards. A minimal two-CMOV/Jcc
test proves the result, while the assembly control proves the valid CMOV-to-MOV
optimization remains.

Permanent regression tests:

- [tests/test/cg/tcmovliveness1.pp](../tests/test/cg/tcmovliveness1.pp)

## Defining the destination for an empty runtime set range

For a reversed runtime range, a separate destination retained stale bits because
fpc_varset_set_range returned before copying the source set. The existing copy
moved before the empty-range return: the destination is always defined before
optional mutation, with no extra work on forward and aliased paths.

Tests cover constant/runtime, checked, alias, boundary, based-set, and
cross-unit forms, including a randomized matrix.

Permanent regression tests:

- [tests/test/cg/tsetopenrange1.pp](../tests/test/cg/tsetopenrange1.pp)
- [tests/test/cg/usetopenrange1.pas](../tests/test/cg/usetopenrange1.pas)

## Retaining the type of a folded 128-bit result

Small explicit UInt128/Int128 expressions folded before the selected wide
definition reached the constant node; arithmetic, div/mod, shifts, and unary
minus collapsed to a type based on the value's magnitude.

The common fold constructor retains signed/unsigned 128-bit definitions; only
128-bit div/mod waits for the existing selection pass, and constant unary minus
receives the same Int128 as the runtime path. Cross-unit RTTI/PPU tests lock
down boundaries and neighbouring untyped/runtime forms.

Permanent regression tests:

- [tests/test/cg/tint128constfold1.pp](../tests/test/cg/tint128constfold1.pp)
- [tests/test/cg/uint128constfold1.pas](../tests/test/cg/uint128constfold1.pas)

## Retaining the code-page destination of Str

During O3 lowering of Str to a RawByteString compilerproc, the original
destination definition was erased before constant folding, so a typed
AnsiString received a CP0 header.

Across call copies and the PPU inline tree, only the destination definition
needed to build a folded AnsiString constant is retained. RawByteString CP_NONE
folds to the neutral CP0 contract of the live helper. The new payload raised the
PPU long version, and stale PPU is rejected.

Permanent regression tests:

- [tests/test/tcpstr29.pp](../tests/test/tcpstr29.pp)
- [tests/test/ucpstr29.pas](../tests/test/ucpstr29.pas)

## Delphi result width for real intrinsics

On Linux x86-64, Delphi-mode Int, Frac, Exp, Ln, Sin, Cos, ArcTan, and Sqrt
exposed x87 Extended. Overload selection and surrounding arithmetic differed
from Delphi Win64, whose computation boundary is an 8-byte Double.

The target Delphi computation type is selected while explicit CExtended is
retained; the type travels through helper lowering and the x87 result is
materialized in the declared scalar location. The checked Frac conversion with
AVX is preserved. Optimizers stay enabled; direct SSE/CExtended paths are not
rewritten.

Permanent regression tests:

- [tests/test/cg/tfracresulttype1avx2.pp](../tests/test/cg/tfracresulttype1avx2.pp)
- [tests/test/cg/tintrinsicresulttype1.pp](../tests/test/cg/tintrinsicresulttype1.pp)
- [tests/test/cg/tintrinsicresulttype1avx2.pp](../tests/test/cg/tintrinsicresulttype1avx2.pp)
- [tests/test/cg/uintrinsicresulttype1.pas](../tests/test/cg/uintrinsicresulttype1.pas)

## Retaining the checked type of a constant real intrinsic

Real-intrinsic folding recreated a result through pbestrealtype, widening the
constant after Delphi-compatible selection. An implicit CExtended to Extended
conversion likewise lost source identity before overload selection.

A folded real node is created with the already checked result definition; only
an implicit sc80 to s80 constant conversion is retained through the consumer.
Tests cover all affected intrinsics, Single/Double/Extended/CExtended, negative
controls, and separately loaded PPU constants.

Permanent regression tests:

- [tests/test/cg/tintrinsicconsttype1.pp](../tests/test/cg/tintrinsicconsttype1.pp)
- [tests/test/cg/uintrinsicconsttype1.pas](../tests/test/cg/uintrinsicconsttype1.pas)

## Retaining inline depth when copying a call

A nested recursive inline call could be copied through an initialization or
argument tree with inlinelevel reset. It repeatedly bypassed the existing growth
heuristic until the compiler exhausted the stack.

The transient inlinelevel is copied with the rest of tcallnode state.
Nonrecursive inlining remains active and machine-code-identical; tests include
#41184, branching recursion, runtime, and PPU paths.

Permanent regression tests:

- [tests/test/tinlinecopy1.pp](../tests/test/tinlinecopy1.pp)
- [tests/test/uinlinecopy1.pas](../tests/test/uinlinecopy1.pas)
- [tests/webtbf/tinlinecopyfail1.pp](../tests/webtbf/tinlinecopyfail1.pp)
- [tests/webtbs/tw41184.pp](../tests/webtbs/tw41184.pp)

## Normalizing a nested inline block before its enclosing scope

In #41456, nested inline control flow was extracted before surrounding
inline-parameter temporaries; temporary references became invalid and the
compiler raised IE 200108231. normalize pre-walked the body only for void
blocks; a value block moved first and lost its enclosing lifetime.

The body of any block is now normalized before deciding whether to extract the
enclosing value block. Runtime, boundary, callback, cross-unit, and isolated-PPU
tests lock down the boundary in O1/O2/O3.

Permanent regression tests:

- [tests/test/tinlineblock1.pp](../tests/test/tinlineblock1.pp)
- [tests/test/uinlineblock1.pas](../tests/test/uinlineblock1.pas)

## Delphi semantics of integer expressions

Arithmetic, div/mod identities, and unary signs use measured Delphi promotion
domains; narrow bitwise results remain narrow where Delphi retains them. Only
the syntax/provenance of a constant that affects overload resolution is kept;
it is serialized in PPU and cleared at parentheses, casts, and arithmetic
identities exactly as DCC64 does.

Source constants differ from constants created after inlining: source UInt64
negation follows Delphi compile-time rules, while an inline live expression
retains modular Q- behavior or runtime overflow under Q+. AUTOINLINE is not
disabled.

Permanent regression tests:

- [tests/test/cg/tcheckedneg1.pp](../tests/test/cg/tcheckedneg1.pp)
- [tests/test/cg/tcheckedneg2.pp](../tests/test/cg/tcheckedneg2.pp)
- [tests/test/cg/tcheckedneg3.pp](../tests/test/cg/tcheckedneg3.pp)
- [tests/test/cg/tcheckedneg4.pp](../tests/test/cg/tcheckedneg4.pp)
- [tests/test/cg/tcheckednegauto1.pp](../tests/test/cg/tcheckednegauto1.pp)
- [tests/test/cg/tcheckednegconst1.pp](../tests/test/cg/tcheckednegconst1.pp)
- [tests/test/cg/tcheckednegruntime1.pp](../tests/test/cg/tcheckednegruntime1.pp)
- [tests/test/cg/tdelphiconsttype1.pp](../tests/test/cg/tdelphiconsttype1.pp)
- [tests/test/cg/texplicitconst1.pp](../tests/test/cg/texplicitconst1.pp)
- [tests/test/cg/tintpromotion1.pp](../tests/test/cg/tintpromotion1.pp)
- [tests/test/cg/tmoddividentity1.pp](../tests/test/cg/tmoddividentity1.pp)
- [tests/test/cg/tmoddividentityfpc1.pp](../tests/test/cg/tmoddividentityfpc1.pp)
- [tests/test/cg/tunarysign1.pp](../tests/test/cg/tunarysign1.pp)
- [tests/test/cg/tuncheckedneg1.pp](../tests/test/cg/tuncheckedneg1.pp)
- [tests/test/cg/tuncheckedneg2.pp](../tests/test/cg/tuncheckedneg2.pp)
- [tests/test/cg/tuncheckedneg3.pp](../tests/test/cg/tuncheckedneg3.pp)
- [tests/test/cg/tuncheckedneg4.pp](../tests/test/cg/tuncheckedneg4.pp)
- [tests/test/cg/tuncheckednegauto1.pp](../tests/test/cg/tuncheckednegauto1.pp)
- [tests/test/cg/uexplicitconst1.pp](../tests/test/cg/uexplicitconst1.pp)
- [tests/test/cg/uuncheckedneg1.pas](../tests/test/cg/uuncheckedneg1.pas)
- [tests/webtbs/tw41808.pp](../tests/webtbs/tw41808.pp)

## Retaining required MOVSXD after x86 arithmetic

Sign extension is not removed after arithmetic and multi-step shifts unless the
high 32 bits are proven to be the sign extension of the low result. Existing
removal for direct moves and proven bitwise producers remains; the boundary test
reproduces conversion of a negative LongInt into a positive 64-bit value.

Permanent regression tests:

- [tests/test/cg/tmovsxdarith1.pp](../tests/test/cg/tmovsxdarith1.pp)

## Classifying 64-bit radix literals as UInt64

Delphi hexadecimal/binary patterns with the high bit set are parsed again as
UInt64, rather than negative Int64. This restores DCC overload selection and
removes false R+ diagnostics for
$8000000000000000..$FFFFFFFFFFFFFFFF. Signed literals, the FPC octal
extension, and ObjFPC are unchanged.

Permanent regression tests:

- [tests/test/cg/tu64radixliteral1.pp](../tests/test/cg/tu64radixliteral1.pp)
- [tests/test/cg/tu64radixliteralfpc1.pp](../tests/test/cg/tu64radixliteralfpc1.pp)

## Mathematical comparison of mixed Int64/UInt64

Delphi compares mixed signed/unsigned 64-bit values mathematically. The old
path converted UInt64 to Int64, so identical bit patterns could compare equal
and values above High(Int64) became negative. Only Delphi relational operators
extend both operands to signed 128-bit. FPC mode and arithmetic expressions are
unchanged.

Permanent regression tests:

- [tests/test/cg/tmixedint64compare1.pp](../tests/test/cg/tmixedint64compare1.pp)

## Retaining overflow checks when lowering Inc/Dec

The checked fallback intentionally lowers Inc/Dec to add/sub, but
create_internal marked the arithmetic internal, and codegen disables overflow
checks for it. It now builds ordinary add/sub, and nf_internal is inherited only
from an actually internal source node, as in checked Succ/Pred. Tests cover
signed and signed/unsigned 64-bit overflow.

Permanent regression tests:

- [tests/test/cg/tcheckedincdec1.pp](../tests/test/cg/tcheckedincdec1.pp)

## Normalizing `or` over `ByteBool` in Delphi mode

Delphi materializes a logical expression over ByteBool, WordBool, and LongBool
as an ordinary one-byte Boolean with value 0/1. Assigning that result back to a
C-style Boolean separately produces the ABI true representation
$ff/$ffff/$ffffffff. Previously or could preserve raw operand bits, and a
nested explicit read of storage width (Byte(ByteBool) and equivalents) was
incorrectly fused with later widening, extending every one bit over the wide
destination.

In Delphi mode the logical-expression result is now Boolean; non-Delphi modes
are unchanged. The optimizer no longer fuses an explicitly written intermediate
bool-to-int cast with outer int widening. The runtime test covers and/or/xor,
all three C-style types, expression size, assignment ABI, and explicit storage
casts, without letting constant folding hide the representation.

Permanent regression tests:

- [tests/test/cg/tbyteboolor1.pp](../tests/test/cg/tbyteboolor1.pp)

## Delphi semantics of Hi/Lo

For Word, Integer, Cardinal, Int64, and UInt64, Delphi returns the high/low byte
of the low word. FPC returned half the operand width and warned in Delphi mode.
A constant expression has a byte-sized type, while a runtime expression is
Word; the distinction is visible through SizeOf and overload resolution.
Constant folding, runtime shift, and runtime result type change only under
m_delphi; TP/FPC behavior is unaffected.

Permanent regression tests:

- [tests/test/cg/tdelphihilo1.pp](../tests/test/cg/tdelphihilo1.pp)

## Branch-exact inclusive floating selection

The min/max rewrite used one SSE intrinsic for strict and inclusive comparisons.
With equal float sources, the source branch selects different operands, visible
for +0/-0; one MINSD ordering cannot preserve both tie selection and the NaN
else path. Inclusive float selection remains a branch; the existing min/max
optimization remains for strict float and every integer case.

Permanent regression tests:

- [tests/test/cg/tfloatminselect1.pp](../tests/test/cg/tfloatminselect1.pp)

## Delphi storage and alignment for set

Delphi rounds set storage: 3 bytes to 4, 5..7 to 8, and above 8 returns to the
exact byte count. FPC already knew the 3-byte boundary but kept 5 bytes for
set of 0..32. Separately, an ordinary record/class field aligned to widened
storage, whereas Delphi gives a set field byte alignment and thus shifts all
following fields.

Only the missing Delphi-mode 5..7 rounding and byte field alignment were added.
Set base/max, packed rules, and non-Delphi modes are unchanged. The DCC64 oracle
covers sizes through 17 bytes, nonzero bases, records, arrays, class fields,
parameters, and runtime copy/membership.

Permanent regression tests:

- [tests/test/cg/tdelphisetlayout1.pp](../tests/test/cg/tdelphisetlayout1.pp)

## Reverse finalization order for managed fields

FinalizeRecordFields counted down but moved the pointer forward, so locals,
record, and object fields finalized in declaration order. The pointer now starts
after the table and decrements before each call, as in Delphi. Array-element
finalization is a separate path and remains forward.

Permanent regression tests:

- [tests/test/cg/tfinalizeorder1.pp](../tests/test/cg/tfinalizeorder1.pp)

## Lexical reverse finalization of Delphi managed locals

Classic Delphi procedure locals are destroyed in reverse declaration order. A
managed inline variable instead lives from its declaration to the end of the
enclosing lexical block, including sibling blocks, loop re-entry, Exit, Break,
Continue, exceptions, and the program body. Walking symbol tables only at
procedure exit could not represent that block lifetime.

Classic locals are emitted in reverse symbol order. A managed inline declaration
is transiently marked, initialized in place, and registers finalization through
existing defer lowering. A lexical block turns the markers into one ordinary
LIFO try/finally; procedure-wide init/fini skips that symbol, preventing early
or double cleanup. Tuple, for-in destructuring, and scoped with var use the
same helper. FPC/ObjFPC retain the former path.

An ordinary try/finally was intentional: O3 DFA does not model a parser-only
implicit finally, and that shortcut had already caused an internal error. Cost
occurs only in routines with managed inline variables and uses the supported
exception/early-exit path.

Focused tests cover classic locals, normal/exceptional exits, initializer
failure, sibling blocks, early exits, loop re-entry, custom managed records,
the program body, user defer, scoped-with, tuple declarations, and for-in
destructuring. Shared Delphi-compatible tests also pass under DCC64 12.2.

Permanent regression tests:

- [tests/test/cg/tdelphilocalfinalize1.pp](../tests/test/cg/tdelphilocalfinalize1.pp)

## Static binding of inherited inside a Delphi class helper

Delphi permits inherited inside a class helper to bind to the selected extended
class method even if Self is a descendant with an override in the same VMT slot.
The parser selected the right procdef but retained Self as a method pointer, so
codegen dispatched again through the descendant VMT.

The existing type-based inherited-call path is enabled only in Delphi mode.
ObjFPC retains its documented virtual helper dispatch.

Permanent regression tests:

- [tests/test/cg/tdelphihelperinherited1.pp](../tests/test/cg/tdelphihelperinherited1.pp)

## Delphi dialect and error result of integer Val

Delphi rejects %/& radix prefixes, does not skip a leading TAB, reports an
unsigned negative position after the minus, and retains the parsed value when
Code reports trailing input or integer overflow. FPC accepted the extra
prefixes, skipped TAB, returned another position, and zeroed the result.

The native integer helper already receives negative DestSize; this impossible
ordinary-call value is used as a Delphi-only contract bit. The common
ShortString parser immediately restores positive size and applies measured
rules. Dynamic-string wrappers use that path only for negative DestSize;
FPC/ObjFPC continue calling the prior public Val(ShortString, ...).

Permanent regression tests:

- [tests/test/cg/tdelphival1.pp](../tests/test/cg/tdelphival1.pp)

## NUL terminator in the direct integer parser

Optimized TryStrToInt/TryStrToInt64 reads UnicodeString directly from the wide
buffer instead of copying into ShortString and common Val. Originally it
accepted only digits through Length(S), so '3210'#0'ABFG' was rejected. Delphi
and the former Val treat the first #0 after digits as the end of the number;
a lone #0, sign, or radix prefix before #0 is not a number.

No preliminary pass or per-digit branch was added. Only an already found
non-digit is tested for #0 and accepted if at least one digit preceded it.
Decimal/hex overflow, trailing garbage, and the ordinary hot path are unchanged.

Permanent regression test:

- [RTL-test/semantic/integer_conversion.dpr](../RTL-test/semantic/integer_conversion.dpr)

The same cross-profile run fixed a neighbouring formatting defect: writing a
pair of decimal digits was hard-coded as PCardinal, four bytes. That matched two
Unicode Char values but overwrote two adjacent bytes in the ANSI bootstrap RTL.
The write is now typed TDecimalDigitPair, so its width automatically equals two
current Char values in both RTL profiles.

## Transferring ownership of an interface function result

A managed interface result in a hidden temporary already owns one reference.
Ordinary assignment added another one and the hidden result deliberately was not
finalized, so a wrapped result such as an interface as-cast leaked.

The existing function-result detector now sees through as and only
location-preserving implicit/internal interface conversions. A proven owned
temporary uses the move helper: the old destination is released and the
reference transferred without AddRef. Explicit casts, class-to-interface,
ordinary interface copies, and managed records stay on their old paths.

Permanent regression tests:

- [tests/test/cg/tdelphiinterfacechain1.pp](../tests/test/cg/tdelphiinterfacechain1.pp)
- [tests/test/cg/tdelphiinterfacefuncret1.pp](../tests/test/cg/tdelphiinterfacefuncret1.pp)

## Releasing an exception replaced inside finally

The legacy PSABI runtime retained a displaced exception object when finally
raised a new exception. Simply removing any earlier refcount-zero wrapper would
also be wrong: the new exception may be locally caught inside that finally,
after which the original unwind must continue.

The runtime records the exact pair of the CFA frame and next outer LSDA action
after this finally's catch-all landing pad. A new exception marks the old one
replaced only when its search phase actually reaches that action without first
meeting a local handler. In cleanup on the same CFA, only the marked wrapper is
deleted; same-object protection does not release a live object twice. Normal
finally, local typed/catch-all handlers, nested-procedure calls, and genuine
replacement are locked down independently.

Permanent regression tests:

- [tests/test/tdelphiexceptionreplace1.pp](../tests/test/tdelphiexceptionreplace1.pp)

## Static RTTI catalogue for TRttiContext.GetTypes

FPC could construct RTTI for a known PTypeInfo but not enumerate linked
application types. A project-side manual registry would duplicate Pascal
declarations and could silently miss a new type.

The compiler now marks only top-level named candidates of the current module,
asks the ordinary RTTI writer to materialize supported definitions, and places
only actually created PTypeInfo in a table. The linker combines linked-unit
tables into one executable catalogue; TRttiContext.GetTypes reads it without
runtime registration or initialization hooks. Generic templates, partial
specializations, forward/unique aliases, internal/ObjC types, and VMT-less
classes do not become false identities. Changed PPU metadata raises the PPU
version.

Permanent gates:

- qualification/suite/scripts/run_rtti_gettypes_gate.sh;
- qualification/suite/scripts/run_rtti_ppu_version_gate.sh;
- qualification/suite/scripts/run_rtti_nocall_comparison.sh.

The static x86-64 executable boundary on Linux and Win64 is locked down by the
listed runtime and PPU-version gates.

## Delphi compatibility proven by a full-scale application

These forms emerged in a large multi-module build and were then reduced to
focused tests with the exact first broken invariant.

### One identity for aliases and default namespaces

MoonBot mixes dotted Delphi unit names and legacy FPC names. Treating them as
two modules split identical generic interfaces, while PPU reuse permitted a
qualifier differently from a clean build.

The repair uses the existing unit-alias mechanism: an alias is validated, bound
to the real module, and its source qualifier restored during specialization and
PPU load. Only the lookup key is normalized; target spelling is unchanged, so
-UaFoo=Bar on a case-sensitive filesystem still opens Bar.pas. No second type
identity is created and unaliased lookup is unaffected. The permanent
qualification/suite/scripts/run_namespace_scope_gate.sh gate checks clean/PPU
reuse, shadowing, and generic specialization.

A later product repro found the reciprocal half: uses SysUtils resolved through
-UaSystem.SysUtils=SysUtils left only SysUtils visible, while Delphi also keeps
System.SysUtils. The unit symbol table registers an extra name only for
configured dotted aliases that refer to an imported short name. The physical
module, PPU, and type identity remain singular; ordinary -UaFoo=Bar gains no
new reverse visibility. Focused regression
[tmoonnamespacequalified1.pp](../tests/test/cg/tmoonnamespacequalified1.pp) and
the namespace gate check short/full qualifiers, O2/O3, and clean/PPU reuse.
Because the PPU loader clears tunitsym.module, generic replay reconnects every
source/full alias of one used module, not merely the first short symbol; a
separate generic body makes this boundary red without the repair.

### Implicit function specialization without a mandatory named type

Delphi mode had not enabled the existing FPC implicit-specialization path, so a
generic method could not infer the type of a sibling generic method. Enabling it
exposed an upstream edge: an unnamed TArray<T> from another unit has no typesym,
and inference raised internal error 2021020905 instead of comparing types.

The named-type path is unchanged. Only with typesym=nil is identity proved by
canonical definition and owner.is_generic_param; a distinct alias, different
generic parameter, or foreign definition cannot match. This is the same
definition-plus-owner invariant as adjacent array inference.

Permanent regression tests:

- [tests/test/timpfuncspez38.pp](../tests/test/timpfuncspez38.pp);
- [tests/test/uimpfuncspez38a.pp](../tests/test/uimpfuncspez38a.pp);
- [tests/test/uimpfuncspez38b.pp](../tests/test/uimpfuncspez38b.pp);
- upstream tests/webtbs/tw39677.pp and the existing implicit-specialization family.

### Retaining inherited on a helper property

The parser retained the inherited-call flag for a helper method but lost it
when the selected member was a property accessor. A helper property could
recursively invoke itself or redispatch through the active helper instead of
the base getter/setter extended class.

Only already established inherited flags are passed to the accessor; an ordinary
member-call flag is then added if needed. No other flags are copied, and
ordinary property access remains on its old path.

Permanent regression test:
[tests/test/cg/tdelphihelperinheritedproperty1.pp](../tests/test/cg/tdelphihelperinheritedproperty1.pp).
Omni separately retains the exact product TMyTrackBar.Value form, with a field
read and method write.

### Capturing an exception variable with Delphi semantics

on E: Exception lives in a temporary exception symbol table. The anonymous
routine capturer considered only normal local/parameter/block tables, so E
reached codegen without a location or crashed the O3 inliner.

The exception table is recognized by its owning procedure; every lexical
handler gets a collision-proof capturer field, the raw value is copied at entry,
and explicit reads/writes of E redirect to that field. Hidden exception
ownership is not transferred: Delphi 12.2 also destroys the object on handler
exit even if the closure outlives it. One pre-codegen invariant applies to a
procedure, program body, and unit init/fini; special static routines receive
distinct internal names.

The same form exposed another O3 defect: replacing a function-reference
parameter caused replaceparaload to lose nf_load_procvar, so a callback could
run while method/VMT/hidden-self carriers were built. The existing marker is
now retained on the replacement load. noinline was not added; AUTOINLINE stays
enabled and is checked by O3 assembly.

The permanent qualification/suite/scripts/run_exception_capture_gate.sh gate
checks O-/O2/O3, mutation of E, nested/sibling handlers, re-raise, lifetime,
callbacks, and program/unit init/fini.

### Initializing the fallback monitor manager

Generic thread initialization could leave the monitor manager as a zero record.
A late owner TMonitor after successful shutdown finalized through nil callback
DoFreeMonitorData. For a target with a fallback monitor, the existing
InitMonitor is called. This is init/fini, not a hot path; Win32/Win64 use the
platform thread unit and do not enter the branch.

Permanent regression tests:
[tests/test/tmonitorfinalize.pp](../tests/test/tmonitorfinalize.pp) and
[tests/test/umonitorfinalize.pp](../tests/test/umonitorfinalize.pp).

### Opt-in backslash handling on POSIX

MoonBot stores Delphi-style paths with backslashes. Globally recognizing
backslash as a POSIX separator would silently change every FPC program, so the
RTL offers one process-wide opt-in switch defaulting to False; the service sets
it before application initialization. Disabled state preserves old POSIX
behavior. The product probe checks ForceDirectories, stream/text I/O,
rename/delete while enabled, and literal backslash while disabled.

### Repairing existing Delphi/Unicode paths in paszlib

Real ZIP read/write in Delphi Unicode mode found two package errors: zError
wrote through a name-conflicting fallback result, and tree_ptr was indexed
without pointer math. Result is used and pointer math enabled in the unit where
indexing already occurred. The deflate/inflate algorithm and archive format are
unchanged; the product adapter passes a round trip.

### Aligning conditional identifiers with Delphi expressions and string mode

Two independent conditional-compiler forms diverged from the active ABI. A bare
unknown identifier and its unary not must evaluate False rather than become a
truthy string. Separately, an ordinary non-product source-unit transition from
DelphiUnicode to Delphi changed Char/String ABI but left UNICODE and
FPC_UNICODESTRINGS defined.

The first repair retains the unresolved-identifier marker only inside a
conditional expression and changes exactly the bare/unary-not path in Delphi
mode. The second clears Unicode defines where the ordinary scanner changes
active string mode. Conversely, product MOONCOMPILER_UNICODE_DEFAULT
intentionally retains Unicode String/Char and both defines even after
{$mode delphi}: a source-mode directive may not silently change the ABI of the
single product RTL. Comparisons, Boolean operators, unit loading, ObjFPC mode,
and explicit AnsiString/AnsiChar retain their old paths.

The permanent oracle is in omni_conditional_* units and
mode-delphi-defines-match-types inside Omni; both program by O2/O3 by seed
paths run through qualification/suite/scripts/run_forms_gate.sh on Linux and
run_forms_gate.ps1 on Win64.

### Narrow extension of the RTL/API compatibility surface

Other service-derived commits add missing Delphi surface by delegating to
existing implementations rather than copying algorithms:

| Surface | Minimal implementation and retained boundary |
|---|---|
| Variant Char/WideChar dispatch | Only these arguments use the existing managed wide-string Variant path; Win64 returns varOleStr, Linux varUString, with identical text. |
| Explicit anonymous callback cast | Const type checking is retained; codegen emits the explicitly requested value ABI and rejects incompatible modifiers. |
| Variant to distinct ordinal | df_unique layers reach the base ordinal only without a user operator, then restore the final distinct type internally. |
| Reserved member after . | A word token is accepted only in qualified-member position; declaration grammar is unchanged. |
| Unicode defines and source mode | The ordinary profile follows actual string mode; the product Unicode profile keeps Unicode ABI and defines after {$mode delphi}. |
| Nested anonymous Self | Compiler dummy Self resolves to the actual enclosing-method instance; ordinary nested routines are unchanged. |
| Inline local initialization | Reuses assignment-expression and typed-constant writers for Variant and comma-separated const arrays; frees the replay buffer on both success paths. |
| TArray.Sort/BinarySearch | Delegates to existing TArrayHelper; no second algorithm, and the upstream Int32 boundary is not hidden by a dead check. |
| Anonymous equality comparer | A Delphi function reference is retained by the delegated comparer; existing overloads are unchanged. |
| Dotted string comparers | Only dotted Delphi aliases explicitly bind to UnicodeString. |
| OleVariant to UTF-8 | Uses the existing VariantManager WideString-to-UTF8 scheme. |
| TCollection.ClearAndResetID | Performs ordinary Clear, then only this API resets the next-ID counter. |
| TStrings.KeyNames | A separate accessor retains the whole entry without a separator; otherwise it returns the key prefix. |
| DivMod(UInt64) | Unsigned division and one-time remainder reconstruction. |
| Delphi overload UIntToStr(Int64) | Signed storage is formatted through the existing QWord bit-pattern path. |

These source forms are locked down by focused tests and versioned MoonBot/Omni
gates. No change replaces a working algorithm or alters an unrelated mode.

## Repairs across the broad compiler/RTL surface

Every repair below is limited to its first broken invariant and has a permanent
executable regression.

| Defect | Repair boundary | Regression |
|---|---|---|
| Unsigned Word * Word lost zero extension on widening or Cardinal assignment of equal width under {$R+} | Visible Delphi type remains Integer; a separate marker exists only for unsigned narrow multiplication, and UInt32 is applied only when folding/converting to an unsigned target no narrower than the result | [tunsignednarrowarith1.pp](../tests/test/cg/tunsignednarrowarith1.pp) |
| Mixed signed/UInt64 operators selected the wrong domain; positive untyped literals/constants fitting UInt32 stayed signed, so valid MoonBot Max(UsedNonce, StoredNonce + 1) was ambiguous | In Delphi mode measured DCC constant-fit applies first: through High(UInt32) selects UInt64; typed Integer/Int64 and larger natural Int64 retain signed domain; the normal mixed runtime expression then remains visible Int64 | [tdelphimixeduint641.pp](../tests/test/cg/tdelphimixeduint641.pp) |
| Delphi uses expected types of an entire two-parameter signature: Pair(UInt64, UInt64 + Integer) selects UInt64 although isolated Kind(UInt64 + Integer) sees Int64 | Only on a complete ordinary-ranking tie, a Delphi-mode tie-breaker treats UInt64 parameters receiving mixed arithmetic; direct Pair(Int64, UInt64) remains ambiguous and declaration order is irrelevant | [tdelphimixeduint641.pp](../tests/test/cg/tdelphimixeduint641.pp), [delphi_mixed_uint64_pair_ambiguous.pas](../qualification/suite/tests/smoke/delphi_mixed_uint64_pair_ambiguous.pas) |
| x86-64 UInt64 mod 4294967296 attempted to encode $00000000FFFFFFFF as sign-extended 32-bit immediate and failed in the assembler | The power-of-two fast path reuses generic a_op_const_reg: encodable masks remain immediate and others materialize in a register | [tu64modpow2mask1.pp](../tests/test/cg/tu64modpow2mask1.pp) |
| Folded x86 shifts differed from instructions at large counts and lost signed result type at high bit | Only Delphi/x86 folding uses operand width, hardware count mask, and selected result definition | [tdelphix86shiftfold1.pp](../tests/test/cg/tdelphix86shiftfold1.pp) |
| A generic comparer probe dereferenced an argument before a conversion had a result type | Rejects only incomplete inline candidates; fully typed candidates retain lifetime checks | [tinlinegenericcomparer1.pp](../packages/rtl-generics/tests/tinlinegenericcomparer1.pp) |
| A concrete symbol shadowed an implicit generic of the same name before parsing <...> | Selection defers only with a registered generic candidate and specialization token | [tnestedgenericarray1.pp](../packages/rtl-generics/tests/tnestedgenericarray1.pp) |
| Capturing a managed inline variable moved storage into a capturer while lexical init/fini remained at old storage | Generated init/finalizer form a lifetime pair; on ownership transfer both markers are removed and the field is serviced by the capturer | [tcapturedinlineinterface1.pp](../tests/test/cg/tcapturedinlineinterface1.pp), [tcapturedinlineinterface2.pp](../tests/test/cg/tcapturedinlineinterface2.pp) |
| Full RTTI helper referenced a nested-generic record without requesting its RTTI | Dependency is added only in the full helper-RTTI writer that actually writes the reference | [thelpernestedgenericrtti1.pp](../tests/test/cg/thelpernestedgenericrtti1.pp) |
| Win64 pre-simplification loop unroll moved an SEH handler before detecting managed temporaries | Skips only a pre-simplification x86-64 SEH loop with exception frame; unroller and legality checks remain | [tforunrollfinally1.pp](../tests/test/cg/tforunrollfinally1.pp), [tforunrollfinally2.pp](../tests/test/cg/tforunrollfinally2.pp) |
| x86 MOV forwarding changed runtime-bound CMP into cmp reg,reg and liveness removed the bound | Forbids only the exact CMP substitution merging two registers; a broad ban was rejected after corrupt self-host A/B | [tpeepequalregloop1.pp](../tests/test/cg/tpeepequalregloop1.pp) |
| Block-scoped Delphi const after a statement gave Illegal expression or a false compile-time constant | Always creates a declaration-point read-only local; typed aggregate copies from internal static carrier and user write is forbidden | [tdelphiinlineconstruntime1.pp](../tests/test/cg/tdelphiinlineconstruntime1.pp) |
| Win64 Currency * Currency truncated product to 64 bits before dividing by 10000 | Non-reducible integer-backed path uses signed 128-bit intermediate, Delphi ties-to-even, and range check | [tdelphicurrencymul1.pp](../tests/test/cg/tdelphicurrencymul1.pp) |
| RawByteString concat/compare routed mixed code pages through system encoding, and Unicode-default product profile promoted the entire raw operation | RawByteString provenance survives folding; explicit/static raw blocks only default-Unicode promotion of an untyped literal. These concats retain bytes/dynamic CP, explicit Unicode still wins, typed AnsiString retains system-CP path; PPU version rises for the serialized flag | [tdelphirawbyteconcat1.pp](../tests/test/cg/tdelphirawbyteconcat1.pp) |
| In Unicode product RTL, TGUID.FromString(ShortString) addressed one-byte characters through two-byte PChar, so StringToGUID rejected every valid GUID | Preserves ShortString ABI and changes only the physically wrong pointer to PAnsiChar; GUID layout, hex parser, format errors, and reverse conversion remain | [tunicodeguidparse1.pp](../tests/test/cg/tunicodeguidparse1.pp), Devil dvl-0046 |
| Win64 Delphi ABI string/UnicodeString Variants were varOleStr and ASCII literal varString; after one subtype change, comparing two varUString values crashed | Assignment-operator lookup retains source AST kind, Unicode operator creates standard varUString, and common-type/compare/concat paths fully handle it; explicit WideString/AnsiString unchanged | [tdelphivariantstring1.pp](../tests/test/cg/tdelphivariantstring1.pp), Devil dvl-0051 |
| Explicit RawByteString(VariantValue) found no conversion operator and broke Unicode mORMot builds | Exact RawByteString assignment operators for Variant/OleVariant call existing VarToLStr; Delphi oracle matches AnsiString(VariantValue) ANSI-codepage result | [tdelphivariantrawbytestring1.pp](../tests/test/cg/tdelphivariantrawbytestring1.pp) |
| O2/O3 CSE treated IEEE +0.0 and -0.0 as one real constant | Constant-node equality compares the sign bit unless fast math is permitted; folding/emission, Currency, nonzero values, and explicit fast-math contract remain | [tdelphinegativezero1.pp](../tests/test/cg/tdelphinegativezero1.pp), Devil dvl-0053 |
| Non-addressable record with target died before an escaped closure read it | Materializes the rvalue once in a lexical read-only local and passes it to the ordinary capturer | [delphi_with_anonymous.pas](../qualification/suite/tests/smoke/delphi_with_anonymous.pas) |
| Addressable composite with target was copied into closure already typed and did not capture storage | Computes lvalue address once, captures pointer and base outer storage, and re-typechecks copy in nested context | [delphi_with_anonymous.pas](../qualification/suite/tests/smoke/delphi_with_anonymous.pas) |
| Delphi expects TList<T>.arrayofT as exact backing-array type | Adds public nested compile-time alias TArrayOfT; storage/layout/runtime unchanged | [delphi_tlist_arrayoft.pas](../qualification/suite/tests/smoke/delphi_tlist_arrayoft.pas) |
| TList<array of T> stopped compiling after pointer-index Exchange/Reverse optimization: PT[index] meant an inner dynamic-array index | Both reorder paths again use FItems[index]; Release without range checks remains direct addressing but type system preserves the outer generic element and nested-array lifetime | [collections_hotpaths.dpr](../RTL-test/semantic/collections_hotpaths.dpr), trackers QP-31 and SO-04 |
| Generic PPU replay lost source-unit alias and outer-token position | Symbol indexed by source spelling and canonical alias; position restored only at three replay points | [generic_alias_replay.pas](../qualification/suite/tests/smoke/generic_alias_replay.pas) |
| A non-distinct result-alias implementation diverged from generic declaration with equal definitions | After compare_rettype declaration result is reused only for non-distinct aliases; distinct/other arguments rejected | [generic_return_alias.pas](../qualification/suite/tests/smoke/generic_return_alias.pas) |
| New(Value) in assigned/passed anonymous routine parsed as FPC expression New(Type) | Before each nested body only inherited parser flags of outer assignment/call-argument context reset and are restored after; normal New(pointer-lvalue), managed init, and FPC expression form unchanged | [tdelphianonymousnew1.pp](../tests/test/cg/tdelphianonymousnew1.pp), [moonbot_inline_pointer_new.pas](../qualification/suite/fixtures/minimized/moonbot_inline_pointer_new.pas) |
| Constant set of 200..255 changed a padding byte based on unrelated source-neighbour files | Internal set always has 256 meaningful bits; when rebased, only logical 5..7 bytes copy and rounded eight-byte Delphi ABI tail is zeroed; 33rd-byte read removed | [tsetconstbase1.pp](../tests/test/cg/tsetconstbase1.pp), [run_devil_env_gate.py](../qualification/suite/scripts/run_devil_env_gate.py) |
| StaticArray[InvariantField] address was recomputed every iteration although base/index were invariant | Hoists only ordinary unpacked static array with unmanaged element and R/Q disabled; initial delta uses signed pointer domain. Any call/ASM, pointer write/escape, volatile field, or same-symbol write including alias prevents hoist; managed/checked paths remain to preserve lifetime and zero-iteration exceptions | [tloopinvariantaddr1.pp](../tests/test/cg/tloopinvariantaddr1.pp) |
| After inner-loop unroll, optimizer deemed Table[Data[I]] invariant in outer loop and AES diverged from FIPS-197 from round two | Vector expression invariant only if loop neither writes/modifies same base nor takes/releases its address and has no opaque call/ASM/pointer write; preserves actual invariant StaticArray[InvariantField] hoist while forbidding stale address | [tloopinvariantarraywrite1.pp](../tests/test/cg/tloopinvariantarraywrite1.pp), Devil dvl-0055 |
| Two O3 passes trusted direct node-DFA definitions: strength reduction hoisted mutable global/static scalar over call and missed post-inline writes; CONSTPROP moved parent-frame non-registerable local through loop, producing old product, 441 not 651, and 142 not 127 | Local/value parameter must be registerable, uncaptured, non-address-taken, nonvolatile, and without direct write. Static scalar uses one common final-tree opteffect model that sees opaque calls and post-inline writes; old node-kind scan removed. CONSTPROP moves a constant through loop only for temporary or registerable scalar | [tloopopaqueeffects1.pp](../tests/test/cg/tloopopaqueeffects1.pp), Devil optimizer-effects matrix, dvl-0060, dvl-0062 |
| Variant(Cardinal($FFFFFFF0)) to Cardinal raised overflow although varLongWord carrier was correct | Small integer carriers retain allocation-free path; exact varLongWord read directly, other Variant/OleVariant carriers enter unsigned domain immediately; string carriers follow Delphi round/modulo contract under {$Q-}{$R-} | [variant_cardinal_semantic.dpr](../RTL-test/semantic/variant_cardinal_semantic.dpr), Devil dvl-0061 |
| O3 strength reduction used source enum/subrange for initial address; guarded cursor could start outside slice, and @procedure-variable element meant code pointer | Internal address cursor separately marked, calculated in signed pointer-size domain, and requests storage address. Checked loops do not strength-reduce, retaining original range/overflow point | [tstrengthenumguard1.pp](../tests/test/cg/tstrengthenumguard1.pp), [strength_guarded_enum_semantic.dpr](../RTL-test/semantic/strength_guarded_enum_semantic.dpr) |
| O2/O3 moved +1 from fixed-array index outside retaining conversion; after insertion-sort sentinel J=-1, range(J+1) became range(J)+1 and wrote to a huge address | Constant offset moves to machine displacement only when index root itself is add/sub with no outer retaining conversion; safe direct A[I+const] folds, converted expression evaluates J+1 first | [tarrayindexoffsetconv1.pp](../tests/test/cg/tarrayindexoffsetconv1.pp), [array_index_offset_semantic.dpr](../RTL-test/semantic/array_index_offset_semantic.dpr) |
| After AUTOINLINE proven no-throw scalar code stayed inside dead try/except and hidden parameter temporary spilled due to caller handler | Post-inline simplifier uses conservative no-throw proof only for unchecked ordinal tree without calls, managed values, indirect/reference loads, delayed-temp init, division, or FP; it fully parses/checks handler first, removes dead runtime region, synchronizes procedure exception flag, and preserves every genuine access/overflow/range/division/callee handler | [tdelphiinlineexceptreg1.pp](../tests/test/cg/tdelphiinlineexceptreg1.pp), [dead_try_handler_still_checked.pas](../qualification/suite/tests/smoke/dead_try_handler_still_checked.pas) |

Delphi-compatible shift semantics also found one wrong assumption in the
mandatory MM: heap-status formatter wrote 1 shl 50 without explicit 64-bit
operand. PtrUInt(1) shl 50 changes neither allocator nor hot path and removes
only division by zero on finalization. The sole source is runtime/mm; product
and extended mORMot suites compile it through --pinned-unit.

The permanent Win64 repair gate does not rely on source repros: it runs 50
executables and ten compile-fail controls in O2/O3, 120 lines total, and inspects
assembly for SEH unroll, invariant array address, removal only of proven-dead
post-inline exception region, and absence of an extra copy of a read-only
managed function result. A separate runtime regression checks three consecutive
indexed-array mutations and forbids reuse of the address selected by first-pass
data. Provenance also hashes installed system.ppu and sysutils.ppu so an RTL
regression cannot be attributed merely to the compiler executable hash. Runtime
inline constants are checked as scalar/typed values, arrays, strings,
interfaces, records, generic methods, loop declarations, closures, and the
exact MoonBot field-expression form.

## Qualified System.Integer in Object Pascal modes

**Symptom.** Integer(Word(65535)) yielded 65535, while
System.Integer(Word(65535)) yielded -1. A deep Devil consumer showed the
production consequence: ordinary TComparer<Word> flipped the sign for
32768..65535, so TArray.Sort<Word> and binary search silently failed.

**Cause.** System has historical bootstrap alias Integer = SmallInt. In
Delphi/ObjFPC/Unleashed modes implicit ObjPas provides real language
Integer = LongInt on targets wider than 16 bits. Bare name saw ObjPas, while
qualified unit lookup returned System's two-byte symbol. Thus it was a
type-resolution defect, not codegen/comparer failure.

**Repair.** Qualified lookup normalizes exactly System.Integer, only with active
m_objpas, to signed 32-bit; a 16-bit target remains 16-bit. TP/ISO and other
System types are unchanged. The broader prototype that rewrote global System
symbol was rejected because it changed bare lookup in bootstrap builds and broke
packages.

**Validation.** tdelphiqualifiedinteger1 covers size/range, cast, declaration,
pointer, array, argument, var/out, and Word boundaries. tqualifiedintegercomparer1
checks comparer sign, sort, and binary search while preserving Byte/Cardinal/
UInt64 controls. Both run in O2/O3 in permanent Win64 repair gate; focused
execution passed O-/O2/O3. TP/ObjFPC controls confirm unchanged two-byte TP and
32-bit ObjPas semantics.

## TStringHelper.Split for an empty string

**Symptom.** ''.Split([',']) returned an array with one empty string whereas
Delphi 12.2 returns an empty array; normal for Part in Line.Split(...) therefore
ran one extra iteration only for degenerate input.

**Cause.** Both central helper implementations entered the shared loop with
LastSep = 0, whose LastSep <= Length(Self) condition treated an empty string as
one field. In Delphi, empty source is a distinct early invariant before separator
search.

**Repair.** The two master overloads, for character and string arrays, return
nil before result allocation when Self is empty. Wrappers, quote parsing,
options/count, and nonempty hot path are neither duplicated nor changed.

**Validation.** tdelphisplitempty1 passes with one source under Delphi 12.2 and
MoonCompiler, covering char/string separators, None, ExcludeEmpty,
ExcludeLastEmpty, Count, quotes, empty separator arrays, and nearby nonempty
forms. Current Win64 RTL passed O-/O2/O3; permanent repair gate is 74/74.

## Delphi-default BOM for TStrings

**Symptom.** A new TStringList saved TEncoding.UTF8 without EF BB BF, whereas
Delphi 12.2 writes a BOM by default. The difference also covered empty text:
Delphi saves one preamble while ours saved an empty stream.

**Cause.** SaveToStream(Stream, Encoding) already correctly checked WriteBOM
and wrote Encoding.GetPreamble. The initial option set was wrong: soWriteBOM
was absent and soPreserveBOM implicit. Thus a new object started
WriteBOM=False, and loading a BOM-less file fixed that outcome; Delphi starts
WriteBOM=True and does not change it while reading.

**Repair.** Initial options match Delphi: soWriteBOM, soTrailingLineBreak,
soUseLocale. Serialization and conversion path are unchanged. Explicit
WriteBOM=False still disables preamble; FPC soPreserveBOM remains explicit
opt-in for applications that must reproduce a source file's BOM.

**Validation.** tdelphistringlistbom1 runs from one source under Delphi 12.2
and MoonCompiler. It covers UTF-8/UTF-16, empty/nonempty list, explicit disable,
files with/without BOM, and FPC-control soPreserveBOM. Pre-fix exact binary
exited 1; after repair O-/O2/O3 and shared Win64 repair gate 74/74 are green.
The full self-host compiler, RTL, and package build completed with the new
toolchain.

## Unicode strings in Variant

Delphi 12.2 assigns string, UnicodeString, and ASCII/non-ASCII literals to an
ordinary Variant as varUString. MoonCompiler produced varOleStr and varString
for ASCII; changing only the tag made two varUString values fail comparison with
EVariantInvalidOpError, and VarArrayOf then failed writing varUString to Variant
SAFEARRAY with EVariantTypeCastError.

The three causes were VarFromWStr producing BSTR, overload lookup passing
nothingn and losing the rule that an untyped string literal in Delphi Unicode
mode is Unicode, and MapToCommonType not classifying supported varUString.
Actual tnodetype now reaches normal overload ranking; Unicode assignment clears
the old Variant and creates standard varUString without extending TVariantManager.
Common-type/compare/concat support it; concat preserves left subtype
varUString/varOleStr/varString. SAFEARRAY converts Pascal-managed varString and
varUString to BSTR because it cannot own Pascal strings, and Delphi returns
varOleStr from its element. On Linux WideString and UnicodeString are one RTL
type, so normal Unicode Variant remains physically varOleStr: this explicit ABI
boundary changes neither text semantics nor SAFEARRAY BSTR contract.

tdelphivariantstring1 covers variables/literals/casts, ASCII/Unicode, empty,
NUL, surrogate pair, procedure/function/property/concat, copy/overwrite/clear,
complete Unicode/Wide/Ansi concat matrix, comparison, VarArrayOf and Variant
array element write; a tiny Delphi oracle confirms SAFEARRAY subtype. RTL passes
O-/O2/O3 and full Devil proceeds past language layer without runtime crash.

## Explicit Variant to RawByteString

Legacy and supplementary mORMot use RawByteString(Value) for Variant-to-UTF-8.
MoonCompiler had AnsiString/UTF8String operators but rejected the explicit
RawByteString cast. RawByteString has distinct dynamic-codepage definition, so
the AnsiString result overload was not exact. Separate Variant/OleVariant result
operators in System RTL call existing VarToLStr; no compiler rule/path was
added. Delphi 12.2 confirms RawByteString(Variant) equals AnsiString(Variant)
in ANSI code page while UTF8String remains UTF-8.

tdelphivariantrawbytestring1 tests both Variant kinds and Ansi/UTF-8 controls
in O-/O2/O3 on Win64/Linux. It originally fixed only the Delphi cast, not whole
mORMot Unicode-default POSIX compatibility; product mORMot was later adapted:
application String/TFileName remain Unicode and raw UTF-8 appears only at POSIX
boundaries, without removing the old guard or introducing mixed ABI.

## Real-zero sign in CSE

Devil dvl-0053 was initially misdiagnosed as constant folding: -0.0 and
0.0 * -1.0 seemed to lose sign under O2/O3. O- and assembly showed correct
fold/emission; CSE replaced it with adjacent +0.0. trealconstnode equality used
mathematical equality (+0.0 = -0.0) despite noninterchangeable bits. Without
fast math, equal real zero constants now require equal signs. Arithmetic folding,
Currency, NaN/infinity, ordinary nonzero constants, and explicit fast-math
freedom remain.

Focused regression covers both neighbouring +0/-0 orders, seven folded
arithmetic forms, and runtime controls; Delphi 12.2 and MoonCompiler agree in
O-/O2/O3. Original Devil probe is fail-closed. Expanded Omni and integrated
Mega run native Win64 O2/O3 over six deterministic seeds with exact failure
sets/target oracles: 15 236 checks; 1 280 forms cross 20 integer-value sources,
eight operators, eight consumers, and eight contexts, including UInt64 +
inside overload, assignment, case, loop bound, index, nested routine, with,
try/finally, and re-entry.

## Win64 COFF bigobj 32-bit section number

Full Devil created one object with over 65 535 sections and link failed on
undefined $unwind$.... Microsoft bigobj already uses 32-bit SectionNumber, but
TCoffObjOutput.create_symbols stored objsym.objsection.index in local Word:
65536 became zero and emitted unwind section appeared missing. Only temporary
type changes to LongInt, matching existing writer. Ordinary COFF, unwind
generation, and optimization remain. run_win64_bigobj_unwind_gate.py generates
12000 actually invoked try/finally, checks header >65535 sections, and runs the
binary: pre-fix reliably undefined unwind symbol; repaired 72017 sections.

## Narrow extension after long-distance peephole

Three Devil families—narrow cast, generic-method return, and assignment in
with—could produce UInt64(Word(SmallIntValue)) =
$00000000FFFF8001 instead of $0000000000008001 in O3. with/generic only changed
AUTOINLINE/register-allocation decisions and reached one x86 peephole. The rule
removed movzx/movsx after mov narrow-constant,reg but widened early mov without
normalizing immediate. One helper masks by original 8/16/32-bit width then
performs signed/unsigned extension; no runtime instruction added. Permanent
run_devil_zeroext_gate.py reproduces seeds 1/24, 200 cases, five layers,
Debug/O1/O2/O3; 1268 checks agree and old dvl-0001/dvl-0026/dvl-0043 records
were removed from known-findings registry.

## Delphi-default stack for Win32/Win64 and Linux x86-64 TThread

Win32 and x86-64 Win64 target records inherited 16 MiB reserve while PE writers
committed 4 KiB; measured Delphi 12.2 PE32/PE32+ contract is 1 MiB reserve and
16 KiB commit, also used for StackSize=0 threads. One constants pair applies
only to system_i386_win32/system_x86_64_win64; target supplies reserve and
internal/external PE writers write commit. -Cs, {$M}, {$MAXSTACKSIZE}, and
{$MINSTACKSIZE} retain precedence; WinCE/AArch64 unchanged. 1 MiB is virtual
reserve, not physical use. qualification/win-stack-default/run.ps1 verifies PE
fields for internal/external linker and default/command-line/{$M}/explicit
min-max, runs four product binaries, and DCC32/DCC64 36.0 oracle is
1048576/16384.

Linux has no PE header: ordinary TThread.Create and size-less BeginThread use
DefaultStackSize passed by cthreads to pthread_attr_setstacksize. Product
Linux x86-64 changes it 4 MiB to 1 MiB; explicit constructor StackSize and
FPC_USE_SMALL_DEFAULTSTACKSIZE retain precedence. Main thread and third-party
raw pthread with no size retain inherited RLIMIT_STACK/pthread defaults; deeper
stack/guard stress is intentionally PB-011 in BACKLOG.md.

## Mandatory Linux x86-64 table-driven exception unwinding

Upstream enabled PSABI EH only with compiler define psabieh, producing two
normal-path cost variants and making product correctness depend on hidden driver
key. tf_use_psabieh is now unconditional Linux x86-64 ABI; build removes
-dpsabieh. Normal self-host build must define FPC_USE_PSABIEH, emit
.gcc_except_table, and use _FPC_psabieh_personality_v0; other architectures and
Win64 unchanged.

Audit also fixed frame-pointer CFI: saved nonvolatiles live in local frame, so
CFI emits after locals allocation from save_regs_ref, not as pushes before
prologue; otherwise unwind corrupts caller RBX. PSABI runtime distinguishes an
exception locally caught in finally from true replacement using LSDA action
chain/CFA, marking/deleting old refcount-zero wrapper only in latter cleanup and
never destroying same object. run_linux_psabieh_gate.sh, without PSABIEH keys,
compiles/runs O-/O1/O2/O3 normal try/except/finally, typed/catch-all, bare
reraise, managed-record/interface unwind, Exit/Break/Continue through finally,
replacement, nonvolatile restoration and thread; it separately checks ordinary
compiler error, unwind metadata, and no legacy exception-frame call on normal
path.

## Exact pin unit and cross-platform MM profile

--pinned-unit=<name>=<source> resolves exact source before PPU/package/search
lookup, so a product project containing another mORMot tree cannot rely on -Fu
order to prove which mormot.core.fpcx64mm compiled. Conflicting uses ... in is
rejected; permanent gate covers foreign source, stale PPU, ordinary unpinned
lookup, missing source, and explicit override. Under MOONBOT_MM_PROFILE_REQUIRED
bundled MM requires FPCMM_BOOSTER and FPCMM_MOONSHARD and forbids
FPCMM_DISABLE/FPCMM_STANDALONE, replacing the old unreliable GNU-ld symbol
contract on PE. Medium-arena ownership is target-independent: Linux mmap,
Win64 VirtualAlloc/VirtualQuery, one 2 MiB aligned-pool/owner lookup/
alloc-free-realloc invariant; both OS gates cover O2/O3, multiple owners,
cross-thread transfer, diagnostics.

### Safe Linux entrypoint start

The public-command audit found two independent Linux errors. A pinned dependency
inside .moonbot was excluded by service-directory filter; driver now adds passed
source root explicitly and filters only children. Separately, a program without
cthreads crashed initializing Unix because threaded RTL used allocator
per-thread path before setup. The full product prefix now inserts at FPC's early
heaptrc point: pinned MM, cthreads, cwstring, monitor manager, leaving dpr only
application units. Explicit late cmem, which previously replaced installed MM
and made diagnostic leak report live=0, now gets compile-time fatal; vanilla
opt-out and compiler-selected Valgrind/ASan retain deliberate cmem.
qualification/build-driver/project_profile_gate.py runs Debug/Release on both
OS without manual runtime units, creates actual TTask, executes TMonitor, and
requires exact cmem diagnostic in normal/diagnostic-MM; pinned-unit run.sh and
run.ps1 lock ordered prefix and vanilla/Valgrind exceptions.

## Further Devil-derived repairs

Delphi Unicode literal/source-byte/byte-string fixes retain Unicode Char/
UnicodeString for ASCII literal, folded Chr, and ASCII addition, while explicit
set of AnsiChar, typed array of AnsiChar, and RawByteString can be byte contexts;
variables/value >255 do not narrow. tdelphiunicodeliteral1 covers literal, Chr,
#$, concat, constant, vtWideChar, byte set/array, ANSI controls; case AnsiChar
is explicit byte context; tobjfpcliteralcastoverload1 locks ObjFPC. Overload
ranking now selects AnsiChar over RawByteString for any ordinal character
constant (#0, boundary/named/folded Chr); a nonconstant WideChar prefers string
against AnsiChar but exact WideChar still wins. This is common comparator repair,
covered by exact mormot_unicode_char_overload.pas and Omni litov-*.

Unicode literal now retains both codepage-decoded Unicode value and exact source
bytes: under cp1251 #$85 is U+2026/UTF-8 E2 80 A6 in Unicode but byte 85 in
RawByteString/AnsiChar array. Metadata survives concat, named constant, PPU
replay; typed AnsiChar-array creates byte context only while parsing; PPU long
version 38 to 39 rejects stale PPU. tdelphibyteconstppu1 covers #$85, concat,
RawByteString, CP1251/UTF-8/typed array before/after PPU; external-name test
tdelphiunicodeexternalname1 confirms source encoding. Unix conversion tests use
cwstring since absent Unicode manager is not frontend semantics.

Byte concat distinguishes A + #$85 (raw byte) from A + Chr($85) (Unicode
U+0085 transcodes to CP of A, ? in CP1251). Byte domain now transfers only from
typed AnsiString to literalbyte-provenance node or ASCII; PPU/named #$ constants
retain bytes, folded Chr/WideChar do ordinary transcode; tdelphibytestringconcatdomain1
and Omni cover pair, wide cast, expected codepage. ASCII AnsiString('a') +
AnsiString(RuntimeValue) no longer calls host reverse Unicode map and cannot
EAccessViolation on headless Linux.

Explicit Delphi cast between AnsiString subtypes is an equal-conversion storage
view retaining pointer/bytes/codepage header; assignment transcodes. Only that
cast path changes, not implicit conversion/ObjFPC helper; tdelphibytestringcast1
covers CP1251 to UTF8/CP866/Raw view and actual transcode. Integer/Cardinal and
Int64/UInt64 overload pairs compare complete static source range after basic
ordinal-distance tie: fitting signed selects signed otherwise unsigned, solving
dvl-0028/dvl-0039; only these pairs, not var/out/Variant/ObjFPC/other sets;
opposed parameter requirements stay ambiguous. tdelphiintpair1 covers order,
subrange, widths/boundaries and ObjFPC control.

Parser maps both Delphi const [ref] and [ref] const to existing vs_constref,
adding no parameter kind/copy/lifecycle; tdelphiconstref1 checks real managed
record address, native constref, readonly/ObjFPC fail controls. Devil runner is
fail-closed: each build stores exit code; nonzero or missing terminal digest is
runtime-failed with output tail; unit test reproduces EVariantTypeCastError
false-green. Odd(UInt64 constant) now folds uvalue and 1 rather than reading
through Int64; tmoonoddconstu641 covers high-bit, High(UInt64), signed negative,
runtime. Under {$R-}, a source ordinal-constant fixed-array index is checked in
its source signed/unsigned domain before range adaptation; late optimizer
constants are not relabelled. PPU long version 37 to 38 serializes marker;
tmoonarrayconstindex1 and array_const_index_out_of_range.pas demand exact
failure, while tarrayconstafterinline1 O3 probes -1100..1100 against independent
case oracle. Global/static storage is excluded from local CONSTPROP; locals,
parameters, compiler temps remain; tmoonconstpropglobalcalls1 checks two calls,
count/result.

## Remaining public/runtime fixes

An inline void procedure can create first managed temporary after caller entry/
exit frame is fixed, causing IE 200405231. Before substitution this exact risk
keeps ordinary call only when caller lacks implicit cleanup frame; function
result with result slot/protected caller remains inline:
tmooninlinemanagedexprfinally1.pp. TCustomAttribute.Create is public so an
empty descendant inherits parameterless constructor; tmoonattributemarker1
compiles markers on type/field/property/method. Product SysUtils exports
TProc/TFunc/TPredicate through four arguments under product define only;
scoped macros retain normal FPC generic declarations; tmoondelphicallbacktypes1
creates/calls every arity.

Product RTL inherited Delphi RTTI defaults expose public fields/attributes
without RTTI EXPLICIT. Product Rtti facade presents Boolean as
TRttiEnumerationType, tkEnumeration for TRttiType.TypeKind/TValue.Kind, while
raw PTypeInfo.Kind=tkBool/storage remain since replacing kind byte would make
TypInfo read wrong enumeration data; exact dvl-0049 boundary. rtti_gettypes.dpr
checks fields/attributes/facade/name/TValue text/Variant/array on both x86-64.
Full record RTTI now requests every type reference actually serialized for
public method result/argument and property/indexed-property (same writer
filters), not only fields; rtti_generic_dependency_types.pas and mormot
IKeyValue<Integer,Int64> repro lock it. FPC TRttiInfo.RecordAllFields now fills
out RecSize, rejects nil field RTTI and accepts set only rkEnumeration rather
than numeric rkInteger, returning nil for whole unsafe record; mormot probe and
Delphi oracle JSON cover numeric/enum set/offset/RecSize. AnsiChar constant
preserves byte provenance in Delphi Unicode mode uchar only, fixing mORMot
EF+BB+BF BOM from becoming four bytes; tdelphirawbyteconst1, exact product repro,
Omni and Linux O2/O3 mORMot cover it.

ADD/LEA folding cannot remove 32-bit ADD before 64-bit LEA because eax/rax share
super-register but constant transfer required exact subregister: correct mORMot
@PByteArray(P)[PByte(P+1)^+2] was two bytes early. Disallow when ADD is narrower
than LEA; equal/narrow transfer compares super-register. tarraypointerindexoffset1,
semantic gate and 1007 Omni lea-index-* checks cover operands, subtraction,
base, scale, High(Cardinal)+2. Function Result loop counter hidden by retaining
enum conversion let O3 hoist Table[Result] before initialization; compare actual
target storage under conversion, preserving true strength reduction/cursor;
tstrengthresultcounter1 plus semantic gate/traces including -gt and FPC #39915.

x86-64 default FPU mask is Delphi $133F x87/$1F80 SSE; SetExceptionMask still
changes process default for threads/SysResetFPU and libraries retain host mask
through IsLibrary; mORMot ffLibrary/ffPascal explicit. fpu_default_mask_semantic
checks masks, reset, thread, Inf/NaN/unordered/overflow/invalid Int64 O-/O2/O3.
Default(StaticArray) with custom Assign now recognizes exact hidden default of
matching static record array and uses aligned zero heap buffer, phased init,
finalize/ownership move and try/finally guards, preserving valid destination on
Finalize throw, unwinding partial init, overflow and zero allocation semantics;
only Win64/Linux x86-64, other assignment lowering unchanged. Pins:
tdelphidefaultarray1, default_assign_safety_semantic, Omni mem-defaultop-*,
Devil dvl-0058: value 100, direct/field/index/generic PPU, single eval,
both exception phases, 32-byte alignment, 2MiB array on 1MiB stack.

resourcestring in typed string const materializes compile-time default text then
common destination conversion. SetResourceStrings retranslation updates only
native ABI slots (Ansi classic, Unicode Unicode RTL; Linux Wide=Unicode);
cross-ABI Ansi/Win64 BSTR Wide get default but no reference slot. RTL uses
RTLString. resourcestring_typed_const_semantic covers enum arrays, standalone,
Ansi/Unicode/Wide, Format, cross-unit PPU/retranslation/Omni. nil is not an
addressable var/out overload candidate even though pointer-compatible; pointer
lvalues remain. tdelphinilvaroverload1/full MoonBot repro/Omni cover nil, typed
nil, readonly/writable constants, const, lvalue forms/out write. Ranking now
uses pure valid_for_assign(apply_effects=false) after var_para_allowed type
compatibility, avoiding AST effects from losing candidate; closes function
result/property rvalues, set literal, foreign-codepage AnsiString/untyped
formal; winner gets existing mutating ncal, open array/inline out separate.
tdelphivarrankpure1 matches DCC64 declaration orders/lvalues.

TThread gains missing parameterless Create delegating Create(False), preserving
SysCreate/platform/default-stack/AfterConstruction/lifecycle; focused tests and
Omni/Mega verify immediate/suspended/run/WaitFor. TArray adds exactly Delphi
Copy<T> Count and SourceIndex/DestIndex/Count overloads delegating helper:
ranges then same backing array, System.Move unmanaged/assignment managed, no
destination create/expand; tdelphitarraycopy1/rtl_api_array_copy DCC/Moon test.
TFile.GetSize returns GetFileAttributesEx/stat size or -1 no exception;
tdelphifilegetsize1 covers missing/empty/seven-byte/Unicode/deleted/executable
on both platform Debug/Release. for var Item: PVariant in Values now terminates
type-only parsing at in and sets bt_var_type before colon; generic named pointer,
managed string/counting route common; tdelphiforvarexplicit1/Omni/MoonBot repro.

TMemoryStream SetCapacity is protected virtual and NativeInt in product Unicode
RTL (PtrInt bootstrap), no allocation/ABI change; capacity dispatch/API tests.
SetSize restores LongInt virtual wrapper plus Int64 implementation; narrow FPC
QWord bridge permits Int64 else range error, without global ranking change;
tdelphimemorystreamsetsize1 DCC source covers overloads, virtual slots, size,
shrink/position/QWord. SysUtils TextPos PAnsiChar/PWideChar clone/lower/StrPos/
translate pointer/free in finally; nil intentionally crashes like Delphi;
tdelphitextpos1/API cover. TDictionary.IsEmpty is inline FItemsLength=0 in
TCustomDictionary, no state/counter/hot branch; test and API gate.

## By-ref custom Variant and subsequent runtime repairs

TDocVariant late-bound property is varVariant or varByRef, so
ContainsText(Doc.data.response.payload.data,'}') failed UnicodeString conversion
with EVariantError and left response time stale. Strip carrier tags before
TCustomVariantType lookup for all scalar conversion/cast/compare/binary op;
normal Variant hot path retains inline tag checks, same-custom VarAsType is copy,
nil carrier error. VarCopyNoInd now ordinary assignment; its byref source stays
forbidden/unindirected. tdelphicustomvariantbyref1 covers carriers,
ANSI/Wide/Unicode, numeric/float/currency/date/Boolean, cast/compare/binary/nil,
VarCopyNoInd; mormot probe/Omni cover JSON chain. sysvartowstr also now finally
clears temporary TVarData returned from custom CastTo, avoiding one string ref
per conversion even on partial-init exception; regression requires heap return
to baseline.

TTask.WaitForAll/Any now tracks filled count not capacity, starts WaitForAny
sentinel -1, uses one finite-timeout deadline, and protects callback registration/
unregistration/signalling with one ownership protocol; infinite/main-thread
wait no polling. task_wait_semantic covers empty/nil/already-complete/mixed,
finite/infinite, winner, exception/cancel/races Debug/O2/O3. CheckSynchronize
need is decided over entire unfinished set, not first/current task, avoiding
interactive/noninteractive callback deadlock; both orders/waits regression.
TBaseWorkerThread creates suspended, initializes FRunningEvent/pool/ID then
starts; TerminatedSet signals same startup barrier if cancelled before Execute,
without sleep/polling/repeated SetEvent; thread_pool_lifecycle_semantic covers
immediate shutdown, repeated lifecycle, clean process exit. Shared IOUtils
restores GetDirectoryRoot, timestamp accessors, directory enumerator overloads
through platform primitives but does not claim Windows Encrypt/Decrypt portable;
ioutils_api_semantic covers roots/times/missing/enumeration/errors.

URL decoder now decodes %XX into raw buffer then materializes UTF-8 once,
avoiding process-codepage corruption of %D0%96; encoder aligns Delphi
space/plus/percent/query-unsafe/invalid escapes; url_encoding_utf8_codepage_semantic
covers Unicode/high bytes/NUL/CP_UTF8 boundary. Linux JSON serializer explicitly
depends on Api.Ffi.manager/libffi for RTTI Invoke; direct nonserializer Invoke
users still name manager; rtti_invoke_product_semantic imports only serializer
and tests class/record ctor/method, managed Unicode, exception. SHA512_224/
SHA512_256 reuse SHA-512 compression/finalization with FIPS IV and truncate 28/32
bytes; rtl_api_product_semantic covers abc/HMAC key/data plus SHA-256/SHA-512,
Base64, URL, threading.

## for step, managed construction, containers, streams, and final optimizer fixes

for ... step now measures physical distance. It evaluates step once in wide
unsigned domain (64-bit, 128-bit for 128-bit counter/step), raises range error
for runtime step<=0 before bound/counter/body, then uses rotated body/latch:
dist := bits(bound)-bits(i), modular increment, one step<=dist continuation
compare. No first flag/wrap detection/checked arithmetic; Q/R disabled only for
step nodes, continue through finally reaches latch. Natural exit leaves modular
first-past, empty leaves from. loopstep serializes PPU, strength reduction and
foreach/DFA preserve it. tforstep1..15, C-002 gate, latch ASM tforsteplatchasm1
and physical semantic test cover byte 256/257/512, Word 65536, Int64/QWord/
Int128/UInt128, enum R-, downto, error order, finally continue/break, Q/R,
O3, PPU and step 0/-N diagnostics.

C-003 gives every constructed managed value/storage one finalizer on every path,
none for failed Initialize. InitializeRecord becomes phased table try/except:
field throw reverses ready prefix; custom Initialize throw finalizes auto fields
but never record Finalize. InlinedInitialize replaces array helper. Openarray
copy owns alloc+init+assign, cleans content/buffer on failure. Scalar copy uses
flag + hidden caller managed TDelphiCopyGuard, fpc_delphi_finalize_copy and
disarm protocol across callee/funclet/unwind/normal done. Inline frame puts temp
creation/zero flags outside implicit try/finally, Init/arm/Assign/body inside,
and flag-gated finalizers. Inventory says 15 product Initialize+Copy/AddRef
families nonthrowing or no destination mutation; none in mORMot-product/MoonBot.
Pins record_init_unwind_paths_semantic, aggregate_init_unwind_semantic
(custom-record-op I1;OI;F1), record_management_operators_semantic and exact
declaration/reverse/array-forward order.

C-001 CheckArraySlice(Index,Count,Total) is one nonvirtual inline primitive:
SizeUInt(Index)>SizeUInt(Total) or SizeUInt(Count)>SizeUInt(Total-Index) raises
EArgumentOutOfRangeException before trivial exits/pointer formation; no
Index+Count. It fixes Copy/Sort/BinarySearch/TList.Exchange/Move, zero-count
BinarySearch insertion Index and same-index Move shortcut. O3 four instructions
lea/cmp,jb/sub/cmp,jnb; facades delegate. ListIndexErrorMsg now retains max/name
and message List index (5) out of bounds: TList<…> object range is 0..2.
TSortedList.Add handles zero-count SearchResult correctly. array_list_span_semantic
locks DCC matrix/state/messages/comparer/insertion/first Add; intentional DCC
deviations are safe Exchange both-index checking and Copy negative-source reject.

MemoryStream/TBytesStream state machine now validates capacity/seek/write/read/
SetSize before state publication: shared overflow-safe quarter growth/block
rounding; seek candidate before FPosition; DCC full-overflow Write behavior;
negative/sign/width validation; JSONByteReader 0->16->x2, wide SetString
flush/reset, DCC interning cache/input >1MiB, zero-allocation ctor. DCC
differences are zero-count Write no-op and protected SetCapacity below Size.
memory_stream_state_semantic/json_byte_reader_semantic cover rejected transitions,
state, round trip, 16/surrogate/double flush/cache; ParseJSONValue UTF8-option
loss in CreateParser remains codec-block finding. Empty-literal equality now uses
other operand domain only for =/<>, avoiding RawUtf8 64KiB Unicode conversion;
ordering unchanged. string_empty_compare_semantic plus O3 call ban preserve
behavior/JSON 1.047x->0.659x.

AUTOINLINE unit cycle B interface->A/A implementation->B with private static
class var SymId=-2 now registers symbol in declaring module symlist before
cross-module reference; later registration does not duplicate. Repro
o3-indysecopenssl-provider runs -O2/-O2 AUTOINLINE/-O3 and prints
O3_AUTOINLINE_CYCLE_OK; old compiler EListError in AUTOINLINE modes. CONSTS now
runs only with REGVAR so -OoNOREGVAR cannot reuse persistent FP 0.5 temporary;
tconstsnoregvar1 two-dimensional Advect. Cardinal fast path matches exact VType,
so varLongWord or varByRef/array cannot read pointer bits; test covers Variant/
OleVariant changes. OleVariant QWord/Int64 now call VarToWord64/VarToInt64 in
right order; tdelphiolevariantint641 DCC boundary controls. Direct inherited
binding stays only Object Pascal helper; ordinary class property retains virtual
dispatch, tinheritedabstractproperty1 plus helper test. After inline condition
fold, constant propagation firstpasses only reachable if branch; tinlineenumguard1
checks O3 Cr false/boundary true; tmoonarrayconstindex1 remains compile-fail.

## Exact regression and oracle reference index

The following source references remain part of the permanent evidence:

- [tdelphidictionaryisempty1.pp](../packages/rtl-generics/tests/tdelphidictionaryisempty1.pp), [tdelphitarraycopy1.pp](../packages/rtl-generics/tests/tdelphitarraycopy1.pp), [moonbot_for_var_explicit_pointer.pas](../qualification/suite/fixtures/minimized/moonbot_for_var_explicit_pointer.pas), [moonbot_nil_var_overload.pas](../qualification/suite/fixtures/minimized/moonbot_nil_var_overload.pas).
- [mormot_docvariant_unicode_probe.pas](../qualification/suite/fixtures/minimized/mormot_docvariant_unicode_probe.pas), [mormot_ikeyvalue_rtti_link.pas](../qualification/suite/fixtures/minimized/mormot_ikeyvalue_rtti_link.pas), [mormot_rawbytestring_bom_const.pas](../qualification/suite/fixtures/minimized/mormot_rawbytestring_bom_const.pas), [mormot_record_fields_rtti_probe.pas](../qualification/suite/fixtures/minimized/mormot_record_fields_rtti_probe.pas), [delphi_mormot_record_fields_oracle.json](../qualification/suite/research/delphi_mormot_record_fields_oracle.json).
- [o3-indysecopenssl-provider README](../qualification/suite/tests/compiler-crash/o3-indysecopenssl-provider/README.md), [rtl_api_array_copy.dpr](../qualification/suite/tests/rtl-api/rtl_api_array_copy.dpr), [rtti_generic_dependency_types.pas](../qualification/suite/tests/rtti/rtti_generic_dependency_types.pas), [rtti_gettypes.dpr](../qualification/suite/tests/rtti/rtti_gettypes.dpr), [array_const_index_out_of_range.pas](../qualification/suite/tests/smoke/array_const_index_out_of_range.pas), [win-stack-default run.ps1](../qualification/win-stack-default/run.ps1).
- [aggregate_init_unwind_semantic.dpr](../RTL-test/semantic/aggregate_init_unwind_semantic.dpr), [array_list_span_semantic.dpr](../RTL-test/semantic/array_list_span_semantic.dpr), [array_pointer_index_offset_semantic.dpr](../RTL-test/semantic/array_pointer_index_offset_semantic.dpr), [default_assign_safety_semantic.dpr](../RTL-test/semantic/default_assign_safety_semantic.dpr), [for_counter_physical_bounds_semantic.dpr](../RTL-test/semantic/for_counter_physical_bounds_semantic.dpr), [fpu_default_mask_semantic.dpr](../RTL-test/semantic/fpu_default_mask_semantic.dpr), [ioutils_api_semantic.dpr](../RTL-test/semantic/ioutils_api_semantic.dpr), [json_byte_reader_semantic.dpr](../RTL-test/semantic/json_byte_reader_semantic.dpr), [memory_stream_state_semantic.dpr](../RTL-test/semantic/memory_stream_state_semantic.dpr), [record_init_unwind_paths_semantic.dpr](../RTL-test/semantic/record_init_unwind_paths_semantic.dpr), [record_management_operators_semantic.dpr](../RTL-test/semantic/record_management_operators_semantic.dpr), [resourcestring_typed_const_semantic.dpr](../RTL-test/semantic/resourcestring_typed_const_semantic.dpr), [rtl_api_product_semantic.dpr](../RTL-test/semantic/rtl_api_product_semantic.dpr), [rtti_invoke_product_semantic.dpr](../RTL-test/semantic/rtti_invoke_product_semantic.dpr), [strength_result_counter_semantic.dpr](../RTL-test/semantic/strength_result_counter_semantic.dpr), [string_empty_compare_semantic.dpr](../RTL-test/semantic/string_empty_compare_semantic.dpr), [task_wait_semantic.dpr](../RTL-test/semantic/task_wait_semantic.dpr), [thread_pool_lifecycle_semantic.dpr](../RTL-test/semantic/thread_pool_lifecycle_semantic.dpr), [url_encoding_utf8_codepage_semantic.dpr](../RTL-test/semantic/url_encoding_utf8_codepage_semantic.dpr).
- [tarrayconstafterinline1.pp](../tests/test/cg/tarrayconstafterinline1.pp), [tarraypointerindexoffset1.pp](../tests/test/cg/tarraypointerindexoffset1.pp), [tdelphicustomvariantbyref1.pp](../tests/test/cg/tdelphicustomvariantbyref1.pp), [tdelphidefaultarray1.pp](../tests/test/cg/tdelphidefaultarray1.pp), [tdelphifilegetsize1.pp](../tests/test/cg/tdelphifilegetsize1.pp), [tdelphiforvarexplicit1.pp](../tests/test/cg/tdelphiforvarexplicit1.pp), [tdelphimemorystreamcapacity1.pp](../tests/test/cg/tdelphimemorystreamcapacity1.pp), [tdelphimemorystreamsetsize1.pp](../tests/test/cg/tdelphimemorystreamsetsize1.pp), [tdelphinilvaroverload1.pp](../tests/test/cg/tdelphinilvaroverload1.pp), [tdelphiolevariantint641.pp](../tests/test/cg/tdelphiolevariantint641.pp), [tdelphirawbyteconst1.pp](../tests/test/cg/tdelphirawbyteconst1.pp), [tdelphitextpos1.pp](../tests/test/cg/tdelphitextpos1.pp), [tdelphivariantcardinalbyref1.pp](../tests/test/cg/tdelphivariantcardinalbyref1.pp), [tdelphivarrankpure1.pp](../tests/test/cg/tdelphivarrankpure1.pp), [tforsteplatchasm1.pp](../tests/test/cg/tforsteplatchasm1.pp), [tinheritedabstractproperty1.pp](../tests/test/cg/tinheritedabstractproperty1.pp), [tinlineenumguard1.pp](../tests/test/cg/tinlineenumguard1.pp), [tmoonarrayconstindex1.pp](../tests/test/cg/tmoonarrayconstindex1.pp), [tmoonattributemarker1.pp](../tests/test/cg/tmoonattributemarker1.pp), [tmoonconstpropglobalcalls1.pp](../tests/test/cg/tmoonconstpropglobalcalls1.pp), [tmoondelphicallbacktypes1.pp](../tests/test/cg/tmoondelphicallbacktypes1.pp), [tmooninlinemanagedexprfinally1.pp](../tests/test/cg/tmooninlinemanagedexprfinally1.pp), [tmoonoddconstu641.pp](../tests/test/cg/tmoonoddconstu641.pp), [tstrengthresultcounter1.pp](../tests/test/cg/tstrengthresultcounter1.pp), [tstrengthresultcountertrace1.pp](../tests/test/cg/tstrengthresultcountertrace1.pp), [tconstsnoregvar1.pp](../tests/test/opt/tconstsnoregvar1.pp), [tforstep9.pp](../tests/test/tforstep9.pp), and [BACKLOG.md](BACKLOG.md).
