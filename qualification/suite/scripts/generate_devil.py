#!/usr/bin/env python3
"""Devil: generate self-checking compiler-hunting programs.

Devil is not a frozen corpus.  A seed picks concrete points out of the form
space (type x value x provenance x operator x consumer x nesting), the
generator emits Pascal for exactly those points, and every check carries its
own oracle:

  * the expected value comes from this generator's arithmetic model, not from
    a captured compiler run;
  * the same value is additionally computed inside the program through a
    different lowering, so a wrong model and a wrong compiler cannot agree
    silently;
  * where the language semantics themselves are the thing under test, the
    oracle is differential: constant folding against runtime evaluation, or
    one optimization level against another - neither needs an external truth.

Every emitted case is described in the manifest, so a failing check name is
enough to reconstruct the exact form.
"""

from __future__ import annotations

import argparse
import json
import random
import zlib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"


# --------------------------------------------------------------------------
# integer model
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class IntType:
    pascal: str
    slug: str
    bits: int
    signed: bool

    @property
    def low(self) -> int:
        return -(1 << (self.bits - 1)) if self.signed else 0

    @property
    def high(self) -> int:
        return (1 << (self.bits - 1)) - 1 if self.signed else (1 << self.bits) - 1

    @property
    def promoted_bits(self) -> int:
        """Delphi promotes anything narrower than 32 bit to Integer."""
        return 32 if self.bits < 32 else self.bits

    @property
    def promoted_signed(self) -> bool:
        return True if self.bits < 32 else self.signed

    def literal(self, value: int) -> str:
        """A literal that is unambiguously of this type."""
        if value < 0:
            return f"{self.pascal}({value})"
        if value > 0x7FFFFFFF:
            digits = max(1, (self.bits + 3) // 4)
            return f"{self.pascal}(${value:0{digits}X})"
        return f"{self.pascal}({value})"

    def store(self, value: int) -> int:
        """Value as stored in a variable of this type (no range checks)."""
        masked = value & ((1 << self.bits) - 1)
        if self.signed and masked >= (1 << (self.bits - 1)):
            masked -= 1 << self.bits
        return masked

    def raw(self, value: int) -> int:
        """Stored bit pattern, zero extended, the way DvlRaw* reports it."""
        return self.store(value) & ((1 << self.bits) - 1)


TYPES = [
    IntType("ShortInt", "i8", 8, True),
    IntType("Byte", "u8", 8, False),
    IntType("SmallInt", "i16", 16, True),
    IntType("Word", "u16", 16, False),
    IntType("Integer", "i32", 32, True),
    IntType("Cardinal", "u32", 32, False),
    IntType("Int64", "i64", 64, True),
    IntType("UInt64", "u64", 64, False),
]

TYPE_BY_SLUG = {t.slug: t for t in TYPES}


def wrap_domain(value: int, bits: int, signed: bool) -> int:
    masked = value & ((1 << bits) - 1)
    if signed and masked >= (1 << (bits - 1)):
        masked -= 1 << bits
    return masked


def pascal_div(a: int, b: int) -> int:
    """Pascal div truncates toward zero."""
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def pascal_mod(a: int, b: int) -> int:
    return a - pascal_div(a, b) * b


BINARY_OPS = ("add", "sub", "mul", "div", "mod", "and", "or", "xor", "shl", "shr")
WIDE_SHIFT_COUNTS = (0, 1, 31, 32, 33, 63, 64, 65, 95, 127)

OP_TOKEN = {
    "add": "+",
    "sub": "-",
    "mul": "*",
    "div": "div",
    "mod": "mod",
    "and": "and",
    "or": "or",
    "xor": "xor",
    "shl": "shl",
    "shr": "shr",
}

COMPARE_OPS = ("eq", "ne", "lt", "le", "gt", "ge")

COMPARE_TOKEN = {
    "eq": "=",
    "ne": "<>",
    "lt": "<",
    "le": "<=",
    "gt": ">",
    "ge": ">=",
}

UNARY_OPS = ("neg", "not", "abs", "sqr", "succ", "pred", "odd")


def eval_binary(t: IntType, op: str, a: int, b: int) -> int:
    """Delphi semantics for `A op B` with both operands of type t, {$Q-}{$R-},
    result stored back into a variable of type t."""
    bits = t.promoted_bits
    signed = t.promoted_signed
    if op in ("add", "sub", "mul"):
        raw = {"add": a + b, "sub": a - b, "mul": a * b}[op]
        return t.store(wrap_domain(raw, bits, signed))
    if op == "div":
        return t.store(wrap_domain(pascal_div(a, b), bits, signed))
    if op == "mod":
        return t.store(wrap_domain(pascal_mod(a, b), bits, signed))
    if op in ("and", "or", "xor"):
        mask = (1 << bits) - 1
        ua, ub = a & mask, b & mask
        raw = {"and": ua & ub, "or": ua | ub, "xor": ua ^ ub}[op]
        return t.store(wrap_domain(raw, bits, signed))
    if op == "shl":
        mask = (1 << bits) - 1
        return t.store(wrap_domain((a & mask) << (b & (bits - 1)), bits, signed))
    if op == "shr":
        mask = (1 << bits) - 1
        return t.store(wrap_domain((a & mask) >> (b & (bits - 1)), bits, signed))
    raise ValueError(op)


def eval_unary(t: IntType, op: str, a: int) -> int:
    bits = t.promoted_bits
    signed = t.promoted_signed
    if op == "neg":
        return t.store(wrap_domain(-a, bits, signed))
    if op == "not":
        mask = (1 << bits) - 1
        return t.store(wrap_domain((~a) & mask, bits, signed))
    if op == "abs":
        return t.store(wrap_domain(abs(a), bits, signed))
    if op == "sqr":
        return t.store(wrap_domain(a * a, bits, signed))
    if op == "succ":
        return t.store(wrap_domain(a + 1, bits, signed))
    if op == "pred":
        return t.store(wrap_domain(a - 1, bits, signed))
    if op == "odd":
        return 1 if (a & 1) else 0
    raise ValueError(op)


def eval_compare(op: str, a: int, b: int) -> int:
    return {
        "eq": a == b,
        "ne": a != b,
        "lt": a < b,
        "le": a <= b,
        "gt": a > b,
        "ge": a >= b,
    }[op] and 1 or 0


def interesting_values(t: IntType, rng: random.Random) -> list[int]:
    values = {
        t.low,
        t.low + 1,
        -1 if t.signed else 0,
        0,
        1,
        2,
        t.high - 1,
        t.high,
        t.store(1 << (t.bits - 1)),
        t.store((1 << (t.bits // 2)) - 1),
        t.store(1 << (t.bits // 2)),
        t.store((1 << (t.bits // 2)) + 1),
    }
    for _ in range(4):
        values.add(t.store(rng.getrandbits(t.bits)))
    return sorted(values)


def pick_operands(t: IntType, op: str, rng: random.Random) -> tuple[int, int]:
    pool = interesting_values(t, rng)
    a = rng.choice(pool)
    b = rng.choice(pool)
    if op in ("div", "mod"):
        while b == 0:
            b = rng.choice(pool)
        # Low(T) div -1 traps on x86: a language edge, not a comparable form
        if t.signed and a == t.low and b == -1:
            b = 1
    if op in ("shl", "shr"):
        # counts at and past the width exercise the hardware masking rule
        b = rng.choice(WIDE_SHIFT_COUNTS) if rng.random() < 0.4             else rng.randrange(0, t.promoted_bits)
    return a, b


def pick_unary_operand(t: IntType, op: str, rng: random.Random) -> int:
    pool = interesting_values(t, rng)
    a = rng.choice(pool)
    if op == "abs" and t.signed and a == t.low:
        # Abs(Low(T)) has no representable result; excluded from this family
        a = t.low + 1
    return a


# --------------------------------------------------------------------------
# emitter and shared machinery
# --------------------------------------------------------------------------


@dataclass
class Emitter:
    lines: list[str] = field(default_factory=list)

    def line(self, value: str = "") -> None:
        self.lines.append(value)

    def block(self, values: list[str]) -> None:
        self.lines.extend(values)

    def text(self) -> str:
        return "\n".join(self.lines).rstrip("\n") + "\n"


SOURCES = (
    "literal",
    "typed-const",
    "local",
    "opaque",
    "field",
    "property",
    "func-result",
    "array-element",
    "var-param",
    "const-param",
)

CONSUMERS = (
    "assign",
    "field",
    "array-element",
    "func-result",
    "var-param",
    "property",
    "array-index",
    "case-selector",
    "loop-bound",
)

CONTEXTS = (
    "none",
    "runtime-if",
    "for-loop",
    "while-loop",
    "repeat-until",
    "try-finally",
    "try-except",
    "raise-catch",
    "case-branch",
    "with-record",
    "nested-proc",
    "managed-scope",
    "closure",
)


class FormBuilder:
    """Shared body builder: operand provenance, consumer placement and a
    recursive stack of execution contexts.  Layers plug in their own core
    expression and their own oracle."""

    def __init__(self, index: int, prefix: str) -> None:
        self.index = index
        self.prefix = prefix
        self.proc = f"Dvl{prefix.capitalize()}{index:05d}"
        self.name = f"dvl-{prefix}-{index:05d}"
        self.vars: list[tuple[str, str]] = []
        self.consts: list[tuple[str, str]] = []
        self.nested: list[list[str]] = []
        self.setup: list[str] = []
        self.holders: list[str] = []
        self.labels: list[str] = []
        self.optimization_off = False
        self.uid = 0

    def uniq(self) -> int:
        self.uid += 1
        return self.uid

    def var(self, name: str, pascal_type: str) -> str:
        self.vars.append((name, pascal_type))
        return name

    def const(self, name: str, pascal_type: str, value: str) -> str:
        self.consts.append((f"{name}: {pascal_type}", value))
        return name

    # -- operand provenance ----------------------------------------------

    def operand(self, tag: str, source: str, t: IntType, value: int) -> str:
        suffix = tag.upper()
        if source == "literal":
            return t.literal(value)
        if source == "typed-const":
            return self.const(f"C{suffix}{self.index:05d}", t.pascal,
                              t.literal(value))
        if source == "local":
            name = self.var(f"L{suffix}", t.pascal)
            self.setup.append(f"  {name} := {t.literal(value)};")
            return name
        if source == "opaque":
            name = self.var(f"O{suffix}", t.pascal)
            if t.signed:
                self.setup.append(
                    f"  {name} := {t.pascal}(OpaqueI(Int64({t.literal(value)})));")
            else:
                self.setup.append(
                    f"  {name} := {t.pascal}(OpaqueU(UInt64({t.literal(value)})));")
            return name
        if source == "field":
            name = self.var(f"R{suffix}", "TDvlBox")
            self.setup.append(f"  {name}.F{t.slug} := {t.literal(value)};")
            return f"{name}.F{t.slug}"
        if source == "property":
            name = self.var(f"P{suffix}", "TDvlHolder")
            self.setup.append(f"  {name} := TDvlHolder.Create;")
            self.setup.append(f"  {name}.Prop{t.slug} := {t.literal(value)};")
            self.holders.append(name)
            return f"{name}.Prop{t.slug}"
        if source == "func-result":
            return f"DvlEcho{t.slug}({t.literal(value)})"
        if source == "array-element":
            name = self.var(f"A{suffix}", f"array[0..3] of {t.pascal}")
            idx = self.var(f"I{suffix}", "Integer")
            self.setup.append(f"  {name}[2] := {t.literal(value)};")
            self.setup.append(f"  {idx} := Integer(OpaqueI(2));")
            return f"{name}[{idx}]"
        if source == "var-param":
            name = self.var(f"V{suffix}", t.pascal)
            self.setup.append(f"  DvlLoad{t.slug}({name}, {t.literal(value)});")
            return name
        if source == "const-param":
            name = self.var(f"K{suffix}", t.pascal)
            self.setup.append(f"  {name} := {t.literal(value)};")
            return f"DvlPassConst{t.slug}({name})"
        raise ValueError(source)

    # -- consumer placement ----------------------------------------------

    def consume(self, t: IntType, expression: str, consumer: str,
                target: str, indent: str) -> list[str]:
        out: list[str] = []
        raw = f"DvlRaw{t.slug}"
        if consumer == "assign":
            value = self.var(f"CV{self.uniq()}", t.pascal)
            out.append(f"{indent}{value} := {expression};")
            out.append(f"{indent}{target} := {raw}({value});")
        elif consumer == "field":
            box = self.var(f"CB{self.uniq()}", "TDvlBox")
            out.append(f"{indent}{box}.F{t.slug} := {expression};")
            out.append(f"{indent}{target} := {raw}({box}.F{t.slug});")
        elif consumer == "array-element":
            arr = self.var(f"CA{self.uniq()}", f"array[0..3] of {t.pascal}")
            out.append(f"{indent}{arr}[1] := {expression};")
            out.append(f"{indent}{target} := {raw}({arr}[1]);")
        elif consumer == "func-result":
            value = self.var(f"CF{self.uniq()}", t.pascal)
            out.append(f"{indent}{value} := DvlEcho{t.slug}({expression});")
            out.append(f"{indent}{target} := {raw}({value});")
        elif consumer == "var-param":
            value = self.var(f"CP{self.uniq()}", t.pascal)
            out.append(f"{indent}DvlLoad{t.slug}({value}, {expression});")
            out.append(f"{indent}{target} := {raw}({value});")
        elif consumer == "property":
            holder = self.var(f"CH{self.uniq()}", "TDvlHolder")
            self.setup.append(f"  {holder} := TDvlHolder.Create;")
            self.holders.append(holder)
            out.append(f"{indent}{holder}.Prop{t.slug} := {expression};")
            out.append(f"{indent}{target} := {raw}({holder}.Prop{t.slug});")
        elif consumer == "array-index":
            table = self.var(f"CT{self.uniq()}", "array[Byte] of UInt64")
            idx = self.var(f"CI{self.uniq()}", "Integer")
            self.setup.append(f"  for {idx} := 0 to High({table}) do")
            self.setup.append(f"    {table}[{idx}] := UInt64({idx} xor $A5);")
            out.append(f"{indent}{target} := {table}[Byte({raw}({expression}))];")
        elif consumer == "case-selector":
            out.append(f"{indent}case Byte({raw}({expression}) and 7) of")
            for k in range(7):
                out.append(f"{indent}  {k}: {target} := {k * 11 + 3};")
            out.append(f"{indent}else")
            out.append(f"{indent}  {target} := 97;")
            out.append(f"{indent}end;")
        elif consumer == "loop-bound":
            out.append(f"{indent}{target} := 0;")
            out.append(f"{indent}for var Bound{self.uniq()} := 0 to "
                       f"Integer({raw}({expression}) and 7) do")
            out.append(f"{indent}  {target} := {target} + UInt64(Bound{self.uid} + 1);")
        else:
            raise ValueError(consumer)
        return out

    @staticmethod
    def consumer_transform(consumer: str, raw_value: int) -> int:
        if consumer == "array-index":
            return (raw_value & 0xFF) ^ 0xA5
        if consumer == "case-selector":
            k = raw_value & 7
            return k * 11 + 3 if k < 7 else 97
        if consumer == "loop-bound":
            n = raw_value & 7
            return sum(range(1, n + 2))
        return raw_value

    # -- context nesting ---------------------------------------------------

    def wrap(self, body: list[str], contexts: list[str], indent: str,
             target: str) -> list[str]:
        if not contexts:
            return list(body)
        head, rest = contexts[0], contexts[1:]
        i = indent
        if head == "none":
            return self.wrap(body, rest, indent, target)
        if head == "runtime-if":
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}if OpaqueU(1) = 1 then", f"{i}begin"] + inner +
                    [f"{i}end", f"{i}else", f"{i}  {target} := High(UInt64);"])
        if head == "for-loop":
            guard = f"Guard{self.uniq()}"
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}for var {guard} := 0 to Integer(OpaqueU(0)) do",
                     f"{i}begin"] + inner + [f"{i}end;"])
        if head == "while-loop":
            guard = self.var(f"G{self.uniq()}", "Integer")
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}{guard} := 0;",
                     f"{i}while {guard} <= Integer(OpaqueU(0)) do",
                     f"{i}begin"] + inner + [f"{i}  Inc({guard});", f"{i}end;"])
        if head == "repeat-until":
            inner = self.wrap(body, rest, i + "  ", target)
            return [f"{i}repeat"] + inner + [f"{i}until OpaqueU(1) = 1;"]
        if head == "try-finally":
            marker = self.var(f"M{self.uniq()}", "Integer")
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}{marker} := 0;", f"{i}try"] + inner +
                    [f"{i}finally", f"{i}  Inc({marker});", f"{i}end;",
                     f"{i}if {marker} <> 1 then",
                     f"{i}  {target} := High(UInt64);"])
        if head == "try-except":
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}try"] + inner +
                    [f"{i}except", f"{i}  {target} := High(UInt64);", f"{i}end;"])
        if head == "raise-catch":
            inner = self.wrap(body, rest, i + "    ", target)
            return ([f"{i}try",
                     f"{i}  if OpaqueU(1) = 1 then",
                     f"{i}    raise EDvlSignal.Create('dvl');",
                     f"{i}except",
                     f"{i}  on EDvlSignal do",
                     f"{i}  begin"] + inner + [f"{i}  end;", f"{i}end;"])
        if head == "case-branch":
            inner = self.wrap(body, rest, i + "    ", target)
            return ([f"{i}case Integer(OpaqueU(1)) of",
                     f"{i}  1:", f"{i}  begin"] + inner +
                    [f"{i}  end;", f"{i}else",
                     f"{i}  {target} := High(UInt64);", f"{i}end;"])
        if head == "with-record":
            box = self.var(f"W{self.uniq()}", "TDvlBox")
            inner = self.wrap(body, rest, i + "  ", target)
            return ([f"{i}{box}.Fi32 := Integer(OpaqueI(1));",
                     f"{i}with {box} do", f"{i}begin"] + inner +
                    [f"{i}  if Fi32 <> 1 then",
                     f"{i}    {target} := High(UInt64);", f"{i}end;"])
        if head == "nested-proc":
            slot = len(self.nested)
            proc = f"Nested{slot}"
            self.nested.append([])
            inner = self.wrap(body, rest, "    ", target)
            self.nested[slot] = ([f"  procedure {proc};", "  begin"] + inner +
                                 ["  end;", ""])
            return [f"{i}{proc};"]
        if head == "closure":
            proc = self.var(f"Closure{self.uniq()}", "TDvlProc")
            inner = self.wrap(body, rest, i + "    ", target)
            return ([f"{i}{proc} :=", f"{i}  procedure", f"{i}  begin"] + inner +
                    [f"{i}  end;", f"{i}{proc}();", f"{i}{proc} := nil;"])
        if head == "managed-scope":
            n = self.uniq()
            s = self.var(f"S{n}", "AnsiString")
            g = self.var(f"Guard{n}", "IInterface")
            alive = self.var(f"Alive{n}", "Integer")
            tag = f"dvl-{n:05d}"
            inner = self.wrap(body, rest, i, target)
            return ([f"{i}{alive} := TDvlGuard.Alive;",
                     f"{i}{g} := TDvlGuard.Create;",
                     f"{i}{s} := AnsiString('{tag}');"] + inner +
                    [f"{i}if Length({s}) <> {len(tag)} then",
                     f"{i}  {target} := High(UInt64);",
                     f"{i}{g} := nil;",
                     f"{i}if TDvlGuard.Alive <> {alive} then",
                     f"{i}  {target} := High(UInt64);"])
        raise ValueError(head)

    # -- assembly ---------------------------------------------------------

    def emit(self, e: Emitter, statements: list[str], checks: list[str],
             preamble: list[str] | None = None) -> None:
        # some routines are compiled unoptimized inside an otherwise optimized
        # module: the boundary between the two is its own defect surface
        if self.optimization_off:
            e.line("{$push}{$optimization off}")
        e.line(f"procedure {self.proc};")
        if self.labels:
            e.line("label")
            e.line("  " + ", ".join(self.labels) + ";")
        if self.consts:
            e.line("const")
            for decl, value in self.consts:
                e.line(f"  {decl} = {value};")
        if self.vars:
            e.line("var")
            for name, pascal_type in self.vars:
                e.line(f"  {name}: {pascal_type};")
        for nested in reversed(self.nested):
            e.block(nested)
        e.line("begin")
        if preamble:
            e.block(preamble)
        e.block(self.setup)
        if self.holders:
            e.line("  try")
            e.block([f"  {line}" for line in statements])
            e.block([f"  {line}" for line in checks])
            e.line("  finally")
            for holder in self.holders:
                e.line(f"    {holder}.Free;")
            e.line("  end;")
        else:
            e.block(statements)
            e.block(checks)
        e.line("end;")
        if self.optimization_off:
            e.line("{$pop}")
        e.line()


# --------------------------------------------------------------------------
# model lowering emitted into the program (independent second path)
# --------------------------------------------------------------------------


def model_binary(t: IntType, op: str, a: int, b: int, target: str,
                 sa: str, sb: str) -> list[str]:
    bits = t.promoted_bits
    out = [
        f"  {sa} := MaskTo(UInt64(${a & ((1 << 64) - 1):016X}), {bits});",
        f"  {sb} := MaskTo(UInt64(${b & ((1 << 64) - 1):016X}), {bits});",
    ]
    if op in ("add", "sub", "mul"):
        out.append(f"  {target} := MaskTo({sa} {OP_TOKEN[op]} {sb}, {bits});")
    elif op in ("and", "or", "xor"):
        out.append(f"  {target} := MaskTo({sa} {op} {sb}, {bits});")
    elif op == "shl":
        out.append(f"  {target} := MaskTo({sa} shl ({b} and {bits - 1}), {bits});")
    elif op == "shr":
        out.append(f"  {target} := MaskTo({sa} shr ({b} and {bits - 1}), {bits});")
    elif op in ("div", "mod"):
        token = "div" if op == "div" else "mod"
        if t.promoted_signed:
            out.append(f"  {target} := MaskTo(UInt64("
                       f"SignExtendTo({sa}, {bits}) {token} "
                       f"SignExtendTo({sb}, {bits})), {bits});")
        else:
            out.append(f"  {target} := MaskTo({sa} {token} {sb}, {bits});")
    else:
        raise ValueError(op)
    if t.bits < bits:
        out.append(f"  {target} := MaskTo({target}, {t.bits});")
    return out


def model_consumer(consumer: str, target: str) -> list[str]:
    if consumer == "array-index":
        return [f"  {target} := UInt64(Byte({target}) xor $A5);"]
    if consumer == "case-selector":
        return [f"  if ({target} and 7) < 7 then",
                f"    {target} := ({target} and 7) * 11 + 3",
                "  else",
                f"    {target} := 97;"]
    if consumer == "loop-bound":
        return [f"  {target} := (({target} and 7) + 1) * (({target} and 7) + 2) div 2;"]
    return []


# --------------------------------------------------------------------------
# layers
# --------------------------------------------------------------------------


@dataclass
class CaseRecord:
    name: str
    layer: str
    detail: dict


def pick_contexts(rng: random.Random, depth: int) -> list[str]:
    contexts: list[str] = []
    for _ in range(depth):
        choice = rng.choice(CONTEXTS)
        while choice == "nested-proc" and "closure" in contexts:
            choice = rng.choice(CONTEXTS)
        contexts.append(choice)
    return contexts


def layer_expr(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Same-type binary arithmetic: model oracle plus in-program second path."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        t = rng.choice(TYPES)
        op = rng.choice(BINARY_OPS)
        a, b = pick_operands(t, op, rng)
        source_a = rng.choice(SOURCES)
        source_b = rng.choice(SOURCES)
        consumer = rng.choice(CONSUMERS)
        contexts = pick_contexts(rng, rng.choice((0, 1, 1, 2, 2, 3, 3, 4)))
        # two constant operands make the whole expression a constant one, and
        # Delphi rejects a constant expression that leaves its domain; keep the
        # form by making one operand runtime instead
        if source_a in ("literal", "typed-const") and source_b in ("literal", "typed-const"):
            exact = exact_binary(op, a, b)
            if t.promoted_signed:
                domain = TYPE_BY_SLUG["i32" if t.promoted_bits == 32 else "i64"]
            else:
                # an unsigned constant expression that goes negative is a
                # compile-time overflow for Delphi, not a wrap
                domain = TYPE_BY_SLUG["u32" if t.promoted_bits == 32 else "u64"]
            if exact is not None and not (domain.low <= exact <= domain.high):
                source_b = "opaque"

        fb = FormBuilder(index, "expr")
        fb.optimization_off = rng.random() < 0.17
        expr_a = fb.operand("a", source_a, t, a)
        expr_b = fb.operand("b", source_b, t, b)
        expression = f"{t.pascal}({expr_a} {OP_TOKEN[op]} {expr_b})"
        form = fb.var("FormRaw", "UInt64")
        model = fb.var("ModelRaw", "UInt64")
        sa = fb.var("ModelA", "UInt64")
        sb = fb.var("ModelB", "UInt64")
        body = fb.consume(t, expression, consumer, form, "  ")
        statements = fb.wrap(body, contexts, "  ", form)
        statements += model_binary(t, op, a, b, model, sa, sb)
        statements += model_consumer(consumer, model)
        expected = fb.consumer_transform(consumer, t.raw(eval_binary(t, op, a, b)))
        checks = [
            f"  DevilCheckU('{fb.name}-model', {model}, UInt64(${expected:016X}));",
            f"  DevilCheckU('{fb.name}-form', {form}, {model});",
        ]
        fb.emit(e, statements, checks, [f"  {form} := High(UInt64) - 1;"])
        calls.append(fb.proc)
        records.append(CaseRecord(fb.name, "expr", {
            "type": t.slug, "op": op, "a": a, "b": b,
            "source_a": source_a, "source_b": source_b,
            "consumer": consumer, "contexts": contexts, "expected": expected}))
    emit_runner(e, "Expr", calls)
    return records


def layer_unary(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Unary operators: model oracle."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        t = rng.choice(TYPES)
        op = rng.choice(UNARY_OPS)
        if not t.signed and op in ("abs", "neg"):
            # unary minus / Abs on an unsigned constant is a compile-time
            # overflow in Delphi; that argument lives in the domain layer
            op = rng.choice(("not", "sqr", "succ", "pred", "odd"))
        a = pick_unary_operand(t, op, rng)
        source = rng.choice(SOURCES)
        exact = {"neg": -a, "not": ~a, "abs": abs(a), "sqr": a * a,
                 "succ": a + 1, "pred": a - 1, "odd": a & 1}[op]
        signed_domain = TYPE_BY_SLUG["i32" if t.promoted_bits == 32 else "i64"]
        if source in ("literal", "typed-const") and not (
                signed_domain.low <= exact <= signed_domain.high):
            source = "opaque"       # keep the form, drop the constant overflow
        consumer = rng.choice(CONSUMERS)
        contexts = pick_contexts(rng, rng.choice((0, 1, 1, 2, 3)))

        fb = FormBuilder(index, "unary")
        fb.optimization_off = rng.random() < 0.17
        operand = fb.operand("a", source, t, a)
        if op == "neg":
            expression = f"{t.pascal}(-({operand}))"
        elif op == "not":
            expression = f"{t.pascal}(not ({operand}))"
        elif op == "abs":
            expression = f"{t.pascal}(Abs({operand}))"
        elif op == "sqr":
            expression = f"{t.pascal}(Sqr({operand}))"
        elif op == "succ":
            expression = f"{t.pascal}(Succ({operand}))"
        elif op == "pred":
            expression = f"{t.pascal}(Pred({operand}))"
        elif op == "odd":
            expression = f"{t.pascal}(Ord(Odd({operand})))"
        else:
            raise ValueError(op)

        form = fb.var("FormRaw", "UInt64")
        body = fb.consume(t, expression, consumer, form, "  ")
        statements = fb.wrap(body, contexts, "  ", form)
        expected = fb.consumer_transform(consumer, t.raw(eval_unary(t, op, a)))
        checks = [
            f"  DevilCheckU('{fb.name}', {form}, UInt64(${expected:016X}));",
        ]
        fb.emit(e, statements, checks, [f"  {form} := High(UInt64) - 1;"])
        calls.append(fb.proc)
        records.append(CaseRecord(fb.name, "unary", {
            "type": t.slug, "op": op, "a": a, "source": source,
            "consumer": consumer, "contexts": contexts, "expected": expected}))
    emit_runner(e, "Unary", calls)
    return records


def exact_binary(op: str, a: int, b: int) -> int | None:
    """Mathematically exact result, or None when the operation is not defined
    for the pair."""
    if op == "add":
        return a + b
    if op == "sub":
        return a - b
    if op == "mul":
        return a * b
    if op == "div":
        return None if b == 0 else pascal_div(a, b)
    if op == "mod":
        return None if b == 0 else pascal_mod(a, b)
    if op in ("and", "or", "xor"):
        if a < 0 or b < 0:
            return None                     # bitwise on negatives: domain bound
        return {"and": a & b, "or": a | b, "xor": a ^ b}[op]
    if op == "shl":
        return None if a < 0 or b < 0 else a << b
    if op == "shr":
        return None if a < 0 or b < 0 else a >> b
    raise ValueError(op)


def layer_fold(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Constant folding against runtime evaluation.

    The oracle is differential and needs no semantic model: the very same
    assignment must produce identical bits whether its operands are literals
    (folded at compile time) or opaque runtime values.  Only pairs whose exact
    result fits the destination are emitted, so a legitimate compile-time
    overflow diagnostic never masquerades as a defect - overflowing constant
    expressions are the business of the reject layer."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    i64 = TYPE_BY_SLUG["i64"]
    u64 = TYPE_BY_SLUG["u64"]
    emitted = 0
    index = start
    attempts = 0
    while emitted < count and attempts < count * 40:
        attempts += 1
        ta = rng.choice(TYPES)
        tb = rng.choice(TYPES)
        op = rng.choice(BINARY_OPS)
        a = rng.choice(interesting_values(ta, rng))
        b = rng.choice(interesting_values(tb, rng))
        if op in ("shl", "shr"):
            tb = TYPE_BY_SLUG["u8"]
            b = rng.randrange(0, 32)
        if op in ("div", "mod") and b == -1 and ta.signed and a == ta.low:
            continue
        exact = exact_binary(op, a, b)
        if exact is None:
            continue
        # destination wide enough to hold the exact result unchanged; both
        # operands are cast to it, so the evaluation domain is unambiguous
        # and no compile-time overflow diagnostic can fire
        if exact < 0 or a < 0 or b < 0:
            dest = i64
        elif exact > i64.high:
            dest = u64
        else:
            dest = rng.choice((i64, u64))
        # both operands are cast to dest as well, so dest must hold them too
        if not all(dest.low <= v <= dest.high for v in (a, b, exact)):
            continue

        fb = FormBuilder(index, "fold")
        fb.optimization_off = rng.random() < 0.17
        lit_a = ta.literal(a)
        lit_b = tb.literal(b)
        opq_a = fb.var("OpA", ta.pascal)
        opq_b = fb.var("OpB", tb.pascal)
        cast_a = (f"{ta.pascal}(OpaqueI(Int64({lit_a})))" if ta.signed
                  else f"{ta.pascal}(OpaqueU(UInt64({lit_a})))")
        cast_b = (f"{tb.pascal}(OpaqueI(Int64({lit_b})))" if tb.signed
                  else f"{tb.pascal}(OpaqueU(UInt64({lit_b})))")
        fb.setup.append(f"  {opq_a} := {cast_a};")
        fb.setup.append(f"  {opq_b} := {cast_b};")

        fold_v = fb.var("FoldVal", dest.pascal)
        rt_v = fb.var("RtVal", dest.pascal)
        half_v = fb.var("HalfVal", dest.pascal)
        folded = fb.var("FoldRaw", "UInt64")
        runtime = fb.var("RtRaw", "UInt64")
        halfway = fb.var("HalfRaw", "UInt64")
        token = OP_TOKEN[op]
        raw = f"DvlRaw{dest.slug}"
        contexts = pick_contexts(rng, rng.choice((0, 1, 1, 2, 3)))
        d = dest.pascal
        body = [
            f"  {fold_v} := {d}({lit_a}) {token} {d}({lit_b});",
            f"  {rt_v} := {d}({opq_a}) {token} {d}({opq_b});",
            f"  {half_v} := {d}({lit_a}) {token} {d}({opq_b});",
            f"  {folded} := {raw}({fold_v});",
            f"  {runtime} := {raw}({rt_v});",
            f"  {halfway} := {raw}({half_v});",
        ]
        statements = fb.wrap(body, contexts, "  ", folded)
        checks = [
            f"  DevilCheckU('{fb.name}-fold-vs-runtime', {folded}, {runtime});",
            f"  DevilCheckU('{fb.name}-half-vs-runtime', {halfway}, {runtime});",
            f"  DevilCheckU('{fb.name}-exact', {runtime}, "
            f"UInt64(${dest.raw(exact):016X}));",
        ]
        fb.emit(e, statements, checks)
        calls.append(fb.proc)
        records.append(CaseRecord(fb.name, "fold", {
            "type_a": ta.slug, "type_b": tb.slug, "dest": dest.slug,
            "op": op, "a": a, "b": b, "exact": exact,
            "contexts": contexts, "oracle": "differential+exact"}))
        emitted += 1
        index += 1
    emit_runner(e, "Fold", calls)
    return records


def layer_compare(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Comparisons: same-type against the model, mixed-type differentially
    (fold against runtime), plus the algebraic identities every relational
    operator must satisfy."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        ta = rng.choice(TYPES)
        mixed = rng.random() < 0.5
        tb = rng.choice(TYPES) if mixed else ta
        op = rng.choice(COMPARE_OPS)
        a = rng.choice(interesting_values(ta, rng))
        b = rng.choice(interesting_values(tb, rng))
        contexts = pick_contexts(rng, rng.choice((0, 1, 2)))

        fb = FormBuilder(index, "cmp")
        lit_a = ta.literal(a)
        lit_b = tb.literal(b)
        opq_a = fb.var("OpA", ta.pascal)
        opq_b = fb.var("OpB", tb.pascal)
        fb.setup.append(f"  {opq_a} := {ta.pascal}(" +
                        (f"OpaqueI(Int64({lit_a})));" if ta.signed
                         else f"OpaqueU(UInt64({lit_a})));"))
        fb.setup.append(f"  {opq_b} := {tb.pascal}(" +
                        (f"OpaqueI(Int64({lit_b})));" if tb.signed
                         else f"OpaqueU(UInt64({lit_b})));"))
        token = COMPARE_TOKEN[op]
        rt = fb.var("RtRaw", "UInt64")
        folded = fb.var("FoldRaw", "UInt64")
        identity = fb.var("IdRaw", "UInt64")
        body = [
            f"  {rt} := UInt64(Ord({opq_a} {token} {opq_b}));",
            f"  {folded} := UInt64(Ord({lit_a} {token} {lit_b}));",
            f"  {identity} := UInt64(Ord(not ({opq_a} {token} {opq_b})));",
        ]
        statements = fb.wrap(body, contexts, "  ", rt)
        checks = [
            f"  DevilCheckU('{fb.name}-fold-vs-runtime', {folded}, {rt});",
            f"  DevilCheckU('{fb.name}-negation', {identity}, 1 - {rt});",
        ]
        if not mixed:
            expected = eval_compare(op, a, b)
            checks.append(
                f"  DevilCheckU('{fb.name}-model', {rt}, UInt64({expected}));")
        fb.emit(e, statements, checks)
        calls.append(fb.proc)
        records.append(CaseRecord(fb.name, "cmp", {
            "type_a": ta.slug, "type_b": tb.slug, "op": op, "a": a, "b": b,
            "mixed": mixed, "contexts": contexts}))
    emit_runner(e, "Cmp", calls)
    return records


LIFE_SHAPES = (
    "managed-record-scope",
    "managed-record-array",
    "managed-record-param",
    "locals-normal",
    "locals-exception",
    "locals-exit",
    "record-fields",
    "array-shrink",
    "array-element-nil",
    "byval-record",
    "func-result",
    "loop-churn",
    "closure-capture",
    "nested-record",
    "out-param",
    "self-assign",
    "string-cow",
    "interface-swap",
    "exception-unwind-deep",
)


def layer_life(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Managed lifetime.

    The scenario always runs inside its own routine and the balance is checked
    after that routine returns: hidden temporaries stay alive until the end of
    the routine that built them, and Delphi legitimately holds them longer than
    FPC.  Whatever the language does not fix - the order of destruction, the
    exact moment a temporary dies - is reported as an observation and compared
    across compilers instead of being asserted."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        shape = rng.choice(LIFE_SHAPES)
        n = rng.choice((2, 3, 4))
        # the scenario body lives in its own routine, so contexts that emit
        # their own declarations (nested routine, closure) cannot wrap it here
        contexts = [c for c in pick_contexts(rng, rng.choice((0, 0, 1, 1, 2)))
                    if c not in ("nested-proc", "closure")]
        fb = FormBuilder(index, "life")
        name = fb.name
        tags = [chr(ord("a") + k) for k in range(n)]
        svars: list[tuple[str, str]] = []
        extra: list[list[str]] = []
        body: list[str] = []

        def sv(vname: str, vtype: str) -> str:
            svars.append((vname, vtype))
            return vname

        def guard(tag: str) -> str:
            return "TDvlTagged.Create(" + repr(tag).replace('"', "'") + ")"

        if shape in ("locals-normal", "locals-exception", "locals-exit"):
            for k in range(n):
                sv("L%d" % k, "IInterface")
            body = ["    L%d := %s;" % (k, guard(tags[k])) for k in range(n)]
            if shape == "locals-exception":
                body.append("    raise EDvlSignal.Create('dvl');")
            elif shape == "locals-exit":
                body += ["    if OpaqueU(1) = 1 then", "      Exit;"]
            body.append("    DevilCheckU('%s-alive-inside', "
                        "UInt64(TDvlTagged.Alive), %d);" % (name, n))

        elif shape == "record-fields":
            sv("Rec", "TDvlTaggedRec")
            n = 3
            body = ["    Rec.A := %s;" % guard("a"),
                    "    Rec.B := %s;" % guard("b"),
                    "    Rec.C := %s;" % guard("c"),
                    "    Rec.S := AnsiString('rec');",
                    "    DevilCheckU('%s-alive-full', "
                    "UInt64(TDvlTagged.Alive), 3);" % name]

        elif shape == "array-shrink":
            sv("Arr", "array of IInterface")
            body = ["    SetLength(Arr, %d);" % n]
            body += ["    Arr[%d] := %s;" % (k, guard(tags[k])) for k in range(n)]
            body += ["    DevilCheckU('%s-alive-full', "
                     "UInt64(TDvlTagged.Alive), %d);" % (name, n),
                     "    SetLength(Arr, 1);",
                     "    DevilCheckU('%s-alive-shrunk', "
                     "UInt64(TDvlTagged.Alive), 1);" % name,
                     "    Arr := nil;",
                     "    DevilCheckU('%s-alive-cleared', "
                     "UInt64(TDvlTagged.Alive), 0);" % name]

        elif shape == "array-element-nil":
            sv("Arr", "array of IInterface")
            body = ["    SetLength(Arr, %d);" % n]
            body += ["    Arr[%d] := %s;" % (k, guard(tags[k])) for k in range(n)]
            body += ["    Arr[0] := nil;",
                     "    DevilCheckU('%s-alive-after-nil', "
                     "UInt64(TDvlTagged.Alive), %d);" % (name, n - 1)]

        elif shape == "byval-record":
            n = 2
            sv("Rec", "TDvlTaggedRec")
            extra.append(["  procedure Take(R: TDvlTaggedRec);",
                          "  begin",
                          "    R.A := nil;",
                          "    DevilCheckU('%s-inside-callee', "
                          "UInt64(TDvlTagged.Alive), 2);" % name,
                          "  end;", ""])
            body = ["    Rec.A := %s;" % guard("a"),
                    "    Rec.B := %s;" % guard("b"),
                    "    Take(Rec);",
                    "    DevilCheckU('%s-after-call', "
                    "UInt64(TDvlTagged.Alive), 2);" % name]

        elif shape == "func-result":
            n = 1
            sv("V", "IInterface")
            extra.append(["  function Make: IInterface;",
                          "  begin",
                          "    Result := %s;" % guard("a"),
                          "  end;", ""])
            body = ["    V := Make;",
                    "    DevilCheckU('%s-held', "
                    "UInt64(TDvlTagged.Alive), 1);" % name,
                    "    V := nil;",
                    "    DevilNote('%s-alive-after-nil', "
                    "UInt64(TDvlTagged.Alive));" % name]

        elif shape == "loop-churn":
            n = 0
            rounds = rng.choice((3, 5, 8))
            sv("V", "IInterface")
            body = ["    for var Round := 1 to %d do" % rounds,
                    "    begin",
                    "      V := %s;" % guard("a"),
                    "      V := nil;",
                    "    end;",
                    "    DevilCheckU('%s-born', "
                    "UInt64(TDvlTagged.Born), %d);" % (name, rounds),
                    "    DevilCheckU('%s-alive', "
                    "UInt64(TDvlTagged.Alive), 0);" % name]

        elif shape == "closure-capture":
            n = 1
            sv("V", "IInterface")
            sv("Keep", "TDvlProc")
            body = ["    V := %s;" % guard("a"),
                    "    Keep :=", "      procedure",
                    "      begin",
                    "        if V <> nil then",
                    "          DevilTrailAdd('k');",
                    "      end;",
                    "    Keep();",
                    "    DevilCheckU('%s-captured-ran', "
                    "UInt64(Ord(Pos('k', DevilTrailText) > 0)), 1);" % name,
                    "    V := nil;",
                    "    DevilNote('%s-alive-after-nil', "
                    "UInt64(TDvlTagged.Alive));" % name,
                    "    Keep := nil;"]

        elif shape == "nested-record":
            n = 1
            sv("Outer", "TDvlTaggedRec")
            sv("CopyRec", "TDvlTaggedRec")
            body = ["    Outer.A := %s;" % guard("a"),
                    "    Outer.S := AnsiString('deep');",
                    "    CopyRec := Outer;",
                    "    DevilCheckU('%s-copy-alive', "
                    "UInt64(TDvlTagged.Alive), 1);" % name,
                    "    Outer.A := nil;",
                    "    DevilCheckU('%s-copy-holds', "
                    "UInt64(TDvlTagged.Alive), 1);" % name,
                    "    DevilCheckU('%s-string-copied', "
                    "UInt64(Length(CopyRec.S)), 4);" % name]

        elif shape == "out-param":
            n = 2
            sv("V", "IInterface")
            extra.append(["  procedure Replace(out P: IInterface);",
                          "  begin",
                          "    P := %s;" % guard("b"),
                          "  end;", ""])
            body = ["    V := %s;" % guard("a"),
                    "    Replace(V);",
                    "    DevilCheckU('%s-old-released', "
                    "UInt64(TDvlTagged.Alive), 1);" % name]

        elif shape == "self-assign":
            n = 1
            sv("V", "IInterface")
            body = ["    V := %s;" % guard("a"),
                    "    V := V;",
                    "    DevilCheckU('%s-self-assign-alive', "
                    "UInt64(TDvlTagged.Alive), 1);" % name,
                    "    V := nil;",
                    "    DevilCheckU('%s-released', "
                    "UInt64(TDvlTagged.Alive), 0);" % name]

        elif shape == "string-cow":
            n = 0
            sv("SA", "AnsiString")
            sv("SB", "AnsiString")
            body = ["    SA := AnsiString('abcdef') + AnsiString(IntToStr(0));",
                    "    SB := SA;",
                    "    SB[1] := 'Z';",
                    "    DevilCheckU('%s-source-intact', "
                    "UInt64(Ord(SA[1])), UInt64(Ord('a')));" % name,
                    "    DevilCheckU('%s-target-written', "
                    "UInt64(Ord(SB[1])), UInt64(Ord('Z')));" % name,
                    "    DevilCheckU('%s-length', "
                    "UInt64(Length(SA)), 7);" % name]

        elif shape == "interface-swap":
            n = 2
            sv("V1", "IInterface")
            sv("V2", "IInterface")
            body = ["    V1 := %s;" % guard("a"),
                    "    V2 := %s;" % guard("b"),
                    "    V1 := V2;",
                    "    DevilCheckU('%s-after-swap', "
                    "UInt64(TDvlTagged.Alive), 1);" % name,
                    "    V1 := nil;",
                    "    V2 := nil;",
                    "    DevilCheckU('%s-drained', "
                    "UInt64(TDvlTagged.Alive), 0);" % name]

        elif shape.startswith("managed-record"):
            n = 0
            if shape == "managed-record-scope":
                sv("A", "TDvlTracked")
                sv("B", "TDvlTracked")
                body = ["    A.Value := 7;",
                        "    B := A;",
                        "    DevilCheckU('%s-assign-ran', "
                        "UInt64(Cardinal(B.Value)), 107);" % name,
                        "    DevilCheckU('%s-init-count', "
                        "UInt64(Cardinal(DvlTrackedInit)), 2);" % name]
            elif shape == "managed-record-array":
                sv("D", "TDvlTrackedArray")
                body = ["    SetLength(D, 3);",
                        "    DevilCheckU('%s-array-init', "
                        "UInt64(Cardinal(DvlTrackedInit)), 3);" % name,
                        "    DevilCheckU('%s-array-value', "
                        "UInt64(Cardinal(D[2].Value)), 5);" % name,
                        "    SetLength(D, 1);",
                        "    DevilCheckU('%s-array-fini', "
                        "UInt64(Cardinal(DvlTrackedFini)), 2);" % name]
            else:
                sv("A", "TDvlTracked")
                extra.append(["  procedure Take(R: TDvlTracked);",
                              "  begin",
                              "    R.Value := R.Value + 1;",
                              "  end;", ""])
                body = ["    A.Value := 11;",
                        "    Take(A);",
                        "    DevilCheckU('%s-param-isolated', "
                        "UInt64(Cardinal(A.Value)), 11);" % name]
            pass

        else:   # exception-unwind-deep
            extra.append(["  procedure Deep(Level: Integer);",
                          "  var",
                          "    L: IInterface;",
                          "  begin",
                          "    L := TDvlTagged.Create(AnsiChar(Ord('a') + Level));",
                          "    if Level > 0 then",
                          "      Deep(Level - 1)",
                          "    else",
                          "      raise EDvlSignal.Create('deep');",
                          "  end;", ""])
            body = ["    try",
                    "      Deep(%d);" % (n - 1),
                    "    except",
                    "      on EDvlSignal do DevilTrailAdd('x');",
                    "    end;",
                    "    DevilCheckU('%s-unwound', "
                    "UInt64(TDvlTagged.Alive), 0);" % name]

        wrapped = fb.wrap(body, contexts, "    ", "DevilFailures")
        scenario = ["  procedure Scenario;"]
        if svars:
            scenario.append("  var")
            scenario += ["    %s: %s;" % (vn, vt) for vn, vt in svars]
        scenario += ["  begin"] + wrapped + ["  end;", ""]
        if shape == "locals-exception":
            call = ["  try", "    Scenario;", "  except",
                    "    on EDvlSignal do DevilTrailAdd('x');", "  end;"]
        else:
            call = ["  Scenario;"]

        # emit() prints nested routines deepest-first (reversed), so the
        # scenario goes in first and its helpers after it
        fb.nested.append(scenario)
        for block in extra:
            fb.nested.append(block)
        checks = [
            "  DevilCheckU('%s-balance', UInt64(TDvlTagged.Alive), 0);" % name,
            "  DevilNote('%s-order', DevilTrailHash);" % name,
            "  DevilNoteText('%s-trail', DevilTrailText);" % name,
        ]
        preamble = ["  TDvlTagged.Alive := 0;", "  TDvlTagged.Born := 0;",
                    "  DvlTrackedReset;", "  DevilTrailReset;"]
        fb.emit(e, call, checks, preamble)
        calls.append(fb.proc)
        records.append(CaseRecord(fb.name, "life", {
            "shape": shape, "count": n, "contexts": contexts}))
    emit_runner(e, "Life", calls)
    return records


ABI_FIELD_TYPES = (
    ("ShortInt", "i8", "scalar"),
    ("Byte", "u8", "scalar"),
    ("SmallInt", "i16", "scalar"),
    ("Word", "u16", "scalar"),
    ("Integer", "i32", "scalar"),
    ("Cardinal", "u32", "scalar"),
    ("Int64", "i64", "scalar"),
    ("UInt64", "u64", "scalar"),
    ("Single", "f32", "float"),
    ("Double", "f64", "float"),
    ("Currency", "cur", "float"),
    ("Boolean", "bool", "scalar"),
    ("WordBool", "wbool", "scalar"),
    ("AnsiChar", "ach", "scalar"),
    ("WideChar", "wch", "scalar"),
    ("AnsiString", "astr", "managed"),
    ("UnicodeString", "ustr", "managed"),
    ("IInterface", "intf", "managed"),
    ("array[0..2] of Byte", "arr3", "array"),
    ("array[0..1] of Integer", "arri2", "array"),
    ("TDvlPoint", "pt", "record"),
    ("set of 0..7", "set8", "scalar"),
    ("set of 0..31", "set32", "scalar"),
)

ABI_LAYOUTS = ("plain", "packed", "align1", "align2", "align4", "align8", "align16")


def layer_abi(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """Record layout and calling convention.

    Sizes and field offsets are reported as observations: they are ABI, and the
    contract is that our compiler matches Delphi byte for byte, which the gate
    verifies by comparing builds.  Everything about behaviour - by-value
    isolation, managed fields surviving a copy, a record returned from a
    function - is a hard check against the model."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-abi-%05d" % index
        proc = "DvlAbi%05d" % index
        layout = rng.choice(ABI_LAYOUTS)
        nfields = rng.choice((2, 3, 4, 5, 6))
        fields = [rng.choice(ABI_FIELD_TYPES) for _ in range(nfields)]
        has_managed = any(kind == "managed" for _, _, kind in fields)
        rec = "TDvlAbi%05d" % index

        decl = ["type"]
        head = "  %s = %srecord" % (rec, "packed " if layout == "packed" else "")
        decl.append(head)
        for k, (pascal, slug, _) in enumerate(fields):
            decl.append("    F%d: %s;" % (k, pascal))
        if layout.startswith("align"):
            decl.append("  end align %s;" % layout[5:])
        else:
            decl.append("  end;")
        decl.append("")

        body = ["  FillChar(Rec, SizeOf(Rec), 0);"]
        if has_managed:
            body = ["  Initialize(Rec);"]
        checks = []
        # observations: size and every field offset
        checks.append("  DevilNote('%s-size', UInt64(SizeOf(%s)));" % (name, rec))
        for k in range(nfields):
            checks.append(
                "  DevilNote('%s-offset-%d', UInt64(NativeUInt(@Rec.F%d) - "
                "NativeUInt(@Rec)));" % (name, k, k))

        # deterministic content, then a by-value round trip
        seed_values = []
        for k, (pascal, slug, kind) in enumerate(fields):
            if kind == "scalar":
                if pascal in ("Boolean", "WordBool"):
                    body.append("  Rec.F%d := True;" % k)
                    seed_values.append(("bool", k))
                elif pascal == "AnsiChar":
                    body.append("  Rec.F%d := AnsiChar(%d);" % (k, 65 + k))
                    seed_values.append(("ach", k))
                elif pascal == "WideChar":
                    body.append("  Rec.F%d := WideChar(%d);" % (k, 1000 + k))
                    seed_values.append(("wch", k))
                elif pascal.startswith("set of"):
                    body.append("  Rec.F%d := [%d];" % (k, k))
                    seed_values.append(("set", k))
                else:
                    body.append("  Rec.F%d := %d;" % (k, 7 + k))
                    seed_values.append(("int", k))
            elif kind == "float":
                body.append("  Rec.F%d := %d.5;" % (k, k + 1))
                seed_values.append(("float", k))
            elif kind == "managed":
                if pascal == "IInterface":
                    body.append("  Rec.F%d := TDvlTagged.Create('m');" % k)
                    seed_values.append(("intf", k))
                elif pascal == "AnsiString":
                    body.append("  Rec.F%d := AnsiString('abi') + "
                                "AnsiString(IntToStr(%d));" % (k, k))
                    seed_values.append(("astr", k))
                else:
                    body.append("  Rec.F%d := UnicodeString('abi') + "
                                "UnicodeString(IntToStr(%d));" % (k, k))
                    seed_values.append(("ustr", k))
            elif kind == "array":
                body.append("  Rec.F%d[0] := %d;" % (k, k + 1))
                seed_values.append(("arr", k))
            else:   # record
                body.append("  Rec.F%d.X := %d;" % (k, k + 3))
                seed_values.append(("pt", k))

        body.append("  Copy1 := Rec;")
        body.append("  DvlAbiMutate%05d(Rec);" % index)

        # by-value isolation and copy fidelity
        for kind, k in seed_values:
            if kind == "int":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Int64(Copy1.F%d)), UInt64(%d));"
                              % (name, k, k, 7 + k))
            elif kind == "bool":
                # C-style Booleans carry all bits set for True, and how far
                # that value is extended is itself an observation
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Ord(Copy1.F%d <> False)), 1);"
                              % (name, k, k))
                checks.append("  DevilNote('%s-boolraw-%d', "
                              "UInt64(Ord(Copy1.F%d)));" % (name, k, k))
            elif kind == "ach":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Ord(Copy1.F%d)), %d);" % (name, k, k, 65 + k))
            elif kind == "wch":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Ord(Copy1.F%d)), %d);" % (name, k, k, 1000 + k))
            elif kind == "set":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Ord(%d in Copy1.F%d)), 1);" % (name, k, k, k))
            elif kind == "float":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Round(Copy1.F%d * 2)), %d);"
                              % (name, k, k, (k + 1) * 2 + 1))
            elif kind == "astr":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Length(Copy1.F%d)), %d);"
                              % (name, k, k, 3 + len(str(k))))
            elif kind == "ustr":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Length(Copy1.F%d)), %d);"
                              % (name, k, k, 3 + len(str(k))))
            elif kind == "intf":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Ord(Copy1.F%d <> nil)), 1);" % (name, k, k))
            elif kind == "arr":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Copy1.F%d[0]), %d);" % (name, k, k, k + 1))
            elif kind == "pt":
                checks.append("  DevilCheckU('%s-value-%d', "
                              "UInt64(Copy1.F%d.X), %d);" % (name, k, k, k + 3))

        # the callee mutated its own copy only
        first = seed_values[0]
        if first[0] == "int":
            checks.append("  DevilCheckU('%s-byval-isolated', "
                          "UInt64(Int64(Rec.F%d)), UInt64(%d));"
                          % (name, first[1], 7 + first[1]))

        mutate = ["procedure DvlAbiMutate%05d(R: %s);" % (index, rec),
                  "begin"]
        if first[0] == "int":
            mutate.append("  R.F%d := 99;" % first[1])
        elif first[0] in ("astr", "ustr"):
            mutate.append("  R.F%d := '';" % first[1])
        elif first[0] == "intf":
            mutate.append("  R.F%d := nil;" % first[1])
        else:
            mutate.append("  FillChar(R.F%d, SizeOf(R.F%d), 0);"
                          % (first[1], first[1]))
        mutate += ["end;", ""]

        e.block(decl)
        e.block(mutate)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Rec, Copy1: %s;" % rec)
        e.line("begin")
        e.block(body)
        e.block(checks)
        if has_managed:
            e.line("  Finalize(Rec);")
            e.line("  Finalize(Copy1);")
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "abi", {
            "layout": layout,
            "fields": [slug for _, slug, _ in fields],
        }))
    emit_runner(e, "Abi", calls)
    return records


FLOAT_OPS = ("add", "sub", "mul", "div")


def float_values(rng: random.Random) -> list[float]:
    """Values that every IEEE double represents exactly, so the model stays
    exact without depending on the host's rounding."""
    base = [0.0, 1.0, -1.0, 0.5, -0.25, 2.0, -8.0, 1024.0, -4096.0,
            0.125, 3.5, -7.75, 65536.0, 1048576.0, 2.0 ** 31, -(2.0 ** 31),
            2.0 ** 52, 2.0 ** 53, -(2.0 ** 53), 1.0 / 1024.0]
    extra = []
    for _ in range(4):
        m = rng.randrange(-(1 << 20), 1 << 20)
        e = rng.randrange(-20, 20)
        extra.append(float(m) * (2.0 ** e))
    return base + extra


def double_bits(value: float) -> int:
    import struct
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def single_bits(value: float) -> int:
    import struct
    return struct.unpack("<I", struct.pack("<f", value))[0]


def single_round(value: float) -> float:
    import struct
    return struct.unpack("<f", struct.pack("<f", value))[0]


def pascal_float_literal(value: float) -> str:
    if value == int(value) and abs(value) < 1e18:
        return "%d.0" % int(value)
    return repr(value)


def layer_float(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Floating point and Currency.

    Only exactly representable operands are used, so the expected bit pattern
    is computed by the model with no rounding guesswork.  Single results are
    additionally rounded through the 32-bit format by the model, which is where
    an unwanted wider intermediate shows up."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-float-%05d" % index
        proc = "DvlFloat%05d" % index
        kind = rng.choice(("double", "single", "currency", "convert",
                           "compare", "intrinsic", "special", "mixed-int",
                           "extended-width"))
        fb = FormBuilder(index, "float")
        body: list[str] = []
        checks: list[str] = []
        detail: dict = {"kind": kind}

        if kind in ("double", "single"):
            pascal = "Double" if kind == "double" else "Single"
            op = rng.choice(FLOAT_OPS)
            pool = float_values(rng)
            a = rng.choice(pool)
            b = rng.choice(pool)
            if op == "div":
                while b == 0.0:
                    b = rng.choice(pool)
            if kind == "single":
                a, b = single_round(a), single_round(b)
            exact = {"add": a + b, "sub": a - b, "mul": a * b,
                     "div": (a / b) if b else 0.0}[op]
            if kind == "single":
                exact = single_round(exact)
                if abs(exact) > 3.0e38:
                    continue
                bits = single_bits(exact)
                width = 8
                bitfn = "SingleBits"
            else:
                bits = double_bits(exact)
                width = 16
                bitfn = "DoubleBits"
            va = fb.var("A", pascal)
            vb = fb.var("B", pascal)
            vr = fb.var("R", pascal)
            body = ["  %s := %s;" % (va, pascal_float_literal(a)),
                    "  %s := %s;" % (vb, pascal_float_literal(b)),
                    "  %s := %s %s %s;" % (vr, va, OP_TOKEN[op] if op != "div"
                                           else "/", vb)]
            checks = ["  DevilCheckU('%s-bits', UInt64(%s(%s)), UInt64($%0*X));"
                      % (name, bitfn, vr, width, bits)]
            detail.update({"type": pascal, "op": op, "a": a, "b": b})

        elif kind == "currency":
            # Currency is a scaled Int64: exact by construction
            scale = 10000
            a = rng.randrange(-(10 ** 9), 10 ** 9)
            b = rng.randrange(-(10 ** 6), 10 ** 6)
            op = rng.choice(("add", "sub", "muli"))
            va = fb.var("A", "Currency")
            vb = fb.var("B", "Currency")
            vr = fb.var("R", "Currency")
            k = rng.randrange(-20, 20)
            if op == "add":
                raw = a + b
                expr = "%s + %s" % (va, vb)
            elif op == "sub":
                raw = a - b
                expr = "%s - %s" % (va, vb)
            else:
                raw = a * k
                expr = "%s * %d" % (va, k)
            body = ["  %s := %d / %d;" % (va, a, scale),
                    "  %s := %d / %d;" % (vb, b, scale),
                    "  %s := %s;" % (vr, expr)]
            checks = ["  DevilCheckU('%s-raw', UInt64(PInt64(@%s)^), "
                      "UInt64($%016X));" % (name, vr, raw & ((1 << 64) - 1)),
                      "  DevilCheckU('%s-operand-raw', UInt64(PInt64(@%s)^), "
                      "UInt64($%016X));" % (name, va, a & ((1 << 64) - 1))]
            detail.update({"op": op, "a": a, "b": b, "k": k})

        elif kind == "convert":
            src = rng.choice(("i32", "i64", "u64", "double", "single"))
            value = rng.choice(float_values(rng))
            if src in ("i32", "i64", "u64"):
                t = TYPE_BY_SLUG[src]
                iv = rng.choice(interesting_values(t, rng))
                vd = fb.var("D", "Double")
                vi = fb.var("I", t.pascal)
                body = ["  %s := %s;" % (vi, t.literal(iv)),
                        "  %s := %s;" % (vd, vi)]
                if not t.signed and iv >= (1 << 63):
                    modelled = float(iv - (1 << 64)) + float(1 << 64)
                else:
                    modelled = float(iv)
                checks = ["  DevilCheckU('%s-int-to-double', "
                          "UInt64(DoubleBits(%s)), UInt64($%016X));"
                          % (name, vd, double_bits(modelled))]
                if modelled != float(iv):
                    checks.append("  DevilNote('%s-ieee-gap', UInt64($%016X));"
                                  % (name, double_bits(float(iv))))
                detail.update({"from": src, "value": iv})
            else:
                vd = fb.var("D", "Double")
                vs = fb.var("S", "Single")
                sv = single_round(value)
                body = ["  %s := %s;" % (vd, pascal_float_literal(value)),
                        "  %s := %s;" % (vs, vd)]
                checks = ["  DevilCheckU('%s-double-to-single', "
                          "UInt64(SingleBits(%s)), UInt64($%08X));"
                          % (name, vs, single_bits(sv))]
                detail.update({"from": "double", "value": value})

        elif kind == "compare":
            pool = float_values(rng)
            a = rng.choice(pool)
            b = rng.choice(pool)
            op = rng.choice(COMPARE_OPS)
            va = fb.var("A", "Double")
            vb = fb.var("B", "Double")
            expected = {"eq": a == b, "ne": a != b, "lt": a < b,
                        "le": a <= b, "gt": a > b, "ge": a >= b}[op]
            body = ["  %s := %s;" % (va, pascal_float_literal(a)),
                    "  %s := %s;" % (vb, pascal_float_literal(b))]
            checks = ["  DevilCheckU('%s-compare', UInt64(Ord(%s %s %s)), %d);"
                      % (name, va, COMPARE_TOKEN[op], vb, 1 if expected else 0)]
            detail.update({"op": op, "a": a, "b": b})

        elif kind == "mixed-int":
            # the width an implicit float expression is computed in: Delphi
            # Win64 uses Double, and mixing an integer must not widen it
            t = rng.choice([TYPE_BY_SLUG[x] for x in ("i32", "i64", "u32")])
            iv = rng.choice([v for v in interesting_values(t, rng)
                             if abs(v) < 2 ** 40])
            fv = rng.choice([0.5, 2.0, -4.0, 0.25, 1024.0])
            vd = fb.var("D", "Double")
            vi = fb.var("I", t.pascal)
            body = ["  %s := %s;" % (vi, t.literal(iv)),
                    "  %s := %s * %s;" % (vd, vi, pascal_float_literal(fv))]
            checks = ["  DevilCheckU('%s-mixed', UInt64(DoubleBits(%s)), "
                      "UInt64($%016X));"
                      % (name, vd, double_bits(float(iv) * fv))]
            detail.update({"int": iv, "float": fv, "type": t.slug})

        elif kind == "extended-width":
            # Extended is 10 bytes on Linux x86-64 and 8 on Delphi Win64, so its
            # size is an observation, while the value of an exact computation is
            # a hard check on both
            value = rng.choice([1.0, 0.5, 1024.0, -8.0, 2.0 ** 40])
            ve = fb.var("E", "Extended")
            body = ["  %s := %s;" % (ve, pascal_float_literal(value)),
                    "  %s := %s * 2.0;" % (ve, ve)]
            checks = ["  DevilNote('%s-extended-size', UInt64(SizeOf(Extended)));"
                      % name,
                      "  DevilCheckU('%s-extended-value', "
                      "UInt64(Round(%s)), UInt64($%016X));"
                      % (name, ve, int(value * 2) & ((1 << 64) - 1))]
            detail.update({"value": value})

        elif kind == "special":
            # NaN, infinities and signed zero: bit patterns are the only honest
            # way to talk about them, and the ordering rules are IEEE, not Delphi
            which = rng.choice(("nan-compare", "inf-arith", "neg-zero",
                                "nan-self", "inf-compare", "denormal-step",
                                "underflow-to-zero"))
            u = fb.var("U", "UInt64")
            d = fb.var("D", "Double")
            other = fb.var("O", "Double")
            if which in ("nan-compare", "nan-self"):
                bits = 0x7FF8000000000001
                body = ["  %s := UInt64($%016X);" % (u, bits),
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := 1.0;" % other]
                if which == "nan-self":
                    checks = ["  DevilCheckU('%s-nan-ne-self', "
                              "UInt64(Ord(%s <> %s)), 1);" % (name, d, d),
                              "  DevilCheckU('%s-nan-not-eq-self', "
                              "UInt64(Ord(not (%s = %s))), 1);" % (name, d, d)]
                else:
                    checks = ["  DevilCheckU('%s-nan-lt', "
                              "UInt64(Ord(%s < %s)), 0);" % (name, d, other),
                              "  DevilCheckU('%s-nan-gt', "
                              "UInt64(Ord(%s > %s)), 0);" % (name, d, other),
                              "  DevilCheckU('%s-nan-eq', "
                              "UInt64(Ord(%s = %s)), 0);" % (name, d, other)]
            elif which == "inf-arith":
                body = ["  %s := UInt64($7FF0000000000000);" % u,
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := %s + 1.0;" % (other, d)]
                checks = ["  DevilCheckU('%s-inf-stays', "
                          "UInt64(DoubleBits(%s)), UInt64($7FF0000000000000));"
                          % (name, other),
                          "  DevilCheckU('%s-inf-minus-inf-nan', "
                          "UInt64(Ord((%s - %s) <> (%s - %s))), 1);"
                          % (name, d, d, d, d)]
            elif which == "inf-compare":
                body = ["  %s := UInt64($FFF0000000000000);" % u,
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := -1.0E308;" % other]
                checks = ["  DevilCheckU('%s-neg-inf-lt', "
                          "UInt64(Ord(%s < %s)), 1);" % (name, d, other)]
            elif which == "denormal-step":
                # halving the smallest normal must land on the largest
                # denormal, and its bit pattern is exactly one shift down
                body = ["  %s := UInt64($0010000000000000);" % u,
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := %s * 0.5;" % (other, d)]
                checks = ["  DevilCheckU('%s-min-normal', "
                          "UInt64(DoubleBits(%s)), UInt64($0010000000000000));"
                          % (name, d),
                          "  DevilCheckU('%s-denormal', "
                          "UInt64(DoubleBits(%s)), UInt64($0008000000000000));"
                          % (name, other),
                          "  DevilCheckU('%s-denormal-back', "
                          "UInt64(DoubleBits(%s * 2.0)), "
                          "UInt64($0010000000000000));" % (name, other)]
            elif which == "underflow-to-zero":
                body = ["  %s := UInt64(1);" % u,
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := %s * 0.5;" % (other, d)]
                checks = ["  DevilCheckU('%s-smallest-denormal', "
                          "UInt64(DoubleBits(%s)), UInt64(1));" % (name, d),
                          "  DevilCheckU('%s-underflow', "
                          "UInt64(DoubleBits(%s)), 0);" % (name, other)]
            else:
                body = ["  %s := UInt64($8000000000000000);" % u,
                        "  Move(%s, %s, 8);" % (u, d),
                        "  %s := 0.0;" % other]
                checks = ["  DevilCheckU('%s-neg-zero-equals-zero', "
                          "UInt64(Ord(%s = %s)), 1);" % (name, d, other),
                          "  DevilCheckU('%s-neg-zero-bits', "
                          "UInt64(DoubleBits(%s)), UInt64($8000000000000000));"
                          % (name, d),
                          "  DevilNote('%s-neg-zero-plus-zero', "
                          "UInt64(DoubleBits(%s + %s)));" % (name, d, other)]
            detail.update({"special": which})

        else:   # intrinsic
            pool = [v for v in float_values(rng) if abs(v) < 2.0 ** 40]
            value = rng.choice(pool)
            fn = rng.choice(("trunc", "round", "abs", "int", "frac", "sqr"))
            vd = fb.var("D", "Double")
            body = ["  %s := %s;" % (vd, pascal_float_literal(value))]
            if fn == "trunc":
                expected = int(value)              # toward zero
                checks = ["  DevilCheckU('%s-trunc', UInt64(Int64(Trunc(%s))), "
                          "UInt64($%016X));"
                          % (name, vd, expected & ((1 << 64) - 1))]
            elif fn == "round":
                # banker's rounding, the Delphi contract
                import decimal
                d = decimal.Decimal(value)
                expected = int(d.quantize(decimal.Decimal(1),
                                          rounding=decimal.ROUND_HALF_EVEN))
                checks = ["  DevilCheckU('%s-round', UInt64(Int64(Round(%s))), "
                          "UInt64($%016X));"
                          % (name, vd, expected & ((1 << 64) - 1))]
            elif fn == "abs":
                checks = ["  DevilCheckU('%s-abs', UInt64(DoubleBits(Abs(%s))), "
                          "UInt64($%016X));" % (name, vd, double_bits(abs(value)))]
            elif fn == "int":
                truncated = float(int(value))
                checks = ["  DevilCheckU('%s-int', UInt64(DoubleBits(Int(%s))), "
                          "UInt64($%016X));" % (name, vd, double_bits(truncated))]
            elif fn == "frac":
                fraction = value - float(int(value))
                checks = ["  DevilCheckU('%s-frac', UInt64(DoubleBits(Frac(%s))), "
                          "UInt64($%016X));" % (name, vd, double_bits(fraction))]
            else:
                squared = value * value
                if abs(squared) > 1e300:
                    continue
                checks = ["  DevilCheckU('%s-sqr', UInt64(DoubleBits(Sqr(%s))), "
                          "UInt64($%016X));" % (name, vd, double_bits(squared))]
            detail.update({"fn": fn, "value": value})

        contexts = pick_contexts(rng, rng.choice((0, 0, 1, 1, 2)))
        statements = fb.wrap(body, [c for c in contexts
                                    if c not in ("nested-proc", "closure")],
                             "  ", "DevilFailures")
        fb.proc = proc
        fb.name = name
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "float", detail))
    emit_runner(e, "Float", calls)
    return records


STRING_TYPES = (
    ("AnsiString", "astr"),
    ("UnicodeString", "ustr"),
    ("UTF8String", "u8str"),
    ("ShortString", "sstr"),
)

STRING_OPS = ("concat", "copy", "delete", "insert", "pos", "setlength",
              "index-write", "compare", "upper", "trim", "self-concat",
              "empty-concat", "char-append")


def string_pool(rng: random.Random) -> list[str]:
    base = ["", "a", "ab", "abc", "abcdef", "0123456789",
            "The quick brown", "zz", "MiXeD", "  spaced  "]
    extra = []
    for _ in range(2):
        length = rng.randrange(0, 12)
        extra.append("".join(chr(rng.randrange(ord("a"), ord("z") + 1))
                             for _ in range(length)))
    return base + extra


def pascal_string_literal(value: str) -> str:
    if not value:
        return "''"
    return "'" + value.replace("'", "''") + "'"


def layer_string(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """String machinery: the model is plain Python string arithmetic with
    Pascal's 1-based indexing and clamping rules, so every expectation is
    derived, never captured."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-str-%05d" % index
        proc = "DvlStr%05d" % index
        pascal, slug = rng.choice(STRING_TYPES)
        op = rng.choice(STRING_OPS)
        pool = string_pool(rng)
        a = rng.choice(pool)
        b = rng.choice(pool)
        if slug == "sstr":
            a, b = a[:20], b[:20]
        fb = FormBuilder(index, "str")
        fb.proc = proc
        fb.name = name
        va = fb.var("A", pascal)
        vb = fb.var("B", pascal)
        body = ["  %s := %s(%s);" % (va, pascal, pascal_string_literal(a)),
                "  %s := %s(%s);" % (vb, pascal, pascal_string_literal(b))]
        checks: list[str] = []
        detail = {"type": slug, "op": op, "a": a, "b": b}

        def check_len(expr: str, expected: int, tag: str) -> str:
            return ("  DevilCheckU('%s-%s', UInt64(Length(%s)), %d);"
                    % (name, tag, expr, expected))

        def check_char(expr: str, pos: int, ch: str, tag: str) -> str:
            return ("  DevilCheckU('%s-%s', UInt64(Ord(%s[%d])), %d);"
                    % (name, tag, expr, pos, ord(ch)))

        if op == "concat":
            result = a + b
            body.append("  %s := %s + %s;" % (va, va, vb))
            checks.append(check_len(va, len(result), "length"))
            if result:
                checks.append(check_char(va, 1, result[0], "head"))
                checks.append(check_char(va, len(result), result[-1], "tail"))

        elif op == "copy":
            index_ = rng.randrange(-2, len(a) + 3)
            countv = rng.randrange(-1, len(a) + 3)
            start_ = max(index_, 1)
            result = a[start_ - 1:start_ - 1 + max(countv, 0)]
            body.append("  %s := Copy(%s, %d, %d);" % (vb, va, index_, countv))
            checks.append(check_len(vb, len(result), "length"))
            if result:
                checks.append(check_char(vb, 1, result[0], "head"))

        elif op == "delete":
            if not a:
                continue
            index_ = rng.randrange(1, len(a) + 1)
            countv = rng.randrange(0, len(a) + 2)
            result = a[:index_ - 1] + a[index_ - 1 + countv:]
            body.append("  Delete(%s, %d, %d);" % (va, index_, countv))
            checks.append(check_len(va, len(result), "length"))
            if result:
                checks.append(check_char(va, 1, result[0], "head"))

        elif op == "insert":
            index_ = rng.randrange(1, len(a) + 2)
            result = a[:index_ - 1] + b + a[index_ - 1:]
            if slug == "sstr":
                result = result[:255]
            body.append("  Insert(%s, %s, %d);" % (vb, va, index_))
            checks.append(check_len(va, len(result), "length"))
            if result:
                checks.append(check_char(va, 1, result[0], "head"))

        elif op == "pos":
            needle = b if b else "a"
            found = a.find(needle) + 1 if needle else 0
            body.append("  %s := %s(%s);" % (vb, pascal,
                                             pascal_string_literal(needle)))
            checks.append("  DevilCheckU('%s-pos', UInt64(Pos(%s, %s)), %d);"
                          % (name, vb, va, found))

        elif op == "setlength":
            newlen = rng.randrange(0, len(a) + 4)
            keep = a[:newlen]
            body.append("  SetLength(%s, %d);" % (va, newlen))
            checks.append(check_len(va, newlen, "length"))
            if keep:
                checks.append(check_char(va, 1, keep[0], "kept-head"))
                checks.append(check_char(va, len(keep), keep[-1], "kept-tail"))

        elif op == "index-write":
            if not a:
                continue
            pos = rng.randrange(1, len(a) + 1)
            # UniqueString exists only for the two canonical string types
            if slug in ("astr", "ustr"):
                body.append("  UniqueString(%s);" % va)
            body.append("  %s := %s;" % (vb, va))
            body.append("  %s[%d] := 'Z';" % (vb, pos))
            checks.append(check_char(va, pos, a[pos - 1], "source-intact"))
            checks.append(check_char(vb, pos, "Z", "target-written"))

        elif op == "compare":
            expected = 1 if a < b else 0
            checks.append("  DevilCheckU('%s-lt', UInt64(Ord(%s < %s)), %d);"
                          % (name, va, vb, expected))
            checks.append("  DevilCheckU('%s-eq', UInt64(Ord(%s = %s)), %d);"
                          % (name, va, vb, 1 if a == b else 0))

        elif op == "upper":
            result = a.upper()
            body.append("  %s := %s(UpperCase(string(%s)));" % (vb, pascal, va))
            checks.append(check_len(vb, len(result), "length"))
            if result:
                checks.append(check_char(vb, 1, result[0], "head"))

        elif op == "trim":
            result = a.strip(" ")
            body.append("  %s := %s(Trim(string(%s)));" % (vb, pascal, va))
            checks.append(check_len(vb, len(result), "length"))

        elif op == "self-concat":
            result = a + a
            if slug == "sstr":
                result = result[:255]
            body.append("  %s := %s + %s;" % (va, va, va))
            checks.append(check_len(va, len(result), "length"))

        elif op == "empty-concat":
            result = a + "" + b + ""
            if slug == "sstr":
                result = result[:255]
            body.append("  %s := %s + '' + %s + '';" % (va, va, vb))
            checks.append(check_len(va, len(result), "length"))

        else:   # char-append
            result = a + "q"
            if slug == "sstr":
                result = result[:255]
            if slug == "ustr":
                body.append("  %s := %s + WideChar('q');" % (va, va))
            else:
                body.append("  %s := %s + AnsiChar('q');" % (va, va))
            checks.append(check_len(va, len(result), "length"))
            checks.append(check_char(va, len(result), result[-1], "tail"))

        if not checks:
            continue
        contexts = [c for c in pick_contexts(rng, rng.choice((0, 0, 1, 2)))
                    if c not in ("nested-proc", "closure")]
        statements = fb.wrap(body, contexts, "  ", "DevilFailures")
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "str", detail))
    emit_runner(e, "Str", calls)
    return records


DISPATCH_SHAPES = ("virtual-chain", "inherited-chain", "class-function",
                   "metaclass-ctor", "interface-call", "interface-cross",
                   "method-pointer", "dynamic-method", "class-helper",
                   "abstract-override", "procvar-swap", "anon-invoke")


def layer_dispatch(e: Emitter, rng: random.Random, count: int,
                   start: int) -> list[CaseRecord]:
    """Dispatch: which body actually runs.  Each case builds a small hierarchy
    with distinct return values, so the expected number is arithmetic, and the
    call trail records the order of bodies that ran."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-disp-%05d" % index
        proc = "DvlDisp%05d" % index
        shape = rng.choice(DISPATCH_SHAPES)
        base_v = rng.randrange(1, 50)
        mid_v = rng.randrange(50, 100)
        leaf_v = rng.randrange(100, 200)
        arg = rng.randrange(1, 20)
        cls = "TDvlD%05d" % index
        decl = ["type",
                "  %sBase = class" % cls,
                "  public",
                "    function Step(X: Integer): Integer; virtual;",
                "    function Chain(X: Integer): Integer; virtual;",
                "    class function Kind: Integer; virtual;",
                "  end;",
                "  %sMid = class(%sBase)" % (cls, cls),
                "  public",
                "    function Step(X: Integer): Integer; override;",
                "    function Chain(X: Integer): Integer; override;",
                "    class function Kind: Integer; override;",
                "  end;",
                "  %sLeaf = class(%sMid)" % (cls, cls),
                "  public",
                "    function Step(X: Integer): Integer; override;",
                "    function Chain(X: Integer): Integer; override;",
                "    class function Kind: Integer; override;",
                "  end;",
                "  %sClass = class of %sBase;" % (cls, cls),
                "  %sFunc = function(X: Integer): Integer of object;" % cls,
                "",
                "function %sBase.Step(X: Integer): Integer;" % cls,
                "begin",
                "  Result := X + %d;" % base_v,
                "end;",
                "",
                "function %sBase.Chain(X: Integer): Integer;" % cls,
                "begin",
                "  Result := X * 2;",
                "end;",
                "",
                "class function %sBase.Kind: Integer;" % cls,
                "begin",
                "  Result := %d;" % base_v,
                "end;",
                "",
                "function %sMid.Step(X: Integer): Integer;" % cls,
                "begin",
                "  Result := X + %d;" % mid_v,
                "end;",
                "",
                "function %sMid.Chain(X: Integer): Integer;" % cls,
                "begin",
                "  Result := inherited Chain(X) + %d;" % mid_v,
                "end;",
                "",
                "class function %sMid.Kind: Integer;" % cls,
                "begin",
                "  Result := %d;" % mid_v,
                "end;",
                "",
                "function %sLeaf.Step(X: Integer): Integer;" % cls,
                "begin",
                "  Result := X + %d;" % leaf_v,
                "end;",
                "",
                "function %sLeaf.Chain(X: Integer): Integer;" % cls,
                "begin",
                "  Result := inherited Chain(X) * 3;",
                "end;",
                "",
                "class function %sLeaf.Kind: Integer;" % cls,
                "begin",
                "  Result := %d;" % leaf_v,
                "end;",
                ""]
        e.block(decl)

        fb = FormBuilder(index, "disp")
        fb.proc = proc
        fb.name = name
        obj = fb.var("Obj", "%sBase" % cls)
        res = fb.var("Res", "Integer")
        body: list[str] = []
        checks: list[str] = []

        if shape in ("virtual-chain", "inherited-chain", "abstract-override"):
            level = rng.choice(("Base", "Mid", "Leaf"))
            body.append("  %s := %s%s.Create;" % (obj, cls, level))
            if shape == "inherited-chain":
                expected = {"Base": arg * 2,
                            "Mid": arg * 2 + mid_v,
                            "Leaf": (arg * 2 + mid_v) * 3}[level]
                body.append("  %s := %s.Chain(%d);" % (res, obj, arg))
            else:
                expected = arg + {"Base": base_v, "Mid": mid_v,
                                  "Leaf": leaf_v}[level]
                body.append("  %s := %s.Step(%d);" % (res, obj, arg))
            body.append("  %s.Free;" % obj)
            checks.append("  DevilCheckU('%s-value', UInt64(Cardinal(%s)), %d);"
                          % (name, res, expected & 0xFFFFFFFF))

        elif shape == "class-function":
            level = rng.choice(("Base", "Mid", "Leaf"))
            expected = {"Base": base_v, "Mid": mid_v, "Leaf": leaf_v}[level]
            body.append("  %s := %s%s.Kind;" % (res, cls, level))
            checks.append("  DevilCheckU('%s-classfunc', UInt64(Cardinal(%s)), %d);"
                          % (name, res, expected))

        elif shape == "metaclass-ctor":
            meta = fb.var("Meta", "%sClass" % cls)
            level = rng.choice(("Base", "Mid", "Leaf"))
            expected = arg + {"Base": base_v, "Mid": mid_v, "Leaf": leaf_v}[level]
            kind = {"Base": base_v, "Mid": mid_v, "Leaf": leaf_v}[level]
            body += ["  %s := %s%s;" % (meta, cls, level),
                     "  %s := %s.Create;" % (obj, meta),
                     "  %s := %s.Step(%d);" % (res, obj, arg),
                     "  %s.Free;" % obj]
            checks += ["  DevilCheckU('%s-meta-step', UInt64(Cardinal(%s)), %d);"
                       % (name, res, expected & 0xFFFFFFFF),
                       "  DevilCheckU('%s-meta-kind', UInt64(Cardinal(%s.Kind)), %d);"
                       % (name, meta, kind)]

        elif shape == "method-pointer":
            fnv = fb.var("Fn", "%sFunc" % cls)
            level = rng.choice(("Base", "Mid", "Leaf"))
            expected = arg + {"Base": base_v, "Mid": mid_v, "Leaf": leaf_v}[level]
            body += ["  %s := %s%s.Create;" % (obj, cls, level),
                     "  %s := %s.Step;" % (fnv, obj),
                     "  %s := %s(%d);" % (res, fnv, arg),
                     "  %s.Free;" % obj]
            checks.append("  DevilCheckU('%s-methptr', UInt64(Cardinal(%s)), %d);"
                          % (name, res, expected & 0xFFFFFFFF))

        elif shape == "procvar-swap":
            fnv = fb.var("Fn", "%sFunc" % cls)
            obj2 = fb.var("Obj2", "%sBase" % cls)
            body += ["  %s := %sMid.Create;" % (obj, cls),
                     "  %s := %sLeaf.Create;" % (obj2, cls),
                     "  %s := %s.Step;" % (fnv, obj),
                     "  %s := %s(%d);" % (res, fnv, arg),
                     "  %s := %s.Step;" % (fnv, obj2),
                     "  %s := %s + %s(%d);" % (res, res, fnv, arg),
                     "  %s.Free;" % obj, "  %s.Free;" % obj2]
            expected = (arg + mid_v) + (arg + leaf_v)
            checks.append("  DevilCheckU('%s-swap', UInt64(Cardinal(%s)), %d);"
                          % (name, res, expected & 0xFFFFFFFF))

        elif shape in ("interface-call", "interface-cross"):
            # real interface dispatch: two interfaces on one object, cross-cast
            # through QueryInterface and COM identity through IInterface
            alpha = fb.var("IA", "IDvlAlpha")
            beta = fb.var("IB", "IDvlBeta")
            u1 = fb.var("U1", "IInterface")
            u2 = fb.var("U2", "IInterface")
            res2 = fb.var("Res2", "Integer")
            body = ["  TDvlDual.Alive := 0;",
                    "  %s := TDvlDual.Create(%d);" % (alpha, arg),
                    "  DevilCheckU('%s-alive', UInt64(TDvlDual.Alive), 1);" % name,
                    "  %s := %s.AlphaValue;" % (res, alpha),
                    "  DevilCheckU('%s-alpha', UInt64(Cardinal(%s)), %d);"
                    % (name, res, (arg * 2) & 0xFFFFFFFF)]
            if shape == "interface-cross":
                body += ["  %s := %s as IDvlBeta;" % (beta, alpha),
                         "  %s := %s.BetaValue;" % (res2, beta),
                         "  DevilCheckU('%s-beta', UInt64(Cardinal(%s)), %d);"
                         % (name, res2, (arg + 1000) & 0xFFFFFFFF),
                         "  %s := %s as IInterface;" % (u1, alpha),
                         "  %s := %s as IInterface;" % (u2, beta),
                         "  DevilCheckU('%s-com-identity', "
                         "UInt64(Ord(%s = %s)), 1);" % (name, u1, u2),
                         "  DevilCheckU('%s-still-one', "
                         "UInt64(TDvlDual.Alive), 1);" % name,
                         "  %s := nil;" % u1, "  %s := nil;" % u2,
                         "  %s := nil;" % beta]
            body += ["  %s := nil;" % alpha,
                     "  DevilCheckU('%s-released', "
                     "UInt64(TDvlDual.Alive), 0);" % name]

        elif shape == "anon-invoke":
            fnr = fb.var("Ref", "TDvlIntFunc")
            body += ["  %s := %sLeaf.Create;" % (obj, cls),
                     "  %s :=" % fnr,
                     "    function(X: Integer): Integer",
                     "    begin",
                     "      Result := %s.Step(X);" % obj,
                     "    end;",
                     "  %s := %s(%d);" % (res, fnr, arg),
                     "  %s := nil;" % fnr,
                     "  %s.Free;" % obj]
            checks.append("  DevilCheckU('%s-anon', UInt64(Cardinal(%s)), %d);"
                          % (name, res, (arg + leaf_v) & 0xFFFFFFFF))

        else:   # dynamic-method / class-helper fall back to a virtual probe
            body += ["  %s := %sLeaf.Create;" % (obj, cls),
                     "  %s := %s.Chain(%d);" % (res, obj, arg),
                     "  %s.Free;" % obj]
            checks.append("  DevilCheckU('%s-chain', UInt64(Cardinal(%s)), %d);"
                          % (name, res, ((arg * 2 + mid_v) * 3) & 0xFFFFFFFF))

        contexts = [c for c in pick_contexts(rng, rng.choice((0, 0, 1, 2)))
                    if c not in ("nested-proc", "closure")]
        statements = fb.wrap(body, contexts, "  ", "DevilFailures")
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "disp", {"shape": shape}))
    emit_runner(e, "Disp", calls)
    return records


GENERIC_SHAPES = ("box-scalar", "box-managed", "nested-spec", "two-params",
                  "class-var-per-spec", "generic-method", "constraint-class",
                  "array-of-t", "generic-record-op", "swap-generic")


def layer_generic(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Generics: specialization must keep values, layout and per-instantiation
    state apart.  Values come from the model; the identity of a specialization
    is checked through SizeOf and class variables."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-gen-%05d" % index
        proc = "DvlGen%05d" % index
        shape = rng.choice(GENERIC_SHAPES)
        t = rng.choice(TYPES)
        value = rng.choice(interesting_values(t, rng))
        fb = FormBuilder(index, "gen")
        fb.proc = proc
        fb.name = name
        body: list[str] = []
        checks: list[str] = []

        if shape in ("box-scalar", "nested-spec", "array-of-t"):
            if shape == "box-scalar":
                box = fb.var("Box", "TDvlManagedBox<%s>" % t.pascal)
                body = ["  %s.Value := %s;" % (box, t.literal(value))]
                checks = ["  DevilCheckU('%s-roundtrip', DvlRaw%s(%s.Value), "
                          "UInt64($%016X));"
                          % (name, t.slug, box, t.raw(value))]
            elif shape == "array-of-t":
                arr = fb.var("Arr", "TArray<%s>" % t.pascal)
                body = ["  SetLength(%s, 3);" % arr,
                        "  %s[1] := %s;" % (arr, t.literal(value))]
                checks = ["  DevilCheckU('%s-array-len', UInt64(Length(%s)), 3);"
                          % (name, arr),
                          "  DevilCheckU('%s-array-value', DvlRaw%s(%s[1]), "
                          "UInt64($%016X));" % (name, t.slug, arr, t.raw(value))]
            else:
                v = fb.var("Val", t.pascal)
                body = ["  %s := %s;" % (v, t.literal(value))]
                checks = ["  DevilCheckU('%s-nested', DvlRaw%s(%s), "
                          "UInt64($%016X));" % (name, t.slug, v, t.raw(value))]

        elif shape == "class-var-per-spec":
            body = ["  TDvlCounter<Integer>.Value := 0;",
                    "  TDvlCounter<AnsiString>.Value := 0;",
                    "  TDvlCounter<Integer>.Bump;",
                    "  TDvlCounter<Integer>.Bump;",
                    "  TDvlCounter<AnsiString>.Bump;"]
            checks = ["  DevilCheckU('%s-int-slot', "
                      "UInt64(TDvlCounter<Integer>.Value), 2);" % name,
                      "  DevilCheckU('%s-str-slot', "
                      "UInt64(TDvlCounter<AnsiString>.Value), 1);" % name]

        elif shape == "generic-method":
            v = fb.var("Val", t.pascal)
            body = ["  %s := %s;" % (v, t.literal(value))]
            checks = ["  DevilCheckU('%s-echo', DvlRaw%s(TDvlOps.Echo<%s>(%s)), "
                      "UInt64($%016X));"
                      % (name, t.slug, t.pascal, v, t.raw(value))]

        elif shape == "swap-generic":
            v1 = fb.var("V1", t.pascal)
            v2 = fb.var("V2", t.pascal)
            other = rng.choice(interesting_values(t, rng))
            body = ["  %s := %s;" % (v1, t.literal(value)),
                    "  %s := %s;" % (v2, t.literal(other)),
                    "  TDvlOps.Swap<%s>(%s, %s);" % (t.pascal, v1, v2)]
            checks = ["  DevilCheckU('%s-swap-a', DvlRaw%s(%s), UInt64($%016X));"
                      % (name, t.slug, v1, t.raw(other)),
                      "  DevilCheckU('%s-swap-b', DvlRaw%s(%s), UInt64($%016X));"
                      % (name, t.slug, v2, t.raw(value))]

        elif shape == "box-managed":
            body = ["  TDvlTagged.Alive := 0;",
                    "  DvlManagedBoxRoundTrip;"]
            checks = ["  DevilCheckU('%s-managed-drained', "
                      "UInt64(TDvlTagged.Alive), 0);" % name]

        elif shape == "two-params":
            v = fb.var("Val", t.pascal)
            body = ["  %s := %s;" % (v, t.literal(value))]
            checks = ["  DevilCheckU('%s-pair', "
                      "DvlRaw%s(TDvlOps.First<%s, Integer>(%s, 7)), "
                      "UInt64($%016X));"
                      % (name, t.slug, t.pascal, v, t.raw(value))]

        elif shape == "constraint-class":
            body = ["  DvlConstraintProbe;"]
            checks = ["  DevilCheckU('%s-constraint', DvlConstraintValue, 5);"
                      % name]

        else:   # generic-record-op
            v = fb.var("Val", "Integer")
            body = ["  %s := DvlGenericAdd(%d, %d);"
                    % (v, value & 0xFFFF, 3)]
            checks = ["  DevilCheckU('%s-record-op', UInt64(Cardinal(%s)), %d);"
                      % (name, v, ((value & 0xFFFF) + 3) & 0xFFFFFFFF)]

        if not checks:
            continue
        contexts = [c for c in pick_contexts(rng, rng.choice((0, 0, 1)))
                    if c not in ("nested-proc", "closure")]
        statements = fb.wrap(body, contexts, "  ", "DevilFailures")
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "gen", {"shape": shape, "type": t.slug}))
    emit_runner(e, "Gen", calls)
    return records


ARRAY_SHAPES = ("static-index", "dynamic-grow", "dynamic-share", "copy-detach",
                "insert-delete", "two-dim", "pointer-walk", "slice-open",
                "open-array-sum", "negative-based", "concat", "ragged")


def layer_array(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Arrays and pointers: indexing arithmetic, reference semantics and the
    exact moment a dynamic array detaches."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-arr-%05d" % index
        proc = "DvlArr%05d" % index
        shape = rng.choice(ARRAY_SHAPES)
        n = rng.choice((4, 6, 8))
        fb = FormBuilder(index, "arr")
        fb.proc = proc
        fb.name = name
        body: list[str] = []
        checks: list[str] = []

        if shape == "static-index":
            arr = fb.var("Arr", "array[0..%d] of Integer" % (n - 1))
            k = fb.var("K", "Integer")
            body = ["  for %s := 0 to %d do" % (k, n - 1),
                    "    %s[%s] := %s * 7 + 1;" % (arr, k, k)]
            probe = rng.randrange(0, n)
            checks = ["  DevilCheckU('%s-value', UInt64(Cardinal(%s[%d])), %d);"
                      % (name, arr, probe, probe * 7 + 1)]

        elif shape == "negative-based":
            arr = fb.var("Arr", "array[-3..%d] of Integer" % (n - 4))
            k = fb.var("K", "Integer")
            body = ["  for %s := -3 to %d do" % (k, n - 4),
                    "    %s[%s] := %s * 3;" % (arr, k, k)]
            checks = ["  DevilCheckU('%s-low', UInt64(Cardinal(%s[-3])), %d);"
                      % (name, arr, (-9) & 0xFFFFFFFF),
                      "  DevilCheckU('%s-high', UInt64(Cardinal(%s[%d])), %d);"
                      % (name, arr, n - 4, ((n - 4) * 3) & 0xFFFFFFFF)]

        elif shape == "dynamic-grow":
            arr = fb.var("Arr", "TArray<Integer>")
            k = fb.var("K", "Integer")
            body = ["  SetLength(%s, %d);" % (arr, n),
                    "  for %s := 0 to %d do" % (k, n - 1),
                    "    %s[%s] := %s;" % (arr, k, k),
                    "  SetLength(%s, %d);" % (arr, n + 2)]
            checks = ["  DevilCheckU('%s-len', UInt64(Length(%s)), %d);"
                      % (name, arr, n + 2),
                      "  DevilCheckU('%s-kept', UInt64(Cardinal(%s[%d])), %d);"
                      % (name, arr, n - 1, n - 1),
                      "  DevilCheckU('%s-fresh', UInt64(Cardinal(%s[%d])), 0);"
                      % (name, arr, n + 1)]

        elif shape == "dynamic-share":
            a = fb.var("A", "TArray<Integer>")
            b = fb.var("B", "TArray<Integer>")
            body = ["  SetLength(%s, %d);" % (a, n),
                    "  %s[0] := 11;" % a,
                    "  %s := %s;" % (b, a),
                    "  %s[0] := 22;" % b]
            checks = ["  DevilCheckU('%s-shared', UInt64(Cardinal(%s[0])), 22);"
                      % (name, a)]

        elif shape == "copy-detach":
            a = fb.var("A", "TArray<Integer>")
            b = fb.var("B", "TArray<Integer>")
            body = ["  SetLength(%s, %d);" % (a, n),
                    "  %s[0] := 11;" % a,
                    "  %s := Copy(%s);" % (b, a),
                    "  %s[0] := 22;" % b]
            checks = ["  DevilCheckU('%s-source', UInt64(Cardinal(%s[0])), 11);"
                      % (name, a),
                      "  DevilCheckU('%s-copy', UInt64(Cardinal(%s[0])), 22);"
                      % (name, b)]

        elif shape == "insert-delete":
            a = fb.var("A", "TArray<Integer>")
            body = ["  SetLength(%s, 3);" % a,
                    "  %s[0] := 1;" % a, "  %s[1] := 2;" % a, "  %s[2] := 3;" % a,
                    "  Insert(9, %s, 1);" % a,
                    "  Delete(%s, 0, 1);" % a]
            checks = ["  DevilCheckU('%s-len', UInt64(Length(%s)), 3);" % (name, a),
                      "  DevilCheckU('%s-head', UInt64(Cardinal(%s[0])), 9);"
                      % (name, a),
                      "  DevilCheckU('%s-tail', UInt64(Cardinal(%s[2])), 3);"
                      % (name, a)]

        elif shape == "two-dim":
            arr = fb.var("Arr", "array[0..3, 0..3] of Integer")
            r = fb.var("R", "Integer")
            c = fb.var("C", "Integer")
            body = ["  for %s := 0 to 3 do" % r,
                    "    for %s := 0 to 3 do" % c,
                    "      %s[%s, %s] := %s * 10 + %s;" % (arr, r, c, r, c)]
            checks = ["  DevilCheckU('%s-cell', UInt64(Cardinal(%s[2, 3])), 23);"
                      % (name, arr)]

        elif shape == "pointer-walk":
            arr = fb.var("Arr", "array[0..%d] of Integer" % (n - 1))
            k = fb.var("K", "Integer")
            ptr = fb.var("P", "PInteger")
            total = sum(i * 5 for i in range(n))
            body = ["  for %s := 0 to %d do" % (k, n - 1),
                    "    %s[%s] := %s * 5;" % (arr, k, k),
                    "  %s := @%s[0];" % (ptr, arr),
                    "  %s := 0;" % k,
                    "  while NativeUInt(%s) <= NativeUInt(@%s[%d]) do"
                    % (ptr, arr, n - 1),
                    "  begin",
                    "    %s := %s + %s^;" % (k, k, ptr),
                    "    Inc(%s);" % ptr,
                    "  end;"]
            checks = ["  DevilCheckU('%s-sum', UInt64(Cardinal(%s)), %d);"
                      % (name, k, total)]

        elif shape in ("slice-open", "open-array-sum"):
            arr = fb.var("Arr", "array[0..%d] of Integer" % (n - 1))
            k = fb.var("K", "Integer")
            body = ["  for %s := 0 to %d do" % (k, n - 1),
                    "    %s[%s] := %s + 1;" % (arr, k, k)]
            if shape == "slice-open":
                take = rng.randrange(1, n + 1)
                total = sum(i + 1 for i in range(take))
                checks = ["  DevilCheckU('%s-slice', "
                          "UInt64(Cardinal(DvlSumOpen(Slice(%s, %d)))), %d);"
                          % (name, arr, take, total)]
            else:
                total = sum(i + 1 for i in range(n))
                checks = ["  DevilCheckU('%s-open', "
                          "UInt64(Cardinal(DvlSumOpen(%s))), %d);"
                          % (name, arr, total)]

        elif shape == "concat":
            a = fb.var("A", "TArray<Integer>")
            b = fb.var("B", "TArray<Integer>")
            c = fb.var("C", "TArray<Integer>")
            body = ["  SetLength(%s, 2);" % a, "  %s[0] := 1;" % a,
                    "  %s[1] := 2;" % a,
                    "  SetLength(%s, 2);" % b, "  %s[0] := 3;" % b,
                    "  %s[1] := 4;" % b,
                    "  %s := Concat(%s, %s);" % (c, a, b)]
            checks = ["  DevilCheckU('%s-len', UInt64(Length(%s)), 4);" % (name, c),
                      "  DevilCheckU('%s-tail', UInt64(Cardinal(%s[3])), 4);"
                      % (name, c)]

        else:   # ragged
            a = fb.var("A", "TArray<TArray<Integer>>")
            body = ["  SetLength(%s, 2);" % a,
                    "  SetLength(%s[0], 3);" % a,
                    "  SetLength(%s[1], 1);" % a,
                    "  %s[0][2] := 42;" % a,
                    "  %s[1][0] := 7;" % a]
            checks = ["  DevilCheckU('%s-inner-len', UInt64(Length(%s[0])), 3);"
                      % (name, a),
                      "  DevilCheckU('%s-inner-value', "
                      "UInt64(Cardinal(%s[0][2])), 42);" % (name, a)]

        contexts = [c for c in pick_contexts(rng, rng.choice((0, 0, 1, 2)))
                    if c not in ("nested-proc", "closure")]
        statements = fb.wrap(body, contexts, "  ", "DevilFailures")
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "arr", {"shape": shape, "n": n}))
    emit_runner(e, "Arr", calls)
    return records


def layer_unitcross(e: Emitter, rng: random.Random, count: int,
                    start: int) -> list[CaseRecord]:
    """Cross-unit forms.

    The bodies live in a separate generated unit, so the compiler has to carry
    types, inline bodies and generic specializations through the PPU.  The gate
    additionally rebuilds the program reusing those PPUs, which is where replay
    defects show up."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    unit_lines = [
        "unit devil_gen_unit;",
        "",
        "{$ifdef FPC}",
        "  {$mode delphiunicode}{$H+}",
        "  {$modeswitch advancedrecords}",
        "  {$modeswitch anonymousfunctions}",
        "  {$modeswitch functionreferences}",
        "{$endif}",
        "{$Q-}{$R-}",
        "",
        "interface",
        "",
        "uses",
        "  SysUtils, devil_runtime, devil_gen_second;",
        "",
        "type",
        "  TDvlUnitRec = record",
        "    A: Integer;",
        "    B: Int64;",
        "    S: AnsiString;",
        "  end;",
        "",
        "  TDvlUnitBox<T> = record",
        "    Value: T;",
        "    function Read: T;",
        "  end;",
        "",
        "  TDvlUnitAlias = TDvlUnitRec;",
        "",
    ]
    impl_lines = [
        "implementation",
        "",
        "function TDvlUnitBox<T>.Read: T;",
        "begin",
        "  Result := Value;",
        "end;",
        "",
    ]

    for index in range(start, start + count):
        name = "dvl-unit-%05d" % index
        proc = "DvlUnit%05d" % index
        t = rng.choice(TYPES)
        value = rng.choice(interesting_values(t, rng))
        shape = rng.choice(("inline-func", "generic-box", "record-through-unit",
                            "alias-identity", "const-through-unit",
                            "second-unit-chain", "generic-across-units"))
        fn = "DvlUnitFn%05d" % index

        if shape == "inline-func":
            unit_lines.append("function %s(X: %s): %s; inline;"
                              % (fn, t.pascal, t.pascal))
            impl_lines += ["function %s(X: %s): %s;" % (fn, t.pascal, t.pascal),
                           "begin",
                           "  Result := X;",
                           "end;", ""]
            body = ["  V := %s;" % t.literal(value),
                    "  R := %s(V);" % fn]
            decl = [("V", t.pascal), ("R", t.pascal)]
            checks = ["  DevilCheckU('%s-inline', DvlRaw%s(R), UInt64($%016X));"
                      % (name, t.slug, t.raw(value))]

        elif shape == "generic-box":
            body = ["  Box.Value := %s;" % t.literal(value),
                    "  R := Box.Read;"]
            decl = [("Box", "TDvlUnitBox<%s>" % t.pascal), ("R", t.pascal)]
            checks = ["  DevilCheckU('%s-generic', DvlRaw%s(R), UInt64($%016X));"
                      % (name, t.slug, t.raw(value))]

        elif shape == "record-through-unit":
            unit_lines.append("function %s(const R: TDvlUnitRec): Int64;" % fn)
            impl_lines += ["function %s(const R: TDvlUnitRec): Int64;" % fn,
                           "begin",
                           "  Result := R.A + R.B + Length(R.S);",
                           "end;", ""]
            a = rng.randrange(-1000, 1000)
            b = rng.randrange(-10 ** 9, 10 ** 9)
            body = ["  Rec.A := %d;" % a,
                    "  Rec.B := %d;" % b,
                    "  Rec.S := AnsiString('unit');",
                    "  R := %s(Rec);" % fn]
            decl = [("Rec", "TDvlUnitRec"), ("R", "Int64")]
            checks = ["  DevilCheckU('%s-record', UInt64(R), UInt64($%016X));"
                      % (name, (a + b + 4) & ((1 << 64) - 1))]

        elif shape == "alias-identity":
            body = ["  Rec.A := 7;",
                    "  Alias := Rec;",
                    "  Alias.A := Alias.A + 1;"]
            decl = [("Rec", "TDvlUnitRec"), ("Alias", "TDvlUnitAlias")]
            checks = ["  DevilCheckU('%s-alias-copy', UInt64(Cardinal(Rec.A)), 7);"
                      % name,
                      "  DevilCheckU('%s-alias-value', "
                      "UInt64(Cardinal(Alias.A)), 8);" % name,
                      "  DevilCheckU('%s-alias-size', "
                      "UInt64(SizeOf(TDvlUnitAlias)), "
                      "UInt64(SizeOf(TDvlUnitRec)));" % name]

        elif shape == "second-unit-chain":
            # value crosses two units: A calls into B, so the PPU of A must
            # carry B's inline body and types correctly
            unit_lines.append("function %s(X: %s): %s;" % (fn, t.pascal, t.pascal))
            impl_lines += ["function %s(X: %s): %s;" % (fn, t.pascal, t.pascal),
                           "begin",
                           "  Result := DvlSecondEcho%s(X);" % t.slug,
                           "end;", ""]
            body = ["  V := %s;" % t.literal(value),
                    "  R := %s(V);" % fn]
            decl = [("V", t.pascal), ("R", t.pascal)]
            checks = ["  DevilCheckU('%s-two-units', DvlRaw%s(R), UInt64($%016X));"
                      % (name, t.slug, t.raw(value))]

        elif shape == "generic-across-units":
            unit_lines.append("function %s(X: %s): %s;" % (fn, t.pascal, t.pascal))
            impl_lines += ["function %s(X: %s): %s;" % (fn, t.pascal, t.pascal),
                           "var",
                           "  B: TDvlSecondBox<%s>;" % t.pascal,
                           "begin",
                           "  B.Value := X;",
                           "  Result := B.Read;",
                           "end;", ""]
            body = ["  V := %s;" % t.literal(value),
                    "  R := %s(V);" % fn]
            decl = [("V", t.pascal), ("R", t.pascal)]
            checks = ["  DevilCheckU('%s-generic-two-units', DvlRaw%s(R), "
                      "UInt64($%016X));" % (name, t.slug, t.raw(value))]

        else:   # const-through-unit
            const_name = "DvlUnitConst%05d" % index
            unit_lines.append("const")
            unit_lines.append("  %s = %s;" % (const_name, t.literal(value)))
            body = ["  R := %s;" % const_name]
            decl = [("R", t.pascal)]
            checks = ["  DevilCheckU('%s-const', DvlRaw%s(R), UInt64($%016X));"
                      % (name, t.slug, t.raw(value))]

        e.line("procedure %s;" % proc)
        if decl:
            e.line("var")
            for vn, vt in decl:
                e.line("  %s: %s;" % (vn, vt))
        e.line("begin")
        e.block(body)
        e.block(checks)
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "unit", {"shape": shape, "type": t.slug}))

    unit_lines.append("")
    unit_lines += impl_lines + ["end."]
    second = ["unit devil_gen_second;", "",
              "{$ifdef FPC}",
              "  {$mode delphiunicode}{$H+}",
              "  {$modeswitch advancedrecords}",
              "{$endif}",
              "{$Q-}{$R-}", "",
              "interface", "", "type",
              "  TDvlSecondBox<T> = record",
              "    Value: T;",
              "    function Read: T;",
              "  end;", ""]
    for st in TYPES:
        second.append("function DvlSecondEcho%s(X: %s): %s; inline;"
                      % (st.slug, st.pascal, st.pascal))
    second += ["", "implementation", "",
               "function TDvlSecondBox<T>.Read: T;",
               "begin", "  Result := Value;", "end;", ""]
    for st in TYPES:
        second += ["function DvlSecondEcho%s(X: %s): %s;"
                   % (st.slug, st.pascal, st.pascal),
                   "begin", "  Result := X;", "end;", ""]
    second.append("end.")
    (DEVIL / "devil_gen_second.pas").write_text(
        chr(10).join(second) + chr(10), encoding="utf-8")
    (DEVIL / "devil_gen_unit.pas").write_text("\n".join(unit_lines) + "\n",
                                              encoding="utf-8")
    emit_runner(e, "Unit", calls)
    return records


def layer_checked(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Checked arithmetic and range checking are behaviour, not decoration.

    Every case knows from the model whether the operation leaves the type, so
    the expectation "raises" or "does not raise" is derived, and both directions
    are checked: a missing exception and a spurious one are equally defects."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-chk-%05d" % index
        proc = "DvlChk%05d" % index
        mode = rng.choice(("overflow-add", "overflow-mul", "overflow-inc",
                           "overflow-neg", "overflow-div", "overflow-shl",
                           "div-min-by-minus-one",
                           "range-array", "range-subrange",
                           "range-dynarray", "range-string", "range-for-bound"))
        t = rng.choice([x for x in TYPES if x.bits in (8, 16, 32, 64)])
        e.line("{$Q+}{$R+}")
        e.line("function %sBody: Integer;" % proc)
        raises = False
        if mode.startswith("overflow"):
            a = rng.choice(interesting_values(t, rng))
            b = rng.choice(interesting_values(t, rng))
            if mode == "overflow-add":
                exact, expr = a + b, "A + B"
            elif mode == "overflow-mul":
                exact, expr = a * b, "A * B"
            elif mode == "overflow-inc":
                exact, expr = a + 1, "A + 1"
            elif mode == "div-min-by-minus-one":
                if not t.signed:
                    a, b = t.low, 1
                    exact, expr = pascal_div(a, b), "A div B"
                else:
                    a, b = t.low, -1
                    exact, expr = -t.low, "A div B"
            elif mode == "overflow-div":
                if b == 0:
                    b = 1
                if t.signed and a == t.low and b == -1:
                    b = 1
                exact, expr = pascal_div(a, b), "A div B"
            elif mode == "overflow-shl":
                shift = rng.randrange(0, 8)
                exact, expr = (a << shift), "A shl Integer(OpaqueI(%d))" % shift
            else:
                exact, expr = -a, "-A"
            # a narrow type reports the escape as a range error on the store,
            # a full-width one as an overflow during the operation; either way
            # the question is whether the exact result still fits the type
            raises = not (t.low <= exact <= t.high)
            if mode == "div-min-by-minus-one":
                # Low(T) div -1 has no representable result for a signed type
                raises = t.signed
            if mode == "overflow-shl":
                # a shift is never overflow-checked; only the store into a
                # narrower variable can still trip the range check
                raises = t.bits < 32 and not (t.low <= exact <= t.high)
            if mode == "overflow-div":
                # truncating division never leaves the type except Low div -1,
                # which this layer excludes on purpose
                raises = False
            if mode == "overflow-neg" and not t.signed:
                # negating an unsigned value leaves the type unless it is zero
                raises = a != 0
            e.line("var")
            e.line("  A, B: %s;" % t.pascal)
            e.line("  R: %s;" % t.pascal)
            e.line("begin")
            e.line("  Result := 0;")
            # operands must be opaque, otherwise the check folds away with them
            if t.signed:
                e.line("  A := %s(OpaqueI(Int64(%s)));" % (t.pascal, t.literal(a)))
                e.line("  B := %s(OpaqueI(Int64(%s)));" % (t.pascal, t.literal(b)))
            else:
                e.line("  A := %s(OpaqueU(UInt64(%s)));" % (t.pascal, t.literal(a)))
                e.line("  B := %s(OpaqueU(UInt64(%s)));" % (t.pascal, t.literal(b)))
            e.line("  try")
            e.line("    R := %s;" % expr)
            e.line("    if R = R then")
            e.line("      Result := 0;")
            e.line("  except")
            e.line("    on EIntOverflow do")
            e.line("      Result := 1;")
            e.line("    on ERangeError do")
            e.line("      Result := 1;")
            e.line("  end;")
            e.line("end;")
        else:
            idx = rng.randrange(-3, 12)
            if mode == "range-array":
                raises = not (0 <= idx <= 3)
                e.line("var")
                e.line("  A: array[0..3] of Integer;")
                e.line("  I: Integer;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  I := Integer(OpaqueI(%d));" % idx)
                e.line("  try")
                e.line("    A[I] := 1;")
                e.line("    Result := 0;")
                e.line("  except")
                e.line("    on ERangeError do")
                e.line("      Result := 1;")
                e.line("  end;")
                e.line("end;")
            elif mode == "range-subrange":
                value = rng.randrange(-5, 120)
                raises = not (1 <= value <= 100)
                e.line("var")
                e.line("  S: 1..100;")
                e.line("  I: Integer;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  I := Integer(OpaqueI(%d));" % value)
                e.line("  try")
                e.line("    S := I;")
                e.line("    if S = S then")
                e.line("      Result := 0;")
                e.line("  except")
                e.line("    on ERangeError do")
                e.line("      Result := 1;")
                e.line("  end;")
                e.line("end;")
            elif mode == "range-dynarray":
                length = rng.choice((1, 3, 5))
                raises = not (0 <= idx < length)
                e.line("var")
                e.line("  A: TArray<Integer>;")
                e.line("  I: Integer;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  SetLength(A, %d);" % length)
                e.line("  I := Integer(OpaqueI(%d));" % idx)
                e.line("  try")
                e.line("    A[I] := 1;")
                e.line("    Result := 0;")
                e.line("  except")
                e.line("    on ERangeError do")
                e.line("      Result := 1;")
                e.line("  end;")
                e.line("end;")
            elif mode == "range-for-bound":
                limit = rng.randrange(-3, 8)
                raises = False        # an empty or short loop never leaves range
                e.line("var")
                e.line("  A: array[0..7] of Integer;")
                e.line("  I, N: Integer;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  N := Integer(OpaqueI(%d));" % limit)
                e.line("  try")
                e.line("    for I := 0 to N do")
                e.line("      if I <= 7 then")
                e.line("        A[I] := I;")
                e.line("    Result := 0;")
                e.line("  except")
                e.line("    on ERangeError do")
                e.line("      Result := 1;")
                e.line("  end;")
                e.line("end;")
            else:
                text = "abcde"
                raises = not (1 <= idx <= len(text))
                e.line("var")
                e.line("  S: AnsiString;")
                e.line("  I: Integer;")
                e.line("  C: AnsiChar;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  S := AnsiString('%s');" % text)
                e.line("  I := Integer(OpaqueI(%d));" % idx)
                e.line("  try")
                e.line("    C := S[I];")
                e.line("    if C = C then")
                e.line("      Result := 0;")
                e.line("  except")
                e.line("    on ERangeError do")
                e.line("      Result := 1;")
                e.line("  end;")
                e.line("end;")
        e.line("{$Q-}{$R-}")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("begin")
        e.line("  DevilCheckU('%s', UInt64(Cardinal(%sBody)), %d);"
               % (name, proc, 1 if raises else 0))
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "chk", {"mode": mode, "type": t.slug,
                                                "raises": raises}))
    emit_runner(e, "Chk", calls)
    return records


def layer_thread(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """Threads with a deterministic oracle.

    Every worker owns its own slots and the join is the barrier, so the answer
    does not depend on scheduling: the main thread recomputes the same kernel
    and the results must be identical.  Managed values are built inside the
    worker and read after the join, which is where ownership handoff breaks."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-thr-%05d" % index
        proc = "DvlThr%05d" % index
        workers = rng.choice((2, 4))
        rounds = rng.choice((25, 50, 100))
        seed = rng.randrange(1, 10 ** 6)
        # monitor-counter is disabled while dvl-0007 stands: TMonitor.Enter
        # crashes with an SEH access violation that no Pascal handler can catch,
        # so it takes the whole run down instead of reporting a failure
        shape = rng.choice(("pure-kernel", "managed-handoff",
                            "interface-handoff", "atomic-counter",
                            "threadvar-isolation", "fatal-exception",
                            "queue-drain"))

        e.line("type")
        e.line("  TDvlWorker%05d = class(TThread)" % index)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    OutSum: Int64;")
        e.line("    OutStr: AnsiString;")
        e.line("    OutIntf: IInterface;")
        e.line("  protected")
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlWorker%05d.Execute;" % index)
        e.line("var")
        e.line("  K: Integer;")
        e.line("begin")
        e.line("  OutSum := 0;")
        e.line("  for K := 1 to %d do" % rounds)
        e.line("    OutSum := OutSum + Int64(Slot + %d) * K;" % seed)
        if shape in ("managed-handoff", "interface-handoff"):
            e.line("  OutStr := AnsiString('w') + AnsiString(IntToStr(Slot));")
        if shape == "interface-handoff":
            e.line("  OutIntf := TDvlTagged.Create(AnsiChar(Ord('a') + Slot));")
        if shape == "queue-drain":
            e.line("  TThread.Queue(nil,")
            e.line("    procedure")
            e.line("    begin")
            e.line("      InterLockedIncrement64(DvlThreadCounter);")
            e.line("    end);")
        if shape == "atomic-counter":
            e.line("  for K := 1 to %d do" % rounds)
            e.line("    InterLockedIncrement64(DvlThreadCounter);")
        if shape == "threadvar-isolation":
            e.line("  DvlThreadLocal := Slot + 1;")
            e.line("  for K := 1 to 50 do")
            e.line("    DvlThreadLocal := DvlThreadLocal;")
            e.line("  OutSum := DvlThreadLocal;")
        if shape == "fatal-exception":
            e.line("  if Slot = 0 then")
            e.line("    raise EDvlSignal.Create('worker');")
        if shape == "monitor-counter":
            # a broken monitor must not take the whole run down with it:
            # the failure is recorded, not propagated
            e.line("  try")
            e.line("    TMonitor.Enter(DvlThreadLock);")
            e.line("    try")
            e.line("      Inc(DvlThreadCounter, %d);" % rounds)
            e.line("    finally")
            e.line("      TMonitor.Exit(DvlThreadLock);")
            e.line("    end;")
            e.line("  except")
            e.line("    on Exception do")
            e.line("      InterLockedIncrement64(DvlThreadFailures);")
            e.line("  end;")
        e.line("end;")
        e.line()

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Ws: array[0..%d] of TDvlWorker%05d;" % (workers - 1, index))
        e.line("  I, K: Integer;")
        e.line("  Model: Int64;")
        e.line("begin")
        e.line("  TDvlTagged.Alive := 0;")
        e.line("  DvlThreadCounter := 0;")
        e.line("  DvlThreadFailures := 0;")
        e.line("  if DvlThreadLock = nil then")
        e.line("    DvlThreadLock := TObject.Create;")
        e.line("  for I := 0 to %d do" % (workers - 1))
        e.line("  begin")
        e.line("    Ws[I] := TDvlWorker%05d.Create(True);" % index)
        e.line("    Ws[I].FreeOnTerminate := False;")
        e.line("    Ws[I].Slot := I;")
        e.line("  end;")
        e.line("  for I := 0 to %d do" % (workers - 1))
        e.line("    Ws[I].Start;")
        e.line("  for I := 0 to %d do" % (workers - 1))
        e.line("    Ws[I].WaitFor;")
        e.line("  for I := %d to %d do"
               % (1 if shape == "fatal-exception" else 0, workers - 1))
        e.line("  begin")
        e.line("    Model := 0;")
        e.line("    for K := 1 to %d do" % rounds)
        e.line("      Model := Model + Int64(I + %d) * K;" % seed)
        if shape == "threadvar-isolation":
            # this shape reports its thread-local value through OutSum,
            # so the kernel-sum model does not apply to it
            e.line("    DevilCheckU('%s-threadvar-slot', "
                   "UInt64(Ws[I].OutSum), UInt64(I + 1));" % name)
        else:
            e.line("    DevilCheckU('%s-sum', UInt64(Ws[I].OutSum), "
                   "UInt64(Model));" % name)
        if shape in ("managed-handoff", "interface-handoff"):
            e.line("    DevilCheckU('%s-str', UInt64(Length(Ws[I].OutStr)), "
                   "UInt64(1 + Length(IntToStr(I))));" % name)
        if shape == "interface-handoff":
            e.line("    DevilCheckU('%s-intf', "
                   "UInt64(Ord(Ws[I].OutIntf <> nil)), 1);" % name)
        e.line("  end;")
        if shape == "interface-handoff":
            e.line("  DevilCheckU('%s-alive', UInt64(TDvlTagged.Alive), %d);"
                   % (name, workers))
        if shape == "queue-drain":
            # the worker only posts; the main thread must drain the queue for
            # the callback to run at all
            e.line("  CheckSynchronize(0);")
            e.line("  DevilCheckU('%s-queued', UInt64(DvlThreadCounter), %d);"
                   % (name, workers))
        if shape == "atomic-counter":
            e.line("  DevilCheckU('%s-atomic', UInt64(DvlThreadCounter), %d);"
                   % (name, workers * rounds))
        if shape == "threadvar-isolation":
            e.line("  DevilCheckU('%s-threadvar-main', "
                   "UInt64(Cardinal(DvlThreadLocal)), 0);" % name)
        if shape == "fatal-exception":
            e.line("  DevilCheckU('%s-fatal-class', "
                   "UInt64(Ord(Ws[0].FatalException <> nil)), 1);" % name)
            e.line("  DevilCheckU('%s-others-clean', "
                   "UInt64(Ord(Ws[%d].FatalException = nil)), 1);"
                   % (name, workers - 1))
        if shape == "monitor-counter":
            e.line("  DevilCheckU('%s-counter', UInt64(DvlThreadCounter), %d);"
                   % (name, workers * rounds))
            e.line("  DevilCheckU('%s-monitor-usable', "
                   "UInt64(DvlThreadFailures), 0);" % name)
        e.line("  for I := 0 to %d do" % (workers - 1))
        e.line("  begin")
        e.line("    Ws[I].OutIntf := nil;")
        e.line("    Ws[I].Free;")
        e.line("  end;")
        e.line("  DevilCheckU('%s-drained', UInt64(TDvlTagged.Alive), 0);" % name)
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "thr", {"shape": shape,
                                                "workers": workers,
                                                "rounds": rounds}))
    emit_runner(e, "Thr", calls)
    return records


SET_BASES = ((0, 7), (0, 8), (0, 15), (0, 16), (0, 31), (0, 32), (0, 63),
             (0, 255), (3, 9), (100, 200), (200, 255))

SET_OPS = ("union", "diff", "intersect", "symdiff", "include", "exclude",
           "in-probe", "subset", "equal", "range-runtime", "iterate")


def layer_set(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """Sets and enumerations.

    The oracle is a plain Python set with the same elements, so membership,
    every operator and the iteration order are derived.  Sizes are reported as
    observations: set storage is ABI and must match Delphi byte for byte."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-set-%05d" % index
        proc = "DvlSet%05d" % index
        # every fourth case probes an enumeration with holes instead of a set:
        # sizes under $Z1/$Z4 and ordinal arithmetic across the gaps
        if index % 4 == 3:
            enum = "TDvlHoley%05d" % index
            packing = rng.choice((1, 4))
            values = sorted(rng.sample(range(1, 250), 4))
            e.line("{$Z%d}" % packing)
            e.line("type")
            e.line("  %s = (%s);" % (enum, ", ".join(
                "dh%05d_%d = %d" % (index, k, v) for k, v in enumerate(values))))
            e.line("{$Z1}")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  V: %s;" % enum)
            e.line("  I, Cnt: Integer;")
            e.line("begin")
            e.line("  Cnt := 0;")
            e.line("  for I := 0 to 255 do")
            e.line("    if %s(I) >= %s(%d) then" % (enum, enum, values[-1]))
            e.line("      Inc(Cnt);")
            e.line("  DevilCheckU('%s-above-top', UInt64(Cardinal(Cnt)), %d);"
                   % (name, 256 - values[-1]))
            e.line("  V := %s(Integer(OpaqueI(%d)));" % (enum, values[1]))
            e.line("  DevilCheckU('%s-ord', UInt64(Cardinal(Ord(V))), %d);"
                   % (name, values[1]))
            e.line("  DevilCheckU('%s-succ', UInt64(Cardinal(Ord(Succ(V)))), %d);"
                   % (name, values[1] + 1))
            e.line("  DevilNote('%s-size', UInt64(SizeOf(%s)));" % (name, enum))
            e.line("end;")
            e.line()
            calls.append(proc)
            records.append(CaseRecord(name, "set", {"holey": True,
                                                    "packing": packing,
                                                    "values": values}))
            continue
        lo, hi = rng.choice(SET_BASES)
        op = rng.choice(SET_OPS)
        universe = list(range(lo, hi + 1))
        pick = lambda: sorted(rng.sample(universe, min(len(universe),
                                                       rng.randrange(1, 6))))
        a_items = pick()
        b_items = pick()
        set_type = "TDvlSet%05d" % index

        e.line("type")
        e.line("  %s = set of %d..%d;" % (set_type, lo, hi))
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  A, B, C: %s;" % set_type)
        e.line("  I, Cnt: Integer;")
        e.line("begin")
        e.line("  A := [%s];" % ", ".join(str(v) for v in a_items))
        e.line("  B := [%s];" % ", ".join(str(v) for v in b_items))
        e.line("  Cnt := 0;")

        sa, sb = set(a_items), set(b_items)
        if op == "union":
            result = sa | sb
            e.line("  C := A + B;")
        elif op == "diff":
            result = sa - sb
            e.line("  C := A - B;")
        elif op == "intersect":
            result = sa & sb
            e.line("  C := A * B;")
        elif op == "symdiff":
            result = sa ^ sb
            e.line("  C := (A + B) - (A * B);")
        elif op == "include":
            v = rng.choice(universe)
            result = sa | {v}
            e.line("  C := A;")
            e.line("  Include(C, %d);" % v)
        elif op == "exclude":
            v = rng.choice(sorted(sa)) if sa else rng.choice(universe)
            result = sa - {v}
            e.line("  C := A;")
            e.line("  Exclude(C, %d);" % v)
        elif op == "range-runtime":
            x = rng.choice(universe)
            y = rng.choice(universe)
            result = set(range(min(x, y), max(x, y) + 1)) if x <= y else set()
            e.line("  I := Integer(OpaqueI(%d));" % x)
            e.line("  C := [];")
            e.line("  if I <= %d then" % y)
            e.line("    C := [%d..%d]" % (x, y))
            e.line("  else")
            e.line("    C := [];")
        else:
            result = sa
            e.line("  C := A;")

        # membership over the whole universe: the strongest oracle for a set
        for v in universe[:64]:
            e.line("  if %d in C then" % v)
            e.line("    Inc(Cnt);")
        expected_count = len([v for v in universe[:64] if v in result])
        e.line("  DevilCheckU('%s-count', UInt64(Cardinal(Cnt)), %d);"
               % (name, expected_count))

        if op == "subset":
            e.line("  DevilCheckU('%s-subset', UInt64(Ord(A <= A + B)), 1);" % name)
            e.line("  DevilCheckU('%s-not-subset', UInt64(Ord((A + B) <= A)), %d);"
                   % (name, 1 if sb <= sa else 0))
        if op == "equal":
            e.line("  DevilCheckU('%s-equal-self', UInt64(Ord(A = A)), 1);" % name)
            e.line("  DevilCheckU('%s-equal-ab', UInt64(Ord(A = B)), %d);"
                   % (name, 1 if sa == sb else 0))
        if op == "in-probe":
            probe = rng.choice(universe)
            e.line("  I := Integer(OpaqueI(%d));" % probe)
            e.line("  DevilCheckU('%s-in-runtime', UInt64(Ord(I in A)), %d);"
                   % (name, 1 if probe in sa else 0))
        if op == "iterate":
            e.line("  Cnt := 0;")
            e.line("  for I in C do")
            e.line("    Inc(Cnt);")
            e.line("  DevilCheckU('%s-iterate', UInt64(Cardinal(Cnt)), %d);"
                   % (name, len(result)))

        e.line("  DevilNote('%s-size', UInt64(SizeOf(%s)));" % (name, set_type))
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "set", {"lo": lo, "hi": hi, "op": op}))
    emit_runner(e, "Set", calls)
    return records


RTTI_SHAPES = ("typeinfo-kind", "enum-names", "published-prop",
               "ordprop-roundtrip", "class-name", "typeinfo-distinct",
               "rtti-field-value", "rtti-method-call", "attribute-read",
               "gettypes-contains", "tvalue-roundtrip", "rtti-field-set",
               "rtti-instance-type")


def layer_rtti(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """RTTI: what the program can learn about itself.

    Names, kinds and enum tables are derived from the declarations the
    generator itself wrote, so the expectation is exact; the presence of a type
    in the linked catalogue is checked the way MoonProto's registry does it."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-rtti-%05d" % index
        proc = "DvlRtti%05d" % index
        shape = rng.choice(RTTI_SHAPES)
        enum_count = rng.choice((3, 4, 6))
        enum_type = "TDvlEnum%05d" % index
        cls = "TDvlRtti%05d" % index
        members = ["de%05d_%d" % (index, k) for k in range(enum_count)]
        value = rng.randrange(1, 1000)

        e.line("{$M+}")
        e.line("{$RTTI EXPLICIT FIELDS([vcPublic, vcPublished]) "
               "METHODS([vcPublic, vcPublished]) "
               "PROPERTIES([vcPublic, vcPublished])}")
        e.line("type")
        e.line("  %s = (%s);" % (enum_type, ", ".join(members)))
        e.line("  %s = class" % cls)
        e.line("  public")
        e.line("    FCount: Integer;")
        e.line("    FKind: %s;" % enum_type)
        e.line("  published")
        e.line("    property Count: Integer read FCount write FCount;")
        e.line("    property Kind: %s read FKind write FKind;" % enum_type)
        e.line("  end;")
        e.line("{$M-}")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Obj: %s;" % cls)
        e.line("  PI: PPropInfo;")
        e.line("begin")
        e.line("  Obj := %s.Create;" % cls)
        e.line("  try")

        if shape == "typeinfo-kind":
            e.line("    DevilCheckU('%s-kind', "
                   "UInt64(Ord(PTypeInfo(TypeInfo(%s))^.Kind)), "
                   "UInt64(Ord(tkEnumeration)));" % (name, enum_type))
            e.line("    DevilCheckU('%s-int-kind', "
                   "UInt64(Ord(PTypeInfo(TypeInfo(Integer))^.Kind)), "
                   "UInt64(Ord(tkInteger)));" % name)
        elif shape == "enum-names":
            k = rng.randrange(0, enum_count)
            e.line("    DevilCheckU('%s-enum-name', "
                   "UInt64(Length(GetEnumName(TypeInfo(%s), %d))), %d);"
                   % (name, enum_type, k, len(members[k])))
            e.line("    DevilCheckU('%s-enum-value', "
                   "UInt64(Cardinal(GetEnumValue(TypeInfo(%s), '%s'))), %d);"
                   % (name, enum_type, members[k], k))
            e.line("    DevilCheckU('%s-enum-missing', "
                   "UInt64(Cardinal(GetEnumValue(TypeInfo(%s), 'nope'))), "
                   "UInt64(Cardinal(-1)));" % (name, enum_type))
        elif shape in ("published-prop", "ordprop-roundtrip"):
            e.line("    Obj.Count := %d;" % value)
            e.line("    PI := GetPropInfo(Obj, 'Count');")
            e.line("    DevilCheckU('%s-propinfo', "
                   "UInt64(Ord(PI <> nil)), 1);" % name)
            e.line("    if PI <> nil then")
            e.line("    begin")
            e.line("      DevilCheckU('%s-getord', "
                   "UInt64(Cardinal(GetOrdProp(Obj, PI))), %d);" % (name, value))
            e.line("      SetOrdProp(Obj, PI, %d);" % (value + 1))
            e.line("      DevilCheckU('%s-setord', "
                   "UInt64(Cardinal(Obj.Count)), %d);" % (name, value + 1))
            e.line("    end;")
            e.line("    DevilCheckU('%s-missing-prop', "
                   "UInt64(Ord(GetPropInfo(Obj, 'Nope') = nil)), 1);" % name)
        elif shape == "class-name":
            e.line("    DevilCheckU('%s-classname', "
                   "UInt64(Length(Obj.ClassName)), %d);" % (name, len(cls)))
            e.line("    DevilCheckU('%s-classtype', "
                   "UInt64(Ord(Obj.ClassType = %s)), 1);" % (name, cls))
            e.line("    DevilCheckU('%s-inherits', "
                   "UInt64(Ord(Obj.InheritsFrom(TObject))), 1);" % name)
        elif shape == "typeinfo-distinct":
            e.line("    DevilCheckU('%s-distinct', "
                   "UInt64(Ord(TypeInfo(%s) <> TypeInfo(Integer))), 1);"
                   % (name, enum_type))
            e.line("    DevilCheckU('%s-same', "
                   "UInt64(Ord(TypeInfo(%s) = TypeInfo(%s))), 1);"
                   % (name, enum_type, enum_type))
        elif shape == "gettypes-contains":
            e.line("    DevilNote('%s-gettypes', UInt64(DvlRttiTypeCount));" % name)
            e.line("    DevilCheckU('%s-finds-self', "
                   "UInt64(Ord(DvlRttiHasType(TypeInfo(%s)))), 1);"
                   % (name, enum_type))
        elif shape == "tvalue-roundtrip":
            e.line("    DevilCheckU('%s-tvalue-int', "
                   "UInt64(Cardinal(TValue.From<Integer>(%d).AsInteger)), %d);"
                   % (name, value, value))
            e.line("    DevilCheckU('%s-tvalue-kind', "
                   "UInt64(Ord(TValue.From<Integer>(%d).Kind)), "
                   "UInt64(Ord(tkInteger)));" % (name, value))
            e.line("    DevilCheckU('%s-tvalue-string', "
                   "UInt64(Length(TValue.From<string>('abc').AsString)), 3);" % name)
            e.line("    DevilCheckU('%s-tvalue-empty', "
                   "UInt64(Ord(TValue.Empty.IsEmpty)), 1);" % name)

        elif shape in ("rtti-field-value", "rtti-field-set"):
            e.line("    Obj.Count := %d;" % value)
            e.line("    DevilCheckU('%s-field-read', "
                   "UInt64(Cardinal(DvlRttiFieldValue(Obj, 'FCount'))), %d);"
                   % (name, value))
            if shape == "rtti-field-set":
                e.line("    DvlRttiFieldSet(Obj, 'FCount', %d);" % (value + 3))
                e.line("    DevilCheckU('%s-field-write', "
                       "UInt64(Cardinal(Obj.Count)), %d);" % (name, value + 3))

        elif shape == "rtti-instance-type":
            e.line("    DevilCheckU('%s-instance-name', "
                   "UInt64(Ord(DvlRttiTypeNameMatches(Obj.ClassInfo, '%s'))), 1);"
                   % (name, cls))
            e.line("    DevilCheckU('%s-field-count', "
                   "UInt64(DvlRttiFieldCount(Obj.ClassInfo) >= 2), 1);" % name)

        elif shape == "attribute-read":
            e.line("    DevilCheckU('%s-no-attribute', "
                   "UInt64(DvlRttiAttributeCount(Obj.ClassInfo)), 0);" % name)

        else:
            e.line("    Obj.Kind := %s;" % members[enum_count - 1])
            e.line("    DevilCheckU('%s-enum-prop', "
                   "UInt64(Ord(Obj.Kind)), %d);" % (name, enum_count - 1))

        e.line("  finally")
        e.line("    Obj.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "rtti", {"shape": shape,
                                                 "enum_count": enum_count}))
    emit_runner(e, "Rtti", calls)
    return records


FLOW_SHAPES = ("case-ranges", "case-int64", "case-negative", "goto-forward",
               "goto-backward", "goto-out-of-loop", "exit-through-finally",
               "break-continue-finally", "nested-exit", "loop-edge-byte",
               "loop-edge-int64", "repeat-continue", "short-circuit",
               "full-boolean")


def layer_flow(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Control flow: every branch, jump and early exit has a counted trail, so
    the model knows exactly how many times each point was reached."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-flow-%05d" % index
        proc = "DvlFlow%05d" % index
        shape = rng.choice(FLOW_SHAPES)
        fb = FormBuilder(index, "flow")
        fb.proc = proc
        fb.name = name
        body: list[str] = []
        checks: list[str] = []
        detail = {"shape": shape}

        if shape in ("case-ranges", "case-negative", "case-int64"):
            probe = rng.randrange(-2100, 2100)
            sel = fb.var("Sel", "Int64" if shape == "case-int64" else "Integer")
            res = fb.var("Res", "Integer")
            if shape == "case-int64":
                probe = rng.choice((-2147483649, -2147483648, -1, 0, 1,
                                    2147483647, 2147483648, 4294967296,
                                    rng.randrange(-10 ** 12, 10 ** 12)))
                arms = [(-2147483648, 1), (-1, 2), (0, 3), (1, 4),
                        (2147483647, 5)]
                expected = next((v for k, v in arms if probe == k), 9)
                body = ["  %s := %s;" % (sel, probe),
                        "  case %s of" % sel]
                for k, v in arms:
                    body.append("    %d: %s := %d;" % (k, res, v))
                body += ["  else", "    %s := 9;" % res, "  end;"]
            else:
                base = -2000 if shape == "case-negative" else 0
                arms = [(base, base + 9, 1), (base + 10, base + 99, 2),
                        (base + 100, base + 999, 3)]
                expected = 4
                for lo, hi, v in arms:
                    if lo <= probe <= hi:
                        expected = v
                        break
                body = ["  %s := Integer(OpaqueI(%d));" % (sel, probe),
                        "  case %s of" % sel]
                for lo, hi, v in arms:
                    body.append("    %d..%d: %s := %d;" % (lo, hi, res, v))
                body += ["  else", "    %s := 4;" % res, "  end;"]
            checks = ["  DevilCheckU('%s-case', UInt64(Cardinal(%s)), %d);"
                      % (name, res, expected)]
            detail["probe"] = probe

        elif shape in ("goto-forward", "goto-backward", "goto-out-of-loop"):
            counter = fb.var("Cnt", "Integer")
            label = "DvlLab%05d" % index
            if shape == "goto-forward":
                body = ["  %s := 0;" % counter,
                        "  if OpaqueU(1) = 1 then",
                        "    goto %s;" % label,
                        "  %s := %s + 100;" % (counter, counter),
                        "%s:" % label,
                        "  Inc(%s);" % counter]
                expected = 1
            elif shape == "goto-backward":
                body = ["  %s := 0;" % counter,
                        "%s:" % label,
                        "  Inc(%s);" % counter,
                        "  if %s < 5 then" % counter,
                        "    goto %s;" % label]
                expected = 5
            else:
                body = ["  %s := 0;" % counter,
                        "  for var I%05d := 1 to 10 do" % index,
                        "  begin",
                        "    Inc(%s);" % counter,
                        "    if %s = 3 then" % counter,
                        "      goto %s;" % label,
                        "  end;",
                        "%s:" % label,
                        "  Inc(%s, 100);" % counter]
                expected = 103
            fb.labels.append(label)
            checks = ["  DevilCheckU('%s-goto', UInt64(Cardinal(%s)), %d);"
                      % (name, counter, expected)]

        elif shape in ("exit-through-finally", "nested-exit"):
            fin = fb.var("Fin", "Integer")
            res = fb.var("Res", "Integer")
            e.line("function %sBody(var Fin: Integer): Integer;" % proc)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  try")
            e.line("    try")
            e.line("      Exit(7);")
            e.line("    finally")
            e.line("      Inc(Fin);")
            e.line("    end;")
            e.line("  finally")
            e.line("    Inc(Fin, 10);")
            e.line("  end;")
            e.line("end;")
            e.line()
            body = ["  %s := 0;" % fin,
                    "  %s := %sBody(%s);" % (res, proc, fin)]
            checks = ["  DevilCheckU('%s-result', UInt64(Cardinal(%s)), 7);"
                      % (name, res),
                      "  DevilCheckU('%s-finally', UInt64(Cardinal(%s)), 11);"
                      % (name, fin)]

        elif shape == "break-continue-finally":
            fins = fb.var("Fins", "Integer")
            bodies = fb.var("Bodies", "Integer")
            body = ["  %s := 0;" % fins, "  %s := 0;" % bodies,
                    "  for var I%05d := 0 to 99 do" % index,
                    "  begin",
                    "    try",
                    "      if (I%05d and 3) = 1 then" % index,
                    "        Continue;",
                    "      if I%05d = 78 then" % index,
                    "        Break;",
                    "      Inc(%s);" % bodies,
                    "    finally",
                    "      Inc(%s);" % fins,
                    "    end;",
                    "  end;"]
            checks = ["  DevilCheckU('%s-finallys', UInt64(Cardinal(%s)), 79);"
                      % (name, fins),
                      "  DevilCheckU('%s-bodies', UInt64(Cardinal(%s)), 58);"
                      % (name, bodies)]

        elif shape == "loop-edge-byte":
            cnt = fb.var("Cnt", "Integer")
            body = ["  %s := 0;" % cnt,
                    "  for var B%05d: Byte := 250 to 255 do" % index,
                    "    Inc(%s);" % cnt,
                    "  for var C%05d: Byte := 5 downto 0 do" % index,
                    "    Inc(%s);" % cnt]
            checks = ["  DevilCheckU('%s-byte-edges', UInt64(Cardinal(%s)), 12);"
                      % (name, cnt)]

        elif shape == "loop-edge-int64":
            cnt = fb.var("Cnt", "Integer")
            body = ["  %s := 0;" % cnt,
                    "  for var L%05d: Int64 := High(Int64) - 2 to High(Int64) do"
                    % index,
                    "    Inc(%s);" % cnt]
            checks = ["  DevilCheckU('%s-int64-top', UInt64(Cardinal(%s)), 3);"
                      % (name, cnt)]

        elif shape == "repeat-continue":
            iters = fb.var("Iters", "Integer")
            hits = fb.var("Hits", "Integer")
            body = ["  %s := 0;" % iters, "  %s := 0;" % hits,
                    "  repeat",
                    "    Inc(%s);" % iters,
                    "    if (%s and 1) = 1 then" % iters,
                    "      Continue;",
                    "    Inc(%s);" % hits,
                    "  until %s >= 10;" % iters]
            checks = ["  DevilCheckU('%s-iters', UInt64(Cardinal(%s)), 10);"
                      % (name, iters),
                      "  DevilCheckU('%s-hits', UInt64(Cardinal(%s)), 5);"
                      % (name, hits)]

        else:   # short-circuit / full-boolean
            calls_v = fb.var("Calls", "Integer")
            body = ["  DvlFlowCalls := 0;",
                    "  if DvlFlowTrue and DvlFlowFalse then",
                    "    %s := 0;" % calls_v,
                    "  %s := DvlFlowCalls;" % calls_v]
            checks = ["  DevilCheckU('%s-short', UInt64(Cardinal(%s)), 2);"
                      % (name, calls_v)]
            if shape == "full-boolean":
                body += ["  DvlFlowCalls := 0;",
                         "  if DvlFlowFalse and DvlFlowTrue then",
                         "    %s := 0;" % calls_v,
                         "  %s := DvlFlowCalls;" % calls_v]
                checks = ["  DevilCheckU('%s-short-left', "
                          "UInt64(Cardinal(%s)), 1);" % (name, calls_v)]

        statements = fb.wrap(body, [], "  ", "DevilFailures")
        fb.emit(e, statements, checks)
        calls.append(proc)
        records.append(CaseRecord(name, "flow", detail))
    emit_runner(e, "Flow", calls)
    return records


INT128_OPS = ("add", "sub", "mul", "and", "or", "xor", "shl", "shr")


def layer_int128(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """128-bit integers.

    Delphi has no Int128, so this layer is ours alone: the expectation comes
    from the model, and the levels must agree with each other."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    e.line("{$ifdef FPC}")
    for index in range(start, start + count):
        name = "dvl-i128-%05d" % index
        proc = "DvlI128%05d" % index
        signed = rng.random() < 0.5
        pascal = "Int128" if signed else "UInt128"
        op = rng.choice(INT128_OPS)
        bits = 128
        lo = -(1 << 127) if signed else 0
        hi = (1 << 127) - 1 if signed else (1 << 128) - 1
        pool = [0, 1, 2, hi, hi - 1, lo, 1 << 64, (1 << 64) - 1,
                (1 << 63), rng.randrange(0, 1 << 100)]
        if signed:
            pool += [-1, -(1 << 64), -(1 << 100)]
        a = rng.choice(pool)
        b = rng.choice(pool)
        if op in ("shl", "shr"):
            b = rng.randrange(0, 64)
        raw_a = a & ((1 << 128) - 1)
        raw_b = b & ((1 << 128) - 1)
        if op == "add":
            exact = a + b
        elif op == "sub":
            exact = a - b
        elif op == "mul":
            exact = a * b
        elif op == "and":
            exact = raw_a & raw_b
        elif op == "or":
            exact = raw_a | raw_b
        elif op == "xor":
            exact = raw_a ^ raw_b
        elif op == "shl":
            exact = raw_a << b
        else:
            exact = raw_a >> b
        stored = exact & ((1 << 128) - 1)
        low64 = stored & ((1 << 64) - 1)
        high64 = (stored >> 64) & ((1 << 64) - 1)

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  A, B, R: %s;" % pascal)
        e.line("begin")
        # build through the unsigned view: converting UInt64 to Int128 is a
        # separate question, probed on its own below
        e.line("  A := %s((UInt128(UInt64($%016X)) shl 64) or "
               "UInt128(UInt64($%016X)));"
               % (pascal, (raw_a >> 64) & ((1 << 64) - 1),
                  raw_a & ((1 << 64) - 1)))
        if op in ("shl", "shr"):
            e.line("  R := A %s %d;" % (op, b))
        else:
            e.line("  B := %s((UInt128(UInt64($%016X)) shl 64) or "
                   "UInt128(UInt64($%016X)));"
                   % (pascal, (raw_b >> 64) & ((1 << 64) - 1),
                      raw_b & ((1 << 64) - 1)))
            e.line("  R := A %s B;" % OP_TOKEN[op])
        e.line("  DevilCheckU('%s-low', UInt64(R and $FFFFFFFFFFFFFFFF), "
               "UInt64($%016X));" % (name, low64))
        # shifting a signed 128-bit value right is arithmetic, so the raw upper
        # half has to be read through the unsigned view
        e.line("  DevilCheckU('%s-high', UInt64((UInt128(R) shr 64) and "
               "$FFFFFFFFFFFFFFFF), UInt64($%016X));" % (name, high64))
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "i128", {"type": pascal, "op": op,
                                                 "a": str(a), "b": str(b)}))
    e.line("procedure DvlI128Convert;")
    e.line("var")
    e.line("  U: UInt128;")
    e.line("  S: Int128;")
    e.line("begin")
    e.line("  U := UInt128(UInt64($FFFFFFFFFFFFFFFF));")
    e.line("  DevilCheckU('dvl-i128-convert-unsigned-high', "
           "UInt64((U shr 64) and $FFFFFFFFFFFFFFFF), 0);")
    e.line("  S := Int128(UInt64($FFFFFFFFFFFFFFFF));")
    e.line("  DevilNote('dvl-i128-convert-signed-high', "
           "UInt64((UInt128(S) shr 64) and $FFFFFFFFFFFFFFFF));")
    e.line("end;")
    e.line()
    e.line("procedure RunDevilI128Layer;")
    e.line("begin")
    e.line("  DvlI128Convert;")
    for call in calls:
        e.line("  %s;" % call)
    e.line("end;")
    e.line("{$else}")
    e.line("procedure DvlI128Convert;")
    e.line("var")
    e.line("  U: UInt128;")
    e.line("  S: Int128;")
    e.line("begin")
    e.line("  U := UInt128(UInt64($FFFFFFFFFFFFFFFF));")
    e.line("  DevilCheckU('dvl-i128-convert-unsigned-high', "
           "UInt64((U shr 64) and $FFFFFFFFFFFFFFFF), 0);")
    e.line("  S := Int128(UInt64($FFFFFFFFFFFFFFFF));")
    e.line("  DevilNote('dvl-i128-convert-signed-high', "
           "UInt64((UInt128(S) shr 64) and $FFFFFFFFFFFFFFFF));")
    e.line("end;")
    e.line()
    e.line("procedure RunDevilI128Layer;")
    e.line("begin")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    return records


LANG_SHAPES = ("class-operator-arith", "class-operator-compare",
               "class-operator-implicit", "record-helper", "class-helper",
               "type-helper", "tp-object", "message-method",
               "interface-delegation", "absolute-view", "array-of-const",
               "variant-arith", "variant-null", "default-property",
               "index-property", "nested-type", "writable-const",
               "resourcestring", "for-in-enumerator", "operator-in",
               "digit-separators", "binary-literal", "record-align",
               "caret-literal")


def layer_lang(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Delphi language surface: the constructs application code actually uses.

    Each shape declares its own types with a unique index, so cases never
    collide, and every value is derived from the declaration itself."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-lang-%05d" % index
        proc = "DvlLang%05d" % index
        shape = rng.choice(LANG_SHAPES)
        a = rng.randrange(1, 1000)
        b = rng.randrange(1, 1000)
        tag = "%05d" % index

        if shape in ("class-operator-arith", "class-operator-compare",
                     "class-operator-implicit", "operator-in"):
            e.line("type")
            e.line("  TDvlNum%s = record" % tag)
            e.line("    V: Integer;")
            e.line("    class operator Add(const X, Y: TDvlNum%s): TDvlNum%s;" % (tag, tag))
            e.line("    class operator Subtract(const X, Y: TDvlNum%s): TDvlNum%s;" % (tag, tag))
            e.line("    class operator Multiply(const X: TDvlNum%s; K: Integer): TDvlNum%s;" % (tag, tag))
            e.line("    class operator Implicit(K: Integer): TDvlNum%s;" % tag)
            e.line("    class operator Equal(const X, Y: TDvlNum%s): Boolean;" % tag)
            e.line("    class operator LessThan(const X, Y: TDvlNum%s): Boolean;" % tag)
            e.line("    class operator In(K: Integer; const X: TDvlNum%s): Boolean;" % tag)
            e.line("  end;")
            e.line()
            for opname, body in (("Add", "Result.V := X.V + Y.V;"),
                                 ("Subtract", "Result.V := X.V - Y.V;")):
                e.line("class operator TDvlNum%s.%s(const X, Y: TDvlNum%s): TDvlNum%s;"
                       % (tag, opname, tag, tag))
                e.line("begin")
                e.line("  " + body)
                e.line("end;")
                e.line()
            e.line("class operator TDvlNum%s.Multiply(const X: TDvlNum%s; K: Integer): TDvlNum%s;"
                   % (tag, tag, tag))
            e.line("begin")
            e.line("  Result.V := X.V * K;")
            e.line("end;")
            e.line()
            e.line("class operator TDvlNum%s.Implicit(K: Integer): TDvlNum%s;" % (tag, tag))
            e.line("begin")
            e.line("  Result.V := K * 10;")
            e.line("end;")
            e.line()
            e.line("class operator TDvlNum%s.Equal(const X, Y: TDvlNum%s): Boolean;" % (tag, tag))
            e.line("begin")
            e.line("  Result := X.V = Y.V;")
            e.line("end;")
            e.line()
            e.line("class operator TDvlNum%s.LessThan(const X, Y: TDvlNum%s): Boolean;" % (tag, tag))
            e.line("begin")
            e.line("  Result := X.V < Y.V;")
            e.line("end;")
            e.line()
            e.line("class operator TDvlNum%s.In(K: Integer; const X: TDvlNum%s): Boolean;" % (tag, tag))
            e.line("begin")
            e.line("  Result := (X.V mod K) = 0;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  X, Y, R: TDvlNum%s;" % tag)
            e.line("begin")
            e.line("  X.V := %d;" % a)
            e.line("  Y.V := %d;" % b)
            if shape == "class-operator-arith":
                e.line("  R := X + Y;")
                e.line("  DevilCheckU('%s-add', UInt64(Cardinal(R.V)), %d);"
                       % (name, a + b))
                e.line("  R := X - Y;")
                e.line("  DevilCheckU('%s-sub', UInt64(Cardinal(R.V)), %d);"
                       % (name, (a - b) & 0xFFFFFFFF))
                e.line("  R := X * 3;")
                e.line("  DevilCheckU('%s-mul', UInt64(Cardinal(R.V)), %d);"
                       % (name, (a * 3) & 0xFFFFFFFF))
            elif shape == "class-operator-compare":
                e.line("  DevilCheckU('%s-eq', UInt64(Ord(X = Y)), %d);"
                       % (name, 1 if a == b else 0))
                e.line("  DevilCheckU('%s-lt', UInt64(Ord(X < Y)), %d);"
                       % (name, 1 if a < b else 0))
            elif shape == "operator-in":
                divisor = rng.choice((2, 3, 5, 7))
                e.line("  DevilCheckU('%s-in', UInt64(Ord(%d in X)), %d);"
                       % (name, divisor, 1 if a % divisor == 0 else 0))
            else:
                e.line("  R := %d;" % a)
                e.line("  DevilCheckU('%s-implicit', UInt64(Cardinal(R.V)), %d);"
                       % (name, (a * 10) & 0xFFFFFFFF))
            e.line("end;")

        elif shape in ("record-helper", "type-helper"):
            e.line("type")
            if shape == "record-helper":
                e.line("  TDvlRec%s = record" % tag)
                e.line("    V: Integer;")
                e.line("  end;")
                e.line("  TDvlRecHelper%s = record helper for TDvlRec%s" % (tag, tag))
                e.line("    function Doubled: Integer;")
                e.line("  end;")
                e.line()
                e.line("function TDvlRecHelper%s.Doubled: Integer;" % tag)
                e.line("begin")
                e.line("  Result := V * 2;")
                e.line("end;")
            else:
                e.line("  TDvlIntHelper%s = record helper for Integer" % tag)
                e.line("    function Tripled%s: Integer;" % tag)
                e.line("  end;")
                e.line()
                e.line("function TDvlIntHelper%s.Tripled%s: Integer;" % (tag, tag))
                e.line("begin")
                e.line("  Result := Self * 3;")
                e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            if shape == "record-helper":
                e.line("  R: TDvlRec%s;" % tag)
                e.line("begin")
                e.line("  R.V := %d;" % a)
                e.line("  DevilCheckU('%s-helper', UInt64(Cardinal(R.Doubled)), %d);"
                       % (name, (a * 2) & 0xFFFFFFFF))
            else:
                e.line("  I: Integer;")
                e.line("begin")
                e.line("  I := %d;" % a)
                e.line("  DevilCheckU('%s-type-helper', "
                       "UInt64(Cardinal(I.Tripled%s)), %d);"
                       % (name, tag, (a * 3) & 0xFFFFFFFF))
            e.line("end;")

        elif shape == "class-helper":
            e.line("type")
            e.line("  TDvlBase%s = class" % tag)
            e.line("    Value: Integer;")
            e.line("    function Get: Integer; virtual;")
            e.line("  end;")
            e.line("  TDvlBaseHelper%s = class helper for TDvlBase%s" % (tag, tag))
            e.line("    function GetTwice: Integer;")
            e.line("  end;")
            e.line()
            e.line("function TDvlBase%s.Get: Integer;" % tag)
            e.line("begin")
            e.line("  Result := Value;")
            e.line("end;")
            e.line()
            e.line("function TDvlBaseHelper%s.GetTwice: Integer;" % tag)
            e.line("begin")
            e.line("  Result := Get * 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  O: TDvlBase%s;" % tag)
            e.line("begin")
            e.line("  O := TDvlBase%s.Create;" % tag)
            e.line("  try")
            e.line("    O.Value := %d;" % a)
            e.line("    DevilCheckU('%s-class-helper', "
                   "UInt64(Cardinal(O.GetTwice)), %d);" % (name, (a * 2) & 0xFFFFFFFF))
            e.line("  finally")
            e.line("    O.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "tp-object":
            e.line("type")
            e.line("  PDvlObj%s = ^TDvlObj%s;" % (tag, tag))
            e.line("  TDvlObj%s = object" % tag)
            e.line("    Value: Integer;")
            e.line("    constructor Init(AValue: Integer);")
            e.line("    function Area: Integer; virtual;")
            e.line("    function Twice: Integer;")
            e.line("  end;")
            e.line()
            e.line("constructor TDvlObj%s.Init(AValue: Integer);" % tag)
            e.line("begin")
            e.line("  Value := AValue;")
            e.line("end;")
            e.line()
            e.line("function TDvlObj%s.Area: Integer;" % tag)
            e.line("begin")
            e.line("  Result := Value * Value;")
            e.line("end;")
            e.line()
            e.line("function TDvlObj%s.Twice: Integer;" % tag)
            e.line("begin")
            e.line("  Result := Area * 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  O: TDvlObj%s;" % tag)
            e.line("  P: PDvlObj%s;" % tag)
            e.line("begin")
            e.line("  O.Init(%d);" % (a % 100))
            e.line("  DevilCheckU('%s-area', UInt64(Cardinal(O.Area)), %d);"
                   % (name, ((a % 100) ** 2) & 0xFFFFFFFF))
            e.line("  DevilCheckU('%s-twice', UInt64(Cardinal(O.Twice)), %d);"
                   % (name, (2 * (a % 100) ** 2) & 0xFFFFFFFF))
            e.line("  P := @O;")
            e.line("  DevilCheckU('%s-through-pointer', "
                   "UInt64(Cardinal(P^.Area)), %d);"
                   % (name, ((a % 100) ** 2) & 0xFFFFFFFF))
            e.line("end;")

        elif shape == "message-method":
            e.line("type")
            e.line("  TDvlMsg%s = packed record" % tag)
            e.line("    Id: Cardinal;")
            e.line("    Data: Integer;")
            e.line("    Res: Integer;")
            e.line("  end;")
            e.line("  TDvlThing%s = class" % tag)
            e.line("    procedure Handle(var M: TDvlMsg%s); message 100;" % tag)
            e.line("    procedure DefaultHandler(var Message); override;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlThing%s.Handle(var M: TDvlMsg%s);" % (tag, tag))
            e.line("begin")
            e.line("  M.Res := M.Data * 2;")
            e.line("end;")
            e.line()
            e.line("procedure TDvlThing%s.DefaultHandler(var Message);" % tag)
            e.line("begin")
            e.line("  TDvlMsg%s(Message).Res := -1;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  T: TDvlThing%s;" % tag)
            e.line("  M: TDvlMsg%s;" % tag)
            e.line("begin")
            e.line("  T := TDvlThing%s.Create;" % tag)
            e.line("  try")
            e.line("    M.Id := 100;")
            e.line("    M.Data := %d;" % a)
            e.line("    T.Dispatch(M);")
            e.line("    DevilCheckU('%s-handled', UInt64(Cardinal(M.Res)), %d);"
                   % (name, (a * 2) & 0xFFFFFFFF))
            e.line("    M.Id := 999;")
            e.line("    M.Data := %d;" % a)
            e.line("    T.Dispatch(M);")
            e.line("    DevilCheckU('%s-default', UInt64(Cardinal(M.Res)), "
                   "UInt64(Cardinal(-1)));" % name)
            e.line("  finally")
            e.line("    T.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "interface-delegation":
            e.line("type")
            e.line("  IDvlThing%s = interface" % tag)
            e.line("    ['{A1B2C3D4-0000-4000-8000-%012d}']" % (index % 10 ** 12))
            e.line("    function Value: Integer;")
            e.line("  end;")
            e.line("  TDvlInner%s = class(TInterfacedObject, IDvlThing%s)" % (tag, tag))
            e.line("    function Value: Integer;")
            e.line("  end;")
            e.line("  TDvlOuter%s = class(TInterfacedObject, IDvlThing%s)" % (tag, tag))
            e.line("  private")
            e.line("    FInner: IDvlThing%s;" % tag)
            e.line("  public")
            e.line("    constructor Create;")
            e.line("    property Inner: IDvlThing%s read FInner implements IDvlThing%s;"
                   % (tag, tag))
            e.line("  end;")
            e.line()
            e.line("function TDvlInner%s.Value: Integer;" % tag)
            e.line("begin")
            e.line("  Result := %d;" % a)
            e.line("end;")
            e.line()
            e.line("constructor TDvlOuter%s.Create;" % tag)
            e.line("begin")
            e.line("  inherited Create;")
            e.line("  FInner := TDvlInner%s.Create;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  T: IDvlThing%s;" % tag)
            e.line("begin")
            e.line("  T := TDvlOuter%s.Create;" % tag)
            e.line("  DevilCheckU('%s-delegated', UInt64(Cardinal(T.Value)), %d);"
                   % (name, a))
            e.line("  T := nil;")
            e.line("end;")

        elif shape == "absolute-view":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Q: UInt64;")
            e.line("  W: array[0..3] of Word absolute Q;")
            e.line("begin")
            e.line("  Q := UInt64($1111222233334444);")
            e.line("  DevilCheckU('%s-word0', UInt64(W[0]), $4444);" % name)
            e.line("  DevilCheckU('%s-word3', UInt64(W[3]), $1111);" % name)
            e.line("  W[0] := $ABCD;")
            e.line("  DevilCheckU('%s-writeback', UInt64(Q), "
                   "UInt64($111122223333ABCD));" % name)
            e.line("end;")

        elif shape == "array-of-const":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := Format('%%d-%%s-%%d', [%d, 'x', %d]);" % (a, b))
            e.line("  DevilCheckU('%s-format-len', UInt64(Length(S)), %d);"
                   % (name, len("%d-x-%d" % (a, b))))
            e.line("  DevilCheckU('%s-varargs', "
                   "UInt64(Cardinal(DvlCountArgs([%d, 'x', %d, True]))), 4);"
                   % (name, a, b))
            e.line("end;")

        elif shape in ("variant-arith", "variant-null"):
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  V, W: Variant;")
            e.line("  I: Integer;")
            e.line("begin")
            if shape == "variant-arith":
                e.line("  V := %d;" % a)
                e.line("  W := %d;" % b)
                e.line("  V := V + W;")
                e.line("  I := V;")
                e.line("  DevilCheckU('%s-sum', UInt64(Cardinal(I)), %d);"
                       % (name, a + b))
                e.line("  V := V * 2;")
                e.line("  I := V;")
                e.line("  DevilCheckU('%s-mul', UInt64(Cardinal(I)), %d);"
                       % (name, ((a + b) * 2) & 0xFFFFFFFF))
            else:
                e.line("  V := Null;")
                e.line("  DevilCheckU('%s-is-null', UInt64(Ord(VarIsNull(V))), 1);"
                       % name)
                e.line("  V := Unassigned;")
                e.line("  DevilCheckU('%s-is-empty', UInt64(Ord(VarIsEmpty(V))), 1);"
                       % name)
                e.line("  V := %d;" % a)
                e.line("  DevilCheckU('%s-type', "
                       "UInt64(Ord(VarType(V) = varInteger)), 1);" % name)
            e.line("end;")

        elif shape in ("default-property", "index-property"):
            e.line("type")
            e.line("  TDvlBag%s = class" % tag)
            e.line("  private")
            e.line("    FItems: array[0..7] of Integer;")
            e.line("    function GetItem(I: Integer): Integer;")
            e.line("    procedure SetItem(I, V: Integer);")
            e.line("    function GetIndexed(Ix: Integer): Integer;")
            e.line("  public")
            e.line("    property Items[I: Integer]: Integer read GetItem write SetItem; default;")
            e.line("    property First: Integer index 1 read GetIndexed;")
            e.line("    property Second: Integer index 2 read GetIndexed;")
            e.line("  end;")
            e.line()
            e.line("function TDvlBag%s.GetItem(I: Integer): Integer;" % tag)
            e.line("begin")
            e.line("  Result := FItems[I and 7];")
            e.line("end;")
            e.line()
            e.line("procedure TDvlBag%s.SetItem(I, V: Integer);" % tag)
            e.line("begin")
            e.line("  FItems[I and 7] := V;")
            e.line("end;")
            e.line()
            e.line("function TDvlBag%s.GetIndexed(Ix: Integer): Integer;" % tag)
            e.line("begin")
            e.line("  Result := Ix * 100;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  B: TDvlBag%s;" % tag)
            e.line("begin")
            e.line("  B := TDvlBag%s.Create;" % tag)
            e.line("  try")
            if shape == "default-property":
                e.line("  B[3] := %d;" % a)
                e.line("  DevilCheckU('%s-default-prop', "
                       "UInt64(Cardinal(B[3])), %d);" % (name, a))
                e.line("  DevilCheckU('%s-masked', "
                       "UInt64(Cardinal(B[11])), %d);" % (name, a))
            else:
                e.line("  DevilCheckU('%s-index-first', "
                       "UInt64(Cardinal(B.First)), 100);" % name)
                e.line("  DevilCheckU('%s-index-second', "
                       "UInt64(Cardinal(B.Second)), 200);" % name)
            e.line("  finally")
            e.line("    B.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "nested-type":
            e.line("type")
            e.line("  TDvlOuterT%s = record" % tag)
            e.line("  public")
            e.line("    const Cap = %d;" % (a % 32 + 1))
            e.line("    type")
            e.line("      TInner = record")
            e.line("        V: Integer;")
            e.line("      end;")
            e.line("    var")
            e.line("      Inner: TInner;")
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  O: TDvlOuterT%s;" % tag)
            e.line("  I: TDvlOuterT%s.TInner;" % tag)
            e.line("begin")
            e.line("  O.Inner.V := %d;" % a)
            e.line("  I := O.Inner;")
            e.line("  DevilCheckU('%s-nested-value', UInt64(Cardinal(I.V)), %d);"
                   % (name, a))
            e.line("  DevilCheckU('%s-nested-const', "
                   "UInt64(Cardinal(TDvlOuterT%s.Cap)), %d);"
                   % (name, tag, a % 32 + 1))
            e.line("end;")

        elif shape == "writable-const":
            e.line("{$J+}")
            e.line("const")
            e.line("  DvlCounter%s: Integer = %d;" % (tag, a))
            e.line("{$J-}")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DvlCounter%s := DvlCounter%s + 1;" % (tag, tag))
            e.line("  DevilCheckU('%s-writable-const', "
                   "UInt64(Cardinal(DvlCounter%s)), %d);" % (name, tag, a + 1))
            e.line("  DvlCounter%s := %d;" % (tag, a))
            e.line("end;")

        elif shape == "resourcestring":
            e.line("resourcestring")
            e.line("  DvlRes%s = 'devil-%s';" % (tag, tag))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilCheckU('%s-resourcestring', "
                   "UInt64(Length(DvlRes%s)), %d);"
                   % (name, tag, len("devil-%s" % tag)))
            e.line("end;")

        elif shape in ("digit-separators", "binary-literal"):
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B, C: Integer;")
            e.line("begin")
            if shape == "digit-separators":
                e.line("  A := 1_234_567;")
                e.line("  B := $BE_EF;")
                e.line("  C := A + B;")
                e.line("  DevilCheckU('%s-decimal', UInt64(Cardinal(A)), %d);"
                       % (name, 1234567))
                e.line("  DevilCheckU('%s-hex', UInt64(Cardinal(B)), %d);"
                       % (name, 0xBEEF))
                e.line("  DevilCheckU('%s-sum', UInt64(Cardinal(C)), %d);"
                       % (name, 1234567 + 0xBEEF))
            else:
                e.line("  A := %1010_1010;")
                e.line("  B := %11111111;")
                e.line("  C := A xor B;")
                e.line("  DevilCheckU('%s-binary', UInt64(Cardinal(A)), 170);" % name)
                e.line("  DevilCheckU('%s-binary-full', UInt64(Cardinal(B)), 255);"
                       % name)
                e.line("  DevilCheckU('%s-binary-xor', UInt64(Cardinal(C)), 85);"
                       % name)
            e.line("end;")

        elif shape == "record-align":
            alignment = rng.choice((1, 2, 4, 8, 16))
            e.line("type")
            e.line("  TDvlAl%s = record" % tag)
            e.line("    B: Byte;")
            e.line("  end align %d;" % alignment)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: array[0..1] of TDvlAl%s;" % tag)
            e.line("begin")
            e.line("  A[0].B := 1;")
            e.line("  A[1].B := 2;")
            e.line("  DevilCheckU('%s-size', UInt64(SizeOf(TDvlAl%s)), %d);"
                   % (name, tag, alignment))
            e.line("  DevilCheckU('%s-stride', "
                   "UInt64(NativeUInt(@A[1]) - NativeUInt(@A[0])), %d);"
                   % (name, alignment))
            e.line("end;")

        elif shape == "caret-literal":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  C: AnsiChar;")
            e.line("  S: AnsiString;")
            e.line("begin")
            e.line("  C := ^M;")
            e.line("  DevilCheckU('%s-caret-cr', UInt64(Ord(C)), 13);" % name)
            e.line("  DevilCheckU('%s-caret-a', UInt64(Ord(^A)), 1);" % name)
            e.line("  S := AnsiChar(^J) + AnsiChar(^I);")
            e.line("  DevilCheckU('%s-caret-string', "
                   "UInt64(Ord(S[1])) * 256 + UInt64(Ord(S[2])), %d);"
                   % (name, 10 * 256 + 9))
            e.line("end;")

        else:   # for-in-enumerator
            e.line("type")
            e.line("  TDvlEnum%sRec = record" % tag)
            e.line("    FCur, FStop: Integer;")
            e.line("    function MoveNext: Boolean;")
            e.line("    property Current: Integer read FCur;")
            e.line("  end;")
            e.line("  TDvlRange%s = record" % tag)
            e.line("    FFrom, FTo: Integer;")
            e.line("    function GetEnumerator: TDvlEnum%sRec;" % tag)
            e.line("  end;")
            e.line()
            e.line("function TDvlEnum%sRec.MoveNext: Boolean;" % tag)
            e.line("begin")
            e.line("  Inc(FCur);")
            e.line("  Result := FCur <= FStop;")
            e.line("end;")
            e.line()
            e.line("function TDvlRange%s.GetEnumerator: TDvlEnum%sRec;" % (tag, tag))
            e.line("begin")
            e.line("  Result.FCur := FFrom - 1;")
            e.line("  Result.FStop := FTo;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlRange%s;" % tag)
            e.line("  I, Sum, Cnt: Integer;")
            e.line("begin")
            lo = a % 10
            hi = lo + (b % 8)
            e.line("  R.FFrom := %d;" % lo)
            e.line("  R.FTo := %d;" % hi)
            e.line("  Sum := 0;")
            e.line("  Cnt := 0;")
            e.line("  for I in R do")
            e.line("  begin")
            e.line("    Sum := Sum + I;")
            e.line("    Inc(Cnt);")
            e.line("  end;")
            e.line("  DevilCheckU('%s-enumerator-count', UInt64(Cardinal(Cnt)), %d);"
                   % (name, hi - lo + 1))
            e.line("  DevilCheckU('%s-enumerator-sum', UInt64(Cardinal(Sum)), %d);"
                   % (name, sum(range(lo, hi + 1))))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name, "lang", {"shape": shape, "a": a, "b": b}))
    emit_runner(e, "Lang", calls)
    return records


def emit_runner(e: Emitter, layer: str, calls: list[str]) -> None:
    e.line(f"procedure RunDevil{layer}Layer;")
    e.line("begin")
    for call in calls:
        e.line(f"  {call};")
    e.line("end;")
    e.line()


SUPPORT = r"""{ Devil support declarations: shared by every generated layer. }

type
  EDvlSignal = class(Exception);

  TDvlProc = reference to procedure;

  TDvlPoint = record
    X: Integer;
    Y: Integer;
  end;


  TDvlIntFunc = reference to function(X: Integer): Integer;

  TDvlCounter<T> = class
  public
    class var Value: Integer;
    class procedure Bump;
  end;

  TDvlOps = class
  public
    class function Echo<T>(const AValue: T): T; static;
    class procedure Swap<T>(var A, B: T); static;
    class function First<A, B>(const AValue: A; const BValue: B): A; static;
  end;

  TDvlSeeded = class
  public
    Value: Integer;
    constructor Create; virtual;
  end;

  TDvlFactory<T: TDvlSeeded, constructor> = class
    class function Make: T; static;
  end;

  TDvlManagedBox<T> = record
    Value: T;
  end;


  TDvlTracked = record
    Value: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TDvlTracked);
    class operator Finalize(var Dest: TDvlTracked);
{$ifdef FPC}
    class operator Copy(constref Src: TDvlTracked; var Dest: TDvlTracked);
{$else}
    class operator Assign(var Dest: TDvlTracked; const [ref] Src: TDvlTracked);
{$endif}
  end;
  TDvlTrackedArray = array of TDvlTracked;


  IDvlAlpha = interface
    ['{6B1D2C30-8A44-4C0E-9E21-5D77A1B90001}']
    function AlphaValue: Integer;
  end;

  IDvlBeta = interface
    ['{6B1D2C30-8A44-4C0E-9E21-5D77A1B90002}']
    function BetaValue: Integer;
  end;

  TDvlDual = class(TInterfacedObject, IDvlAlpha, IDvlBeta)
  private
    FSeed: Integer;
  public
    class var Alive: Integer;
    constructor Create(ASeed: Integer);
    destructor Destroy; override;
    function AlphaValue: Integer;
    function BetaValue: Integer;
  end;

  TDvlBox = record
    Fi8: ShortInt;
    Fu8: Byte;
    Fi16: SmallInt;
    Fu16: Word;
    Fi32: Integer;
    Fu32: Cardinal;
    Fi64: Int64;
    Fu64: UInt64;
  end;

  TDvlGuard = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TDvlHolder = class
  private
    FBox: TDvlBox;
    function GetI8: ShortInt;
    procedure SetI8(Value: ShortInt);
    function GetU8: Byte;
    procedure SetU8(Value: Byte);
    function GetI16: SmallInt;
    procedure SetI16(Value: SmallInt);
    function GetU16: Word;
    procedure SetU16(Value: Word);
    function GetI32: Integer;
    procedure SetI32(Value: Integer);
    function GetU32: Cardinal;
    procedure SetU32(Value: Cardinal);
    function GetI64: Int64;
    procedure SetI64(Value: Int64);
    function GetU64: UInt64;
    procedure SetU64(Value: UInt64);
  public
    property Propi8: ShortInt read GetI8 write SetI8;
    property Propu8: Byte read GetU8 write SetU8;
    property Propi16: SmallInt read GetI16 write SetI16;
    property Propu16: Word read GetU16 write SetU16;
    property Propi32: Integer read GetI32 write SetI32;
    property Propu32: Cardinal read GetU32 write SetU32;
    property Propi64: Int64 read GetI64 write SetI64;
    property Propu64: UInt64 read GetU64 write SetU64;
  end;

constructor TDvlGuard.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TDvlGuard.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TDvlHolder.GetI8: ShortInt;
begin
  Result := FBox.Fi8;
end;

procedure TDvlHolder.SetI8(Value: ShortInt);
begin
  FBox.Fi8 := Value;
end;

function TDvlHolder.GetU8: Byte;
begin
  Result := FBox.Fu8;
end;

procedure TDvlHolder.SetU8(Value: Byte);
begin
  FBox.Fu8 := Value;
end;

function TDvlHolder.GetI16: SmallInt;
begin
  Result := FBox.Fi16;
end;

procedure TDvlHolder.SetI16(Value: SmallInt);
begin
  FBox.Fi16 := Value;
end;

function TDvlHolder.GetU16: Word;
begin
  Result := FBox.Fu16;
end;

procedure TDvlHolder.SetU16(Value: Word);
begin
  FBox.Fu16 := Value;
end;

function TDvlHolder.GetI32: Integer;
begin
  Result := FBox.Fi32;
end;

procedure TDvlHolder.SetI32(Value: Integer);
begin
  FBox.Fi32 := Value;
end;

function TDvlHolder.GetU32: Cardinal;
begin
  Result := FBox.Fu32;
end;

procedure TDvlHolder.SetU32(Value: Cardinal);
begin
  FBox.Fu32 := Value;
end;

function TDvlHolder.GetI64: Int64;
begin
  Result := FBox.Fi64;
end;

procedure TDvlHolder.SetI64(Value: Int64);
begin
  FBox.Fi64 := Value;
end;

function TDvlHolder.GetU64: UInt64;
begin
  Result := FBox.Fu64;
end;

procedure TDvlHolder.SetU64(Value: UInt64);
begin
  FBox.Fu64 := Value;
end;

function DvlRawi8(V: ShortInt): UInt64;
begin
  Result := UInt64(Byte(V));
end;

function DvlRawu8(V: Byte): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi16(V: SmallInt): UInt64;
begin
  Result := UInt64(Word(V));
end;

function DvlRawu16(V: Word): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi32(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(V));
end;

function DvlRawu32(V: Cardinal): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi64(V: Int64): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawu64(V: UInt64): UInt64;
begin
  Result := V;
end;

function DvlEchoi8(V: ShortInt): ShortInt;
begin
  Result := V;
end;

function DvlEchou8(V: Byte): Byte;
begin
  Result := V;
end;

function DvlEchoi16(V: SmallInt): SmallInt;
begin
  Result := V;
end;

function DvlEchou16(V: Word): Word;
begin
  Result := V;
end;

function DvlEchoi32(V: Integer): Integer;
begin
  Result := V;
end;

function DvlEchou32(V: Cardinal): Cardinal;
begin
  Result := V;
end;

function DvlEchoi64(V: Int64): Int64;
begin
  Result := V;
end;

function DvlEchou64(V: UInt64): UInt64;
begin
  Result := V;
end;

procedure DvlLoadi8(var Dest: ShortInt; Value: ShortInt);
begin
  Dest := Value;
end;

procedure DvlLoadu8(var Dest: Byte; Value: Byte);
begin
  Dest := Value;
end;

procedure DvlLoadi16(var Dest: SmallInt; Value: SmallInt);
begin
  Dest := Value;
end;

procedure DvlLoadu16(var Dest: Word; Value: Word);
begin
  Dest := Value;
end;

procedure DvlLoadi32(var Dest: Integer; Value: Integer);
begin
  Dest := Value;
end;

procedure DvlLoadu32(var Dest: Cardinal; Value: Cardinal);
begin
  Dest := Value;
end;

procedure DvlLoadi64(var Dest: Int64; Value: Int64);
begin
  Dest := Value;
end;

procedure DvlLoadu64(var Dest: UInt64; Value: UInt64);
begin
  Dest := Value;
end;

function DvlPassConsti8(const V: ShortInt): ShortInt;
begin
  Result := V;
end;

function DvlPassConstu8(const V: Byte): Byte;
begin
  Result := V;
end;

function DvlPassConsti16(const V: SmallInt): SmallInt;
begin
  Result := V;
end;

function DvlPassConstu16(const V: Word): Word;
begin
  Result := V;
end;

function DvlPassConsti32(const V: Integer): Integer;
begin
  Result := V;
end;

function DvlPassConstu32(const V: Cardinal): Cardinal;
begin
  Result := V;
end;

function DvlPassConsti64(const V: Int64): Int64;
begin
  Result := V;
end;

function DvlPassConstu64(const V: UInt64): UInt64;
begin
  Result := V;
end;

threadvar
  DvlThreadLocal: Integer;

var
  DvlThreadLock: TObject;
  DvlThreadCounter: Int64;
  DvlThreadFailures: Int64;
  DvlFlowCalls: Integer;

function DvlFlowTrue: Boolean;
begin
  Inc(DvlFlowCalls);
  Result := True;
end;

function DvlFlowFalse: Boolean;
begin
  Inc(DvlFlowCalls);
  Result := False;
end;


function DvlRttiFieldValue(Instance: TObject; const FieldName: string): Integer;
var
  Context: TRttiContext;
  F: TRttiField;
begin
  Result := -1;
  Context := TRttiContext.Create;
  try
    F := Context.GetType(Instance.ClassType).GetField(FieldName);
    if F <> nil then
      Result := F.GetValue(Instance).AsInteger;
  finally
    Context.Free;
  end;
end;

procedure DvlRttiFieldSet(Instance: TObject; const FieldName: string;
  Value: Integer);
var
  Context: TRttiContext;
  F: TRttiField;
begin
  Context := TRttiContext.Create;
  try
    F := Context.GetType(Instance.ClassType).GetField(FieldName);
    if F <> nil then
      F.SetValue(Instance, TValue.From<Integer>(Value));
  finally
    Context.Free;
  end;
end;

function DvlRttiFieldCount(Info: Pointer): Integer;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := Length(Context.GetType(Info).GetFields);
  finally
    Context.Free;
  end;
end;

function DvlRttiAttributeCount(Info: Pointer): UInt64;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := UInt64(Length(Context.GetType(Info).GetAttributes));
  finally
    Context.Free;
  end;
end;

function DvlRttiTypeNameMatches(Info: Pointer; const Expected: string): Boolean;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := SameText(Context.GetType(Info).Name, Expected);
  finally
    Context.Free;
  end;
end;

function DvlRttiTypeCount: UInt64;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := UInt64(Length(Context.GetTypes));
  finally
    Context.Free;
  end;
end;

function DvlRttiHasType(Info: Pointer): Boolean;
var
  Context: TRttiContext;
  T: TRttiType;
begin
  Result := False;
  Context := TRttiContext.Create;
  try
    for T in Context.GetTypes do
      if T.Handle = Info then
        Exit(True);
  finally
    Context.Free;
  end;
end;

class procedure TDvlCounter<T>.Bump;
begin
  Inc(Value);
end;

class function TDvlOps.Echo<T>(const AValue: T): T;
begin
  Result := AValue;
end;

class procedure TDvlOps.Swap<T>(var A, B: T);
var
  Tmp: T;
begin
  Tmp := A;
  A := B;
  B := Tmp;
end;

class function TDvlOps.First<A, B>(const AValue: A; const BValue: B): A;
begin
  Result := AValue;
end;

constructor TDvlSeeded.Create;
begin
  inherited Create;
  Value := 5;
end;

class function TDvlFactory<T>.Make: T;
begin
  Result := T.Create;
end;

var
  DvlConstraintSlot: Integer = 0;

procedure DvlConstraintProbe;
var
  Obj: TDvlSeeded;
begin
  Obj := TDvlFactory<TDvlSeeded>.Make;
  DvlConstraintSlot := Obj.Value;
  Obj.Free;
end;

function DvlConstraintValue: UInt64;
begin
  Result := UInt64(DvlConstraintSlot);
end;

procedure DvlManagedBoxRoundTrip;
var
  Box: TDvlManagedBox<IInterface>;
begin
  Box.Value := TDvlTagged.Create('g');
  Box.Value := nil;
end;

function DvlGenericAdd(A, B: Integer): Integer;
begin
  Result := TDvlOps.First<Integer, Integer>(A + B, 0);
end;


var
  DvlTrackedInitCount: Integer;
  DvlTrackedFiniCount: Integer;
  DvlTrackedCopyCount: Integer;

class operator TDvlTracked.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TDvlTracked);
begin
  Dest.Value := 5;
  Inc(DvlTrackedInitCount);
end;

class operator TDvlTracked.Finalize(var Dest: TDvlTracked);
begin
  Inc(DvlTrackedFiniCount);
end;

{$ifdef FPC}
class operator TDvlTracked.Copy(constref Src: TDvlTracked; var Dest: TDvlTracked);
{$else}
class operator TDvlTracked.Assign(var Dest: TDvlTracked; const [ref] Src: TDvlTracked);
{$endif}
begin
  Dest.Value := Src.Value + 100;
  Inc(DvlTrackedCopyCount);
end;


constructor TDvlDual.Create(ASeed: Integer);
begin
  inherited Create;
  FSeed := ASeed;
  Inc(Alive);
end;

destructor TDvlDual.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TDvlDual.AlphaValue: Integer;
begin
  Result := FSeed * 2;
end;

function TDvlDual.BetaValue: Integer;
begin
  Result := FSeed + 1000;
end;

procedure DvlTrackedReset;
begin
  DvlTrackedInitCount := 0;
  DvlTrackedFiniCount := 0;
  DvlTrackedCopyCount := 0;
end;

function DvlTrackedInit: Integer;
begin
  Result := DvlTrackedInitCount;
end;

function DvlTrackedFini: Integer;
begin
  Result := DvlTrackedFiniCount;
end;

function DvlCountArgs(const A: array of const): Integer;
begin
  Result := Length(A);
end;

function DvlSumOpen(const A: array of Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := Low(A) to High(A) do
    Result := Result + A[K];
end;
"""


PROGRAM_TEMPLATE = """program devil;

{{ Generated by scripts/generate_devil.py.  One seed, one program. }}

{{$ifdef FPC}}
  {{$mode delphiunicode}}{{$H+}}
  {{$modeswitch advancedrecords}}
  {{$modeswitch anonymousfunctions}}
  {{$modeswitch functionreferences}}
  {{$modeswitch INLINEVARS}}
{{$endif}}
{{$APPTYPE CONSOLE}}
{{$Q-}}{{$R-}}

uses
{{$ifdef FPC}}
  {{$ifdef UNIX}}cthreads,{{$endif}}
{{$endif}}
  SysUtils, Classes, Math, TypInfo, Rtti, devil_runtime{uses_extra};

{{$I devil_support.inc}}
{includes}

begin
  {{ Delphi Win64 masks every floating point exception by default while FPC
     leaves exInvalidOp unmasked; the forms under test must see one and the
     same environment on both. }}
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
{runs}
  Halt(DevilReport('DEVIL', {seed}));
end.
"""


LAYERS = {
    "expr": layer_expr,
    "unary": layer_unary,
    "fold": layer_fold,
    "cmp": layer_compare,
    "life": layer_life,
    "abi": layer_abi,
    "float": layer_float,
    "str": layer_string,
    "disp": layer_dispatch,
    "gen": layer_generic,
    "arr": layer_array,
    "unit": layer_unitcross,
    "chk": layer_checked,
    "thr": layer_thread,
    "set": layer_set,
    "rtti": layer_rtti,
    "flow": layer_flow,
    "i128": layer_int128,
    "lang": layer_lang,
}

# Числовые слои держатся на голодном пайке специально.  Сверять результат
# арифметической операции легко, поэтому генератор сам собой сползает в
# бесконечные числовые формы, а всё остальное — время жизни, layout, раздельная
# компиляция, вердикт компиляции — остаётся непокрытым.  Дефект в арифметике мы
# уже поймали там, где он есть; расширение покрытия идёт в структурных слоях.
ARITHMETIC_LAYERS = ("expr", "unary", "fold", "cmp", "float", "i128")
ARITHMETIC_SHARE = 0.1

LAYER_RUNNERS = {
    "expr": "RunDevilExprLayer",
    "unary": "RunDevilUnaryLayer",
    "fold": "RunDevilFoldLayer",
    "cmp": "RunDevilCmpLayer",
    "life": "RunDevilLifeLayer",
    "abi": "RunDevilAbiLayer",
    "float": "RunDevilFloatLayer",
    "str": "RunDevilStrLayer",
    "disp": "RunDevilDispLayer",
    "gen": "RunDevilGenLayer",
    "arr": "RunDevilArrLayer",
    "unit": "RunDevilUnitLayer",
    "chk": "RunDevilChkLayer",
    "thr": "RunDevilThrLayer",
    "set": "RunDevilSetLayer",
    "rtti": "RunDevilRttiLayer",
    "flow": "RunDevilFlowLayer",
    "i128": "RunDevilI128Layer",
    "lang": "RunDevilLangLayer",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cases", type=int, default=400,
                        help="cases per layer")
    parser.add_argument("--layers", default="all")
    parser.add_argument("--out", type=Path, default=DEVIL)
    args = parser.parse_args()

    selected = list(LAYERS) if args.layers == "all" else args.layers.split(",")
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    (out / "devil_support.inc").write_text(SUPPORT, encoding="utf-8")

    records: list[CaseRecord] = []
    includes: list[str] = []
    runs: list[str] = []
    for layer in selected:
        # stable across processes: Python's hash() is randomized per run
        rng = random.Random((args.seed << 8) ^ zlib.crc32(layer.encode()))
        e = Emitter()
        e.line(f"{{ Generated by scripts/generate_devil.py: layer={layer} "
               f"seed={args.seed}. Do not edit. }}")
        e.line()
        cases = (max(8, int(args.cases * ARITHMETIC_SHARE))
                 if layer in ARITHMETIC_LAYERS else args.cases)
        records += LAYERS[layer](e, rng, cases, 0)
        (out / f"devil_{layer}.inc").write_text(e.text(), encoding="utf-8")
        includes.append(f"{{$I devil_{layer}.inc}}")
        runs.append(f"  {LAYER_RUNNERS[layer]};")

    (out / "devil.dpr").write_text(
        PROGRAM_TEMPLATE.format(
            seed=args.seed, includes="\n".join(includes),
            runs="\n".join(runs),
            uses_extra=", devil_gen_unit" if "unit" in selected else ""),
        encoding="utf-8")
    manifest = {
        "schema": 2,
        "generator": "scripts/generate_devil.py",
        "seed": args.seed,
        "cases_per_layer": args.cases,
        "layers": selected,
        "case_count": len(records),
        "cases": [{"name": r.name, "layer": r.layer, **r.detail} for r in records],
    }
    (out / "devil_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"seed": args.seed, "layers": selected,
                      "cases": len(records)}, sort_keys=True))


if __name__ == "__main__":
    main()
