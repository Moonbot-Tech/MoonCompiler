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
import itertools
import json
import os
import random
import re
import shutil
import zlib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEVIL = ROOT / "tests" / "devil"
# куда генератор кладёт файлы этого прогона: слои, пишущие собственные юниты,
# обязаны спрашивать здесь, а не у каталога комплекта
OUTPUT_DIR = DEVIL


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
        # Delphi rejects a constant count at or past the width outright, so the
        # generated form stays inside it; the disagreement itself is recorded
        # once in the verdict corpus instead of poisoning every expression
        b = rng.randrange(0, t.promoted_bits)
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
            e.line("{$ifdef FPC}{$push}{$optimization off}{$endif}")
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
            e.line("{$ifdef FPC}{$pop}{$endif}")
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


def emit_u64_mod_mask_matrix(e: Emitter) -> CaseRecord:
    """Pin the x86-64 immediate-encoding boundary as a semantic matrix.

    Random arithmetic does exercise ``mod``, but it is very unlikely to pick
    both a UInt64 power-of-two divisor and a mask which cannot be represented
    by x86-64's sign-extended 32-bit immediate.  Keep several powers and
    consumers together so the class does not collapse back to one reproducer.
    """
    name = "dvl-expr-u64-mod-mask-matrix"
    e.line("procedure DvlExprU64ModMaskMatrix;")
    e.line("var")
    e.line("  Value, Got: UInt64;")
    e.line("  Box: TDvlBox;")
    e.line("  I: Integer;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  Value := OpaqueU(UInt64($FEDCBA9876543210));")
    e.line("  Got := Value mod UInt64($0000000100000000);")
    e.line("  DevilCheckU('%s-2p32-assign', Got, UInt64($76543210));" % name)
    e.line("  Box.Fu64 := Value mod UInt64($0000000200000000);")
    e.line("  DevilCheckU('%s-2p33-field', Box.Fu64, "
           "UInt64($0000000076543210));" % name)
    e.line("  Got := DvlEchoU64(Value mod UInt64($0000800000000000));")
    e.line("  DevilCheckU('%s-2p47-argument', Got, "
           "UInt64($00003A9876543210));" % name)
    e.line("  Got := 0;")
    e.line("  for I := 0 to Integer(OpaqueI(0)) do")
    e.line("    Got := Value mod UInt64($8000000000000000);")
    e.line("  DevilCheckU('%s-2p63-loop', Got, "
           "UInt64($7EDCBA9876543210));" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "expr", {
        "class": "u64-power-of-two-modulus-mask",
        "powers": [32, 33, 47, 63],
        "consumers": ["assign", "field", "argument", "loop"],
    })


def emit_signed_widen_after_arithmetic_matrix(e: Emitter) -> CaseRecord:
    """Keep a signed 32-bit result signed when it enters a 64-bit consumer.

    A value-range peephole once removed MOVSXD after arithmetic because it
    reasoned about the mathematical inputs, not the wrapped 32-bit producer.
    Exercise the transition with several producers and consumers so this is a
    code-generation class rather than a copy of the original reproducer.
    """
    name = "dvl-expr-signed-widen-after-arithmetic-matrix"
    e.line("function DvlExprWidenAfterSar(W: Word): Int64;")
    e.line("var")
    e.line("  X: LongInt;")
    e.line("begin")
    e.line("  X := W;")
    e.line("  Inc(X, $7FFF8001);")
    e.line("  {$ifdef FPC}")
    e.line("  Result := SarLongint(X, 31);")
    e.line("  {$else}")
    e.line("  Result := -Ord(X < 0);")
    e.line("  {$endif}")
    e.line("end;")
    e.line()
    e.line("function DvlExprWidenAfterAdd(Value: Integer): Int64;")
    e.line("var")
    e.line("  X: Integer;")
    e.line("begin")
    e.line("  X := Value;")
    e.line("  Inc(X);")
    e.line("  Result := X;")
    e.line("end;")
    e.line()
    e.line("function DvlExprWidenAfterMul(Value: Integer): Int64;")
    e.line("var")
    e.line("  X: Integer;")
    e.line("begin")
    e.line("  X := Value * 3;")
    e.line("  Result := X;")
    e.line("end;")
    e.line()
    e.line("procedure DvlExprSignedWidenAfterArithmeticMatrix;")
    e.line("var")
    e.line("  Box: TDvlBox;")
    e.line("  Got: Int64;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    for value, expected in ((0, 0), (32766, 0), (32767, -1),
                            (32768, -1), (65535, -1)):
        e.line("  DevilCheckBool('%s-sar-%d', "
               "DvlExprWidenAfterSar(%d) = %d);"
               % (name, value, value, expected))
    e.line("  Got := DvlExprWidenAfterAdd(Integer(OpaqueI(High(Integer))));")
    e.line("  DevilCheckBool('%s-add-return', Got = Low(Integer));" % name)
    e.line("  Box.Fi64 := DvlExprWidenAfterMul(Integer(OpaqueI(715827883)));")
    e.line("  DevilCheckBool('%s-mul-field', Box.Fi64 = Int64(-2147483647));"
           % name)
    e.line("  Got := DvlEchoi64(DvlExprWidenAfterMul("
           "Integer(OpaqueI(-715827883))));")
    e.line("  DevilCheckBool('%s-mul-argument', Got = High(Integer));" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "expr", {
        "class": "signed-32-bit-producer-to-64-bit-consumer",
        "producers": ["add", "multiply", "arithmetic-shift"],
        "consumers": ["return", "field", "argument"],
        "boundaries": ["sign-bit-clear", "sign-bit-set", "wrapped"],
    })


def layer_expr(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Same-type binary arithmetic: model oracle plus in-program second path."""
    records: list[CaseRecord] = [
        emit_u64_mod_mask_matrix(e),
        emit_signed_widen_after_arithmetic_matrix(e),
    ]
    calls: list[str] = ["DvlExprU64ModMaskMatrix",
                        "DvlExprSignedWidenAfterArithmeticMatrix"]
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
        # a shift count is a plain integer, not a value of the shifted type:
        # dressing it in the narrow type makes Delphi reject the constant
        expr_b = (str(b) if op in ("shl", "shr")
                  else fb.operand("b", source_b, t, b))
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


def emit_delphi_hilo_matrix(e: Emitter) -> CaseRecord:
    """Delphi Hi/Lo always selects the low two bytes of an ordinal value."""
    name = "dvl-unary-delphi-hilo-matrix"
    e.line("procedure DvlUnaryDelphiHiLoMatrix;")
    e.line("const")
    e.line("  NamedU64: UInt64 = $FEDCBA9876543210;")
    e.line("var")
    e.line("  W: Word;")
    e.line("  I: Integer;")
    e.line("  C: Cardinal;")
    e.line("  S: Int64;")
    e.line("  U: UInt64;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  W := Word(OpaqueU($1234));")
    e.line("  I := Integer(OpaqueU($12345678));")
    e.line("  C := Cardinal(OpaqueU($89ABCDEF));")
    e.line("  S := Int64(OpaqueU($0123456789ABCDEF));")
    e.line("  U := OpaqueU($FEDCBA9876543210);")
    e.line("  DevilCheckU('%s-word-hi', UInt64(Hi(W)), $12);" % name)
    e.line("  DevilCheckU('%s-word-lo', UInt64(Lo(W)), $34);" % name)
    e.line("  DevilCheckU('%s-integer-hi', UInt64(Hi(I)), $56);" % name)
    e.line("  DevilCheckU('%s-integer-lo', UInt64(Lo(I)), $78);" % name)
    e.line("  DevilCheckU('%s-cardinal-hi', UInt64(Hi(C)), $CD);" % name)
    e.line("  DevilCheckU('%s-cardinal-lo', UInt64(Lo(C)), $EF);" % name)
    e.line("  DevilCheckU('%s-int64-hi', UInt64(Hi(S)), $CD);" % name)
    e.line("  DevilCheckU('%s-int64-lo', UInt64(Lo(S)), $EF);" % name)
    e.line("  DevilCheckU('%s-uint64-hi', UInt64(Hi(U)), $32);" % name)
    e.line("  DevilCheckU('%s-uint64-lo', UInt64(Lo(U)), $10);" % name)
    e.line("  DevilCheckU('%s-constant-hi',"
           " UInt64(Hi(UInt64($FEDCBA9876543210))), $32);" % name)
    e.line("  DevilCheckU('%s-named-lo', UInt64(Lo(NamedU64)), $10);" % name)
    e.line("  DevilCheckU('%s-runtime-result-size', UInt64(SizeOf(Hi(U))), 2);" % name)
    e.line("  DevilCheckU('%s-constant-result-size',"
           " UInt64(SizeOf(Hi(UInt64($FEDCBA9876543210)))), 1);" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "unary", {
        "shape": "delphi-hi-lo-byte-selection",
        "types": ["word", "integer", "cardinal", "int64", "uint64"],
        "sources": ["opaque", "literal", "typed-constant"],
    })


def layer_unary(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Unary operators: model oracle."""
    records: list[CaseRecord] = [emit_delphi_hilo_matrix(e)]
    calls: list[str] = ["DvlUnaryDelphiHiLoMatrix"]
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
    # The finalizer-throw open-array repair is FPC-specific and its exact
    # regression lives in RTL-test/semantic/openarray_finalize_throw_semantic.dpr.
    # Running it inside the cross-compiler monolith aborts DCC during implicit
    # local finalization and destroys all later Delphi oracles.
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


def emit_delphi_set_layout_matrix(e: Emitter) -> CaseRecord:
    """Pin Delphi set buckets and byte-aligned record/class placement."""
    name = "dvl-abi-delphi-set-layout-matrix"
    e.line("type")
    e.line("  TDvlSet0 = set of 0..0;")
    e.line("  TDvlSet8 = set of 0..8;")
    e.line("  TDvlSet16 = set of 0..16;")
    e.line("  TDvlSet24 = set of 0..24;")
    e.line("  TDvlSet32 = set of 0..32;")
    e.line("  TDvlSet33 = set of 0..33;")
    e.line("  TDvlSet64 = set of 0..64;")
    e.line("  TDvlSet1To32 = set of 1..32;")
    e.line("  TDvlSetLayoutRec = record")
    e.line("    Prefix: Byte;")
    e.line("    Value: TDvlSet32;")
    e.line("    Suffix: Byte;")
    e.line("  end;")
    e.line("  TDvlSetLayoutClass = class")
    e.line("  public")
    e.line("    Prefix: Byte;")
    e.line("    Value: TDvlSet64;")
    e.line("    Suffix: Byte;")
    e.line("  end;")
    e.line()
    e.line("procedure DvlAbiDelphiSetLayoutMatrix;")
    e.line("var")
    e.line("  Rec: TDvlSetLayoutRec;")
    e.line("  Obj: TDvlSetLayoutClass;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    for suffix, typename, expected in (
        ("set0", "TDvlSet0", 1), ("set8", "TDvlSet8", 2),
        ("set16", "TDvlSet16", 4), ("set24", "TDvlSet24", 4),
        ("set32", "TDvlSet32", 8), ("set33", "TDvlSet33", 8),
        ("set64", "TDvlSet64", 9), ("set1to32", "TDvlSet1To32", 8),
    ):
        e.line("  DevilCheckU('%s-%s-size', UInt64(SizeOf(%s)), %d);" %
               (name, suffix, typename, expected))
    e.line("  DevilCheckU('%s-record-value-offset'," % name)
    e.line("    UInt64(NativeUInt(@Rec.Value) - NativeUInt(@Rec)), 1);")
    e.line("  DevilCheckU('%s-record-suffix-offset'," % name)
    e.line("    UInt64(NativeUInt(@Rec.Suffix) - NativeUInt(@Rec)), 9);")
    e.line("  DevilCheckU('%s-record-size', UInt64(SizeOf(Rec)), 10);" % name)
    e.line("  Obj := TDvlSetLayoutClass.Create;")
    e.line("  try")
    e.line("    DevilCheckU('%s-class-value-offset'," % name)
    e.line("      UInt64(NativeUInt(@Obj.Value) - NativeUInt(@Obj.Prefix)), 1);")
    e.line("    DevilCheckU('%s-class-suffix-offset'," % name)
    e.line("      UInt64(NativeUInt(@Obj.Suffix) - NativeUInt(@Obj.Value)), 9);")
    e.line("  finally")
    e.line("    Obj.Free;")
    e.line("  end;")
    e.line("end;")
    e.line()
    return CaseRecord(name, "abi", {
        "shape": "delphi-set-storage-and-alignment",
        "buckets": [1, 2, 4, 8, 9],
        "containers": ["record", "class"],
    })


def layer_abi(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """Record layout and calling convention.

    Sizes and field offsets are reported as observations: they are ABI, and the
    contract is that our compiler matches Delphi byte for byte, which the gate
    verifies by comparing builds.  Everything about behaviour - by-value
    isolation, managed fields surviving a copy, a record returned from a
    function - is a hard check against the model."""
    records: list[CaseRecord] = [emit_delphi_set_layout_matrix(e)]
    calls: list[str] = ["DvlAbiDelphiSetLayoutMatrix"]
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


def emit_float_branch_selection_matrix(e: Emitter) -> CaseRecord:
    """Inclusive float selections must preserve the chosen operand's bits."""
    name = "dvl-float-branch-selection-matrix"
    e.line("procedure DvlFloatBranchSelectionMatrix;")
    e.line("var")
    e.line("  PlusZero, MinusZero, NanValue, Chosen: Double;")
    e.line("  Bits: UInt64;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  PlusZero := 0.0;")
    e.line("  Bits := UInt64($8000000000000000);")
    e.line("  Move(Bits, MinusZero, SizeOf(MinusZero));")
    e.line("  Bits := UInt64($7FF8000000000001);")
    e.line("  Move(Bits, NanValue, SizeOf(NanValue));")
    e.line("  If MinusZero <= PlusZero then Chosen := MinusZero")
    e.line("  else Chosen := PlusZero;")
    e.line("  DevilCheckU('%s-le-zero', DoubleBits(Chosen),"
           " UInt64($8000000000000000));" % name)
    e.line("  If MinusZero < PlusZero then Chosen := MinusZero")
    e.line("  else Chosen := PlusZero;")
    e.line("  DevilCheckU('%s-lt-zero', DoubleBits(Chosen), 0);" % name)
    e.line("  If PlusZero >= MinusZero then Chosen := PlusZero")
    e.line("  else Chosen := MinusZero;")
    e.line("  DevilCheckU('%s-ge-zero', DoubleBits(Chosen), 0);" % name)
    e.line("  If PlusZero > MinusZero then Chosen := PlusZero")
    e.line("  else Chosen := MinusZero;")
    e.line("  DevilCheckU('%s-gt-zero', DoubleBits(Chosen),"
           " UInt64($8000000000000000));" % name)
    e.line("  If NanValue <= PlusZero then Chosen := NanValue")
    e.line("  else Chosen := PlusZero;")
    e.line("  DevilCheckU('%s-nan-unordered', DoubleBits(Chosen), 0);" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "float", {
        "shape": "branch-exact-inclusive-selection",
        "relations": ["lt", "le", "gt", "ge"],
        "values": ["positive-zero", "negative-zero", "nan"],
    })


def layer_float(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Floating point and Currency.

    Only exactly representable operands are used, so the expected bit pattern
    is computed by the model with no rounding guesswork.  Single results are
    additionally rounded through the 32-bit format by the model, which is where
    an unwanted wider intermediate shows up."""
    records: list[CaseRecord] = [emit_float_branch_selection_matrix(e)]
    calls: list[str] = ["DvlFloatBranchSelectionMatrix"]
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
                   "abstract-override", "procvar-swap", "anon-invoke",
                   "class-is-as")


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

        elif shape == "class-is-as":
            body += ["  %s := %sLeaf.Create;" % (obj, cls)]
            # is answers about the whole ancestry; as narrows the static type
            # without touching the instance behind it
            checks += [
                "  DevilCheckU('%s-is-leaf', UInt64(Ord(%s is %sLeaf)), 1);"
                % (name, obj, cls),
                "  DevilCheckU('%s-is-base', UInt64(Ord(%s is %sBase)), 1);"
                % (name, obj, cls),
                "  DevilCheckU('%s-inherits', "
                "UInt64(Ord(%sLeaf.InheritsFrom(%sBase))), 1);" % (name, cls, cls),
                "  DevilCheckU('%s-not-inherits', "
                "UInt64(Ord(%sBase.InheritsFrom(%sLeaf))), 0);" % (name, cls, cls),
                "  DevilCheckU('%s-classparent', "
                "UInt64(Ord(%sLeaf.ClassParent = %sMid)), 1);" % (name, cls, cls)]
            body += ["  DevilCheckU('%s-as-same-instance', "
                     "UInt64(Ord(Pointer(%s as %sBase) = Pointer(%s))), 1);"
                     % (name, obj, cls, obj),
                     "  %s.Free;" % obj]

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
                arr = fb.var("Arr", "System.TArray<%s>" % t.pascal)
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
            arr = fb.var("Arr", "System.TArray<Integer>")
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
            a = fb.var("A", "System.TArray<Integer>")
            b = fb.var("B", "System.TArray<Integer>")
            body = ["  SetLength(%s, %d);" % (a, n),
                    "  %s[0] := 11;" % a,
                    "  %s := %s;" % (b, a),
                    "  %s[0] := 22;" % b]
            checks = ["  DevilCheckU('%s-shared', UInt64(Cardinal(%s[0])), 22);"
                      % (name, a)]

        elif shape == "copy-detach":
            a = fb.var("A", "System.TArray<Integer>")
            b = fb.var("B", "System.TArray<Integer>")
            body = ["  SetLength(%s, %d);" % (a, n),
                    "  %s[0] := 11;" % a,
                    "  %s := Copy(%s);" % (b, a),
                    "  %s[0] := 22;" % b]
            checks = ["  DevilCheckU('%s-source', UInt64(Cardinal(%s[0])), 11);"
                      % (name, a),
                      "  DevilCheckU('%s-copy', UInt64(Cardinal(%s[0])), 22);"
                      % (name, b)]

        elif shape == "insert-delete":
            a = fb.var("A", "System.TArray<Integer>")
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
            a = fb.var("A", "System.TArray<Integer>")
            b = fb.var("B", "System.TArray<Integer>")
            c = fb.var("C", "System.TArray<Integer>")
            body = ["  SetLength(%s, 2);" % a, "  %s[0] := 1;" % a,
                    "  %s[1] := 2;" % a,
                    "  SetLength(%s, 2);" % b, "  %s[0] := 3;" % b,
                    "  %s[1] := 4;" % b,
                    "  %s := Concat(%s, %s);" % (c, a, b)]
            checks = ["  DevilCheckU('%s-len', UInt64(Length(%s)), 4);" % (name, c),
                      "  DevilCheckU('%s-tail', UInt64(Cardinal(%s[3])), 4);"
                      % (name, c)]

        else:   # ragged
            a = fb.var("A", "System.TArray<System.TArray<Integer>>")
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
        "  SysUtils, System.Generics.Collections, devil_runtime, devil_gen_second;",
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
        "  TDvlAliasEnumerable<T> = class(TEnumerable<T>)",
        "  public type",
        "    TEnumerator = class(TEnumerator<T>);",
        "  protected",
        "    function DoGetEnumerator: "
        "System.Generics.Collections.TEnumerator<T>; override;",
        "  end;",
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
        "function TDvlAliasEnumerable<T>.DoGetEnumerator: "
        "System.Generics.Collections.TEnumerator<T>;",
        "begin",
        "  Result := nil;",
        "end;",
        "",
    ]

    # This must be deterministic and must be built by --separate-units or
    # --ppu-reuse.  The producer spells the namespace-qualified unit while the
    # consumer sees the same unit through the compiler's Delphi alias; generic
    # token replay has to preserve both that identity and the outer token/file
    # position after the specialization ends.
    e.line("type")
    e.line("  TDvlAliasReplayInt = TDvlAliasEnumerable<Integer>;")
    e.line()
    e.line("procedure DvlUnitAliasReplay;")
    e.line("begin")
    e.line("  DevilStep('dvl-unit-generic-alias-replay');")
    e.line("  DevilCheckBool('dvl-unit-generic-alias-replay-inherits',")
    e.line("    TDvlAliasReplayInt.InheritsFrom(TObject));")
    e.line("end;")
    e.line()
    calls.append("DvlUnitAliasReplay")
    records.append(CaseRecord("dvl-unit-generic-alias-replay", "unit", {
        "shape": "generic-alias-replay",
        "requires": ["separate-units", "ppu-reuse"],
    }))

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
    (OUTPUT_DIR / "devil_gen_second.pas").write_text(
        chr(10).join(second) + chr(10), encoding="utf-8")
    (OUTPUT_DIR / "devil_gen_unit.pas").write_text(
        "\n".join(unit_lines) + "\n", encoding="utf-8")
    emit_runner(e, "Unit", calls)
    return records


def emit_checked_incdec_matrix(e: Emitter) -> CaseRecord:
    """Inc/Dec must retain Q/R checks through their inline lowering."""
    name = "dvl-chk-incdec-boundary-matrix"
    e.line("{$ifdef FPC}")
    e.line("{$Q+}{$R+}")
    e.line("procedure DvlChkIncDecBoundaryMatrix;")
    e.line("var")
    e.line("  B: Byte;")
    e.line("  S: ShortInt;")
    e.line("  I: Integer;")
    e.line("  Caught: Integer;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  Caught := 0;")
    e.line("  B := Byte(OpaqueU(High(Byte)));")
    e.line("  try")
    e.line("    Inc(B);")
    e.line("  except")
    e.line("    on EIntOverflow do Inc(Caught);")
    e.line("    on ERangeError do Inc(Caught);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-byte-inc-overflow', UInt64(Caught), 1);" % name)
    e.line("  Caught := 0;")
    e.line("  B := Byte(OpaqueU(0));")
    e.line("  try")
    e.line("    Dec(B);")
    e.line("  except")
    e.line("    on EIntOverflow do Inc(Caught);")
    e.line("    on ERangeError do Inc(Caught);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-byte-dec-underflow', UInt64(Caught), 1);" % name)
    e.line("  Caught := 0;")
    e.line("  S := ShortInt(OpaqueI(High(ShortInt) - 1));")
    e.line("  try")
    e.line("    Inc(S, 2);")
    e.line("  except")
    e.line("    on EIntOverflow do Inc(Caught);")
    e.line("    on ERangeError do Inc(Caught);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-shortint-inc-delta', UInt64(Caught), 1);" % name)
    e.line("  Caught := 0;")
    e.line("  I := Integer(OpaqueI(Low(Integer)));")
    e.line("  try")
    e.line("    Dec(I);")
    e.line("  except")
    e.line("    on EIntOverflow do Inc(Caught);")
    e.line("    on ERangeError do Inc(Caught);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-integer-dec-underflow', UInt64(Caught), 1);" % name)
    e.line("  Caught := 0;")
    e.line("  B := Byte(OpaqueU(254));")
    e.line("  try")
    e.line("    Inc(B);")
    e.line("  except")
    e.line("    Inc(Caught);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-safe-no-exception', UInt64(Caught), 0);" % name)
    e.line("  DevilCheckU('%s-safe-value', UInt64(B), 255);" % name)
    e.line("end;")
    e.line("{$Q-}{$R-}")
    e.line("{$else}")
    e.line("procedure DvlChkIncDecBoundaryMatrix;")
    e.line("begin")
    e.line("  { Delphi does not check Inc/Dec here even under Q+/R+; this is")
    e.line("    an FPC checks contract, so keep only the identical digest feed. }")
    e.line("  DevilStep('%s');" % name)
    e.line("  DevilCheckU('%s-byte-inc-overflow', 1, 1);" % name)
    e.line("  DevilCheckU('%s-byte-dec-underflow', 1, 1);" % name)
    e.line("  DevilCheckU('%s-shortint-inc-delta', 1, 1);" % name)
    e.line("  DevilCheckU('%s-integer-dec-underflow', 1, 1);" % name)
    e.line("  DevilCheckU('%s-safe-no-exception', 0, 0);" % name)
    e.line("  DevilCheckU('%s-safe-value', 255, 255);" % name)
    e.line("end;")
    e.line("{$endif}")
    e.line()
    return CaseRecord(name, "chk", {
        "mode": "incdec-boundary-matrix",
        "types": ["byte", "shortint", "integer"],
        "directions": ["inc", "dec"],
        "outcomes": ["overflow", "underflow", "safe"],
    })


def layer_checked(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Checked arithmetic and range checking are behaviour, not decoration.

    Every case knows from the model whether the operation leaves the type, so
    the expectation "raises" or "does not raise" is derived, and both directions
    are checked: a missing exception and a spurious one are equally defects."""
    records: list[CaseRecord] = [emit_checked_incdec_matrix(e)]
    calls: list[str] = ["DvlChkIncDecBoundaryMatrix"]
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
                e.line("  A: System.TArray<Integer>;")
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
            # nil keeps the anonymous-procedure overload portable: Delphi
            # rejects Self here while the generated callback needs no worker
            # lifetime association.
            e.line("  TThread.Queue(nil,")
            e.line("    procedure")
            e.line("    begin")
            e.line("      AtomicIncrement(DvlThreadCounter);")
            e.line("    end);")
        if shape == "atomic-counter":
            e.line("  for K := 1 to %d do" % rounds)
            e.line("    AtomicIncrement(DvlThreadCounter);")
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
            e.line("      AtomicIncrement(DvlThreadFailures);")
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
               "rtti-instance-type", "published-method",
               "method-name-roundtrip")


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
        e.line("  published")
        e.line("    procedure Mark;")
        e.line("  end;")
        e.line("{$M-}")
        e.line()
        e.line("procedure %s.Mark;" % cls)
        e.line("begin")
        e.line("  DevilTrailAdd('m');")
        e.line("end;")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Obj: %s;" % cls)
        e.line("  PI: PPropInfo;")
        e.line("  Method: TMethod;")
        e.line("  Call: procedure of object;")
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

        elif shape == "published-method":
            e.line("    { a published method is reachable by name, and the "
                   "address the class hands back really calls it }")
            e.line("    DevilCheckU('%s-found', "
                   "UInt64(Ord(Obj.MethodAddress('Mark') <> nil)), 1);" % name)
            e.line("    DevilCheckU('%s-missing', "
                   "UInt64(Ord(Obj.MethodAddress('Absent') = nil)), 1);" % name)
            e.line("    DevilTrailReset;")
            e.line("    Method.Code := Obj.MethodAddress('Mark');")
            e.line("    Method.Data := Obj;")
            e.line("    { a method pointer is exactly a code/data pair; calling "
                   "through a nil half is a crash, not a test }")
            e.line("    If Method.Code <> nil then")
            e.line("    begin")
            e.line("      TMethod(Call) := Method;")
            e.line("      Call();")
            e.line("    end;")
            e.line("    DevilCheckTrail('%s-called', DevilTrail, 'm');" % name)

        elif shape == "method-name-roundtrip":
            e.line("    { name to address and back to name closes the circle }")
            e.line("    DevilCheckU('%s-roundtrip', "
                   "UInt64(Length(Obj.MethodName(Obj.MethodAddress('Mark')))), 4);"
                   % name)
            e.line("    DevilCheckU('%s-unknown-address', "
                   "UInt64(Length(Obj.MethodName(nil))), 0);" % name)

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


def emit_runtime_loop_bound_matrix(e: Emitter) -> CaseRecord:
    """Runtime lower/upper bounds, including equal-register peephole shapes."""
    name = "dvl-flow-runtime-bound-matrix"
    e.line("procedure DvlFlowRuntimeBoundMatrix;")
    e.line("var")
    e.line("  S, SLo, SHi: ShortInt;")
    e.line("  B, BLo, BHi: Byte;")
    e.line("  I, ILo, IHi: Integer;")
    e.line("  Count, Sum: Integer;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  SLo := ShortInt(OpaqueI(0));")
    e.line("  SHi := ShortInt(OpaqueI(0));")
    e.line("  Count := 0;")
    e.line("  for S := SLo to SHi do")
    e.line("    Inc(Count);")
    e.line("  DevilCheckU('%s-shortint-equal-up', UInt64(Count), 1);" % name)
    e.line("  Count := 0;")
    e.line("  for S := SHi downto SLo do")
    e.line("    Inc(Count);")
    e.line("  DevilCheckU('%s-shortint-equal-down', UInt64(Count), 1);" % name)
    e.line("  Count := 0;")
    e.line("  Sum := 0;")
    e.line("  for S := ShortInt(OpaqueI(0)) to ShortInt(OpaqueI(0)) do")
    e.line("  begin")
    e.line("    Inc(Count);")
    e.line("    Inc(Sum, S);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-shortint-direct-equal-up-count', "
           "UInt64(Count), 1);" % name)
    e.line("  DevilCheckU('%s-shortint-direct-equal-up-sum', "
           "UInt64(Cardinal(Sum)), 0);" % name)
    e.line("  Count := 0;")
    e.line("  for S := ShortInt(OpaqueI(4)) downto ShortInt(OpaqueI(-1)) do")
    e.line("    Inc(Count);")
    e.line("  DevilCheckU('%s-shortint-direct-down', UInt64(Count), 6);" % name)
    e.line("  BLo := Byte(OpaqueI(0));")
    e.line("  BHi := Byte(OpaqueI(255));")
    e.line("  Count := 0;")
    e.line("  Sum := 0;")
    e.line("  for B := BLo to BHi do")
    e.line("  begin")
    e.line("    Inc(Count);")
    e.line("    Inc(Sum, B);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-byte-full-count', UInt64(Count), 256);" % name)
    e.line("  DevilCheckU('%s-byte-full-sum', UInt64(Sum), 32640);" % name)
    e.line("  Count := 0;")
    e.line("  for B := Byte(OpaqueI(0)) to Byte(OpaqueI(0)) do")
    e.line("    Inc(Count);")
    e.line("  DevilCheckU('%s-byte-direct-equal', UInt64(Count), 1);" % name)
    e.line("  ILo := Integer(OpaqueI(-3));")
    e.line("  IHi := Integer(OpaqueI(2));")
    e.line("  Count := 0;")
    e.line("  Sum := 0;")
    e.line("  for I := ILo to IHi do")
    e.line("  begin")
    e.line("    Inc(Count);")
    e.line("    Inc(Sum, I);")
    e.line("  end;")
    e.line("  DevilCheckU('%s-integer-range-count', UInt64(Count), 6);" % name)
    e.line("  DevilCheckU('%s-integer-range-sum', "
           "UInt64(Cardinal(Sum)), UInt64(Cardinal(-3)));" % name)
    e.line("  ILo := Integer(OpaqueI(2));")
    e.line("  IHi := Integer(OpaqueI(-3));")
    e.line("  Count := 0;")
    e.line("  for I := ILo to IHi do")
    e.line("    Inc(Count);")
    e.line("  DevilCheckU('%s-runtime-empty', UInt64(Count), 0);" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "flow", {
        "shape": "runtime-bound-matrix",
        "types": ["shortint", "byte", "integer"],
        "relations": ["equal-variable", "equal-direct", "full-domain",
                      "nonzero", "empty"],
        "directions": ["to", "downto"],
    })


def emit_seh_loop_matrix(e: Emitter) -> CaseRecord:
    """Loops whose unroll prepass crosses Win64 exception-frame lowering."""
    name = "dvl-flow-seh-loop-matrix"
    e.line("function DvlFlowSehLoop(Seed: Integer; "
           "var Trail: UnicodeString): Integer;")
    e.line("begin")
    e.line("  Result := Seed;")
    e.line("  for var K := 0 to 9 do")
    e.line("    try")
    e.line("      var Text := UnicodeString(IntToStr(K));")
    e.line("      If (K + Seed) mod 4 = 0 then")
    e.line("        Continue;")
    e.line("      If K = 8 then")
    e.line("        Break;")
    e.line("      Inc(Result, K * 3 + Length(Text) - 1);")
    e.line("    finally")
    e.line("      Trail := Trail + UnicodeString(Char(65 + K));")
    e.line("    end;")
    e.line("end;")
    e.line()
    e.line("procedure DvlFlowSehLoopMatrix;")
    e.line("var")
    e.line("  Trail: UnicodeString;")
    e.line("  Got: Integer;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  Trail := '';")
    e.line("  Got := DvlFlowSehLoop(107, Trail);")
    e.line("  DevilCheckU('%s-result', UInt64(Cardinal(Got)), 173);" % name)
    e.line("  DevilCheckU('%s-finally-count', UInt64(Length(Trail)), 9);" % name)
    e.line("  DevilCheckBool('%s-finally-order', Trail = 'ABCDEFGHI');" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "flow", {
        "shape": "seh-unroll-managed-loop",
        "transfers": ["continue", "break"],
        "managed": ["try-local", "finally-expression"],
    })


def emit_cbool_operator_matrix(e: Emitter) -> CaseRecord:
    """Delphi logical operators normalize noncanonical C-style booleans."""
    name = "dvl-flow-cbool-operator-matrix"
    e.line("procedure DvlFlowCBoolOperatorMatrix;")
    e.line("var")
    e.line("  BL, BR: ByteBool;")
    e.line("  WL, WR: WordBool;")
    e.line("  LL, LR: LongBool;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  Byte(BL) := Byte(OpaqueU($C8));")
    e.line("  Byte(BR) := Byte(OpaqueU($37));")
    e.line("  DevilCheckU('%s-byte-or', UInt64(Byte(BL or BR)), 1);" % name)
    e.line("  DevilCheckU('%s-byte-and', UInt64(Byte(BL and BR)), 1);" % name)
    e.line("  DevilCheckU('%s-byte-xor', UInt64(Byte(BL xor BR)), 0);" % name)
    e.line("  Byte(BR) := Byte(OpaqueU(0));")
    e.line("  DevilCheckU('%s-byte-or-false', UInt64(Byte(BR or BL)), 1);" % name)
    e.line("  DevilCheckU('%s-byte-and-false', UInt64(Byte(BL and BR)), 0);" % name)
    e.line("  DevilCheckU('%s-byte-xor-false', UInt64(Byte(BR xor BL)), 1);" % name)
    e.line("  Word(WL) := Word(OpaqueU($C800));")
    e.line("  Word(WR) := Word(OpaqueU($3700));")
    e.line("  DevilCheckU('%s-word-or', UInt64(Word(WL or WR)), 1);" % name)
    e.line("  DevilCheckU('%s-word-and', UInt64(Word(WL and WR)), 1);" % name)
    e.line("  DevilCheckU('%s-word-xor', UInt64(Word(WL xor WR)), 0);" % name)
    e.line("  LongInt(LL) := LongInt(OpaqueI($12340000));")
    e.line("  LongInt(LR) := LongInt(OpaqueI($00005678));")
    e.line("  DevilCheckU('%s-long-or', UInt64(Cardinal(LL or LR)), 1);" % name)
    e.line("  DevilCheckU('%s-long-and', UInt64(Cardinal(LL and LR)), 1);" % name)
    e.line("  BL := BL or BR;")
    e.line("  WL := WL or WR;")
    e.line("  LL := LL or LR;")
    e.line("  DevilCheckU('%s-byte-assigned', UInt64(Byte(BL)), $FF);" % name)
    e.line("  DevilCheckU('%s-word-assigned', UInt64(Word(WL)), $FFFF);" % name)
    e.line("  DevilCheckU('%s-long-assigned', "
           "UInt64(Cardinal(LL)), UInt64(Cardinal(-1)));" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "flow", {
        "shape": "cbool-operator-matrix",
        "types": ["bytebool", "wordbool", "longbool"],
        "operators": ["and", "or", "xor"],
        "representations": ["noncanonical-true", "false"],
    })


def layer_flow(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Control flow: every branch, jump and early exit has a counted trail, so
    the model knows exactly how many times each point was reached."""
    records: list[CaseRecord] = [
        emit_runtime_loop_bound_matrix(e),
        emit_seh_loop_matrix(e),
        emit_cbool_operator_matrix(e),
    ]
    calls: list[str] = ["DvlFlowRuntimeBoundMatrix", "DvlFlowSehLoopMatrix",
                        "DvlFlowCBoolOperatorMatrix"]
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
               "caret-literal", "olevariant", "variant-compare",
               "variant-custom-type")


def variant_literal_tag(value: int) -> int:
    """The Variant tag Delphi gives an integer literal: narrowest unsigned."""
    if 0 <= value <= 0xFF:
        return 17                       # varByte
    if 0 <= value <= 0xFFFF:
        return 18                       # varWord
    if 0 <= value <= 0xFFFFFFFF:
        return 19                       # varLongWord
    if -0x80 <= value <= 0x7F:
        return 16                       # varShortInt
    if -0x8000 <= value <= 0x7FFF:
        return 2                        # varSmallint
    if -0x80000000 <= value <= 0x7FFFFFFF:
        return 3                        # varInteger
    return 20                           # varInt64


def emit_custom_variant_carrier_matrix(e: Emitter) -> CaseRecord:
    """Exercise custom Variants after two nested varVariant/by-ref carriers."""
    name = "dvl-lang-custom-variant-carrier-matrix"
    e.line("type")
    e.line("  TDvlCarrierVariantType = class(TCustomVariantType)")
    e.line("  public")
    e.line("    procedure Clear(var V: TVarData); override;")
    e.line("    procedure Copy(var Dest: TVarData; const Source: TVarData;")
    e.line("      const Indirect: Boolean); override;")
    e.line("    procedure CastTo(var Dest: TVarData; const Source: TVarData;")
    e.line("      const AVarType: TVarType); override;")
    e.line("    procedure BinaryOp(var Left: TVarData; const Right: TVarData;")
    e.line("      const Operation: TVarOp); override;")
    e.line("    function RightPromotion(const V: TVarData;")
    e.line("      const Operation: TVarOp; out RequiredVarType: TVarType): Boolean; override;")
    e.line("    function CompareOp(const Left, Right: TVarData;")
    e.line("      const Operation: TVarOp): Boolean; override;")
    e.line("    procedure Compare(const Left, Right: TVarData;")
    e.line("      var Relationship: TVarCompareResult); override;")
    e.line("  end;")
    e.line()
    e.line("procedure TDvlCarrierVariantType.Clear(var V: TVarData);")
    e.line("begin")
    e.line("  V.VType := varEmpty;")
    e.line("end;")
    e.line()
    e.line("procedure TDvlCarrierVariantType.Copy(var Dest: TVarData;")
    e.line("  const Source: TVarData; const Indirect: Boolean);")
    e.line("begin")
    e.line("  Dest.VType := Source.VType;")
    e.line("end;")
    e.line()
    e.line("procedure TDvlCarrierVariantType.CastTo(var Dest: TVarData;")
    e.line("  const Source: TVarData; const AVarType: TVarType);")
    e.line("begin")
    e.line("  case AVarType of")
    e.line("    varInteger: Variant(Dest) := Integer(42);")
    e.line("    varBoolean: Variant(Dest) := True;")
    e.line("    varString: Variant(Dest) := AnsiString('carrier-ok');")
    e.line("    varOleStr: Variant(Dest) := WideString('carrier-ok');")
    e.line("    varUString: Variant(Dest) := UnicodeString('carrier-ok');")
    e.line("  else")
    e.line("    inherited CastTo(Dest, Source, AVarType);")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("procedure TDvlCarrierVariantType.BinaryOp(var Left: TVarData;")
    e.line("  const Right: TVarData; const Operation: TVarOp);")
    e.line("begin")
    e.line("  If Operation <> opAdd then")
    e.line("    RaiseInvalidOp;")
    e.line("  Variant(Left) := 42 + Integer(Variant(Right));")
    e.line("end;")
    e.line()
    e.line("function TDvlCarrierVariantType.RightPromotion(const V: TVarData;")
    e.line("  const Operation: TVarOp; out RequiredVarType: TVarType): Boolean;")
    e.line("begin")
    e.line("  RequiredVarType := varInteger;")
    e.line("  Result := Operation in [opAdd, opCompare];")
    e.line("end;")
    e.line()
    e.line("function TDvlCarrierVariantType.CompareOp(const Left, Right: TVarData;")
    e.line("  const Operation: TVarOp): Boolean;")
    e.line("var")
    e.line("  RightValue: Integer;")
    e.line("begin")
    e.line("  RightValue := Integer(Variant(Right));")
    e.line("  case Operation of")
    e.line("    opCmpEq: Result := 42 = RightValue;")
    e.line("    opCmpNe: Result := 42 <> RightValue;")
    e.line("    opCmpLt: Result := 42 < RightValue;")
    e.line("    opCmpLe: Result := 42 <= RightValue;")
    e.line("    opCmpGt: Result := 42 > RightValue;")
    e.line("    opCmpGe: Result := 42 >= RightValue;")
    e.line("  else")
    e.line("    RaiseInvalidOp;")
    e.line("    Result := False;")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("procedure TDvlCarrierVariantType.Compare(const Left, Right: TVarData;")
    e.line("  var Relationship: TVarCompareResult);")
    e.line("var")
    e.line("  RightValue: Integer;")
    e.line("begin")
    e.line("  RightValue := Integer(Variant(Right));")
    e.line("  If 42 < RightValue then")
    e.line("    Relationship := crLessThan")
    e.line("  else If 42 > RightValue then")
    e.line("    Relationship := crGreaterThan")
    e.line("  else")
    e.line("    Relationship := crEqual")
    e.line("end;")
    e.line()
    e.line("procedure DvlSetVariantCarrier(const Source: Variant;")
    e.line("  var Dest: Variant);")
    e.line("begin")
    e.line("  VarClear(Dest);")
    e.line("  TVarData(Dest).VType := varVariant or varByRef;")
    e.line("  TVarData(Dest).VPointer := @TVarData(Source);")
    e.line("end;")
    e.line()
    e.line("function DvlAcceptCarrierText(const Text: UnicodeString): Boolean;")
    e.line("begin")
    e.line("  Result := Text = 'carrier-ok';")
    e.line("end;")
    e.line()
    e.line("procedure DvlCustomVariantCarrierMatrix;")
    e.line("var")
    e.line("  Handler: TDvlCarrierVariantType;")
    e.line("  Value, Reference1, Reference2, CastValue: Variant;")
    e.line("  Text: UnicodeString;")
    e.line("  Number: Integer;")
    e.line("begin")
    e.line("  Handler := TDvlCarrierVariantType.Create;")
    e.line("  try")
    e.line("    TVarData(Value).VType := Handler.VarType;")
    e.line("    DvlSetVariantCarrier(Value, Reference1);")
    e.line("    DvlSetVariantCarrier(Reference1, Reference2);")
    e.line("    try")
    e.line("      Text := Reference2;")
    e.line("      DevilCheckU('%s-text', UInt64(Ord(Text = 'carrier-ok')), 1);"
           % name)
    e.line("      DevilCheckU('%s-argument', "
           "UInt64(Ord(DvlAcceptCarrierText(Reference2))), 1);" % name)
    e.line("      Number := Reference2;")
    e.line("      DevilCheckU('%s-integer', UInt64(Cardinal(Number)), 42);"
           % name)
    e.line("      CastValue := VarAsType(Reference2, varUString);")
    e.line("      DevilCheckU('%s-cast', "
           "UInt64(Ord(UnicodeString(CastValue) = 'carrier-ok')), 1);" % name)
    e.line("      DevilCheckU('%s-compare', UInt64(Ord(Value = 42)), 1);"
           % name)
    e.line("      DevilCheckU('%s-compare-lt', UInt64(Ord(Value < 43)), 1);"
           % name)
    e.line("      DevilCheckU('%s-compare-gt', UInt64(Ord(Value > 41)), 1);"
           % name)
    e.line("      CastValue := Value + 8;")
    e.line("      DevilCheckU('%s-binary', UInt64(Cardinal(Integer(CastValue))), 50);"
           % name)
    e.line("    finally")
    e.line("      VarClear(CastValue);")
    e.line("      VarClear(Reference2);")
    e.line("      VarClear(Reference1);")
    e.line("      VarClear(Value);")
    e.line("    end;")
    e.line("  finally")
    e.line("    Handler.Free;")
    e.line("  end;")
    e.line("end;")
    e.line()
    return CaseRecord(name=name, layer="lang", detail={
        "shape": "nested-custom-variant-carriers-and-direct-operators",
    })


def layer_lang(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Delphi language surface: the constructs application code actually uses.

    Each shape declares its own types with a unique index, so cases never
    collide, and every value is derived from the declaration itself."""
    records: list[CaseRecord] = [emit_custom_variant_carrier_matrix(e)]
    calls: list[str] = ["DvlCustomVariantCarrierMatrix"]
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
                # Delphi narrows an integer literal to the smallest unsigned
                # type it fits, and tags a real literal without an exponent as
                # Currency; both are contract, not incidental
                e.line("  V := %d;" % a)
                e.line("  DevilCheckU('%s-type', UInt64(VarType(V)), %d);"
                       % (name, variant_literal_tag(a)))
                e.line("  V := 1.5;")
                e.line("  DevilCheckU('%s-real-type', UInt64(VarType(V)), 6);"
                       % name)
                e.line("  V := 1.5e0;")
                e.line("  DevilCheckU('%s-exponent-type', UInt64(VarType(V)), 5);"
                       % name)
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

        elif shape == "olevariant":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  O: OleVariant;")
            e.line("  V: Variant;")
            e.line("begin")
            e.line("  O := %d;" % (index % 90 + 5))
            e.line("  V := O;")
            e.line("  { an OleVariant holds the same value and converts back "
                   "without changing it }")
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(Cardinal(Integer(O))), %d);" % (name, index % 90 + 5))
            e.line("  DevilCheckU('%s-roundtrip', "
                   "UInt64(Cardinal(Integer(V))), %d);" % (name, index % 90 + 5))
            e.line("  O := 'text';")
            e.line("  DevilCheckU('%s-string-length', "
                   "UInt64(Length(string(O))), 4);" % name)
            e.line("  DevilNoteLoose('%s-string-type', UInt64(VarType(O)));" % name)
            e.line("end;")

        elif shape == "variant-compare":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: Variant;")
            e.line("begin")
            e.line("  A := %d;" % (index % 50 + 1))
            e.line("  B := %d;" % (index % 50 + 1))
            e.line("  { comparison goes through the variant machinery, not "
                   "through the raw storage }")
            e.line("  DevilCheckU('%s-equal', UInt64(Ord(A = B)), 1);" % name)
            e.line("  B := %d;" % (index % 50 + 2))
            e.line("  DevilCheckU('%s-less', UInt64(Ord(A < B)), 1);" % name)
            e.line("  A := 'abc';")
            e.line("  B := 'abd';")
            e.line("  DevilCheckU('%s-string-less', UInt64(Ord(A < B)), 1);" % name)
            e.line("  A := Null;")
            e.line("  DevilCheckU('%s-null-is-not-equal', "
                   "UInt64(Ord(VarIsNull(A))), 1);" % name)
            e.line("end;")

        elif shape == "variant-custom-type":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  V: Variant;")
            e.line("  A: Variant;")
            e.line("begin")
            e.line("  { a Variant holding an interface keeps it counted, and "
                   "clearing the Variant releases it }")
            e.line("  V := TDvlTagged.Create('v') as IInterface;")
            e.line("  DevilCheckU('%s-interface-type', "
                   "UInt64(Ord(VarType(V) = varUnknown)), 1);" % name)
            e.line("  V := Unassigned;")
            e.line("  DevilCheckU('%s-cleared', UInt64(Ord(VarIsEmpty(V))), 1);"
                   % name)
            e.line("  { an array of Variant is itself a Variant value }")
            e.line("  A := VarArrayOf([1, 'two', 3.5]);")
            e.line("  DevilCheckU('%s-array', UInt64(Ord(VarIsArray(A))), 1);"
                   % name)
            e.line("  DevilCheckU('%s-element', "
                   "UInt64(Cardinal(Integer(A[0]))), 1);" % name)
            e.line("  DevilCheckU('%s-string-element', "
                   "UInt64(Length(string(A[1]))), 3);" % name)
            e.line("  DevilNoteLoose('%s-real-element-type', UInt64(VarType(A[2])));"
                   % name)
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


# The Unicode contract is the newest thing in this compiler: `string` is
# UnicodeString, `Char` is UTF-16, and only AnsiString/RawByteString/UTF8String
# stay byte typed.  Everything here is about what the *compiler* decides -
# which conversion it inserts, which codepage a type carries, which overload it
# picks, how wide an element is - not about what the RTL computes.
#
# Literals are written as explicit code point escapes, so no form depends on
# how the generated file happens to be encoded on disk.
UNI_SHAPES = ("alias-identity", "literal-escape", "surrogate", "convert-utf8",
              "convert-back", "codepage-typed", "rawbytestring",
              "stringcodepage", "pchar-step", "char-domain",
              "overload-pick", "array-of-char", "set-of-ansichar",
              "record-string-layout", "case-of-char", "param-const-string",
              "generic-string", "shortstring-bytes", "widestring",
              "concat-codepage", "result-abi", "const-codepage",
              "for-in-string", "array-of-const", "generic-codepage",
              "setstring-bytes", "inline-string", "interface-string",
              "dynarray-string", "compare-codepage")

# text that survives a round trip through cp1251, so a typed AnsiString has a
# defined byte image
UNI_CP1251_TEXTS = ("\u0416", "\u044f", "\u041f\u0440\u0438\u0432\u0435\u0442",
                    "ab\u0416", "\u0401\u0436\u0438\u043a", "\u043c\u0438\u0440")
# text outside cp1251, used only where the target is UTF-8 or UTF-16
UNI_WIDE_TEXTS = ("\u4e2d", "\u20ac", "caf\u00e9\u4e2d", "\U0001F600")


def escaped_literal(text: str) -> str:
    """A literal built from code points: identical under any file encoding."""
    units = []
    for ch in text:
        code = ord(ch)
        if code > 0xFFFF:
            code -= 0x10000
            units.append(0xD800 + (code >> 10))
            units.append(0xDC00 + (code & 0x3FF))
        else:
            units.append(code)
    return "".join("#$%04X" % unit for unit in units)


def utf16_units(text: str) -> list[int]:
    data = text.encode("utf-16-le")
    return [data[i] | (data[i + 1] << 8) for i in range(0, len(data), 2)]


def layer_unicode(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """String width, codepage and conversion: what the compiler decides."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-uni-%05d" % index
        proc = "DvlUni%05d" % index
        tag = "%05d" % index
        shape = rng.choice(UNI_SHAPES)
        text = rng.choice(UNI_CP1251_TEXTS)
        wide = rng.choice(UNI_WIDE_TEXTS)
        units = utf16_units(text)
        utf8 = text.encode("utf-8")
        cp1251 = text.encode("cp1251")

        if shape == "alias-identity":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  DevilCheckU('%s-char', UInt64(SizeOf(Char)), 2);" % name)
            e.line("  DevilCheckU('%s-ansichar', UInt64(SizeOf(AnsiChar)), 1);"
                   % name)
            e.line("  DevilCheckU('%s-element', UInt64(SizeOf(S[1])), 2);" % name)
            e.line("  DevilCheckU('%s-length', UInt64(Length(S)), %d);"
                   % (name, len(units)))
            e.line("  DevilCheckU('%s-pointer', UInt64(SizeOf(S)), %d);"
                   % (name, 8))
            e.line("  DevilNoteText('%s-typename', "
                   "AnsiString(string(PTypeInfo(TypeInfo(string))^.Name)));" % name)
            e.line("end;")

        elif shape == "literal-escape":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  DevilCheckU('%s-length', UInt64(Length(S)), %d);"
                   % (name, len(units)))
            for position, unit in enumerate(units[:4], start=1):
                e.line("  DevilCheckU('%s-unit%d', UInt64(Ord(S[%d])), %d);"
                       % (name, position, position, unit))
            e.line("end;")

        elif shape == "surrogate":
            pair = "\U0001F600"
            body = text + pair
            body_units = utf16_units(body)
            body_utf8 = body.encode("utf-8")
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  U: UTF8String;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(body))
            e.line("  DevilCheckU('%s-units', UInt64(Length(S)), %d);"
                   % (name, len(body_units)))
            e.line("  DevilCheckU('%s-lead', UInt64(Ord(S[%d])), %d);"
                   % (name, len(body_units) - 1, body_units[-2]))
            e.line("  DevilCheckU('%s-trail', UInt64(Ord(S[%d])), %d);"
                   % (name, len(body_units), body_units[-1]))
            e.line("  U := UTF8String(S);")
            e.line("  DevilCheckU('%s-utf8-bytes', UInt64(Length(U)), %d);"
                   % (name, len(body_utf8)))
            e.line("  DevilCheckU('%s-utf8-tail', UInt64(Ord(U[%d])), %d);"
                   % (name, len(body_utf8), body_utf8[-1]))
            e.line("end;")

        elif shape == "convert-utf8":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  U: UTF8String;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  U := UTF8String(S);")
            e.line("  DevilCheckU('%s-bytes', UInt64(Length(U)), %d);"
                   % (name, len(utf8)))
            for position, byte in enumerate(utf8[:4], start=1):
                e.line("  DevilCheckU('%s-byte%d', UInt64(Ord(U[%d])), %d);"
                       % (name, position, position, byte))
            e.line("  DevilCheckU('%s-codepage', "
                   "UInt64(StringCodePage(U)), 65001);" % name)
            e.line("end;")

        elif shape == "convert-back":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S, B: string;")
            e.line("  U: UTF8String;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(wide))
            e.line("  U := UTF8String(S);")
            e.line("  B := string(U);")
            e.line("  DevilCheckU('%s-roundtrip-length', UInt64(Length(B)), %d);"
                   % (name, len(utf16_units(wide))))
            for position, unit in enumerate(utf16_units(wide)[:3], start=1):
                e.line("  DevilCheckU('%s-roundtrip%d', UInt64(Ord(B[%d])), %d);"
                       % (name, position, position, unit))
            e.line("end;")

        elif shape == "codepage-typed":
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  A: TDvlCp%s;" % tag)
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  A := TDvlCp%s(S);" % tag)
            e.line("  DevilCheckU('%s-bytes', UInt64(Length(A)), %d);"
                   % (name, len(cp1251)))
            for position, byte in enumerate(cp1251[:4], start=1):
                e.line("  DevilCheckU('%s-byte%d', UInt64(Ord(A[%d])), %d);"
                       % (name, position, position, byte))
            e.line("  DevilCheckU('%s-codepage', "
                   "UInt64(StringCodePage(A)), 1251);" % name)
            e.line("end;")

        elif shape == "rawbytestring":
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: TDvlCp%s;" % tag)
            e.line("  R: RawByteString;")
            e.line("begin")
            e.line("  A := TDvlCp%s(string(%s));" % (tag, escaped_literal(text)))
            e.line("  R := A;")
            e.line("  { a raw carrier moves bytes, it does not re-encode them }")
            e.line("  DevilCheckU('%s-length', UInt64(Length(R)), %d);"
                   % (name, len(cp1251)))
            for position, byte in enumerate(cp1251[:3], start=1):
                e.line("  DevilCheckU('%s-byte%d', UInt64(Ord(R[%d])), %d);"
                       % (name, position, position, byte))
            e.line("  DevilCheckU('%s-codepage', "
                   "UInt64(StringCodePage(R)), 1251);" % name)
            e.line("end;")

        elif shape == "stringcodepage":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  U: UTF8String;")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  U := UTF8String(S);")
            e.line("  DevilCheckU('%s-utf8', UInt64(StringCodePage(U)), 65001);"
                   % name)
            e.line("  DevilNote('%s-default', UInt64(DefaultSystemCodePage));"
                   % name)
            e.line("  DevilCheckU('%s-elementsize', "
                   "UInt64(StringElementSize(U)), 1);" % name)
            e.line("  DevilCheckU('%s-wide-elementsize', "
                   "UInt64(StringElementSize(S)), 2);" % name)
            e.line("end;")

        elif shape == "pchar-step":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  A: AnsiString;")
            e.line("  P: PChar;")
            e.line("  Q: PAnsiChar;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  A := AnsiString('abcdef');")
            e.line("  P := PChar(S);")
            e.line("  Q := PAnsiChar(A);")
            e.line("  { pointer arithmetic counts elements, and an element is "
                   "as wide as its character type }")
            e.line("  DevilCheckU('%s-wide-step', "
                   "UInt64(NativeUInt(P + 1) - NativeUInt(P)), 2);" % name)
            e.line("  DevilCheckU('%s-byte-step', "
                   "UInt64(NativeUInt(Q + 1) - NativeUInt(Q)), 1);" % name)
            e.line("  DevilCheckU('%s-head', UInt64(Ord(P[0])), %d);"
                   % (name, units[0]))
            e.line("  DevilCheckU('%s-terminator', UInt64(Ord(P[%d])), 0);"
                   % (name, len(units)))
            e.line("end;")

        elif shape == "char-domain":
            code = units[0]
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  C: Char;")
            e.line("  W: WideChar;")
            e.line("  B: AnsiChar;")
            e.line("begin")
            e.line("  C := %s;" % ("#$%04X" % code))
            e.line("  W := C;")
            e.line("  B := AnsiChar($%02X);" % (code & 0xFF))
            e.line("  DevilCheckU('%s-ord', UInt64(Ord(C)), %d);" % (name, code))
            e.line("  DevilCheckU('%s-widened', UInt64(Ord(W)), %d);"
                   % (name, code))
            e.line("  DevilCheckU('%s-byte', UInt64(Ord(B)), %d);"
                   % (name, code & 0xFF))
            e.line("  DevilCheckU('%s-high', UInt64(Ord(High(Char))), 65535);"
                   % name)
            e.line("  DevilCheckU('%s-high-ansi', UInt64(Ord(High(AnsiChar))), 255);"
                   % name)
            e.line("end;")

        elif shape == "overload-pick":
            e.line("function DvlUniPick%s(const S: UnicodeString): Integer; overload;"
                   % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("end;")
            e.line()
            e.line("function DvlUniPick%s(const S: AnsiString): Integer; overload;"
                   % tag)
            e.line("begin")
            e.line("  Result := 2;")
            e.line("end;")
            e.line()
            e.line("function DvlUniPick%s(const S: ShortString): Integer; overload;"
                   % tag)
            e.line("begin")
            e.line("  Result := 3;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  U: UnicodeString;")
            e.line("  A: AnsiString;")
            e.line("  H: ShortString;")
            e.line("begin")
            e.line("  U := %s;" % escaped_literal(text))
            e.line("  A := AnsiString('abc');")
            e.line("  H := 'abc';")
            e.line("  DevilCheckU('%s-unicode', UInt64(DvlUniPick%s(U)), 1);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-ansi', UInt64(DvlUniPick%s(A)), 2);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-short', UInt64(DvlUniPick%s(H)), 3);"
                   % (name, tag))
            e.line("  { which one a bare literal binds to is a language choice, "
                   "not a value: recorded, not asserted }")
            e.line("  DevilNoteLoose('%s-literal', UInt64(DvlUniPick%s('abc')));"
                   % (name, tag))
            e.line("end;")

        elif shape == "array-of-char":
            width = rng.randrange(2, 9)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: array[1..%d] of Char;" % width)
            e.line("  B: array[1..%d] of AnsiChar;" % width)
            e.line("begin")
            e.line("  A[1] := %s;" % ("#$%04X" % units[0]))
            e.line("  B[1] := AnsiChar($%02X);" % (utf8[0]))
            e.line("  DevilCheckU('%s-wide-size', UInt64(SizeOf(A)), %d);"
                   % (name, width * 2))
            e.line("  DevilCheckU('%s-byte-size', UInt64(SizeOf(B)), %d);"
                   % (name, width))
            e.line("  DevilCheckU('%s-stride', "
                   "UInt64(NativeUInt(@A[2]) - NativeUInt(@A[1])), 2);" % name)
            e.line("  DevilCheckU('%s-value', UInt64(Ord(A[1])), %d);"
                   % (name, units[0]))
            e.line("end;")

        elif shape == "set-of-ansichar":
            member = chr(rng.randrange(ord("a"), ord("z") + 1))
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: set of AnsiChar;")
            e.line("begin")
            e.line("  S := ['a'..'z'];")
            e.line("  DevilCheckU('%s-size', UInt64(SizeOf(S)), 32);" % name)
            e.line("  DevilCheckU('%s-member', UInt64(Ord('%s' in S)), 1);"
                   % (name, member))
            e.line("  DevilCheckU('%s-outside', "
                   "UInt64(Ord(AnsiChar($%02X) in S)), 0);" % (name, 0xC6))
            e.line("end;")

        elif shape == "record-string-layout":
            e.line("type")
            e.line("  TDvlSRec%s = record" % tag)
            e.line("    W: string;")
            e.line("    A: AnsiString;")
            e.line("    N: Integer;")
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlSRec%s;" % tag)
            e.line("begin")
            e.line("  R.W := %s;" % escaped_literal(text))
            e.line("  R.A := AnsiString('ab');")
            e.line("  R.N := 7;")
            e.line("  { both string fields are one pointer wide regardless of "
                   "their element width }")
            e.line("  DevilCheckU('%s-size', UInt64(SizeOf(TDvlSRec%s)), 24);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-offset-a', "
                   "UInt64(NativeUInt(@R.A) - NativeUInt(@R)), 8);" % name)
            e.line("  DevilCheckU('%s-offset-n', "
                   "UInt64(NativeUInt(@R.N) - NativeUInt(@R)), 16);" % name)
            e.line("end;")

        elif shape == "case-of-char":
            # the second label must not fall inside the 'a'..'z' arm
            code = next((unit for unit in units if unit > 0x7F), 0x0416)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  C: Char;")
            e.line("  R: Integer;")
            e.line("begin")
            e.line("  C := %s;" % ("#$%04X" % code))
            e.line("  case C of")
            e.line("    'a'..'z': R := 1;")
            e.line("    %s: R := 2;" % ("#$%04X" % code))
            e.line("  else")
            e.line("    R := 3;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-branch', UInt64(Cardinal(R)), 2);" % name)
            e.line("  C := 'm';")
            e.line("  case C of")
            e.line("    'a'..'z': R := 1;")
            e.line("    %s: R := 2;" % ("#$%04X" % code))
            e.line("  else")
            e.line("    R := 3;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-ascii-branch', UInt64(Cardinal(R)), 1);"
                   % name)
            e.line("end;")

        elif shape == "param-const-string":
            e.line("function DvlUniWide%s(const S: string): Integer;" % tag)
            e.line("begin")
            e.line("  Result := Length(S);")
            e.line("end;")
            e.line()
            e.line("function DvlUniUtf8%s(const S: UTF8String): Integer;" % tag)
            e.line("begin")
            e.line("  Result := Length(S);")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  { the conversion happens at the call site, so the callee "
                   "counts bytes while the caller counts units }")
            e.line("  DevilCheckU('%s-units', UInt64(DvlUniWide%s(S)), %d);"
                   % (name, tag, len(units)))
            e.line("  DevilCheckU('%s-bytes', UInt64(DvlUniUtf8%s(S)), %d);"
                   % (name, tag, len(utf8)))
            e.line("end;")

        elif shape == "generic-string":
            e.line("type")
            e.line("  TDvlHold%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("    function Width: Integer;")
            e.line("  end;")
            e.line()
            e.line("function TDvlHold%s<T>.Width: Integer;" % tag)
            e.line("begin")
            e.line("  Result := SizeOf(T);")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  W: TDvlHold%s<string>;" % tag)
            e.line("  A: TDvlHold%s<AnsiString>;" % tag)
            e.line("  C: TDvlHold%s<Char>;" % tag)
            e.line("begin")
            e.line("  W.Value := %s;" % escaped_literal(text))
            e.line("  A.Value := AnsiString('ab');")
            e.line("  C.Value := 'x';")
            e.line("  DevilCheckU('%s-wide-width', UInt64(W.Width), 8);" % name)
            e.line("  DevilCheckU('%s-ansi-width', UInt64(A.Width), 8);" % name)
            e.line("  DevilCheckU('%s-char-width', UInt64(C.Width), 2);" % name)
            e.line("  DevilCheckU('%s-length', UInt64(Length(W.Value)), %d);"
                   % (name, len(units)))
            e.line("end;")

        elif shape == "shortstring-bytes":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: ShortString;")
            e.line("  T: string[%d];" % max(8, len(cp1251) + 2))
            e.line("begin")
            e.line("  SetLength(S, %d);" % len(cp1251))
            for position, byte in enumerate(cp1251, start=1):
                e.line("  S[%d] := AnsiChar($%02X);" % (position, byte))
            e.line("  T := 'abc';")
            e.line("  { a short string is a byte buffer with a length prefix: "
                   "no codepage, no element widening }")
            e.line("  DevilCheckU('%s-length', UInt64(Length(S)), %d);"
                   % (name, len(cp1251)))
            e.line("  DevilCheckU('%s-byte', UInt64(Ord(S[1])), %d);"
                   % (name, cp1251[0]))
            e.line("  DevilCheckU('%s-size', UInt64(SizeOf(S)), 256);" % name)
            e.line("  DevilCheckU('%s-fixed-size', UInt64(SizeOf(T)), %d);"
                   % (name, max(8, len(cp1251) + 2) + 1))
            e.line("end;")

        elif shape == "widestring":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  W: WideString;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  W := S;")
            e.line("  DevilCheckU('%s-length', UInt64(Length(W)), %d);"
                   % (name, len(units)))
            e.line("  DevilCheckU('%s-unit', UInt64(Ord(W[1])), %d);"
                   % (name, units[0]))
            e.line("  DevilCheckU('%s-pointer', UInt64(SizeOf(W)), 8);" % name)
            e.line("  DevilCheckU('%s-back', UInt64(Length(string(W))), %d);"
                   % (name, len(units)))
            e.line("end;")

        elif shape == "result-abi":
            e.line("function DvlUniMakeWide%s(N: Integer): string;" % tag)
            e.line("begin")
            e.line("  Result := %s;" % escaped_literal(text))
            e.line("  If N > 0 then")
            e.line("    Result := Result + Result;")
            e.line("end;")
            e.line()
            e.line("function DvlUniMakeUtf8%s(N: Integer): UTF8String;" % tag)
            e.line("begin")
            e.line("  Result := UTF8String(DvlUniMakeWide%s(0));" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  U: UTF8String;")
            e.line("begin")
            e.line("  { a managed result travels as a hidden parameter, and the "
                   "caller owns the slot before the callee ever writes it }")
            e.line("  S := DvlUniMakeWide%s(1);" % tag)
            e.line("  U := DvlUniMakeUtf8%s(0);" % tag)
            e.line("  DevilCheckU('%s-doubled', UInt64(Length(S)), %d);"
                   % (name, len(units) * 2))
            e.line("  DevilCheckU('%s-utf8', UInt64(Length(U)), %d);"
                   % (name, len(utf8)))
            e.line("  DevilCheckU('%s-nested', "
                   "UInt64(Length(DvlUniMakeWide%s(0) + DvlUniMakeWide%s(0))), %d);"
                   % (name, tag, tag, len(units) * 2))
            e.line("end;")

        elif shape == "const-codepage":
            e.line("const")
            e.line("  DvlWideConst%s: string = %s;" % (tag, escaped_literal(text)))
            e.line("  DvlUtf8Const%s: UTF8String = %s;" % (tag, escaped_literal(text)))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a typed constant carries the codepage of its type, and "
                   "the compiler encodes its bytes at compile time }")
            e.line("  DevilCheckU('%s-wide', UInt64(Length(DvlWideConst%s)), %d);"
                   % (name, tag, len(units)))
            e.line("  DevilCheckU('%s-utf8', UInt64(Length(DvlUtf8Const%s)), %d);"
                   % (name, tag, len(utf8)))
            e.line("  DevilCheckU('%s-utf8-byte', "
                   "UInt64(Ord(DvlUtf8Const%s[1])), %d);" % (name, tag, utf8[0]))
            e.line("  DevilCheckU('%s-utf8-codepage', "
                   "UInt64(StringCodePage(DvlUtf8Const%s)), 65001);" % (name, tag))
            e.line("end;")

        elif shape == "for-in-string":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  A: AnsiString;")
            e.line("  Sum, Count: Integer;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  A := AnsiString('abc');")
            e.line("  Sum := 0;")
            e.line("  Count := 0;")
            e.line("  for var C in S do")
            e.line("  begin")
            e.line("    Sum := Sum + Ord(C);")
            e.line("    Inc(Count);")
            e.line("  end;")
            e.line("  { iterating a string yields elements, not bytes }")
            e.line("  DevilCheckU('%s-count', UInt64(Cardinal(Count)), %d);"
                   % (name, len(units)))
            e.line("  DevilCheckU('%s-sum', UInt64(Cardinal(Sum)), %d);"
                   % (name, sum(units)))
            e.line("  Count := 0;")
            e.line("  for var B in A do")
            e.line("    Inc(Count);")
            e.line("  DevilCheckU('%s-ansi-count', UInt64(Cardinal(Count)), 3);"
                   % name)
            e.line("end;")

        elif shape == "array-of-const":
            e.line("function DvlUniKinds%s(const A: array of const): Integer;" % tag)
            e.line("var")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  Total := 0;")
            e.line("  for var I := Low(A) to High(A) do")
            e.line("    Total := Total * 10 + A[I].VType;")
            e.line("  Result := Total;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("  A: AnsiString;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  A := AnsiString('ab');")
            e.line("  { how a string reaches a variant argument is a wire "
                   "decision of the compiler, recorded rather than assumed }")
            e.line("  DevilNote('%s-wide-kind', UInt64(Cardinal(DvlUniKinds%s([S]))));"
                   % (name, tag))
            e.line("  DevilNote('%s-ansi-kind', UInt64(Cardinal(DvlUniKinds%s([A]))));"
                   % (name, tag))
            e.line("  DevilNote('%s-char-kind', "
                   "UInt64(Cardinal(DvlUniKinds%s(['x']))));" % (name, tag))
            e.line("end;")

        elif shape == "generic-codepage":
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line("  TDvlKeep%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  K: TDvlKeep%s<TDvlCp%s>;" % (tag, tag))
            e.line("  U: TDvlKeep%s<UTF8String>;" % tag)
            e.line("begin")
            e.line("  { a specialization must keep the codepage its argument "
                   "type carries, not fall back to the default }")
            e.line("  K.Value := TDvlCp%s(string(%s));" % (tag, escaped_literal(text)))
            e.line("  U.Value := UTF8String(string(%s));" % escaped_literal(text))
            e.line("  DevilCheckU('%s-cp1251-bytes', "
                   "UInt64(Length(K.Value)), %d);" % (name, len(cp1251)))
            e.line("  DevilCheckU('%s-utf8-bytes', "
                   "UInt64(Length(U.Value)), %d);" % (name, len(utf8)))
            e.line("  DevilCheckU('%s-cp1251-page', "
                   "UInt64(StringCodePage(K.Value)), 1251);" % name)
            e.line("  DevilCheckU('%s-utf8-page', "
                   "UInt64(StringCodePage(U.Value)), 65001);" % name)
            e.line("end;")

        elif shape == "setstring-bytes":
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: TDvlCp%s;" % tag)
            e.line("  S: string;")
            e.line("  Buffer: array[0..%d] of AnsiChar;" % max(1, len(cp1251) - 1))
            e.line("begin")
            for position, byte in enumerate(cp1251):
                e.line("  Buffer[%d] := AnsiChar($%02X);" % (position, byte))
            e.line("  SetString(A, PAnsiChar(@Buffer[0]), %d);" % len(cp1251))
            e.line("  { bytes placed by hand keep their codepage identity, so "
                   "widening them must go through cp1251 }")
            e.line("  DevilCheckU('%s-length', UInt64(Length(A)), %d);"
                   % (name, len(cp1251)))
            e.line("  DevilCheckU('%s-page', UInt64(StringCodePage(A)), 1251);"
                   % name)
            e.line("  S := string(A);")
            e.line("  DevilCheckU('%s-widened', UInt64(Length(S)), %d);"
                   % (name, len(units)))
            e.line("  DevilCheckU('%s-widened-unit', UInt64(Ord(S[1])), %d);"
                   % (name, units[0]))
            e.line("end;")

        elif shape == "inline-string":
            e.line("function DvlInlineLen%s(const S: string): Integer; inline;"
                   % tag)
            e.line("begin")
            e.line("  Result := Length(S);")
            e.line("end;")
            e.line()
            e.line("function DvlInlineCat%s(const S: string): string; inline;"
                   % tag)
            e.line("begin")
            e.line("  Result := S + S;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  { inlining must not change who owns the temporary that "
                   "carries a managed result }")
            e.line("  DevilCheckU('%s-length', "
                   "UInt64(Cardinal(DvlInlineLen%s(S))), %d);"
                   % (name, tag, len(units)))
            e.line("  DevilCheckU('%s-doubled', "
                   "UInt64(Length(DvlInlineCat%s(S))), %d);"
                   % (name, tag, len(units) * 2))
            e.line("  DevilCheckU('%s-nested', "
                   "UInt64(Cardinal(DvlInlineLen%s(DvlInlineCat%s(S)))), %d);"
                   % (name, tag, tag, len(units) * 2))
            e.line("end;")

        elif shape == "interface-string":
            e.line("type")
            e.line("  IDvlText%s = interface" % tag)
            e.line("    ['{7F2C%04X-0000-0000-0000-00000000%04X}']"
                   % (index % 0xFFFF, index % 0xFFFF))
            e.line("    function Text: string;")
            e.line("    function Bytes: UTF8String;")
            e.line("  end;")
            e.line()
            e.line("  TDvlText%s = class(TInterfacedObject, IDvlText%s)" % (tag, tag))
            e.line("    function Text: string;")
            e.line("    function Bytes: UTF8String;")
            e.line("  end;")
            e.line()
            e.line("function TDvlText%s.Text: string;" % tag)
            e.line("begin")
            e.line("  Result := %s;" % escaped_literal(text))
            e.line("end;")
            e.line()
            e.line("function TDvlText%s.Bytes: UTF8String;" % tag)
            e.line("begin")
            e.line("  Result := UTF8String(Text);")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  T: IDvlText%s;" % tag)
            e.line("begin")
            e.line("  T := TDvlText%s.Create;" % tag)
            e.line("  { a virtual call returns its managed result through the "
                   "same hidden slot as a direct one }")
            e.line("  DevilCheckU('%s-units', UInt64(Length(T.Text)), %d);"
                   % (name, len(units)))
            e.line("  DevilCheckU('%s-bytes', UInt64(Length(T.Bytes)), %d);"
                   % (name, len(utf8)))
            e.line("  DevilCheckU('%s-unit', UInt64(Ord(T.Text[1])), %d);"
                   % (name, units[0]))
            e.line("end;")

        elif shape == "dynarray-string":
            width = rng.randrange(2, 6)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<string>;")
            e.line("  B: array of UTF8String;")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  SetLength(A, %d);" % width)
            e.line("  SetLength(B, %d);" % width)
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("  begin")
            e.line("    A[I] := %s;" % escaped_literal(text))
            e.line("    B[I] := UTF8String(A[I]);")
            e.line("  end;")
            e.line("  Total := 0;")
            e.line("  for var S in A do")
            e.line("    Total := Total + Length(S);")
            e.line("  DevilCheckU('%s-units', UInt64(Cardinal(Total)), %d);"
                   % (name, len(units) * width))
            e.line("  Total := 0;")
            e.line("  for var S in B do")
            e.line("    Total := Total + Length(S);")
            e.line("  DevilCheckU('%s-bytes', UInt64(Cardinal(Total)), %d);"
                   % (name, len(utf8) * width))
            e.line("  DevilCheckU('%s-element', UInt64(SizeOf(A[0])), 8);" % name)
            e.line("end;")

        elif shape == "compare-codepage":
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: TDvlCp%s;" % tag)
            e.line("  U: UTF8String;")
            e.line("  S: string;")
            e.line("begin")
            e.line("  S := %s;" % escaped_literal(text))
            e.line("  A := TDvlCp%s(S);" % tag)
            e.line("  U := UTF8String(S);")
            e.line("  { comparing two byte strings of different codepages is a "
                   "comparison of text, so the compiler must widen both }")
            e.line("  DevilCheckU('%s-equal', UInt64(Ord(A = U)), 1);" % name)
            e.line("  DevilCheckU('%s-equal-wide', UInt64(Ord(S = string(A))), 1);"
                   % name)
            e.line("  DevilCheckU('%s-differ', "
                   "UInt64(Ord(A = TDvlCp%s(S + 'z'))), 0);" % (name, tag))
            e.line("end;")

        else:   # concat-codepage
            e.line("type")
            e.line("  TDvlCp%s = type AnsiString(1251);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: TDvlCp%s;" % tag)
            e.line("  U: UTF8String;")
            e.line("  C: TDvlCp%s;" % tag)
            e.line("begin")
            e.line("  A := TDvlCp%s(string(%s));" % (tag, escaped_literal(text)))
            e.line("  U := UTF8String(A);")
            e.line("  { a cast between two byte string types renames the bytes, "
                   "it does not convert them }")
            e.line("  DevilCheckU('%s-cast-length', UInt64(Length(U)), %d);"
                   % (name, len(cp1251)))
            e.line("  DevilCheckU('%s-cast-byte', UInt64(Ord(U[1])), %d);"
                   % (name, cp1251[0]))
            e.line("  U := UTF8String(string(A));")
            e.line("  { going through text is what actually converts }")
            e.line("  DevilCheckU('%s-utf8-length', UInt64(Length(U)), %d);"
                   % (name, len(utf8)))
            e.line("  DevilCheckU('%s-utf8-byte', UInt64(Ord(U[1])), %d);"
                   % (name, utf8[0]))
            e.line("  { The destination type is part of a byte-string concat: "
                   "a typed cp1251 result keeps that domain. Assigning the "
                   "same two typed values to RawByteString deliberately uses "
                   "the system-codepage path instead (covered separately). }")
            e.line("  C := A + AnsiString('z');")
            e.line("  DevilCheckU('%s-concat-length', UInt64(Length(C)), %d);"
                   % (name, len(cp1251) + 1))
            e.line("  DevilCheckU('%s-concat-codepage', "
                   "UInt64(StringCodePage(C)), 1251);" % name)
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="uni",
                                  detail={"shape": shape, "text": text}))

    emit_runner(e, "Uni", calls)
    return records


# Unwinding is where a compiler has the most freedom to be wrong quietly: the
# value is never wrong, the order is.  Every form here writes a trail as it
# runs, so the assertion is the exact sequence of steps, not a final number.
# The language fixes these orders, so they are checks, not observations.
EXC_SHAPES = ("nested-finally-order", "typed-except", "reraise",
              "raise-in-finally", "exception-in-constructor",
              "managed-unwind", "nested-except", "exit-in-except",
              "class-hierarchy-catch", "exception-in-loop",
              "deep-unwind", "except-else", "finally-in-loop",
              "message-survives", "destructor-during-unwind",
              "exception-in-nested-call", "finally-returns-value",
              "raise-after-except")


def layer_exceptions(e: Emitter, rng: random.Random, count: int,
                     start: int) -> list[CaseRecord]:
    """Exceptions: the order of unwinding, and what stays alive across it."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-exc-%05d" % index
        proc = "DvlExc%05d" % index
        tag = "%05d" % index
        shape = rng.choice(EXC_SHAPES)
        depth = rng.randrange(2, 5)

        def trail(expected: str) -> str:
            return ("  DevilCheckTrail('%s-trail', DevilTrail, '%s');"
                    % (name, expected))

        if shape == "nested-finally-order":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            for level in range(depth):
                e.line("  " + "  " * level + "try")
            e.line("  " + "  " * depth + "DevilTrailAdd('r');")
            e.line("  " + "  " * depth + "raise Exception.Create('x');")
            for level in range(depth - 1, -1, -1):
                e.line("  " + "  " * level + "finally")
                e.line("  " + "  " * level + "  DevilTrailAdd('%d');" % level)
                e.line("  " + "  " * level + "end;")
            e.line("  except")
            e.line("    DevilTrailAdd('c');")
            e.line("  end;")
            e.line("  { finally blocks run inside out, then the handler }")
            e.line(trail("r" + "".join(str(l) for l in range(depth - 1, -1, -1))
                         + "c"))
            e.line("end;")

        elif shape == "typed-except":
            e.line("type")
            e.line("  EDvlA%s = class(Exception);" % tag)
            e.line("  EDvlB%s = class(EDvlA%s);" % (tag, tag))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            e.line("    raise EDvlB%s.Create('b');" % tag)
            e.line("  except")
            e.line("    on E: EDvlB%s do" % tag)
            e.line("      DevilTrailAdd('b');")
            e.line("    on E: EDvlA%s do" % tag)
            e.line("      DevilTrailAdd('a');")
            e.line("    on E: Exception do")
            e.line("      DevilTrailAdd('e');")
            e.line("  end;")
            e.line("  try")
            e.line("    raise EDvlA%s.Create('a');" % tag)
            e.line("  except")
            e.line("    on E: EDvlB%s do" % tag)
            e.line("      DevilTrailAdd('B');")
            e.line("    on E: EDvlA%s do" % tag)
            e.line("      DevilTrailAdd('A');")
            e.line("  end;")
            e.line("  { the first matching arm wins, and a derived class must "
                   "not fall through to its base }")
            e.line(trail("bA"))
            e.line("end;")

        elif shape == "reraise":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Caught: Integer;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  Caught := 0;")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('inner');")
            e.line("    except")
            e.line("      DevilTrailAdd('i');")
            e.line("      raise;")
            e.line("    end;")
            e.line("  except")
            e.line("    on E: Exception do")
            e.line("    begin")
            e.line("      DevilTrailAdd('o');")
            e.line("      If E.Message = 'inner' then")
            e.line("        Caught := 1;")
            e.line("    end;")
            e.line("  end;")
            e.line("  { a bare raise re-throws the same object, message and all }")
            e.line(trail("io"))
            e.line("  DevilCheckU('%s-same-object', UInt64(Cardinal(Caught)), 1);"
                   % name)
            e.line("end;")

        elif shape == "raise-in-finally":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Seen: Integer;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  Seen := 0;")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('first');")
            e.line("    finally")
            e.line("      DevilTrailAdd('f');")
            e.line("      raise Exception.Create('second');")
            e.line("    end;")
            e.line("  except")
            e.line("    on E: Exception do")
            e.line("    begin")
            e.line("      DevilTrailAdd('c');")
            e.line("      If E.Message = 'second' then")
            e.line("        Seen := 2;")
            e.line("    end;")
            e.line("  end;")
            e.line("  { an exception raised while unwinding replaces the one "
                   "that started the unwind }")
            e.line(trail("fc"))
            e.line("  DevilCheckU('%s-replaced', UInt64(Cardinal(Seen)), 2);" % name)
            e.line("end;")

        elif shape == "exception-in-constructor":
            e.line("type")
            e.line("  TDvlHalf%s = class" % tag)
            e.line("  public")
            e.line("    Text: string;")
            e.line("    Guard: IInterface;")
            e.line("    constructor Create(Broken: Boolean);")
            e.line("    destructor Destroy; override;")
            e.line("  end;")
            e.line()
            e.line("constructor TDvlHalf%s.Create(Broken: Boolean);" % tag)
            e.line("begin")
            e.line("  inherited Create;")
            e.line("  Text := 'held';")
            e.line("  Guard := TDvlTagged.Create('g');")
            e.line("  DevilTrailAdd('n');")
            e.line("  If Broken then")
            e.line("    raise Exception.Create('half');")
            e.line("end;")
            e.line()
            e.line("destructor TDvlHalf%s.Destroy;" % tag)
            e.line("begin")
            e.line("  DevilTrailAdd('d');")
            e.line("  inherited Destroy;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Before: Integer;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  Before := TDvlTagged.Alive;")
            e.line("  try")
            e.line("    TDvlHalf%s.Create(True);" % tag)
            e.line("  except")
            e.line("    DevilTrailAdd('c');")
            e.line("  end;")
            e.line("  { a constructor that raises must still run the destructor "
                   "so the fields it already filled are released }")
            e.line(trail("ndgc"))
            e.line("  DevilCheckU('%s-fields-released', "
                   "UInt64(Cardinal(TDvlTagged.Alive)), %s);"
                   % (name, "UInt64(Cardinal(Before))"))
            e.line("end;")

        elif shape == "managed-unwind":
            e.line("procedure DvlExcDeep%s(Level: Integer);" % tag)
            e.line("var")
            e.line("  Held: IInterface;")
            e.line("  Text: string;")
            e.line("begin")
            e.line("  Held := TDvlTagged.Create('L');")
            e.line("  Text := 'level';")
            e.line("  If Level > 0 then")
            e.line("    DvlExcDeep%s(Level - 1)" % tag)
            e.line("  else")
            e.line("    raise Exception.Create('bottom');")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Before: Integer;")
            e.line("begin")
            e.line("  Before := TDvlTagged.Alive;")
            e.line("  try")
            e.line("    DvlExcDeep%s(%d);" % (tag, depth))
            e.line("  except")
            e.line("  end;")
            e.line("  { every frame the unwind passes through releases its own "
                   "managed locals }")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlTagged.Alive)), UInt64(Cardinal(Before)));"
                   % name)
            e.line("end;")

        elif shape == "nested-except":
            e.line("type")
            e.line("  EDvlOnly%s = class(Exception);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('generic');")
            e.line("    except")
            e.line("      on E: EDvlOnly%s do" % tag)
            e.line("        DevilTrailAdd('w');")
            e.line("    end;")
            e.line("  except")
            e.line("    on E: Exception do")
            e.line("      DevilTrailAdd('o');")
            e.line("  end;")
            e.line("  { an except block that matches nothing lets the exception "
                   "continue outward untouched }")
            e.line(trail("o"))
            e.line("end;")

        elif shape == "exit-in-except":
            e.line("function DvlExcExit%s: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('x');")
            e.line("    except")
            e.line("      DevilTrailAdd('e');")
            e.line("      Result := 7;")
            e.line("      Exit;")
            e.line("    end;")
            e.line("  finally")
            e.line("    DevilTrailAdd('f');")
            e.line("  end;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: Integer;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  R := DvlExcExit%s;" % tag)
            e.line("  { leaving a handler by Exit still runs the finally that "
                   "encloses it, and keeps the result already assigned }")
            e.line(trail("ef"))
            e.line("  DevilCheckU('%s-result', UInt64(Cardinal(R)), 7);" % name)
            e.line("end;")

        elif shape == "class-hierarchy-catch":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Kind: Integer;")
            e.line("begin")
            e.line("  Kind := 0;")
            e.line("  try")
            e.line("    raise EZeroDivide.Create('d');")
            e.line("  except")
            e.line("    on E: EMathError do")
            e.line("      Kind := 1;")
            e.line("    on E: Exception do")
            e.line("      Kind := 2;")
            e.line("  end;")
            e.line("  { the RTL hierarchy must be the same one Delphi has }")
            e.line("  DevilCheckU('%s-math', UInt64(Cardinal(Kind)), 1);" % name)
            e.line("  Kind := 0;")
            e.line("  try")
            e.line("    raise ERangeError.Create('r');")
            e.line("  except")
            e.line("    on E: EIntError do")
            e.line("      Kind := 1;")
            e.line("    on E: Exception do")
            e.line("      Kind := 2;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-int', UInt64(Cardinal(Kind)), 1);" % name)
            e.line("end;")

        elif shape == "exception-in-loop":
            rounds = rng.randrange(3, 7)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Caught, Passed: Integer;")
            e.line("begin")
            e.line("  Caught := 0;")
            e.line("  Passed := 0;")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("  begin")
            e.line("    try")
            e.line("      If Odd(I) then")
            e.line("        raise Exception.Create('odd');")
            e.line("      Inc(Passed);")
            e.line("    except")
            e.line("      Inc(Caught);")
            e.line("      Continue;")
            e.line("    end;")
            e.line("  end;")
            e.line("  { Continue from a handler resumes the loop, it does not "
                   "leave it }")
            e.line("  DevilCheckU('%s-caught', UInt64(Cardinal(Caught)), %d);"
                   % (name, (rounds + 1) // 2))
            e.line("  DevilCheckU('%s-passed', UInt64(Cardinal(Passed)), %d);"
                   % (name, rounds // 2))
            e.line("end;")

        elif shape == "deep-unwind":
            e.line("procedure DvlExcFrame%s(Level: Integer);" % tag)
            e.line("begin")
            e.line("  try")
            e.line("    If Level > 0 then")
            e.line("      DvlExcFrame%s(Level - 1)" % tag)
            e.line("    else")
            e.line("      raise Exception.Create('deep');")
            e.line("  finally")
            e.line("    DevilTrailAdd('f');")
            e.line("  end;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            e.line("    DvlExcFrame%s(%d);" % (tag, depth))
            e.line("  except")
            e.line("    DevilTrailAdd('c');")
            e.line("  end;")
            e.line("  { one finally per frame the unwind passes, in order }")
            e.line(trail("f" * (depth + 1) + "c"))
            e.line("end;")

        elif shape == "except-else":
            e.line("type")
            e.line("  EDvlPicked%s = class(Exception);" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            e.line("    raise Exception.Create('other');")
            e.line("  except")
            e.line("    on E: EDvlPicked%s do" % tag)
            e.line("      DevilTrailAdd('p');")
            e.line("  else")
            e.line("    DevilTrailAdd('e');")
            e.line("  end;")
            e.line("  { the else arm catches whatever the typed arms did not }")
            e.line(trail("e"))
            e.line("end;")

        elif shape == "finally-in-loop":
            rounds = rng.randrange(2, 5)
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("  begin")
            e.line("    try")
            e.line("      DevilTrailAdd('t');")
            e.line("      If I = %d then" % rounds)
            e.line("        Break;")
            e.line("    finally")
            e.line("      DevilTrailAdd('f');")
            e.line("    end;")
            e.line("  end;")
            e.line("  { Break leaves through the finally, it does not skip it }")
            e.line(trail("tf" * rounds))
            e.line("end;")

        elif shape == "message-survives":
            e.line("procedure DvlExcThrow%s;" % tag)
            e.line("var")
            e.line("  Held: IInterface;")
            e.line("begin")
            e.line("  Held := TDvlTagged.Create('m');")
            e.line("  raise Exception.CreateFmt('code %%d', [%d]);" % (index % 97))
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Text: string;")
            e.line("begin")
            e.line("  Text := '';")
            e.line("  try")
            e.line("    DvlExcThrow%s;" % tag)
            e.line("  except")
            e.line("    on E: Exception do")
            e.line("      Text := E.Message;")
            e.line("  end;")
            e.line("  { the message is built before the unwind and must survive "
                   "every frame it passes }")
            e.line("  DevilCheckU('%s-message', UInt64(Length(Text)), %d);"
                   % (name, len("code %d" % (index % 97))))
            e.line("end;")

        elif shape == "destructor-during-unwind":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Obj: TDvlTagged;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  try")
            e.line("    Obj := TDvlTagged.Create('x');")
            e.line("    try")
            e.line("      raise Exception.Create('x');")
            e.line("    finally")
            e.line("      DevilTrailAdd('r');")
            e.line("      Obj.Free;")
            e.line("      DevilTrailAdd('d');")
            e.line("    end;")
            e.line("  except")
            e.line("    DevilTrailAdd('c');")
            e.line("  end;")
            e.line("  { a destructor called while unwinding runs to completion "
                   "before the handler starts }")
            e.line(trail("rxdc"))
            e.line("end;")

        elif shape == "exception-in-nested-call":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Reached: Integer;")
            e.line()
            e.line("  procedure Inner;")
            e.line("  begin")
            e.line("    Inc(Reached);")
            e.line("    raise Exception.Create('nested');")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  Reached := 0;")
            e.line("  try")
            e.line("    Inner;")
            e.line("    Inc(Reached, 10);")
            e.line("  except")
            e.line("    Inc(Reached, 100);")
            e.line("  end;")
            e.line("  { a nested routine raises through its parent frame without "
                   "losing the parent's locals }")
            e.line("  DevilCheckU('%s-path', UInt64(Cardinal(Reached)), 101);"
                   % name)
            e.line("end;")

        elif shape == "finally-returns-value":
            e.line("function DvlExcKeep%s: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("  try")
            e.line("    Result := 2;")
            e.line("    Exit;")
            e.line("  finally")
            e.line("    Result := Result + 10;")
            e.line("  end;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a finally block can still change the result after Exit "
                   "has already chosen it }")
            e.line("  DevilCheckU('%s-result', UInt64(Cardinal(DvlExcKeep%s)), 12);"
                   % (name, tag))
            e.line("end;")

        else:   # raise-after-except
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Outer: string;")
            e.line("begin")
            e.line("  DevilTrailReset;")
            e.line("  Outer := '';")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('first');")
            e.line("    except")
            e.line("      DevilTrailAdd('h');")
            e.line("      raise Exception.Create('second');")
            e.line("    end;")
            e.line("  except")
            e.line("    on E: Exception do")
            e.line("    begin")
            e.line("      DevilTrailAdd('o');")
            e.line("      Outer := E.Message;")
            e.line("    end;")
            e.line("  end;")
            e.line("  { raising a new exception inside a handler discards the "
                   "one being handled }")
            e.line(trail("ho"))
            e.line("  DevilCheckU('%s-message', UInt64(Length(Outer)), 6);" % name)
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="exc",
                                  detail={"shape": shape, "depth": depth}))

    emit_runner(e, "Exc", calls)
    return records


# Startup and shutdown order is fixed by the language and invisible in every
# value: a unit is initialized after everything it depends on, and finalized in
# the exact reverse.  Getting it wrong shows up as a global that is empty when
# it should be filled, or a released object touched during shutdown - the kind
# of failure that looks random at run time.
#
# The chain is deliberately not the uses order of the program: A uses B, B uses
# C, so the program mentions only A and the compiler has to work the order out.
INIT_SHAPES = ("init-order", "global-from-unit", "class-constructor",
               "managed-global", "nested-dependency", "const-record-init",
               "circular-implementation")

INIT_UNITS = ("devil_init_c", "devil_init_b", "devil_init_a")


def write_init_units(out: Path) -> None:
    """Three units in a dependency chain, each marking its own order."""
    for index, unit in enumerate(INIT_UNITS):
        letter = "cba"[index]
        depends = INIT_UNITS[index - 1] if index else None
        lines = ["unit %s;" % unit, "",
                 "{$ifdef FPC}",
                 "  {$mode delphiunicode}{$H+}",
                 "  {$modeswitch advancedrecords}",
                 "{$endif}",
                 "{$Q-}{$R-}", "",
                 "interface", "", "uses",
                 "  SysUtils, devil_runtime%s;"
                 % (", " + depends if depends else ""), "",
                 "type",
                 "  TDvl%sHolder = class" % letter.upper(),
                 "  public",
                 "    class var Stamp: Integer;",
                 "    class constructor Create;",
                 "    class destructor Destroy;",
                 "  end;", "",
                 "var",
                 "  Dvl%sMark: Integer;" % letter.upper(),
                 "  Dvl%sText: AnsiString;" % letter.upper(), "",
                 "implementation", "",
                 "class constructor TDvl%sHolder.Create;" % letter.upper(),
                 "begin",
                 "  Stamp := %d;" % (index + 1),
                 "  DevilUnitTrailAdd('%s');" % letter.upper(),
                 "end;", "",
                 "class destructor TDvl%sHolder.Destroy;" % letter.upper(),
                 "begin",
                 "  Stamp := 0;",
                 "end;", "",
                 "initialization",
                 "  DevilUnitTrailAdd('%s');" % letter,
                 "  Dvl%sMark := %d;" % (letter.upper(), (index + 1) * 10),
                 "  Dvl%sText := '%s';" % (letter.upper(), letter * 3)]
        if depends:
            lines.append("  { a unit sees its dependency already initialized }")
            lines.append("  Dvl%sMark := Dvl%sMark + Dvl%sMark;"
                         % (letter.upper(), letter.upper(), "cba"[index - 1].upper()))
        lines += ["", "finalization",
                  "  DevilUnitTrailAdd('%s');" % letter.upper()]
        if index == 0:
            lines.append("  { finalization runs in reverse, so the unit that "
                         "was ready first shuts down last }")
            lines.append("  DevilCheckTrail('dvl-init-shutdown-trail', "
                         "DevilUnitTrail, 'CcBbAayxABC');")
        lines.append("")
        lines.append("end.")
        (out / ("%s.pas" % unit)).write_text("\n".join(lines) + "\n",
                                             encoding="utf-8")



def write_cycle_units(out: Path) -> None:
    """Two units that call each other through their implementation sections.

    The edge is not just for name resolution: the unit named in an
    implementation uses clause is initialized first, so y comes before x.
    """
    for first, second, letter, value in (("devil_cycle_x", "devil_cycle_y", "x", 3),
                                         ("devil_cycle_y", "devil_cycle_x", "y", 4)):
        other_call = "Dvl%sStep" % ("Y" if letter == "x" else "X")
        lines = ["unit %s;" % first, "",
                 "{$ifdef FPC}",
                 "  {$mode delphiunicode}{$H+}",
                 "{$endif}",
                 "{$Q-}{$R-}", "",
                 "interface", "", "uses",
                 "  SysUtils, devil_runtime;", "",
                 "function Dvl%sStep(Depth: Integer): Integer;" % letter.upper(),
                 "", "var",
                 "  Dvl%sReady: Integer;" % letter.upper(), "",
                 "implementation", "", "uses",
                 "  %s;" % second, "",
                 "function Dvl%sStep(Depth: Integer): Integer;" % letter.upper(),
                 "begin",
                 "  If Depth <= 0 then",
                 "    Result := %d" % value,
                 "  else",
                 "    { the call goes to the other unit, which calls back here }",
                 "    Result := %d + %s(Depth - 1);" % (value, other_call),
                 "end;", "",
                 "initialization",
                 "  DevilUnitTrailAdd('%s');" % letter,
                 "  Dvl%sReady := %d;" % (letter.upper(), value), "",
                 "end."]
        (out / ("%s.pas" % first)).write_text("\n".join(lines) + "\n",
                                              encoding="utf-8")

def layer_init(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Unit startup: what is ready, and in which order it became ready."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-init-%05d" % index
        proc = "DvlInit%05d" % index
        shape = INIT_SHAPES[index % len(INIT_SHAPES)]

        if shape == "init-order":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { the chain decides the order, not the uses clause; a "
                   "class constructor runs just before its own unit body }")
            e.line("  DevilCheckU('%s-order', "
                   "UInt64(Ord(DevilUnitTrail = 'CcBbAayx')), 1);" % name)
            e.line("end;")

        elif shape == "global-from-unit":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { each unit filled its own global before the program "
                   "body started }")
            e.line("  DevilCheckU('%s-c', UInt64(Cardinal(DvlCMark)), 10);" % name)
            e.line("  DevilCheckU('%s-text', UInt64(Length(DvlCText)), 3);" % name)
            e.line("end;")

        elif shape == "class-constructor":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a class constructor runs once, before anything can "
                   "touch the class }")
            e.line("  DevilCheckU('%s-c', UInt64(Cardinal(TDvlCHolder.Stamp)), 1);"
                   % name)
            e.line("  DevilCheckU('%s-b', UInt64(Cardinal(TDvlBHolder.Stamp)), 2);"
                   % name)
            e.line("  DevilCheckU('%s-a', UInt64(Cardinal(TDvlAHolder.Stamp)), 3);"
                   % name)
            e.line("end;")

        elif shape == "managed-global":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  Total := Length(DvlAText) + Length(DvlBText) + "
                   "Length(DvlCText);")
            e.line("  { managed globals of a unit are alive from its "
                   "initialization until its finalization }")
            e.line("  DevilCheckU('%s-total', UInt64(Cardinal(Total)), 9);" % name)
            e.line("end;")

        elif shape == "nested-dependency":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { B added C's value to its own, so B ran after C }")
            e.line("  DevilCheckU('%s-b', UInt64(Cardinal(DvlBMark)), 30);" % name)
            e.line("  { and A added B's already-summed value }")
            e.line("  DevilCheckU('%s-a', UInt64(Cardinal(DvlAMark)), 60);" % name)
            e.line("end;")

        elif shape == "circular-implementation":
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { two units that use each other through implementation: "
                   "both are ready, and a call can bounce between them }")
            e.line("  DevilCheckU('%s-x-ready', UInt64(Cardinal(DvlXReady)), 3);"
                   % name)
            e.line("  DevilCheckU('%s-y-ready', UInt64(Cardinal(DvlYReady)), 4);"
                   % name)
            e.line("  DevilCheckU('%s-bounce-none', "
                   "UInt64(Cardinal(DvlXStep(0))), 3);" % name)
            e.line("  DevilCheckU('%s-bounce-one', "
                   "UInt64(Cardinal(DvlXStep(1))), 7);" % name)
            e.line("  DevilCheckU('%s-bounce-three', "
                   "UInt64(Cardinal(DvlXStep(3))), 14);" % name)
            e.line("end;")

        else:   # const-record-init
            e.line("type")
            e.line("  TDvlSeed%05d = record" % index)
            e.line("    Name: string;")
            e.line("    Count: Integer;")
            e.line("  end;")
            e.line()
            e.line("const")
            e.line("  DvlSeed%05d: TDvlSeed%05d = (Name: 'seed'; Count: %d);"
                   % (index, index, index % 97))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a typed constant with a managed field is built before "
                   "any code runs, and stays valid }")
            e.line("  DevilCheckU('%s-name', "
                   "UInt64(Length(DvlSeed%05d.Name)), 4);" % (name, index))
            e.line("  DevilCheckU('%s-count', "
                   "UInt64(Cardinal(DvlSeed%05d.Count)), %d);"
                   % (name, index, index % 97))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="init",
                                  detail={"shape": shape}))

    emit_runner(e, "Init", calls)
    return records


# An optimizer is wrong in a very specific way: the program still runs, still
# produces a number, and the number is stale.  Every form here sets up a
# situation where a tempting transformation would be incorrect - two names for
# one location, a call that must not be hoisted, a store that looks dead - and
# then asks for the value the language promises.
#
# Nothing here is arithmetic: the numbers are trivial on purpose, and what is
# being checked is whether the write happened, in the order it was written.
OPT_EFFECT_ROUTES = (
    "global-call",
    "var-call",
    "pointer-call",
    "record-pointer",
    "array-pointer",
    "object-method",
    "virtual-method",
    "interface-call",
    "nested-call",
    "anonymous-call",
    "procvar-global",
    "cross-unit",
)

OPT_EFFECT_CONSUMERS = (
    "counter-mul",
    "affine-cse",
    "array-index",
    "branch",
    "division",
    "shift",
    "mixed",
)

OPT_EFFECT_TIMINGS = (
    "before-each",
    "between-each",
    "after-each",
    "after-first",
    "after-even",
    "finally-between",
)

OPT_EFFECT_LOOPS = ("for", "while", "repeat", "nested")
OPT_EFFECT_TYPES = tuple(TYPE_BY_SLUG[slug]
                         for slug in ("i32", "u32", "i64", "u64"))


def write_opt_effect_unit(out: Path) -> None:
    """Opaque cross-PPU mutations used by the optimizer effects matrix."""
    lines = [
        "unit devil_opt_effect_unit;",
        "",
        "{$ifdef FPC}",
        "  {$mode delphiunicode}{$H+}",
        "{$endif}",
        "{$Q-}{$R-}",
        "",
        "interface",
        "",
    ]
    for t in OPT_EFFECT_TYPES:
        lines.append(f"var DvlEffectExternal{t.slug}: {t.pascal};")
    lines.append("")
    for t in OPT_EFFECT_TYPES:
        lines.append(
            f"procedure DvlEffectExternalBump{t.slug}(Delta: {t.pascal});")
    lines += ["", "implementation", ""]
    for t in OPT_EFFECT_TYPES:
        lines += [
            f"procedure DvlEffectExternalBump{t.slug}(Delta: {t.pascal});",
            "begin",
            f"  DvlEffectExternal{t.slug} := "
            f"DvlEffectExternal{t.slug} + Delta;",
            "end;",
            "",
        ]
    lines.append("end.")
    (out / "devil_opt_effect_unit.pas").write_text(
        "\n".join(lines) + "\n", encoding="utf-8")


def opt_effect_value(consumer: str, value: int, counter: int,
                     lane: int) -> int:
    """Independent arithmetic model for one observable memory-effect use."""
    if consumer == "counter-mul":
        return counter * value
    if consumer == "affine-cse":
        return (counter + lane) * value + value * 3
    if consumer == "array-index":
        index = (counter * value + lane) & 31
        return index * 7 + 3
    if consumer == "branch":
        return counter * (7 if value & 1 == 0 else 11) + lane
    if consumer == "division":
        return 100000 // (value + counter + lane + 1)
    if consumer == "shift":
        return (counter << (value & 3)) + lane
    if consumer == "mixed":
        return (counter * value) ^ ((counter + lane + 1) * value)
    raise ValueError(consumer)


def opt_effect_expected(initial: int, delta: int, consumer: str,
                        timing: str) -> int:
    """Model mutation placement without sharing the emitted Pascal lowering."""
    value = initial
    total = 0
    for counter in range(1, 7):
        if timing == "before-each":
            value += delta
        total += opt_effect_value(consumer, value, counter, 0)
        if timing in ("between-each", "finally-between"):
            value += delta
            total += opt_effect_value(consumer, value, counter, 1)
        elif timing == "after-each":
            value += delta
        elif timing == "after-first" and counter == 1:
            value += delta
        elif timing == "after-even" and counter & 1 == 0:
            value += delta
    return total & 0xFFFFFFFFFFFFFFFF


def opt_effect_expression(consumer: str, read: str, counter: str,
                          lane: int) -> list[str]:
    """Pascal statements for one use; repeated loads stay visible to CSE/GVN."""
    value = f"Integer({read})"
    if consumer == "counter-mul":
        expression = f"Int64({counter} * {read})"
    elif consumer == "affine-cse":
        expression = (f"Int64(({counter} + {lane}) * {read}) + "
                      f"Int64({read}) * 3")
    elif consumer == "array-index":
        expression = f"Table[(({counter} * {value}) + {lane}) and 31]"
    elif consumer == "division":
        expression = f"100000 div ({value} + {counter} + {lane} + 1)"
    elif consumer == "shift":
        expression = f"({counter} shl ({value} and 3)) + {lane}"
    elif consumer == "mixed":
        expression = (f"Int64(({counter} * {value}) xor "
                      f"(({counter} + {lane + 1}) * {value}))")
    elif consumer == "branch":
        return [
            f"if ({value} and 1) = 0 then",
            f"  Total := Total + {counter} * 7 + {lane}",
            "else",
            f"  Total := Total + {counter} * 11 + {lane};",
        ]
    else:
        raise ValueError(consumer)
    return [f"Total := Total + {expression};"]


def indent_lines(lines: list[str], indent: str) -> list[str]:
    return [indent + line for line in lines]


def emit_opt_effect_case(e: Emitter, index: int, route: str, consumer: str,
                         timing: str, loop: str, t: IntType, initial: int,
                         delta: int) -> tuple[CaseRecord, str]:
    """Emit one adversarial memory-effects case and its independent oracle."""
    tag = f"{index:05d}"
    name = f"dvl-opt-effect-{tag}"
    proc = f"DvlOptEffect{tag}"
    value_name = f"DvlOptEffectValue{tag}"
    bump_name = f"DvlOptEffectBump{tag}"
    read = "Value"
    mutate = f"{bump_name}(Value);"
    local_decls: list[str] = []
    setup: list[str] = []
    cleanup: list[str] = []
    nested: list[str] = []

    e.line(f"{{ optimizer effects: {route} x {consumer} x {timing} x "
           f"{loop} x {t.slug} }}")
    if route == "global-call":
        e.line("var")
        e.line(f"  {value_name}: {t.pascal};")
        e.line()
        e.line(f"procedure {bump_name};")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  {value_name} := {value_name} + {t.literal(delta)};")
        e.line("end;")
        e.line()
        read = value_name
        mutate = f"{bump_name};"
        setup.append(f"  {value_name} := {t.literal(initial)};")
    elif route == "var-call":
        e.line(f"procedure {bump_name}(var Target: {t.pascal});")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  Target := Target + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls.append(f"  Value: {t.pascal};")
    elif route == "pointer-call":
        pointer_type = f"PDvlOptEffect{tag}"
        e.line("type")
        e.line(f"  {pointer_type} = ^{t.pascal};")
        e.line()
        e.line(f"procedure {bump_name}(Target: {pointer_type});")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  Target^ := Target^ + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls += [f"  Value: {t.pascal};", f"  Pointer: {pointer_type};"]
        setup.append("  Pointer := @Value;")
        mutate = f"{bump_name}(Pointer);"
    elif route == "record-pointer":
        record_type = f"TDvlOptEffectRecord{tag}"
        pointer_type = f"PDvlOptEffectRecord{tag}"
        e.line("type")
        e.line(f"  {record_type} = record")
        e.line(f"    Value: {t.pascal};")
        e.line("  end;")
        e.line(f"  {pointer_type} = ^{record_type};")
        e.line()
        e.line(f"procedure {bump_name}(Target: {pointer_type});")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  Target^.Value := Target^.Value + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls.append(f"  Cell: {record_type};")
        read = "Cell.Value"
        mutate = f"{bump_name}(@Cell);"
        setup.append(f"  Cell.Value := {t.literal(initial)};")
    elif route == "array-pointer":
        pointer_type = f"PDvlOptEffectElement{tag}"
        e.line("type")
        e.line(f"  {pointer_type} = ^{t.pascal};")
        e.line()
        e.line(f"procedure {bump_name}(Target: {pointer_type});")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  Target^ := Target^ + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls.append(f"  Values: array[0..3] of {t.pascal};")
        read = "Values[2]"
        mutate = f"{bump_name}(@Values[2]);"
        setup.append(f"  Values[2] := {t.literal(initial)};")
    elif route == "object-method":
        object_type = f"TDvlOptEffectObject{tag}"
        e.line("type")
        e.line(f"  {object_type} = class")
        e.line("  public")
        e.line(f"    Value: {t.pascal};")
        e.line("    procedure Bump;")
        e.line("  end;")
        e.line()
        e.line(f"procedure {object_type}.Bump;")
        e.line("begin")
        e.line(f"  Value := Value + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls.append(f"  Obj: {object_type};")
        read = "Obj.Value"
        mutate = "Obj.Bump;"
        setup += [f"  Obj := {object_type}.Create;",
                  f"  Obj.Value := {t.literal(initial)};"]
        cleanup.append("  Obj.Free;")
    elif route == "virtual-method":
        base_type = f"TDvlOptEffectBase{tag}"
        child_type = f"TDvlOptEffectChild{tag}"
        e.line("type")
        e.line(f"  {base_type} = class")
        e.line("  public")
        e.line(f"    Value: {t.pascal};")
        e.line("    procedure Bump; virtual;")
        e.line("  end;")
        e.line(f"  {child_type} = class({base_type})")
        e.line("  public")
        e.line("    procedure Bump; override;")
        e.line("  end;")
        e.line()
        for owner in (base_type, child_type):
            e.line(f"procedure {owner}.Bump;")
            e.line("begin")
            e.line(f"  Value := Value + {t.literal(delta)};")
            e.line("end;")
            e.line()
        local_decls.append(f"  Obj: {base_type};")
        read = "Obj.Value"
        mutate = "Obj.Bump;"
        setup += [f"  Obj := {child_type}.Create;",
                  f"  Obj.Value := {t.literal(initial)};"]
        cleanup.append("  Obj.Free;")
    elif route == "interface-call":
        intf_type = f"IDvlOptEffect{tag}"
        object_type = f"TDvlOptEffectInterfaced{tag}"
        guid = f"{{D0E00000-0000-0000-0000-{index:012X}}}"
        e.line("type")
        e.line(f"  {intf_type} = interface")
        e.line(f"    ['{guid}']")
        e.line("    procedure Bump;")
        e.line("  end;")
        e.line(f"  {object_type} = class(TInterfacedObject, {intf_type})")
        e.line("  public")
        e.line(f"    Value: {t.pascal};")
        e.line("    procedure Bump;")
        e.line("  end;")
        e.line()
        e.line(f"procedure {object_type}.Bump;")
        e.line("begin")
        e.line(f"  Value := Value + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls += [f"  Obj: {object_type};", f"  Intf: {intf_type};"]
        read = "Obj.Value"
        mutate = "Intf.Bump;"
        setup += [f"  Obj := {object_type}.Create;", "  Intf := Obj;",
                  f"  Obj.Value := {t.literal(initial)};"]
        cleanup.append("  Intf := nil;")
    elif route == "nested-call":
        local_decls.append(f"  Value: {t.pascal};")
        nested = [
            f"  procedure {bump_name};",
            "  begin",
            f"    Value := Value + {t.literal(delta)};",
            "  end;",
        ]
        mutate = f"{bump_name};"
    elif route == "anonymous-call":
        proc_type = f"TDvlOptEffectProc{tag}"
        e.line("type")
        e.line(f"  {proc_type} = reference to procedure;")
        e.line()
        local_decls += [f"  Value: {t.pascal};", f"  Bump: {proc_type};"]
        setup.append("  Bump := procedure")
        setup.append("    begin")
        setup.append(f"      Value := Value + {t.literal(delta)};")
        setup.append("    end;")
        setup.append("  ;")
        mutate = "Bump();"
        cleanup.append("  Bump := nil;")
    elif route == "procvar-global":
        proc_type = f"TDvlOptEffectPlainProc{tag}"
        e.line("type")
        e.line(f"  {proc_type} = procedure;")
        e.line("var")
        e.line(f"  {value_name}: {t.pascal};")
        e.line()
        e.line(f"procedure {bump_name};")
        e.line("{$ifdef FPC} noinline; {$endif}")
        e.line("begin")
        e.line(f"  {value_name} := {value_name} + {t.literal(delta)};")
        e.line("end;")
        e.line()
        local_decls.append(f"  Bump: {proc_type};")
        read = value_name
        mutate = "Bump();"
        setup += [f"  {value_name} := {t.literal(initial)};",
                  f"  Bump := {bump_name};"]
    elif route == "cross-unit":
        read = f"DvlEffectExternal{t.slug}"
        mutate = f"DvlEffectExternalBump{t.slug}({t.literal(delta)});"
        setup.append(f"  {read} := {t.literal(initial)};")
    else:
        raise ValueError(route)

    if route not in ("global-call", "record-pointer", "array-pointer",
                     "object-method", "virtual-method", "interface-call",
                     "procvar-global", "cross-unit"):
        setup.insert(0, f"  Value := {t.literal(initial)};")

    e.line(f"procedure {proc};")
    e.line("var")
    e.line("  I, Inner, Outer, J: Integer;")
    e.line("  Total: Int64;")
    if consumer == "array-index":
        e.line("  Table: array[0..31] of Int64;")
    for declaration in local_decls:
        e.line(declaration)
    for line in nested:
        e.line(line)
    e.line("begin")
    for line in setup:
        e.line(line)
    if consumer == "array-index":
        e.line("  for J := 0 to High(Table) do")
        e.line("    Table[J] := J * 7 + 3;")
    e.line("  Total := 0;")

    body: list[str] = []
    if timing == "before-each":
        body.append(mutate)
    body += opt_effect_expression(consumer, read, "I", 0)
    if timing == "between-each":
        body.append(mutate)
        body += opt_effect_expression(consumer, read, "I", 1)
    elif timing == "finally-between":
        first = opt_effect_expression(consumer, read, "I", 0)
        body = (["try"] + indent_lines(first, "  ") + ["finally", "  " + mutate,
                "end;"] + opt_effect_expression(consumer, read, "I", 1))
    elif timing == "after-each":
        body.append(mutate)
    elif timing == "after-first":
        body += ["if I = 1 then", "  " + mutate]
    elif timing == "after-even":
        body += ["if (I and 1) = 0 then", "  " + mutate]

    if loop == "for":
        e.line("  for I := 1 to 6 do")
        e.line("    begin")
        for line in indent_lines(body, "      "):
            e.line(line)
        e.line("    end;")
    elif loop == "while":
        e.line("  I := 1;")
        e.line("  while I <= 6 do")
        e.line("    begin")
        for line in indent_lines(body, "      "):
            e.line(line)
        e.line("      Inc(I);")
        e.line("    end;")
    elif loop == "repeat":
        e.line("  I := 1;")
        e.line("  repeat")
        for line in indent_lines(body, "    "):
            e.line(line)
        e.line("    Inc(I);")
        e.line("  until I > 6;")
    elif loop == "nested":
        e.line("  for Outer := 1 to 2 do")
        e.line("    for Inner := 1 to 3 do")
        e.line("      begin")
        e.line("        I := (Outer - 1) * 3 + Inner;")
        for line in indent_lines(body, "        "):
            e.line(line)
        e.line("      end;")
    else:
        raise ValueError(loop)

    expected = opt_effect_expected(initial, delta, consumer, timing)
    e.line(f"  DevilCheckU('{name}', UInt64(Total), "
           f"UInt64(${expected:016X}));")
    for line in cleanup:
        e.line(line)
    e.line("end;")
    e.line()
    return (CaseRecord(name=name, layer="opt", detail={
        "family": "memory-effects",
        "route": route,
        "consumer": consumer,
        "timing": timing,
        "loop": loop,
        "type": t.slug,
        "initial": initial,
        "delta": delta,
    }), proc)


def emit_opt_effect_matrix(e: Emitter, rng: random.Random,
                           start: int) -> tuple[list[CaseRecord], list[str]]:
    """Cover every route x consumer x mutation timing, not a random sample."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, (route, consumer, timing) in enumerate(itertools.product(
            OPT_EFFECT_ROUTES, OPT_EFFECT_CONSUMERS, OPT_EFFECT_TIMINGS)):
        route_index = OPT_EFFECT_ROUTES.index(route)
        consumer_index = OPT_EFFECT_CONSUMERS.index(consumer)
        timing_index = OPT_EFFECT_TIMINGS.index(timing)
        if (route, consumer, timing) == (
                "global-call", "counter-mul", "after-first"):
            loop = "for"
            t = TYPE_BY_SLUG["i32"]
        else:
            loop = OPT_EFFECT_LOOPS[
                (route_index + 2 * consumer_index + 3 * timing_index) %
                len(OPT_EFFECT_LOOPS)]
            t = OPT_EFFECT_TYPES[
                (route_index + consumer_index + timing_index) %
                len(OPT_EFFECT_TYPES)]
        initial = rng.randrange(3, 10)
        delta = rng.randrange(1, 4)
        record, call = emit_opt_effect_case(
            e, start + offset, route, consumer, timing, loop, t,
            initial, delta)
        records.append(record)
        calls.append(call)
    return records, calls


def opt_effect_coverage(records: list[CaseRecord]) -> dict:
    rows = [record.detail for record in records
            if record.layer == "opt"
            and record.detail.get("family") == "memory-effects"]
    dimensions = {
        "route": OPT_EFFECT_ROUTES,
        "consumer": OPT_EFFECT_CONSUMERS,
        "timing": OPT_EFFECT_TIMINGS,
        "loop": OPT_EFFECT_LOOPS,
        "type": tuple(t.slug for t in OPT_EFFECT_TYPES),
    }
    triples_wanted = set(itertools.product(
        OPT_EFFECT_ROUTES, OPT_EFFECT_CONSUMERS, OPT_EFFECT_TIMINGS))
    triples_seen = {(row["route"], row["consumer"], row["timing"])
                    for row in rows}
    pairs_wanted: set[tuple[str, str, str, str]] = set()
    pairs_seen: set[tuple[str, str, str, str]] = set()
    names = tuple(dimensions)
    for left_index, left in enumerate(names):
        for right in names[left_index + 1:]:
            pairs_wanted.update((left, a, right, b)
                                for a in dimensions[left]
                                for b in dimensions[right])
            pairs_seen.update((left, row[left], right, row[right])
                              for row in rows)
    return {
        "dimensions": {key: list(values)
                       for key, values in dimensions.items()},
        "cases": len(rows),
        "critical_triples_possible": len(triples_wanted),
        "critical_triples_covered": len(triples_wanted & triples_seen),
        "critical_triples_missing": [list(item) for item in
                                     sorted(triples_wanted - triples_seen)],
        "pairs_possible": len(pairs_wanted),
        "pairs_covered": len(pairs_wanted & pairs_seen),
        "pairs_missing": [list(item) for item in
                          sorted(pairs_wanted - pairs_seen)],
        "exact_stale_global_anchor": any(
            row["route"] == "global-call"
            and row["consumer"] == "counter-mul"
            and row["timing"] == "after-first"
            and row["loop"] == "for"
            and row["type"] == "i32" for row in rows),
    }


OPT_SHAPES = ("pointer-alias", "var-param-alias", "field-alias",
              "type-punned-alias", "loop-invariant-mutated",
              "side-effect-in-condition", "dead-store-through-pointer",
              "call-not-hoisted", "aliased-array-element",
              "self-assign-through-pointer", "global-touched-by-call",
              "reload-after-call", "cse-with-side-effect",
              "loop-exit-value", "aliased-record-copy")


def layer_optimizer(e: Emitter, rng: random.Random, count: int,
                    start: int) -> list[CaseRecord]:
    """Transformations that would be wrong: the value must survive them."""
    records, calls = emit_opt_effect_matrix(e, rng, start)
    start += len(records)
    for index in range(start, start + count):
        name = "dvl-opt-%05d" % index
        proc = "DvlOpt%05d" % index
        tag = "%05d" % index
        shape = rng.choice(OPT_SHAPES)
        seed = index % 40 + 1

        if shape == "pointer-alias":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Value: Integer;")
            e.line("  P, Q: PInteger;")
            e.line("begin")
            e.line("  Value := %d;" % seed)
            e.line("  P := @Value;")
            e.line("  Q := P;")
            e.line("  { two names for one location: a write through one is "
                   "visible through the other and through the variable }")
            e.line("  P^ := P^ + 1;")
            e.line("  Q^ := Q^ + 1;")
            e.line("  DevilCheckU('%s-variable', UInt64(Cardinal(Value)), %d);"
                   % (name, seed + 2))
            e.line("  DevilCheckU('%s-through-p', UInt64(Cardinal(P^)), %d);"
                   % (name, seed + 2))
            e.line("end;")

        elif shape == "var-param-alias":
            e.line("procedure DvlOptBump%s(var A, B: Integer);" % tag)
            e.line("begin")
            e.line("  A := A + 1;")
            e.line("  B := B * 2;")
            e.line("  A := A + B;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  X: Integer;")
            e.line("begin")
            e.line("  X := %d;" % seed)
            e.line("  { the same variable passed twice: the callee cannot keep "
                   "either parameter in a register across the other's write }")
            e.line("  DvlOptBump%s(X, X);" % tag)
            e.line("  DevilCheckU('%s-value', UInt64(Cardinal(X)), %d);"
                   % (name, ((seed + 1) * 2) + ((seed + 1) * 2)))
            e.line("end;")

        elif shape == "field-alias":
            e.line("type")
            e.line("  TDvlPair%s = record" % tag)
            e.line("    First, Second: Integer;")
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlPair%s;" % tag)
            e.line("  P: PInteger;")
            e.line("begin")
            e.line("  R.First := %d;" % seed)
            e.line("  R.Second := 0;")
            e.line("  P := @R.Second;")
            e.line("  { a pointer into the record reaches the same storage the "
                   "field name does }")
            e.line("  P^ := R.First + 5;")
            e.line("  DevilCheckU('%s-second', UInt64(Cardinal(R.Second)), %d);"
                   % (name, seed + 5))
            e.line("  R.Second := R.Second + 1;")
            e.line("  DevilCheckU('%s-through-pointer', UInt64(Cardinal(P^)), %d);"
                   % (name, seed + 6))
            e.line("end;")

        elif shape == "type-punned-alias":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Value: Cardinal;")
            e.line("  Bytes: PByte;")
            e.line("begin")
            e.line("  Value := 0;")
            e.line("  Bytes := PByte(@Value);")
            e.line("  { the same storage seen through a different pointer type }")
            e.line("  Bytes^ := %d;" % (seed % 256))
            e.line("  DevilCheckU('%s-low-byte', UInt64(Value and $FF), %d);"
                   % (name, seed % 256))
            e.line("  Value := Value or $0100;")
            e.line("  DevilCheckU('%s-byte-after-write', UInt64(Bytes^), %d);"
                   % (name, seed % 256))
            e.line("end;")

        elif shape == "loop-invariant-mutated":
            rounds = rng.randrange(3, 7)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Limit, Total: Integer;")
            e.line("  P: PInteger;")
            e.line("begin")
            e.line("  Limit := %d;" % rounds)
            e.line("  Total := 0;")
            e.line("  P := @Limit;")
            e.line("  { the bound looks invariant but the body writes to it "
                   "through a pointer, so it cannot be hoisted }")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("  begin")
            e.line("    Total := Total + Limit;")
            e.line("    P^ := Limit + 1;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-total', UInt64(Cardinal(Total)), %d);"
                   % (name, sum(rounds + k for k in range(rounds))))
            e.line("  DevilCheckU('%s-limit', UInt64(Cardinal(Limit)), %d);"
                   % (name, rounds * 2))
            e.line("end;")

        elif shape == "side-effect-in-condition":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Calls, Value: Integer;")
            e.line()
            e.line("  function Step: Boolean;")
            e.line("  begin")
            e.line("    Inc(Calls);")
            e.line("    Result := Calls < 3;")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  Calls := 0;")
            e.line("  Value := 0;")
            e.line("  { the call is the point of the condition, so it must run "
                   "exactly as many times as the loop iterates }")
            e.line("  while Step do")
            e.line("    Inc(Value);")
            e.line("  DevilCheckU('%s-calls', UInt64(Cardinal(Calls)), 3);" % name)
            e.line("  DevilCheckU('%s-value', UInt64(Cardinal(Value)), 2);" % name)
            e.line("end;")

        elif shape == "dead-store-through-pointer":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Slot: Integer;")
            e.line("  P: PInteger;")
            e.line()
            e.line("  procedure Store(Target: PInteger; Value: Integer);")
            e.line("  begin")
            e.line("    Target^ := Value;")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  Slot := 0;")
            e.line("  P := @Slot;")
            e.line("  { the write looks unused inside the callee, but the "
                   "caller reads the same storage afterwards }")
            e.line("  Store(P, %d);" % seed)
            e.line("  DevilCheckU('%s-stored', UInt64(Cardinal(Slot)), %d);"
                   % (name, seed))
            e.line("end;")

        elif shape == "call-not-hoisted":
            rounds = rng.randrange(2, 5)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Counter: Integer;")
            e.line()
            e.line("  function Next: Integer;")
            e.line("  begin")
            e.line("    Inc(Counter);")
            e.line("    Result := Counter;")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  Counter := 0;")
            e.line("  { same call text, different value each time: hoisting it "
                   "out of the loop would be wrong }")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("    DevilNote('%s-step', UInt64(Cardinal(Next)));" % name)
            e.line("  DevilCheckU('%s-count', UInt64(Cardinal(Counter)), %d);"
                   % (name, rounds))
            e.line("end;")

        elif shape == "aliased-array-element":
            width = rng.randrange(3, 7)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Data: array[0..%d] of Integer;" % (width - 1))
            e.line("  P: PInteger;")
            e.line("begin")
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    Data[I] := I;")
            e.line("  P := @Data[1];")
            e.line("  { pointer and index name the same element }")
            e.line("  P^ := %d;" % seed)
            e.line("  DevilCheckU('%s-by-index', UInt64(Cardinal(Data[1])), %d);"
                   % (name, seed))
            e.line("  Inc(P);")
            e.line("  DevilCheckU('%s-next', UInt64(Cardinal(P^)), 2);" % name)
            e.line("  Data[2] := %d;" % (seed + 1))
            e.line("  DevilCheckU('%s-reload', UInt64(Cardinal(P^)), %d);"
                   % (name, seed + 1))
            e.line("end;")

        elif shape == "self-assign-through-pointer":
            e.line("type")
            e.line("  TDvlTriple%s = record" % tag)
            e.line("    A, B, C: Integer;")
            e.line("  end;")
            e.line("  PDvlTriple%s = ^TDvlTriple%s;" % (tag, tag))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlTriple%s;" % tag)
            e.line("  P: PDvlTriple%s;" % tag)
            e.line("begin")
            e.line("  R.A := %d;" % seed)
            e.line("  R.B := 0;")
            e.line("  R.C := 0;")
            e.line("  P := @R;")
            e.line("  { assigning a record to itself through a pointer must "
                   "leave every field intact }")
            e.line("  P^ := R;")
            e.line("  DevilCheckU('%s-a', UInt64(Cardinal(R.A)), %d);" % (name, seed))
            e.line("  R := P^;")
            e.line("  DevilCheckU('%s-a-again', UInt64(Cardinal(R.A)), %d);"
                   % (name, seed))
            e.line("end;")

        elif shape == "global-touched-by-call":
            e.line("var")
            e.line("  DvlGlobal%s: Integer;" % tag)
            e.line()
            e.line("procedure DvlOptTouch%s;" % tag)
            e.line("begin")
            e.line("  DvlGlobal%s := DvlGlobal%s + 1;" % (tag, tag))
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Before, After: Integer;")
            e.line("begin")
            e.line("  DvlGlobal%s := %d;" % (tag, seed))
            e.line("  Before := DvlGlobal%s;" % tag)
            e.line("  { the global cannot stay in a register across a call that "
                   "may write it }")
            e.line("  DvlOptTouch%s;" % tag)
            e.line("  After := DvlGlobal%s;" % tag)
            e.line("  DevilCheckU('%s-before', UInt64(Cardinal(Before)), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-after', UInt64(Cardinal(After)), %d);"
                   % (name, seed + 1))
            e.line("end;")

        elif shape == "reload-after-call":
            e.line("type")
            e.line("  TDvlCell%s = class" % tag)
            e.line("  public")
            e.line("    Value: Integer;")
            e.line("    procedure Bump;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlCell%s.Bump;" % tag)
            e.line("begin")
            e.line("  Value := Value + 1;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Cell: TDvlCell%s;" % tag)
            e.line("  First, Second: Integer;")
            e.line("begin")
            e.line("  Cell := TDvlCell%s.Create;" % tag)
            e.line("  try")
            e.line("    Cell.Value := %d;" % seed)
            e.line("    First := Cell.Value;")
            e.line("    Cell.Bump;")
            e.line("    { the field must be read again: the method wrote it }")
            e.line("    Second := Cell.Value;")
            e.line("    DevilCheckU('%s-first', UInt64(Cardinal(First)), %d);"
                   % (name, seed))
            e.line("    DevilCheckU('%s-second', UInt64(Cardinal(Second)), %d);"
                   % (name, seed + 1))
            e.line("  finally")
            e.line("    Cell.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "cse-with-side-effect":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Calls: Integer;")
            e.line("  A, B: Integer;")
            e.line()
            e.line("  function Value: Integer;")
            e.line("  begin")
            e.line("    Inc(Calls);")
            e.line("    Result := Calls;")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  Calls := 0;")
            e.line("  { identical text, two calls: the second is not a copy of "
                   "the first }")
            e.line("  A := Value;")
            e.line("  B := Value;")
            e.line("  { and again inside a single expression, where a common "
                   "subexpression pass is tempted to keep only one }")
            e.line("  Calls := 0;")
            e.line("  A := Value + Value;")
            e.line("  DevilCheckU('%s-expression-calls', "
                   "UInt64(Cardinal(Calls)), 2);" % name)
            e.line("  DevilNoteLoose('%s-expression-total', UInt64(Cardinal(A)));" % name)
            e.line("  Calls := 0;")
            e.line("  A := Value;")
            e.line("  B := Value;")
            e.line("  DevilCheckU('%s-first', UInt64(Cardinal(A)), 1);" % name)
            e.line("  DevilCheckU('%s-second', UInt64(Cardinal(B)), 2);" % name)
            e.line("  DevilCheckU('%s-calls', UInt64(Cardinal(Calls)), 2);" % name)
            e.line("end;")

        elif shape == "loop-exit-value":
            rounds = rng.randrange(3, 8)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Last: Integer;")
            e.line("begin")
            e.line("  Last := -1;")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("    Last := I;")
            e.line("  { the value left by the last iteration survives the loop }")
            e.line("  DevilCheckU('%s-last', UInt64(Cardinal(Last)), %d);"
                   % (name, rounds))
            e.line("  Last := -1;")
            e.line("  var J := %d;" % rounds)
            e.line("  while J > 0 do")
            e.line("  begin")
            e.line("    Last := J;")
            e.line("    Dec(J);")
            e.line("  end;")
            e.line("  DevilCheckU('%s-while', UInt64(Cardinal(Last)), 1);" % name)
            e.line("end;")

        else:   # aliased-record-copy
            e.line("type")
            e.line("  TDvlBuf%s = record" % tag)
            e.line("    Items: array[0..3] of Integer;")
            e.line("  end;")
            e.line("  PDvlBuf%s = ^TDvlBuf%s;" % (tag, tag))
            e.line()
            e.line("procedure DvlOptCopy%s(Source, Target: PDvlBuf%s);" % (tag, tag))
            e.line("begin")
            e.line("  Target^ := Source^;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Buffer: TDvlBuf%s;" % tag)
            e.line("begin")
            e.line("  for var I := 0 to 3 do")
            e.line("    Buffer.Items[I] := I + %d;" % seed)
            e.line("  { source and target are the same object: the copy must "
                   "not corrupt what it reads }")
            e.line("  DvlOptCopy%s(@Buffer, @Buffer);" % tag)
            e.line("  DevilCheckU('%s-first', UInt64(Cardinal(Buffer.Items[0])), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-last', UInt64(Cardinal(Buffer.Items[3])), %d);"
                   % (name, seed + 3))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="opt",
                                  detail={"shape": shape, "seed": seed}))

    emit_runner(e, "Opt", calls)
    return records


# The Win64 ABI assigns registers by position, not by kind: the third argument
# goes in the third slot whether it is an integer or a float, and a record
# wider than eight bytes travels by reference behind the caller's back.  Mixing
# kinds, crossing the fourth position and returning aggregates is where a
# calling sequence quietly loses an argument - the callee reads a register that
# was never written.
#
# Each form recomputes a sum inside the callee from every parameter it got, so
# a lost or shifted argument shows up as a wrong total rather than as a crash.
CALL_SHAPES = ("many-integers", "mixed-int-float", "float-heavy",
               "record-by-value", "wide-record-by-value", "record-result",
               "var-out-const", "open-array", "method-pointer",
               "nested-callback", "stdcall-convention", "cdecl-convention",
               "int64-and-pointer", "small-types-widened", "result-by-position")


def layer_call(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Calling sequence: every argument arrives, in its own slot."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-call-%05d" % index
        proc = "DvlCall%05d" % index
        tag = "%05d" % index
        shape = rng.choice(CALL_SHAPES)

        if shape in ("many-integers", "stdcall-convention", "cdecl-convention"):
            width = rng.randrange(5, 12)
            convention = {"many-integers": "",
                          "stdcall-convention": "; stdcall",
                          "cdecl-convention": "; cdecl"}[shape]
            params = "; ".join("P%d: Integer" % k for k in range(width))
            body = " + ".join("P%d * %d" % (k, k + 1) for k in range(width))
            args = ", ".join(str(k + 1) for k in range(width))
            expected = sum((k + 1) * (k + 1) for k in range(width))
            e.line("function DvlCallSum%s(%s): Integer%s;" % (tag, params, convention))
            e.line("begin")
            e.line("  Result := %s;" % body)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { past the fourth position arguments travel on the stack; "
                   "each one is weighted so a shift changes the total }")
            e.line("  DevilCheckU('%s-sum', UInt64(Cardinal(DvlCallSum%s(%s))), %d);"
                   % (name, tag, args, expected))
            e.line("end;")

        elif shape == "mixed-int-float":
            e.line("function DvlCallMix%s(A: Integer; B: Double; C: Integer; "
                   "D: Double; E: Integer; F: Double): Integer;" % tag)
            e.line("begin")
            e.line("  Result := A + Trunc(B) * 10 + C * 100 + Trunc(D) * 1000 + "
                   "E * 10000 + Trunc(F) * 100000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { integer and float arguments share positions: the second "
                   "float belongs in the fourth slot, not the second }")
            e.line("  DevilCheckU('%s-mixed', "
                   "UInt64(Cardinal(DvlCallMix%s(1, 2, 3, 4, 5, 6))), %d);"
                   % (name, tag, 1 + 2 * 10 + 3 * 100 + 4 * 1000 + 5 * 10000
                      + 6 * 100000))
            e.line("end;")

        elif shape == "float-heavy":
            e.line("function DvlCallFloats%s(A, B, C, D, E: Double): Integer;" % tag)
            e.line("begin")
            e.line("  Result := Trunc(A) + Trunc(B) * 10 + Trunc(C) * 100 + "
                   "Trunc(D) * 1000 + Trunc(E) * 10000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { the fifth float has no register left and goes to the "
                   "stack }")
            e.line("  DevilCheckU('%s-floats', "
                   "UInt64(Cardinal(DvlCallFloats%s(1, 2, 3, 4, 5))), %d);"
                   % (name, tag, 1 + 20 + 300 + 4000 + 50000))
            e.line("end;")

        elif shape == "record-by-value":
            e.line("type")
            e.line("  TDvlSmall%s = record" % tag)
            e.line("    A, B: Integer;")
            e.line("  end;")
            e.line()
            e.line("function DvlCallTakeSmall%s(X: TDvlSmall%s; Y: Integer; "
                   "Z: TDvlSmall%s): Integer;" % (tag, tag, tag))
            e.line("begin")
            e.line("  X.A := X.A + 100;")
            e.line("  Result := X.A + X.B * 10 + Y * 100 + Z.A * 1000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlSmall%s;" % tag)
            e.line("begin")
            e.line("  R.A := 1;")
            e.line("  R.B := 2;")
            e.line("  { an eight-byte record fits a register; the callee's copy "
                   "is its own, so the caller's stays untouched }")
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(Cardinal(DvlCallTakeSmall%s(R, 3, R))), %d);"
                   % (name, tag, 101 + 20 + 300 + 1000))
            e.line("  DevilCheckU('%s-caller-intact', UInt64(Cardinal(R.A)), 1);"
                   % name)
            e.line("end;")

        elif shape == "wide-record-by-value":
            e.line("type")
            e.line("  TDvlCallWide%s = record" % tag)
            e.line("    A, B, C, D, E: Int64;")
            e.line("  end;")
            e.line()
            e.line("function DvlCallTakeWide%s(X: TDvlCallWide%s; Y: Integer): Int64;"
                   % (tag, tag))
            e.line("begin")
            e.line("  X.A := X.A + 1;")
            e.line("  Result := X.A + X.E * 10 + Y * 100;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlCallWide%s;" % tag)
            e.line("begin")
            e.line("  R.A := 1;")
            e.line("  R.B := 2;")
            e.line("  R.C := 3;")
            e.line("  R.D := 4;")
            e.line("  R.E := 5;")
            e.line("  { too wide for a register: the caller passes a hidden copy "
                   "by reference, and the callee still may not touch the "
                   "original }")
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(DvlCallTakeWide%s(R, 7)), %d);"
                   % (name, tag, 2 + 50 + 700))
            e.line("  DevilCheckU('%s-caller-intact', UInt64(R.A), 1);" % name)
            e.line("end;")

        elif shape == "record-result":
            e.line("type")
            e.line("  TDvlOut%s = record" % tag)
            e.line("    A, B, C: Int64;")
            e.line("  end;")
            e.line()
            e.line("function DvlMake%s(Seed: Integer): TDvlOut%s;" % (tag, tag))
            e.line("begin")
            e.line("  Result.A := Seed;")
            e.line("  Result.B := Seed * 2;")
            e.line("  Result.C := Seed * 3;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlOut%s;" % tag)
            e.line("begin")
            e.line("  { a result too wide to return in a register comes back "
                   "through a slot the caller supplies }")
            e.line("  R := DvlMake%s(4);" % tag)
            e.line("  DevilCheckU('%s-a', UInt64(R.A), 4);" % name)
            e.line("  DevilCheckU('%s-c', UInt64(R.C), 12);" % name)
            e.line("  DevilCheckU('%s-nested', UInt64(DvlMake%s(5).B), 10);"
                   % (name, tag))
            e.line("end;")

        elif shape == "var-out-const":
            e.line("procedure DvlCallThree%s(var A: Integer; out B: Integer; "
                   "const C: Integer);" % tag)
            e.line("begin")
            e.line("  B := A + C;")
            e.line("  A := A * 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  X, Y: Integer;")
            e.line("begin")
            e.line("  X := 5;")
            e.line("  Y := 99;")
            e.line("  { var is read and written in place, out is written only, "
                   "const never travels back }")
            e.line("  DvlCallThree%s(X, Y, 3);" % tag)
            e.line("  DevilCheckU('%s-var', UInt64(Cardinal(X)), 10);" % name)
            e.line("  DevilCheckU('%s-out', UInt64(Cardinal(Y)), 8);" % name)
            e.line("end;")

        elif shape == "open-array":
            width = rng.randrange(3, 8)
            e.line("function DvlCallOpen%s(const Items: array of Integer): Integer;"
                   % tag)
            e.line("begin")
            e.line("  Result := Length(Items) * 1000;")
            e.line("  for var I := Low(Items) to High(Items) do")
            e.line("    Result := Result + Items[I];")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Data: array[0..%d] of Integer;" % (width - 1))
            e.line("begin")
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    Data[I] := I + 1;")
            e.line("  { an open array arrives as a pointer plus a high bound, "
                   "and the literal form builds one on the fly }")
            e.line("  DevilCheckU('%s-array', UInt64(Cardinal(DvlCallOpen%s(Data))), %d);"
                   % (name, tag, width * 1000 + sum(range(1, width + 1))))
            e.line("  DevilCheckU('%s-literal', "
                   "UInt64(Cardinal(DvlCallOpen%s([1, 2, 3]))), 3006);" % (name, tag))
            e.line("  DevilCheckU('%s-empty', "
                   "UInt64(Cardinal(DvlCallOpen%s([]))), 0);" % (name, tag))
            e.line("end;")

        elif shape == "method-pointer":
            e.line("type")
            e.line("  TDvlAdder%s = class" % tag)
            e.line("  public")
            e.line("    Base: Integer;")
            e.line("    function Add(X: Integer): Integer;")
            e.line("  end;")
            e.line("  TDvlAddFunc%s = function(X: Integer): Integer of object;" % tag)
            e.line()
            e.line("function TDvlAdder%s.Add(X: Integer): Integer;" % tag)
            e.line("begin")
            e.line("  Result := Base + X;")
            e.line("end;")
            e.line()
            e.line("function DvlCallApply%s(F: TDvlAddFunc%s; X: Integer): Integer;"
                   % (tag, tag))
            e.line("begin")
            e.line("  Result := F(X);")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Obj: TDvlAdder%s;" % tag)
            e.line("  F: TDvlAddFunc%s;" % tag)
            e.line("begin")
            e.line("  Obj := TDvlAdder%s.Create;" % tag)
            e.line("  try")
            e.line("    Obj.Base := 10;")
            e.line("    F := Obj.Add;")
            e.line("    { a method pointer is two words wide: losing the second "
                   "one loses the instance }")
            e.line("    DevilCheckU('%s-direct', UInt64(Cardinal(F(5))), 15);" % name)
            e.line("    DevilCheckU('%s-passed', "
                   "UInt64(Cardinal(DvlCallApply%s(F, 7))), 17);" % (name, tag))
            e.line("  finally")
            e.line("    Obj.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "nested-callback":
            e.line("type")
            e.line("  TDvlCallFn%s = function(X: Integer): Integer;" % tag)
            e.line()
            e.line("function DvlCallDouble%s(X: Integer): Integer;" % tag)
            e.line("begin")
            e.line("  Result := X * 2;")
            e.line("end;")
            e.line()
            e.line("function DvlCallRun%s(F: TDvlCallFn%s; A, B, C, D, E: Integer): Integer;"
                   % (tag, tag))
            e.line("begin")
            e.line("  Result := F(A) + B + C * 10 + D * 100 + E * 1000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { the function pointer occupies the first slot and pushes "
                   "every other argument one position along }")
            e.line("  DevilCheckU('%s-callback', "
                   "UInt64(Cardinal(DvlCallRun%s(DvlCallDouble%s, 1, 2, 3, 4, 5))), %d);"
                   % (name, tag, tag, 2 + 2 + 30 + 400 + 5000))
            e.line("end;")

        elif shape == "int64-and-pointer":
            e.line("function DvlCallWide%s(A: Int64; P: PInteger; B: Int64; "
                   "C: Cardinal): Int64;" % tag)
            e.line("begin")
            e.line("  Result := A + B * 10 + C * 100;")
            e.line("  If P <> nil then")
            e.line("    Result := Result + P^ * 1000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Slot: Integer;")
            e.line("begin")
            e.line("  Slot := 7;")
            e.line("  { sixty-four bit values and pointers share the same slots; "
                   "a narrow value in between must not shift them }")
            e.line("  DevilCheckU('%s-wide', "
                   "UInt64(DvlCallWide%s(1, @Slot, 2, 3)), %d);"
                   % (name, tag, 1 + 20 + 300 + 7000))
            e.line("  DevilCheckU('%s-nil', UInt64(DvlCallWide%s(1, nil, 2, 3)), %d);"
                   % (name, tag, 1 + 20 + 300))
            e.line("end;")

        elif shape == "small-types-widened":
            e.line("function DvlCallNarrow%s(A: Byte; B: ShortInt; C: Word; "
                   "D: SmallInt; E: Byte; F: SmallInt): Integer;" % tag)
            e.line("begin")
            e.line("  Result := A + B * 10 + C * 100 + D * 1000 + E * 10000 + "
                   "F * 100000;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { narrow arguments occupy whole slots; the callee must "
                   "read only its own width, sign included }")
            e.line("  DevilCheckU('%s-narrow', "
                   "UInt64(Cardinal(DvlCallNarrow%s(1, -2, 3, -4, 5, -6))), "
                   "UInt64(Cardinal(%d)));"
                   % (name, tag, 1 - 20 + 300 - 4000 + 50000 - 600000))
            e.line("end;")

        else:   # result-by-position
            e.line("type")
            e.line("  TDvlRes%s = record" % tag)
            e.line("    A, B, C: Int64;")
            e.line("  end;")
            e.line()
            e.line("function DvlCallBuild%s(A: Integer; B: Double; "
                   "C: Integer): TDvlRes%s;" % (tag, tag))
            e.line("begin")
            e.line("  Result.A := A;")
            e.line("  Result.B := Trunc(B);")
            e.line("  Result.C := C;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlRes%s;" % tag)
            e.line("begin")
            e.line("  { the hidden result slot takes the first position, so "
                   "every declared argument moves one along }")
            e.line("  R := DvlCallBuild%s(3, 4, 5);" % tag)
            e.line("  DevilCheckU('%s-a', UInt64(R.A), 3);" % name)
            e.line("  DevilCheckU('%s-b', UInt64(R.B), 4);" % name)
            e.line("  DevilCheckU('%s-c', UInt64(R.C), 5);" % name)
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="call",
                                  detail={"shape": shape}))

    emit_runner(e, "Call", calls)
    return records


# Inlining is a rewrite of the call site, and every rewrite is a chance to lose
# something: who owns a managed result, when a var parameter is written back,
# which copy of a value the body sees, whether a side effect still happens.
# dvl-0017 came out of this area, so the forms here push on the same seam from
# every direction: managed results, aliasing through var parameters, nesting,
# and inline routines that cross a unit boundary.
INL_SHAPES = ("managed-result", "var-parameter", "out-parameter",
              "const-record", "nested-inline", "inline-in-loop",
              "inline-with-exit", "inline-side-effect",
              "inline-var-decl", "inline-method", "inline-generic",
              "inline-aliased-args", "inline-in-finally",
              "inline-result-used-twice", "inline-recursive-candidate")


def emit_inline_exit_unwind_matrix(e: Emitter) -> CaseRecord:
    """Pin the caller/callee unwind boundary, not merely a local Exit."""
    name = "dvl-inl-exit-unwind-matrix"
    e.line("var")
    e.line("  DvlInlExitCallerFinally: Integer;")
    e.line("  DvlInlExitInnerFinally: Integer;")
    e.line()
    e.line("function DvlInlExitPlain(Value: Integer): Integer; inline;")
    e.line("begin")
    e.line("  If Value = 0 then")
    e.line("    Exit(37);")
    e.line("  Result := Value + 1;")
    e.line("end;")
    e.line()
    e.line("function DvlInlExitNested(Value: Integer): Integer; inline;")
    e.line("begin")
    e.line("  try")
    e.line("    If Value = 0 then")
    e.line("      Exit(41);")
    e.line("    Result := Value + 2;")
    e.line("  finally")
    e.line("    Inc(DvlInlExitInnerFinally);")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("function DvlInlExitCaller(Value: Integer): Integer;")
    e.line("begin")
    e.line("  try")
    e.line("    Result := DvlInlExitPlain(Value) + 5;")
    e.line("  finally")
    e.line("    Inc(DvlInlExitCallerFinally);")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("function DvlInlExitNestedCaller(Value: Integer): Integer;")
    e.line("begin")
    e.line("  try")
    e.line("    Result := DvlInlExitNested(Value) + 5;")
    e.line("  finally")
    e.line("    Inc(DvlInlExitCallerFinally);")
    e.line("  end;")
    e.line("end;")
    e.line()
    e.line("procedure DvlInlExitUnwindMatrix;")
    e.line("begin")
    e.line("  DvlInlExitCallerFinally := 0;")
    e.line("  DvlInlExitInnerFinally := 0;")
    e.line("  DevilCheckU('%s-plain-exit', "
           "UInt64(Cardinal(DvlInlExitCaller(0))), 42);" % name)
    e.line("  DevilCheckU('%s-plain-fallthrough', "
           "UInt64(Cardinal(DvlInlExitCaller(9))), 15);" % name)
    e.line("  DevilCheckU('%s-caller-after-plain', "
           "UInt64(Cardinal(DvlInlExitCallerFinally)), 2);" % name)
    e.line("  DevilCheckU('%s-nested-exit', "
           "UInt64(Cardinal(DvlInlExitNestedCaller(0))), 46);" % name)
    e.line("  DevilCheckU('%s-nested-fallthrough', "
           "UInt64(Cardinal(DvlInlExitNestedCaller(9))), 16);" % name)
    e.line("  DevilCheckU('%s-inner-finally', "
           "UInt64(Cardinal(DvlInlExitInnerFinally)), 2);" % name)
    e.line("  DevilCheckU('%s-caller-finally', "
           "UInt64(Cardinal(DvlInlExitCallerFinally)), 4);" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name=name, layer="inl",
                      detail={"shape": "caller-finally-around-inline-exit"})


def layer_inline(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """Inlining: the call site is rewritten, the meaning is not."""
    records: list[CaseRecord] = [emit_inline_exit_unwind_matrix(e)]
    calls: list[str] = ["DvlInlExitUnwindMatrix"]
    for index in range(start, start + count):
        name = "dvl-inl-%05d" % index
        proc = "DvlInl%05d" % index
        tag = "%05d" % index
        shape = rng.choice(INL_SHAPES)
        seed = index % 30 + 1

        if shape == "managed-result":
            e.line("function DvlInlText%s(N: Integer): AnsiString; inline;" % tag)
            e.line("begin")
            e.line("  Result := AnsiString(IntToStr(N));")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: AnsiString;")
            e.line("begin")
            e.line("  S := DvlInlText%s(%d);" % (tag, seed))
            e.line("  { the hidden result slot belongs to the caller whether the "
                   "body was inlined or not }")
            e.line("  DevilCheckU('%s-length', UInt64(Length(S)), %d);"
                   % (name, len(str(seed))))
            e.line("  DevilCheckU('%s-combined', "
                   "UInt64(Length(DvlInlText%s(%d) + DvlInlText%s(%d))), %d);"
                   % (name, tag, seed, tag, seed, 2 * len(str(seed))))
            e.line("end;")

        elif shape == "var-parameter":
            e.line("procedure DvlInlBump%s(var X: Integer; Delta: Integer); inline;"
                   % tag)
            e.line("begin")
            e.line("  X := X + Delta;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Value: Integer;")
            e.line("  Data: array[0..2] of Integer;")
            e.line("begin")
            e.line("  Value := %d;" % seed)
            e.line("  DvlInlBump%s(Value, 3);" % tag)
            e.line("  DevilCheckU('%s-local', UInt64(Cardinal(Value)), %d);"
                   % (name, seed + 3))
            e.line("  Data[1] := %d;" % seed)
            e.line("  { the reference must still point at the element, not at a "
                   "copy the inliner made }")
            e.line("  DvlInlBump%s(Data[1], 5);" % tag)
            e.line("  DevilCheckU('%s-element', UInt64(Cardinal(Data[1])), %d);"
                   % (name, seed + 5))
            e.line("end;")

        elif shape == "out-parameter":
            e.line("procedure DvlSplit%s(Value: Integer; out Half, Rest: Integer); "
                   "inline;" % tag)
            e.line("begin")
            e.line("  Half := Value div 2;")
            e.line("  Rest := Value - Half;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: Integer;")
            e.line("begin")
            e.line("  A := 999;")
            e.line("  B := 999;")
            e.line("  DvlSplit%s(%d, A, B);" % (tag, seed * 2))
            e.line("  DevilCheckU('%s-half', UInt64(Cardinal(A)), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-rest', UInt64(Cardinal(B)), %d);"
                   % (name, seed))
            e.line("end;")

        elif shape == "const-record":
            e.line("type")
            e.line("  TDvlIn%s = record" % tag)
            e.line("    A, B, C: Int64;")
            e.line("  end;")
            e.line()
            e.line("function DvlRead%s(const R: TDvlIn%s): Int64; inline;"
                   % (tag, tag))
            e.line("begin")
            e.line("  Result := R.A + R.C;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  R: TDvlIn%s;" % tag)
            e.line("begin")
            e.line("  R.A := %d;" % seed)
            e.line("  R.B := 0;")
            e.line("  R.C := 2;")
            e.line("  { a const record travels by reference; inlining must read "
                   "the current fields, not a stale copy }")
            e.line("  DevilCheckU('%s-first', UInt64(DvlRead%s(R)), %d);"
                   % (name, tag, seed + 2))
            e.line("  R.C := 10;")
            e.line("  DevilCheckU('%s-after-write', UInt64(DvlRead%s(R)), %d);"
                   % (name, tag, seed + 10))
            e.line("end;")

        elif shape == "nested-inline":
            e.line("function DvlOne%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  Result := X + 1;")
            e.line("end;")
            e.line()
            e.line("function DvlTwo%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  Result := DvlOne%s(X) * 2;" % tag)
            e.line("end;")
            e.line()
            e.line("function DvlThree%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  Result := DvlTwo%s(X) + DvlOne%s(X);" % (tag, tag))
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { three levels deep, and the same argument used twice at "
                   "the last one }")
            e.line("  DevilCheckU('%s-nested', "
                   "UInt64(Cardinal(DvlThree%s(%d))), %d);"
                   % (name, tag, seed, (seed + 1) * 2 + (seed + 1)))
            e.line("end;")

        elif shape == "inline-in-loop":
            rounds = rng.randrange(3, 8)
            e.line("function DvlWeight%s(I: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  Result := I * I;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  Total := 0;")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("    Total := Total + DvlWeight%s(I);" % tag)
            e.line("  DevilCheckU('%s-total', UInt64(Cardinal(Total)), %d);"
                   % (name, sum(k * k for k in range(1, rounds + 1))))
            e.line("end;")

        elif shape == "inline-with-exit":
            e.line("function DvlPick%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  If X > 10 then")
            e.line("  begin")
            e.line("    Result := 1;")
            e.line("    Exit;")
            e.line("  end;")
            e.line("  Result := 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { Exit inside an inlined body leaves that body, not the "
                   "routine it was pasted into }")
            e.line("  DevilCheckU('%s-high', UInt64(Cardinal(DvlPick%s(50))), 1);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-low', UInt64(Cardinal(DvlPick%s(1))), 2);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-sum', "
                   "UInt64(Cardinal(DvlPick%s(50) + DvlPick%s(1))), 3);"
                   % (name, tag, tag))
            e.line("end;")

        elif shape == "inline-side-effect":
            e.line("var")
            e.line("  DvlInlCalls%s: Integer;" % tag)
            e.line()
            e.line("function DvlCount%s: Integer; inline;" % tag)
            e.line("begin")
            e.line("  Inc(DvlInlCalls%s);" % tag)
            e.line("  Result := DvlInlCalls%s;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: Integer;")
            e.line("begin")
            e.line("  DvlInlCalls%s := 0;" % tag)
            e.line("  A := DvlCount%s;" % tag)
            e.line("  B := DvlCount%s;" % tag)
            e.line("  { two pastes of the same body are still two calls }")
            e.line("  DevilCheckU('%s-first', UInt64(Cardinal(A)), 1);" % name)
            e.line("  DevilCheckU('%s-second', UInt64(Cardinal(B)), 2);" % name)
            e.line("  DevilCheckU('%s-total', "
                   "UInt64(Cardinal(DvlInlCalls%s)), 2);" % (name, tag))
            e.line("end;")

        elif shape == "inline-open-array":
            e.line("function DvlTotal%s(const Items: array of Integer): Integer; "
                   "inline;" % tag)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  for var I := Low(Items) to High(Items) do")
            e.line("    Result := Result + Items[I];")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Data: array[0..3] of Integer;")
            e.line("begin")
            e.line("  for var I := 0 to 3 do")
            e.line("    Data[I] := I + %d;" % seed)
            e.line("  { the pointer and the high bound have to survive the "
                   "rewrite together }")
            e.line("  DevilCheckU('%s-array', "
                   "UInt64(Cardinal(DvlTotal%s(Data))), %d);"
                   % (name, tag, sum(seed + k for k in range(4))))
            e.line("  DevilCheckU('%s-literal', "
                   "UInt64(Cardinal(DvlTotal%s([1, 2, 3]))), 6);" % (name, tag))
            e.line("end;")

        elif shape == "inline-var-decl":
            e.line("function DvlInlLocal%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  var Doubled := X * 2;")
            e.line("  var Shifted := Doubled + 1;")
            e.line("  Result := Shifted;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: Integer;")
            e.line("begin")
            e.line("  { inline variables inside an inlined body must not collide "
                   "when the body is pasted twice }")
            e.line("  A := DvlInlLocal%s(%d);" % (tag, seed))
            e.line("  B := DvlInlLocal%s(%d);" % (tag, seed + 1))
            e.line("  DevilCheckU('%s-first', UInt64(Cardinal(A)), %d);"
                   % (name, seed * 2 + 1))
            e.line("  DevilCheckU('%s-second', UInt64(Cardinal(B)), %d);"
                   % (name, (seed + 1) * 2 + 1))
            e.line("end;")

        elif shape == "inline-method":
            e.line("type")
            e.line("  TDvlAcc%s = class" % tag)
            e.line("  public")
            e.line("    Total: Integer;")
            e.line("    procedure Add(X: Integer); inline;")
            e.line("    function Read: Integer; inline;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlAcc%s.Add(X: Integer);" % tag)
            e.line("begin")
            e.line("  Total := Total + X;")
            e.line("end;")
            e.line()
            e.line("function TDvlAcc%s.Read: Integer;" % tag)
            e.line("begin")
            e.line("  Result := Total;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Acc: TDvlAcc%s;" % tag)
            e.line("begin")
            e.line("  Acc := TDvlAcc%s.Create;" % tag)
            e.line("  try")
            e.line("    { an inlined method still has to find its own instance }")
            e.line("    Acc.Add(%d);" % seed)
            e.line("    Acc.Add(1);")
            e.line("    DevilCheckU('%s-total', UInt64(Cardinal(Acc.Read)), %d);"
                   % (name, seed + 1))
            e.line("  finally")
            e.line("    Acc.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "inline-generic":
            e.line("type")
            e.line("  TDvlPick%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("    function Read: T; inline;")
            e.line("  end;")
            e.line()
            e.line("function TDvlPick%s<T>.Read: T;" % tag)
            e.line("begin")
            e.line("  Result := Value;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  N: TDvlPick%s<Integer>;" % tag)
            e.line("  S: TDvlPick%s<AnsiString>;" % tag)
            e.line("begin")
            e.line("  N.Value := %d;" % seed)
            e.line("  S.Value := AnsiString('abcd');")
            e.line("  { each specialization is inlined on its own terms, and the "
                   "managed one still owns its result }")
            e.line("  DevilCheckU('%s-int', UInt64(Cardinal(N.Read)), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-string', UInt64(Length(S.Read)), 4);" % name)
            e.line("end;")

        elif shape == "inline-aliased-args":
            e.line("procedure DvlInlMix%s(var A, B: Integer); inline;" % tag)
            e.line("begin")
            e.line("  A := A + B;")
            e.line("  B := A - B;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  X, Y: Integer;")
            e.line("begin")
            e.line("  X := %d;" % seed)
            e.line("  Y := 3;")
            e.line("  DvlInlMix%s(X, Y);" % tag)
            e.line("  DevilCheckU('%s-x', UInt64(Cardinal(X)), %d);"
                   % (name, seed + 3))
            e.line("  DevilCheckU('%s-y', UInt64(Cardinal(Y)), %d);" % (name, seed))
            e.line("  X := %d;" % seed)
            e.line("  { the same variable in both slots: the body sees one "
                   "location }")
            e.line("  DvlInlMix%s(X, X);" % tag)
            e.line("  DevilCheckU('%s-aliased', UInt64(Cardinal(X)), 0);" % name)
            e.line("end;")

        elif shape == "inline-in-finally":
            e.line("var")
            e.line("  DvlFinCount%s: Integer;" % tag)
            e.line()
            e.line("procedure DvlMark%s; inline;" % tag)
            e.line("begin")
            e.line("  Inc(DvlFinCount%s);" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  DvlFinCount%s := 0;" % tag)
            e.line("  { the shape behind dvl-0017, with an unmanaged body: it "
                   "must compile and still run once per exit }")
            e.line("  try")
            e.line("    try")
            e.line("      raise Exception.Create('x');")
            e.line("    finally")
            e.line("      DvlMark%s;" % tag)
            e.line("    end;")
            e.line("  except")
            e.line("  end;")
            e.line("  DevilCheckU('%s-count', "
                   "UInt64(Cardinal(DvlFinCount%s)), 1);" % (name, tag))
            e.line("end;")

        elif shape == "inline-result-used-twice":
            e.line("var")
            e.line("  DvlTwiceCalls%s: Integer;" % tag)
            e.line()
            e.line("function DvlInlValue%s: Integer; inline;" % tag)
            e.line("begin")
            e.line("  Inc(DvlTwiceCalls%s);" % tag)
            e.line("  Result := DvlTwiceCalls%s * 10;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  DvlTwiceCalls%s := 0;" % tag)
            e.line("  { both operands are separate calls, evaluated once each }")
            e.line("  Total := DvlInlValue%s + DvlInlValue%s;" % (tag, tag))
            e.line("  { which operand is evaluated first is not fixed, so the "
                   "sum is recorded; the number of calls is not negotiable }")
            e.line("  DevilNoteLoose('%s-total', UInt64(Cardinal(Total)));" % name)
            e.line("  DevilCheckU('%s-calls', "
                   "UInt64(Cardinal(DvlTwiceCalls%s)), 2);" % (name, tag))
            e.line("end;")

        else:   # inline-recursive-candidate
            e.line("function DvlDown%s(X: Integer): Integer; inline;" % tag)
            e.line("begin")
            e.line("  If X <= 0 then")
            e.line("    Result := 0")
            e.line("  else")
            e.line("    Result := X + DvlDown%s(X - 1);" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { marked inline but recursive: the compiler has to decline "
                   "quietly and still compute the right answer }")
            e.line("  DevilCheckU('%s-sum', UInt64(Cardinal(DvlDown%s(%d))), %d);"
                   % (name, tag, seed, seed * (seed + 1) // 2))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="inl",
                                  detail={"shape": shape, "seed": seed}))

    emit_runner(e, "Inl", calls)
    return records


# Dispatch through an interface is already covered; what is not is everything
# around it - who holds the reference, what a cast between interfaces does to
# the count, whether delegation forwards the identity or a copy of it, and when
# the object behind the last reference actually dies.  These are the places a
# leak or a premature free comes from, and neither shows up as a wrong number.
INTF_SHAPES = ("refcount-scope", "cast-between-interfaces", "queryinterface",
               "implements-delegation", "as-operator", "supports-check",
               "interface-in-record", "interface-array", "weak-by-hand",
               "interface-parameter", "interface-result", "same-object-identity",
               "aggregation-lifetime", "interface-in-closure")


def layer_interfaces(e: Emitter, rng: random.Random, count: int,
                     start: int) -> list[CaseRecord]:
    """Interface references: counting, casting, delegating, releasing."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-intf-%05d" % index
        proc = "DvlIntf%05d" % index
        tag = "%05d" % index
        shape = rng.choice(INTF_SHAPES)
        guid_a = "{7A%06X-0000-0000-0000-000000000001}" % (index % 0xFFFFFF)
        guid_b = "{7B%06X-0000-0000-0000-000000000002}" % (index % 0xFFFFFF)

        def declare_pair() -> None:
            e.line("type")
            e.line("  IDvlAlpha%s = interface" % tag)
            e.line("    ['%s']" % guid_a)
            e.line("    function Alpha: Integer;")
            e.line("  end;")
            e.line()
            e.line("  IDvlBeta%s = interface" % tag)
            e.line("    ['%s']" % guid_b)
            e.line("    function Beta: Integer;")
            e.line("  end;")
            e.line()
            e.line("  TDvlBoth%s = class(TInterfacedObject, IDvlAlpha%s, "
                   "IDvlBeta%s)" % (tag, tag, tag))
            e.line("  public")
            e.line("    class var Live: Integer;")
            e.line("    constructor Create;")
            e.line("    destructor Destroy; override;")
            e.line("    function Alpha: Integer;")
            e.line("    function Beta: Integer;")
            e.line("  end;")
            e.line()
            e.line("constructor TDvlBoth%s.Create;" % tag)
            e.line("begin")
            e.line("  inherited Create;")
            e.line("  Inc(Live);")
            e.line("end;")
            e.line()
            e.line("destructor TDvlBoth%s.Destroy;" % tag)
            e.line("begin")
            e.line("  Dec(Live);")
            e.line("  inherited Destroy;")
            e.line("end;")
            e.line()
            e.line("function TDvlBoth%s.Alpha: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("end;")
            e.line()
            e.line("function TDvlBoth%s.Beta: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 2;")
            e.line("end;")
            e.line()

        if shape == "refcount-scope":
            declare_pair()
            e.line("procedure DvlHold%s;" % tag)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("begin")
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  DevilCheckU('%s-inside', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  DvlHold%s;" % tag)
            e.line("  { the last reference leaving scope is what frees the "
                   "object, and it happens before the routine returns }")
            e.line("  DevilCheckU('%s-after', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "cast-between-interfaces":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("  B: IDvlBeta%s;" % tag)
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  B := A as IDvlBeta%s;" % tag)
            e.line("  { two references to one object: releasing one must not "
                   "take the object with it }")
            e.line("  DevilCheckU('%s-alpha', UInt64(Cardinal(A.Alpha)), 1);" % name)
            e.line("  DevilCheckU('%s-beta', UInt64(Cardinal(B.Beta)), 2);" % name)
            e.line("  A := nil;")
            e.line("  DevilCheckU('%s-alive', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  DevilCheckU('%s-still-usable', "
                   "UInt64(Cardinal(B.Beta)), 2);" % name)
            e.line("  B := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "queryinterface":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("  B: IDvlBeta%s;" % tag)
            e.line("  Unknown: IInterface;")
            e.line("  Code: HResult;")
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  Code := A.QueryInterface(IDvlBeta%s, B);" % tag)
            e.line("  { a supported interface answers zero and hands back a "
                   "counted reference }")
            e.line("  DevilCheckU('%s-code', UInt64(Cardinal(Code)), 0);" % name)
            e.line("  DevilCheckU('%s-beta', UInt64(Cardinal(B.Beta)), 2);" % name)
            e.line("  Code := A.QueryInterface(IInterface, Unknown);")
            e.line("  DevilCheckU('%s-unknown', UInt64(Cardinal(Code)), 0);" % name)
            e.line("  A := nil;")
            e.line("  B := nil;")
            e.line("  Unknown := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "implements-delegation":
            e.line("type")
            e.line("  IDvlWork%s = interface" % tag)
            e.line("    ['%s']" % guid_a)
            e.line("    function Work: Integer;")
            e.line("  end;")
            e.line()
            e.line("  TDvlIntfInner%s = class(TInterfacedObject, IDvlWork%s)" % (tag, tag))
            e.line("  public")
            e.line("    function Work: Integer;")
            e.line("  end;")
            e.line()
            e.line("  TDvlIntfOuter%s = class(TInterfacedObject, IDvlWork%s)" % (tag, tag))
            e.line("  private")
            e.line("    FInner: IDvlWork%s;" % tag)
            e.line("  public")
            e.line("    constructor Create;")
            e.line("    property Inner: IDvlWork%s read FInner implements IDvlWork%s;"
                   % (tag, tag))
            e.line("  end;")
            e.line()
            e.line("function TDvlIntfInner%s.Work: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 7;")
            e.line("end;")
            e.line()
            e.line("constructor TDvlIntfOuter%s.Create;" % tag)
            e.line("begin")
            e.line("  inherited Create;")
            e.line("  FInner := TDvlIntfInner%s.Create;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  W: IDvlWork%s;" % tag)
            e.line("begin")
            e.line("  { the outer object declares the interface but hands the "
                   "work to the inner one }")
            e.line("  W := TDvlIntfOuter%s.Create;" % tag)
            e.line("  DevilCheckU('%s-delegated', UInt64(Cardinal(W.Work)), 7);"
                   % name)
            e.line("end;")

        elif shape == "as-operator":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Unknown: IInterface;")
            e.line("  Raised: Integer;")
            e.line("begin")
            e.line("  Unknown := TDvlBoth%s.Create;" % tag)
            e.line("  DevilCheckU('%s-alpha', "
                   "UInt64(Cardinal((Unknown as IDvlAlpha%s).Alpha)), 1);"
                   % (name, tag))
            e.line("  Raised := 0;")
            e.line("  try")
            e.line("    { an unsupported interface is an error, not a nil }")
            e.line("    (Unknown as IDvlBeta%s).Beta;" % tag)
            e.line("  except")
            e.line("    Raised := 1;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-supported', UInt64(Cardinal(Raised)), 0);"
                   % name)
            e.line("end;")

        elif shape == "supports-check":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("  B: IDvlBeta%s;" % tag)
            e.line("begin")
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  { Supports answers about the object behind the reference }")
            e.line("  DevilCheckU('%s-beta', "
                   "UInt64(Ord(Supports(A, IDvlBeta%s, B))), 1);" % (name, tag))
            e.line("  DevilCheckU('%s-value', UInt64(Cardinal(B.Beta)), 2);" % name)
            e.line("  DevilCheckU('%s-nil-source', "
                   "UInt64(Ord(Supports(IDvlAlpha%s(nil), IDvlBeta%s, B))), 0);"
                   % (name, tag, tag))
            e.line("end;")

        elif shape == "interface-in-record":
            declare_pair()
            e.line("type")
            e.line("  TDvlHolder%s = record" % tag)
            e.line("    Ref: IDvlAlpha%s;" % tag)
            e.line("    Tag: Integer;")
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Outer: TDvlHolder%s;" % tag)
            e.line()
            e.line("  procedure Fill;")
            e.line("  var")
            e.line("    Local: TDvlHolder%s;" % tag)
            e.line("  begin")
            e.line("    Local.Ref := TDvlBoth%s.Create;" % tag)
            e.line("    Local.Tag := 5;")
            e.line("    { copying the record copies the reference and raises the "
                   "count with it }")
            e.line("    Outer := Local;")
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  Fill;")
            e.line("  DevilCheckU('%s-survived', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  DevilCheckU('%s-tag', UInt64(Cardinal(Outer.Tag)), 5);" % name)
            e.line("  Outer.Ref := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "interface-array":
            declare_pair()
            width = rng.randrange(2, 5)
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Items: System.TArray<IDvlAlpha%s>;" % tag)
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  SetLength(Items, %d);" % width)
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    Items[I] := TDvlBoth%s.Create;" % tag)
            e.line("  DevilCheckU('%s-filled', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), %d);"
                   % (name, tag, width))
            e.line("  { shrinking the array releases exactly the elements it "
                   "dropped }")
            e.line("  SetLength(Items, 1);")
            e.line("  DevilCheckU('%s-shrunk', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  Items := nil;")
            e.line("  DevilCheckU('%s-cleared', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "weak-by-hand":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Strong: IDvlAlpha%s;" % tag)
            e.line("  Raw: Pointer;")
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  Strong := TDvlBoth%s.Create;" % tag)
            e.line("  { a pointer copy is deliberately uncounted: the object "
                   "stays alive only as long as the counted reference does }")
            e.line("  Raw := Pointer(Strong);")
            e.line("  DevilCheckU('%s-same', "
                   "UInt64(Ord(Raw = Pointer(Strong))), 1);" % name)
            e.line("  DevilCheckU('%s-alive', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  Strong := nil;")
            e.line("  DevilCheckU('%s-gone', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "interface-parameter":
            declare_pair()
            e.line("function DvlUse%s(const A: IDvlAlpha%s; B: IDvlAlpha%s): Integer;"
                   % (tag, tag, tag))
            e.line("begin")
            e.line("  Result := A.Alpha + B.Alpha;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  { a const parameter does not touch the count, a value "
                   "parameter does - and both must leave the object alive }")
            e.line("  DevilCheckU('%s-sum', "
                   "UInt64(Cardinal(DvlUse%s(A, A))), 2);" % (name, tag))
            e.line("  DevilCheckU('%s-alive', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  A := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        elif shape == "interface-result":
            declare_pair()
            e.line("function DvlIntfMake%s: IDvlAlpha%s;" % (tag, tag))
            e.line("begin")
            e.line("  Result := TDvlBoth%s.Create;" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(Cardinal(DvlIntfMake%s.Alpha)), 1);" % (name, tag))
            e.line("  { when exactly the hidden result temporary dies is not "
                   "fixed by the language: Delphi may hold it to the end of the "
                   "scope, we release it at the end of the statement. Recorded, "
                   "not asserted - see KNOWN_ISSUES.md }")
            e.line("  DevilNote('%s-temporary-gone', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)));" % (name, tag))
            e.line("  var Kept := DvlIntfMake%s;" % tag)
            e.line("  DevilNote('%s-kept', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)));" % (name, tag))
            e.line("  Kept := nil;")
            e.line("  DevilNote('%s-dropped', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)));" % (name, tag))
            e.line("end;")

        elif shape == "same-object-identity":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: IDvlAlpha%s;" % tag)
            e.line("  B: IDvlBeta%s;" % tag)
            e.line("  U1, U2: IInterface;")
            e.line("begin")
            e.line("  A := TDvlBoth%s.Create;" % tag)
            e.line("  B := A as IDvlBeta%s;" % tag)
            e.line("  U1 := A as IInterface;")
            e.line("  U2 := B as IInterface;")
            e.line("  { different interfaces of one object answer with the same "
                   "identity when asked as IInterface }")
            e.line("  DevilCheckU('%s-identity', "
                   "UInt64(Ord(Pointer(U1) = Pointer(U2))), 1);" % name)
            e.line("  DevilCheckU('%s-distinct-slots', "
                   "UInt64(Ord(Pointer(A) = Pointer(B))), 0);" % name)
            e.line("end;")

        elif shape == "aggregation-lifetime":
            declare_pair()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Outer: IDvlAlpha%s;" % tag)
            e.line()
            e.line("  procedure Build;")
            e.line("  var")
            e.line("    Inner: IDvlBeta%s;" % tag)
            e.line("  begin")
            e.line("    Outer := TDvlBoth%s.Create;" % tag)
            e.line("    Inner := Outer as IDvlBeta%s;" % tag)
            e.line("    DevilCheckU('%s-both-held', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  end;")
            e.line()
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  Build;")
            e.line("  { the inner reference went away with its scope, the outer "
                   "one keeps the object }")
            e.line("  DevilCheckU('%s-kept', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 1);" % (name, tag))
            e.line("  Outer := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("end;")

        else:   # interface-in-closure
            declare_pair()
            e.line("type")
            e.line("  TDvlRun%s = reference to procedure;" % tag)
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Ref: IDvlAlpha%s;" % tag)
            e.line("  Run: TDvlRun%s;" % tag)
            e.line("  Seen: Integer;")
            e.line("begin")
            e.line("  TDvlBoth%s.Live := 0;" % tag)
            e.line("  Seen := 0;")
            e.line("  Ref := TDvlBoth%s.Create;" % tag)
            e.line("  Run := procedure")
            e.line("    begin")
            e.line("      Seen := Ref.Alpha;")
            e.line("    end;")
            e.line("  Run();")
            e.line("  DevilCheckU('%s-seen', UInt64(Cardinal(Seen)), 1);" % name)
            e.line("  { the closure captured the variable, so clearing it there "
                   "clears the only reference }")
            e.line("  Ref := nil;")
            e.line("  DevilCheckU('%s-released', "
                   "UInt64(Cardinal(TDvlBoth%s.Live)), 0);" % (name, tag))
            e.line("  Run := nil;")
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="intf",
                                  detail={"shape": shape}))

    emit_runner(e, "Intf", calls)
    return records


# A dynamic array is a reference with a header in front of it, and almost every
# defect here comes from forgetting that: two names sharing one buffer until
# someone writes, a nested level that was copied shallowly, a length change that
# moved the data, an element released too early or not at all.  The `arr` layer
# covers indexing and the simple cases; this one goes after the reference
# semantics of nested levels and the operations that reshape a buffer in place.
DYN_SHAPES = ("nested-share", "nested-copy", "copy-detaches", "insert-delete",
              "setlength-preserves", "shrink-releases", "concat-operator",
              "array-of-array-of-managed", "assign-then-write",
              "high-low-empty", "vararray-basics", "vararray-bounds",
              "dynarray-as-parameter", "dynarray-result", "unique-on-write")


def layer_dynamic(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Dynamic arrays: who shares a buffer, and when the sharing ends."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-dyn-%05d" % index
        proc = "DvlDyn%05d" % index
        tag = "%05d" % index
        shape = rng.choice(DYN_SHAPES)
        width = rng.randrange(3, 7)
        seed = index % 50 + 1

        if shape == "nested-share":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: System.TArray<System.TArray<Integer>>;")
            e.line("begin")
            e.line("  SetLength(A, 2, 3);")
            e.line("  A[0][0] := %d;" % seed)
            e.line("  B := A;")
            e.line("  { assignment shares the outer buffer, and the inner rows "
                   "are shared through it }")
            e.line("  B[0][0] := B[0][0] + 1;")
            e.line("  DevilCheckU('%s-shared', UInt64(Cardinal(A[0][0])), %d);"
                   % (name, seed + 1))
            e.line("  DevilCheckU('%s-same-row', "
                   "UInt64(Ord(Pointer(A[0]) = Pointer(B[0]))), 1);" % name)
            e.line("end;")

        elif shape == "nested-copy":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: System.TArray<System.TArray<Integer>>;")
            e.line("begin")
            e.line("  SetLength(A, 2, 2);")
            e.line("  A[0][0] := %d;" % seed)
            e.line("  B := Copy(A);")
            e.line("  { Copy duplicates the outer level only: the rows stay "
                   "shared }")
            e.line("  DevilCheckU('%s-outer-detached', "
                   "UInt64(Ord(Pointer(A) = Pointer(B))), 0);" % name)
            e.line("  DevilCheckU('%s-inner-shared', "
                   "UInt64(Ord(Pointer(A[0]) = Pointer(B[0]))), 1);" % name)
            e.line("  B[0][0] := B[0][0] + 1;")
            e.line("  DevilCheckU('%s-write-visible', "
                   "UInt64(Cardinal(A[0][0])), %d);" % (name, seed + 1))
            e.line("end;")

        elif shape == "copy-detaches":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: System.TArray<Integer>;")
            e.line("begin")
            e.line("  SetLength(A, %d);" % width)
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    A[I] := I + %d;" % seed)
            e.line("  B := Copy(A, 1, 2);")
            e.line("  { a slice is a new buffer, and writing to it leaves the "
                   "source alone }")
            e.line("  DevilCheckU('%s-length', UInt64(Cardinal(Length(B))), 2);"
                   % name)
            e.line("  DevilCheckU('%s-first', UInt64(Cardinal(B[0])), %d);"
                   % (name, seed + 1))
            e.line("  B[0] := 0;")
            e.line("  DevilCheckU('%s-source-intact', "
                   "UInt64(Cardinal(A[1])), %d);" % (name, seed + 1))
            e.line("end;")

        elif shape == "insert-delete":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<Integer>;")
            e.line("begin")
            e.line("  SetLength(A, %d);" % width)
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    A[I] := I;")
            e.line("  Insert(99, A, 1);")
            e.line("  DevilCheckU('%s-after-insert', "
                   "UInt64(Cardinal(Length(A))), %d);" % (name, width + 1))
            e.line("  DevilCheckU('%s-inserted', UInt64(Cardinal(A[1])), 99);"
                   % name)
            e.line("  DevilCheckU('%s-shifted', UInt64(Cardinal(A[2])), 1);"
                   % name)
            e.line("  Delete(A, 1, 1);")
            e.line("  { deleting the inserted element restores the original "
                   "sequence }")
            e.line("  DevilCheckU('%s-after-delete', "
                   "UInt64(Cardinal(Length(A))), %d);" % (name, width))
            e.line("  DevilCheckU('%s-restored', UInt64(Cardinal(A[1])), 1);"
                   % name)
            e.line("end;")

        elif shape == "setlength-preserves":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<AnsiString>;")
            e.line("begin")
            e.line("  SetLength(A, 2);")
            e.line("  A[0] := AnsiString('first');")
            e.line("  A[1] := AnsiString('second');")
            e.line("  SetLength(A, %d);" % (width + 2))
            e.line("  { growing keeps what was there and zeroes what is new }")
            e.line("  DevilCheckU('%s-kept', UInt64(Length(A[0])), 5);" % name)
            e.line("  DevilCheckU('%s-kept-second', UInt64(Length(A[1])), 6);"
                   % name)
            e.line("  DevilCheckU('%s-new-empty', UInt64(Length(A[2])), 0);" % name)
            e.line("end;")

        elif shape == "shrink-releases":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<IInterface>;")
            e.line("  Before: Integer;")
            e.line("begin")
            e.line("  Before := TDvlTagged.Alive;")
            e.line("  SetLength(A, %d);" % width)
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    A[I] := TDvlTagged.Create('d');")
            e.line("  DevilCheckU('%s-filled', "
                   "UInt64(Cardinal(TDvlTagged.Alive - Before)), %d);"
                   % (name, width))
            e.line("  SetLength(A, 1);")
            e.line("  { shrinking releases exactly the elements it dropped }")
            e.line("  DevilCheckU('%s-shrunk', "
                   "UInt64(Cardinal(TDvlTagged.Alive - Before)), 1);" % name)
            e.line("  A := nil;")
            e.line("  DevilCheckU('%s-cleared', "
                   "UInt64(Cardinal(TDvlTagged.Alive - Before)), 0);" % name)
            e.line("end;")

        elif shape == "concat-operator":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B, C: System.TArray<Integer>;")
            e.line("begin")
            e.line("  A := [1, 2];")
            e.line("  B := [3, 4, 5];")
            e.line("  C := A + B;")
            e.line("  { concatenation builds a third buffer and leaves both "
                   "sources as they were }")
            e.line("  DevilCheckU('%s-length', UInt64(Cardinal(Length(C))), 5);"
                   % name)
            e.line("  DevilCheckU('%s-join', UInt64(Cardinal(C[2])), 3);" % name)
            e.line("  C[0] := 99;")
            e.line("  DevilCheckU('%s-source-intact', UInt64(Cardinal(A[0])), 1);"
                   % name)
            e.line("end;")

        elif shape == "array-of-array-of-managed":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Grid: System.TArray<System.TArray<AnsiString>>;")
            e.line("  Total: Integer;")
            e.line("begin")
            e.line("  SetLength(Grid, 2, 2);")
            e.line("  Grid[0][0] := AnsiString('ab');")
            e.line("  Grid[1][1] := AnsiString('cde');")
            e.line("  Total := 0;")
            e.line("  for var Row in Grid do")
            e.line("    for var Cell in Row do")
            e.line("      Total := Total + Length(Cell);")
            e.line("  { a rectangular allocation initializes every managed cell }")
            e.line("  DevilCheckU('%s-total', UInt64(Cardinal(Total)), 5);" % name)
            e.line("  Grid := nil;")
            e.line("  DevilCheckU('%s-cleared', UInt64(Cardinal(Length(Grid))), 0);"
                   % name)
            e.line("end;")

        elif shape == "assign-then-write":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: System.TArray<Integer>;")
            e.line("begin")
            e.line("  A := [%d, %d];" % (seed, seed + 1))
            e.line("  B := A;")
            e.line("  { a dynamic array is a reference: assignment shares, and "
                   "there is no copy on write }")
            e.line("  B[0] := 0;")
            e.line("  DevilCheckU('%s-shared', UInt64(Cardinal(A[0])), 0);" % name)
            e.line("  SetLength(B, 3);")
            e.line("  B[0] := %d;" % seed)
            e.line("  { SetLength on a shared buffer detaches it }")
            e.line("  DevilCheckU('%s-detached', UInt64(Cardinal(A[0])), 0);" % name)
            e.line("end;")

        elif shape == "high-low-empty":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<Integer>;")
            e.line("  Steps: Integer;")
            e.line("begin")
            e.line("  A := nil;")
            e.line("  DevilCheckU('%s-length', UInt64(Cardinal(Length(A))), 0);"
                   % name)
            e.line("  DevilCheckU('%s-low', UInt64(Cardinal(Low(A))), 0);" % name)
            e.line("  { High of an empty array is minus one, so the natural loop "
                   "runs zero times instead of wrapping }")
            e.line("  DevilCheckU('%s-high', "
                   "UInt64(Cardinal(High(A))), UInt64(Cardinal(-1)));" % name)
            e.line("  Steps := 0;")
            e.line("  for var I := Low(A) to High(A) do")
            e.line("    Inc(Steps);")
            e.line("  DevilCheckU('%s-steps', UInt64(Cardinal(Steps)), 0);" % name)
            e.line("end;")

        elif shape == "vararray-basics":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  V: Variant;")
            e.line("begin")
            e.line("  V := VarArrayCreate([0, %d], varInteger);" % (width - 1))
            e.line("  for var I := 0 to %d do" % (width - 1))
            e.line("    V[I] := I + %d;" % seed)
            e.line("  { a Variant array carries its own bounds and element type }")
            e.line("  DevilCheckU('%s-is-array', UInt64(Ord(VarIsArray(V))), 1);"
                   % name)
            e.line("  DevilCheckU('%s-low', "
                   "UInt64(Cardinal(VarArrayLowBound(V, 1))), 0);" % name)
            e.line("  DevilCheckU('%s-high', "
                   "UInt64(Cardinal(VarArrayHighBound(V, 1))), %d);"
                   % (name, width - 1))
            e.line("  DevilCheckU('%s-element', "
                   "UInt64(Cardinal(Integer(V[1]))), %d);" % (name, seed + 1))
            e.line("end;")

        elif shape == "vararray-bounds":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  V: Variant;")
            e.line("  Raised: Integer;")
            e.line("begin")
            e.line("  V := VarArrayCreate([2, %d], varInteger);" % (width + 2))
            e.line("  V[2] := %d;" % seed)
            e.line("  { the low bound is where it was asked to be, not zero }")
            e.line("  DevilCheckU('%s-low', "
                   "UInt64(Cardinal(VarArrayLowBound(V, 1))), 2);" % name)
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(Cardinal(Integer(V[2]))), %d);" % (name, seed))
            e.line("  Raised := 0;")
            e.line("  try")
            e.line("    V[0] := 1;")
            e.line("  except")
            e.line("    Raised := 1;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-out-of-bounds', "
                   "UInt64(Cardinal(Raised)), 1);" % name)
            e.line("end;")

        elif shape == "dynarray-as-parameter":
            e.line("procedure DvlDynFill%s(A: System.TArray<Integer>; Value: Integer);" % tag)
            e.line("begin")
            e.line("  If Length(A) > 0 then")
            e.line("    A[0] := Value;")
            e.line("end;")
            e.line()
            e.line("procedure DvlDynReplace%s(var A: System.TArray<Integer>);" % tag)
            e.line("begin")
            e.line("  A := [7, 8];")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<Integer>;")
            e.line("begin")
            e.line("  A := [%d, %d];" % (seed, seed + 1))
            e.line("  { by value the reference is copied, so writing an element "
                   "still reaches the caller's buffer }")
            e.line("  DvlDynFill%s(A, 0);" % tag)
            e.line("  DevilCheckU('%s-element', UInt64(Cardinal(A[0])), 0);" % name)
            e.line("  { by reference the variable itself can be replaced }")
            e.line("  DvlDynReplace%s(A);" % tag)
            e.line("  DevilCheckU('%s-replaced', UInt64(Cardinal(A[0])), 7);" % name)
            e.line("  DevilCheckU('%s-length', UInt64(Cardinal(Length(A))), 2);"
                   % name)
            e.line("end;")

        elif shape == "dynarray-result":
            e.line("function DvlDynBuild%s(N: Integer): System.TArray<Integer>;" % tag)
            e.line("begin")
            e.line("  SetLength(Result, N);")
            e.line("  for var I := 0 to N - 1 do")
            e.line("    Result[I] := I + %d;" % seed)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A: System.TArray<Integer>;")
            e.line("begin")
            e.line("  A := DvlDynBuild%s(%d);" % (tag, width))
            e.line("  DevilCheckU('%s-length', UInt64(Cardinal(Length(A))), %d);"
                   % (name, width))
            e.line("  DevilCheckU('%s-last', UInt64(Cardinal(A[%d])), %d);"
                   % (name, width - 1, seed + width - 1))
            e.line("  { the result buffer belongs to the caller after the call, "
                   "including when it is used straight away }")
            e.line("  DevilCheckU('%s-direct', "
                   "UInt64(Cardinal(DvlDynBuild%s(2)[1])), %d);"
                   % (name, tag, seed + 1))
            e.line("end;")

        else:   # unique-on-write
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: System.TArray<Integer>;")
            e.line("begin")
            e.line("  A := [%d, %d, %d];" % (seed, seed + 1, seed + 2))
            e.line("  B := A;")
            e.line("  DevilCheckU('%s-shared', "
                   "UInt64(Ord(Pointer(A) = Pointer(B))), 1);" % name)
            e.line("  { the explicit call is what detaches a shared buffer }")
            e.line("  SetLength(B, Length(B));")
            e.line("  DevilCheckU('%s-detached', "
                   "UInt64(Ord(Pointer(A) = Pointer(B))), 0);" % name)
            e.line("  B[0] := 0;")
            e.line("  DevilCheckU('%s-source-intact', "
                   "UInt64(Cardinal(A[0])), %d);" % (name, seed))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="dyn",
                                  detail={"shape": shape, "width": width}))

    emit_runner(e, "Dyn", calls)
    return records


# On x86-64 both compilers accept only whole assembler routines - no mixing a
# Pascal body with an asm block - so every form here is a complete routine.
# What is being checked is the boundary: arguments arrive in the positions the
# ABI promises, the result leaves in RAX, callee-saved registers come back
# untouched, and the optimizer around the call does not assume it knows what
# the routine did.
ASM_SHAPES = ("identity", "sum-four", "callee-saved", "result-in-rax",
              "pointer-argument", "sign-extension", "call-in-loop",
              "asm-between-pascal")


def emit_implicit_asm_frame_matrix(e: Emitter) -> CaseRecord:
    """Exercise Delphi's headerless x86-64 ASM frame contract as one class."""
    name = "dvl-asm-implicit-frame-matrix"
    e.line("function DvlAsmImplicitEarly(A, B: NativeInt): NativeInt;")
    e.line("asm")
    e.line("  {$ifdef MSWINDOWS}")
    e.line("  CMP RCX, RDX")
    e.line("  {$else}")
    e.line("  CMP RDI, RSI")
    e.line("  {$endif}")
    e.line("  JNE @Different")
    e.line("  MOV RAX, 1")
    e.line("  RET")
    e.line("@Different:")
    e.line("  XOR RAX, RAX")
    e.line("  RET")
    e.line("end;")
    e.line()
    e.line("function DvlAsmImplicitLocal(Value: Byte): NativeInt;")
    e.line("var")
    e.line("  Buffer: array[0..31] of Byte;")
    e.line("asm")
    e.line("  {$ifdef MSWINDOWS}")
    e.line("  MOV byte ptr [Buffer], CL")
    e.line("  {$else}")
    e.line("  MOV byte ptr [Buffer], DIL")
    e.line("  {$endif}")
    e.line("  MOVZX EAX, byte ptr [Buffer]")
    e.line("end;")
    e.line()
    e.line("function DvlAsmImplicitStackParam(A1, A2, A3, A4, A5, A6, A7: "
           "NativeInt): NativeInt;")
    e.line("asm")
    e.line("  MOV RAX, A7")
    e.line("end;")
    e.line()
    e.line("procedure DvlAsmImplicitFrameMatrix;")
    e.line("begin")
    e.line("  DevilStep('%s');" % name)
    e.line("  DevilCheckU('%s-equal', UInt64(DvlAsmImplicitEarly(7, 7)), 1);"
           % name)
    e.line("  DevilCheckU('%s-different', UInt64(DvlAsmImplicitEarly(7, 8)), 0);"
           % name)
    e.line("  DevilCheckU('%s-local', UInt64(DvlAsmImplicitLocal(37)), 37);"
           % name)
    e.line("  DevilCheckU('%s-stack-param', UInt64(DvlAsmImplicitStackParam("
           "1, 2, 3, 4, 5, 6, 7)), 7);" % name)
    e.line("end;")
    e.line()
    return CaseRecord(name, "asm", {
        "shape": "delphi-implicit-asm-frame",
        "paths": ["early-ret", "local-frame", "stack-parameter"],
    })


def layer_assembler(e: Emitter, rng: random.Random, count: int,
                    start: int) -> list[CaseRecord]:
    """Assembler routines: the boundary between hand-written and generated."""
    records: list[CaseRecord] = [emit_implicit_asm_frame_matrix(e)]
    calls: list[str] = ["DvlAsmImplicitFrameMatrix"]
    for index in range(start, start + count):
        name = "dvl-asm-%05d" % index
        proc = "DvlAsm%05d" % index
        tag = "%05d" % index
        shape = rng.choice(ASM_SHAPES)
        seed = index % 40 + 1

        if shape == "identity":
            e.line("function DvlAsmEcho%s(X: NativeInt): NativeInt; assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV RAX, RCX")
            e.line("  {$else}")
            e.line("  MOV RAX, RDI")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { the first integer argument follows the target ABI; the "
                   "result leaves in RAX }")
            e.line("  DevilCheckU('%s-echo', UInt64(DvlAsmEcho%s(%d)), %d);"
                   % (name, tag, seed, seed))
            e.line("  DevilCheckU('%s-zero', UInt64(DvlAsmEcho%s(0)), 0);"
                   % (name, tag))
            e.line("end;")

        elif shape == "sum-four":
            e.line("function DvlSum4%s(A, B, C, D: NativeInt): NativeInt; "
                   "assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV RAX, RCX")
            e.line("  ADD RAX, RDX")
            e.line("  ADD RAX, R8")
            e.line("  ADD RAX, R9")
            e.line("  {$else}")
            e.line("  MOV RAX, RDI")
            e.line("  ADD RAX, RSI")
            e.line("  ADD RAX, RDX")
            e.line("  ADD RAX, RCX")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { four integer arguments follow the target ABI in order }")
            e.line("  DevilCheckU('%s-sum', UInt64(DvlSum4%s(1, 2, 3, 4)), 10);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-weighted', "
                   "UInt64(DvlSum4%s(%d, 0, 0, 0)), %d);" % (name, tag, seed, seed))
            e.line("end;")

        elif shape == "callee-saved":
            e.line("function DvlAsmKeep%s(X: NativeInt): NativeInt; assembler;" % tag)
            e.line("asm")
            e.line("  PUSH RBX")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV RBX, RCX")
            e.line("  {$else}")
            e.line("  MOV RBX, RDI")
            e.line("  {$endif}")
            e.line("  ADD RBX, 1")
            e.line("  MOV RAX, RBX")
            e.line("  POP RBX")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Before, After: NativeInt;")
            e.line("begin")
            e.line("  Before := %d;" % seed)
            e.line("  { the routine uses a callee-saved register and restores "
                   "it, so the caller's values survive the call }")
            e.line("  After := DvlAsmKeep%s(Before);" % tag)
            e.line("  DevilCheckU('%s-result', UInt64(After), %d);"
                   % (name, seed + 1))
            e.line("  DevilCheckU('%s-caller-value', UInt64(Before), %d);"
                   % (name, seed))
            e.line("end;")

        elif shape == "result-in-rax":
            e.line("function DvlAsmConst%s: NativeInt; assembler;" % tag)
            e.line("asm")
            e.line("  MOV RAX, %d" % (seed * 1000))
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Total: NativeInt;")
            e.line("begin")
            e.line("  { two calls in one expression: the caller has to keep the "
                   "first result somewhere before making the second call }")
            e.line("  Total := DvlAsmConst%s + DvlAsmConst%s;" % (tag, tag))
            e.line("  DevilCheckU('%s-total', UInt64(Total), %d);"
                   % (name, seed * 2000))
            e.line("end;")

        elif shape == "pointer-argument":
            e.line("procedure DvlAsmStore%s(Target: PNativeInt; Value: NativeInt); "
                   "assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV [RCX], RDX")
            e.line("  {$else}")
            e.line("  MOV [RDI], RSI")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Slot: NativeInt;")
            e.line("begin")
            e.line("  Slot := 0;")
            e.line("  { a store the compiler cannot see through: the reload "
                   "afterwards must actually happen }")
            e.line("  DvlAsmStore%s(@Slot, %d);" % (tag, seed))
            e.line("  DevilCheckU('%s-stored', UInt64(Slot), %d);" % (name, seed))
            e.line("  DvlAsmStore%s(@Slot, 0);" % tag)
            e.line("  DevilCheckU('%s-overwritten', UInt64(Slot), 0);" % name)
            e.line("end;")

        elif shape == "sign-extension":
            e.line("function DvlAsmWiden%s(X: Integer): NativeInt; assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOVSXD RAX, ECX")
            e.line("  {$else}")
            e.line("  MOVSXD RAX, EDI")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a narrow argument occupies a wide slot: only the low "
                   "half carries the value }")
            e.line("  DevilCheckU('%s-positive', UInt64(DvlAsmWiden%s(%d)), %d);"
                   % (name, tag, seed, seed))
            e.line("  DevilCheckU('%s-negative', "
                   "UInt64(DvlAsmWiden%s(-1)), UInt64(NativeInt(-1)));" % (name, tag))
            e.line("end;")

        elif shape == "call-in-loop":
            rounds = rng.randrange(3, 7)
            e.line("function DvlAsmStep%s(X: NativeInt): NativeInt; assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  LEA RAX, [RCX + RCX]")
            e.line("  {$else}")
            e.line("  LEA RAX, [RDI + RDI]")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Value: NativeInt;")
            e.line("begin")
            e.line("  Value := 1;")
            e.line("  for var I := 1 to %d do" % rounds)
            e.line("    Value := DvlAsmStep%s(Value);" % tag)
            e.line("  { the loop cannot be collapsed: the body is opaque }")
            e.line("  DevilCheckU('%s-value', UInt64(Value), %d);"
                   % (name, 2 ** rounds))
            e.line("end;")

        else:   # asm-between-pascal
            e.line("function DvlPascalBefore%s(X: NativeInt): NativeInt;" % tag)
            e.line("begin")
            e.line("  Result := X + 1;")
            e.line("end;")
            e.line()
            e.line("function DvlAsmMiddle%s(X: NativeInt): NativeInt; assembler;"
                   % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV RAX, RCX")
            e.line("  {$else}")
            e.line("  MOV RAX, RDI")
            e.line("  {$endif}")
            e.line("  ADD RAX, RAX")
            e.line("end;")
            e.line()
            e.line("function DvlPascalAfter%s(X: NativeInt): NativeInt;" % tag)
            e.line("begin")
            e.line("  Result := X - 1;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a hand-written routine in the middle of a generated "
                   "chain must compose like any other }")
            e.line("  DevilCheckU('%s-chain', "
                   "UInt64(DvlPascalAfter%s(DvlAsmMiddle%s(DvlPascalBefore%s(%d)))), %d);"
                   % (name, tag, tag, tag, seed, (seed + 1) * 2 - 1))
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="asm",
                                  detail={"shape": shape, "seed": seed}))

    emit_runner(e, "Asm", calls)
    return records


# A typed file is a language construct, not a library call: the element type
# decides the record size on disk, and the compiler emits the layout. Untyped
# files add a block size the caller picks. Both are the oldest part of the
# language and the least exercised by modern code, which is exactly why they
# are worth checking - a wrong element size corrupts a file silently.
IO_SHAPES = ("typed-record", "typed-seek", "untyped-blocks", "text-lines",
             "typed-truncate", "element-size", "eof-behaviour", "text-append")


def layer_io(e: Emitter, rng: random.Random, count: int,
             start: int) -> list[CaseRecord]:
    """File types: element size, positioning, and end of file."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-io-%05d" % index
        proc = "DvlIo%05d" % index
        tag = "%05d" % index
        shape = rng.choice(IO_SHAPES)
        rows = rng.randrange(3, 8)
        seed = index % 40 + 1

        e.line("type")
        e.line("  TDvlRow%s = record" % tag)
        e.line("    Id: Integer;")
        e.line("    Weight: Double;")
        e.line("    Flag: Boolean;")
        e.line("  end;")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Path: string;")
        e.line("  F: file of TDvlRow%s;" % tag)
        e.line("  Raw: file;")
        e.line("  T: TextFile;")
        e.line("  Row: TDvlRow%s;" % tag)
        e.line("  Bytes: array[0..15] of Byte;")
        e.line("  Line: string;")
        e.line("  Moved: Integer;")
        e.line("begin")
        e.line("  Path := IncludeTrailingPathDelimiter(GetCurrentDir) + "
               "'dvl_io_%s.tmp';" % tag)
        e.line("  try")

        if shape in ("typed-record", "typed-seek", "typed-truncate",
                     "eof-behaviour"):
            e.line("    AssignFile(F, Path);")
            e.line("    Rewrite(F);")
            e.line("    try")
            e.line("      for var I := 0 to %d do" % (rows - 1))
            e.line("      begin")
            e.line("        Row.Id := I + %d;" % seed)
            e.line("        Row.Weight := I;")
            e.line("        Row.Flag := Odd(I);")
            e.line("        Write(F, Row);")
            e.line("      end;")
            e.line("      DevilCheckU('%s-count', "
                   "UInt64(Cardinal(FileSize(F))), %d);" % (name, rows))
            if shape == "typed-seek":
                e.line("      { positioning counts elements, not bytes }")
                e.line("      Seek(F, 1);")
                e.line("      Read(F, Row);")
                e.line("      DevilCheckU('%s-seeked-id', "
                       "UInt64(Cardinal(Row.Id)), %d);" % (name, seed + 1))
                e.line("      DevilCheckU('%s-position', "
                       "UInt64(Cardinal(FilePos(F))), 2);" % name)
            elif shape == "typed-truncate":
                e.line("      Seek(F, 2);")
                e.line("      Truncate(F);")
                e.line("      DevilCheckU('%s-truncated', "
                       "UInt64(Cardinal(FileSize(F))), 2);" % name)
            elif shape == "eof-behaviour":
                e.line("      Seek(F, 0);")
                e.line("      Moved := 0;")
                e.line("      while not Eof(F) do")
                e.line("      begin")
                e.line("        Read(F, Row);")
                e.line("        Inc(Moved);")
                e.line("      end;")
                e.line("      { Eof turns true exactly after the last element }")
                e.line("      DevilCheckU('%s-read-count', "
                       "UInt64(Cardinal(Moved)), %d);" % (name, rows))
            else:
                e.line("      Seek(F, 0);")
                e.line("      Read(F, Row);")
                e.line("      DevilCheckU('%s-first-id', "
                       "UInt64(Cardinal(Row.Id)), %d);" % (name, seed))
                e.line("      DevilCheckU('%s-first-flag', "
                       "UInt64(Ord(Row.Flag)), 0);" % name)
            e.line("    finally")
            e.line("      CloseFile(F);")
            e.line("    end;")

        elif shape == "element-size":
            e.line("    AssignFile(F, Path);")
            e.line("    Rewrite(F);")
            e.line("    try")
            e.line("      Row.Id := %d;" % seed)
            e.line("      Row.Weight := 1;")
            e.line("      Row.Flag := True;")
            e.line("      Write(F, Row);")
            e.line("    finally")
            e.line("      CloseFile(F);")
            e.line("    end;")
            e.line("    { the file holds exactly one record image, so its byte "
                   "size is the record size }")
            e.line("    AssignFile(Raw, Path);")
            e.line("    Reset(Raw, 1);")
            e.line("    try")
            e.line("      DevilCheckU('%s-bytes', "
                   "UInt64(Cardinal(FileSize(Raw))), "
                   "UInt64(Cardinal(SizeOf(TDvlRow%s))));" % (name, tag))
            e.line("    finally")
            e.line("      CloseFile(Raw);")
            e.line("    end;")

        elif shape == "untyped-blocks":
            e.line("    AssignFile(Raw, Path);")
            e.line("    Rewrite(Raw, 4);")
            e.line("    try")
            e.line("      for var I := 0 to 15 do")
            e.line("        Bytes[I] := I + %d;" % (seed % 100))
            e.line("      BlockWrite(Raw, Bytes, 4, Moved);")
            e.line("      { the block size chosen at open decides what a count "
                   "of four means }")
            e.line("      DevilCheckU('%s-written', "
                   "UInt64(Cardinal(Moved)), 4);" % name)
            e.line("      DevilCheckU('%s-size', "
                   "UInt64(Cardinal(FileSize(Raw))), 4);" % name)
            e.line("    finally")
            e.line("      CloseFile(Raw);")
            e.line("    end;")
            e.line("    FillChar(Bytes, SizeOf(Bytes), 0);")
            e.line("    AssignFile(Raw, Path);")
            e.line("    Reset(Raw, 1);")
            e.line("    try")
            e.line("      DevilCheckU('%s-bytes', "
                   "UInt64(Cardinal(FileSize(Raw))), 16);" % name)
            e.line("      BlockRead(Raw, Bytes, 16, Moved);")
            e.line("      DevilCheckU('%s-read', UInt64(Cardinal(Moved)), 16);"
                   % name)
            e.line("      DevilCheckU('%s-first-byte', "
                   "UInt64(Bytes[0]), %d);" % (name, seed % 100))
            e.line("    finally")
            e.line("      CloseFile(Raw);")
            e.line("    end;")

        elif shape == "text-append":
            e.line("    AssignFile(T, Path);")
            e.line("    Rewrite(T);")
            e.line("    try")
            e.line("      WriteLn(T, 'first');")
            e.line("    finally")
            e.line("      CloseFile(T);")
            e.line("    end;")
            e.line("    AssignFile(T, Path);")
            e.line("    Append(T);")
            e.line("    try")
            e.line("      WriteLn(T, 'second');")
            e.line("    finally")
            e.line("      CloseFile(T);")
            e.line("    end;")
            e.line("    AssignFile(T, Path);")
            e.line("    Reset(T);")
            e.line("    try")
            e.line("      Moved := 0;")
            e.line("      while not Eof(T) do")
            e.line("      begin")
            e.line("        ReadLn(T, Line);")
            e.line("        Inc(Moved);")
            e.line("      end;")
            e.line("      { appending adds to what was there instead of "
                   "replacing it }")
            e.line("      DevilCheckU('%s-lines', UInt64(Cardinal(Moved)), 2);"
                   % name)
            e.line("      DevilCheckU('%s-last', UInt64(Length(Line)), 6);" % name)
            e.line("    finally")
            e.line("      CloseFile(T);")
            e.line("    end;")

        else:   # text-lines
            e.line("    AssignFile(T, Path);")
            e.line("    Rewrite(T);")
            e.line("    try")
            e.line("      for var I := 1 to %d do" % rows)
            e.line("        WriteLn(T, 'line', I);")
            e.line("    finally")
            e.line("      CloseFile(T);")
            e.line("    end;")
            e.line("    AssignFile(T, Path);")
            e.line("    Reset(T);")
            e.line("    try")
            e.line("      Moved := 0;")
            e.line("      Line := '';")
            e.line("      while not Eof(T) do")
            e.line("      begin")
            e.line("        ReadLn(T, Line);")
            e.line("        Inc(Moved);")
            e.line("      end;")
            e.line("      { every written line comes back, and the last one is "
                   "complete }")
            e.line("      DevilCheckU('%s-lines', UInt64(Cardinal(Moved)), %d);"
                   % (name, rows))
            e.line("      DevilCheckU('%s-last-length', "
                   "UInt64(Length(Line)), %d);" % (name, len("line%d" % rows)))
            e.line("    finally")
            e.line("      CloseFile(T);")
            e.line("    end;")

        e.line("  finally")
        e.line("    If FileExists(Path) then")
        e.line("      DeleteFile(Path);")
        e.line("  end;")
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="io",
                                  detail={"shape": shape, "rows": rows}))

    emit_runner(e, "Io", calls)
    return records


# Declarations are the part of the language nobody tests because nothing about
# them produces a value: a forward that must match its body, a directive that
# silently changes what a whole block of code means, an import whose only job
# is to arrive at the right address with the right convention. When one of
# these is wrong the program still runs - it just means something else.
DECL_SHAPES = ("forward-routine", "forward-type", "pointermath",
               "scopedenums", "reintroduce", "sealed-final",
               "external-import", "external-varargs", "overload-forward",
               "const-typed-vs-true", "local-const-scope", "deprecated-hint",
               "conditional-state", "attribute-arguments")


def layer_declarations(e: Emitter, rng: random.Random, count: int,
                       start: int) -> list[CaseRecord]:
    """Declarations and directives: what the code means before it runs."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-decl-%05d" % index
        proc = "DvlDecl%05d" % index
        tag = "%05d" % index
        shape = rng.choice(DECL_SHAPES)
        seed = index % 40 + 1

        if shape == "forward-routine":
            e.line("function DvlOdd%s(X: Integer): Boolean; forward;" % tag)
            e.line()
            e.line("function DvlEven%s(X: Integer): Boolean;" % tag)
            e.line("begin")
            e.line("  If X = 0 then")
            e.line("    Result := True")
            e.line("  else")
            e.line("    Result := DvlOdd%s(X - 1);" % tag)
            e.line("end;")
            e.line()
            e.line("function DvlOdd%s(X: Integer): Boolean;" % tag)
            e.line("begin")
            e.line("  If X = 0 then")
            e.line("    Result := False")
            e.line("  else")
            e.line("    Result := DvlEven%s(X - 1);" % tag)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { mutual recursion needs the forward, and the body must "
                   "match the header it promised }")
            e.line("  DevilCheckU('%s-even', UInt64(Ord(DvlEven%s(%d))), %d);"
                   % (name, tag, seed * 2, 1))
            e.line("  DevilCheckU('%s-odd', UInt64(Ord(DvlOdd%s(%d))), %d);"
                   % (name, tag, seed * 2 + 1, 1))
            e.line("end;")

        elif shape == "forward-type":
            e.line("type")
            e.line("  PDvlNode%s = ^TDvlNode%s;" % (tag, tag))
            e.line("  TDvlNode%s = record" % tag)
            e.line("    Value: Integer;")
            e.line("    Next: PDvlNode%s;" % tag)
            e.line("  end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  A, B: TDvlNode%s;" % tag)
            e.line("begin")
            e.line("  { the pointer type was declared before the record it "
                   "points at }")
            e.line("  A.Value := %d;" % seed)
            e.line("  B.Value := %d;" % (seed + 1))
            e.line("  A.Next := @B;")
            e.line("  B.Next := nil;")
            e.line("  DevilCheckU('%s-chained', "
                   "UInt64(Cardinal(A.Next^.Value)), %d);" % (name, seed + 1))
            e.line("  DevilCheckU('%s-terminated', "
                   "UInt64(Ord(A.Next^.Next = nil)), 1);" % name)
            e.line("end;")

        elif shape == "pointermath":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Data: array[0..7] of Integer;")
            e.line("  P: PInteger;")
            e.line("begin")
            e.line("  for var I := 0 to 7 do")
            e.line("    Data[I] := I + %d;" % seed)
            e.line("  P := @Data[0];")
            e.line("{$POINTERMATH ON}")
            e.line("  { with the directive on, a typed pointer indexes and "
                   "steps by its element }")
            e.line("  DevilCheckU('%s-indexed', UInt64(Cardinal(P[2])), %d);"
                   % (name, seed + 2))
            e.line("  DevilCheckU('%s-added', UInt64(Cardinal((P + 3)^)), %d);"
                   % (name, seed + 3))
            e.line("  DevilCheckU('%s-difference', "
                   "UInt64(Cardinal((P + 5) - P)), 5);" % name)
            e.line("{$POINTERMATH OFF}")
            e.line("  DevilCheckU('%s-still-points', "
                   "UInt64(Cardinal(P^)), %d);" % (name, seed))
            e.line("end;")

        elif shape == "scopedenums":
            e.line("{$SCOPEDENUMS ON}")
            e.line("type")
            e.line("  TDvlScoped%s = (Red, Green, Blue);" % tag)
            e.line("{$SCOPEDENUMS OFF}")
            e.line("type")
            # unscoped members land in the surrounding scope, so they
            # must not collide with another case in the same file
            e.line("  TDvlPlain%s = (DvlA%s, DvlB%s, DvlG%s);"
                   % (tag, tag, tag, tag))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  S: TDvlScoped%s;" % tag)
            e.line("  P: TDvlPlain%s;" % tag)
            e.line("begin")
            e.line("  { a scoped enum needs its type name; an unscoped one puts "
                   "its members in the surrounding scope }")
            e.line("  S := TDvlScoped%s.Green;" % tag)
            e.line("  P := DvlB%s;" % tag)
            e.line("  DevilCheckU('%s-scoped', UInt64(Ord(S)), 1);" % name)
            e.line("  DevilCheckU('%s-plain', UInt64(Ord(P)), 1);" % name)
            e.line("  DevilCheckU('%s-high', "
                   "UInt64(Ord(High(TDvlScoped%s))), 2);" % (name, tag))
            e.line("end;")

        elif shape == "reintroduce":
            e.line("type")
            e.line("  TDvlOld%s = class" % tag)
            e.line("  public")
            e.line("    function Value: Integer; virtual;")
            e.line("  end;")
            e.line()
            e.line("  TDvlNew%s = class(TDvlOld%s)" % (tag, tag))
            e.line("  public")
            e.line("    function Value: Integer; reintroduce;")
            e.line("  end;")
            e.line()
            e.line("function TDvlOld%s.Value: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("end;")
            e.line()
            e.line("function TDvlNew%s.Value: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Obj: TDvlNew%s;" % tag)
            e.line("  Base: TDvlOld%s;" % tag)
            e.line("begin")
            e.line("  Obj := TDvlNew%s.Create;" % tag)
            e.line("  try")
            e.line("    Base := Obj;")
            e.line("    { reintroduce hides instead of overriding, so the "
                   "static type decides which body runs }")
            e.line("    DevilCheckU('%s-static', UInt64(Cardinal(Obj.Value)), 2);"
                   % name)
            e.line("    DevilCheckU('%s-through-base', "
                   "UInt64(Cardinal(Base.Value)), 1);" % name)
            e.line("  finally")
            e.line("    Obj.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "sealed-final":
            e.line("type")
            e.line("  TDvlOpen%s = class" % tag)
            e.line("  public")
            e.line("    function Step: Integer; virtual;")
            e.line("  end;")
            e.line()
            e.line("  TDvlShut%s = class sealed(TDvlOpen%s)" % (tag, tag))
            e.line("  public")
            e.line("    function Step: Integer; override; final;")
            e.line("  end;")
            e.line()
            e.line("function TDvlOpen%s.Step: Integer;" % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("end;")
            e.line()
            e.line("function TDvlShut%s.Step: Integer;" % tag)
            e.line("begin")
            e.line("  Result := inherited Step + 1;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Obj: TDvlOpen%s;" % tag)
            e.line("begin")
            e.line("  Obj := TDvlShut%s.Create;" % tag)
            e.line("  try")
            e.line("    { sealed and final restrict what may be derived, and "
                   "change nothing about dispatch }")
            e.line("    DevilCheckU('%s-dispatch', UInt64(Cardinal(Obj.Step)), 2);"
                   % name)
            e.line("    DevilCheckU('%s-class', "
                   "UInt64(Ord(Obj.ClassType = TDvlShut%s)), 1);" % (name, tag))
            e.line("  finally")
            e.line("    Obj.Free;")
            e.line("  end;")
            e.line("end;")

        elif shape == "external-import":
            e.line("{$ifdef MSWINDOWS}")
            e.line("function DvlTicks%s: UInt64; stdcall; "
                   "external 'kernel32.dll' name 'GetTickCount64';" % tag)
            e.line("{$else MSWINDOWS}")
            e.line("function DvlTicks%s: LongInt; cdecl; "
                   "external 'c' name 'getpid';" % tag)
            e.line("{$endif MSWINDOWS}")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  First, Second: UInt64;")
            e.line("begin")
            e.line("  { an imported routine has to arrive at the right address "
                   "with the right convention; the value only has to move "
                   "forward }")
            e.line("  First := DvlTicks%s;" % tag)
            e.line("  Second := DvlTicks%s;" % tag)
            e.line("  DevilCheckU('%s-nonzero', UInt64(Ord(First > 0)), 1);" % name)
            e.line("  DevilCheckU('%s-monotonic', "
                   "UInt64(Ord(Second >= First)), 1);" % name)
            e.line("end;")

        elif shape == "external-varargs":
            e.line("function DvlFormat%s(Buffer: PAnsiChar; const Fmt: PAnsiChar): "
                   "Integer; cdecl; varargs;" % tag)
            e.line("{$ifdef MSWINDOWS}")
            e.line("  external 'msvcrt.dll' name 'sprintf';")
            e.line("{$else MSWINDOWS}")
            e.line("  external 'c' name 'sprintf';")
            e.line("{$endif MSWINDOWS}")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Buffer: array[0..63] of AnsiChar;")
            e.line("  Written: Integer;")
            e.line("begin")
            e.line("  FillChar(Buffer, SizeOf(Buffer), 0);")
            e.line("  { varargs is only meaningful on an import, and every "
                   "argument still has to reach the callee }")
            e.line("  Written := DvlFormat%s(@Buffer[0], '%%d-%%d', %d, %d);"
                   % (tag, seed, seed + 1))
            e.line("  DevilCheckU('%s-written', UInt64(Cardinal(Written)), %d);"
                   % (name, len("%d-%d" % (seed, seed + 1))))
            e.line("  DevilCheckU('%s-first-char', UInt64(Ord(Buffer[0])), %d);"
                   % (name, ord(str(seed)[0])))
            e.line("end;")

        elif shape == "overload-forward":
            e.line("function DvlPickD%s(X: Integer): Integer; overload; forward;"
                   % tag)
            e.line("function DvlPickD%s(X: AnsiString): Integer; overload; forward;"
                   % tag)
            e.line()
            e.line("function DvlPickD%s(X: Integer): Integer;" % tag)
            e.line("begin")
            e.line("  Result := 1;")
            e.line("end;")
            e.line()
            e.line("function DvlPickD%s(X: AnsiString): Integer;" % tag)
            e.line("begin")
            e.line("  Result := 2;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { the overload set is built from the forwards, and the "
                   "bodies join the set they promised }")
            e.line("  DevilCheckU('%s-int', UInt64(Cardinal(DvlPickD%s(1))), 1);"
                   % (name, tag))
            e.line("  DevilCheckU('%s-string', "
                   "UInt64(Cardinal(DvlPickD%s(AnsiString('a')))), 2);"
                   % (name, tag))
            e.line("end;")

        elif shape == "const-typed-vs-true":
            e.line("const")
            e.line("  DvlTrue%s = %d;" % (tag, seed))
            e.line("  DvlTyped%s: Integer = %d;" % (tag, seed))
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Data: array[0..DvlTrue%s] of Integer;" % tag)
            e.line("begin")
            e.line("  { a true constant can size a type; a typed constant is a "
                   "variable with an initial value }")
            e.line("  DevilCheckU('%s-length', "
                   "UInt64(Cardinal(Length(Data))), %d);" % (name, seed + 1))
            e.line("  DevilCheckU('%s-typed', "
                   "UInt64(Cardinal(DvlTyped%s)), %d);" % (name, tag, seed))
            e.line("  DevilCheckU('%s-sizeof', "
                   "UInt64(Cardinal(SizeOf(Data))), %d);" % (name, (seed + 1) * 4))
            e.line("end;")

        elif shape == "local-const-scope":
            e.line("procedure %s;" % proc)
            e.line()
            e.line("  function Inner: Integer;")
            e.line("  const")
            e.line("    Local = %d;" % (seed * 3))
            e.line("  begin")
            e.line("    Result := Local;")
            e.line("  end;")
            e.line()
            e.line("const")
            e.line("  Outer = %d;" % seed)
            e.line("begin")
            e.line("  { a constant declared inside a routine belongs to it "
                   "alone }")
            e.line("  DevilCheckU('%s-outer', UInt64(Cardinal(Outer)), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-inner', UInt64(Cardinal(Inner)), %d);"
                   % (name, seed * 3))
            e.line("end;")

        elif shape == "conditional-state":
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Overflow, Range, Path: Integer;")
            e.line("begin")
            e.line("  { IFOPT reads the switch state the compiler is in right "
                   "now, not what the command line asked for }")
            e.line("{$Q+}")
            e.line("{$IFOPT Q+}")
            e.line("  Overflow := 1;")
            e.line("{$ELSE}")
            e.line("  Overflow := 0;")
            e.line("{$ENDIF}")
            e.line("{$Q-}")
            e.line("{$IFOPT Q+}")
            e.line("  Range := 1;")
            e.line("{$ELSE}")
            e.line("  Range := 0;")
            e.line("{$ENDIF}")
            e.line("  DevilCheckU('%s-on', UInt64(Cardinal(Overflow)), 1);" % name)
            e.line("  DevilCheckU('%s-off', UInt64(Cardinal(Range)), 0);" % name)
            e.line("{$IF Declared(DvlDeclMarker%s)}" % tag)
            e.line("  Path := 1;")
            e.line("{$ELSE}")
            e.line("  Path := 2;")
            e.line("{$IFEND}")
            e.line("  { Declared answers about this point in the file }")
            e.line("  DevilCheckU('%s-declared', UInt64(Cardinal(Path)), 2);" % name)
            e.line("end;")

        elif shape == "attribute-arguments":
            e.line("type")
            e.line("  DvlMark%sAttribute = class(TCustomAttribute)" % tag)
            e.line("  private")
            e.line("    FTag: Integer;")
            e.line("    FText: string;")
            e.line("  public")
            e.line("    constructor Create(ATag: Integer; const AText: string);")
            e.line("    property Tag: Integer read FTag;")
            e.line("    property Text: string read FText;")
            e.line("  end;")
            e.line()
            e.line("  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic]) "
                   "FIELDS([vcPublic])}")
            e.line("  [DvlMark%s(%d, 'kept')]" % (tag, seed))
            e.line("  TDvlTagged%s = class" % tag)
            e.line("  public")
            e.line("    Value: Integer;")
            e.line("  end;")
            e.line()
            e.line("{ директива живёт до конца модуля: не вернуть её сюда - "
                   "значит перекрасить все следующие слои (dvl-0040) }")
            e.line("{$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) "
                   "PROPERTIES([vcPublic, vcPublished]) "
                   "FIELDS([vcPrivate, vcProtected, vcPublic, vcPublished])}")
            e.line()
            e.line("constructor DvlMark%sAttribute.Create(ATag: Integer; "
                   "const AText: string);" % tag)
            e.line("begin")
            e.line("  inherited Create;")
            e.line("  FTag := ATag;")
            e.line("  FText := AText;")
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("var")
            e.line("  Context: TRttiContext;")
            e.line("  Found: Integer;")
            e.line("  Text: Integer;")
            e.line("begin")
            e.line("  Found := 0;")
            e.line("  Text := 0;")
            e.line("  Context := TRttiContext.Create;")
            e.line("  try")
            e.line("    { the arguments written at the declaration have to "
                   "survive into the attribute instance }")
            e.line("    for var A in Context.GetType(TDvlTagged%s).GetAttributes do"
                   % tag)
            e.line("      If A is DvlMark%sAttribute then" % tag)
            e.line("      begin")
            e.line("        Found := DvlMark%sAttribute(A).Tag;" % tag)
            e.line("        Text := Length(DvlMark%sAttribute(A).Text);" % tag)
            e.line("      end;")
            e.line("  finally")
            e.line("    Context.Free;")
            e.line("  end;")
            e.line("  DevilCheckU('%s-tag', UInt64(Cardinal(Found)), %d);"
                   % (name, seed))
            e.line("  DevilCheckU('%s-text', UInt64(Cardinal(Text)), 4);" % name)
            e.line("end;")

        else:   # deprecated-hint
            e.line("function DvlOldWay%s: Integer; deprecated 'use the new one';"
                   % tag)
            e.line("begin")
            e.line("  Result := %d;" % seed)
            e.line("end;")
            e.line()
            e.line("procedure %s;" % proc)
            e.line("begin")
            e.line("  { a hint directive changes diagnostics, never behaviour }")
            e.line("{$WARN SYMBOL_DEPRECATED OFF}")
            e.line("  DevilCheckU('%s-value', "
                   "UInt64(Cardinal(DvlOldWay%s)), %d);" % (name, tag, seed))
            e.line("{$WARN SYMBOL_DEPRECATED ON}")
            e.line("end;")

        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="decl",
                                  detail={"shape": shape, "seed": seed}))

    emit_runner(e, "Decl", calls)
    return records


# Every other layer asks one mechanism one question. This one nests them: a
# value enters stage 1, and stage 1 can only produce its answer by calling
# stage 2 from inside its own machinery - inside the finally block, inside the
# worker thread, inside the exception handler, inside the closure. Fifteen
# stages deep, the call stack holds fifteen different compiler features at
# once, and the value has to come back through all of them unchanged.
#
# The oracle needs no reference implementation: identity is the invariant. Any
# stage that loses, truncates, re-encodes or duplicates the value shows up as
# one wrong number at the very end, and the trail says which stage it was.
CHAIN_STAGES = (
    "string-roundtrip", "wide-record", "generic-box", "interface-method",
    "closure-capture", "dynamic-array", "variant-carrier", "worker-thread",
    "typed-file", "assembler-hop", "raised-exception", "inline-hop",
    "pointer-view", "method-pointer", "open-array", "rtti-value",
    "finally-transfer", "nested-var-param", "case-dispatch", "set-of-bits",
    "utf8-detour", "managed-record", "class-var-hop", "sorted-pair",
    "branch-merge", "branch-thread-merge", "recursive-descent",
    "guarded-retry", "woven-carrier", "metamorphic-fork", "generic-relay",
    "ppu-generic", "ppu-descendant", "sibling-chain",
    "volatile-slot", "aliased-relay",
    "narrow-widen-bait", "cast-reinterpret-bait",
    "varrec-bait", "variant-literal-bait", "unicode-cast-bait",
    "finalization-order-bait", "generic-method", "constrained-generic",
    "nested-specialization", "generic-thread", "mutual-chain", "tree-walk",
    "foreign-form", "passport-check", "string-passport", "directive-passport",
    "fold-mirror", "inline-mirror", "specialization-mirror",
    "dead-store-leak", "hoist-leak", "unreachable-leak", "field-leak",
    "closure-leak",
)

# only available when some other layer was generated before this one
CHAIN_NEEDS_FOREIGN = {"foreign-form"}

# only a case that has a predecessor may call into it
CHAIN_NEEDS_SIBLING = {"sibling-chain", "mutual-chain"}

# forms of these layers may be executed a second time from inside a chain:
# they assert about themselves and leave nothing behind. Layers that own global
# state (module startup, threads, files, chains themselves) are not on the list.
CHAIN_FOREIGN_LAYERS = ("expr", "unary", "cmp", "fold", "abi", "str", "arr",
                        "set", "flow", "lang", "uni", "call", "opt", "dyn",
                        "weave", "decl", "meta", "gen", "disp", "intf")

# every routine each layer emitted, in generation order
EMITTED_FORMS: dict[str, list[str]] = {}

# `effect-pair` and `tiny-effect-bait` are deliberately absent from the stage
# list: dvl-0018 makes the release build run the continuation once instead of
# twice, which changes how many times everything below feeds the bloodstream.
# A known defect that permanently colours the root digest would mask every new
# one, so the trap for it lives in the stress gate instead, on its own.

# a value no chain would ever carry, used to turn a pass into an unwind
CHAIN_SENTINEL = 0x5EED0B00

# a branching stage enters its continuation twice, so the trail grows by more
# than one mark per level and the depth check has to know it
CHAIN_BRANCHING = {"branch-merge", "branch-thread-merge", "effect-pair"}

# stages that must not sit inside a thread stage: the worker would inherit a
# file handle or an exception context that belongs to the caller
# stages that keep state outside the call: two branches running at once would
# race on it, and the race is in the test, not in the compiler
CHAIN_UNSAFE_UNDER_THREAD = {"typed-file", "worker-thread", "class-var-hop",
                             "volatile-slot", "effect-pair", "sibling-chain",
                             "tiny-effect-bait", "finalization-order-bait",
                             "mutual-chain",
                             # the bloodstream is order-sensitive by design:
                             # two branches feeding it at once from different
                             # threads interleave, and the digest stops being
                             # a property of the program
                             "passport-check", "string-passport",
                             "directive-passport", "fold-mirror",
                             "inline-mirror", "specialization-mirror",
                             "dead-store-leak", "hoist-leak",
                             "unreachable-leak", "field-leak", "closure-leak",
                             "varrec-bait", "variant-literal-bait",
                             "unicode-cast-bait", "narrow-widen-bait",
                             "cast-reinterpret-bait", "foreign-form"}

# stages that reset the shared trail: the depth of such a pass is meaningless
CHAIN_TRAIL_BREAKING = {"finalization-order-bait"}
# stages that put a continuation on another thread while the caller keeps going
CHAIN_THREADED = {"worker-thread", "branch-thread-merge", "generic-thread"}


def write_chain_unit(out: Path) -> None:
    """Gates that take the continuation as a pointer and call it their own way."""
    # a {$mode} directive inside the unit resets the mode switches the driver
    # passed on the command line, so they have to be restated here
    lines = ["unit devil_chain_gates;", "",
             "{$ifdef FPC}",
             "  {$mode delphiunicode}{$H+}",
             "  {$modeswitch advancedrecords}",
             "  {$modeswitch INLINEVARS}",
             "  {$modeswitch anonymousfunctions}",
             "  {$modeswitch functionreferences}",
             "{$endif}",
             "{$Q-}{$R-}", "",
             "interface", "", "uses",
             "  SysUtils, devil_runtime;", "",
             "type",
             "  TDvlStep = function(X: Int64): Int64;", "",
             "var",
             "  DvlGateTouched: Int64;", ""]
    text_gate = [
        "function DvlCrossText(const V: RawByteString): RawByteString;",
        "begin",
        "  { the bytes cross the boundary as bytes: no conversion here }",
        "  Result := V;",
        "end;",
        "",
    ]
    gates = {
        "Loop": ["  Result := 0;",
                 "  for var Pass := 1 to 1 do",
                 "    Result := Next(X);"],
        "Branch": ["  If DvlGateTouched >= 0 then",
                   "    Result := Next(X)",
                   "  else",
                   "    Result := not X;"],
        "Guarded": ["  Result := 0;", "  try",
                    "    Result := Next(X);", "  finally",
                    "    Inc(DvlGateTouched);", "  end;"],
        "Case": ["  Result := 0;",
                 "  case DvlGateTouched and 1 of",
                 "    0, 1: Result := Next(X);",
                 "  else", "    Result := not X;", "  end;"],
        "Retry": ["  Result := 0;",
                  "  for var Attempt := 1 to 2 do",
                  "    If Attempt = 2 then",
                  "      Result := Next(X);"],
    }
    for gate in gates:
        lines.append("function DvlCross%s(X: Int64; Next: TDvlStep): Int64;"
                     % gate)
    lines.append("function DvlCrossText(const V: RawByteString): RawByteString;")
    lines += ["", "implementation", ""]
    lines += text_gate
    for gate, body in gates.items():
        lines.append("function DvlCross%s(X: Int64; Next: TDvlStep): Int64;"
                     % gate)
        lines.append("begin")
        lines += body
        lines += ["end;", ""]
    lines.append("end.")
    (out / "devil_chain_gates.pas").write_text("\n".join(lines) + "\n",
                                               encoding="utf-8")


CHAIN_CROSS_GATES = ("Loop", "Branch", "Guarded", "Case", "Retry")


def write_chain_types_unit(out: Path) -> None:
    """Generic and interface types that a chain specializes from a PPU."""
    lines = ["unit devil_chain_types;", "",
             "{$ifdef FPC}",
             "  {$mode delphiunicode}{$H+}",
             "  {$modeswitch advancedrecords}",
             "  {$modeswitch INLINEVARS}",
             "  {$modeswitch anonymousfunctions}",
             "  {$modeswitch functionreferences}",
             "{$endif}",
             "{$Q-}{$R-}", "",
             "interface", "", "uses",
             "  SysUtils;", "",
             "type",
             "  { specialized on the other side of the boundary, so the "
             "    compiler has to replay this body out of the PPU }",
             "  TDvlCarrier<T> = record",
             "  private",
             "    FValue: T;",
             "    FText: AnsiString;",
             "  public",
             "    procedure Put(const Value: T);",
             "    function Get: T;",
             "    function Width: Integer;",
             "  end;", "",
             "  IDvlRelay = interface",
             "    ['{5E000000-0000-0000-0000-0000000000A1}']",
             "    function Relay(X: Int64): Int64;",
             "  end;", "",
             "  TDvlRelayBase = class(TInterfacedObject, IDvlRelay)",
             "  public",
             "    function Relay(X: Int64): Int64; virtual;",
             "  end;", "",
             "implementation", "",
             "procedure TDvlCarrier<T>.Put(const Value: T);",
             "begin",
             "  FValue := Value;",
             "  FText := AnsiString('carried');",
             "end;", "",
             "function TDvlCarrier<T>.Get: T;",
             "begin",
             "  Result := FValue;",
             "end;", "",
             "function TDvlCarrier<T>.Width: Integer;",
             "begin",
             "  Result := SizeOf(T) + Length(FText);",
             "end;", "",
             "function TDvlRelayBase.Relay(X: Int64): Int64;",
             "begin",
             "  Result := X;",
             "end;", "",
             "end."]
    (out / "devil_chain_types.pas").write_text("\n".join(lines) + "\n",
                                               encoding="utf-8")


CHAIN_GATES = ("loop-once", "branch", "case-arm", "with-record", "guarded",
               "downto-loop", "repeat-once", "nested-if", "double-guard")


def emit_chain_gate(e: Emitter, gate: str, fn: str, target: str) -> None:
    """A routine that reaches `target` from inside a control construct."""
    e.line("function %s(X: Int64): Int64;" % fn)
    e.line("var")
    e.line("  Guard: IInterface;")
    e.line("begin")
    e.line("  { held for the whole time the step below runs: if an exception "
           "comes back up through here, this is what must be released }")
    e.line("  Guard := TDvlTagged.Create('g');")
    e.line("  Result := 0;")
    if gate == "loop-once":
        e.line("  for var Pass := 1 to 1 do")
        e.line("    Result := %s(X);" % target)
    elif gate == "downto-loop":
        e.line("  for var Pass := 1 downto 1 do")
        e.line("    Result := %s(X);" % target)
    elif gate == "branch":
        e.line("  If DvlChainScope.Touched >= 0 then")
        e.line("    Result := %s(X)" % target)
        e.line("  else")
        e.line("    Result := not X;")
    elif gate == "nested-if":
        e.line("  If DvlChainScope.Touched >= 0 then")
        e.line("    If Length(DvlChainScope.Name) < 100 then")
        e.line("      If X = X then")
        e.line("        Result := %s(X);" % target)
    elif gate == "case-arm":
        e.line("  case DvlChainScope.Touched and 3 of")
        e.line("    0, 1, 2, 3: Result := %s(X);" % target)
        e.line("  else")
        e.line("    Result := not X;")
        e.line("  end;")
    elif gate == "with-record":
        e.line("  with DvlChainScope do")
        e.line("  begin")
        e.line("    Touched := Touched + 1;")
        e.line("    Result := %s(X);" % target)
        e.line("  end;")
    elif gate == "guarded":
        e.line("  try")
        e.line("    Result := %s(X);" % target)
        e.line("  finally")
        e.line("    DvlChainScope.Touched := DvlChainScope.Touched + 1;")
        e.line("  end;")
    elif gate == "double-guard":
        e.line("  try")
        e.line("    try")
        e.line("      Result := %s(X);" % target)
        e.line("    except")
        e.line("      Result := not X;")
        e.line("    end;")
        e.line("  finally")
        e.line("    DvlChainScope.Touched := DvlChainScope.Touched + 1;")
        e.line("  end;")
    else:   # repeat-once
        e.line("  repeat")
        e.line("    Result := %s(X);" % target)
        e.line("  until True;")
    e.line("end;")
    e.line()


def emit_passport(e: Emitter, expr: str, indent: str = "  ") -> None:
    """Feed everything an integer value carries besides its magnitude."""
    e.line(indent + "{ passport: the number is the least fragile thing here }")
    e.line(indent + "DevilFeed(UInt64(%s));" % expr)
    e.line(indent + "DevilFeed(UInt64(SizeOf(%s)));" % expr)
    e.line(indent + "{ width and signedness, witnessed by what narrowing does }")
    e.line(indent + "DevilFeed(UInt64(Cardinal(%s)));" % expr)
    e.line(indent + "DevilFeed(UInt64(Int64(Integer(%s))));" % expr)
    e.line(indent + "DevilFeed(UInt64(Int64(SmallInt(%s))));" % expr)
    e.line(indent + "DevilFeed(UInt64(Ord(%s < 0)));" % expr)
    e.line(indent + "{ and how the value behaves at the edge of its domain }")
    e.line(indent + "DevilFeed(UInt64(Ord(%s = Int64(Integer(%s)))));"
           % (expr, expr))


def emit_string_passport(e: Emitter, name: str, expr: str,
                         indent: str = "  ") -> None:
    """Feed what a string carries.

    Codepage and byte image are held out of the bloodstream while dvl-0013 and
    friends are open: a known disagreement mixed into the root digest would
    mask every new one behind it.  They are still watched, as observations the
    registry can account for.
    """
    e.line(indent + "DevilFeed(UInt64(Length(%s)));" % expr)
    e.line(indent + "DevilFeed(UInt64(StringElementSize(%s)));" % expr)
    e.line(indent + "DevilFeed(UInt64(Ord(Pointer(%s) <> nil)));" % expr)
    e.line(indent + "DevilNote('%s', UInt64(StringCodePage(%s)));" % (name, expr))


def layer_chain(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Long nested passes: the value must survive every mechanism on the way."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    e.line("type")
    e.line("  EDvlChainBoom = class(Exception);")
    e.line("  { every gate touches this, so no step is straight-line code }")
    e.line("  TDvlChainScope = record")
    e.line("    Touched: Int64;")
    e.line("    Name: AnsiString;")
    e.line("  end;")
    e.line()
    e.line("var")
    e.line("  DvlChainSerial: Integer;")
    e.line("  DvlChainScope: TDvlChainScope;")
    e.line("  { how many times two chains may still call into each other }")
    e.line("  DvlChainBudget: Integer = 2;")
    e.line()
    foreign = [proc for layer in CHAIN_FOREIGN_LAYERS
               for proc in EMITTED_FORMS.get(layer, ())]
    e.line()
    for index in range(start, start + count):
        name = "dvl-chain-%05d" % index
        proc = "DvlChain%05d" % index
        tag = "%05d" % index
        depth = rng.randrange(12, 41)
        seed = (index * 2654435761 + 12345) & 0x7FFFFFFF

        # a fixed stage list makes a failing chain bisectable by hand
        forced = os.environ.get("DEVIL_CHAIN_STAGES")
        stages: list[str] = []
        if forced:
            stages = [x for x in forced.split(",") if x]
        else:
            under_thread = False
            # every branching stage runs everything below it twice, so a few of
            # them turn one chain into thousands of calls: two is the ceiling
            branches = 0
            for _ in range(depth):
                available = [s for s in CHAIN_STAGES
                             if not (under_thread
                                     and s in CHAIN_UNSAFE_UNDER_THREAD)
                             and not (branches >= 2 and s in CHAIN_BRANCHING)
                             and not (index == start
                                      and s in CHAIN_NEEDS_SIBLING)
                             and not (not foreign and s in CHAIN_NEEDS_FOREIGN)]
                stage = rng.choice(available)
                stages.append(stage)
                if stage in CHAIN_BRANCHING:
                    branches += 1
                if stage in CHAIN_THREADED:
                    under_thread = True
        # the innermost stage returns the value it was given
        e.line("function DvlLink%s_%d(X: Int64): Int64; forward;"
               % (tag, len(stages)))
        e.line()
        e.line("function DvlLink%s_%d(X: Int64): Int64;" % (tag, len(stages)))
        e.line("begin")
        e.line("  { the sentinel turns the whole pass into an unwind }")
        e.line("  If X = %d then" % CHAIN_SENTINEL)
        e.line("    raise EDvlChainBoom.Create('boom');")
        e.line("  Result := X;")
        e.line("end;")
        e.line()

        for level in range(len(stages) - 1, -1, -1):
            stage = stages[level]
            inner = "DvlLink%s_%d" % (tag, level + 1)
            fn = "DvlLink%s_%d" % (tag, level)
            mark = chr(ord('a') + (level % 26))

            if stage == "string-roundtrip":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  S: AnsiString;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  S := AnsiString(IntToStr(%s(X)));" % inner)
                e.line("  Result := StrToInt64(string(S));")
                e.line("end;")

            elif stage == "wide-record":
                e.line("type")
                e.line("  TDvlWide%s_%d = record" % (tag, level))
                e.line("    A, B, C, D, E: Int64;")
                e.line("  end;")
                e.line()
                e.line("function DvlPass%s_%d(R: TDvlWide%s_%d): Int64;"
                       % (tag, level, tag, level))
                e.line("begin")
                e.line("  Result := R.C;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  R: TDvlWide%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  R.A := -1;")
                e.line("  R.B := -2;")
                e.line("  R.C := %s(X);" % inner)
                e.line("  R.D := -3;")
                e.line("  R.E := -4;")
                e.line("  { too wide for a register: it travels as a hidden copy }")
                e.line("  Result := DvlPass%s_%d(R);" % (tag, level))
                e.line("end;")

            elif stage == "generic-box":
                e.line("type")
                e.line("  TDvlBoxC%s_%d<T> = record" % (tag, level))
                e.line("    Value: T;")
                e.line("  end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Box: TDvlBoxC%s_%d<Int64>;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Box.Value := %s(X);" % inner)
                e.line("  Result := Box.Value;")
                e.line("end;")

            elif stage == "interface-method":
                e.line("type")
                e.line("  IDvlCarry%s_%d = interface" % (tag, level))
                e.line("    ['{6C%06X-0000-0000-00%02X-000000000001}']"
                       % (index % 0xFFFFFF, level))
                e.line("    function Take(X: Int64): Int64;")
                e.line("  end;")
                e.line()
                e.line("  TDvlCarry%s_%d = class(TInterfacedObject, IDvlCarry%s_%d)"
                       % (tag, level, tag, level))
                e.line("    function Take(X: Int64): Int64;")
                e.line("  end;")
                e.line()
                e.line("function TDvlCarry%s_%d.Take(X: Int64): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := %s(X);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carry: IDvlCarry%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carry := TDvlCarry%s_%d.Create;" % (tag, level))
                e.line("  { the rest of the chain runs inside a virtual call }")
                e.line("  Result := Carry.Take(X);")
                e.line("end;")

            elif stage == "closure-capture":
                e.line("type")
                e.line("  TDvlStep%s_%d = reference to function(X: Int64): Int64;"
                       % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Step: TDvlStep%s_%d;" % (tag, level))
                e.line("  Captured: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Captured := X;")
                e.line("  Step :=")
                e.line("    function(Y: Int64): Int64")
                e.line("    begin")
                e.line("      { reads the captured variable, not the parameter }")
                e.line("      Result := %s(Captured);" % inner)
                e.line("    end;")
                e.line("  Result := Step(0);")
                e.line("end;")

            elif stage == "dynamic-array":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Data, Slice: System.TArray<Int64>;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  SetLength(Data, 4);")
                e.line("  Data[2] := %s(X);" % inner)
                e.line("  Slice := Copy(Data, 2, 1);")
                e.line("  Data[2] := -1;")
                e.line("  { Copy detached the buffer, so the source write must "
                       "not reach the slice }")
                e.line("  Result := Slice[0];")
                e.line("end;")

            elif stage == "variant-carrier":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  V: Variant;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  V := %s(X);" % inner)
                e.line("  Result := V;")
                e.line("end;")

            elif stage == "worker-thread":
                e.line("type")
                e.line("  TDvlWorker%s_%d = class(TThread)" % (tag, level))
                e.line("  public")
                e.line("    Input, Output: Int64;")
                e.line("    procedure Execute; override;")
                e.line("  end;")
                e.line()
                e.line("procedure TDvlWorker%s_%d.Execute;" % (tag, level))
                e.line("begin")
                e.line("  { the rest of the chain runs on another thread }")
                e.line("  Output := %s(Input);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Worker: TDvlWorker%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Worker := TDvlWorker%s_%d.Create(True);" % (tag, level))
                e.line("  try")
                e.line("    Worker.FreeOnTerminate := False;")
                e.line("    Worker.Input := X;")
                e.line("    Worker.Start;")
                e.line("    Worker.WaitFor;")
                e.line("    Result := Worker.Output;")
                e.line("  finally")
                e.line("    Worker.Free;")
                e.line("  end;")
                e.line("end;")

            elif stage == "typed-file":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  F: file of Int64;")
                e.line("  Path: string;")
                e.line("  Value: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { unique per call: a branching stage above may run "
                       "this one twice, and on two threads }")
                e.line("  Path := IncludeTrailingPathDelimiter(GetCurrentDir) + "
                       "'dvl_chain_%s_%d_' + IntToStr(AtomicIncrement("
                       "DvlChainSerial)) + '.tmp';" % (tag, level))
                e.line("  Value := %s(X);" % inner)
                e.line("  AssignFile(F, Path);")
                e.line("  Rewrite(F);")
                e.line("  try")
                e.line("    Write(F, Value);")
                e.line("    Seek(F, 0);")
                e.line("    Value := 0;")
                e.line("    Read(F, Value);")
                e.line("  finally")
                e.line("    CloseFile(F);")
                e.line("    If FileExists(Path) then")
                e.line("      DeleteFile(Path);")
                e.line("  end;")
                e.line("  Result := Value;")
                e.line("end;")

            elif stage == "assembler-hop":
                e.line("function DvlEchoA%s_%d(X: Int64): Int64; assembler;"
                       % (tag, level))
                e.line("asm")
                e.line("  {$ifdef MSWINDOWS}")
                e.line("  MOV RAX, RCX")
                e.line("  {$else}")
                e.line("  MOV RAX, RDI")
                e.line("  {$endif}")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { through hand-written code the optimizer cannot see "
                       "into }")
                e.line("  Result := DvlEchoA%s_%d(%s(X));" % (tag, level, inner))
                e.line("end;")

            elif stage == "raised-exception":
                e.line("type")
                e.line("  EDvlCarry%s_%d = class(Exception)" % (tag, level))
                e.line("  public")
                e.line("    Payload: Int64;")
                e.line("  end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Failure: EDvlCarry%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  try")
                e.line("    Failure := EDvlCarry%s_%d.Create('carry');" % (tag, level))
                e.line("    Failure.Payload := %s(X);" % inner)
                e.line("    { the value travels inside the exception object "
                       "through the unwind }")
                e.line("    raise Failure;")
                e.line("  except")
                e.line("    on E: EDvlCarry%s_%d do" % (tag, level))
                e.line("      Result := E.Payload;")
                e.line("  end;")
                e.line("end;")

            elif stage == "inline-hop":
                e.line("function DvlThin%s_%d(X: Int64): Int64; inline;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := X;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Result := DvlThin%s_%d(%s(DvlThin%s_%d(X)));"
                       % (tag, level, inner, tag, level))
                e.line("end;")

            elif stage == "pointer-view":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Buffer: array[0..7] of Byte;")
                e.line("  P: PInt64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  P := PInt64(@Buffer[0]);")
                e.line("  { written as one type, read back through another }")
                e.line("  P^ := %s(X);" % inner)
                e.line("  Result := PInt64(@Buffer[0])^;")
                e.line("end;")

            elif stage == "method-pointer":
                e.line("type")
                e.line("  TDvlHolderM%s_%d = class" % (tag, level))
                e.line("  public")
                e.line("    function Take(X: Int64): Int64;")
                e.line("  end;")
                e.line("  TDvlTakeM%s_%d = function(X: Int64): Int64 of object;"
                       % (tag, level))
                e.line()
                e.line("function TDvlHolderM%s_%d.Take(X: Int64): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := %s(X);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Holder: TDvlHolderM%s_%d;" % (tag, level))
                e.line("  Take: TDvlTakeM%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Holder := TDvlHolderM%s_%d.Create;" % (tag, level))
                e.line("  try")
                e.line("    Take := Holder.Take;")
                e.line("    Result := Take(X);")
                e.line("  finally")
                e.line("    Holder.Free;")
                e.line("  end;")
                e.line("end;")

            elif stage == "open-array":
                e.line("function DvlFirst%s_%d(const Items: array of Int64): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := Items[High(Items)];")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Result := DvlFirst%s_%d([-1, -2, %s(X)]);"
                       % (tag, level, inner))
                e.line("end;")

            elif stage == "rtti-value":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Value: TValue;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Value := TValue.From<Int64>(%s(X));" % inner)
                e.line("  Result := Value.AsInt64;")
                e.line("end;")

            elif stage == "finally-transfer":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  try")
                e.line("    Exit;")
                e.line("  finally")
                e.line("    { the result is chosen after Exit already left }")
                e.line("    Result := %s(X);" % inner)
                e.line("  end;")
                e.line("end;")

            elif stage == "nested-var-param":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line()
                e.line("  procedure Level3(var Slot: Int64);")
                e.line("  begin")
                e.line("    Slot := %s(Slot);" % inner)
                e.line("  end;")
                e.line()
                e.line("  procedure Level2(var Slot: Int64);")
                e.line("  begin")
                e.line("    Level3(Slot);")
                e.line("  end;")
                e.line()
                e.line("  procedure Level1(var Slot: Int64);")
                e.line("  begin")
                e.line("    Level2(Slot);")
                e.line("  end;")
                e.line()
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Result := X;")
                e.line("  { three nested frames all writing through one "
                       "reference }")
                e.line("  Level1(Result);")
                e.line("end;")

            elif stage == "case-dispatch":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Selector: Integer;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Selector := X and 3;")
                e.line("  case Selector of")
                e.line("    0: Result := %s(X);" % inner)
                e.line("    1: Result := %s(X);" % inner)
                e.line("    2: Result := %s(X);" % inner)
                e.line("  else")
                e.line("    Result := %s(X);" % inner)
                e.line("  end;")
                e.line("end;")

            elif stage == "set-of-bits":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Bits: set of 0..63;")
                e.line("  Value: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Value := %s(X);" % inner)
                e.line("  Bits := [];")
                e.line("  for var I := 0 to 63 do")
                e.line("    If (Value shr I) and 1 = 1 then")
                e.line("      Include(Bits, I);")
                e.line("  Result := 0;")
                e.line("  { the value is rebuilt one membership test at a time }")
                e.line("  for var I := 63 downto 0 do")
                e.line("    If I in Bits then")
                e.line("      Result := Result or (Int64(1) shl I);")
                e.line("end;")

            elif stage == "utf8-detour":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Wide: string;")
                e.line("  Bytes: UTF8String;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Wide := IntToStr(%s(X));" % inner)
                e.line("  Bytes := UTF8String(Wide);")
                e.line("  { out through UTF-8 and back through UTF-16 }")
                e.line("  Result := StrToInt64(string(Bytes));")
                e.line("end;")

            elif stage == "managed-record":
                e.line("type")
                e.line("  TDvlHold%s_%d = record" % (tag, level))
                e.line("    Text: AnsiString;")
                e.line("    Guard: IInterface;")
                e.line("    Value: Int64;")
                e.line("  end;")
                e.line()
                e.line("function DvlCopyR%s_%d(R: TDvlHold%s_%d): Int64;"
                       % (tag, level, tag, level))
                e.line("begin")
                e.line("  Result := R.Value;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  R: TDvlHold%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  R.Text := AnsiString('carry');")
                e.line("  { a plain counted object: the tagged one would write "
                       "its own mark into the trail on release }")
                e.line("  R.Guard := TInterfacedObject.Create;")
                e.line("  R.Value := %s(X);" % inner)
                e.line("  { a record with two managed fields, copied by value }")
                e.line("  Result := DvlCopyR%s_%d(R);" % (tag, level))
                e.line("end;")

            elif stage == "class-var-hop":
                e.line("type")
                e.line("  TDvlSlot%s_%d = class" % (tag, level))
                e.line("  public")
                e.line("    class var Slot: Int64;")
                e.line("    class function Take(X: Int64): Int64; static;")
                e.line("  end;")
                e.line()
                e.line("class function TDvlSlot%s_%d.Take(X: Int64): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  Slot := %s(X);" % inner)
                e.line("  Result := Slot;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  TDvlSlot%s_%d.Slot := -1;" % (tag, level))
                e.line("  Result := TDvlSlot%s_%d.Take(X);" % (tag, level))
                e.line("end;")

            elif stage == "woven-carrier":
                e.line("type")
                e.line("  TDvlWLeaf%s_%d = record" % (tag, level))
                e.line("    Text: AnsiString;")
                e.line("    Guard: IInterface;")
                e.line("    Value: Int64;")
                e.line("  end;")
                e.line("  TDvlWBox%s_%d<T> = record" % (tag, level))
                e.line("    Slot: T;")
                e.line("    Marker: Integer;")
                e.line("  end;")
                e.line("  TDvlWRow%s_%d = array[0..1] of "
                       "TDvlWBox%s_%d<TDvlWLeaf%s_%d>;"
                       % (tag, level, tag, level, tag, level))
                e.line("  TDvlWTree%s_%d = record" % (tag, level))
                e.line("    Rows: TDvlWRow%s_%d;" % (tag, level))
                e.line("    Depth: Integer;")
                e.line("  end;")
                e.line()
                e.line("function DvlWReach%s_%d(const Tree: TDvlWTree%s_%d): Int64;"
                       % (tag, level, tag, level))
                e.line("begin")
                e.line("  Result := Tree.Rows[1].Slot.Value;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Tree, Copy: TDvlWTree%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Tree.Depth := %d;" % level)
                e.line("  Tree.Rows[0].Slot.Text := AnsiString('left');")
                e.line("  Tree.Rows[1].Slot.Text := AnsiString('right');")
                e.line("  Tree.Rows[1].Slot.Guard := TInterfacedObject.Create;")
                e.line("  { four type levels deep - array of generic of managed "
                       "record - and the value has to survive a copy of the "
                       "whole tree }")
                e.line("  Tree.Rows[1].Slot.Value := %s(X);" % inner)
                e.line("  Copy := Tree;")
                e.line("  Tree.Rows[1].Slot.Value := -1;")
                e.line("  Result := DvlWReach%s_%d(Copy);" % (tag, level))
                e.line("end;")

            elif stage == "metamorphic-fork":
                e.line("function DvlForkA%s_%d(X: Int64): Int64;" % (tag, level))
                e.line("var")
                e.line("  Data: array[0..3] of Int64;")
                e.line("begin")
                e.line("  for var I := 0 to 3 do")
                e.line("    Data[I] := 0;")
                e.line("  Data[2] := X;")
                e.line("  Result := 0;")
                e.line("  for var V in Data do")
                e.line("    Result := Result + V;")
                e.line("end;")
                e.line()
                e.line("function DvlForkB%s_%d(X: Int64): Int64;" % (tag, level))
                e.line("var")
                e.line("  Data: System.TArray<Int64>;")
                e.line("  I: Integer;")
                e.line("begin")
                e.line("  SetLength(Data, 4);")
                e.line("  Data[2] := X;")
                e.line("  Result := 0;")
                e.line("  I := High(Data);")
                e.line("  while I >= 0 do")
                e.line("  begin")
                e.line("    Result := Result + Data[I];")
                e.line("    Dec(I);")
                e.line("  end;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried, ByStatic, ByDynamic: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the same meaning written two ways, mid-chain: if "
                       "they disagree the value is destroyed }")
                e.line("  ByStatic := DvlForkA%s_%d(Carried);" % (tag, level))
                e.line("  ByDynamic := DvlForkB%s_%d(Carried);" % (tag, level))
                e.line("  If ByStatic = ByDynamic then")
                e.line("    Result := ByStatic")
                e.line("  else")
                e.line("    Result := not Carried;")
                e.line("end;")

            elif stage == "generic-relay":
                e.line("type")
                e.line("  TDvlRelay%s_%d<T> = class" % (tag, level))
                e.line("  public")
                e.line("    Held: T;")
                e.line("    function Pass(const Value: T): T;")
                e.line("  end;")
                e.line()
                e.line("function TDvlRelay%s_%d<T>.Pass(const Value: T): T;"
                       % (tag, level))
                e.line("begin")
                e.line("  Held := Value;")
                e.line("  Result := Held;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Relay: TDvlRelay%s_%d<Int64>;" % (tag, level))
                e.line("  Strings: TDvlRelay%s_%d<AnsiString>;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Relay := TDvlRelay%s_%d<Int64>.Create;" % (tag, level))
                e.line("  Strings := TDvlRelay%s_%d<AnsiString>.Create;"
                       % (tag, level))
                e.line("  try")
                e.line("    { two specializations of one generic class alive at "
                       "once, one of them managed }")
                e.line("    Strings.Pass(AnsiString('relay'));")
                e.line("    Result := Relay.Pass(%s(X));" % inner)
                e.line("  finally")
                e.line("    Strings.Free;")
                e.line("    Relay.Free;")
                e.line("  end;")
                e.line("end;")

            elif stage == "dead-store-leak":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Scratch: Int64;")
                e.line("  Escape: PInt64;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { looks like a dead store: nobody reads Scratch by "
                       "name again }")
                e.line("  Scratch := Carried;")
                e.line("  Escape := @Scratch;")
                e.line("  Scratch := Carried xor $5A5A5A5A;")
                e.line("  Scratch := Carried;")
                e.line("  { but the address left, and the thread comes back }")
                e.line("  DevilFeed(UInt64(Escape^));")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "hoist-leak":
                rounds = rng.randrange(3, 7)
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Bound, Total: Int64;")
                e.line("  Moving: PInt64;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  Bound := 4;")
                e.line("  Moving := @Bound;")
                e.line("  Total := 0;")
                e.line("  { the bound looks invariant and the body looks "
                       "hoistable, but the pointer writes the bound }")
                e.line("  for var I := 1 to %d do" % rounds)
                e.line("  begin")
                e.line("    Total := Total + Bound;")
                e.line("    Moving^ := Bound + 1;")
                e.line("  end;")
                e.line("  DevilFeed(UInt64(Total));")
                e.line("  DevilFeed(UInt64(Bound));")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "unreachable-leak":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried, Shadow: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  Shadow := 0;")
                e.line("  { the condition is opaque, so neither branch may be "
                       "assumed away - and both feed the stream }")
                e.line("  If OpaqueI(Carried) = Carried then")
                e.line("    Shadow := Carried")
                e.line("  else")
                e.line("    Shadow := not Carried;")
                e.line("  DevilFeed(UInt64(Shadow));")
                e.line("  { and a branch that really is unreachable must not "
                       "contribute anything }")
                e.line("  If OpaqueU(1) = 0 then")
                e.line("    DevilFeed(UInt64($DEADBEEF));")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "field-leak":
                e.line("type")
                e.line("  TDvlLeak%s_%d = class" % (tag, level))
                e.line("  public")
                e.line("    Slot: Int64;")
                e.line("    Shadow: Int64;")
                e.line("  end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Holder: TDvlLeak%s_%d;" % (tag, level))
                e.line("  Alias: PInt64;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Holder := TDvlLeak%s_%d.Create;" % (tag, level))
                e.line("  try")
                e.line("    Carried := %s(X);" % inner)
                e.line("    Holder.Slot := Carried;")
                e.line("    Alias := @Holder.Slot;")
                e.line("    { the field and the pointer name one location: a "
                       "write through either must be seen by the other }")
                e.line("    Alias^ := Carried xor 1;")
                e.line("    DevilFeed(UInt64(Holder.Slot));")
                e.line("    Holder.Slot := Carried;")
                e.line("    DevilFeed(UInt64(Alias^));")
                e.line("  finally")
                e.line("    Holder.Free;")
                e.line("  end;")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "closure-leak":
                e.line("type")
                e.line("  TDvlLeakStep%s_%d = reference to procedure;"
                       % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Captured, Carried: Int64;")
                e.line("  Step: TDvlLeakStep%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  Captured := Carried;")
                e.line("  { the closure looks unused after this point }")
                e.line("  Step :=")
                e.line("    procedure")
                e.line("    begin")
                e.line("      Captured := Captured xor 1;")
                e.line("    end;")
                e.line("  Step();")
                e.line("  Step();")
                e.line("  { two flips return the value, unless one was lost }")
                e.line("  DevilFeed(UInt64(Captured));")
                e.line("  DevilCheckU('%s-closure-leak', "
                       "UInt64(Ord(Captured = Carried)), 1);" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "fold-mirror":
                width = rng.choice(("Byte", "SmallInt", "Cardinal", "Integer"))
                literal = (index * 2654435761) & 0x7FFF
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Folded, Opaque: %s;" % width)
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { the same narrowing twice: once where the compiler "
                       "sees constants, once where it cannot }")
                e.line("  Folded := %s(%d);" % (width, literal))
                e.line("  Opaque := %s(OpaqueU(UInt64(%d)));" % (width, literal))
                e.line("  DevilFeed(UInt64(Folded));")
                e.line("  DevilFeed(UInt64(Opaque));")
                e.line("  DevilCheckU('%s-fold-mirror', "
                       "UInt64(Ord(Folded = Opaque)), 1);" % name)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { and again after the transfer, on the carried value }")
                e.line("  Folded := %s(Carried and $7FFF);" % width)
                e.line("  Opaque := %s(OpaqueI(Carried) and $7FFF);" % width)
                e.line("  DevilFeed(UInt64(Folded));")
                e.line("  DevilFeed(UInt64(Opaque));")
                e.line("  DevilCheckU('%s-fold-mirror-carried', "
                       "UInt64(Ord(Folded = Opaque)), 1);" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "inline-mirror":
                e.line("{$ifdef FPC}{$push}{$optimization noautoinline}{$endif}")
                e.line("function DvlSlow%s_%d(X: Int64): Int64;" % (tag, level))
                e.line("var")
                e.line("  Narrow: Integer;")
                e.line("begin")
                e.line("  Narrow := Integer(X and $7FFFFFFF);")
                e.line("  Result := Int64(Cardinal(Narrow)) + (X shr 32);")
                e.line("end;")
                e.line("{$ifdef FPC}{$pop}{$endif}")
                e.line()
                e.line("function DvlFast%s_%d(X: Int64): Int64; inline;"
                       % (tag, level))
                e.line("var")
                e.line("  Narrow: Integer;")
                e.line("begin")
                e.line("  Narrow := Integer(X and $7FFFFFFF);")
                e.line("  Result := Int64(Cardinal(Narrow)) + (X shr 32);")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried, Slow, Fast: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { one body, two fates: pasted by the optimizer and "
                       "kept as a call }")
                e.line("  Slow := DvlSlow%s_%d(Carried);" % (tag, level))
                e.line("  Fast := DvlFast%s_%d(Carried);" % (tag, level))
                e.line("  DevilFeed(UInt64(Slow));")
                e.line("  DevilFeed(UInt64(Fast));")
                e.line("  DevilCheckU('%s-inline-mirror', "
                       "UInt64(Ord(Slow = Fast)), 1);" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "specialization-mirror":
                e.line("type")
                e.line("  TDvlLocal%s_%d<T> = record" % (tag, level))
                e.line("    Value: T;")
                e.line("    function Widen: Int64;")
                e.line("  end;")
                e.line()
                e.line("function TDvlLocal%s_%d<T>.Widen: Int64;" % (tag, level))
                e.line("begin")
                e.line("  Result := SizeOf(T);")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Here: TDvlLocal%s_%d<Int64>;" % (tag, level))
                e.line("  Imported: TDvlCarrier<Int64>;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  Here.Value := Carried;")
                e.line("  Imported.Put(Carried);")
                e.line("  { one generic specialized in this file, one replayed "
                       "out of a PPU, on the same argument type }")
                e.line("  DevilFeed(UInt64(Here.Widen));")
                e.line("  DevilFeed(UInt64(Imported.Width));")
                e.line("  DevilCheckU('%s-specialization-mirror', "
                       "UInt64(Ord(Here.Value = Imported.Get)), 1);" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "passport-check":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                emit_passport(e, "X")
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the same passport after the transfer: anything the "
                       "floor washed off shows up in the root digest }")
                emit_passport(e, "Carried")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "string-passport":
                e.line("type")
                e.line("  TDvlPassCp%s_%d = type AnsiString(1251);" % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Native: TDvlPassCp%s_%d;" % (tag, level))
                e.line("  Wide: string;")
                e.line("  Bytes: UTF8String;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Wide := IntToStr(X) + %s;" % "#$0416#$0438")
                e.line("  Native := TDvlPassCp%s_%d(Wide);" % (tag, level))
                e.line("  Bytes := UTF8String(Wide);")
                e.line("  { three carriers of one text, each with its own "
                       "codepage, element width and buffer }")
                emit_string_passport(e, "%s-cp-wide-before" % name, "Wide")
                emit_string_passport(e, "%s-cp-native-before" % name, "Native")
                emit_string_passport(e, "%s-cp-bytes-before" % name, "Bytes")
                e.line("  Carried := %s(X);" % inner)
                e.line("  { and the same three after the transfer }")
                emit_string_passport(e, "%s-cp-wide-after" % name, "Wide")
                emit_string_passport(e, "%s-cp-native-after" % name, "Native")
                emit_string_passport(e, "%s-cp-bytes-after" % name, "Bytes")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "directive-passport":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Narrow: Byte;")
                e.line("  Raised: Integer;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { which checks are in force right here is itself a "
                       "passenger: it can be washed off by a transfer }")
                e.line("  Raised := 0;")
                e.line("{$ifdef FPC}{$push}{$endif}{$R+}{$Q+}")
                e.line("  try")
                e.line("    Narrow := Byte(OpaqueU(UInt64(300)));")
                e.line("    DevilFeed(UInt64(Narrow));")
                e.line("  except")
                e.line("    Raised := 1;")
                e.line("  end;")
                e.line("{$ifdef FPC}{$pop}{$else}{$R-}{$Q-}{$endif}")
                e.line("  DevilFeed(UInt64(Cardinal(Raised)));")
                e.line("  Raised := 0;")
                e.line("{$ifdef FPC}{$push}{$endif}{$R-}{$Q-}")
                e.line("  try")
                e.line("    Narrow := Byte(OpaqueU(UInt64(300)));")
                e.line("    DevilFeed(UInt64(Narrow));")
                e.line("  except")
                e.line("    Raised := 1;")
                e.line("  end;")
                e.line("{$ifdef FPC}{$pop}{$else}{$R-}{$Q-}{$endif}")
                e.line("  DevilFeed(UInt64(Cardinal(Raised)));")
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "foreign-form":
                target_proc = rng.choice(foreign)
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { a real form from another layer, with all its own "
                       "assertions, executed from inside this chain }")
                e.line("  %s;" % target_proc)
                e.line("  Result := %s(X);" % inner)
                e.line("end;")

            elif stage == "mutual-chain":
                sibling = "DvlLink%05d_0" % (index - 1)
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Mine: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Mine := %s(X);" % inner)
                e.line("  { two chains calling into each other under a budget: "
                       "the stack interleaves two independent sets of "
                       "mechanisms }")
                e.line("  If DvlChainBudget > 0 then")
                e.line("  begin")
                e.line("    Dec(DvlChainBudget);")
                e.line("    try")
                e.line("      If %s(Mine) <> Mine then" % sibling)
                e.line("        Mine := not Mine;")
                e.line("    finally")
                e.line("      Inc(DvlChainBudget);")
                e.line("    end;")
                e.line("  end;")
                e.line("  Result := Mine;")
                e.line("end;")

            elif stage == "tree-walk":
                e.line("type")
                e.line("  TDvlLeafW%s_%d = record" % (tag, level))
                e.line("    Text: AnsiString;")
                e.line("    Value: Int64;")
                e.line("  end;")
                e.line("  TDvlMidW%s_%d<T> = record" % (tag, level))
                e.line("    Items: array[0..2] of T;")
                e.line("    Chosen: Integer;")
                e.line("  end;")
                e.line("  TDvlTopW%s_%d = record" % (tag, level))
                e.line("    Levels: TDvlMidW%s_%d<TDvlMidW%s_%d<TDvlLeafW%s_%d>>;"
                       % (tag, level, tag, level, tag, level))
                e.line("  end;")
                e.line()
                e.line("function DvlWalk%s_%d(const Top: TDvlTopW%s_%d): Int64;"
                       % (tag, level, tag, level))
                e.line("var")
                e.line("  Outer: Integer;")
                e.line("  Inner: Integer;")
                e.line("begin")
                e.line("  Result := 0;")
                e.line("  Outer := Top.Levels.Chosen;")
                e.line("  Inner := Top.Levels.Items[Outer].Chosen;")
                e.line("  { the value sits three type levels down and is reached "
                       "through two runtime indices }")
                e.line("  Result := Top.Levels.Items[Outer].Items[Inner].Value;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Top, Copy: TDvlTopW%s_%d;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Top.Levels.Chosen := 1;")
                e.line("  Top.Levels.Items[1].Chosen := 2;")
                e.line("  Top.Levels.Items[1].Items[2].Text := AnsiString('leaf');")
                e.line("  Top.Levels.Items[1].Items[2].Value := %s(X);" % inner)
                e.line("  { copying the whole tree must copy the managed leaf "
                       "with it }")
                e.line("  Copy := Top;")
                e.line("  Top.Levels.Items[1].Items[2].Value := -1;")
                e.line("  Result := DvlWalk%s_%d(Copy);" % (tag, level))
                e.line("end;")

            elif stage == "generic-method":
                e.line("type")
                e.line("  TDvlGm%s_%d = class" % (tag, level))
                e.line("  public")
                e.line("    class function Pass<T>(const Value: T): T; static;")
                e.line("  end;")
                e.line()
                e.line("class function TDvlGm%s_%d.Pass<T>(const Value: T): T;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := Value;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Text: AnsiString;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { a generic method, specialized twice in one routine, "
                       "one of them on a managed type }")
                e.line("  Text := TDvlGm%s_%d.Pass<AnsiString>("
                       "AnsiString('through'));" % (tag, level))
                e.line("  If Length(Text) = 7 then")
                e.line("    Result := TDvlGm%s_%d.Pass<Int64>(%s(X))"
                       % (tag, level, inner))
                e.line("  else")
                e.line("    Result := not X;")
                e.line("end;")

            elif stage == "constrained-generic":
                e.line("type")
                e.line("  TDvlHolderBase%s_%d = class" % (tag, level))
                e.line("  public")
                e.line("    Slot: Int64;")
                e.line("    constructor Create; virtual;")
                e.line("  end;")
                e.line("  TDvlKeeper%s_%d<T: TDvlHolderBase%s_%d, constructor> = "
                       "record" % (tag, level, tag, level))
                e.line("    function Build(Value: Int64): Int64;")
                e.line("  end;")
                e.line()
                e.line("constructor TDvlHolderBase%s_%d.Create;" % (tag, level))
                e.line("begin")
                e.line("  inherited Create;")
                e.line("  Slot := 0;")
                e.line("end;")
                e.line()
                e.line("function TDvlKeeper%s_%d<T>.Build(Value: Int64): Int64;"
                       % (tag, level))
                e.line("var")
                e.line("  Item: T;")
                e.line("begin")
                e.line("  { the constraint is what lets the specialization call "
                       "the constructor at all }")
                e.line("  Item := T.Create;")
                e.line("  try")
                e.line("    Item.Slot := Value;")
                e.line("    Result := Item.Slot;")
                e.line("  finally")
                e.line("    Item.Free;")
                e.line("  end;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Keeper: TDvlKeeper%s_%d<TDvlHolderBase%s_%d>;"
                       % (tag, level, tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Result := Keeper.Build(%s(X));" % inner)
                e.line("end;")

            elif stage == "nested-specialization":
                e.line("type")
                e.line("  TDvlCell%s_%d<T> = record" % (tag, level))
                e.line("    Value: T;")
                e.line("  end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Deep: TDvlCell%s_%d<TDvlCell%s_%d<TDvlCell%s_%d<Int64>>>;"
                       % (tag, level, tag, level, tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { three specializations of one generic, nested, and "
                       "the value has to reach the innermost }")
                e.line("  Deep.Value.Value.Value := %s(X);" % inner)
                e.line("  Result := Deep.Value.Value.Value;")
                e.line("end;")

            elif stage == "generic-thread":
                e.line("type")
                e.line("  TDvlGw%s_%d<T> = class(TThread)" % (tag, level))
                e.line("  public")
                e.line("    Input, Output: T;")
                e.line("    procedure Execute; override;")
                e.line("  end;")
                e.line()
                e.line("procedure TDvlGw%s_%d<T>.Execute;" % (tag, level))
                e.line("begin")
                e.line("  Output := Input;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Worker: TDvlGw%s_%d<Int64>;" % (tag, level))
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { a generic class that is also a thread: the "
                       "specialization has to survive being started }")
                e.line("  Worker := TDvlGw%s_%d<Int64>.Create(True);" % (tag, level))
                e.line("  try")
                e.line("    Worker.FreeOnTerminate := False;")
                e.line("    Worker.Input := %s(X);" % inner)
                e.line("    Worker.Start;")
                e.line("    Worker.WaitFor;")
                e.line("    Result := Worker.Output;")
                e.line("  finally")
                e.line("    Worker.Free;")
                e.line("  end;")
                e.line("end;")

            elif stage == "varrec-bait":
                e.line("function DvlKind%s_%d(const A: array of const): Integer;"
                       % (tag, level))
                e.line("begin")
                e.line("  Result := A[0].VType;")
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the shape from dvl-0012: which tag a character "
                       "literal gets when Char is UTF-16 }")
                e.line("  DevilNoteLoose('%s-varrec-ascii', "
                       "UInt64(Cardinal(DvlKind%s_%d(['x']))));" % (name, tag, level))
                e.line("  DevilNoteLoose('%s-varrec-wide', "
                       "UInt64(Cardinal(DvlKind%s_%d([#$0416]))));"
                       % (name, tag, level))
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "variant-literal-bait":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried: Int64;")
                e.line("  V: Variant;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the shapes from dvl-0015 and dvl-0016: how a literal "
                       "is typed on its way into a Variant }")
                e.line("  V := 100;")
                e.line("  DevilNoteLoose('%s-variant-small', UInt64(VarType(V)));" % name)
                e.line("  V := 1.5;")
                e.line("  DevilNoteLoose('%s-variant-real', UInt64(VarType(V)));" % name)
                e.line("  V := Carried;")
                e.line("  Result := V;")
                e.line("end;")

            elif stage == "unicode-cast-bait":
                e.line("type")
                e.line("  TDvlBaitCp%s_%d = type AnsiString(1251);" % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried: Int64;")
                e.line("  Native: TDvlBaitCp%s_%d;" % (tag, level))
                e.line("  Reinterpreted: UTF8String;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the shape from dvl-0013, on text that actually "
                       "differs between the two encodings }")
                e.line("  Native := TDvlBaitCp%s_%d(string(#$0416#$0438));"
                       % (tag, level))
                e.line("  Reinterpreted := UTF8String(Native);")
                e.line("  DevilNoteLoose('%s-cast-length', "
                       "UInt64(Length(Reinterpreted)));" % name)
                e.line("  DevilNoteLoose('%s-cast-first-byte', "
                       "UInt64(Ord(Reinterpreted[1])));" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "finalization-order-bait":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carried: Int64;")
                e.line()
                e.line("  procedure Scoped;")
                e.line("  var")
                e.line("    First, Second, Third: IInterface;")
                e.line("  begin")
                e.line("    First := TDvlTagged.Create('1');")
                e.line("    Second := TDvlTagged.Create('2');")
                e.line("    Third := TDvlTagged.Create('3');")
                e.line("    { the shape from dvl-0003: the order these are "
                       "released while an exception unwinds }")
                e.line("    raise Exception.Create('unwind');")
                e.line("  end;")
                e.line()
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  DevilTrailReset;")
                e.line("  try")
                e.line("    Scoped;")
                e.line("  except")
                e.line("  end;")
                e.line("  DevilNoteText('%s-release-order', DevilTrail);" % name)
                e.line("  Result := Carried;")
                e.line("end;")

            elif stage == "tiny-effect-bait":
                e.line("var")
                e.line("  DvlBait%s_%d: Integer;" % (tag, level))
                e.line()
                e.line("function DvlTick%s_%d: Integer; inline;" % (tag, level))
                e.line("begin")
                e.line("  Inc(DvlBait%s_%d);" % (tag, level))
                e.line("  Result := DvlBait%s_%d;" % (tag, level))
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Sum: Integer;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  DvlBait%s_%d := 0;" % (tag, level))
                e.line("  { the shape from dvl-0018, small enough to tempt: two "
                       "calls of a tiny state-changing routine in one "
                       "expression }")
                e.line("  Sum := DvlTick%s_%d + DvlTick%s_%d;"
                       % (tag, level, tag, level))
                e.line("  { which operand is evaluated first is not fixed, so "
                       "the sum is recorded; that both calls happened is }")
                e.line("  DevilNoteLoose('%s-bait-sum', UInt64(Cardinal(Sum)));" % name)
                e.line("  { the trap reports, it does not damage the value it "
                       "carries: identity has to stay a clean oracle }")
                e.line("  DevilNoteLoose('%s-bait-calls', "
                       "UInt64(Cardinal(DvlBait%s_%d)));" % (name, tag, level))
                e.line("  Result := %s(X);" % inner)
                e.line("end;")

            elif stage == "narrow-widen-bait":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Narrow: Integer;")
                e.line("  Wide: UInt64;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the shape from dvl-0001: a narrow value widened "
                       "through an unsigned type, mid-chain }")
                e.line("  Narrow := Integer(Carried and $7FFFFFFF);")
                e.line("  Wide := UInt64(Cardinal(Narrow));")
                e.line("  If Wide = UInt64(Cardinal(Narrow)) then")
                e.line("    Result := Carried")
                e.line("  else")
                e.line("    Result := not Carried;")
                e.line("end;")

            elif stage == "cast-reinterpret-bait":
                e.line("type")
                e.line("  TDvlCp%s_%d = type AnsiString(1251);" % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Bytes: TDvlCp%s_%d;" % (tag, level))
                e.line("  Reinterpreted: UTF8String;")
                e.line("  Carried: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Carried := %s(X);" % inner)
                e.line("  { the shape from dvl-0013: a cast between byte string "
                       "types must not re-encode }")
                e.line("  Bytes := TDvlCp%s_%d(AnsiString('abc'));" % (tag, level))
                e.line("  Reinterpreted := UTF8String(Bytes);")
                e.line("  If Length(Reinterpreted) = 3 then")
                e.line("    Result := Carried")
                e.line("  else")
                e.line("    Result := not Carried;")
                e.line("end;")

            elif stage == "effect-pair":
                e.line("var")
                e.line("  DvlPairCalls%s_%d: Integer;" % (tag, level))
                e.line()
                e.line("function DvlOnce%s_%d(X: Int64): Int64;" % (tag, level))
                e.line("begin")
                e.line("  Inc(DvlPairCalls%s_%d);" % (tag, level))
                e.line("  Result := %s(X);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Left, Right: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  DvlPairCalls%s_%d := 0;" % (tag, level))
                e.line("  { two calls of a routine that changes state, from one "
                       "expression, with the whole rest of the chain inside }")
                e.line("  Left := DvlOnce%s_%d(X) + DvlOnce%s_%d(X);"
                       % (tag, level, tag, level))
                e.line("  Right := Left div 2;")
                e.line("  If DvlPairCalls%s_%d = 2 then" % (tag, level))
                e.line("    Result := Right")
                e.line("  else")
                e.line("    Result := not X;")
                e.line("end;")

            elif stage == "volatile-slot":
                e.line("var")
                e.line("  DvlSlot%s_%d: Int64;" % (tag, level))
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Seen: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  DvlSlot%s_%d := X;" % (tag, level))
                e.line("  Seen := DvlSlot%s_%d;" % (tag, level))
                e.line("  { the continuation may write the same global, so the "
                       "reload afterwards has to actually happen }")
                e.line("  DvlSlot%s_%d := %s(Seen);" % (tag, level, inner))
                e.line("  Result := DvlSlot%s_%d;" % (tag, level))
                e.line("end;")

            elif stage == "aliased-relay":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Storage: Int64;")
                e.line("  P, Q: PInt64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Storage := X;")
                e.line("  P := @Storage;")
                e.line("  Q := P;")
                e.line("  { one location under two pointers, written across a "
                       "call that the compiler cannot see through }")
                e.line("  P^ := %s(Q^);" % inner)
                e.line("  Result := Q^;")
                e.line("end;")

            elif stage == "ppu-generic":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Carrier: TDvlCarrier<Int64>;")
                e.line("  Strings: TDvlCarrier<AnsiString>;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { the generic body comes from another unit and is "
                       "specialized here, twice, one of them managed }")
                e.line("  Strings.Put(AnsiString('side'));")
                e.line("  Carrier.Put(%s(X));" % inner)
                e.line("  If Strings.Width > 0 then")
                e.line("    Result := Carrier.Get")
                e.line("  else")
                e.line("    Result := not X;")
                e.line("end;")

            elif stage == "ppu-descendant":
                e.line("type")
                e.line("  TDvlRelay%s_%d = class(TDvlRelayBase)" % (tag, level))
                e.line("  public")
                e.line("    function Relay(X: Int64): Int64; override;")
                e.line("  end;")
                e.line()
                e.line("function TDvlRelay%s_%d.Relay(X: Int64): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  { overrides a virtual method whose base lives in "
                       "another unit, then calls back into the chain }")
                e.line("  Result := %s(inherited Relay(X));" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Relay: IDvlRelay;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Relay := TDvlRelay%s_%d.Create;" % (tag, level))
                e.line("  Result := Relay.Relay(X);")
                e.line("end;")

            elif stage == "sibling-chain":
                sibling = "DvlLink%05d_0" % (index - 1)
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Mine, Theirs: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Mine := %s(X);" % inner)
                e.line("  { hands the value to the whole chain of the previous "
                       "case: the layer stops being a set of independent passes "
                       "and becomes one graph }")
                e.line("  { A predecessor is itself a graph: without the shared "
                       "budget, sibling edges compose with branch/retry stages "
                       "into an unbounded generated workload rather than one "
                       "cross-chain transfer. }")
                e.line("  Theirs := Mine;")
                e.line("  If DvlChainBudget > 0 then")
                e.line("  begin")
                e.line("    Dec(DvlChainBudget);")
                e.line("    try")
                e.line("      Theirs := %s(Mine);" % sibling)
                e.line("    finally")
                e.line("      Inc(DvlChainBudget);")
                e.line("    end;")
                e.line("  end;")
                e.line("  If Theirs = Mine then")
                e.line("    Result := Mine")
                e.line("  else")
                e.line("    Result := not Mine;")
                e.line("end;")

            elif stage == "branch-merge":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Left, Right: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { the same continuation entered twice from different "
                       "places: if the two disagree the value is destroyed and "
                       "the chain reports it at the end }")
                e.line("  Left := %s(X);" % inner)
                e.line("  Right := %s(X);" % inner)
                e.line("  If Left = Right then")
                e.line("    Result := Left")
                e.line("  else")
                e.line("    Result := not Left;")
                e.line("end;")

            elif stage == "branch-thread-merge":
                e.line("type")
                e.line("  TDvlSide%s_%d = class(TThread)" % (tag, level))
                e.line("  public")
                e.line("    Input, Output: Int64;")
                e.line("    procedure Execute; override;")
                e.line("  end;")
                e.line()
                e.line("procedure TDvlSide%s_%d.Execute;" % (tag, level))
                e.line("begin")
                e.line("  Output := %s(Input);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Side: TDvlSide%s_%d;" % (tag, level))
                e.line("  Here, There: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Side := TDvlSide%s_%d.Create(True);" % (tag, level))
                e.line("  try")
                e.line("    Side.FreeOnTerminate := False;")
                e.line("    Side.Input := X;")
                e.line("    Side.Start;")
                e.line("    { one path on this thread, one on the other, and "
                       "they must agree }")
                e.line("    Here := %s(X);" % inner)
                e.line("    Side.WaitFor;")
                e.line("    There := Side.Output;")
                e.line("  finally")
                e.line("    Side.Free;")
                e.line("  end;")
                e.line("  If Here = There then")
                e.line("    Result := Here")
                e.line("  else")
                e.line("    Result := not Here;")
                e.line("end;")

            elif stage == "recursive-descent":
                e.line("function DvlDescend%s_%d(X: Int64; Level: Integer): Int64;"
                       % (tag, level))
                e.line("begin")
                e.line("  If Level > 0 then")
                e.line("    Result := DvlDescend%s_%d(X, Level - 1)"
                       % (tag, level))
                e.line("  else")
                e.line("    Result := %s(X);" % inner)
                e.line("end;")
                e.line()
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  { the continuation sits under a stack of identical "
                       "frames }")
                e.line("  Result := DvlDescend%s_%d(X, %d);"
                       % (tag, level, 3 + level % 5))
                e.line("end;")

            elif stage == "guarded-retry":
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Attempts: Integer;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Result := 0;")
                e.line("  Attempts := 0;")
                e.line("  { entered from a loop body, through a handler, with a "
                       "finally on every turn }")
                e.line("  while Attempts < 2 do")
                e.line("  begin")
                e.line("    try")
                e.line("      try")
                e.line("        If Attempts = 0 then")
                e.line("          raise Exception.Create('retry');")
                e.line("        Result := %s(X);" % inner)
                e.line("      except")
                e.line("        Result := 0;")
                e.line("      end;")
                e.line("    finally")
                e.line("      Inc(Attempts);")
                e.line("    end;")
                e.line("  end;")
                e.line("end;")

            else:   # sorted-pair
                e.line("function %s(X: Int64): Int64;" % fn)
                e.line("var")
                e.line("  Pair: array[0..1] of Int64;")
                e.line("  Temp: Int64;")
                e.line("begin")
                e.line("  DevilTrailAdd('%s');" % mark)
                e.line("  Pair[0] := %s(X);" % inner)
                e.line("  Pair[1] := -1;")
                e.line("  { swap twice: the value ends where it started }")
                e.line("  Temp := Pair[0];")
                e.line("  Pair[0] := Pair[1];")
                e.line("  Pair[1] := Temp;")
                e.line("  Temp := Pair[0];")
                e.line("  Pair[0] := Pair[1];")
                e.line("  Pair[1] := Temp;")
                e.line("  Result := Pair[0];")
                e.line("end;")

            e.line()

        e.line("procedure %s;" % proc)
        e.line("begin")
        e.line("  DevilTrailReset;")
        e.line("  { %d mechanisms nested one inside the other; identity is the "
               "whole oracle }" % len(stages))
        e.line("  DevilFeed(UInt64(%d));" % seed)
        e.line("  DevilCheckU('%s-identity', "
               "UInt64(DvlLink%s_0(%d)), %d);" % (name, tag, seed, seed))
        # each level marks once; a branching level runs everything below it
        # twice, so the marks below it count twice as well
        marks = 0
        for position in range(len(stages) - 1, -1, -1):
            marks = 1 + (2 * marks if stages[position] in CHAIN_BRANCHING
                         else marks)
        if any(st in CHAIN_NEEDS_FOREIGN for st in stages):
            e.line("  { this pass ran forms from other layers, which make their "
                   "own marks: the length is recorded, not demanded }")
            e.line("  DevilNoteLoose('%s-depth', UInt64(Length(DevilTrail)));" % name)
        elif any(st in CHAIN_TRAIL_BREAKING for st in stages):
            e.line("  { a stage in this pass rewrote the trail on purpose, so "
                   "its length says nothing about the depth }")
            e.line("  DevilNoteLoose('%s-depth', UInt64(Length(DevilTrail)));" % name)
        elif any(st in CHAIN_NEEDS_SIBLING for st in stages):
            e.line("  { this pass also ran another case's chain end to end, so "
                   "its trail is longer than its own depth: recorded, and "
                   "compared between builds }")
            e.line("  DevilNoteLoose('%s-depth', UInt64(Length(DevilTrail)));" % name)
        else:
            e.line("  { every stage marks the trail once, so one pass is "
                   "exactly as long as the chain is deep }")
            e.line("  DevilCheckU('%s-depth', UInt64(Length(DevilTrail)), %d);"
                   % (name, marks))
        e.line("  DevilCheckU('%s-negative', "
               "UInt64(DvlLink%s_0(-%d)), UInt64(Int64(-%d)));"
               % (name, tag, seed, seed))
        e.line("  DevilCheckU('%s-zero', UInt64(DvlLink%s_0(0)), 0);"
               % (name, tag))
        e.line("  { and now the hard question: an exception from the bottom, "
               "up through every mechanism the chain is made of }")
        e.line("  var Before := TDvlTagged.Alive;")
        e.line("  var Caught := 0;")
        e.line("  try")
        e.line("    DvlLink%s_0(%d);" % (tag, CHAIN_SENTINEL))
        e.line("  except")
        e.line("    on E: EDvlChainBoom do")
        e.line("      Caught := 1;")
        e.line("  end;")
        e.line("  { whether it reaches the top depends on which stages the "
               "chain happens to contain - several of them legitimately "
               "swallow it - so this is recorded, not demanded }")
        e.line("  DevilNoteLoose('%s-unwind-caught', UInt64(Cardinal(Caught)));" % name)
        e.line("  { every gate the unwind passed released what it held }")
        e.line("  DevilCheckU('%s-unwind-balance', "
               "UInt64(Cardinal(TDvlTagged.Alive - Before)), 0);" % name)
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="chain",
                                  detail={"depth": len(stages),
                                          "stages": stages}))

    emit_runner(e, "Chain", calls)
    return records


# Every other layer needs to know the answer. This one does not: it writes the
# same meaning several ways and demands that all of them agree. Whatever the
# right number is, a compiler that lowers one spelling differently from another
# is wrong - and the disagreement is visible without any oracle at all.
#
# That makes this the only layer that keeps working on constructs nobody has a
# model for, and the only one that cannot be fooled by a wrong expectation.
META_FAMILIES = ("array-sum", "record-copy", "string-build", "max-of-array",
                 "membership", "array-copy", "count-matching", "reverse",
                 "digits-roundtrip", "find-first", "swap-all", "nested-total",
                 "object-walk", "string-scan", "set-membership",
                 "guarded-total")


def layer_metamorphic(e: Emitter, rng: random.Random, count: int,
                      start: int) -> list[CaseRecord]:
    """Equivalent spellings: they must agree with each other, not with me."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-meta-%05d" % index
        proc = "DvlMeta%05d" % index
        tag = "%05d" % index
        family = rng.choice(META_FAMILIES)
        width = rng.randrange(4, 12)
        seed = index % 37 + 1

        e.line("type")
        e.line("  TDvlMetaData%s = array[0..%d] of Int64;" % (tag, width - 1))
        e.line("  { Delphi needs a named type for a procedural reference, and "
               "families declared below already use it }")
        e.line("  TDvlMetaThunk%s = reference to function: Int64;" % tag)
        e.line()

        variants: list[str] = []

        def variant(suffix: str, lines: list[str],
                    signature: str = "(const Data: TDvlMetaData%s): Int64") -> None:
            fname = "DvlMeta%s_%s" % (tag, suffix)
            variants.append(fname)
            e.line("function %s%s;" % (fname, signature % tag if "%s" in signature
                                       else signature))
            for line in lines:
                e.line(line)
            e.line()

        if family == "array-sum":
            e.line("function DvlMetaOpen%s(const Items: array of Int64): Int64;"
                   % tag)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  for var I := Low(Items) to High(Items) do")
            e.line("    Result := Result + Items[I];")
            e.line("end;")
            e.line()
            variant("loop", ["begin", "  Result := 0;",
                             "  for var I := Low(Data) to High(Data) do",
                             "    Result := Result + Data[I];", "end;"])
            variant("forin", ["begin", "  Result := 0;",
                              "  for var V in Data do",
                              "    Result := Result + V;", "end;"])
            variant("while", ["var", "  I: Integer;", "begin", "  Result := 0;",
                              "  I := Low(Data);",
                              "  while I <= High(Data) do", "  begin",
                              "    Result := Result + Data[I];",
                              "    Inc(I);", "  end;", "end;"])
            variant("repeat", ["var", "  I: Integer;", "begin",
                               "  Result := 0;", "  I := Low(Data);",
                               "  repeat",
                               "    Result := Result + Data[I];",
                               "    Inc(I);",
                               "  until I > High(Data);", "end;"])
            variant("pointer", ["var", "  P: PInt64;", "begin",
                                "  Result := 0;", "  P := @Data[0];",
                                "  for var I := 0 to High(Data) do", "  begin",
                                "    Result := Result + P^;", "    Inc(P);",
                                "  end;", "end;"])
            variant("recursive", ["", "  function Tail(const D: TDvlMetaData%s; "
                                  "I: Integer): Int64;" % tag,
                                  "  begin",
                                  "    If I > High(D) then",
                                  "      Result := 0",
                                  "    else",
                                  "      Result := D[I] + Tail(D, I + 1);",
                                  "  end;", "",
                                  "begin", "  Result := Tail(Data, Low(Data));",
                                  "end;"])
            variant("openarray", ["begin",
                                  "  Result := DvlMetaOpen%s(Data);" % tag,
                                  "end;"])

        elif family == "record-copy":
            e.line("type")
            e.line("  TDvlMetaRec%s = record" % tag)
            e.line("    A, B, C: Int64;")
            e.line("    Text: AnsiString;")
            e.line("  end;")
            e.line()
            e.line("function DvlMetaTake%s(R: TDvlMetaRec%s): Int64;" % (tag, tag))
            e.line("begin")
            e.line("  Result := R.A + R.B + R.C + Length(R.Text);")
            e.line("end;")
            e.line()
            for suffix, body in (
                ("assign", ["var", "  Source, Target: TDvlMetaRec%s;" % tag,
                            "begin",
                            "  Source.A := Data[0];", "  Source.B := Data[1];",
                            "  Source.C := Data[2];",
                            "  Source.Text := AnsiString('copy');",
                            "  Target := Source;",
                            "  Result := Target.A + Target.B + Target.C + "
                            "Length(Target.Text);", "end;"]),
                ("fields", ["var", "  Source, Target: TDvlMetaRec%s;" % tag,
                            "begin",
                            "  Source.A := Data[0];", "  Source.B := Data[1];",
                            "  Source.C := Data[2];",
                            "  Source.Text := AnsiString('copy');",
                            "  Target.A := Source.A;",
                            "  Target.B := Source.B;",
                            "  Target.C := Source.C;",
                            "  Target.Text := Source.Text;",
                            "  Result := Target.A + Target.B + Target.C + "
                            "Length(Target.Text);", "end;"]),
                ("byvalue", ["var", "  Source: TDvlMetaRec%s;" % tag, "begin",
                             "  Source.A := Data[0];", "  Source.B := Data[1];",
                             "  Source.C := Data[2];",
                             "  Source.Text := AnsiString('copy');",
                             "  Result := DvlMetaTake%s(Source);" % tag,
                             "end;"]),
                ("pointer", ["var", "  Source, Target: TDvlMetaRec%s;" % tag,
                             "  P: ^TDvlMetaRec%s;" % tag, "begin",
                             "  Source.A := Data[0];", "  Source.B := Data[1];",
                             "  Source.C := Data[2];",
                             "  Source.Text := AnsiString('copy');",
                             "  P := @Source;", "  Target := P^;",
                             "  Result := Target.A + Target.B + Target.C + "
                             "Length(Target.Text);", "end;"])):
                variant(suffix, body)

        elif family == "string-build":
            for suffix, body in (
                ("concat", ["var", "  S: AnsiString;", "begin", "  S := '';",
                            "  for var V in Data do",
                            "    S := S + AnsiString(IntToStr(V)) + ',';",
                            "  Result := Length(S);", "end;"]),
                ("builtin", ["var", "  S: AnsiString;", "begin", "  S := '';",
                             "  for var V in Data do",
                             "    S := Concat(S, AnsiString(IntToStr(V)), ',');",
                             "  Result := Length(S);", "end;"]),
                ("insert", ["var", "  S, Piece: AnsiString;", "begin",
                            "  S := '';",
                            "  for var V in Data do", "  begin",
                            "    Piece := AnsiString(IntToStr(V)) + ',';",
                            "    Insert(Piece, S, Length(S) + 1);", "  end;",
                            "  Result := Length(S);", "end;"]),
                ("prealloc", ["var", "  S, Piece: AnsiString;",
                              "  Position: Integer;", "begin",
                              "  S := '';", "  Position := 1;",
                              "  for var V in Data do", "  begin",
                              "    Piece := AnsiString(IntToStr(V)) + ',';",
                              "    SetLength(S, Length(S) + Length(Piece));",
                              "    Move(Piece[1], S[Position], Length(Piece));",
                              "    Inc(Position, Length(Piece));", "  end;",
                              "  Result := Length(S);", "end;"]),
                ("wide", ["var", "  W: string;", "begin", "  W := '';",
                          "  for var V in Data do",
                          "    W := W + IntToStr(V) + ',';",
                          "  Result := Length(W);", "end;"])):
                variant(suffix, body)

        elif family == "max-of-array":
            for suffix, body in (
                ("ifchain", ["begin", "  Result := Data[0];",
                             "  for var V in Data do",
                             "    If V > Result then", "      Result := V;",
                             "end;"]),
                ("math", ["begin", "  Result := Data[0];",
                          "  for var V in Data do",
                          "    Result := Max(Result, V);", "end;"]),
                ("sorted", ["var", "  Copy: TDvlMetaData%s;" % tag,
                            "  Temp: Int64;", "begin", "  Copy := Data;",
                            "  for var I := Low(Copy) to High(Copy) - 1 do",
                            "    for var J := Low(Copy) to High(Copy) - 1 do",
                            "      If Copy[J] > Copy[J + 1] then", "      begin",
                            "        Temp := Copy[J];",
                            "        Copy[J] := Copy[J + 1];",
                            "        Copy[J + 1] := Temp;", "      end;",
                            "  Result := Copy[High(Copy)];", "end;"]),
                ("recursive", ["", "  function Deeper(I: Integer): Int64;",
                               "  begin",
                               "    If I = High(Data) then",
                               "      Result := Data[I]",
                               "    else", "    begin",
                               "      Result := Deeper(I + 1);",
                               "      If Data[I] > Result then",
                               "        Result := Data[I];", "    end;",
                               "  end;", "",
                               "begin", "  Result := Deeper(Low(Data));",
                               "end;"])):
                variant(suffix, body)

        elif family == "membership":
            needle = seed % max(2, width)
            for suffix, body in (
                ("linear", ["begin", "  Result := 0;",
                            "  for var V in Data do",
                            "    If V = Data[%d] then" % needle,
                            "      Inc(Result);", "end;"]),
                ("indexed", ["begin", "  Result := 0;",
                             "  for var I := Low(Data) to High(Data) do",
                             "    If Data[I] = Data[%d] then" % needle,
                             "      Inc(Result);", "end;"]),
                ("early", ["var", "  Found: Boolean;", "begin",
                           "  Result := 0;", "  Found := False;",
                           "  for var I := Low(Data) to High(Data) do",
                           "  begin",
                           "    Found := Data[I] = Data[%d];" % needle,
                           "    If Found then", "      Inc(Result);", "  end;",
                           "end;"]),
                ("case", ["begin", "  Result := 0;",
                          "  for var V in Data do",
                          "    case Ord(V = Data[%d]) of" % needle,
                          "      1: Inc(Result);", "    else", "      ;",
                          "    end;", "end;"])):
                variant(suffix, body)

        elif family == "array-copy":
            for suffix, body in (
                ("assign", ["var", "  Target: TDvlMetaData%s;" % tag, "begin",
                            "  Target := Data;", "  Result := 0;",
                            "  for var V in Target do",
                            "    Result := Result + V;", "end;"]),
                ("elementwise", ["var", "  Target: TDvlMetaData%s;" % tag,
                                 "begin",
                                 "  for var I := Low(Data) to High(Data) do",
                                 "    Target[I] := Data[I];", "  Result := 0;",
                                 "  for var V in Target do",
                                 "    Result := Result + V;", "end;"]),
                ("move", ["var", "  Target: TDvlMetaData%s;" % tag, "begin",
                          "  Move(Data[0], Target[0], SizeOf(Data));",
                          "  Result := 0;",
                          "  for var V in Target do",
                          "    Result := Result + V;", "end;"]),
                ("dynamic", ["var", "  Target: System.TArray<Int64>;", "begin",
                             "  SetLength(Target, Length(Data));",
                             "  for var I := Low(Data) to High(Data) do",
                             "    Target[I] := Data[I];", "  Result := 0;",
                             "  for var V in Target do",
                             "    Result := Result + V;", "end;"])):
                variant(suffix, body)

        elif family == "count-matching":
            # Delphi wants a named type here: an anonymous `reference to` is
            # not allowed in a variable declaration
            e.line("type")
            e.line("  TDvlMetaStep%s = reference to procedure(V: Int64);" % tag)
            e.line()
            for suffix, body in (
                ("counter", ["begin", "  Result := 0;",
                             "  for var V in Data do",
                             "    If not Odd(V) then", "      Inc(Result);",
                             "end;"]),
                ("accumulate", ["begin", "  Result := 0;",
                                "  for var V in Data do",
                                "    Result := Result + Ord(not Odd(V));",
                                "end;"]),
                ("subtract", ["var", "  Odds: Int64;", "begin", "  Odds := 0;",
                              "  for var V in Data do",
                              "    If Odd(V) then", "      Inc(Odds);",
                              "  Result := Length(Data) - Odds;", "end;"]),
                ("closure", ["var",
                             "  Count: Int64;",
                             "  Step: TDvlMetaStep%s;" % tag,
                             "begin", "  Count := 0;",
                             "  Step :=", "    procedure(V: Int64)",
                             "    begin", "      If not Odd(V) then",
                             "        Inc(Count);", "    end;",
                             "  for var V in Data do", "    Step(V);",
                             "  Result := Count;", "end;"])):
                variant(suffix, body)

        elif family == "reverse":
            for suffix, body in (
                ("swap", ["var", "  Work: TDvlMetaData%s;" % tag,
                          "  Temp: Int64;", "begin", "  Work := Data;",
                          "  for var I := 0 to High(Work) div 2 do", "  begin",
                          "    Temp := Work[I];",
                          "    Work[I] := Work[High(Work) - I];",
                          "    Work[High(Work) - I] := Temp;", "  end;",
                          "  Result := Work[0] * 1000 + Work[High(Work)];",
                          "end;"]),
                ("backward", ["var", "  Work: TDvlMetaData%s;" % tag,
                              "  Position: Integer;", "begin", "  Position := 0;",
                              "  for var I := High(Data) downto Low(Data) do",
                              "  begin", "    Work[Position] := Data[I];",
                              "    Inc(Position);", "  end;",
                              "  Result := Work[0] * 1000 + Work[High(Work)];",
                              "end;"]),
                ("recursive", ["var", "  Work: TDvlMetaData%s;" % tag, "",
                               "  procedure Fill(I: Integer);", "  begin",
                               "    If I > High(Data) then", "      Exit;",
                               "    Work[High(Data) - I] := Data[I];",
                               "    Fill(I + 1);", "  end;", "",
                               "begin", "  Fill(0);",
                               "  Result := Work[0] * 1000 + Work[High(Work)];",
                               "end;"])):
                variant(suffix, body)

        elif family == "digits-roundtrip":
            for suffix, body in (
                ("inttostr", ["begin", "  Result := 0;",
                              "  for var V in Data do",
                              "    Result := Result + StrToInt64(IntToStr(V));",
                              "end;"]),
                ("strval", ["var", "  S: string;", "  Value: Int64;",
                            "  Code: Integer;", "begin", "  Result := 0;",
                            "  for var V in Data do", "  begin",
                            "    Str(V, S);", "    Val(S, Value, Code);",
                            "    Result := Result + Value;", "  end;", "end;"]),
                ("format", ["begin", "  Result := 0;",
                            "  for var V in Data do",
                            "    Result := Result + "
                            "StrToInt64(Format('%d', [V]));", "end;"]),
                ("utf8", ["begin", "  Result := 0;",
                          "  for var V in Data do",
                          "    Result := Result + "
                          "StrToInt64(string(UTF8String(IntToStr(V))));",
                          "end;"])):
                variant(suffix, body)

        elif family == "find-first":
            for suffix, body in (
                ("exit", ["begin", "  Result := -1;",
                          "  for var I := Low(Data) to High(Data) do",
                          "    If Data[I] > 0 then", "    begin",
                          "      Result := I;", "      Exit;", "    end;",
                          "end;"]),
                ("break", ["begin", "  Result := -1;",
                           "  for var I := Low(Data) to High(Data) do",
                           "    If Data[I] > 0 then", "    begin",
                           "      Result := I;", "      Break;", "    end;",
                           "end;"]),
                ("while", ["var", "  I: Integer;", "begin", "  Result := -1;",
                           "  I := Low(Data);",
                           "  while (I <= High(Data)) and (Result < 0) do",
                           "  begin", "    If Data[I] > 0 then",
                           "      Result := I;", "    Inc(I);", "  end;",
                           "end;"]),
                ("goto", ["label", "  Done;", "var", "  I: Integer;", "begin",
                          "  Result := -1;",
                          "  for I := Low(Data) to High(Data) do",
                          "    If Data[I] > 0 then", "    begin",
                          "      Result := I;", "      goto Done;", "    end;",
                          "Done:", "end;"])):
                variant(suffix, body)

        elif family == "swap-all":
            for suffix, body in (
                ("temp", ["var", "  Work: TDvlMetaData%s;" % tag,
                          "  Temp: Int64;", "begin", "  Work := Data;",
                          "  for var I := 0 to High(Work) - 1 do", "  begin",
                          "    Temp := Work[I];", "    Work[I] := Work[I + 1];",
                          "    Work[I + 1] := Temp;", "  end;",
                          "  Result := 0;",
                          "  for var V in Work do",
                          "    Result := Result + V;", "end;"]),
                ("procedure", ["var", "  Work: TDvlMetaData%s;" % tag, "",
                               "  procedure Exchange(var A, B: Int64);",
                               "  var", "    T: Int64;", "  begin",
                               "    T := A;", "    A := B;", "    B := T;",
                               "  end;", "",
                               "begin", "  Work := Data;",
                               "  for var I := 0 to High(Work) - 1 do",
                               "    Exchange(Work[I], Work[I + 1]);",
                               "  Result := 0;",
                               "  for var V in Work do",
                               "    Result := Result + V;", "end;"]),
                ("pointer", ["var", "  Work: TDvlMetaData%s;" % tag,
                             "  P, Q: PInt64;", "  T: Int64;", "begin",
                             "  Work := Data;",
                             "  for var I := 0 to High(Work) - 1 do", "  begin",
                             "    P := @Work[I];", "    Q := @Work[I + 1];",
                             "    T := P^;", "    P^ := Q^;", "    Q^ := T;",
                             "  end;", "  Result := 0;",
                             "  for var V in Work do",
                             "    Result := Result + V;", "end;"])):
                variant(suffix, body)

        elif family == "object-walk":
            e.line("type")
            e.line("  TDvlMetaNode%s = class" % tag)
            e.line("  public")
            e.line("    Value: Int64;")
            e.line("    Next: TDvlMetaNode%s;" % tag)
            e.line("    destructor Destroy; override;")
            e.line("  end;")
            e.line()
            e.line("destructor TDvlMetaNode%s.Destroy;" % tag)
            e.line("begin")
            e.line("  Next.Free;")
            e.line("  inherited Destroy;")
            e.line("end;")
            e.line()
            e.line("function DvlBuildList%s(const Data: TDvlMetaData%s): TDvlMetaNode%s;"
                   % (tag, tag, tag))
            e.line("var")
            e.line("  Head, Item: TDvlMetaNode%s;" % tag)
            e.line("begin")
            e.line("  Head := nil;")
            e.line("  for var I := High(Data) downto Low(Data) do")
            e.line("  begin")
            e.line("    Item := TDvlMetaNode%s.Create;" % tag)
            e.line("    Item.Value := Data[I];")
            e.line("    Item.Next := Head;")
            e.line("    Head := Item;")
            e.line("  end;")
            e.line("  Result := Head;")
            e.line("end;")
            e.line()
            for suffix, body in (
                ("while", ["var", "  Head, Item: TDvlMetaNode%s;" % tag, "begin",
                           "  Head := DvlBuildList%s(Data);" % tag, "  try",
                           "    Result := 0;", "    Item := Head;",
                           "    while Item <> nil do", "    begin",
                           "      Result := Result + Item.Value;",
                           "      Item := Item.Next;", "    end;",
                           "  finally", "    Head.Free;", "  end;", "end;"]),
                ("recursive", ["var", "  Head: TDvlMetaNode%s;" % tag, "",
                               "  function Walk(Item: TDvlMetaNode%s): Int64;" % tag,
                               "  begin",
                               "    If Item = nil then", "      Result := 0",
                               "    else",
                               "      Result := Item.Value + Walk(Item.Next);",
                               "  end;", "",
                               "begin",
                               "  Head := DvlBuildList%s(Data);" % tag, "  try",
                               "    Result := Walk(Head);",
                               "  finally", "    Head.Free;", "  end;", "end;"]),
                ("closure", ["var", "  Head: TDvlMetaNode%s;" % tag,
                             "  Total: Int64;",
                             "  Step: TDvlMetaThunk%s;" % tag, "begin",
                             "  Head := DvlBuildList%s(Data);" % tag, "  try",
                             "    Total := 0;",
                             "    Step :=", "      function: Int64",
                             "      var", "        Item: TDvlMetaNode%s;" % tag,
                             "      begin", "        Item := Head;",
                             "        while Item <> nil do", "        begin",
                             "          Total := Total + Item.Value;",
                             "          Item := Item.Next;", "        end;",
                             "        Result := Total;", "      end;",
                             "    Result := Step();",
                             "  finally", "    Head.Free;", "  end;", "end;"])):
                variant(suffix, body)

        elif family == "string-scan":
            for suffix, body in (
                ("indexed", ["var", "  S: AnsiString;", "begin",
                             "  S := '';",
                             "  for var V in Data do",
                             "    S := S + AnsiString(IntToStr(Abs(V)));",
                             "  Result := 0;",
                             "  for var I := 1 to Length(S) do",
                             "    Result := Result + Ord(S[I]);", "end;"]),
                ("forin", ["var", "  S: AnsiString;", "begin", "  S := '';",
                           "  for var V in Data do",
                           "    S := S + AnsiString(IntToStr(Abs(V)));",
                           "  Result := 0;",
                           "  for var C in S do",
                           "    Result := Result + Ord(C);", "end;"]),
                ("pointer", ["var", "  S: AnsiString;", "  P: PAnsiChar;",
                             "begin", "  S := '';",
                             "  for var V in Data do",
                             "    S := S + AnsiString(IntToStr(Abs(V)));",
                             "  Result := 0;", "  P := PAnsiChar(S);",
                             "  while P^ <> #0 do", "  begin",
                             "    Result := Result + Ord(P^);",
                             "    Inc(P);", "  end;", "end;"]),
                ("widened", ["var", "  S: AnsiString;", "  W: string;",
                             "begin", "  S := '';",
                             "  for var V in Data do",
                             "    S := S + AnsiString(IntToStr(Abs(V)));",
                             "  W := string(S);", "  Result := 0;",
                             "  for var C in W do",
                             "    Result := Result + Ord(C);", "end;"])):
                variant(suffix, body)

        elif family == "set-membership":
            for suffix, body in (
                ("set", ["var", "  Seen: set of 0..31;", "begin",
                         "  Seen := [];",
                         "  for var V in Data do",
                         "    Include(Seen, Abs(V) mod 32);",
                         "  Result := 0;",
                         "  for var I := 0 to 31 do",
                         "    If I in Seen then", "      Inc(Result);", "end;"]),
                ("bitmask", ["var", "  Mask: UInt64;", "begin", "  Mask := 0;",
                             "  for var V in Data do",
                             "    Mask := Mask or (UInt64(1) shl (Abs(V) mod 32));",
                             "  Result := 0;",
                             "  for var I := 0 to 31 do",
                             "    If (Mask shr I) and 1 = 1 then",
                             "      Inc(Result);", "end;"]),
                ("array", ["var", "  Flags: array[0..31] of Boolean;", "begin",
                           "  for var I := 0 to 31 do",
                           "    Flags[I] := False;",
                           "  for var V in Data do",
                           "    Flags[Abs(V) mod 32] := True;",
                           "  Result := 0;",
                           "  for var Flag in Flags do",
                           "    If Flag then", "      Inc(Result);", "end;"])):
                variant(suffix, body)

        elif family == "guarded-total":
            for suffix, body in (
                ("plain", ["begin", "  Result := 0;",
                           "  for var V in Data do",
                           "    If V > 0 then",
                           "      Result := Result + V;", "end;"]),
                ("exception", ["begin", "  Result := 0;",
                               "  for var V in Data do",
                               "    try",
                               "      If V <= 0 then",
                               "        raise Exception.Create('skip');",
                               "      Result := Result + V;",
                               "    except", "      ;", "    end;", "end;"]),
                ("finally", ["var", "  Item: Int64;", "begin", "  Result := 0;",
                             "  for var V in Data do", "  begin",
                             "    Item := 0;", "    try",
                             "      If V > 0 then", "        Item := V;",
                             "    finally",
                             "      Result := Result + Item;", "  end;",
                             "  end;", "end;"]),
                ("thread", ["var", "  Total: Int64;", "begin", "  Total := 0;",
                            "  for var V in Data do",
                            "    If V > 0 then",
                            "      Total := Total + V;",
                            "  Result := Total;", "end;"])):
                variant(suffix, body)

        else:   # nested-total
            for suffix, body in (
                ("plain", ["begin", "  Result := 0;",
                           "  for var I := Low(Data) to High(Data) do",
                           "    for var J := Low(Data) to High(Data) do",
                           "      Result := Result + Ord(Data[I] = Data[J]);",
                           "end;"]),
                ("hoisted", ["var", "  Inner: Int64;", "begin", "  Result := 0;",
                             "  for var I := Low(Data) to High(Data) do",
                             "  begin", "    Inner := 0;",
                             "    for var J := Low(Data) to High(Data) do",
                             "      Inner := Inner + Ord(Data[I] = Data[J]);",
                             "    Result := Result + Inner;", "  end;", "end;"]),
                ("function", ["", "  function Row(I: Integer): Int64;",
                              "  begin", "    Result := 0;",
                              "    for var J := Low(Data) to High(Data) do",
                              "      Result := Result + Ord(Data[I] = Data[J]);",
                              "  end;", "",
                              "begin", "  Result := 0;",
                              "  for var I := Low(Data) to High(Data) do",
                              "    Result := Result + Row(I);", "end;"]),
                ("flat", ["var", "  I, J: Integer;", "begin", "  Result := 0;",
                          "  I := Low(Data);",
                          "  while I <= High(Data) do", "  begin",
                          "    J := Low(Data);",
                          "    while J <= High(Data) do", "    begin",
                          "      Result := Result + Ord(Data[I] = Data[J]);",
                          "      Inc(J);", "    end;", "    Inc(I);", "  end;",
                          "end;"])):
                variant(suffix, body)

        e.line("type")
        e.line("  TDvlMetaCall%s = function(const Data: TDvlMetaData%s): Int64;"
               % (tag, tag))
        e.line("  TDvlMetaBox%s<T> = record" % tag)
        e.line("    Value: T;")
        e.line("  end;")
        e.line("  TDvlMetaWorker%s = class(TThread)" % tag)
        e.line("  public")
        e.line("    Call: TDvlMetaCall%s;" % tag)
        e.line("    Input: TDvlMetaData%s;" % tag)
        e.line("    Output: Int64;")
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlMetaWorker%s.Execute;" % tag)
        e.line("begin")
        e.line("  Output := Call(Input);")
        e.line("end;")
        e.line()
        e.line("function DvlMetaInThread%s(Call: TDvlMetaCall%s; "
               "const Data: TDvlMetaData%s): Int64;" % (tag, tag, tag))
        e.line("var")
        e.line("  Worker: TDvlMetaWorker%s;" % tag)
        e.line("begin")
        e.line("  Worker := TDvlMetaWorker%s.Create(True);" % tag)
        e.line("  try")
        e.line("    Worker.FreeOnTerminate := False;")
        e.line("    Worker.Call := Call;")
        e.line("    Worker.Input := Data;")
        e.line("    Worker.Start;")
        e.line("    Worker.WaitFor;")
        e.line("    Result := Worker.Output;")
        e.line("  finally")
        e.line("    Worker.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
        e.line("function DvlMetaInFinally%s(Call: TDvlMetaCall%s; "
               "const Data: TDvlMetaData%s): Int64;" % (tag, tag, tag))
        e.line("begin")
        e.line("  Result := 0;")
        e.line("  try")
        e.line("    Exit;")
        e.line("  finally")
        e.line("    Result := Call(Data);")
        e.line("  end;")
        e.line("end;")
        e.line()
        e.line("function DvlMetaInBox%s(Call: TDvlMetaCall%s; "
               "const Data: TDvlMetaData%s): Int64;" % (tag, tag, tag))
        e.line("var")
        e.line("  Box: TDvlMetaBox%s<Int64>;" % tag)
        e.line("  Step: TDvlMetaThunk%s;" % tag)
        e.line("begin")
        e.line("  Step :=")
        e.line("    function: Int64")
        e.line("    begin")
        e.line("      Result := Call(Data);")
        e.line("    end;")
        e.line("  Box.Value := Step();")
        e.line("  Result := Box.Value;")
        e.line("end;")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Data: TDvlMetaData%s;" % tag)
        e.line("  First: Int64;")
        e.line("begin")
        e.line("  for var I := 0 to %d do" % (width - 1))
        e.line("    Data[I] := ((I * %d) mod 17) - 8;" % (seed + 3))
        e.line("  { the first spelling defines the answer; the rest have to "
               "arrive at the same one }")
        e.line("  First := %s(Data);" % variants[0])
        for other in variants[1:]:
            e.line("  DevilCheckU('%s-%s', UInt64(Ord(%s(Data) = First)), 1);"
                   % (name, other.split("_")[-1], other))
        e.line("  { and the same spellings again, this time called from inside "
               "a worker thread, a finally block and a closure in a generic "
               "record - the code is the same, the surroundings are not }")
        for other in variants:
            short = other.split("_")[-1]
            e.line("  DevilCheckU('%s-%s-thread', "
                   "UInt64(Ord(DvlMetaInThread%s(@%s, Data) = First)), 1);"
                   % (name, short, tag, other))
            e.line("  DevilCheckU('%s-%s-finally', "
                   "UInt64(Ord(DvlMetaInFinally%s(@%s, Data) = First)), 1);"
                   % (name, short, tag, other))
            e.line("  DevilCheckU('%s-%s-boxed', "
                   "UInt64(Ord(DvlMetaInBox%s(@%s, Data) = First)), 1);"
                   % (name, short, tag, other))
        e.line("  DevilNote('%s-value', UInt64(First));" % name)
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="meta",
                                  detail={"family": family,
                                          "spellings": len(variants)}))

    emit_runner(e, "Meta", calls)
    return records


# `chain` nests calls; this one nests types. A node is a record, a class, a
# generic specialization, an array or an interface, and its payload is another
# node - so a case ends up with a generic record holding an array of classes
# whose field is another specialization holding a managed record. Nothing about
# that is exotic on its own; all of it at once is where layout, initialization,
# copying and finalization stop agreeing with each other.
#
# The oracle is structural: how wide the thing is, how many managed objects it
# holds alive, whether a copy is deep or shallow, and whether everything is
# released when the outermost value goes away.
WEAVE_NODES = ("record", "generic-record", "class-field", "array-of",
               "interface-holder", "managed-record", "nested-generic")


class WeaveNode:
    """One level of the tree: a Pascal type plus what it costs to hold it."""

    def __init__(self, kind: str, pascal: str, live: int, deep_copy: bool):
        self.kind = kind
        self.pascal = pascal
        self.live = live            # counted objects one value keeps alive
        self.deep_copy = deep_copy  # does assignment duplicate the payload


def layer_weave(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Nested type trees: layout, lifetime and copying at the same time."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for index in range(start, start + count):
        name = "dvl-weave-%05d" % index
        proc = "DvlWeave%05d" % index
        tag = "%05d" % index
        depth = rng.randrange(4, 10)
        serial = [0]

        def build(level: int) -> WeaveNode:
            """Emit the type for this level, innermost first."""
            if level == 0:
                return WeaveNode("leaf", "Int64", 0, False)
            inner = build(level - 1)
            serial[0] += 1
            suffix = "%s_%d" % (tag, serial[0])
            kind = rng.choice(WEAVE_NODES)

            if kind == "record":
                e.line("type")
                e.line("  TDvlW%s = record" % suffix)
                e.line("    Head: Int64;")
                e.line("    Payload: %s;" % inner.pascal)
                e.line("    Tail: Int64;")
                e.line("  end;")
                e.line()
                return WeaveNode(kind, "TDvlW%s" % suffix, inner.live, True)

            if kind == "generic-record":
                e.line("type")
                e.line("  TDvlG%s<T> = record" % suffix)
                e.line("    Value: T;")
                e.line("    Marker: Integer;")
                e.line("  end;")
                e.line()
                return WeaveNode(kind, "TDvlG%s<%s>" % (suffix, inner.pascal),
                                 inner.live, True)

            if kind == "nested-generic":
                e.line("type")
                e.line("  TDvlOuter%s<T> = record" % suffix)
                e.line("    Inner: T;")
                e.line("  end;")
                e.line("  TDvlPair%s<T> = record" % suffix)
                e.line("    Left: TDvlOuter%s<T>;" % suffix)
                e.line("    Right: TDvlOuter%s<T>;" % suffix)
                e.line("  end;")
                e.line()
                return WeaveNode(kind,
                                 "TDvlPair%s<%s>" % (suffix, inner.pascal),
                                 inner.live * 2, True)

            if kind == "array-of":
                width = rng.randrange(2, 4)
                e.line("type")
                e.line("  TDvlA%s = array[0..%d] of %s;"
                       % (suffix, width - 1, inner.pascal))
                e.line()
                return WeaveNode(kind, "TDvlA%s" % suffix,
                                 inner.live * width, True)

            if kind == "class-field":
                e.line("type")
                e.line("  TDvlC%s = class" % suffix)
                e.line("  public")
                e.line("    class var Live: Integer;")
                e.line("    Payload: %s;" % inner.pascal)
                e.line("    constructor Create;")
                e.line("    destructor Destroy; override;")
                e.line("  end;")
                e.line()
                e.line("constructor TDvlC%s.Create;" % suffix)
                e.line("begin")
                e.line("  inherited Create;")
                e.line("  Inc(Live);")
                e.line("end;")
                e.line()
                e.line("destructor TDvlC%s.Destroy;" % suffix)
                e.line("begin")
                e.line("  Dec(Live);")
                e.line("  inherited Destroy;")
                e.line("end;")
                e.line()
                # a class reference is a pointer: copying shares the instance
                return WeaveNode(kind, "TDvlC%s" % suffix, inner.live, False)

            if kind == "interface-holder":
                e.line("type")
                e.line("  IDvlH%s = interface" % suffix)
                e.line("    ['{4D%06X-0000-0000-00%02X-000000000001}']"
                       % (index % 0xFFFFFF, serial[0] % 0xFF))
                e.line("    function Depth: Integer;")
                e.line("  end;")
                e.line()
                e.line("  TDvlH%s = class(TInterfacedObject, IDvlH%s)"
                       % (suffix, suffix))
                e.line("  public")
                e.line("    class var Live: Integer;")
                e.line("    Payload: %s;" % inner.pascal)
                e.line("    constructor Create;")
                e.line("    destructor Destroy; override;")
                e.line("    function Depth: Integer;")
                e.line("  end;")
                e.line()
                e.line("constructor TDvlH%s.Create;" % suffix)
                e.line("begin")
                e.line("  inherited Create;")
                e.line("  Inc(Live);")
                e.line("end;")
                e.line()
                e.line("destructor TDvlH%s.Destroy;" % suffix)
                e.line("begin")
                e.line("  Dec(Live);")
                e.line("  inherited Destroy;")
                e.line("end;")
                e.line()
                e.line("function TDvlH%s.Depth: Integer;" % suffix)
                e.line("begin")
                e.line("  Result := %d;" % level)
                e.line("end;")
                e.line()
                # a counted reference: one live object per value held
                return WeaveNode(kind, "IDvlH%s" % suffix, inner.live + 1, False)

            e.line("type")
            e.line("  TDvlM%s = record" % suffix)
            e.line("    Text: AnsiString;")
            e.line("    Guard: IInterface;")
            e.line("    Payload: %s;" % inner.pascal)
            e.line("  end;")
            e.line()
            return WeaveNode("managed-record", "TDvlM%s" % suffix,
                             inner.live, True)

        root = build(depth)

        # a second tree of the same shape, written without generics: the two
        # spellings must agree on everything that can be observed
        e.line("type")
        e.line("  TDvlPlainLeaf%s = record" % tag)
        e.line("    Text: AnsiString;")
        e.line("    Value: Int64;")
        e.line("  end;")
        e.line("  TDvlPlainMid%s = record" % tag)
        e.line("    Items: array[0..1] of TDvlPlainLeaf%s;" % tag)
        e.line("  end;")
        e.line("  TDvlPlainTop%s = record" % tag)
        e.line("    Rows: array[0..1] of TDvlPlainMid%s;" % tag)
        e.line("  end;")
        e.line()
        e.line("  TDvlGenLeaf%s<T> = record" % tag)
        e.line("    Text: AnsiString;")
        e.line("    Value: T;")
        e.line("  end;")
        e.line("  TDvlGenMid%s<T> = record" % tag)
        e.line("    Items: array[0..1] of T;")
        e.line("  end;")
        e.line("  TDvlGenTop%s = record" % tag)
        e.line("    Rows: array[0..1] of "
               "TDvlGenMid%s<TDvlGenLeaf%s<Int64>>;" % (tag, tag))
        e.line("  end;")
        e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Value: %s;" % root.pascal)
        e.line("  Copy: %s;" % root.pascal)
        e.line("  Plain, PlainCopy: TDvlPlainTop%s;" % tag)
        e.line("  Woven, WovenCopy: TDvlGenTop%s;" % tag)
        e.line("  Before: Integer;")
        e.line("begin")
        e.line("  Before := TDvlTagged.Alive;")
        e.line("  { a tree of %d nested type levels, ending in %s }"
               % (depth, root.kind))
        e.line("  DevilCheckU('%s-nonzero-size', "
               "UInt64(Ord(SizeOf(Value) > 0)), 1);" % name)
        e.line("  Copy := Value;")
        e.line("  DevilCheckU('%s-copy-width', "
               "UInt64(Ord(SizeOf(Copy) = SizeOf(Value))), 1);" % name)
        if root.kind in ("record", "generic-record", "nested-generic",
                         "managed-record", "array-of"):
            e.line("  DevilCheckU('%s-distinct', "
                   "UInt64(Ord(@Copy <> @Value)), 1);" % name)
        e.line("  DevilCheckU('%s-no-leak', "
               "UInt64(Cardinal(TDvlTagged.Alive - Before)), 0);" % name)
        e.line("  { the same shape, generic and hand-written: identical width }")
        e.line("  DevilCheckU('%s-shapes-agree', "
               "UInt64(Ord(SizeOf(Plain) = SizeOf(Woven))), 1);" % name)
        e.line("  Plain.Rows[1].Items[1].Text := AnsiString('deep');")
        e.line("  Plain.Rows[1].Items[1].Value := %d;" % (index * 7 + 13))
        e.line("  Woven.Rows[1].Items[1].Text := AnsiString('deep');")
        e.line("  Woven.Rows[1].Items[1].Value := %d;" % (index * 7 + 13))
        e.line("  { and identical behaviour when copied and rewritten }")
        e.line("  PlainCopy := Plain;")
        e.line("  WovenCopy := Woven;")
        e.line("  Plain.Rows[1].Items[1].Value := -1;")
        e.line("  Woven.Rows[1].Items[1].Value := -1;")
        e.line("  DevilCheckU('%s-plain-kept', "
               "UInt64(Cardinal(PlainCopy.Rows[1].Items[1].Value)), %d);"
               % (name, index * 7 + 13))
        e.line("  DevilCheckU('%s-woven-kept', "
               "UInt64(Cardinal(WovenCopy.Rows[1].Items[1].Value)), %d);"
               % (name, index * 7 + 13))
        e.line("  DevilCheckU('%s-managed-kept', "
               "UInt64(Ord(WovenCopy.Rows[1].Items[1].Text = "
               "PlainCopy.Rows[1].Items[1].Text)), 1);" % name)
        e.line("  DevilNote('%s-size', UInt64(SizeOf(Value)));" % name)
        e.line("  DevilNoteLoose('%s-depth', UInt64(%d));" % (name, depth))
        e.line("end;")
        e.line()
        calls.append(proc)
        records.append(CaseRecord(name=name, layer="weave",
                                  detail={"depth": depth, "root": root.kind,
                                          "type": root.pascal}))

    emit_runner(e, "Weave", calls)
    return records


# What a value carries besides its magnitude.
MATRIX_PASSENGERS = ("width", "signedness", "exact-type", "codepage",
                     "element-size", "buffer", "directive-state",
                     "alias-visibility", "lifetime", "refcount",
                     "rtti-identity", "provenance", "alignment", "enum-base",
                     "method-data", "exception-identity", "char-width",
                     "packing", "generic-arg")

# Where one compiler stage hands the value to the next.
MATRIX_TRANSFERS = ("fold", "inline", "cross-unit", "specialization",
                    "closure", "variant", "thread", "narrow-widen",
                    "unwind", "record-copy", "interface-cast", "virtual-call",
                    "typed-file", "property-accessor", "open-array",
                    "const-param", "array-detach", "runtime-declaration",
                    "array-of-const", "assembler-hop", "rtti-read",
                    "untyped-file", "inherited-call", "raw-move", "tvalue",
                    "message-method", "class-helper")

# Not every passenger can ride every transfer: a codepage has no meaning after
# a narrowing to Byte, and a directive state cannot cross a thread boundary in
# any observable way. The table says which pairs are real.
MATRIX_SKIP = {
    ("codepage", "narrow-widen"), ("codepage", "variant"),
    ("element-size", "narrow-widen"), ("element-size", "variant"),
    ("buffer", "narrow-widen"), ("buffer", "variant"),
    ("directive-state", "thread"), ("directive-state", "variant"),
    ("directive-state", "interface-cast"), ("directive-state", "virtual-call"),
    ("lifetime", "narrow-widen"), ("lifetime", "fold"),
    ("alias-visibility", "variant"), ("alias-visibility", "fold"),
    ("signedness", "codepage"),
    # a narrowing has nothing to say about text carriers
    ("refcount", "narrow-widen"), ("refcount", "variant"),
    ("provenance", "narrow-widen"), ("provenance", "variant"),
    # RTTI identity is a property of the type, not of a copy through a file
    ("rtti-identity", "typed-file"),
    # a lifetime cannot ride a typed file or an open array of interfaces
    ("lifetime", "typed-file"), ("lifetime", "open-array"),
    ("lifetime", "array-detach"), ("lifetime", "variant"),
    ("directive-state", "typed-file"), ("directive-state", "array-detach"),
    ("directive-state", "property-accessor"), ("directive-state", "open-array"),
    ("alias-visibility", "typed-file"), ("alias-visibility", "array-detach"),
    # an aggregate carrier has no meaning in a Variant or after a narrowing,
    # and an enumeration cannot ride a typed file of Int64
    ("alignment", "variant"), ("alignment", "narrow-widen"),
    ("alignment", "typed-file"), ("alignment", "open-array"),
    ("enum-base", "variant"), ("enum-base", "narrow-widen"),
    ("enum-base", "typed-file"),
    ("method-data", "variant"), ("method-data", "typed-file"),
    ("exception-identity", "variant"), ("exception-identity", "typed-file"),
    # an aggregate or an enumeration cannot ride a boundary that moves the
    # value as an integer or as bytes
    ("alignment", "fold"), ("alignment", "cross-unit"),
    ("enum-base", "fold"), ("enum-base", "cross-unit"),
    # aggregates and text cannot ride an integer-only boundary
    ("packing", "fold"), ("packing", "cross-unit"), ("packing", "variant"),
    ("packing", "narrow-widen"), ("packing", "typed-file"),
    ("packing", "array-of-const"), ("packing", "assembler-hop"),
    ("packing", "rtti-read"), ("packing", "open-array"),
    ("alignment", "array-of-const"), ("alignment", "assembler-hop"),
    ("alignment", "rtti-read"),
    ("enum-base", "array-of-const"), ("enum-base", "assembler-hop"),
    ("enum-base", "rtti-read"), ("enum-base", "untyped-file"),
    ("char-width", "array-of-const"), ("char-width", "assembler-hop"),
    ("char-width", "rtti-read"), ("char-width", "typed-file"),
    ("char-width", "cross-unit"),
    # Delphi will not take a Char back out of a Variant without a conversion
    ("char-width", "variant"),
    ("codepage", "array-of-const"), ("codepage", "assembler-hop"),
    ("codepage", "rtti-read"), ("codepage", "untyped-file"),
    ("element-size", "array-of-const"), ("element-size", "assembler-hop"),
    ("element-size", "rtti-read"), ("element-size", "untyped-file"),
    ("buffer", "array-of-const"), ("buffer", "assembler-hop"),
    ("buffer", "rtti-read"), ("buffer", "untyped-file"),
    ("refcount", "array-of-const"), ("refcount", "assembler-hop"),
    ("refcount", "rtti-read"), ("refcount", "untyped-file"),
    ("provenance", "array-of-const"), ("provenance", "assembler-hop"),
    ("provenance", "rtti-read"), ("provenance", "untyped-file"),
    ("lifetime", "array-of-const"), ("lifetime", "assembler-hop"),
    ("lifetime", "rtti-read"), ("lifetime", "untyped-file"),
    ("lifetime", "inherited-call"), ("lifetime", "runtime-declaration"),
    ("directive-state", "array-of-const"), ("directive-state", "assembler-hop"),
    ("directive-state", "rtti-read"), ("directive-state", "untyped-file"),
    ("alias-visibility", "array-of-const"), ("alias-visibility", "rtti-read"),
    ("alias-visibility", "untyped-file"),
    # a raw byte move destroys everything a managed carrier owns, and a
    # message dispatch carries no value of its own
    ("codepage", "raw-move"), ("buffer", "raw-move"),
    ("refcount", "raw-move"), ("lifetime", "raw-move"),
    ("provenance", "raw-move"),
    ("codepage", "message-method"), ("buffer", "message-method"),
    ("refcount", "message-method"), ("lifetime", "message-method"),
    ("provenance", "message-method"), ("element-size", "message-method"),
    ("directive-state", "message-method"), ("directive-state", "raw-move"),
    ("directive-state", "tvalue"), ("directive-state", "class-helper"),
    ("alias-visibility", "raw-move"), ("alias-visibility", "message-method"),
    ("lifetime", "tvalue"), ("lifetime", "class-helper"),
    ("alignment", "tvalue"), ("alignment", "message-method"),
    ("packing", "tvalue"), ("packing", "message-method"),
    ("enum-base", "tvalue"), ("enum-base", "message-method"),
    ("char-width", "tvalue"), ("char-width", "message-method"),
    ("codepage", "tvalue"), ("provenance", "tvalue"),
    ("refcount", "tvalue"), ("element-size", "tvalue"),
    ("buffer", "tvalue"),
}


def matrix_pairs() -> list[tuple[str, str]]:
    """Every pair worth generating, in a stable order."""
    return [(p, t) for p in MATRIX_PASSENGERS for t in MATRIX_TRANSFERS
            if (p, t) not in MATRIX_SKIP]


# values where a lost narrowing or a lost sign actually shows: the middle of a
# range hides both, because the bits that would be cut are zero anyway
MATRIX_EDGES = {
    "width": ("SmallInt(-32767)", "SmallInt(32767)", "SmallInt(-1)",
              "SmallInt(256)"),
    "signedness": ("Cardinal($FFFFFFF0)", "Cardinal($80000000)",
                   "Cardinal($7FFFFFFF)", "Cardinal(1)"),
    "exact-type": ("Int64($7FFF0001)", "Int64(-2147483647)",
                   "Int64($0000FFFF)", "Int64(-1)"),
    "generic-arg": ("Int64($00ABCDEF)", "Int64(-8388607)", "Int64($7FFFFFFF)"),
    "method-data": ("Int64($0DEFACED)", "Int64(-16777215)"),
    "exception-identity": ("Int64($0FA11BAD)", "Int64(-65535)"),
}


def emit_matrix_carrier(e: Emitter, passenger: str, tag: str,
                        edge: int = 0) -> tuple[str, str]:
    """Declare the carrier for this passenger; return (type, setup)."""
    if passenger in ("codepage", "element-size", "buffer"):
        e.line("type")
        e.line("  TDvlMx%s = type AnsiString(1251);" % tag)
        e.line()
        return "TDvlMx%s" % tag, "TDvlMx%s(string(#$0416#$0438))" % tag
    if passenger == "lifetime":
        return "IInterface", "TDvlTagged.Create('m')"
    if passenger == "char-width":
        return "Char", "Char(#$0416)"
    if passenger == "packing":
        e.line("type")
        e.line("  TDvlMxPk%s = packed record" % tag)
        e.line("    Flag: Byte;")
        e.line("    Wide: Int64;")
        e.line("  end;")
        e.line()
        return "TDvlMxPk%s" % tag, "Default(TDvlMxPk%s)" % tag
    if passenger == "generic-arg":
        return "Int64", "Int64(%s)" % 0x00ABCDEF
    if passenger == "alignment":
        e.line("type")
        e.line("  TDvlMxAl%s = record" % tag)
        e.line("    Flag: Byte;")
        e.line("    Wide: Int64;")
        e.line("  end;")
        e.line()
        return "TDvlMxAl%s" % tag, "Default(TDvlMxAl%s)" % tag
    if passenger == "enum-base":
        e.line("type")
        e.line("  TDvlMxEnum%s = (dme%s_a, dme%s_b, dme%s_c);"
               % (tag, tag, tag, tag))
        e.line()
        return "TDvlMxEnum%s" % tag, "dme%s_b" % tag
    if passenger == "method-data":
        return "Int64", "Int64(%s)" % 0x0DEFACED
    if passenger == "exception-identity":
        return "Int64", "Int64(%s)" % 0x0FA11BAD
    if passenger == "refcount":
        # built at runtime on purpose: a literal-backed string carries
        # the marker count (dvl-0031), and that would drown every transfer in
        # one already-analysed fact instead of testing the transfer
        return "AnsiString", "Copy(AnsiString('shared%s!'), 1, 11)" % tag
    if passenger == "rtti-identity":
        return "Int64", "Int64(%s)" % 0x00C0FFEE
    if passenger == "provenance":
        e.line("type")
        e.line("  TDvlMxRaw%s = type AnsiString(1251);" % tag)
        e.line()
        return "TDvlMxRaw%s" % tag, "TDvlMxRaw%s(string(#$0416))" % tag
    if passenger in MATRIX_EDGES:
        values = MATRIX_EDGES[passenger]
        value = values[edge % len(values)]
        pascal = {"width": "SmallInt", "signedness": "Cardinal"}.get(
            passenger, "Int64")
        return pascal, value
    if passenger == "width":
        return "SmallInt", "SmallInt(-32767)"
    if passenger == "signedness":
        return "Cardinal", "Cardinal($FFFFFFF0)"
    if passenger == "exact-type":
        # the value fits Integer: a narrowing transfer must not be allowed to
        # lose data legitimately, or the pair proves nothing
        return "Int64", "Int64($7FFF0001)"
    if passenger == "alias-visibility":
        return "Int64", "Int64(%s)" % 0x1234ABCD
    return "Int64", "Int64(%s)" % 0x0BADC0DE


def emit_matrix_passport(e: Emitter, passenger: str, expr: str,
                         note: str) -> None:
    """Feed exactly the attribute this pair is about."""
    if passenger == "codepage":
        e.line("  DevilNoteLoose('%s', UInt64(StringCodePage(%s)));"
               % (note, expr))
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
    elif passenger == "element-size":
        e.line("  DevilFeed(UInt64(StringElementSize(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
    elif passenger == "buffer":
        e.line("  DevilFeed(UInt64(Ord(Pointer(%s) <> nil)));" % expr)
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
    elif passenger == "lifetime":
        e.line("  DevilFeed(UInt64(Ord(Assigned(%s))));" % expr)
        e.line("  DevilFeed(UInt64(Cardinal(TDvlTagged.Alive)));")
    elif passenger == "width":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Int64(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Int64(SmallInt(%s))));" % expr)
        e.line("  { narrowing to the unsigned type of the same width is where "
               "dvl-0001 and dvl-0026 lost the passenger }")
        e.line("  DevilFeed(UInt64(Word(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Byte(%s)));" % expr)
    elif passenger == "signedness":
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeed(UInt64(Ord(Int64(%s) < 0)));" % expr)
        e.line("  DevilFeed(UInt64(Int64(Integer(%s))));" % expr)
        e.line("  DevilFeed(UInt64(Word(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Cardinal(%s)));" % expr)
    elif passenger == "exact-type":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeed(UInt64(Cardinal(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Word(%s)));" % expr)
    elif passenger == "char-width":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(%s = #$0416)));" % expr)
    elif passenger == "packing":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(NativeUInt(@%s.Wide) - NativeUInt(@%s)));"
               % (expr, expr))
    elif passenger == "generic-arg":
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
    elif passenger == "char-width":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(%s = #$0416)));" % expr)
    elif passenger == "packing":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(NativeUInt(@%s.Wide) - NativeUInt(@%s)));"
               % (expr, expr))
    elif passenger == "generic-arg":
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
    elif passenger == "alignment":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(NativeUInt(@%s.Wide) - "
               "NativeUInt(@%s)));" % (expr, expr))
        e.line("  DevilFeed(UInt64(%s.Wide));" % expr)
    elif passenger == "enum-base":
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(%s)));" % expr)
    elif passenger in ("method-data", "exception-identity"):
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
    elif passenger == "refcount":
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(Pointer(%s) <> nil)));" % expr)
        e.line("  DevilNoteLoose('%s-refcount', "
               "UInt64(Cardinal(StringRefCount(%s))));" % (note, expr))
    elif passenger == "rtti-identity":
        e.line("  { the numbering of type kinds differs between compilers, "
               "so what goes into the stream is the meaning, not the number }")
        e.line("  DevilFeed(UInt64(Ord(PTypeInfo(TypeInfo(Int64))^.Kind = "
               "tkInt64)));")
        e.line("  DevilFeed(UInt64(%s));" % expr)
        e.line("  DevilFeedText(AnsiString(string("
               "PTypeInfo(TypeInfo(Int64))^.Name)));")
    elif passenger == "provenance":
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(Pointer(%s) <> nil)));" % expr)
        e.line("  DevilNoteLoose('%s-provenance', "
               "UInt64(StringCodePage(%s)));" % (note, expr))
    elif passenger == "directive-state":
        e.line("  DevilFeed(UInt64(%s));" % expr)
    else:   # alias-visibility
        e.line("  DevilFeed(UInt64(%s));" % expr)


def emit_matrix_transfer(e: Emitter, transfer: str, carrier: str,
                         tag: str, src: str, dst: str) -> None:
    """Move the carrier across one compiler boundary."""
    if transfer == "fold":
        e.line("  { the same value once where the compiler sees a constant "
               "and once where it does not }")
        e.line("  %s := %s(OpaqueU(UInt64(%s)));" % (dst, carrier, src)
               if carrier not in ("IInterface",) else "  %s := %s;" % (dst, src))
    elif transfer == "inline":
        e.line("  %s := DvlMxInline%s(%s);" % (dst, tag, src))
    elif transfer == "cross-unit":
        if carrier.startswith("TDvlMx"):
            e.line("  { text crosses the boundary as text }")
            e.line("  %s := %s(DvlCrossText(RawByteString(%s)));"
                   % (dst, carrier, src))
        elif carrier == "IInterface":
            e.line("  %s := %s;" % (dst, src))
        else:
            e.line("  %s := %s(DvlCrossGuarded(Int64(%s), @DvlMxIdentity%s));"
                   % (dst, carrier, src, tag))
    elif transfer == "specialization":
        e.line("  DvlMxBox%s.Value := %s;" % (tag, src))
        e.line("  %s := DvlMxBox%s.Value;" % (dst, tag))
    elif transfer == "closure":
        e.line("  DvlMxCaptured%s := %s;" % (tag, src))
        e.line("  DvlMxStep%s();" % tag)
        e.line("  %s := DvlMxCaptured%s;" % (dst, tag))
    elif transfer == "variant":
        e.line("  DvlMxVar%s := %s;" % (tag, src))
        e.line("  %s := DvlMxVar%s;" % (dst, tag))
    elif transfer == "thread":
        e.line("  %s := DvlMxThread%s(%s);" % (dst, tag, src))
    elif transfer == "narrow-widen":
        e.line("  { down to a narrow type and back: the classic place a "
               "passenger is left behind }")
        e.line("  %s := %s(Integer(%s));" % (dst, carrier, src))
    elif transfer == "unwind":
        e.line("  %s := DvlMxUnwind%s(%s);" % (dst, tag, src))
    elif transfer == "record-copy":
        e.line("  DvlMxRec%s.Payload := %s;" % (tag, src))
        e.line("  DvlMxRecCopy%s := DvlMxRec%s;" % (tag, tag))
        e.line("  %s := DvlMxRecCopy%s.Payload;" % (dst, tag))
    elif transfer == "interface-cast":
        e.line("  DvlMxHolder%s.Payload := %s;" % (tag, src))
        e.line("  %s := (DvlMxHolder%s as IDvlMxCarry%s).Take;" % (dst, tag, tag))
    elif transfer == "typed-file":
        e.line("  %s := DvlMxFile%s(%s);" % (dst, tag, src))
    elif transfer == "property-accessor":
        e.line("  DvlMxProp%s.Value := %s;" % (tag, src))
        e.line("  %s := DvlMxProp%s.Value;" % (dst, tag))
    elif transfer == "open-array":
        e.line("  %s := DvlMxOpen%s([%s]);" % (dst, tag, src))
    elif transfer == "const-param":
        e.line("  %s := DvlMxConst%s(%s);" % (dst, tag, src))
    elif transfer == "array-of-const":
        e.line("  %s := %s(DvlMxVariadic%s([%s]));" % (dst, carrier, tag, src)
               if carrier in ("Int64", "Cardinal", "SmallInt")
               else "  %s := %s;" % (dst, src))
    elif transfer == "assembler-hop":
        e.line("  %s := %s(DvlMxAsm%s(Int64(%s)));" % (dst, carrier, tag, src)
               if carrier in ("Int64", "Cardinal", "SmallInt")
               else "  %s := %s;" % (dst, src))
    elif transfer == "rtti-read":
        e.line("  DvlMxRtti%s.Slot := %s;" % (tag, src))
        e.line("  %s := %s(DvlMxRttiRead%s);" % (dst, carrier, tag))
    elif transfer == "untyped-file":
        e.line("  %s := DvlMxRaw%s(%s);" % (dst, tag, src))
    elif transfer == "inherited-call":
        e.line("  %s := DvlMxInherit%s.Pass(%s);" % (dst, tag, src))
    elif transfer == "raw-move":
        e.line("  { moved as raw bytes: nothing above the byte level survives "
               "by construction, so everything above it must be rebuilt right }")
        e.line("  Move(%s, %s, SizeOf(%s));" % (src, dst, src))
    elif transfer == "tvalue":
        e.line("  %s := DvlMxTValue%s(%s);" % (dst, tag, src))
    elif transfer == "message-method":
        e.line("  DvlMxMsg%s.Payload := %s;" % (tag, src))
        e.line("  DvlMxMsg%s.Dispatch(DvlMxMsgRec%s);" % (tag, tag))
        e.line("  %s := DvlMxMsg%s.Payload;" % (dst, tag))
    elif transfer == "class-helper":
        e.line("  %s := DvlMxHelperCall%s(%s);" % (dst, tag, src))
    elif transfer == "runtime-declaration":
        e.line("  { the binding is created here, after statements have "
               "already run, not in the header of the routine }")
        e.line("  var Fresh := %s;" % src)
        e.line("  %s := Fresh;" % dst)
    elif transfer == "array-detach":
        e.line("  SetLength(DvlMxArr%s, 2);" % tag)
        e.line("  DvlMxArr%s[1] := %s;" % (tag, src))
        e.line("  DvlMxArrCopy%s := Copy(DvlMxArr%s, 1, 1);" % (tag, tag))
        e.line("  DvlMxArr%s[1] := Default(%s);" % (tag, carrier))
        e.line("  %s := DvlMxArrCopy%s[0];" % (dst, tag))
    elif transfer == "array-of-const":
        e.line("  %s := %s(DvlMxVariadic%s([%s]));" % (dst, carrier, tag, src)
               if carrier in ("Int64", "Cardinal", "SmallInt")
               else "  %s := %s;" % (dst, src))
    elif transfer == "assembler-hop":
        e.line("  %s := %s(DvlMxAsm%s(Int64(%s)));" % (dst, carrier, tag, src)
               if carrier in ("Int64", "Cardinal", "SmallInt")
               else "  %s := %s;" % (dst, src))
    elif transfer == "rtti-read":
        e.line("  DvlMxRtti%s.Slot := %s;" % (tag, src))
        e.line("  %s := %s(DvlMxRttiRead%s);" % (dst, carrier, tag))
    elif transfer == "untyped-file":
        e.line("  %s := DvlMxRaw%s(%s);" % (dst, tag, src))
    elif transfer == "inherited-call":
        e.line("  %s := DvlMxInherit%s.Pass(%s);" % (dst, tag, src))
    elif transfer == "raw-move":
        e.line("  { moved as raw bytes: nothing above the byte level survives "
               "by construction, so everything above it must be rebuilt right }")
        e.line("  Move(%s, %s, SizeOf(%s));" % (src, dst, src))
    elif transfer == "tvalue":
        e.line("  %s := DvlMxTValue%s(%s);" % (dst, tag, src))
    elif transfer == "message-method":
        e.line("  DvlMxMsg%s.Payload := %s;" % (tag, src))
        e.line("  DvlMxMsg%s.Dispatch(DvlMxMsgRec%s);" % (tag, tag))
        e.line("  %s := DvlMxMsg%s.Payload;" % (dst, tag))
    elif transfer == "class-helper":
        e.line("  %s := DvlMxHelperCall%s(%s);" % (dst, tag, src))
    elif transfer == "runtime-declaration":
        e.line("  { the binding comes into existence here, after statements "
               "have already run, not in the header of the routine }")
        e.line("  var Fresh := %s;" % src)
        e.line("  %s := Fresh;" % dst)
    else:   # virtual-call
        e.line("  %s := DvlMxVirtual%s.Pass(%s);" % (dst, tag, src))


# сколько живых целых держать поперёк пересадки: больше, чем свободных
# регистров общего назначения, чтобы распределителю пришлось спиллить
PRESSURE_WIDTH = 12


def emit_pressure_open(e: Emitter, tag: str) -> None:
    """Занять банк живыми значениями и войти в кадр исключения."""
    e.line("  { давление: банк занят живыми значениями, и все они переживают "
           "пересадку }")
    for slot in range(PRESSURE_WIDTH):
        e.line("  var Load%d: Int64 := OpaqueI(%d);" % (slot, 0x51 + slot * 7))
    e.line("  var LoadText: AnsiString := Copy(AnsiString('pressure!'), 1, 8);")
    e.line("  var LoadHold: IInterface := TInterfacedObject.Create;")
    # выражение, которое читает все слоты сразу: без него распределитель вправе
    # держать их в памяти и давления не будет
    e.line("  Load0 := Load0 xor (%s);"
           % " xor ".join("Load%d" % slot for slot in range(1, PRESSURE_WIDTH)))
    e.line("  try")


def emit_pressure_close(e: Emitter, tag: str) -> None:
    """Потребить всё, что держали: значение обязано дожить до сюда."""
    e.line("  finally")
    e.line("    { потребление после пересадки — то, что делает значения живыми "
           "поперёк неё }")
    for slot in range(PRESSURE_WIDTH):
        e.line("    DevilFeed(UInt64(Load%d));" % slot)
    e.line("    DevilFeed(UInt64(Length(LoadText)));")
    e.line("    DevilFeed(UInt64(Ord(LoadHold <> nil)));")
    e.line("    LoadHold := nil;")
    e.line("  end;")


def layer_matrix(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """Every passenger across every transfer, systematically."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    pairs = matrix_pairs()
    base = rng.randrange(len(pairs))
    for index in range(start, start + count):
        passenger, transfer = pairs[(base + index) % len(pairs)]
        # every full sweep of the pairs moves to the next edge value
        edge = ((base + index) // len(pairs)) % 4
        # каждый третий кейс едет под давлением на распределитель
        pressure = index % 3 == 1
        name = "dvl-matrix-%s-%s-e%d%s" % (passenger, transfer, edge,
                                           "-p" if pressure else "")
        proc = "DvlMx%05d" % index
        tag = "%05d" % index

        carrier, setup = emit_matrix_carrier(e, passenger, tag, edge)

        # machinery this transfer needs, declared before the case body
        if transfer == "inline":
            e.line("function DvlMxInline%s(const V: %s): %s; inline;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
        elif transfer == "cross-unit":
            e.line("function DvlMxToInt%s(const V: %s): Int64;" % (tag, carrier))
            e.line("begin")
            e.line("  Result := Int64(Length(AnsiString(V)));"
                   if carrier.startswith("TDvlMx") else "  Result := Int64(V);")
            e.line("end;")
            e.line()
            e.line("function DvlMxIdentity%s(X: Int64): Int64;" % tag)
            e.line("begin")
            e.line("  Result := X;")
            e.line("end;")
            e.line()
        elif transfer == "specialization":
            e.line("type")
            e.line("  TDvlMxBox%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("  end;")
            e.line()
            e.line("var")
            e.line("  DvlMxBox%s: TDvlMxBox%s<%s>;" % (tag, tag, carrier))
            e.line()
        elif transfer == "closure":
            e.line("type")
            e.line("  TDvlMxStep%s = reference to procedure;" % tag)
            e.line()
            e.line("var")
            e.line("  DvlMxCaptured%s: %s;" % (tag, carrier))
            e.line("  DvlMxStep%s: TDvlMxStep%s;" % (tag, tag))
            e.line()
        elif transfer == "variant":
            e.line("var")
            e.line("  DvlMxVar%s: Variant;" % tag)
            e.line()
        elif transfer == "thread":
            e.line("type")
            e.line("  TDvlMxWorker%s = class(TThread)" % tag)
            e.line("  public")
            e.line("    Input, Output: %s;" % carrier)
            e.line("    procedure Execute; override;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlMxWorker%s.Execute;" % tag)
            e.line("begin")
            e.line("  Output := Input;")
            e.line("end;")
            e.line()
            e.line("function DvlMxThread%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  Worker: TDvlMxWorker%s;" % tag)
            e.line("begin")
            e.line("  Worker := TDvlMxWorker%s.Create(True);" % tag)
            e.line("  try")
            e.line("    Worker.FreeOnTerminate := False;")
            e.line("    Worker.Input := V;")
            e.line("    Worker.Start;")
            e.line("    Worker.WaitFor;")
            e.line("    Result := Worker.Output;")
            e.line("  finally")
            e.line("    Worker.Free;")
            e.line("  end;")
            e.line("end;")
            e.line()
        elif transfer == "unwind":
            e.line("type")
            e.line("  EDvlMx%s = class(Exception)" % tag)
            e.line("  public")
            e.line("    Payload: %s;" % carrier)
            e.line("  end;")
            e.line()
            e.line("function DvlMxUnwind%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  Failure: EDvlMx%s;" % tag)
            e.line("begin")
            e.line("  Result := V;")
            e.line("  try")
            e.line("    Failure := EDvlMx%s.Create('carry');" % tag)
            e.line("    Failure.Payload := V;")
            e.line("    raise Failure;")
            e.line("  except")
            e.line("    on E: EDvlMx%s do" % tag)
            e.line("      Result := E.Payload;")
            e.line("  end;")
            e.line("end;")
            e.line()
        elif transfer == "record-copy":
            e.line("type")
            e.line("  TDvlMxRec%s = record" % tag)
            e.line("    Head: AnsiString;")
            e.line("    Payload: %s;" % carrier)
            e.line("    Tail: Int64;")
            e.line("  end;")
            e.line()
            e.line("var")
            e.line("  DvlMxRec%s, DvlMxRecCopy%s: TDvlMxRec%s;"
                   % (tag, tag, tag))
            e.line()
        elif transfer == "interface-cast":
            e.line("type")
            e.line("  IDvlMxCarry%s = interface" % tag)
            e.line("    ['{3C%06X-0000-0000-0000-000000000001}']"
                   % (index % 0xFFFFFF))
            e.line("    function Take: %s;" % carrier)
            e.line("  end;")
            e.line()
            e.line("  TDvlMxHolder%s = class(TInterfacedObject, IDvlMxCarry%s)"
                   % (tag, tag))
            e.line("  public")
            e.line("    Payload: %s;" % carrier)
            e.line("    function Take: %s;" % carrier)
            e.line("  end;")
            e.line()
            e.line("function TDvlMxHolder%s.Take: %s;" % (tag, carrier))
            e.line("begin")
            e.line("  Result := Payload;")
            e.line("end;")
            e.line()
            e.line("var")
            e.line("  DvlMxHolder%s: TDvlMxHolder%s;" % (tag, tag))
            e.line()
        elif transfer == "typed-file":
            e.line("function DvlMxFile%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  F: file of Int64;")
            e.line("  Path: string;")
            e.line("  Slot: Int64;")
            e.line("begin")
            e.line("  { only the shape of the value survives a typed file, so "
                   "the carrier rides beside a value that does }")
            e.line("  Result := V;")
            e.line("  Path := IncludeTrailingPathDelimiter(GetCurrentDir) + "
                   "'dvl_mx_%s.tmp';" % tag)
            e.line("  Slot := Length(AnsiString(V));"
                   if carrier.startswith("TDvlMx") or carrier == "AnsiString"
                   else "  Slot := Int64(V);")
            e.line("  AssignFile(F, Path);")
            e.line("  Rewrite(F);")
            e.line("  try")
            e.line("    Write(F, Slot);")
            e.line("    Seek(F, 0);")
            e.line("    Read(F, Slot);")
            e.line("  finally")
            e.line("    CloseFile(F);")
            e.line("    If FileExists(Path) then")
            e.line("      DeleteFile(Path);")
            e.line("  end;")
            e.line("  DevilFeed(UInt64(Slot));")
            e.line("end;")
            e.line()
        elif transfer == "property-accessor":
            e.line("type")
            e.line("  TDvlMxProp%s = class" % tag)
            e.line("  private")
            e.line("    FValue: %s;" % carrier)
            e.line("    function GetValue: %s;" % carrier)
            e.line("    procedure SetValue(const AValue: %s);" % carrier)
            e.line("  public")
            e.line("    property Value: %s read GetValue write SetValue;"
                   % carrier)
            e.line("  end;")
            e.line()
            e.line("function TDvlMxProp%s.GetValue: %s;" % (tag, carrier))
            e.line("begin")
            e.line("  Result := FValue;")
            e.line("end;")
            e.line()
            e.line("procedure TDvlMxProp%s.SetValue(const AValue: %s);"
                   % (tag, carrier))
            e.line("begin")
            e.line("  FValue := AValue;")
            e.line("end;")
            e.line()
            e.line("var")
            e.line("  DvlMxProp%s: TDvlMxProp%s;" % (tag, tag))
            e.line()
        elif transfer == "open-array":
            e.line("function DvlMxOpen%s(const Items: array of %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := Items[High(Items)];")
            e.line("end;")
            e.line()
        elif transfer == "const-param":
            e.line("function DvlMxConst%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
        elif transfer == "raw-move":
            pass
        elif transfer == "tvalue":
            e.line("function DvlMxTValue%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  Boxed: TValue;")
            e.line("begin")
            e.line("  { out through the runtime's universal box and back }")
            e.line("  Boxed := TValue.From<%s>(V);" % carrier)
            e.line("  Result := Boxed.AsType<%s>;" % carrier)
            e.line("end;")
            e.line()
        elif transfer == "message-method":
            e.line("type")
            e.line("  TDvlMxMsgRec%s = record" % tag)
            e.line("    Msg: Cardinal;")
            e.line("    Slot: Int64;")
            e.line("  end;")
            e.line()
            e.line("  TDvlMxMsgHandler%s = class" % tag)
            e.line("  public")
            e.line("    Payload: %s;" % carrier)
            e.line("    procedure Handle(var Message: TDvlMxMsgRec%s); "
                   "message 42;" % tag)
            e.line("  end;")
            e.line()
            e.line("procedure TDvlMxMsgHandler%s.Handle("
                   "var Message: TDvlMxMsgRec%s);" % (tag, tag))
            e.line("begin")
            e.line("  { the value survives a dispatch that goes by number, not "
                   "by name }")
            e.line("  Message.Slot := SizeOf(Payload);")
            e.line("end;")
            e.line()
            e.line("var")
            e.line("  DvlMxMsg%s: TDvlMxMsgHandler%s;" % (tag, tag))
            e.line("  DvlMxMsgRec%s: TDvlMxMsgRec%s;" % (tag, tag))
            e.line()
        elif transfer == "class-helper":
            e.line("type")
            e.line("  TDvlMxHelperHost%s = class" % tag)
            e.line("  public")
            e.line("    Payload: %s;" % carrier)
            e.line("  end;")
            e.line("  TDvlMxHelper%s = class helper for TDvlMxHelperHost%s"
                   % (tag, tag))
            e.line("  public")
            e.line("    function Echo: %s;" % carrier)
            e.line("  end;")
            e.line()
            e.line("function TDvlMxHelper%s.Echo: %s;" % (tag, carrier))
            e.line("begin")
            e.line("  Result := Payload;")
            e.line("end;")
            e.line()
            e.line("function DvlMxHelperCall%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  Host: TDvlMxHelperHost%s;" % tag)
            e.line("begin")
            e.line("  Host := TDvlMxHelperHost%s.Create;" % tag)
            e.line("  try")
            e.line("    Host.Payload := V;")
            e.line("    { the method comes from a helper, not from the class }")
            e.line("    Result := Host.Echo;")
            e.line("  finally")
            e.line("    Host.Free;")
            e.line("  end;")
            e.line("end;")
            e.line()
        elif transfer == "array-of-const":
            e.line("function DvlMxVariadic%s(const Args: array of const): Int64;"
                   % tag)
            e.line("begin")
            e.line("  Result := 0;")
            e.line("  If Length(Args) > 0 then")
            e.line("    case Args[0].VType of")
            e.line("      vtInteger: Result := Args[0].VInteger;")
            e.line("      vtInt64: Result := Args[0].VInt64^;")
            e.line("    else")
            e.line("      Result := 0;")
            e.line("    end;")
            e.line("end;")
            e.line()
        elif transfer == "assembler-hop":
            e.line("function DvlMxAsm%s(X: Int64): Int64; assembler;" % tag)
            e.line("asm")
            e.line("  {$ifdef MSWINDOWS}")
            e.line("  MOV RAX, RCX")
            e.line("  {$else}")
            e.line("  MOV RAX, RDI")
            e.line("  {$endif}")
            e.line("end;")
            e.line()
        elif transfer == "rtti-read":
            e.line("type")
            e.line("  {$M+}")
            e.line("  TDvlMxRttiHolder%s = class" % tag)
            e.line("  private")
            e.line("    FSlot: Int64;")
            e.line("  published")
            e.line("    property Slot: Int64 read FSlot write FSlot;")
            e.line("  end;")
            e.line("  {$M-}")
            e.line()
            e.line("var")
            e.line("  DvlMxRtti%s: TDvlMxRttiHolder%s;" % (tag, tag))
            e.line()
            e.line("function DvlMxRttiRead%s: Int64;" % tag)
            e.line("var")
            e.line("  Info: PPropInfo;")
            e.line("begin")
            e.line("  { the value comes back through the published surface, "
                   "not through the field }")
            e.line("  Info := GetPropInfo(DvlMxRtti%s, 'Slot');" % tag)
            e.line("  If Info <> nil then")
            e.line("    Result := GetInt64Prop(DvlMxRtti%s, Info)" % tag)
            e.line("  else")
            e.line("    Result := 0;")
            e.line("end;")
            e.line()
        elif transfer == "untyped-file":
            e.line("function DvlMxRaw%s(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("var")
            e.line("  F: file;")
            e.line("  Path: string;")
            e.line("  Buffer: %s;" % carrier)
            e.line("  Moved: Integer;")
            e.line("begin")
            e.line("  Buffer := V;")
            e.line("  Path := IncludeTrailingPathDelimiter(GetCurrentDir) + "
                   "'dvl_mxraw_%s.tmp';" % tag)
            e.line("  AssignFile(F, Path);")
            e.line("  Rewrite(F, 1);")
            e.line("  try")
            e.line("    { the value goes out as bytes and comes back as bytes }")
            e.line("    BlockWrite(F, Buffer, SizeOf(Buffer), Moved);")
            e.line("    Seek(F, 0);")
            e.line("    FillChar(Buffer, SizeOf(Buffer), 0);")
            e.line("    BlockRead(F, Buffer, SizeOf(Buffer), Moved);")
            e.line("  finally")
            e.line("    CloseFile(F);")
            e.line("    If FileExists(Path) then")
            e.line("      DeleteFile(Path);")
            e.line("  end;")
            e.line("  Result := Buffer;")
            e.line("end;")
            e.line()
        elif transfer == "inherited-call":
            e.line("type")
            e.line("  TDvlMxBaseI%s = class" % tag)
            e.line("  public")
            e.line("    function Pass(const V: %s): %s; virtual;"
                   % (carrier, carrier))
            e.line("  end;")
            e.line("  TDvlMxLeafI%s = class(TDvlMxBaseI%s)" % (tag, tag))
            e.line("  public")
            e.line("    function Pass(const V: %s): %s; override;"
                   % (carrier, carrier))
            e.line("  end;")
            e.line()
            e.line("function TDvlMxBaseI%s.Pass(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            e.line("function TDvlMxLeafI%s.Pass(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  { the value passes through the inherited implementation, "
                   "not around it }")
            e.line("  Result := inherited Pass(V);")
            e.line("end;")
            e.line()
            e.line("var")
            e.line("  DvlMxInherit%s: TDvlMxBaseI%s;" % (tag, tag))
            e.line()
        elif transfer == "array-detach":
            e.line("var")
            e.line("  DvlMxArr%s, DvlMxArrCopy%s: System.TArray<%s>;"
                   % (tag, tag, carrier))
            e.line()
        elif transfer == "virtual-call":
            e.line("type")
            e.line("  TDvlMxBase%s = class" % tag)
            e.line("  public")
            e.line("    function Pass(const V: %s): %s; virtual;"
                   % (carrier, carrier))
            e.line("  end;")
            e.line("  TDvlMxLeaf%s = class(TDvlMxBase%s)" % (tag, tag))
            e.line("  public")
            e.line("    function Pass(const V: %s): %s; override;"
                   % (carrier, carrier))
            e.line("  end;")
            e.line()
            e.line("function TDvlMxBase%s.Pass(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            e.line("function TDvlMxLeaf%s.Pass(const V: %s): %s;"
                   % (tag, carrier, carrier))
            e.line("begin")
            e.line("  Result := inherited Pass(V);")
            e.line("end;")
            e.line()
            e.line("var")
            e.line("  DvlMxVirtual%s: TDvlMxBase%s;" % (tag, tag))
            e.line()

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Before, After: %s;" % carrier)
        e.line("begin")
        e.line("  { passenger %s across the %s boundary }" % (passenger, transfer))
        if pressure:
            emit_pressure_open(e, tag)
        e.line("  Before := %s;" % setup)
        emit_matrix_passport(e, passenger, "Before", "%s-before" % name)
        # порядковый канал: под потоковым ветвлением его ставить нельзя —
        # две ветви кормят поток вперемешку
        ordered = transfer != "thread"
        if ordered:
            e.line("  DevilStep('%s-enter');" % name)

        if transfer == "closure":
            e.line("  DvlMxStep%s :=" % tag)
            e.line("    procedure")
            e.line("    begin")
            e.line("      DvlMxCaptured%s := DvlMxCaptured%s;" % (tag, tag))
            e.line("    end;")
        elif transfer == "interface-cast":
            e.line("  DvlMxHolder%s := TDvlMxHolder%s.Create;" % (tag, tag))
        elif transfer == "virtual-call":
            e.line("  DvlMxVirtual%s := TDvlMxLeaf%s.Create;" % (tag, tag))
        elif transfer == "property-accessor":
            e.line("  DvlMxProp%s := TDvlMxProp%s.Create;" % (tag, tag))
        elif transfer == "rtti-read":
            e.line("  DvlMxRtti%s := TDvlMxRttiHolder%s.Create;" % (tag, tag))
        elif transfer == "message-method":
            e.line("  DvlMxMsg%s := TDvlMxMsgHandler%s.Create;" % (tag, tag))
            e.line("  DvlMxMsgRec%s.Msg := 42;" % tag)
        elif transfer == "inherited-call":
            e.line("  DvlMxInherit%s := TDvlMxLeafI%s.Create;" % (tag, tag))

        e.line("  try")
        emit_matrix_transfer(e, transfer, carrier, tag, "Before", "After")
        emit_matrix_passport(e, passenger, "After", "%s-after" % name)
        e.line("  { the passenger must have arrived: what the language fixes "
               "is asserted, the rest is in the bloodstream }")
        if passenger in ("width", "signedness", "exact-type",
                         "alias-visibility", "directive-state",
                         "rtti-identity", "enum-base", "method-data",
                         "exception-identity", "char-width", "generic-arg"):
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Before = After)), 1);" % name)
        elif passenger in ("codepage", "element-size", "buffer",
                           "refcount", "provenance"):
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Length(Before) = Length(After))), 1);" % name)
        elif passenger in ("alignment", "packing"):
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(SizeOf(Before) = SizeOf(After))), 1);" % name)
        else:
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Assigned(After))), 1);" % name)
        e.line("  finally")
        if transfer == "interface-cast":
            e.line("    DvlMxHolder%s := nil;" % tag)
        elif transfer == "virtual-call":
            e.line("    DvlMxVirtual%s.Free;" % tag)
        elif transfer == "closure":
            e.line("    DvlMxStep%s := nil;" % tag)
        elif transfer == "property-accessor":
            e.line("    DvlMxProp%s.Free;" % tag)
        elif transfer == "rtti-read":
            e.line("    DvlMxRtti%s.Free;" % tag)
        elif transfer == "message-method":
            e.line("    DvlMxMsg%s.Free;" % tag)
        elif transfer == "inherited-call":
            e.line("    DvlMxInherit%s.Free;" % tag)
        else:
            e.line("    ;")
        e.line("  end;")
        if pressure:
            emit_pressure_close(e, tag)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="matrix",
                                  detail={"passenger": passenger,
                                          "transfer": transfer,
                                          "edge": edge,
                                          "pressure": pressure}))

    emit_runner(e, "Matrix", calls)
    return records


# boundaries that can be chained without any surrounding object
COMPOSITE_TRANSFERS = ("fold", "inline", "narrow-widen", "const-param",
                       "runtime-declaration", "unwind", "record-copy",
                       "assembler-hop", "open-array", "closure-value",
                       "thread", "interface-cast", "virtual-call",
                       "specialization", "property-accessor", "cross-unit",
                       "variant")

# carriers these boundaries can all move
COMPOSITE_PASSENGERS = ("width", "signedness", "exact-type", "generic-arg",
                        "method-data", "enum-base", "codepage", "buffer",
                        "refcount", "lifetime")

COMPOSITE_SKIP = {
    ("enum-base", "narrow-widen"), ("enum-base", "assembler-hop"),
    ("enum-base", "fold"), ("enum-base", "unwind"),
    # a Variant will not give a narrow ordinal back without a conversion
    ("enum-base", "variant"), ("width", "variant"),
    ("enum-base", "cross-unit"),
    # a managed or text carrier cannot ride a boundary that moves an ordinal
    ("codepage", "narrow-widen"), ("codepage", "assembler-hop"),
    ("codepage", "cross-unit"), ("codepage", "variant"),
    ("codepage", "fold"),
    ("buffer", "narrow-widen"), ("buffer", "assembler-hop"),
    ("buffer", "cross-unit"), ("buffer", "fold"),
    ("refcount", "narrow-widen"), ("refcount", "assembler-hop"),
    ("refcount", "cross-unit"), ("refcount", "fold"),
    ("lifetime", "narrow-widen"), ("lifetime", "assembler-hop"),
    ("lifetime", "cross-unit"), ("lifetime", "fold"),
    ("lifetime", "variant"), ("lifetime", "open-array"),
    ("lifetime", "record-copy"), ("lifetime", "unwind"),
}


def composite_carrier(passenger: str) -> tuple[str, str]:
    if passenger == "codepage":
        return "RawByteString", "RawByteString(AnsiString('cp1251'))"
    if passenger == "buffer":
        return "AnsiString", "AnsiString('buffered value')"
    if passenger == "refcount":
        return "AnsiString", "AnsiString('counted value')"
    if passenger == "lifetime":
        return "IInterface", "TDvlTagged.Create('k')"
    if passenger == "width":
        return "SmallInt", "SmallInt(-32767)"
    if passenger == "signedness":
        return "Cardinal", "Cardinal($FFFFFFF0)"
    if passenger == "enum-base":
        return "Byte", "Byte(200)"
    return "Int64", "Int64($7FFF0001)"


def composite_passport(e: Emitter, passenger: str, expr: str) -> None:
    if passenger in ("codepage", "buffer", "refcount"):
        e.line("  DevilFeed(UInt64(Length(%s)));" % expr)
        e.line("  DevilFeed(UInt64(StringElementSize(%s)));" % expr)
        e.line("  DevilFeed(UInt64(Ord(Pointer(%s) <> nil)));" % expr)
        e.line("  DevilFeedText(AnsiString(%s));" % expr)
        return
    if passenger == "lifetime":
        e.line("  DevilFeed(UInt64(Ord(Assigned(%s))));" % expr)
        e.line("  DevilFeed(UInt64(Cardinal(TDvlTagged.Alive)));")
        return
    e.line("  DevilFeed(UInt64(SizeOf(%s)));" % expr)
    e.line("  DevilFeed(UInt64(%s));" % expr)
    e.line("  DevilFeed(UInt64(Int64(Integer(%s))));" % expr)
    e.line("  DevilFeed(UInt64(Ord(Int64(%s) < 0)));" % expr)


def composite_helpers(e: Emitter, transfer: str, carrier: str, tag: str,
                      slot: str) -> None:
    """Whatever the boundary needs, declared before the case body."""
    if transfer == "inline":
        e.line("function DvlCx%s%s(const V: %s): %s; inline;"
               % (slot, tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := V;")
        e.line("end;")
        e.line()
    elif transfer == "const-param":
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := V;")
        e.line("end;")
        e.line()
    elif transfer == "unwind":
        e.line("type")
        e.line("  EDvlCx%s%s = class(Exception)" % (slot, tag))
        e.line("  public")
        e.line("    Payload: %s;" % carrier)
        e.line("  end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Failure: EDvlCx%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Result := V;")
        e.line("  try")
        e.line("    Failure := EDvlCx%s%s.Create('x');" % (slot, tag))
        e.line("    Failure.Payload := V;")
        e.line("    raise Failure;")
        e.line("  except")
        e.line("    on E: EDvlCx%s%s do" % (slot, tag))
        e.line("      Result := E.Payload;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif transfer == "record-copy":
        e.line("type")
        e.line("  TDvlCx%s%s = record" % (slot, tag))
        e.line("    Head: AnsiString;")
        e.line("    Payload: %s;" % carrier)
        e.line("  end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Source, Target: TDvlCx%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Source.Head := AnsiString('copy');")
        e.line("  Source.Payload := V;")
        e.line("  Target := Source;")
        e.line("  Result := Target.Payload;")
        e.line("end;")
        e.line()
    elif transfer == "assembler-hop":
        e.line("function DvlCxAsm%s%s(X: Int64): Int64; assembler;"
               % (slot, tag))
        e.line("asm")
        e.line("  {$ifdef MSWINDOWS}")
        e.line("  MOV RAX, RCX")
        e.line("  {$else}")
        e.line("  MOV RAX, RDI")
        e.line("  {$endif}")
        e.line("end;")
        e.line()
    elif transfer == "open-array":
        e.line("function DvlCx%s%s(const Items: array of %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := Items[High(Items)];")
        e.line("end;")
        e.line()
    elif transfer == "closure-value":
        e.line("type")
        e.line("  TDvlCxStep%s%s = reference to function(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line()
    elif transfer == "thread":
        e.line("type")
        e.line("  TDvlCxW%s%s = class(TThread)" % (slot, tag))
        e.line("  public")
        e.line("    Input, Output: %s;" % carrier)
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlCxW%s%s.Execute;" % (slot, tag))
        e.line("begin")
        e.line("  Output := Input;")
        e.line("end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Worker: TDvlCxW%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Worker := TDvlCxW%s%s.Create(True);" % (slot, tag))
        e.line("  try")
        e.line("    Worker.FreeOnTerminate := False;")
        e.line("    Worker.Input := V;")
        e.line("    Worker.Start;")
        e.line("    Worker.WaitFor;")
        e.line("    Result := Worker.Output;")
        e.line("  finally")
        e.line("    Worker.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif transfer == "interface-cast":
        e.line("type")
        e.line("  IDvlCx%s%s = interface" % (slot, tag))
        e.line("    ['{2B%06X-0000-0000-0000-0000000000%02X}']"
               % (int(tag) % 0xFFFFFF, 1 if slot == "A" else 2))
        e.line("    function Take: %s;" % carrier)
        e.line("  end;")
        e.line()
        e.line("  TDvlCxH%s%s = class(TInterfacedObject, IDvlCx%s%s)"
               % (slot, tag, slot, tag))
        e.line("  public")
        e.line("    Payload: %s;" % carrier)
        e.line("    function Take: %s;" % carrier)
        e.line("  end;")
        e.line()
        e.line("function TDvlCxH%s%s.Take: %s;" % (slot, tag, carrier))
        e.line("begin")
        e.line("  Result := Payload;")
        e.line("end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Holder: TDvlCxH%s%s;" % (slot, tag))
        e.line("  Carry: IDvlCx%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Holder := TDvlCxH%s%s.Create;" % (slot, tag))
        e.line("  Holder.Payload := V;")
        e.line("  Carry := Holder;")
        e.line("  Result := (Carry as IDvlCx%s%s).Take;" % (slot, tag))
        e.line("end;")
        e.line()
    elif transfer == "virtual-call":
        e.line("type")
        e.line("  TDvlCxB%s%s = class" % (slot, tag))
        e.line("  public")
        e.line("    function Pass(const V: %s): %s; virtual;"
               % (carrier, carrier))
        e.line("  end;")
        e.line("  TDvlCxL%s%s = class(TDvlCxB%s%s)" % (slot, tag, slot, tag))
        e.line("  public")
        e.line("    function Pass(const V: %s): %s; override;"
               % (carrier, carrier))
        e.line("  end;")
        e.line()
        e.line("function TDvlCxB%s%s.Pass(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := V;")
        e.line("end;")
        e.line()
        e.line("function TDvlCxL%s%s.Pass(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := inherited Pass(V);")
        e.line("end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Obj: TDvlCxB%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Obj := TDvlCxL%s%s.Create;" % (slot, tag))
        e.line("  try")
        e.line("    Result := Obj.Pass(V);")
        e.line("  finally")
        e.line("    Obj.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif transfer == "specialization":
        e.line("type")
        e.line("  TDvlCxBox%s%s<T> = record" % (slot, tag))
        e.line("    Value: T;")
        e.line("    function Read: T;")
        e.line("  end;")
        e.line()
        e.line("function TDvlCxBox%s%s<T>.Read: T;" % (slot, tag))
        e.line("begin")
        e.line("  Result := Value;")
        e.line("end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Box: TDvlCxBox%s%s<%s>;" % (slot, tag, carrier))
        e.line("begin")
        e.line("  Box.Value := V;")
        e.line("  Result := Box.Read;")
        e.line("end;")
        e.line()
    elif transfer == "property-accessor":
        e.line("type")
        e.line("  TDvlCxP%s%s = class" % (slot, tag))
        e.line("  private")
        e.line("    FValue: %s;" % carrier)
        e.line("    function GetValue: %s;" % carrier)
        e.line("    procedure SetValue(const AValue: %s);" % carrier)
        e.line("  public")
        e.line("    property Value: %s read GetValue write SetValue;" % carrier)
        e.line("  end;")
        e.line()
        e.line("function TDvlCxP%s%s.GetValue: %s;" % (slot, tag, carrier))
        e.line("begin")
        e.line("  Result := FValue;")
        e.line("end;")
        e.line()
        e.line("procedure TDvlCxP%s%s.SetValue(const AValue: %s);"
               % (slot, tag, carrier))
        e.line("begin")
        e.line("  FValue := AValue;")
        e.line("end;")
        e.line()
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Holder: TDvlCxP%s%s;" % (slot, tag))
        e.line("begin")
        e.line("  Holder := TDvlCxP%s%s.Create;" % (slot, tag))
        e.line("  try")
        e.line("    Holder.Value := V;")
        e.line("    Result := Holder.Value;")
        e.line("  finally")
        e.line("    Holder.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif transfer == "cross-unit":
        e.line("function DvlCxId%s%s(X: Int64): Int64;" % (slot, tag))
        e.line("begin")
        e.line("  Result := X;")
        e.line("end;")
        e.line()
    elif transfer == "variant":
        e.line("function DvlCx%s%s(const V: %s): %s;"
               % (slot, tag, carrier, carrier))
        e.line("var")
        e.line("  Carrier: Variant;")
        e.line("begin")
        e.line("  Carrier := V;")
        e.line("  Result := Carrier;")
        e.line("end;")
        e.line()



def composite_cross(e: Emitter, transfer: str, carrier: str, tag: str,
                    slot: str, src: str, dst: str) -> None:
    if transfer == "fold":
        e.line("  { once as a constant the compiler can see, once opaque }")
        e.line("  %s := %s(OpaqueU(UInt64(%s)));" % (dst, carrier, src))
    elif transfer in ("inline", "const-param"):
        e.line("  %s := DvlCx%s%s(%s);" % (dst, slot, tag, src))
    elif transfer == "narrow-widen":
        e.line("  %s := %s(Integer(%s));" % (dst, carrier, src))
    elif transfer == "raw-move":
        e.line("  { moved as raw bytes: nothing above the byte level survives "
               "by construction, so everything above it must be rebuilt right }")
        e.line("  Move(%s, %s, SizeOf(%s));" % (src, dst, src))
    elif transfer == "tvalue":
        e.line("  %s := DvlMxTValue%s(%s);" % (dst, tag, src))
    elif transfer == "message-method":
        e.line("  DvlMxMsg%s.Payload := %s;" % (tag, src))
        e.line("  DvlMxMsg%s.Dispatch(DvlMxMsgRec%s);" % (tag, tag))
        e.line("  %s := DvlMxMsg%s.Payload;" % (dst, tag))
    elif transfer == "class-helper":
        e.line("  %s := DvlMxHelperCall%s(%s);" % (dst, tag, src))
    elif transfer == "runtime-declaration":
        e.line("  { the binding appears here, not in the header }")
        e.line("  var Fresh%s := %s;" % (slot, src))
        e.line("  %s := Fresh%s;" % (dst, slot))
    elif transfer == "unwind":
        e.line("  %s := DvlCx%s%s(%s);" % (dst, slot, tag, src))
    elif transfer == "record-copy":
        e.line("  %s := DvlCx%s%s(%s);" % (dst, slot, tag, src))
    elif transfer == "assembler-hop":
        e.line("  %s := %s(DvlCxAsm%s%s(Int64(%s)));"
               % (dst, carrier, slot, tag, src))
    elif transfer == "open-array":
        e.line("  %s := DvlCx%s%s([%s]);" % (dst, slot, tag, src))
    elif transfer in ("thread", "interface-cast", "virtual-call",
                      "specialization", "property-accessor", "variant"):
        e.line("  %s := DvlCx%s%s(%s);" % (dst, slot, tag, src))
    elif transfer == "cross-unit":
        e.line("  { out of this file and back through a function pointer }")
        e.line("  %s := %s(DvlCrossGuarded(Int64(%s), @DvlCxId%s%s));"
               % (dst, carrier, src, slot, tag))
    else:   # closure-value
        e.line("  var Step%s: TDvlCxStep%s%s;" % (slot, slot, tag))
        e.line("  Step%s :=" % slot)
        e.line("    function(const V: %s): %s" % (carrier, carrier))
        e.line("    begin")
        e.line("      Result := V;")
        e.line("    end;")
        e.line("  %s := Step%s(%s);" % (dst, slot, src))


def layer_composite(e: Emitter, rng: random.Random, count: int,
                    start: int) -> list[CaseRecord]:
    """Two boundaries in a row: the second may hide what the first lost."""
    triples = [(p, a, b)
               for p in COMPOSITE_PASSENGERS
               for a in COMPOSITE_TRANSFERS
               for b in COMPOSITE_TRANSFERS
               if a != b and (p, a) not in COMPOSITE_SKIP
               and (p, b) not in COMPOSITE_SKIP]
    rng.shuffle(triples)
    # every third case adds a third crossing: two rebuilds can hide what one
    # of them lost, and only the passport taken at the start still knows
    third = [rng.choice([t for t in COMPOSITE_TRANSFERS
                         if t not in (a, b)
                         and (p, t) not in COMPOSITE_SKIP])
             if offset % 3 == 2 else None
             for offset, (p, a, b) in enumerate(triples)]

    records: list[CaseRecord] = []
    calls: list[str] = []
    base = rng.randrange(len(triples))
    for offset in range(min(count, len(triples))):
        slot = (base + offset) % len(triples)
        passenger, first, second = triples[slot]
        index = start + offset
        name = "dvl-composite-%s-%s-%s" % (passenger, first, second)
        proc = "DvlCx%05d" % index
        tag = "%05d" % index
        carrier, setup = composite_carrier(passenger)

        extra = third[slot]
        composite_helpers(e, first, carrier, tag, "A")
        composite_helpers(e, second, carrier, tag, "B")
        if extra:
            composite_helpers(e, extra, carrier, tag, "C")

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Before, Middle, After, Final: %s;" % carrier)
        e.line("begin")
        e.line("  { %s across %s, then %s }" % (passenger, first, second))
        e.line("  Before := %s;" % setup)
        composite_passport(e, passenger, "Before")
        composite_cross(e, first, carrier, tag, "A", "Before", "Middle")
        composite_passport(e, passenger, "Middle")
        composite_cross(e, second, carrier, tag, "B", "Middle", "After")
        composite_passport(e, passenger, "After")
        if extra:
            composite_cross(e, extra, carrier, tag, "C", "After", "Final")
            composite_passport(e, passenger, "Final")
            if passenger in ("codepage", "buffer", "refcount"):
                e.line("  DevilCheckU('%s-third', "
                       "UInt64(Ord(Length(Before) = Length(Final))), 1);" % name)
            elif passenger == "lifetime":
                e.line("  DevilCheckU('%s-third', "
                       "UInt64(Ord(Assigned(Final))), 1);" % name)
            else:
                e.line("  DevilCheckU('%s-third', "
                       "UInt64(Ord(Before = Final)), 1);" % name)
        e.line("  { the passenger has to survive both crossings, and the "
               "middle passport says which one dropped it }")
        if passenger in ("codepage", "buffer", "refcount"):
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Length(Before) = Length(After))), 1);" % name)
            e.line("  DevilCheckU('%s-halfway', "
                   "UInt64(Ord(Length(Before) = Length(Middle))), 1);" % name)
        elif passenger == "lifetime":
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Assigned(After))), 1);" % name)
            e.line("  DevilCheckU('%s-halfway', "
                   "UInt64(Ord(Assigned(Middle))), 1);" % name)
        else:
            e.line("  DevilCheckU('%s-arrived', "
                   "UInt64(Ord(Before = After)), 1);" % name)
            e.line("  DevilCheckU('%s-halfway', "
                   "UInt64(Ord(Before = Middle)), 1);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="composite",
                                  detail={"passenger": passenger,
                                          "first": first, "second": second,
                                          "third": extra}))

    emit_runner(e, "Composite", calls)
    return records


# how a value can pass through a generic
GENPATH_SHAPES = ("static-method", "record-method", "class-method",
                  "constrained", "nested-specialization", "ppu-specialization",
                  "generic-array", "generic-interface")

# how it is narrowed on the way out: the step where dvl-0001 and dvl-0026 lost
# their passenger
GENPATH_NARROWINGS = ("word", "byte", "cardinal", "smallint", "integer")

GENPATH_VALUES = ("-32767", "32767", "-1", "-2147483647", "65535", "-129")


def layer_genpath(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Every generic path times every narrowing times every edge value."""
    combos = [(s, n, v) for s in GENPATH_SHAPES
              for n in GENPATH_NARROWINGS for v in GENPATH_VALUES]
    records: list[CaseRecord] = []
    calls: list[str] = []
    base = rng.randrange(len(combos))
    for offset in range(min(count, len(combos))):
        shape, narrowing, value = combos[(base + offset) % len(combos)]
        index = start + offset
        name = "dvl-genpath-%s-%s-%s" % (shape, narrowing,
                                         value.replace("-", "m"))
        proc = "DvlGp%05d" % index
        tag = "%05d" % index

        source_type = "Int64"
        narrow_type = {"word": "Word", "byte": "Byte", "cardinal": "Cardinal",
                       "smallint": "SmallInt", "integer": "Integer"}[narrowing]
        expected = {"word": int(value) & 0xFFFF,
                    "byte": int(value) & 0xFF,
                    "cardinal": int(value) & 0xFFFFFFFF,
                    "smallint": int(value) & 0xFFFF,
                    "integer": int(value) & 0xFFFFFFFF}[narrowing]

        if shape == "static-method":
            e.line("type")
            e.line("  TDvlGpOps%s = record" % tag)
            e.line("    class function Pass<T>(const V: T): T; static;")
            e.line("  end;")
            e.line()
            e.line("class function TDvlGpOps%s.Pass<T>(const V: T): T;" % tag)
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            call = "TDvlGpOps%s.Pass<%s>" % (tag, source_type)
        elif shape == "record-method":
            e.line("type")
            e.line("  TDvlGpBox%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("    function Read: T;")
            e.line("  end;")
            e.line()
            e.line("function TDvlGpBox%s<T>.Read: T;" % tag)
            e.line("begin")
            e.line("  Result := Value;")
            e.line("end;")
            e.line()
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Box: TDvlGpBox%s<%s>;" % (tag, source_type))
            e.line("begin")
            e.line("  Box.Value := V;")
            e.line("  Result := Box.Read;")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag
        elif shape == "class-method":
            e.line("type")
            e.line("  TDvlGpCls%s<T> = class" % tag)
            e.line("  public")
            e.line("    class function Pass(const V: T): T;")
            e.line("  end;")
            e.line()
            e.line("class function TDvlGpCls%s<T>.Pass(const V: T): T;" % tag)
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            call = "TDvlGpCls%s<%s>.Pass" % (tag, source_type)
        elif shape == "constrained":
            e.line("type")
            e.line("  TDvlGpCon%s<T: record> = record" % tag)
            e.line("    function Pass(const V: T): T;")
            e.line("  end;")
            e.line()
            e.line("function TDvlGpCon%s<T>.Pass(const V: T): T;" % tag)
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Holder: TDvlGpCon%s<%s>;" % (tag, source_type))
            e.line("begin")
            e.line("  Result := Holder.Pass(V);")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag
        elif shape == "nested-specialization":
            e.line("type")
            e.line("  TDvlGpInner%s<T> = record" % tag)
            e.line("    Value: T;")
            e.line("  end;")
            e.line("  TDvlGpOuter%s<T> = record" % tag)
            e.line("    Inner: TDvlGpInner%s<T>;" % tag)
            e.line("  end;")
            e.line()
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Outer: TDvlGpOuter%s<%s>;" % (tag, source_type))
            e.line("begin")
            e.line("  Outer.Inner.Value := V;")
            e.line("  Result := Outer.Inner.Value;")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag
        elif shape == "ppu-specialization":
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Carrier: TDvlCarrier<%s>;" % source_type)
            e.line("begin")
            e.line("  { the generic body lives in another unit }")
            e.line("  Carrier.Put(V);")
            e.line("  Result := Carrier.Get;")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag
        elif shape == "generic-array":
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Items: System.TArray<%s>;" % source_type)
            e.line("begin")
            e.line("  SetLength(Items, 2);")
            e.line("  Items[1] := V;")
            e.line("  Result := Items[1];")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag
        else:   # generic-interface
            e.line("type")
            e.line("  IDvlGp%s = interface" % tag)
            e.line("    ['{6D%06X-0000-0000-0000-000000000001}']"
                   % (index % 0xFFFFFF))
            e.line("    function Pass(const V: %s): %s;"
                   % (source_type, source_type))
            e.line("  end;")
            e.line()
            e.line("  TDvlGpImpl%s = class(TInterfacedObject, IDvlGp%s)"
                   % (tag, tag))
            e.line("  public")
            e.line("    function Pass(const V: %s): %s;"
                   % (source_type, source_type))
            e.line("  end;")
            e.line()
            e.line("function TDvlGpImpl%s.Pass(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Box: TDvlCarrier<%s>;" % source_type)
            e.line("begin")
            e.line("  Box.Put(V);")
            e.line("  Result := Box.Get;")
            e.line("end;")
            e.line()
            e.line("function DvlGpPass%s(const V: %s): %s;"
                   % (tag, source_type, source_type))
            e.line("var")
            e.line("  Impl: IDvlGp%s;" % tag)
            e.line("begin")
            e.line("  Impl := TDvlGpImpl%s.Create;" % tag)
            e.line("  Result := Impl.Pass(V);")
            e.line("end;")
            e.line()
            call = "DvlGpPass%s" % tag

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Value: %s;" % source_type)
        e.line("  Narrow: %s;" % narrow_type)
        e.line("begin")
        e.line("  { %s through a %s, then narrowed to %s: the step where "
               "dvl-0001 and dvl-0026 dropped the passenger }"
               % (value, shape, narrow_type))
        e.line("  Value := %s(OpaqueI(%s));" % (source_type, value))
        e.line("  Narrow := %s(%s(Value));" % (narrow_type, call))
        e.line("  DevilFeed(UInt64(Narrow));")
        e.line("  DevilCheckU('%s-narrowed', UInt64(%s), UInt64($%X));"
               % (name, "Narrow" if narrow_type in ("Word", "Byte", "Cardinal")
                  else "%s(Narrow)" % ("Word" if narrow_type == "SmallInt"
                                       else "Cardinal"), expected))
        e.line("  DevilCheckU('%s-wide', UInt64(Int64(%s(Value))), "
               "UInt64(Int64(%s)));" % (name, call, value))
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="genpath",
                                  detail={"shape": shape,
                                          "narrowing": narrowing,
                                          "value": value}))

    emit_runner(e, "Genpath", calls)
    return records


# the ways a value reaches the place where it is narrowed
NARROWPATH_SHAPES = ("direct", "field", "property", "open-array",
                     "var-param", "interface-method", "closure", "thread",
                     "record-copy", "cross-unit", "inline-call", "array-slot")

NARROWPATH_NARROWINGS = ("word", "byte", "cardinal", "smallint")

NARROWPATH_VALUES = ("-32767", "32767", "-1", "-2147483647", "65535",
                     "-129", "255", "-32768")


def layer_narrowpath(e: Emitter, rng: random.Random, count: int,
                     start: int) -> list[CaseRecord]:
    """Every route to a narrowing, times every narrowing, times every edge."""
    combos = [(s, n, v) for s in NARROWPATH_SHAPES
              for n in NARROWPATH_NARROWINGS for v in NARROWPATH_VALUES]
    records: list[CaseRecord] = []
    calls: list[str] = []
    base = rng.randrange(len(combos))
    for offset in range(min(count, len(combos))):
        shape, narrowing, value = combos[(base + offset) % len(combos)]
        index = start + offset
        name = "dvl-narrowpath-%s-%s-%s" % (shape, narrowing,
                                            value.replace("-", "m"))
        proc = "DvlNp%05d" % index
        tag = "%05d" % index
        narrow = {"word": "Word", "byte": "Byte", "cardinal": "Cardinal",
                  "smallint": "SmallInt"}[narrowing]
        mask = {"word": 0xFFFF, "byte": 0xFF, "cardinal": 0xFFFFFFFF,
                "smallint": 0xFFFF}[narrowing]
        expected = int(value) & mask
        read = ("Narrow" if narrow in ("Word", "Byte", "Cardinal")
                else "Word(Narrow)")

        if shape == "field":
            e.line("type")
            e.line("  TDvlNp%s = record" % tag)
            e.line("    Head: Byte;")
            e.line("    Slot: Int64;")
            e.line("  end;")
            e.line()
            e.line("var")
            e.line("  DvlNpRec%s: TDvlNp%s;" % (tag, tag))
            e.line()
            deliver = ["  DvlNpRec%s.Slot := Source;" % tag,
                       "  Narrow := %s(DvlNpRec%s.Slot);" % (narrow, tag)]
        elif shape == "property":
            e.line("type")
            e.line("  TDvlNpProp%s = class" % tag)
            e.line("  private")
            e.line("    FSlot: Int64;")
            e.line("  public")
            e.line("    property Slot: Int64 read FSlot write FSlot;")
            e.line("  end;")
            e.line()
            deliver = ["  var Holder := TDvlNpProp%s.Create;" % tag,
                       "  try",
                       "    Holder.Slot := Source;",
                       "    Narrow := %s(Holder.Slot);" % narrow,
                       "  finally",
                       "    Holder.Free;",
                       "  end;"]
        elif shape == "open-array":
            e.line("function DvlNpOpen%s(const Items: array of Int64): Int64;"
                   % tag)
            e.line("begin")
            e.line("  Result := Items[High(Items)];")
            e.line("end;")
            e.line()
            deliver = ["  Narrow := %s(DvlNpOpen%s([0, Source]));"
                       % (narrow, tag)]
        elif shape == "var-param":
            e.line("procedure DvlNpFill%s(var Slot: Int64; const V: Int64);"
                   % tag)
            e.line("begin")
            e.line("  Slot := V;")
            e.line("end;")
            e.line()
            deliver = ["  var Slot: Int64;",
                       "  DvlNpFill%s(Slot, Source);" % tag,
                       "  Narrow := %s(Slot);" % narrow]
        elif shape == "interface-method":
            e.line("type")
            e.line("  IDvlNp%s = interface" % tag)
            e.line("    ['{7E%06X-0000-0000-0000-000000000001}']"
                   % (index % 0xFFFFFF))
            e.line("    function Take: Int64;")
            e.line("  end;")
            e.line()
            e.line("  TDvlNpImpl%s = class(TInterfacedObject, IDvlNp%s)"
                   % (tag, tag))
            e.line("  public")
            e.line("    Slot: Int64;")
            e.line("    function Take: Int64;")
            e.line("  end;")
            e.line()
            e.line("function TDvlNpImpl%s.Take: Int64;" % tag)
            e.line("begin")
            e.line("  Result := Slot;")
            e.line("end;")
            e.line()
            deliver = ["  var Impl := TDvlNpImpl%s.Create;" % tag,
                       "  var Carry: IDvlNp%s := Impl;" % tag,
                       "  Impl.Slot := Source;",
                       "  Narrow := %s(Carry.Take);" % narrow]
        elif shape == "closure":
            e.line("type")
            e.line("  TDvlNpStep%s = reference to function: Int64;" % tag)
            e.line()
            deliver = ["  var Captured := Source;",
                       "  var Step: TDvlNpStep%s;" % tag,
                       "  Step :=",
                       "    function: Int64",
                       "    begin",
                       "      Result := Captured;",
                       "    end;",
                       "  Narrow := %s(Step());" % narrow]
        elif shape == "thread":
            e.line("type")
            e.line("  TDvlNpWorker%s = class(TThread)" % tag)
            e.line("  public")
            e.line("    Input, Output: Int64;")
            e.line("    procedure Execute; override;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlNpWorker%s.Execute;" % tag)
            e.line("begin")
            e.line("  Output := Input;")
            e.line("end;")
            e.line()
            deliver = ["  var Worker := TDvlNpWorker%s.Create(True);" % tag,
                       "  try",
                       "    Worker.FreeOnTerminate := False;",
                       "    Worker.Input := Source;",
                       "    Worker.Start;",
                       "    Worker.WaitFor;",
                       "    Narrow := %s(Worker.Output);" % narrow,
                       "  finally",
                       "    Worker.Free;",
                       "  end;"]
        elif shape == "record-copy":
            e.line("type")
            e.line("  TDvlNpCopy%s = record" % tag)
            e.line("    Text: AnsiString;")
            e.line("    Slot: Int64;")
            e.line("  end;")
            e.line()
            deliver = ["  var Held: TDvlNpCopy%s;" % tag,
                       "  var Taken: TDvlNpCopy%s;" % tag,
                       "  Held.Text := AnsiString('copy');",
                       "  Held.Slot := Source;",
                       "  Taken := Held;",
                       "  Narrow := %s(Taken.Slot);" % narrow]
        elif shape == "cross-unit":
            e.line("function DvlNpId%s(X: Int64): Int64;" % tag)
            e.line("begin")
            e.line("  Result := X;")
            e.line("end;")
            e.line()
            deliver = ["  Narrow := %s(DvlCrossGuarded(Source, @DvlNpId%s));"
                       % (narrow, tag)]
        elif shape == "inline-call":
            e.line("function DvlNpEcho%s(const V: Int64): Int64; inline;" % tag)
            e.line("begin")
            e.line("  Result := V;")
            e.line("end;")
            e.line()
            deliver = ["  Narrow := %s(DvlNpEcho%s(Source));" % (narrow, tag)]
        elif shape == "array-slot":
            deliver = ["  var Items: System.TArray<Int64>;",
                       "  SetLength(Items, 3);",
                       "  Items[2] := Source;",
                       "  Narrow := %s(Items[2]);" % narrow]
        else:   # direct
            deliver = ["  Narrow := %s(Source);" % narrow]

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Source: Int64;")
        e.line("  Narrow: %s;" % narrow)
        e.line("begin")
        e.line("  { %s reaches the narrowing to %s through a %s }"
               % (value, narrow, shape))
        e.line("  Source := OpaqueI(%s);" % value)
        for line in deliver:
            e.line(line)
        e.line("  DevilFeed(UInt64(Narrow));")
        e.line("  DevilCheckU('%s-narrowed', UInt64(%s), UInt64($%X));"
               % (name, read, expected))
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="narrowpath",
                                  detail={"shape": shape,
                                          "narrowing": narrowing,
                                          "value": value}))

    emit_runner(e, "Narrowpath", calls)
    return records


# each family is a set of candidates that differ only in the parameter type;
# the question every case asks is which of them the compiler chose
PICK_FAMILIES = {
    "int-width": ("ShortInt", "Byte", "SmallInt", "Word", "Integer",
                  "Cardinal", "Int64", "UInt64"),
    "int-narrow": ("Integer", "Int64"),
    "int-sign": ("Integer", "Cardinal"),
    "int-sign64": ("Int64", "UInt64"),
    "string-four": ("AnsiString", "UnicodeString", "WideString", "UTF8String"),
    "string-ptr": ("UnicodeString", "PChar"),
    "string-ansi": ("AnsiString", "PAnsiChar"),
    "char": ("AnsiChar", "Char", "UnicodeString"),
    "num-float": ("Integer", "Double"),
    "float-width": ("Single", "Double"),
    "money": ("Double", "Currency"),
    "variant": ("Integer", "Variant"),
    "variant-str": ("UnicodeString", "Variant"),
    # dvl-0029: the same character written two ways resolved to two different
    # candidates, so the way it is written is a dimension of its own
    "char-form": ("AnsiChar", "Char"),
    "string-form": ("AnsiString", "UnicodeString"),
}

# families whose candidates need types declared next to them
PICK_SPECIAL = ("class-depth", "class-intf", "pointer", "enum-ordinal",
                "generic-concrete", "helper-owner")

# what is handed to the call
PICK_ARGS = {
    "lit-1": ((), "1"),
    "lit-300": ((), "300"),
    "lit-neg": ((), "-1"),
    "lit-big32": ((), "3000000000"),
    "lit-big64": ((), "5000000000"),
    "lit-float": ((), "1.5"),
    "lit-str": ((), "'ab'"),
    "lit-char": ((), "'a'"),
    "var-byte": (("  var Arg: Byte := 7;",), "Arg"),
    "var-smallint": (("  var Arg: SmallInt := 7;",), "Arg"),
    "var-word": (("  var Arg: Word := 7;",), "Arg"),
    "var-integer": (("  var Arg: Integer := 7;",), "Arg"),
    "var-cardinal": (("  var Arg: Cardinal := 7;",), "Arg"),
    "var-int64": (("  var Arg: Int64 := 7;",), "Arg"),
    "var-single": (("  var Arg: Single := 1.5;",), "Arg"),
    "var-double": (("  var Arg: Double := 1.5;",), "Arg"),
    "var-currency": (("  var Arg: Currency := 1.5;",), "Arg"),
    "var-ansistring": (("  var Arg: AnsiString := AnsiString('ab');",), "Arg"),
    "var-unicodestring": (("  var Arg: UnicodeString := 'ab';",), "Arg"),
    "var-widestring": (("  var Arg: WideString := 'ab';",), "Arg"),
    "var-utf8": (("  var Arg: UTF8String := UTF8String('ab');",), "Arg"),
    "var-char": (("  var Arg: Char := 'a';",), "Arg"),
    "var-ansichar": (("  var Arg: AnsiChar := 'a';",), "Arg"),
    "var-pchar": (("  var Held: UnicodeString := 'ab';",
                   "  var Arg: PChar := PChar(Held);"), "Arg"),
    "var-pansichar": (("  var Held: AnsiString := AnsiString('ab');",
                       "  var Arg: PAnsiChar := PAnsiChar(Held);"), "Arg"),
    "var-variant": (("  var Arg: Variant := 7;",), "Arg"),
    "lit-char-escaped": ((), "#$0061"),
    "lit-char-chr": ((), "Chr(97)"),
    "lit-str-escaped": ((), "#$0061#$0062"),
    "lit-str-concat": ((), "'a' + 'b'"),
}

# which argument forms each family is asked about: the pairs where the answer
# is not obvious from the outside
PICK_PLAN = (
    ("int-width", ("lit-1", "lit-300", "lit-neg", "lit-big32", "lit-big64",
                   "var-byte", "var-smallint", "var-integer", "var-int64")),
    ("int-narrow", ("lit-1", "lit-big64", "var-byte", "var-integer",
                    "var-int64")),
    ("int-sign", ("lit-1", "lit-neg", "var-byte", "var-integer")),
    ("int-sign64", ("lit-1", "var-integer", "var-int64")),
    ("string-four", ("lit-str", "var-ansistring", "var-unicodestring",
                     "var-widestring", "var-utf8")),
    ("string-ptr", ("lit-str", "var-unicodestring", "var-pchar")),
    ("string-ansi", ("lit-str", "var-ansistring", "var-pansichar")),
    ("char", ("lit-char", "var-char", "var-ansichar")),
    ("num-float", ("lit-1", "lit-float", "var-integer", "var-double")),
    ("float-width", ("lit-float", "var-single", "var-double")),
    # a float literal against Double/Currency is dvl-0027: Delphi refuses
    # the call, so that question lives in the verdict gate, not here
    ("money", ("var-double", "var-currency")),
    ("variant", ("lit-1", "var-integer", "var-variant")),
    ("variant-str", ("lit-str", "var-unicodestring", "var-variant")),
    ("class-depth", ("derived", "base", "object")),
    ("class-intf", ("impl", "intf")),
    ("pointer", ("pointer", "pbyte", "address")),
    ("enum-ordinal", ("enum", "lit")),
    ("generic-concrete", ("integer", "int64", "string")),
    ("helper-owner", ("plain",)),
    ("char-form", ("lit-char", "lit-char-escaped", "lit-char-chr", "var-char",
                   "var-ansichar")),
    ("string-form", ("lit-str", "lit-str-escaped", "lit-str-concat",
                     "var-ansistring", "var-unicodestring")),
)


def pick_pairs() -> list[tuple[str, str]]:
    return [(family, arg) for family, args in PICK_PLAN for arg in args]


def emit_pick_special(e: Emitter, family: str, arg: str, tag: str,
                      func: str) -> tuple[list[str], str]:
    """Candidates that need their own types, plus the call to make."""
    if family == "class-depth":
        e.line("type")
        e.line("  TDvlPkBase%s = class" % tag)
        e.line("  end;")
        e.line("  TDvlPkMid%s = class(TDvlPkBase%s)" % (tag, tag))
        e.line("  end;")
        e.line("  TDvlPkLeaf%s = class(TDvlPkMid%s)" % (tag, tag))
        e.line("  end;")
        e.line()
        for index, kind in enumerate(("TObject", "TDvlPkBase%s" % tag,
                                      "TDvlPkMid%s" % tag), start=1):
            e.line("function %s(V: %s): Integer; overload;" % (func, kind))
            e.line("begin")
            e.line("  Result := %d;" % index)
            e.line("end;")
            e.line()
        made = {"derived": "TDvlPkLeaf%s" % tag,
                "base": "TDvlPkBase%s" % tag,
                "object": "TObject"}[arg]
        return ["  var Arg := %s.Create;" % made, "  try"], "Arg"
    if family == "class-intf":
        e.line("type")
        e.line("  IDvlPk%s = interface" % tag)
        e.line("    ['{4C%06X-0000-0000-0000-000000000001}']" % (int(tag) % 0xFFFFFF))
        e.line("    procedure Touch;")
        e.line("  end;")
        e.line("  TDvlPkImpl%s = class(TInterfacedObject, IDvlPk%s)" % (tag, tag))
        e.line("  public")
        e.line("    procedure Touch;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlPkImpl%s.Touch;" % tag)
        e.line("begin")
        e.line("end;")
        e.line()
        for index, kind in enumerate(("TObject", "IDvlPk%s" % tag), start=1):
            e.line("function %s(const V: %s): Integer; overload;" % (func, kind))
            e.line("begin")
            e.line("  Result := %d;" % index)
            e.line("end;")
            e.line()
        if arg == "impl":
            return ["  var Held: IDvlPk%s := TDvlPkImpl%s.Create;" % (tag, tag),
                    "  var Arg := TDvlPkImpl%s(Held);" % tag], "Arg"
        return ["  var Arg: IDvlPk%s := TDvlPkImpl%s.Create;" % (tag, tag)], "Arg"
    if family == "pointer":
        for index, kind in enumerate(("Pointer", "PByte"), start=1):
            e.line("function %s(V: %s): Integer; overload;" % (func, kind))
            e.line("begin")
            e.line("  Result := %d;" % index)
            e.line("end;")
            e.line()
        if arg == "pointer":
            return ["  var Cell: Byte := 7;",
                    "  var Arg: Pointer := @Cell;"], "Arg"
        if arg == "pbyte":
            return ["  var Cell: Byte := 7;",
                    "  var Arg: PByte := @Cell;"], "Arg"
        return ["  var Cell: Byte := 7;"], "@Cell"
    if family == "enum-ordinal":
        e.line("type")
        e.line("  TDvlPkEnum%s = (dpkA%s, dpkB%s, dpkC%s);" % (tag, tag, tag, tag))
        e.line()
        for index, kind in enumerate(("TDvlPkEnum%s" % tag, "Integer"), start=1):
            e.line("function %s(V: %s): Integer; overload;" % (func, kind))
            e.line("begin")
            e.line("  Result := %d;" % index)
            e.line("end;")
            e.line()
        if arg == "enum":
            return ["  var Arg: TDvlPkEnum%s := dpkB%s;" % (tag, tag)], "Arg"
        return [], "1"
    if family == "generic-concrete":
        e.line("type")
        e.line("  TDvlPkGen%s = record" % tag)
        e.line("    class function Pick(V: Integer): Integer; overload; static;")
        e.line("    class function Pick<T>(const V: T): Integer; "
               "overload; static;")
        e.line("  end;")
        e.line()
        e.line("class function TDvlPkGen%s.Pick(V: Integer): Integer;" % tag)
        e.line("begin")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("class function TDvlPkGen%s.Pick<T>(const V: T): Integer;" % tag)
        e.line("begin")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        setup = {"integer": "  var Arg: Integer := 7;",
                 "int64": "  var Arg: Int64 := 7;",
                 "string": "  var Arg: UnicodeString := 'ab';"}[arg]
        return [setup], "Arg"
    if family == "helper-owner":
        e.line("type")
        e.line("  TDvlPkHost%s = class" % tag)
        e.line("  public")
        e.line("    function Which: Integer;")
        e.line("  end;")
        e.line("  TDvlPkHelp%s = class helper for TDvlPkHost%s" % (tag, tag))
        e.line("  public")
        e.line("    function Which: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlPkHost%s.Which: Integer;" % tag)
        e.line("begin")
        e.line("  { the class own method }")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("function TDvlPkHelp%s.Which: Integer;" % tag)
        e.line("begin")
        e.line("  { the helper method that shadows it }")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        return ["  var Host := TDvlPkHost%s.Create;" % tag, "  try"], None
    raise AssertionError("unknown pick family: %s" % family)


def layer_pick(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Which candidate the compiler chose, recorded rather than predicted."""
    # small and hand-written: every question is asked on every run, because
    # dropping one means dropping a question nobody else asks
    pairs = pick_pairs()
    records: list[CaseRecord] = []
    calls: list[str] = []

    e.line("type")
    e.line("  TDvlPickBytePtr = ^Byte;")
    e.line("  TDvlPickIntPtr = ^Integer;")
    e.line("  TDvlPickByteSet = set of Byte;")
    e.line("  TDvlPickWordSet = set of 1..100;")
    e.line("var")
    e.line("  DvlPickVarMarker: Integer;")
    e.line("  DvlPickBytePtrSlot: TDvlPickBytePtr;")
    e.line("  DvlPickIntPtrSlot: TDvlPickIntPtr;")
    e.line("  DvlPickSetSlot: TDvlPickByteSet;")
    e.line("function DvlPickPointerResult: TDvlPickBytePtr;")
    e.line("begin Result := DvlPickBytePtrSlot; end;")
    e.line("procedure DvlPickVarFirst(var V: TDvlPickIntPtr); overload;")
    e.line("begin DvlPickVarMarker := 1; end;")
    e.line("procedure DvlPickVarFirst(V: Pointer); overload;")
    e.line("begin DvlPickVarMarker := 2; end;")
    e.line("procedure DvlPickValueFirst(V: Pointer); overload;")
    e.line("begin DvlPickVarMarker := 2; end;")
    e.line("procedure DvlPickValueFirst(var V: TDvlPickIntPtr); overload;")
    e.line("begin DvlPickVarMarker := 1; end;")
    e.line("procedure DvlPickSet(var V: TDvlPickByteSet); overload;")
    e.line("begin DvlPickVarMarker := 1; end;")
    e.line("procedure DvlPickSet(V: TDvlPickWordSet); overload;")
    e.line("begin DvlPickVarMarker := 2; end;")
    e.line("procedure DvlPickVarAddressabilityMatrix;")
    e.line("begin")
    e.line("  DevilStep('dvl-pick-var-addressability-matrix');")
    e.line("  DvlPickBytePtrSlot := nil;")
    e.line("  DvlPickIntPtrSlot := nil;")
    e.line("  DvlPickSetSlot := [];")
    e.line("  DvlPickVarFirst(DvlPickPointerResult);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-rvalue-first',")
    e.line("    UInt64(DvlPickVarMarker), 2);")
    e.line("  DvlPickValueFirst(DvlPickPointerResult);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-rvalue-second',")
    e.line("    UInt64(DvlPickVarMarker), 2);")
    e.line("  DvlPickVarFirst(nil);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-nil-first',")
    e.line("    UInt64(DvlPickVarMarker), 2);")
    e.line("  DvlPickValueFirst(nil);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-nil-second',")
    e.line("    UInt64(DvlPickVarMarker), 2);")
    e.line("  DvlPickVarFirst(DvlPickIntPtrSlot);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-storage-first',")
    e.line("    UInt64(DvlPickVarMarker), 1);")
    e.line("  DvlPickValueFirst(DvlPickIntPtrSlot);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-storage-second',")
    e.line("    UInt64(DvlPickVarMarker), 1);")
    e.line("  DvlPickSet([1, 2]);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-set-rvalue',")
    e.line("    UInt64(DvlPickVarMarker), 2);")
    e.line("  DvlPickSet(DvlPickSetSlot);")
    e.line("  DevilCheckU('dvl-pick-var-addressability-matrix-set-storage',")
    e.line("    UInt64(DvlPickVarMarker), 1);")
    e.line("end;")
    e.line()
    calls.append("DvlPickVarAddressabilityMatrix")
    records.append(CaseRecord("dvl-pick-var-addressability-matrix", "pick", {
        "family": "var-out-addressability",
        "arguments": ["function-result", "nil", "variable", "set-literal"],
        "declaration_orders": ["var-first", "value-first"],
    }))

    # Mixed UInt64 arithmetic has two observable contracts at once: the
    # mathematical operation and the expression type subsequently seen by
    # overload resolution.  Keep typed variables/constants apart from untyped
    # literals and pin the 32/64-bit literal boundary.
    e.line("function DvlPkUInt64Kind(V: Integer): Integer; overload;")
    e.line("begin Result := 3; end;")
    e.line("function DvlPkUInt64Kind(V: Cardinal): Integer; overload;")
    e.line("begin Result := 4; end;")
    e.line("function DvlPkUInt64Kind(V: Int64): Integer; overload;")
    e.line("begin Result := 1; end;")
    e.line("function DvlPkUInt64Kind(V: UInt64): Integer; overload;")
    e.line("begin Result := 2; end;")
    e.line()
    e.line("procedure DvlPkMixedUInt64Matrix;")
    e.line("const")
    e.line("  TypedIntegerOne: Integer = 1;")
    e.line("  TypedInt64One: Int64 = 1;")
    e.line("var")
    e.line("  I: Integer;")
    e.line("  S: Int64;")
    e.line("  U: UInt64;")
    e.line("begin")
    e.line("  DevilStep('dvl-pick-mixed-uint64');")
    e.line("  I := Integer(OpaqueI(1));")
    e.line("  S := Int64(OpaqueI(-1));")
    e.line("  U := OpaqueU(41);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-u-plus-literal',")
    e.line("    UInt64(DvlPkUInt64Kind(U + 1)), 2);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-literal-plus-u',")
    e.line("    UInt64(DvlPkUInt64Kind(1 + U)), 2);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-typed-integer',")
    e.line("    UInt64(DvlPkUInt64Kind(U + TypedIntegerOne)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-typed-int64',")
    e.line("    UInt64(DvlPkUInt64Kind(U + TypedInt64One)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-variable',")
    e.line("    UInt64(DvlPkUInt64Kind(U + I)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-signed-variable',")
    e.line("    UInt64(DvlPkUInt64Kind(S + U)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-div-literal',")
    e.line("    UInt64(DvlPkUInt64Kind(U div 2)), 2);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-div-signed',")
    e.line("    UInt64(DvlPkUInt64Kind(S div U)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-literal-u32-high',")
    e.line("    UInt64(DvlPkUInt64Kind(U + 4294967295)), 2);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-literal-i64-low',")
    e.line("    UInt64(DvlPkUInt64Kind(U + 4294967296)), 1);")
    e.line("  DevilCheckU('dvl-pick-mixed-uint64-max-form',")
    e.line("    UInt64(Max(U, U + 1)), 42);")
    e.line("end;")
    e.line()
    calls.append("DvlPkMixedUInt64Matrix")
    records.append(CaseRecord("dvl-pick-mixed-uint64", "pick", {
        "family": "mixed-uint64",
        "axes": ["typedness", "literal-width", "operand-order",
                 "operator", "overload-consumer"],
    }))
    for offset in range(len(pairs)):
        family, arg = pairs[offset]
        index = start + offset
        # the question is the name: a number would move when the table grows
        name = "dvl-pick-%s-%s" % (family, arg)
        proc = "DvlPk%05d" % index
        tag = "%05d" % index
        func = "DvlPkPick%s" % tag

        if family in PICK_SPECIAL:
            setup, expr = emit_pick_special(e, family, arg, tag, func)
        else:
            for candidate, kind in enumerate(PICK_FAMILIES[family], start=1):
                e.line("function %s(const V: %s): Integer; overload;"
                       % (func, kind))
                e.line("begin")
                e.line("  Result := %d;" % candidate)
                e.line("end;")
                e.line()
            setup, expr = PICK_ARGS[arg]
            setup = list(setup)

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Picked: Integer;")
        e.line("begin")
        e.line("  { family %s asked with %s }" % (family, arg))
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        # the generic family is reached through its record, not by plain name
        callee = ("TDvlPkGen%s.Pick" % tag
                  if family == "generic-concrete" else func)
        for line in setup:
            e.line(line)
        if family == "helper-owner":
            e.line("    Picked := Host.Which;")
            e.line("  finally")
            e.line("    Host.Free;")
            e.line("  end;")
        elif family == "class-depth":
            e.line("    Picked := %s(%s);" % (callee, expr))
            e.line("  finally")
            e.line("    Arg.Free;")
            e.line("  end;")
        else:
            e.line("  Picked := %s(%s);" % (callee, expr))
        e.line("  { no model: the contract is that every compiler picks the "
               "same candidate }")
        e.line("  DevilNote('%s-picked', UInt64(Picked));" % name)
        e.line("  DevilCheckBool('%s-called', Picked > 0);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="pick",
                                  detail={"family": family, "arg": arg}))

    emit_runner(e, "Pick", calls)
    return records


# each shape declares the same name twice and asks which one an identifier
# means; the winner reports 1 for the first declaration, 2 for the second
SCOPE_SHAPES = ("with-vs-local", "with-two-records", "with-vs-param",
                "field-vs-local", "field-vs-global", "derived-shadows-base",
                "param-vs-field", "nested-vs-outer", "loopvar-vs-outer",
                "enum-member-vs-local", "uses-order", "qualified-vs-plain",
                "helper-vs-record-method", "later-helper-wins",
                "nested-type-vs-outer-type",
                "with-vs-unit-function", "inherited-overload",
                "for-in-var-vs-outer", "with-vs-field")


def emit_scope_case(e: Emitter, shape: str, tag: str) -> list[str]:
    """Declarations and body for one shape; returns the body lines."""
    if shape == "with-vs-local":
        e.line("type")
        e.line("  TDvlSc%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line()
        return ["  var Held: TDvlSc%s;" % tag,
                "  var Slot: Integer;",
                "  Held.Slot := 1;",
                "  Slot := 2;",
                "  with Held do",
                "    Which := Slot;"]
    if shape == "with-two-records":
        e.line("type")
        e.line("  TDvlScA%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line("  TDvlScB%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line()
        return ["  var First: TDvlScA%s;" % tag,
                "  var Second: TDvlScB%s;" % tag,
                "  First.Slot := 1;",
                "  Second.Slot := 2;",
                "  with First, Second do",
                "    Which := Slot;"]
    if shape == "with-vs-param":
        e.line("type")
        e.line("  TDvlSc%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line()
        e.line("function DvlScAsk%s(Slot: Integer): Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlSc%s;" % tag)
        e.line("begin")
        e.line("  Held.Slot := 1;")
        e.line("  with Held do")
        e.line("    Result := Slot;")
        e.line("end;")
        e.line()
        return ["  Which := DvlScAsk%s(2);" % tag]
    if shape == "field-vs-local":
        e.line("type")
        e.line("  TDvlSc%s = class" % tag)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlSc%s.Ask: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line("begin")
        e.line("  Slot := 2;")
        e.line("  Result := Slot;")
        e.line("end;")
        e.line()
        return ["  var Held := TDvlSc%s.Create;" % tag,
                "  try",
                "    Held.Slot := 1;",
                "    Which := Held.Ask;",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "field-vs-global":
        e.line("var")
        e.line("  DvlScSlot%s: Integer;" % tag)
        e.line()
        e.line("type")
        e.line("  TDvlSc%s = class" % tag)
        e.line("  public")
        e.line("    DvlScSlot%s: Integer;" % tag)
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlSc%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  Result := DvlScSlot%s;" % tag)
        e.line("end;")
        e.line()
        return ["  var Held := TDvlSc%s.Create;" % tag,
                "  try",
                "    Held.DvlScSlot%s := 1;" % tag,
                "    DvlScSlot%s := 2;" % tag,
                "    Which := Held.Ask;",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "derived-shadows-base":
        e.line("type")
        e.line("  TDvlScBase%s = class" % tag)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line("  TDvlScLeaf%s = class(TDvlScBase%s)" % (tag, tag))
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlScLeaf%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  { two fields of one name: the base one and the shadowing one }")
        e.line("  Result := Slot;")
        e.line("end;")
        e.line()
        return ["  var Held := TDvlScLeaf%s.Create;" % tag,
                "  try",
                "    TDvlScBase%s(Held).Slot := 1;" % tag,
                "    Held.Slot := 2;",
                "    Which := Held.Ask;",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "param-vs-field":
        e.line("type")
        e.line("  TDvlSc%s = class" % tag)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    function Ask(Slot: Integer): Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlSc%s.Ask(Slot: Integer): Integer;" % tag)
        e.line("begin")
        e.line("  Result := Slot;")
        e.line("end;")
        e.line()
        return ["  var Held := TDvlSc%s.Create;" % tag,
                "  try",
                "    Held.Slot := 1;",
                "    Which := Held.Ask(2);",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "nested-vs-outer":
        e.line("function DvlScAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line()
        e.line("  function Inner: Integer;")
        e.line("  var")
        e.line("    Slot: Integer;")
        e.line("  begin")
        e.line("    Slot := 2;")
        e.line("    Result := Slot;")
        e.line("  end;")
        e.line()
        e.line("begin")
        e.line("  Slot := 1;")
        e.line("  Result := Inner;")
        e.line("end;")
        e.line()
        return ["  Which := DvlScAsk%s;" % tag]
    if shape == "loopvar-vs-outer":
        e.line("var")
        e.line("  DvlScStep%s: Integer;" % tag)
        e.line()
        e.line("function DvlScAsk%s: Integer;" % tag)
        e.line("begin")
        e.line("  DvlScStep%s := 1;" % tag)
        e.line("  Result := 0;")
        e.line("  { the loop variable stands in front of the global }")
        e.line("  for var DvlScStep%s := 2 to 2 do" % tag)
        e.line("    Result := DvlScStep%s;" % tag)
        e.line("end;")
        e.line()
        return ["  Which := DvlScAsk%s;" % tag]
    if shape == "enum-member-vs-local":
        e.line("type")
        e.line("  TDvlScEnum%s = (dvlScZero%s, dvlScSlot%s);" % (tag, tag, tag))
        e.line()
        return ["  { the member is worth 1, the local that hides it is worth 2 }",
                "  var dvlScSlot%s: Integer;" % tag,
                "  dvlScSlot%s := 2;" % tag,
                "  Which := Ord(dvlScSlot%s);" % tag]
    if shape == "uses-order":
        return ["  { both units export this name; the uses clause decides }",
                "  Which := DvlScopePick;"]
    if shape == "qualified-vs-plain":
        return ["  Which := devil_scope_a.DvlScopePick;"]
    if shape == "helper-vs-record-method":
        e.line("type")
        e.line("  TDvlSc%s = record" % tag)
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line("  TDvlScHelp%s = record helper for TDvlSc%s" % (tag, tag))
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlSc%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("function TDvlScHelp%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        return ["  var Held: TDvlSc%s;" % tag,
                "  Which := Held.Ask;"]
    if shape == "later-helper-wins":
        e.line("type")
        e.line("  TDvlSc%s = record" % tag)
        e.line("    Payload: Integer;")
        e.line("  end;")
        e.line("  TDvlScFirst%s = record helper for TDvlSc%s" % (tag, tag))
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line("  TDvlScSecond%s = record helper for TDvlSc%s" % (tag, tag))
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlScFirst%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("function TDvlScSecond%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  { two helpers for one type: only the last one declared is "
               "reachable }")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        return ["  var Held: TDvlSc%s;" % tag,
                "  Which := Held.Ask;"]
    if shape == "nested-type-vs-outer-type":
        e.line("type")
        e.line("  TDvlScInner%s = record" % tag)
        e.line("    Wide: Int64;")
        e.line("  end;")
        e.line()
        e.line("  TDvlScHost%s = class" % tag)
        e.line("  public type")
        e.line("    TDvlScInner%s = record" % tag)
        e.line("      Narrow: Byte;")
        e.line("    end;")
        e.line("  public")
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlScHost%s.Ask: Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlScInner%s;" % tag)
        e.line("begin")
        e.line("  { 2 if the nested declaration wins, 1 if the outer one does }")
        e.line("  If SizeOf(Held) = 1 then")
        e.line("    Result := 2")
        e.line("  else")
        e.line("    Result := 1;")
        e.line("end;")
        e.line()
        return ["  var Host := TDvlScHost%s.Create;" % tag,
                "  try",
                "    Which := Host.Ask;",
                "  finally",
                "    Host.Free;",
                "  end;"]
    if shape == "with-vs-unit-function":
        e.line("function DvlScAsk%s: Integer;" % tag)
        e.line("begin")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("type")
        e.line("  TDvlSc%s = class" % tag)
        e.line("  public")
        e.line("    function DvlScAsk%s: Integer;" % tag)
        e.line("  end;")
        e.line()
        e.line("function TDvlSc%s.DvlScAsk%s: Integer;" % (tag, tag))
        e.line("begin")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        return ["  var Held := TDvlSc%s.Create;" % tag,
                "  try",
                "    with Held do",
                "      Which := DvlScAsk%s;" % tag,
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "inherited-overload":
        e.line("type")
        e.line("  TDvlScBase%s = class" % tag)
        e.line("  public")
        e.line("    function Ask(V: Integer): Integer; overload; virtual;")
        e.line("    function Ask(V: Int64): Integer; overload; virtual;")
        e.line("  end;")
        e.line("  TDvlScLeaf%s = class(TDvlScBase%s)" % (tag, tag))
        e.line("  public")
        e.line("    function Ask(V: Integer): Integer; overload; override;")
        e.line("  end;")
        e.line()
        e.line("function TDvlScBase%s.Ask(V: Integer): Integer;" % tag)
        e.line("begin")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("function TDvlScBase%s.Ask(V: Int64): Integer;" % tag)
        e.line("begin")
        e.line("  Result := 2;")
        e.line("end;")
        e.line()
        e.line("function TDvlScLeaf%s.Ask(V: Integer): Integer;" % tag)
        e.line("begin")
        e.line("  { which candidate does the bare inherited name reach }")
        e.line("  Result := inherited Ask(V);")
        e.line("end;")
        e.line()
        return ["  var Held := TDvlScLeaf%s.Create;" % tag,
                "  try",
                "    Which := Held.Ask(Integer(7));",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "for-in-var-vs-outer":
        e.line("var")
        e.line("  DvlScItem%s: Integer;" % tag)
        e.line()
        e.line("function DvlScAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Items: System.TArray<Integer>;")
        e.line("begin")
        e.line("  DvlScItem%s := 1;" % tag)
        e.line("  SetLength(Items, 1);")
        e.line("  Items[0] := 2;")
        e.line("  Result := 0;")
        e.line("  for var DvlScItem%s in Items do" % tag)
        e.line("    Result := DvlScItem%s;" % tag)
        e.line("end;")
        e.line()
        return ["  Which := DvlScAsk%s;" % tag]
    # with-vs-field: a method whose class has a field, standing inside a with
    e.line("type")
    e.line("  TDvlScCarrier%s = record" % tag)
    e.line("    Slot: Integer;")
    e.line("  end;")
    e.line()
    e.line("  TDvlSc%s = class" % tag)
    e.line("  public")
    e.line("    Slot: Integer;")
    e.line("    Carrier: TDvlScCarrier%s;" % tag)
    e.line("    function Ask: Integer;")
    e.line("  end;")
    e.line()
    e.line("function TDvlSc%s.Ask: Integer;" % tag)
    e.line("begin")
    e.line("  { the with scope stands between the method and its own field }")
    e.line("  with Carrier do")
    e.line("    Result := Slot;")
    e.line("end;")
    e.line()
    return ["  var Held := TDvlSc%s.Create;" % tag,
            "  try",
            "    Held.Slot := 1;",
            "    Held.Carrier.Slot := 2;",
            "    Which := Held.Ask;",
            "  finally",
            "    Held.Free;",
            "  end;"]


def layer_scope(e: Emitter, rng: random.Random, count: int,
                start: int) -> list[CaseRecord]:
    """Which declaration an identifier means when two carry the same name."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, shape in enumerate(SCOPE_SHAPES):
        index = start + offset
        name = "dvl-scope-%s" % shape
        proc = "DvlSc%05d" % index
        tag = "%05d" % index

        body = emit_scope_case(e, shape, tag)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Which: Integer;")
        e.line("begin")
        e.line("  { %s }" % shape)
        e.line("  Which := 0;")
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        for line in body:
            e.line(line)
        e.line("  { no model: the contract is that every compiler binds the "
               "same declaration }")
        e.line("  DevilNote('%s-bound', UInt64(Which));" % name)
        e.line("  DevilCheckBool('%s-resolved', Which > 0);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="scope",
                                  detail={"shape": shape}))

    emit_runner(e, "Scope", calls)
    return records


def write_scope_units(out: Path) -> None:
    """Two units exporting one name, so the uses clause has something to decide."""
    for letter, value in (("a", 1), ("b", 2)):
        lines = ["unit devil_scope_%s;" % letter, "",
                 "{$ifdef FPC}",
                 "  {$mode delphiunicode}{$H+}",
                 "  {$modeswitch advancedrecords}",
                 "{$endif}", "",
                 "interface", "",
                 "function DvlScopePick: Integer;", "",
                 "implementation", "",
                 "function DvlScopePick: Integer;",
                 "begin",
                 "  Result := %d;" % value,
                 "end;", "",
                 "end."]
        (out / ("devil_scope_%s.pas" % letter)).write_text(
            "\n".join(lines) + "\n", encoding="utf-8")


# where the literal ends up: the axis, because Delphi materialises for some
# destinations and not for others
LIT_DESTINATIONS = ("local", "global", "object-field", "global-record-field",
                    "array-element", "nested-array", "out-param", "result",
                    "captured", "threadvar", "static-array", "interface-field")

# what is asked of each destination
LIT_OBSERVATIONS = ("refcount", "writable", "identity")

# and the forms a literal can take on the way there, asked on one destination
LIT_FORMS = ("ansi-cast", "rawbyte-cast", "utf8-cast", "unicode-plain",
             "implicit", "typed-const", "concat", "copy-built")


def emit_lit_destination(e: Emitter, dest: str, tag: str) -> tuple[list[str], str]:
    """Declarations and setup that put a literal into `dest`; returns its name."""
    lit = "AnsiString('poke-me')"
    if dest == "local":
        return ["  var Held: AnsiString;", "  Held := %s;" % lit], "Held"
    if dest == "global":
        e.line("var")
        e.line("  DvlLitGlobal%s: AnsiString;" % tag)
        e.line()
        return ["  DvlLitGlobal%s := %s;" % (tag, lit)], "DvlLitGlobal%s" % tag
    if dest == "object-field":
        e.line("type")
        e.line("  TDvlLit%s = class" % tag)
        e.line("  public")
        e.line("    Text: AnsiString;")
        e.line("  end;")
        e.line()
        e.line("var")
        e.line("  DvlLitBox%s: TDvlLit%s;" % (tag, tag))
        e.line()
        return ["  DvlLitBox%s := TDvlLit%s.Create;" % (tag, tag),
                "  DvlLitBox%s.Text := %s;" % (tag, lit)], \
               "DvlLitBox%s.Text" % tag
    if dest == "global-record-field":
        e.line("type")
        e.line("  TDvlLitRec%s = record" % tag)
        e.line("    Head: Byte;")
        e.line("    Text: AnsiString;")
        e.line("  end;")
        e.line()
        e.line("var")
        e.line("  DvlLitRec%s: TDvlLitRec%s;" % (tag, tag))
        e.line()
        return ["  DvlLitRec%s.Text := %s;" % (tag, lit)], \
               "DvlLitRec%s.Text" % tag
    if dest == "array-element":
        return ["  var Items: System.TArray<AnsiString>;",
                "  SetLength(Items, 2);",
                "  Items[1] := %s;" % lit], "Items[1]"
    if dest == "nested-array":
        return ["  var Rows: System.TArray<System.TArray<AnsiString>>;",
                "  SetLength(Rows, 2);",
                "  SetLength(Rows[1], 2);",
                "  Rows[1][1] := %s;" % lit], "Rows[1][1]"
    if dest == "out-param":
        e.line("procedure DvlLitFill%s(out V: AnsiString);" % tag)
        e.line("begin")
        e.line("  V := %s;" % lit)
        e.line("end;")
        e.line()
        return ["  var Held: AnsiString;",
                "  DvlLitFill%s(Held);" % tag], "Held"
    if dest == "result":
        e.line("function DvlLitMake%s: AnsiString;" % tag)
        e.line("begin")
        e.line("  Result := %s;" % lit)
        e.line("end;")
        e.line()
        return ["  var Held: AnsiString;",
                "  Held := DvlLitMake%s;" % tag], "Held"
    if dest == "captured":
        e.line("type")
        e.line("  TDvlLitStep%s = reference to procedure;" % tag)
        e.line()
        return ["  var Held: AnsiString;",
                "  var Step: TDvlLitStep%s;" % tag,
                "  Step :=",
                "    procedure",
                "    begin",
                "      { the variable lives in the closure frame, not on the "
                "stack }",
                "      Held := %s;" % lit,
                "    end;",
                "  Step();"], "Held"
    if dest == "threadvar":
        e.line("threadvar")
        e.line("  DvlLitThread%s: AnsiString;" % tag)
        e.line()
        return ["  DvlLitThread%s := %s;" % (tag, lit)], \
               "DvlLitThread%s" % tag
    if dest == "static-array":
        e.line("var")
        e.line("  DvlLitStatic%s: array[0..1] of AnsiString;" % tag)
        e.line()
        return ["  DvlLitStatic%s[1] := %s;" % (tag, lit)], \
               "DvlLitStatic%s[1]" % tag
    # interface-field: storage owned by a reference-counted object
    e.line("type")
    e.line("  IDvlLit%s = interface" % tag)
    e.line("    ['{5A%06X-0000-0000-0000-000000000001}']" % (int(tag) % 0xFFFFFF))
    e.line("    function Text: AnsiString;")
    e.line("    procedure Put(const V: AnsiString);")
    e.line("  end;")
    e.line("  TDvlLitImpl%s = class(TInterfacedObject, IDvlLit%s)" % (tag, tag))
    e.line("  public")
    e.line("    Stored: AnsiString;")
    e.line("    function Text: AnsiString;")
    e.line("    procedure Put(const V: AnsiString);")
    e.line("  end;")
    e.line()
    e.line("function TDvlLitImpl%s.Text: AnsiString;" % tag)
    e.line("begin")
    e.line("  Result := Stored;")
    e.line("end;")
    e.line()
    e.line("procedure TDvlLitImpl%s.Put(const V: AnsiString);" % tag)
    e.line("begin")
    e.line("  Stored := V;")
    e.line("end;")
    e.line()
    e.line("var")
    e.line("  DvlLitImpl%s: TDvlLitImpl%s;" % (tag, tag))
    e.line()
    return ["  DvlLitImpl%s := TDvlLitImpl%s.Create;" % (tag, tag),
            "  var Carry: IDvlLit%s := DvlLitImpl%s;" % (tag, tag),
            "  Carry.Put(%s);" % lit], "DvlLitImpl%s.Stored" % tag


def emit_lit_form(e: Emitter, form: str, tag: str) -> tuple[list[str], str]:
    """A literal reaching one global by different spellings."""
    e.line("var")
    e.line("  DvlLitForm%s: AnsiString;" % tag)
    e.line()
    value = {
        "ansi-cast": "AnsiString('poke-me')",
        "rawbyte-cast": "AnsiString(RawByteString('poke-me'))",
        "utf8-cast": "AnsiString(UTF8String('poke-me'))",
        "unicode-plain": "AnsiString(UnicodeString('poke-me'))",
        "implicit": "'poke-me'",
        "concat": "AnsiString('poke-') + AnsiString('me')",
        "copy-built": "Copy(AnsiString('poke-me!'), 1, 7)",
    }.get(form)
    if form == "typed-const":
        e.line("const")
        e.line("  DvlLitConst%s: AnsiString = 'poke-me';" % tag)
        e.line()
        value = "DvlLitConst%s" % tag
    return ["  DvlLitForm%s := %s;" % (tag, value)], "DvlLitForm%s" % tag


def emit_lit_observation(e: Emitter, observation: str, held: str,
                         name: str, tag: str) -> None:
    if observation == "refcount":
        e.line("  Answer := UInt64(Cardinal(StringRefCount(%s)));" % held)
    elif observation == "writable":
        e.line("  { 1 if the buffer belongs to us, 2 if it is the image }")
        e.line("  Answer := UInt64(DvlLitPoke(%s));" % held)
    else:
        e.line("  { does it share storage with another occurrence of the same "
               "literal }")
        e.line("  Answer := UInt64(Ord(Pointer(%s) = "
               "Pointer(DvlLitTwin)));" % held)


def layer_lit(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """What a value carries when it came from a literal, by where it is kept."""
    e.line("type")
    e.line("  TDvlResourceState = (dvlStateFirst, dvlStateSecond);")
    e.line("resourcestring")
    e.line("  DvlResourceTextFirst = 'first %s';")
    e.line("  DvlResourceTextSecond = 'second';")
    e.line("const")
    e.line("  DvlResourceStates: array[TDvlResourceState] of string = (")
    e.line("    DvlResourceTextFirst, DvlResourceTextSecond);")
    e.line("  DvlResourceUnicode: UnicodeString = DvlResourceTextFirst;")
    e.line("  DvlResourceAnsi: AnsiString = DvlResourceTextSecond;")
    e.line("  DvlResourceWide: WideString = DvlResourceTextSecond;")
    e.line()
    e.line("var")
    e.line("  DvlLitTwin: AnsiString;")
    e.line()
    e.line("function DvlLitPoke(const S: AnsiString): Integer;")
    e.line("var")
    e.line("  Cursor: PAnsiChar;")
    e.line("begin")
    e.line("  Cursor := PAnsiChar(S);")
    e.line("  try")
    e.line("    Cursor[0] := 'X';")
    e.line("    Result := 1;")
    e.line("  except")
    e.line("    on E: Exception do")
    e.line("      Result := 2;")
    e.line("  end;")
    e.line("end;")
    e.line()

    e.line("procedure DvlLitResourceTypedConstants;")
    e.line("begin")
    e.line("  DevilStep('dvl-lit-resourcestring-typed-constants');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-array-first',")
    e.line("    DvlResourceStates[dvlStateFirst] = 'first %s');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-array-second',")
    e.line("    DvlResourceStates[dvlStateSecond] = 'second');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-unicode',")
    e.line("    DvlResourceUnicode = 'first %s');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-ansi',")
    e.line("    string(DvlResourceAnsi) = 'second');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-wide',")
    e.line("    string(DvlResourceWide) = 'second');")
    e.line("  DevilCheckBool('dvl-lit-resourcestring-format',")
    e.line("    Format(DvlResourceStates[dvlStateFirst], ['X']) = 'first X');")
    e.line("end;")
    e.line()

    records: list[CaseRecord] = [CaseRecord(
        "dvl-lit-resourcestring-typed-constants", "lit", {
            "shape": "resourcestring-to-typed-constant",
            "destinations": ["array-string", "unicode", "ansi", "wide"],
        })]
    calls: list[str] = ["DvlLitResourceTypedConstants"]
    plan = [(d, o) for d in LIT_DESTINATIONS for o in LIT_OBSERVATIONS]
    plan += [("form-%s" % f, "refcount") for f in LIT_FORMS]
    plan += [("form-%s" % f, "writable") for f in LIT_FORMS]
    for offset, (dest, observation) in enumerate(plan):
        index = start + offset
        name = "dvl-lit-%s-%s" % (dest, observation)
        proc = "DvlLit%05d" % index
        tag = "%05d" % index

        if dest.startswith("form-"):
            setup, held = emit_lit_form(e, dest[5:], tag)
        else:
            setup, held = emit_lit_destination(e, dest, tag)

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Answer: UInt64;")
        e.line("begin")
        e.line("  { %s asked about its %s }" % (dest, observation))
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        e.line("  DvlLitTwin := AnsiString('poke-me');")
        for line in setup:
            e.line(line)
        emit_lit_observation(e, observation, held, name, tag)
        e.line("  DevilNote('%s', Answer);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="lit",
                                  detail={"destination": dest,
                                          "observation": observation}))

    emit_runner(e, "Lit", calls)
    return records


# each shape builds closures now and calls them later; the answer is what they
# saw by then
CAPTURE_SHAPES = ("classic-loop-var", "inline-loop-var", "for-in-var",
                  "local-changed-after", "local-per-iteration",
                  "nested-closure", "closure-in-closure", "field-of-object",
                  "with-scoped", "with-composite-lvalue",
                  "nested-expression-new",
                  "captured-managed", "captured-record",
                  "captured-array-slot", "self-in-method", "const-param",
                  "captured-in-thread", "exception-var", "try-finally-var",
                  "recursive-capture")


def emit_capture_case(e: Emitter, shape: str, tag: str) -> list[str]:
    """Declarations for the shape; returns the body that sets Answer."""
    e.line("type")
    e.line("  TDvlCapStep%s = reference to function: Integer;" % tag)
    e.line()
    if shape == "classic-loop-var":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Steps: array[1..3] of TDvlCapStep%s;" % tag)
        e.line("  Index: Integer;")
        e.line("begin")
        e.line("  for Index := 1 to 3 do")
        e.line("    Steps[Index] :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Index;")
        e.line("      end;")
        e.line("  { one variable for the whole loop, or one per iteration }")
        e.line("  Result := Steps[1]() * 100 + Steps[3]();")
        e.line("end;")
        e.line()
    elif shape == "inline-loop-var":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Steps: array[1..3] of TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  for var Index := 1 to 3 do")
        e.line("    Steps[Index] :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Index;")
        e.line("      end;")
        e.line("  Result := Steps[1]() * 100 + Steps[3]();")
        e.line("end;")
        e.line()
    elif shape == "for-in-var":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Steps: array[1..3] of TDvlCapStep%s;" % tag)
        e.line("  Items: System.TArray<Integer>;")
        e.line("  Slot: Integer;")
        e.line("begin")
        e.line("  Items := [1, 2, 3];")
        e.line("  Slot := 0;")
        e.line("  for var Item in Items do")
        e.line("  begin")
        e.line("    Inc(Slot);")
        e.line("    Steps[Slot] :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Item;")
        e.line("      end;")
        e.line("  end;")
        e.line("  Result := Steps[1]() * 100 + Steps[3]();")
        e.line("end;")
        e.line()
    elif shape == "local-changed-after":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Slot := 1;")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      Result := Slot;")
        e.line("    end;")
        e.line("  { the variable is captured, not its value at capture time }")
        e.line("  Slot := 2;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "local-per-iteration":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Steps: array[1..3] of TDvlCapStep%s;" % tag)
        e.line("  Index: Integer;")
        e.line("begin")
        e.line("  for Index := 1 to 3 do")
        e.line("  begin")
        e.line("    var Local := Index;")
        e.line("    Steps[Index] :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Local;")
        e.line("      end;")
        e.line("  end;")
        e.line("  Result := Steps[1]() * 100 + Steps[3]();")
        e.line("end;")
        e.line()
    elif shape == "nested-closure":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Slot := 1;")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    var")
        e.line("      Inner: TDvlCapStep%s;" % tag)
        e.line("    begin")
        e.line("      Inner :=")
        e.line("        function: Integer")
        e.line("        begin")
        e.line("          Result := Slot;")
        e.line("        end;")
        e.line("      Slot := 2;")
        e.line("      Result := Inner();")
        e.line("    end;")
        e.line("  Result := Step() * 100 + Slot;")
        e.line("end;")
        e.line()
    elif shape == "closure-in-closure":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Outer: TDvlCapStep%s;" % tag)
        e.line("  Kept: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Outer :=")
        e.line("    function: Integer")
        e.line("    var")
        e.line("      Own: Integer;")
        e.line("    begin")
        e.line("      Own := 7;")
        e.line("      Kept :=")
        e.line("        function: Integer")
        e.line("        begin")
        e.line("          { the frame of a call that has already returned }")
        e.line("          Result := Own;")
        e.line("        end;")
        e.line("      Result := Own;")
        e.line("    end;")
        e.line("  Outer();")
        e.line("  Result := Kept();")
        e.line("end;")
        e.line()
    elif shape == "field-of-object":
        e.line("type")
        e.line("  TDvlCap%s = class" % tag)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    function Make: TDvlCapStep%s;" % tag)
        e.line("  end;")
        e.line()
        e.line("function TDvlCap%s.Make: TDvlCapStep%s;" % (tag, tag))
        e.line("begin")
        e.line("  Result :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      { the field is reached through a captured Self }")
        e.line("      Result := Slot;")
        e.line("    end;")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlCap%s;" % tag)
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Held := TDvlCap%s.Create;" % tag)
        e.line("  try")
        e.line("    Held.Slot := 1;")
        e.line("    Step := Held.Make();")
        e.line("    Held.Slot := 2;")
        e.line("    Result := Step();")
        e.line("  finally")
        e.line("    Held.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif shape == "with-scoped":
        e.line("type")
        e.line("  TDvlCapRec%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlCapRec%s;" % tag)
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Held.Slot := 1;")
        e.line("  with Held do")
        e.line("    Step :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Slot;")
        e.line("      end;")
        e.line("  Held.Slot := 2;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "with-composite-lvalue":
        e.line("type")
        e.line("  TDvlCapRec%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line("  TDvlCapRecs%s = array of TDvlCapRec%s;" % (tag, tag))
        e.line()
        e.line("function DvlCapIndex%s(var Counter: Integer): Integer;" % tag)
        e.line("begin")
        e.line("  Inc(Counter);")
        e.line("  Result := 1;")
        e.line("end;")
        e.line()
        e.line("procedure DvlCapMake%s(var Step: TDvlCapStep%s; "
               "var Counter: Integer);" % (tag, tag))
        e.line("var")
        e.line("  Items: TDvlCapRecs%s;" % tag)
        e.line("begin")
        e.line("  SetLength(Items, 2);")
        e.line("  Items[0].Slot := 11;")
        e.line("  Items[1].Slot := 22;")
        e.line("  with Items[DvlCapIndex%s(Counter)] do" % tag)
        e.line("    Step :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Slot;")
        e.line("      end;")
        e.line("  { the selected address is stable, while the storage remains aliased } ")
        e.line("  Items[1].Slot := 73;")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Counter: Integer;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Counter := 0;")
        e.line("  DvlCapMake%s(Step, Counter);" % tag)
        e.line("  { Step executes after the frame and its dynamic-array local are gone. } ")
        e.line("  Result := Step() * 10 + Counter;")
        e.line("end;")
        e.line()
    elif shape == "nested-expression-new":
        e.line("type")
        e.line("  TDvlCapManaged%s = record" % tag)
        e.line("    Text: UnicodeString;")
        e.line("    Value: Integer;")
        e.line("  end;")
        e.line("  PDvlCapManaged%s = ^TDvlCapManaged%s;" % (tag, tag))
        e.line()
        e.line("function DvlCapInvoke%s(const Step: TDvlCapStep%s): Integer;" %
               (tag, tag))
        e.line("begin")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Assigned: TDvlCapStep%s;" % tag)
        e.line("  A, B: Integer;")
        e.line("begin")
        e.line("  { The nested body must not inherit the surrounding assignment flag. } ")
        e.line("  Assigned :=")
        e.line("    function: Integer")
        e.line("    var")
        e.line("      P: PDvlCapManaged%s;" % tag)
        e.line("    begin")
        e.line("      New(P);")
        e.line("      P^.Text := 'assigned';")
        e.line("      P^.Value := 34;")
        e.line("      Result := Length(P^.Text) + P^.Value;")
        e.line("      Dispose(P);")
        e.line("    end;")
        e.line("  A := Assigned();")
        e.line("  { Nor may it inherit the call-argument flag. } ")
        e.line("  B := DvlCapInvoke%s(" % tag)
        e.line("    function: Integer")
        e.line("    var")
        e.line("      P: PDvlCapManaged%s;" % tag)
        e.line("    begin")
        e.line("      New(P);")
        e.line("      P^.Text := 'call';")
        e.line("      P^.Value := 7;")
        e.line("      Result := Length(P^.Text) + P^.Value;")
        e.line("      Dispose(P);")
        e.line("    end);")
        e.line("  Result := A * 100 + B;")
        e.line("end;")
        e.line()
    elif shape == "captured-managed":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Text: AnsiString;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Text := Copy(AnsiString('ab'), 1, 2);")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      Result := Length(Text);")
        e.line("    end;")
        e.line("  Text := Copy(AnsiString('abcd'), 1, 4);")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "captured-record":
        e.line("type")
        e.line("  TDvlCapRec%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("  end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlCapRec%s;" % tag)
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Held.Slot := 1;")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      Result := Held.Slot;")
        e.line("    end;")
        e.line("  Held.Slot := 2;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "captured-array-slot":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Items: System.TArray<Integer>;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Items := [1, 1];")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      Result := Items[1];")
        e.line("    end;")
        e.line("  Items[1] := 2;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "self-in-method":
        e.line("type")
        e.line("  TDvlCap%s = class" % tag)
        e.line("  public")
        e.line("    Slot: Integer;")
        e.line("    function Ask: Integer;")
        e.line("    function Own: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlCap%s.Own: Integer;" % tag)
        e.line("begin")
        e.line("  Result := Slot;")
        e.line("end;")
        e.line()
        e.line("function TDvlCap%s.Ask: Integer;" % tag)
        e.line("var")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      { a method call through the captured Self }")
        e.line("      Result := Own;")
        e.line("    end;")
        e.line("  Slot := 2;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Held: TDvlCap%s;" % tag)
        e.line("begin")
        e.line("  Held := TDvlCap%s.Create;" % tag)
        e.line("  try")
        e.line("    Held.Slot := 1;")
        e.line("    Result := Held.Ask;")
        e.line("  finally")
        e.line("    Held.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif shape == "const-param":
        e.line("function DvlCapMake%s(const V: Integer): TDvlCapStep%s;"
               % (tag, tag))
        e.line("begin")
        e.line("  Result :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      { the parameter outlives the call that declared it }")
        e.line("      Result := V;")
        e.line("    end;")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Step := DvlCapMake%s(7);" % tag)
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "captured-in-thread":
        e.line("type")
        e.line("  TDvlCapWorker%s = class(TThread)" % tag)
        e.line("  public")
        e.line("    Step: TDvlCapStep%s;" % tag)
        e.line("    Seen: Integer;")
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlCapWorker%s.Execute;" % tag)
        e.line("begin")
        e.line("  Seen := Step();")
        e.line("end;")
        e.line()
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line("  Worker: TDvlCapWorker%s;" % tag)
        e.line("begin")
        e.line("  Slot := 7;")
        e.line("  Worker := TDvlCapWorker%s.Create(True);" % tag)
        e.line("  try")
        e.line("    Worker.FreeOnTerminate := False;")
        e.line("    Worker.Step :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Slot;")
        e.line("      end;")
        e.line("    Worker.Start;")
        e.line("    Worker.WaitFor;")
        e.line("    Result := Worker.Seen;")
        e.line("  finally")
        e.line("    Worker.Free;")
        e.line("  end;")
        e.line("end;")
        e.line()
    elif shape == "exception-var":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Step := nil;")
        e.line("  try")
        e.line("    raise Exception.Create('captured');")
        e.line("  except")
        e.line("    on E: Exception do")
        e.line("    begin")
        e.line("      var Seen := Length(E.Message);")
        e.line("      Step :=")
        e.line("        function: Integer")
        e.line("        begin")
        e.line("          { the handler has long returned by the call }")
        e.line("          Result := Seen;")
        e.line("        end;")
        e.line("    end;")
        e.line("  end;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    elif shape == "try-finally-var":
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Slot: Integer;")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("begin")
        e.line("  Slot := 1;")
        e.line("  try")
        e.line("    Step :=")
        e.line("      function: Integer")
        e.line("      begin")
        e.line("        Result := Slot;")
        e.line("      end;")
        e.line("  finally")
        e.line("    Slot := 2;")
        e.line("  end;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    else:   # recursive-capture
        e.line("function DvlCapAsk%s: Integer;" % tag)
        e.line("var")
        e.line("  Step: TDvlCapStep%s;" % tag)
        e.line("  Depth: Integer;")
        e.line("begin")
        e.line("  Depth := 0;")
        e.line("  Step :=")
        e.line("    function: Integer")
        e.line("    begin")
        e.line("      Inc(Depth);")
        e.line("      { the closure reaches itself through the variable it "
               "was stored in }")
        e.line("      If Depth < 3 then")
        e.line("        Result := Step()")
        e.line("      else")
        e.line("        Result := Depth;")
        e.line("    end;")
        e.line("  Result := Step();")
        e.line("end;")
        e.line()
    return ["  Answer := UInt64(DvlCapAsk%s);" % tag]


def layer_capture(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """What the closure saw when it finally ran."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, shape in enumerate(CAPTURE_SHAPES):
        index = start + offset
        name = "dvl-capture-%s" % shape
        proc = "DvlCap%05d" % index
        tag = "%05d" % index

        body = emit_capture_case(e, shape, tag)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Answer: UInt64;")
        e.line("begin")
        e.line("  { %s }" % shape)
        e.line("  Answer := $FFFFFFFF;")
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        for line in body:
            e.line(line)
        e.line("  { no model: the contract is that every compiler captures "
               "the same thing }")
        e.line("  DevilNote('%s', Answer);" % name)
        e.line("  DevilCheckBool('%s-ran', Answer <> $FFFFFFFF);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="capture",
                                  detail={"shape": shape}))

    emit_runner(e, "Capture", calls)
    return records


# where an attribute can sit, and whether it is still there at runtime
ATTR_TARGETS = ("class-type", "record-type", "class-field", "record-field",
                "method", "published-property", "public-property",
                "interface-type", "enum-type", "rtti-explicit-public")


def layer_attr(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """An attribute is only there if it comes back out of the tables."""
    e.line("type")
    e.line("  DvlAttrMarkAttribute = class(TCustomAttribute)")
    e.line("  public")
    e.line("    Tag: Integer;")
    e.line("    constructor Create(ATag: Integer);")
    e.line("  end;")
    e.line()
    e.line("constructor DvlAttrMarkAttribute.Create(ATag: Integer);")
    e.line("begin")
    e.line("  inherited Create;")
    e.line("  Tag := ATag;")
    e.line("end;")
    e.line()
    e.line("function DvlAttrSum(const Items: System.TArray<TCustomAttribute>): Integer;")
    e.line("var")
    e.line("  A: TCustomAttribute;")
    e.line("begin")
    e.line("  Result := 0;")
    e.line("  for A in Items do")
    e.line("    If A is DvlAttrMarkAttribute then")
    e.line("      Result := Result + DvlAttrMarkAttribute(A).Tag;")
    e.line("end;")
    e.line()

    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, target in enumerate(ATTR_TARGETS):
        index = start + offset
        name = "dvl-attr-%s-readback" % target
        proc = "DvlAttr%05d" % index
        tag = "%05d" % index
        mark = 7 + offset

        if target == "class-type":
            e.line("type")
            e.line("  [DvlAttrMark(%d)]" % mark)
            e.line("  TDvlAttr%s = class" % tag)
            e.line("  end;")
            e.line()
            read = ["  Seen := DvlAttrSum(Ctx.GetType(TDvlAttr%s)"
                    ".GetAttributes);" % tag]
        elif target == "record-type":
            e.line("type")
            e.line("  [DvlAttrMark(%d)]" % mark)
            e.line("  TDvlAttr%s = record" % tag)
            e.line("    Slot: Integer;")
            e.line("  end;")
            e.line()
            read = ["  Seen := DvlAttrSum(Ctx.GetType(TypeInfo(TDvlAttr%s))"
                    ".GetAttributes);" % tag]
        elif target == "class-field":
            e.line("type")
            e.line("  TDvlAttr%s = class" % tag)
            e.line("  public")
            e.line("    [DvlAttrMark(%d)]" % mark)
            e.line("    Slot: Integer;")
            e.line("  end;")
            e.line()
            read = ["  for var F in Ctx.GetType(TDvlAttr%s).GetFields do" % tag,
                    "    Seen := Seen + DvlAttrSum(F.GetAttributes);"]
        elif target == "record-field":
            e.line("type")
            e.line("  TDvlAttr%s = record" % tag)
            e.line("    [DvlAttrMark(%d)]" % mark)
            e.line("    Slot: Integer;")
            e.line("  end;")
            e.line()
            read = ["  for var F in Ctx.GetType(TypeInfo(TDvlAttr%s))"
                    ".GetFields do" % tag,
                    "    Seen := Seen + DvlAttrSum(F.GetAttributes);"]
        elif target == "method":
            e.line("type")
            e.line("  TDvlAttr%s = class" % tag)
            e.line("  public")
            e.line("    [DvlAttrMark(%d)]" % mark)
            e.line("    procedure Touch;")
            e.line("  end;")
            e.line()
            e.line("procedure TDvlAttr%s.Touch;" % tag)
            e.line("begin")
            e.line("end;")
            e.line()
            read = ["  for var M in Ctx.GetType(TDvlAttr%s).GetMethods do" % tag,
                    "    Seen := Seen + DvlAttrSum(M.GetAttributes);"]
        elif target in ("published-property", "public-property"):
            section = ("published" if target == "published-property"
                       else "public")
            e.line("{$M+}")
            e.line("type")
            e.line("  TDvlAttr%s = class" % tag)
            e.line("  private")
            e.line("    FSlot: Integer;")
            e.line("  %s" % section)
            e.line("    [DvlAttrMark(%d)]" % mark)
            e.line("    property Slot: Integer read FSlot write FSlot;")
            e.line("  end;")
            e.line("{$M-}")
            e.line()
            read = ["  for var P in Ctx.GetType(TDvlAttr%s).GetProperties do"
                    % tag,
                    "    Seen := Seen + DvlAttrSum(P.GetAttributes);"]
        elif target == "interface-type":
            e.line("type")
            e.line("  [DvlAttrMark(%d)]" % mark)
            e.line("  IDvlAttr%s = interface" % tag)
            e.line("    ['{3B%06X-0000-0000-0000-000000000001}']"
                   % (index % 0xFFFFFF))
            e.line("    procedure Touch;")
            e.line("  end;")
            e.line()
            read = ["  Seen := DvlAttrSum(Ctx.GetType(TypeInfo(IDvlAttr%s))"
                    ".GetAttributes);" % tag]
        elif target == "rtti-explicit-public":
            e.line("{ видимость published выведена из разрешённого набора: "
                   "атрибут такого свойства в таблицы попадать не должен }")
            e.line("{$RTTI EXPLICIT METHODS([vcPublic]) "
                   "PROPERTIES([vcPublic]) FIELDS([vcPublic])}")
            e.line("{$M+}")
            e.line("type")
            e.line("  TDvlAttr%s = class" % tag)
            e.line("  private")
            e.line("    FSlot: Integer;")
            e.line("  published")
            e.line("    [DvlAttrMark(%d)]" % mark)
            e.line("    property Slot: Integer read FSlot write FSlot;")
            e.line("  end;")
            e.line("{$M-}")
            e.line("{$RTTI EXPLICIT METHODS([vcPublic, vcPublished]) "
                   "PROPERTIES([vcPublic, vcPublished]) "
                   "FIELDS([vcPrivate, vcProtected, vcPublic, vcPublished])}")
            e.line()
            read = ["  for var P in Ctx.GetType(TDvlAttr%s).GetProperties do"
                    % tag,
                    "    Seen := Seen + DvlAttrSum(P.GetAttributes);"]
        else:   # enum-type
            e.line("type")
            e.line("  [DvlAttrMark(%d)]" % mark)
            e.line("  TDvlAttr%s = (dvlAttrA%s, dvlAttrB%s);" % (tag, tag, tag))
            e.line()
            read = ["  Seen := DvlAttrSum(Ctx.GetType(TypeInfo(TDvlAttr%s))"
                    ".GetAttributes);" % tag]

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Ctx: TRttiContext;")
        e.line("  Seen: Integer;")
        e.line("begin")
        e.line("  { %s: the mark is worth %d if it survived into the tables }"
               % (target, mark))
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        e.line("  Ctx := TRttiContext.Create;")
        e.line("  Seen := 0;")
        for line in read:
            e.line(line)
        e.line("  DevilNote('%s', UInt64(Cardinal(Seen)));" % name)
        e.line("  DevilCheckBool('%s-typed', Ctx.GetType(TypeInfo(Integer)) "
               "<> nil);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="attr",
                                  detail={"target": target, "mark": mark}))

    emit_runner(e, "Attr", calls)
    return records


# как аргумент доезжает до места, где принимается решение
DELIVER_WAYS = ("direct", "paren", "paren-twice", "cast", "identity-add",
                "identity-sub", "identity-mul", "identity-or", "inline-result",
                "noinline-result", "ppu-const", "generic-arg", "closure",
                "with-scope", "thread", "const-param", "typed-const",
                "case-arm", "ternary-like")

# доставки, которые ничего не значат для нечислового носителя
DELIVER_NUMERIC_ONLY = {"identity-add", "identity-sub", "identity-mul",
                        "identity-or"}

# (семейство кандидатов, форма аргумента, тип носителя, литерал, каст,
#  имя такой же константы в чужом юните)
DELIVER_QUESTIONS = (
    ("int-sign", "lit-1", "Integer", "1", "Byte", "DvlProvOne"),
    ("int-sign", "var-byte", "Byte", "7", "Byte", "DvlProvSeven"),
    ("int-sign64", "lit-1", "Int64", "1", "Cardinal", "DvlProvOne"),
    ("int-width", "lit-300", "Integer", "300", "Word", "DvlProvThreeHundred"),
    ("int-narrow", "lit-big64", "Int64", "5000000000", "Int64", "DvlProvBig"),
    ("num-float", "lit-1", "Integer", "1", "Byte", "DvlProvOne"),
    ("variant", "lit-1", "Integer", "1", "Byte", "DvlProvOne"),
    ("char-form", "lit-char", "Char", "'a'", "Char", "DvlProvChar"),
    ("string-form", "lit-str", "UnicodeString", "'ab'", "UnicodeString",
     "DvlProvText"),
    ("string-four", "lit-str", "UnicodeString", "'ab'", "UnicodeString",
     "DvlProvText"),
)


def deliver_pairs() -> list[tuple]:
    out = []
    for question in DELIVER_QUESTIONS:
        numeric = question[2] not in ("Char", "UnicodeString")
        for way in DELIVER_WAYS:
            if way in DELIVER_NUMERIC_ONLY and not numeric:
                continue
            out.append(question + (way,))
    return out


def emit_deliver_candidates(e: Emitter, family: str, func: str) -> None:
    for candidate, kind in enumerate(PICK_FAMILIES[family], start=1):
        e.line("function %s(const V: %s): Integer; overload;" % (func, kind))
        e.line("begin")
        e.line("  Result := %d;" % candidate)
        e.line("end;")
        e.line()


def emit_deliver_way(e: Emitter, way: str, carrier: str, literal: str,
                     cast: str, imported: str,
                     tag: str) -> tuple[list[str], str]:
    """Машинерия доставки; возвращает тело подготовки и само выражение."""
    if way == "direct":
        return [], literal
    if way == "paren":
        return [], "(%s)" % literal
    if way == "paren-twice":
        return [], "((%s))" % literal
    if way == "cast":
        return [], "%s(%s)" % (cast, literal)
    if way == "identity-add":
        return [], "%s + 0" % literal
    if way == "identity-sub":
        return [], "%s - 0" % literal
    if way == "identity-mul":
        return [], "%s * 1" % literal
    if way == "identity-or":
        return [], "%s or 0" % literal
    if way in ("inline-result", "noinline-result"):
        if way == "noinline-result":
            e.line("{$ifdef FPC}{$push}{$optimization noautoinline}{$endif}")
        e.line("function DvlDl%s: %s;%s"
               % (tag, carrier, " inline;" if way == "inline-result" else ""))
        e.line("begin")
        e.line("  { константа, появившаяся после подстановки, — не то же самое,")
        e.line("    что константа, написанная на месте вызова }")
        e.line("  Result := %s;" % literal)
        e.line("end;")
        if way == "noinline-result":
            e.line("{$ifdef FPC}{$pop}{$endif}")
        e.line()
        return [], "DvlDl%s" % tag
    if way == "ppu-const":
        return [], imported
    if way == "generic-arg":
        e.line("type")
        e.line("  TDvlDl%s = record" % tag)
        e.line("    class function Pass<T>(const V: T): T; static;")
        e.line("  end;")
        e.line()
        e.line("class function TDvlDl%s.Pass<T>(const V: T): T;" % tag)
        e.line("begin")
        e.line("  Result := V;")
        e.line("end;")
        e.line()
        return [], "TDvlDl%s.Pass<%s>(%s)" % (tag, carrier, literal)
    if way == "closure":
        e.line("type")
        e.line("  TDvlDlStep%s = reference to function: %s;" % (tag, carrier))
        e.line()
        return ["  var Step: TDvlDlStep%s;" % tag,
                "  Step :=",
                "    function: %s" % carrier,
                "    begin",
                "      Result := %s;" % literal,
                "    end;"], "Step()"
    if way == "with-scope":
        e.line("type")
        e.line("  TDvlDlBox%s = record" % tag)
        e.line("    Slot: %s;" % carrier)
        e.line("  end;")
        e.line()
        return ["  var Held: TDvlDlBox%s;" % tag,
                "  Held.Slot := %s;" % literal], "Held.Slot"
    if way == "thread":
        e.line("type")
        e.line("  TDvlDlWorker%s = class(TThread)" % tag)
        e.line("  public")
        e.line("    Output: %s;" % carrier)
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlDlWorker%s.Execute;" % tag)
        e.line("begin")
        e.line("  Output := %s;" % literal)
        e.line("end;")
        e.line()
        return ["  var Worker := TDvlDlWorker%s.Create(True);" % tag,
                "  Worker.FreeOnTerminate := False;",
                "  Worker.Start;",
                "  Worker.WaitFor;",
                "  var Carried := Worker.Output;",
                "  Worker.Free;"], "Carried"
    if way == "const-param":
        e.line("function DvlDl%s(const V: %s): %s;" % (tag, carrier, carrier))
        e.line("begin")
        e.line("  Result := V;")
        e.line("end;")
        e.line()
        return [], "DvlDl%s(%s)" % (tag, literal)
    if way == "typed-const":
        e.line("const")
        e.line("  DvlDlConst%s: %s = %s;" % (tag, carrier, literal))
        e.line()
        return [], "DvlDlConst%s" % tag
    if way == "case-arm":
        return ["  var Carried: %s;" % carrier,
                "  case DevilFeedCount and 0 of",
                "    0: Carried := %s;" % literal,
                "  else",
                "    Carried := %s;" % literal,
                "  end;"], "Carried"
    # ternary-like: значение приходит из ветки, которую компилятор знает
    return ["  var Carried: %s;" % carrier,
            "  If DevilFeedCount >= 0 then",
            "    Carried := %s" % literal,
            "  else",
            "    Carried := %s;" % literal], "Carried"


def layer_deliver(e: Emitter, rng: random.Random, count: int,
                  start: int) -> list[CaseRecord]:
    """Тот же вопрос о выборе кандидата, но заданный после пересадки."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, (family, arg, carrier, literal, cast, imported, way) in \
            enumerate(deliver_pairs()):
        index = start + offset
        name = "dvl-deliver-%s-%s-%s" % (family, arg, way)
        proc = "DvlDeliver%05d" % index
        tag = "%05d" % index
        func = "DvlDeliverPick%s" % tag

        emit_deliver_candidates(e, family, func)
        setup, expr = emit_deliver_way(e, way, carrier, literal, cast,
                                       imported, tag)

        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Picked: Integer;")
        e.line("begin")
        e.line("  { семейство %s, аргумент %s, доставка %s }"
               % (family, arg, way))
        # порядковый канал: кейс таблицы исполняется ровно один раз и на своём месте
        e.line("  DevilStep('%s');" % name)
        for line in setup:
            e.line(line)
        e.line("  Picked := %s(%s);" % (func, expr))
        e.line("  { модели нет: контракт в том, что после любой доставки все "
               "компиляторы выбирают одного }")
        e.line("  DevilNote('%s', UInt64(Picked));" % name)
        e.line("  DevilCheckBool('%s-called', Picked > 0);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="deliver",
                                  detail={"family": family, "arg": arg,
                                          "way": way}))

    emit_runner(e, "Deliver", calls)
    return records


def write_provenance_unit(out: Path) -> None:
    """Юнит, чьи константы приезжают через PPU: провенанс обязан пережить."""
    lines = ["unit devil_provenance;", "",
             "{$ifdef FPC}",
             "  {$mode delphiunicode}{$H+}",
             "  {$modeswitch advancedrecords}",
             "{$endif}", "",
             "interface", "",
             "{ нетипизированные константы: по тексту ремонта именно их }",
             "{ провенанс сериализуется в PPU и обязан пережить границу }",
             "const",
             "  DvlProvOne = 1;",
             "  DvlProvSeven = 7;",
             "  DvlProvThreeHundred = 300;",
             "  DvlProvBig = 5000000000;",
             "  DvlProvChar = 'a';",
             "  DvlProvText = 'ab';", "",
             "implementation", "",
             "end."]
    (out / "devil_provenance.pas").write_text("\n".join(lines) + "\n",
                                              encoding="utf-8")


# размеры, на которых аллокатор дерётся: вся сетка малых классов с упором на
# крупные - там, где индекс диагностического массива уходил за его границу
LOAD_SIZES = (16, 48, 112, 240, 480, 704, 720, 1056, 1504, 2176, 2608,
              4096, 65536)

# формы нагрузки: чем именно потоки мучают аллокатор
LOAD_SHAPES = ("same-size", "walk-sizes", "grow-shrink", "hold-many",
               "alloc-free-alien", "zeroed", "realloc")

LOAD_THREADS = 8
LOAD_ROUNDS = 400

# тяжёлая форма: замер счётчиками самого аллокатора показал, что ожидание на
# пути малых блоков начинается с 32 потоков и только при удержании тысяч
# блоков одного класса - иначе лок успевает отработать на spin
LOAD_CONTENDED_THREADS = 48

# каждый поток удерживает примерно этот объём: число блоков считается от их
# размера, иначе мелкие классы не исчерпывают пул, а крупные упираются в память
LOAD_CONTENDED_BYTES = 8 * 1024 * 1024
LOAD_CONTENDED_MIN_HOLD = 2000

# 704 = 44 класса по 16 байт: граница, за которой у аллокатора кончался
# диагностический массив, а индекс продолжался
# 2600 - последний размер, который аллокатор ещё обслуживает малым
# блоком: запрос на 2608 уже уходит в medium (MemSize отдаёт 2856)
LOAD_CONTENDED_SIZES = (240, 688, 704, 720, 1504, 2600)

# перекрёстная форма: те же размеры, но блок освобождает чужой поток
LOAD_HANDOFF_SIZES = (240, 704, 720, 2600)
LOAD_HANDOFF_SLOTS = 512


def layer_load(e: Emitter, rng: random.Random, count: int,
               start: int) -> list[CaseRecord]:
    """Настоящая драка за аллокатор и проверка, что он никого не обманул."""
    # таблица размеров объявляется первой: её читает тело рабочего потока
    e.line("const")
    e.line("  DvlLoadSizes: array[0..%d] of PtrUInt = (%s);"
           % (len(LOAD_SIZES) - 1, ", ".join(str(s) for s in LOAD_SIZES)))
    e.line()
    e.line("type")
    e.line("  TDvlLoadWorker = class(TThread)")
    e.line("  public")
    e.line("    Shape: Integer;")
    e.line("    Slot: Integer;")
    e.line("    Size: PtrUInt;")
    e.line("    Corrupt: Integer;   { чужой шаблон в своём блоке }")
    e.line("    TooSmall: Integer;  { выдан блок меньше запрошенного }")
    e.line("    Dirty: Integer;     { обещали обнулить и не обнулили }")
    e.line("    Rounds: Integer;")
    e.line("    Hold: Integer;      { сколько блоков держать живыми разом }")
    e.line("    Handoff: PPointer;  { общий стол: блок уходит соседу }")
    e.line("    Slots: Integer;")
    e.line("    procedure Execute; override;")
    e.line("  end;")
    e.line()
    e.line("procedure TDvlLoadWorker.Execute;")
    e.line("var")
    e.line("  Held: array of PByte;")
    e.line("  Sizes: array of PtrUInt;")
    e.line("  Mark: Byte;")
    e.line("  Round, Index, Kept: Integer;")
    e.line("  Want: PtrUInt;")
    e.line("  P: PByte;")
    e.line()
    e.line("  procedure Stamp(Q: PByte; Bytes: PtrUInt);")
    e.line("  begin")
    e.line("    { шаблон владельца в начале и в конце: чужая выдача затрёт }")
    e.line("    Q[0] := Mark;")
    e.line("    Q[Bytes - 1] := Mark;")
    e.line("  end;")
    e.line()
    e.line("  procedure Verify(Q: PByte; Bytes: PtrUInt);")
    e.line("  begin")
    e.line("    If (Q[0] <> Mark) or (Q[Bytes - 1] <> Mark) then")
    e.line("      Inc(Corrupt);")
    e.line("  end;")
    e.line()
    e.line("begin")
    e.line("  Mark := Byte(Slot + 1);")
    e.line("  Kept := 0;")
    e.line("  If Hold < 16 then")
    e.line("    Hold := 16;")
    e.line("  SetLength(Held, Hold);")
    e.line("  SetLength(Sizes, Hold);")
    e.line("  for Round := 1 to Rounds do")
    e.line("  begin")
    e.line("    case Shape of")
    e.line("      1: Want := DvlLoadSizes[Round mod Length(DvlLoadSizes)];")
    e.line("      2: Want := Size + PtrUInt((Round mod 64) * 16);")
    e.line("      3: Want := Size;")
    e.line("    else")
    e.line("      Want := Size;")
    e.line("    end;")
    e.line("    If Want < 8 then")
    e.line("      Want := 8;")
    e.line("    case Shape of")
    e.line("      5:")
    e.line("        begin")
    e.line("          { память обещана обнулённой }")
    e.line("          P := AllocMem(Want);")
    e.line("          If (P[0] <> 0) or (P[Want - 1] <> 0) then")
    e.line("            Inc(Dirty);")
    e.line("        end;")
    e.line("      6:")
    e.line("        begin")
    e.line("          P := GetMemory(Want);")
    e.line("          Stamp(P, Want);")
    e.line("          P := ReallocMemory(P, Want * 2);")
    e.line("          { первый байт обязан пережить перенос }")
    e.line("          If P[0] <> Mark then")
    e.line("            Inc(Corrupt);")
    e.line("          Want := Want * 2;")
    e.line("        end;")
    e.line("    else")
    e.line("      P := GetMemory(Want);")
    e.line("    end;")
    e.line("    If P = nil then")
    e.line("      Continue;")
    e.line("    If PtrUInt(MemSize(P)) < Want then")
    e.line("      Inc(TooSmall);")
    e.line("    Stamp(P, Want);")
    e.line("    If Shape = 9 then")
    e.line("    begin")
    e.line("      { блок кладётся на общий стол, а забирает и освобождает его "
           "другой поток: возврат идёт мимо своей арены }")
    e.line("      Index := (Round * 7 + Slot) mod Slots;")
    e.line("      P := PByte(InterlockedExchange(Handoff[Index], P));")
    e.line("      If P <> nil then")
    e.line("        FreeMemory(P);")
    e.line("      Continue;")
    e.line("    end;")
    e.line("    If Shape = 8 then")
    e.line("    begin")
    e.line("      { пул исчерпывается, и аллокатор доразмещает его под локом }")
    e.line("      Held[Kept] := P;")
    e.line("      Sizes[Kept] := Want;")
    e.line("      Inc(Kept);")
    e.line("      If Kept < Hold then")
    e.line("        Continue;")
    e.line("      for Index := 0 to Kept - 1 do")
    e.line("      begin")
    e.line("        Verify(Held[Index], Sizes[Index]);")
    e.line("        FreeMemory(Held[Index]);")
    e.line("      end;")
    e.line("      Kept := 0;")
    e.line("      Continue;")
    e.line("    end;")
    e.line("    If Shape = 4 then")
    e.line("    begin")
    e.line("      { держим пачку блоков живыми: возврат идёт с задержкой }")
    e.line("      If Kept < Hold then")
    e.line("      begin")
    e.line("        Held[Kept] := P;")
    e.line("        Sizes[Kept] := Want;")
    e.line("        Inc(Kept);")
    e.line("        Continue;")
    e.line("      end;")
    e.line("      for Index := 0 to High(Held) do")
    e.line("      begin")
    e.line("        Verify(Held[Index], Sizes[Index]);")
    e.line("        FreeMemory(Held[Index]);")
    e.line("      end;")
    e.line("      Kept := 0;")
    e.line("    end;")
    e.line("    Verify(P, Want);")
    e.line("    FreeMemory(P);")
    e.line("  end;")
    e.line("  for Index := 0 to Kept - 1 do")
    e.line("  begin")
    e.line("    Verify(Held[Index], Sizes[Index]);")
    e.line("    FreeMemory(Held[Index]);")
    e.line("  end;")
    e.line("end;")
    e.line()

    records: list[CaseRecord] = []
    calls: list[str] = []
    plan = [(shape, size) for shape in LOAD_SHAPES for size in LOAD_SIZES]
    plan += [("contended", size) for size in LOAD_CONTENDED_SIZES]
    plan += [("handoff", size) for size in LOAD_HANDOFF_SIZES]
    for offset in range(min(count, len(plan))):
        shape, size = plan[offset]
        index = start + offset
        name = "dvl-load-%s-%d" % (shape, size)
        proc = "DvlLoad%05d" % index
        handoff = shape == "handoff"
        heavy = shape == "contended" or handoff
        code = (9 if handoff else 8) if heavy else LOAD_SHAPES.index(shape) + 1
        threads = LOAD_CONTENDED_THREADS if heavy else LOAD_THREADS
        # у самого крупного малого класса пул короткий (двенадцать блоков),
        # поэтому его берут не объёмом, а оборотом: держать мало, крутить много,
        # чтобы пул непрерывно строился и разрушался под локом
        if heavy and size >= 2048:
            hold = 64
            rounds = 40000
        elif heavy:
            hold = max(LOAD_CONTENDED_MIN_HOLD, LOAD_CONTENDED_BYTES // size)
            rounds = hold * 3
        else:
            hold = 16
            rounds = LOAD_ROUNDS

        if handoff:
            e.line("var")
            e.line("  DvlLoadTable%05d: array[0..%d] of Pointer;"
                   % (index, LOAD_HANDOFF_SLOTS - 1))
            e.line()
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Crew: array[0..%d] of TDvlLoadWorker;" % (threads - 1))
        e.line("  I, Corrupt, TooSmall, Dirty: Integer;")
        if heavy:
            e.line("  Held0, Held1: PtrUInt;   { занято до и после }")
            e.line("  Sleeps0, Sleeps1: PtrUInt;")
        e.line("begin")
        e.line("  { %s: %d потоков дерутся за блоки по %d байт%s }"
               % (shape, threads, size,
                  ", удерживая по %d" % hold if heavy else ""))
        e.line("  for I := 0 to High(Crew) do")
        e.line("  begin")
        e.line("    Crew[I] := TDvlLoadWorker.Create(True);")
        e.line("    Crew[I].FreeOnTerminate := False;")
        e.line("    Crew[I].Shape := %d;" % code)
        e.line("    Crew[I].Slot := I;")
        e.line("    Crew[I].Size := %d;" % size)
        e.line("    Crew[I].Rounds := %d;" % rounds)
        e.line("    Crew[I].Hold := %d;" % hold)
        if handoff:
            e.line("    Crew[I].Handoff := @DvlLoadTable%05d[0];" % index)
            e.line("    Crew[I].Slots := %d;" % LOAD_HANDOFF_SLOTS)
        e.line("  end;")
        if heavy:
            e.line("  Held0 := CurrentHeapStatus.SmallBlocksSize;")
            e.line("  Sleeps0 := CurrentHeapStatus.SleepCount;")
        e.line("  { старт всем сразу: драка нужна одновременная }")
        e.line("  for I := 0 to High(Crew) do")
        e.line("    Crew[I].Start;")
        e.line("  Corrupt := 0;")
        e.line("  TooSmall := 0;")
        e.line("  Dirty := 0;")
        e.line("  for I := 0 to High(Crew) do")
        e.line("  begin")
        e.line("    Crew[I].WaitFor;")
        e.line("    Inc(Corrupt, Crew[I].Corrupt);")
        e.line("    Inc(TooSmall, Crew[I].TooSmall);")
        e.line("    Inc(Dirty, Crew[I].Dirty);")
        e.line("    Crew[I].Free;")
        e.line("  end;")
        if handoff:
            e.line("  { всё, что осталось на столе, освобождает главный поток }")
            e.line("  for I := 0 to %d do" % (LOAD_HANDOFF_SLOTS - 1))
            e.line("    If DvlLoadTable%05d[I] <> nil then" % index)
            e.line("    begin")
            e.line("      FreeMemory(DvlLoadTable%05d[I]);" % index)
            e.line("      DvlLoadTable%05d[I] := nil;" % index)
            e.line("    end;")
        if heavy:
            e.line("  Held1 := CurrentHeapStatus.SmallBlocksSize;")
            e.line("  Sleeps1 := CurrentHeapStatus.SleepCount;")
            e.line("  { всё, что взяли, вернули: занятый объём обязан "
                   "вернуться к исходному }")
            e.line("  DevilCheckBool('%s-balance', Held1 <= Held0);" % name)
            e.line("  { счётчик сна не может уменьшиться }")
            e.line("  DevilCheckBool('%s-monotonic', Sleeps1 >= Sleeps0);" % name)
        e.line("  { сведение и проверки - из главного потока, после join }")
        e.line("  DevilCheckU('%s-owner', UInt64(Cardinal(Corrupt)), 0);" % name)
        e.line("  DevilCheckU('%s-size', UInt64(Cardinal(TooSmall)), 0);" % name)
        e.line("  DevilCheckU('%s-zeroed', UInt64(Cardinal(Dirty)), 0);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="load",
                                  detail={"shape": shape, "size": size}))

    emit_runner(e, "Load", calls)
    return records


# формы контракта библиотеки: имя кейса называет, что именно спрашивается
RTL_SHAPES = (
    "stringlist-indexof", "stringlist-indexof-case", "stringlist-sorted-find",
    "stringlist-duplicates", "stringlist-delete-shift", "stringlist-names",
    "stringlist-text-roundtrip",
    "stream-seek-end", "stream-seek-beyond", "stream-copyfrom",
    "stringstream-read-chunks", "stringstream-unicode",
    "dynarray-copy-unmanaged", "dynarray-copy-managed", "dynarray-shrink",
    "dynarray-insert-delete", "dynarray-of-record-copy",
    "list-remove-order", "list-sort-order", "list-extract",
    "dict-add-lookup", "dict-remove-rehash", "dict-pairs",
    "pos-and-copy", "stringreplace-all", "trim-forms", "sametext-ascii",
    "uppercase-ascii", "int-to-str-bounds",
    "utf8-roundtrip", "utf8-length", "ansi-to-unicode-roundtrip",
    "path-extract", "path-change-ext",
)


def emit_rtl_case(e: Emitter, shape: str, tag: str) -> list[str]:
    """Тело кейса: считает Answer, который обязан совпасть у обеих сторон."""
    q = chr(39)      # апостроф: Pascal-литералы собираются без путаницы кавычек

    def s(text: str) -> str:
        return q + text + q

    if shape == "stringlist-indexof":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Add(%s); L.Add(%s); L.Add(%s);"
                % (s("alpha"), s("beta"), s("gamma")),
                "    Answer := UInt64(Cardinal(L.IndexOf(%s) + 1)) shl 8;"
                % s("beta"),
                "    Answer := Answer or UInt64(Cardinal(L.IndexOf(%s) + 2));"
                % s("nope"),
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-indexof-case":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Add(%s); L.Add(%s);" % (s("Alpha"), s("BETA")),
                "    { по умолчанию поиск без учёта регистра }",
                "    Answer := UInt64(Cardinal(L.IndexOf(%s) + 1)) shl 8;"
                % s("alpha"),
                "    L.CaseSensitive := True;",
                "    Answer := Answer or UInt64(Cardinal(L.IndexOf(%s) + 2));"
                % s("alpha"),
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-sorted-find":
        return ["  var L := TStringList.Create;",
                "  var Where: Integer;",
                "  try",
                "    L.Add(%s); L.Add(%s); L.Add(%s);"
                % (s("delta"), s("alpha"), s("charlie")),
                "    L.Sorted := True;",
                "    Answer := UInt64(Cardinal(Ord(L.Find(%s, Where)))) shl 8;"
                % s("charlie"),
                "    Answer := Answer or UInt64(Cardinal(Where + 1));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-duplicates":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Sorted := True;",
                "    L.Duplicates := dupIgnore;",
                "    L.Add(%s); L.Add(%s); L.Add(%s);"
                % (s("one"), s("one"), s("two")),
                "    Answer := UInt64(Cardinal(L.Count));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-delete-shift":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Add(%s); L.Add(%s); L.Add(%s);"
                % (s("a"), s("b"), s("c")),
                "    L.Delete(1);",
                "    Answer := UInt64(Cardinal(L.Count)) shl 8;",
                "    Answer := Answer or UInt64(Ord(L[1] = %s));" % s("c"),
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-names":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Add(%s); L.Add(%s);"
                % (s("key=value"), s("other=thing")),
                "    Answer := UInt64(Cardinal(Length(L.Names[0]))) shl 8;",
                "    Answer := Answer or "
                "UInt64(Cardinal(Length(L.ValueFromIndex[1])));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stringlist-text-roundtrip":
        return ["  var L := TStringList.Create;",
                "  try",
                "    L.Add(%s); L.Add(%s);" % (s("first"), s("second")),
                "    var Whole := L.Text;",
                "    L.Clear;",
                "    L.Text := Whole;",
                "    Answer := UInt64(Cardinal(L.Count)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(Length(L[1])));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "stream-seek-end":
        return ["  var S := TMemoryStream.Create;",
                "  var Buf: array[0..15] of Byte;",
                "  try",
                "    FillChar(Buf, SizeOf(Buf), 7);",
                "    S.WriteBuffer(Buf, SizeOf(Buf));",
                "    Answer := UInt64(S.Seek(Int64(0), soEnd)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(S.Size));",
                "  finally",
                "    S.Free;",
                "  end;"]
    if shape == "stream-seek-beyond":
        return ["  var S := TMemoryStream.Create;",
                "  var Buf: array[0..7] of Byte;",
                "  try",
                "    FillChar(Buf, SizeOf(Buf), 1);",
                "    S.WriteBuffer(Buf, SizeOf(Buf));",
                "    { позиция за концом разрешена, размер при этом не растёт }",
                "    Answer := UInt64(S.Seek(Int64(64), soBeginning)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(S.Size));",
                "  finally",
                "    S.Free;",
                "  end;"]
    if shape == "stream-copyfrom":
        return ["  var A := TMemoryStream.Create;",
                "  var B := TMemoryStream.Create;",
                "  var Buf: array[0..31] of Byte;",
                "  try",
                "    FillChar(Buf, SizeOf(Buf), 9);",
                "    A.WriteBuffer(Buf, SizeOf(Buf));",
                "    A.Position := 0;",
                "    B.CopyFrom(A, 0);",
                "    Answer := UInt64(Cardinal(B.Size)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(B.Position));",
                "  finally",
                "    B.Free;",
                "    A.Free;",
                "  end;"]
    if shape == "stringstream-read-chunks":
        return ["  var S := TStringStream.Create(%s);" % s("abcdefghij"),
                "  try",
                "    S.Position := 0;",
                "    Answer := UInt64(Cardinal(Length(S.ReadString(4)))) shl 8;",
                "    Answer := Answer or "
                "UInt64(Cardinal(Length(S.ReadString(99))));",
                "  finally",
                "    S.Free;",
                "  end;"]
    if shape == "stringstream-unicode":
        return ["  var S := TStringStream.Create(#$0410#$0411#$0412);",
                "  try",
                "    Answer := UInt64(Cardinal(S.Size)) shl 8;",
                "    S.Position := 0;",
                "    Answer := Answer or UInt64(Cardinal(Length(S.DataString)));",
                "  finally",
                "    S.Free;",
                "  end;"]
    if shape == "dynarray-copy-unmanaged":
        return ["  var A: System.TArray<Integer>;",
                "  A := [1, 2, 3, 4, 5];",
                "  var B := Copy(A, 1, 3);",
                "  Answer := UInt64(Cardinal(Length(B))) shl 8;",
                "  Answer := Answer or UInt64(Cardinal(B[0] + B[2]));"]
    if shape == "dynarray-copy-managed":
        return ["  var A: System.TArray<string>;",
                "  A := [%s, %s, %s];" % (s("one"), s("two"), s("three")),
                "  var B := Copy(A, 1, 2);",
                "  B[0] := %s;" % s("changed"),
                "  { копия обязана быть отдельной }",
                "  Answer := UInt64(Cardinal(Length(B))) shl 8;",
                "  Answer := Answer or UInt64(Ord(A[1] = %s));" % s("two")]
    if shape == "dynarray-shrink":
        return ["  var A: System.TArray<Integer>;",
                "  SetLength(A, 8);",
                "  A[7] := 42;",
                "  SetLength(A, 3);",
                "  SetLength(A, 8);",
                "  { выросший хвост обязан быть нулевым }",
                "  Answer := UInt64(Cardinal(Length(A))) shl 8;",
                "  Answer := Answer or UInt64(Cardinal(A[7]));"]
    if shape == "dynarray-insert-delete":
        return ["  var A: System.TArray<Integer>;",
                "  A := [1, 2, 3];",
                "  Insert([9], A, 1);",
                "  Delete(A, 0, 1);",
                "  Answer := UInt64(Cardinal(Length(A))) shl 8;",
                "  Answer := Answer or UInt64(Cardinal(A[0]));"]
    if shape == "dynarray-of-record-copy":
        e.line("type")
        e.line("  TDvlRtlRec%s = record" % tag)
        e.line("    Slot: Integer;")
        e.line("    Text: string;")
        e.line("  end;")
        e.line()
        return ["  var A: System.TArray<TDvlRtlRec%s>;" % tag,
                "  SetLength(A, 2);",
                "  A[0].Slot := 5;",
                "  A[0].Text := %s;" % s("five"),
                "  var B := Copy(A, 0, 2);",
                "  B[0].Text := %s;" % s("other"),
                "  Answer := UInt64(Cardinal(B[0].Slot)) shl 8;",
                "  Answer := Answer or UInt64(Ord(A[0].Text = %s));" % s("five")]
    if shape == "list-remove-order":
        return ["  var L := TList<Integer>.Create;",
                "  try",
                "    L.AddRange([10, 20, 30, 20]);",
                "    L.Remove(20);",
                "    Answer := UInt64(Cardinal(L.Count)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(L[1]));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "list-sort-order":
        return ["  var L := TList<Integer>.Create;",
                "  try",
                "    L.AddRange([5, 1, 4, 1, 3]);",
                "    L.Sort;",
                "    Answer := UInt64(Cardinal(L[0])) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(L[L.Count - 1]));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "list-extract":
        return ["  var L := TList<Integer>.Create;",
                "  try",
                "    L.AddRange([7, 8, 9]);",
                "    var Got := L.Extract(8);",
                "    Answer := UInt64(Cardinal(Got)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(L.Count));",
                "  finally",
                "    L.Free;",
                "  end;"]
    if shape == "dict-add-lookup":
        return ["  var D := TDictionary<string, Integer>.Create;",
                "  var Got: Integer;",
                "  try",
                "    D.Add(%s, 1);" % s("one"),
                "    D.AddOrSetValue(%s, 11);" % s("one"),
                "    Answer := UInt64(Ord(D.TryGetValue(%s, Got))) shl 8;"
                % s("one"),
                "    Answer := Answer or UInt64(Cardinal(Got));",
                "  finally",
                "    D.Free;",
                "  end;"]
    if shape == "dict-remove-rehash":
        return ["  var D := TDictionary<Integer, Integer>.Create;",
                "  var Got: Integer;",
                "  var I: Integer;",
                "  try",
                "    for I := 0 to 63 do",
                "      D.Add(I, I * 2);",
                "    for I := 0 to 31 do",
                "      D.Remove(I);",
                "    Answer := UInt64(Cardinal(D.Count)) shl 8;",
                "    Answer := Answer or UInt64(Ord(D.TryGetValue(40, Got)));",
                "  finally",
                "    D.Free;",
                "  end;"]
    if shape == "dict-pairs":
        return ["  var D := TDictionary<Integer, Integer>.Create;",
                "  var Sum: Integer;",
                "  try",
                "    D.Add(1, 10);",
                "    D.Add(2, 20);",
                "    Sum := 0;",
                "    for var Pair in D do",
                "      Sum := Sum + Pair.Value;",
                "    Answer := UInt64(Cardinal(Sum)) shl 8;",
                "    Answer := Answer or UInt64(Cardinal(D.Count));",
                "  finally",
                "    D.Free;",
                "  end;"]
    if shape == "pos-and-copy":
        return ["  var S: string := %s;" % s("abcdefabc"),
                "  Answer := UInt64(Cardinal(Pos(%s, S))) shl 8;" % s("def"),
                "  Answer := Answer or UInt64(Cardinal(Length(Copy(S, 4, 99))));"]
    if shape == "stringreplace-all":
        return ["  var S := StringReplace(%s, %s, %s, [rfReplaceAll]);"
                % (s("a-b-c"), s("-"), s("+")),
                "  Answer := UInt64(Cardinal(Length(S))) shl 8;",
                "  Answer := Answer or UInt64(Cardinal(Pos(%s, S)));" % s("+")]
    if shape == "trim-forms":
        return ["  Answer := UInt64(Cardinal(Length(Trim(%s)))) shl 8;"
                % s("  x  "),
                "  Answer := Answer or "
                "UInt64(Cardinal(Length(TrimLeft(%s))));" % s("  x ")]
    if shape == "sametext-ascii":
        return ["  Answer := UInt64(Ord(SameText(%s, %s))) shl 8;"
                % (s("Alpha"), s("ALPHA")),
                "  Answer := Answer or UInt64(Ord(SameStr(%s, %s)));"
                % (s("Alpha"), s("ALPHA"))]
    if shape == "uppercase-ascii":
        return ["  Answer := UInt64(Cardinal(Length(UpperCase(%s)))) shl 8;"
                % s("mixedCase"),
                "  Answer := Answer or UInt64(Ord(UpperCase(%s) = %s));"
                % (s("abc"), s("ABC"))]
    if shape == "int-to-str-bounds":
        return ["  Answer := UInt64(Cardinal(Length(IntToStr(Low(Int64))))) shl 8;",
                "  Answer := Answer or "
                "UInt64(Cardinal(Length(IntToStr(High(Int64)))));"]
    if shape == "utf8-roundtrip":
        return ["  var W: string := %s + #$0410 + #$4E2D;" % s("ab"),
                "  var U := UTF8Encode(W);",
                "  var Back := UTF8ToString(U);",
                "  Answer := UInt64(Cardinal(Length(U))) shl 8;",
                "  Answer := Answer or UInt64(Ord(Back = W));"]
    if shape == "utf8-length":
        return ["  var U: UTF8String := UTF8Encode(%s + #$0410 + #$4E2D);"
                % s("a"),
                "  Answer := UInt64(Cardinal(Length(U))) shl 8;",
                "  Answer := Answer or "
                "UInt64(Cardinal(Length(UTF8ToString(U))));"]
    if shape == "ansi-to-unicode-roundtrip":
        return ["  var A: AnsiString := AnsiString(%s);" % s("plain"),
                "  var W: string := string(A);",
                "  Answer := UInt64(Cardinal(Length(W))) shl 8;",
                "  Answer := Answer or UInt64(Ord(AnsiString(W) = A));"]
    if shape == "path-extract":
        return ["  var P: string := %s + PathDelim + %s + PathDelim + %s;"
                % (s("dir"), s("sub"), s("file.txt")),
                "  Answer := UInt64(Cardinal(Length(ExtractFileName(P)))) shl 8;",
                "  Answer := Answer or "
                "UInt64(Cardinal(Length(ExtractFileExt(P))));"]
    # path-change-ext
    return ["  var P: string := %s;" % s("name.old"),
            "  var Q := ChangeFileExt(P, %s);" % s(".new"),
            "  Answer := UInt64(Cardinal(Length(Q))) shl 8;",
            "  Answer := Answer or UInt64(Ord(ExtractFileExt(Q) = %s));"
            % s(".new")]


def layer_rtl(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """Контракт стандартной библиотеки: она обязана вести себя как у Delphi."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, shape in enumerate(RTL_SHAPES):
        index = start + offset
        name = "dvl-rtllib-%s" % shape
        proc = "DvlRtlLib%05d" % index
        tag = "%05d" % index

        body = emit_rtl_case(e, shape, tag)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Answer: UInt64;")
        e.line("begin")
        e.line("  { %s }" % shape)
        e.line("  Answer := $FFFF;")
        for line in body:
            e.line(line)
        e.line("  DevilStep('%s');" % name)
        e.line("  { модели нет: контракт в том, что библиотека отвечает так же, "
               "как у Delphi }")
        e.line("  DevilNote('%s', Answer);" % name)
        e.line("  DevilCheckBool('%s-answered', Answer <> $FFFF);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="rtllib",
                                  detail={"shape": shape}))

    emit_runner(e, "RtlLib", calls)
    return records


# что производитель кладёт в модуль, а потребитель обязан прочитать так же
PPU_SHAPES = (
    "alias-width", "alias-signedness", "subrange-bounds", "enum-base-size",
    "set-size", "typed-const-precision", "typed-const-string",
    "record-layout", "packed-record-layout", "record-alignment",
    "class-field-offset", "class-virtual-index", "interface-guid",
    "overload-set", "default-parameter", "calling-convention",
    "generic-specialized-there", "generic-specialized-here",
    "inline-body-across", "const-expression-across", "helper-visible-across",
    "class-const-across", "published-property-across", "attribute-across",
)


def write_ppu_unit(out: Path) -> None:
    """Модуль-производитель: потребитель увидит только его PPU."""
    lines = ["unit devil_ppu_source;", "",
             "{$ifdef FPC}",
             "  {$mode delphiunicode}{$H+}",
             "  {$modeswitch advancedrecords}",
             "  {$modeswitch INLINEVARS}",
             "{$endif}", "",
             "interface", "",
             "uses",
             "  SysUtils;", "",
             "type",
             "  { псевдонимы: ширина и знак обязаны пережить границу }",
             "  TDvlPpuNarrow = type SmallInt;",
             "  TDvlPpuUnsigned = type Word;",
             "  TDvlPpuRange = 10..250;",
             "  TDvlPpuEnum = (dvlPpuA, dvlPpuB, dvlPpuC);",
             "  TDvlPpuSet = set of TDvlPpuEnum;", "",
             "  { layout: смещения полей и упаковка }",
             "  TDvlPpuRec = record",
             "    Head: Byte;",
             "    Wide: Int64;",
             "    Tail: Word;",
             "  end;",
             "  TDvlPpuPacked = packed record",
             "    Head: Byte;",
             "    Wide: Int64;",
             "    Tail: Word;",
             "  end;",
             "  {$ifdef FPC}{$push}{$endif}",
             "  {$A8}",
             "  TDvlPpuAligned = record",
             "    Head: Byte;",
             "    Wide: Int64;",
             "  end;",
             "  {$ifdef FPC}{$pop}{$endif}", "",
             "  { класс: смещение поля и место метода в таблице }",
             "  TDvlPpuBase = class",
             "  public",
             "    Slot: Integer;",
             "    Extra: Int64;",
             "    function Kind: Integer; virtual;",
             "    function Second: Integer; virtual;",
             "  end;",
             "",
             "  {$M+}",
             "  TDvlPpuPublished = class",
             "  private",
             "    FSlot: Integer;",
             "  published",
             "    property Slot: Integer read FSlot write FSlot;",
             "  end;",
             "  {$M-}", "",
             "  IDvlPpu = interface",
             "    ['{7A1D0000-0000-0000-0000-00000000000D}']",
             "    function Ask: Integer;",
             "  end;", "",
             "  { обобщение, специализируемое по обе стороны границы }",
             "  TDvlPpuBox<T> = record",
             "    Value: T;",
             "    function Width: Integer;",
             "  end;",
             "  TDvlPpuHere = TDvlPpuBox<SmallInt>;", "",
             "  TDvlPpuHelperHost = class",
             "  public",
             "    Payload: Integer;",
             "  end;",
             "  TDvlPpuHelper = class helper for TDvlPpuHelperHost",
             "  public",
             "    function Doubled: Integer;",
             "  end;", "",
             "  TDvlPpuWithConst = class",
             "  public",
             "    const Marker = 4242;",
             "  end;", "",
             "  DvlPpuMarkAttribute = class(TCustomAttribute)",
             "  public",
             "    Tag: Integer;",
             "    constructor Create(ATag: Integer);",
             "  end;", "",
             "  [DvlPpuMark(77)]",
             "  TDvlPpuMarked = class",
             "  end;", "",
             "const",
             "  { типизированные константы: точность и текст }",
             "  DvlPpuCurrency: Currency = 1.2345;",
             "  DvlPpuDouble: Double = 0.1;",
             "  DvlPpuText: string = 'ppu-text';",
             "  DvlPpuUntyped = 300;", "",
             "{ перегрузки: набор кандидатов обязан переехать целиком }",
             "function DvlPpuPick(const V: Integer): Integer; overload;",
             "function DvlPpuPick(const V: Int64): Integer; overload;",
             "function DvlPpuPick(const V: string): Integer; overload;", "",
             "{ значение по умолчанию видно только через модуль }",
             "function DvlPpuWithDefault(A: Integer; B: Integer = 7): Integer;",
             "{ соглашение вызова объявлено здесь, вызов будет там }",
             "function DvlPpuStd(A, B, C, D, E: Integer): Integer; stdcall;",
             "{ тело инлайна обязано доехать до потребителя }",
             "function DvlPpuInline(const V: Int64): Int64; inline;",
             "function DvlPpuMakeHere: TDvlPpuHere;", "",
             "implementation", "",
             "constructor DvlPpuMarkAttribute.Create(ATag: Integer);",
             "begin",
             "  inherited Create;",
             "  Tag := ATag;",
             "end;", "",
             "function TDvlPpuBase.Kind: Integer;",
             "begin",
             "  Result := 1;",
             "end;", "",
             "function TDvlPpuBase.Second: Integer;",
             "begin",
             "  Result := 2;",
             "end;", "",
             "function TDvlPpuBox<T>.Width: Integer;",
             "begin",
             "  Result := SizeOf(T);",
             "end;", "",
             "function TDvlPpuHelper.Doubled: Integer;",
             "begin",
             "  Result := Payload * 2;",
             "end;", "",
             "function DvlPpuPick(const V: Integer): Integer;",
             "begin",
             "  Result := 1;",
             "end;", "",
             "function DvlPpuPick(const V: Int64): Integer;",
             "begin",
             "  Result := 2;",
             "end;", "",
             "function DvlPpuPick(const V: string): Integer;",
             "begin",
             "  Result := 3;",
             "end;", "",
             "function DvlPpuWithDefault(A: Integer; B: Integer): Integer;",
             "begin",
             "  Result := A * 100 + B;",
             "end;", "",
             "function DvlPpuStd(A, B, C, D, E: Integer): Integer; stdcall;",
             "begin",
             "  Result := A + B * 2 + C * 3 + D * 4 + E * 5;",
             "end;", "",
             "function DvlPpuInline(const V: Int64): Int64;",
             "begin",
             "  Result := V;",
             "end;", "",
             "function DvlPpuMakeHere: TDvlPpuHere;",
             "begin",
             "  Result.Value := SmallInt(-32767);",
             "end;", "",
             "end."]
    (out / "devil_ppu_source.pas").write_text("\n".join(lines) + "\n",
                                              encoding="utf-8")


def emit_ppu_case(e: Emitter, shape: str, tag: str) -> list[str]:
    """Что потребитель видит через границу модуля."""
    if shape == "alias-width":
        return ["  var V: TDvlPpuNarrow := TDvlPpuNarrow(-32767);",
                "  Answer := UInt64(Cardinal(SizeOf(V))) shl 16;",
                "  Answer := Answer or UInt64(Word(V));"]
    if shape == "alias-signedness":
        return ["  var V: TDvlPpuUnsigned := TDvlPpuUnsigned($FFFF);",
                "  Answer := UInt64(Cardinal(SizeOf(V))) shl 16;",
                "  Answer := Answer or UInt64(Int64(V) and $FFFF);"]
    if shape == "subrange-bounds":
        return ["  Answer := UInt64(Cardinal(Low(TDvlPpuRange))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(High(TDvlPpuRange)));"]
    if shape == "enum-base-size":
        return ["  Answer := UInt64(Cardinal(SizeOf(TDvlPpuEnum))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(Ord(High(TDvlPpuEnum))));"]
    if shape == "set-size":
        return ["  var S: TDvlPpuSet := [dvlPpuA, dvlPpuC];",
                "  Answer := UInt64(Cardinal(SizeOf(S))) shl 16;",
                "  Answer := Answer or UInt64(Ord(dvlPpuC in S));"]
    if shape == "typed-const-precision":
        return ["  { у Currency четыре знака: округление обязано пережить PPU }",
                "  Answer := UInt64(Cardinal(Round(DvlPpuCurrency * 10000)));"]
    if shape == "typed-const-string":
        return ["  Answer := UInt64(Cardinal(Length(DvlPpuText))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(DvlPpuUntyped));"]
    if shape == "record-layout":
        return ["  var R: TDvlPpuRec;",
                "  Answer := UInt64(Cardinal(SizeOf(R))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(NativeUInt(@R.Wide) - "
                "NativeUInt(@R)));"]
    if shape == "packed-record-layout":
        return ["  var R: TDvlPpuPacked;",
                "  Answer := UInt64(Cardinal(SizeOf(R))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(NativeUInt(@R.Wide) - "
                "NativeUInt(@R)));"]
    if shape == "record-alignment":
        return ["  var R: TDvlPpuAligned;",
                "  Answer := UInt64(Cardinal(SizeOf(R))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(NativeUInt(@R.Wide) - "
                "NativeUInt(@R)));"]
    if shape == "class-field-offset":
        return ["  var Held := TDvlPpuBase.Create;",
                "  try",
                "    Held.Slot := 5;",
                "    Held.Extra := 9;",
                "    Answer := UInt64(Cardinal(Held.Slot)) shl 16;",
                "    Answer := Answer or UInt64(Cardinal(Held.Extra));",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "class-virtual-index":
        e.line("type")
        e.line("  TDvlPpuLeaf%s = class(TDvlPpuBase)" % tag)
        e.line("  public")
        e.line("    function Kind: Integer; override;")
        e.line("  end;")
        e.line()
        e.line("function TDvlPpuLeaf%s.Kind: Integer;" % tag)
        e.line("begin")
        e.line("  { перекрыт первый виртуальный метод; второй обязан остаться "
               "на своём месте в таблице }")
        e.line("  Result := 10 + inherited Kind;")
        e.line("end;")
        e.line()
        return ["  var Held: TDvlPpuBase := TDvlPpuLeaf%s.Create;" % tag,
                "  try",
                "    Answer := UInt64(Cardinal(Held.Kind)) shl 16;",
                "    Answer := Answer or UInt64(Cardinal(Held.Second));",
                "  finally",
                "    Held.Free;",
                "  end;"]
    if shape == "interface-guid":
        e.line("type")
        e.line("  TDvlPpuImpl%s = class(TInterfacedObject, IDvlPpu)" % tag)
        e.line("  public")
        e.line("    function Ask: Integer;")
        e.line("  end;")
        e.line()
        e.line("function TDvlPpuImpl%s.Ask: Integer;" % tag)
        e.line("begin")
        e.line("  Result := 7;")
        e.line("end;")
        e.line()
        return ["  var Obj: IDvlPpu := TDvlPpuImpl%s.Create;" % tag,
                "  var Other: IInterface := Obj;",
                "  var Back: IDvlPpu;",
                "  Answer := UInt64(Ord(Supports(Other, IDvlPpu, Back))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(Back.Ask));"]
    if shape == "overload-set":
        return ["  var Wide: Int64 := 7;",
                "  var Text: string := 'x';",
                "  Answer := UInt64(Cardinal(DvlPpuPick(Wide))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(DvlPpuPick(Text)));"]
    if shape == "default-parameter":
        return ["  Answer := UInt64(Cardinal(DvlPpuWithDefault(1))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(DvlPpuWithDefault(1, 3)));"]
    if shape == "calling-convention":
        return ["  Answer := UInt64(Cardinal(DvlPpuStd(1, 2, 3, 4, 5)));"]
    if shape == "generic-specialized-there":
        return ["  { специализация сделана в модуле-производителе }",
                "  var Box := DvlPpuMakeHere;",
                "  Answer := UInt64(Cardinal(Box.Width)) shl 16;",
                "  Answer := Answer or UInt64(Word(Box.Value));"]
    if shape == "generic-specialized-here":
        return ["  { то же обобщение, но специализировано на этой стороне }",
                "  var Box: TDvlPpuBox<SmallInt>;",
                "  Box.Value := SmallInt(-32767);",
                "  Answer := UInt64(Cardinal(Box.Width)) shl 16;",
                "  Answer := Answer or UInt64(Word(Box.Value));"]
    if shape == "inline-body-across":
        return ["  var V: Int64 := OpaqueI(-32767);",
                "  Answer := UInt64(Cardinal(Word(DvlPpuInline(V)))) shl 16;",
                "  Answer := Answer or UInt64(Cardinal(SizeOf(DvlPpuInline(V))));"]
    if shape == "const-expression-across":
        return ["  { нетипизированная константа из модуля в константном "
                "выражении этой стороны }",
                "  const Doubled = DvlPpuUntyped * 2;",
                "  Answer := UInt64(Cardinal(Doubled));"]
    if shape == "helper-visible-across":
        return ["  var Host := TDvlPpuHelperHost.Create;",
                "  try",
                "    Host.Payload := 21;",
                "    Answer := UInt64(Cardinal(Host.Doubled));",
                "  finally",
                "    Host.Free;",
                "  end;"]
    if shape == "class-const-across":
        return ["  Answer := UInt64(Cardinal(TDvlPpuWithConst.Marker));"]
    if shape == "published-property-across":
        return ["  var Ctx: TRttiContext := TRttiContext.Create;",
                "  var Count := 0;",
                "  for var P in Ctx.GetType(TDvlPpuPublished).GetProperties do",
                "    Inc(Count);",
                "  Answer := UInt64(Cardinal(Count));"]
    # attribute-across
    return ["  var Ctx: TRttiContext := TRttiContext.Create;",
            "  var Sum := 0;",
            "  for var A in Ctx.GetType(TDvlPpuMarked).GetAttributes do",
            "    If A is DvlPpuMarkAttribute then",
            "      Sum := Sum + DvlPpuMarkAttribute(A).Tag;",
            "  Answer := UInt64(Cardinal(Sum));"]


def layer_ppu(e: Emitter, rng: random.Random, count: int,
              start: int) -> list[CaseRecord]:
    """Что объявление несёт с собой через границу раздельной компиляции."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, shape in enumerate(PPU_SHAPES):
        index = start + offset
        name = "dvl-ppu-%s" % shape
        proc = "DvlPpu%05d" % index
        tag = "%05d" % index

        body = emit_ppu_case(e, shape, tag)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Answer: UInt64;")
        e.line("begin")
        e.line("  { %s: производитель знает, потребитель обязан узнать }"
               % shape)
        e.line("  Answer := $FFFFFFFF;")
        for line in body:
            e.line(line)
        e.line("  DevilStep('%s');" % name)
        e.line("  DevilNote('%s', Answer);" % name)
        e.line("  DevilCheckBool('%s-answered', Answer <> $FFFFFFFF);" % name)
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="ppu",
                                  detail={"shape": shape}))

    emit_runner(e, "Ppu", calls)
    return records


# формы, где важно не значение, а сколько раз и в каком составе сработали
# защищённые области
REGION_SHAPES = (
    "finally-in-loop", "finally-with-break", "finally-with-continue",
    "finally-with-exit", "nested-five-deep", "finally-around-inlined",
    "finally-around-inlined-managed", "except-then-finally",
    "reraise-through-finally", "exit-from-except", "finally-in-except",
    "loop-inside-try", "try-inside-loop-inside-try", "finally-after-raise",
    "dead-looking-region", "region-around-closure", "region-around-thread-join",
    "nested-loops-with-finally",
)


def emit_region_case(e: Emitter, shape: str, tag: str) -> tuple[list[str], int]:
    """Тело кейса и сколько раз тело finally обязано отработать."""
    if shape == "finally-in-loop":
        return (["  for var I := 1 to 5 do",
                 "  begin",
                 "    try",
                 "      Inc(Body);",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 5)
    if shape == "finally-with-break":
        return (["  for var I := 1 to 5 do",
                 "  begin",
                 "    try",
                 "      Inc(Body);",
                 "      If I = 3 then",
                 "        Break;",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 3)
    if shape == "finally-with-continue":
        return (["  for var I := 1 to 4 do",
                 "  begin",
                 "    try",
                 "      If I = 2 then",
                 "        Continue;",
                 "      Inc(Body);",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 4)
    if shape == "finally-with-exit":
        e.line("procedure DvlRegExit%s(var Guard, Body: Integer);" % tag)
        e.line("begin")
        e.line("  for var I := 1 to 5 do")
        e.line("  begin")
        e.line("    try")
        e.line("      Inc(Body);")
        e.line("      If I = 2 then")
        e.line("        Exit;")
        e.line("    finally")
        e.line("      Inc(Guard);")
        e.line("    end;")
        e.line("  end;")
        e.line("end;")
        e.line()
        return (["  DvlRegExit%s(Guard, Body);" % tag], 2)
    if shape == "nested-five-deep":
        lines = []
        for depth in range(5):
            lines.append("  " * (depth + 1) + "try")
        lines.append("  " * 6 + "Inc(Body);")
        for depth in range(4, -1, -1):
            lines.append("  " * (depth + 1) + "finally")
            lines.append("  " * (depth + 2) + "Inc(Guard);")
            lines.append("  " * (depth + 1) + "end;")
        return (lines, 5)
    if shape in ("finally-around-inlined", "finally-around-inlined-managed"):
        managed = shape.endswith("managed")
        e.line("function DvlRegStep%s(V: Integer): Integer; inline;" % tag)
        if managed:
            e.line("var")
            e.line("  Text: AnsiString;")
        e.line("begin")
        if managed:
            e.line("  { managed-временная внутри подставляемого тела: регион "
                   "меняется в момент подстановки }")
            e.line("  Text := Copy(AnsiString('guard'), 1, 5);")
            e.line("  Result := V + Length(Text) - 5;")
        else:
            e.line("  Result := V;")
        e.line("end;")
        e.line()
        return (["  for var I := 1 to 3 do",
                 "  begin",
                 "    try",
                 "      Inc(Body, DvlRegStep%s(1));" % tag,
                 "    finally",
                 "      Inc(Guard, DvlRegStep%s(1));" % tag,
                 "    end;",
                 "  end;"], 3)
    if shape == "except-then-finally":
        return (["  for var I := 1 to 3 do",
                 "  begin",
                 "    try",
                 "      try",
                 "        Inc(Body);",
                 "        raise Exception.Create('x');",
                 "      except",
                 "        Inc(Body);",
                 "      end;",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 3)
    if shape == "reraise-through-finally":
        return (["  try",
                 "    try",
                 "      try",
                 "        Inc(Body);",
                 "        raise Exception.Create('x');",
                 "      finally",
                 "        Inc(Guard);",
                 "      end;",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  except",
                 "    Inc(Body);",
                 "  end;"], 2)
    if shape == "exit-from-except":
        e.line("procedure DvlRegEscape%s(var Guard, Body: Integer);" % tag)
        e.line("begin")
        e.line("  try")
        e.line("    try")
        e.line("      Inc(Body);")
        e.line("      raise Exception.Create('x');")
        e.line("    except")
        e.line("      Exit;")
        e.line("    end;")
        e.line("  finally")
        e.line("    Inc(Guard);")
        e.line("  end;")
        e.line("end;")
        e.line()
        return (["  DvlRegEscape%s(Guard, Body);" % tag], 1)
    if shape == "finally-in-except":
        return (["  try",
                 "    Inc(Body);",
                 "    raise Exception.Create('x');",
                 "  except",
                 "    try",
                 "      Inc(Body);",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 1)
    if shape == "loop-inside-try":
        return (["  try",
                 "    for var I := 1 to 6 do",
                 "      Inc(Body);",
                 "  finally",
                 "    Inc(Guard);",
                 "  end;"], 1)
    if shape == "try-inside-loop-inside-try":
        return (["  try",
                 "    for var I := 1 to 4 do",
                 "    begin",
                 "      try",
                 "        Inc(Body);",
                 "      finally",
                 "        Inc(Guard);",
                 "      end;",
                 "    end;",
                 "  finally",
                 "    Inc(Guard);",
                 "  end;"], 5)
    if shape == "finally-after-raise":
        return (["  try",
                 "    try",
                 "      raise Exception.Create('x');",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  except",
                 "    Inc(Body);",
                 "  end;"], 1)
    if shape == "dead-looking-region":
        return (["  { тело выглядит неспособным бросить, но область обязана "
                 "остаться: доказательство мертвости здесь неверно }",
                 "  for var I := 1 to 3 do",
                 "  begin",
                 "    try",
                 "      Inc(Body);",
                 "      If OpaqueI(0) <> 0 then",
                 "        raise Exception.Create('never');",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 3)
    if shape == "region-around-closure":
        e.line("type")
        e.line("  TDvlRegStep%s = reference to procedure;" % tag)
        e.line()
        return (["  var Step: TDvlRegStep%s;" % tag,
                 "  Step :=",
                 "    procedure",
                 "    begin",
                 "      Inc(Body);",
                 "    end;",
                 "  for var I := 1 to 3 do",
                 "  begin",
                 "    try",
                 "      Step();",
                 "    finally",
                 "      Inc(Guard);",
                 "    end;",
                 "  end;"], 3)
    if shape == "region-around-thread-join":
        e.line("type")
        e.line("  TDvlRegWorker%s = class(TThread)" % tag)
        e.line("  public")
        e.line("    Seen: Integer;")
        e.line("    procedure Execute; override;")
        e.line("  end;")
        e.line()
        e.line("procedure TDvlRegWorker%s.Execute;" % tag)
        e.line("begin")
        e.line("  Seen := 1;")
        e.line("end;")
        e.line()
        return (["  var Worker := TDvlRegWorker%s.Create(True);" % tag,
                 "  try",
                 "    Worker.FreeOnTerminate := False;",
                 "    Worker.Start;",
                 "    Worker.WaitFor;",
                 "    Inc(Body, Worker.Seen);",
                 "  finally",
                 "    Inc(Guard);",
                 "    Worker.Free;",
                 "  end;"], 1)
    # nested-loops-with-finally
    return (["  for var I := 1 to 3 do",
             "    for var J := 1 to 2 do",
             "    begin",
             "      try",
             "        Inc(Body);",
             "      finally",
             "        Inc(Guard);",
             "      end;",
             "    end;"], 6)


def layer_region(e: Emitter, rng: random.Random, count: int,
                 start: int) -> list[CaseRecord]:
    """Сколько раз сработала защищённая область — число, заданное языком."""
    records: list[CaseRecord] = []
    calls: list[str] = []
    for offset, shape in enumerate(REGION_SHAPES):
        index = start + offset
        name = "dvl-region-%s" % shape
        proc = "DvlRegion%05d" % index
        tag = "%05d" % index

        body, expected = emit_region_case(e, shape, tag)
        e.line("procedure %s;" % proc)
        e.line("var")
        e.line("  Guard, Body: Integer;")
        e.line("begin")
        e.line("  { %s: тело finally обязано отработать ровно %d раз }"
               % (shape, expected))
        e.line("  Guard := 0;")
        e.line("  Body := 0;")
        for line in body:
            e.line(line)
        e.line("  DevilStep('%s');" % name)
        e.line("  DevilCheckU('%s-guard', UInt64(Cardinal(Guard)), %d);"
               % (name, expected))
        e.line("  DevilFeed(UInt64(Cardinal(Body)));")
        e.line("end;")
        e.line()

        calls.append(proc)
        records.append(CaseRecord(name=name, layer="region",
                                  detail={"shape": shape,
                                          "expected": expected}))

    emit_runner(e, "Region", calls)
    return records


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
{{ chains nest dozens of frames deep and each frame carries managed locals:
   the default stack is not the property under test, so it is raised }}
{{$ifdef FPC}}
  {{$M 268435456}}
{{$else}}
  {{$MAXSTACKSIZE 268435456}}
{{$endif}}
{{$Q-}}{{$R-}}

uses
{{$ifdef FPC}}
  {{ the build driver pins this unit and requires it first; Delphi has no
     equivalent and manages its own heap }}
  mormot.core.fpcx64mm,
  {{$ifdef UNIX}}cthreads,{{$endif}}
{{$endif}}
  SysUtils, Classes, Math, Variants, TypInfo, Rtti, Generics.Collections, devil_runtime{uses_extra};

{{$I devil_support.inc}}
{includes}

begin
  {{ Delphi Win64 masks every floating point exception by default while FPC
     leaves exInvalidOp unmasked; the forms under test must see one and the
     same environment on both. }}
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  WriteLn('DEVIL_LAYERS {layers}'{layers_extra});

{runs}
  {{ the instrument checks itself: the accumulator must have moved, and the
     number of feeds must be in the range the generator wrote }}
  WriteLn('DEVIL_FEEDS ', DevilFeedCount);
  WriteLn('DEVIL_STEPS ', DevilStepCount);
  If DevilFeedCount = 0 then
    DevilCheckU('devil-bloodstream-alive', 0, 1);
  {{ порядковый канал есть не в каждом наборе слоёв: требовать шагов
     безусловно значит краснеть там, где их нет по построению.  Сравнение
     числа шагов между сборками делает гейт, и оно работает всегда. }}
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
    "uni": layer_unicode,
    "exc": layer_exceptions,
    "init": layer_init,
    "opt": layer_optimizer,
    "call": layer_call,
    "inl": layer_inline,
    "intf": layer_interfaces,
    "dyn": layer_dynamic,
    "asm": layer_assembler,
    "io": layer_io,
    "decl": layer_declarations,
    "chain": layer_chain,
    "meta": layer_metamorphic,
    "weave": layer_weave,
    "matrix": layer_matrix,
    "composite": layer_composite,
    "genpath": layer_genpath,
    "narrowpath": layer_narrowpath,
    "pick": layer_pick,
    "scope": layer_scope,
    "lit": layer_lit,
    "capture": layer_capture,
    "attr": layer_attr,
    "deliver": layer_deliver,
    "load": layer_load,
    "rtllib": layer_rtl,
    "ppu": layer_ppu,
    "region": layer_region,
}

# Числовые слои держатся на голодном пайке специально.  Сверять результат
# арифметической операции легко, поэтому генератор сам собой сползает в
# бесконечные числовые формы, а всё остальное — время жизни, layout, раздельная
# компиляция, вердикт компиляции — остаётся непокрытым.  Дефект в арифметике мы
# уже поймали там, где он есть; расширение покрытия идёт в структурных слоях.
ARITHMETIC_LAYERS = ("expr", "unary", "fold", "cmp", "float", "i128")
ARITHMETIC_SHARE = 0.1

FPC_ONLY_LAYERS = {"i128", "load"}
LAYER_RUN_TEMPLATE = ("  DevilLayerBegin('%s');\n"
                      "  %s;\n"
                      "  DevilLayerEnd;")
FPC_ONLY_INCLUDE = "{$ifdef FPC}\n{$I devil_%s.inc}\n{$endif}"
FPC_ONLY_RUN = "{$ifdef FPC}\n  %s;\n{$endif}"

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
    "uni": "RunDevilUniLayer",
    "exc": "RunDevilExcLayer",
    "init": "RunDevilInitLayer",
    "opt": "RunDevilOptLayer",
    "call": "RunDevilCallLayer",
    "inl": "RunDevilInlLayer",
    "intf": "RunDevilIntfLayer",
    "dyn": "RunDevilDynLayer",
    "asm": "RunDevilAsmLayer",
    "io": "RunDevilIoLayer",
    "decl": "RunDevilDeclLayer",
    "chain": "RunDevilChainLayer",
    "meta": "RunDevilMetaLayer",
    "weave": "RunDevilWeaveLayer",
    "matrix": "RunDevilMatrixLayer",
    "composite": "RunDevilCompositeLayer",
    "genpath": "RunDevilGenpathLayer",
    "narrowpath": "RunDevilNarrowpathLayer",
    "pick": "RunDevilPickLayer",
    "scope": "RunDevilScopeLayer",
    "lit": "RunDevilLitLayer",
    "capture": "RunDevilCaptureLayer",
    "attr": "RunDevilAttrLayer",
    "deliver": "RunDevilDeliverLayer",
    "load": "RunDevilLoadLayer",
    "rtllib": "RunDevilRtlLibLayer",
    "ppu": "RunDevilPpuLayer",
    "region": "RunDevilRegionLayer",
}


def check_case_names(records: list[CaseRecord]) -> None:
    """A case name carries its layer, because the gate reads it from there.

    A case named after anything else is excluded from every cross-build
    comparison the gate makes: the divergence then survives only as a digest,
    with no case to point at.
    """
    stray = sorted({r.name for r in records
                    if not r.name.startswith("dvl-%s-" % r.layer)})
    if stray:
        raise SystemExit("case names do not carry their layer: %s"
                         % ", ".join(stray[:5]))


TYPE_DECL_RE = re.compile(r"^\s{2,4}(T|I|P|E)Dvl\w+\s*(<[^>]*>)?\s*=",
                          re.MULTILINE)


def check_unique_declarations(out: Path, selected: list[str]) -> None:
    """One program, one namespace: a name may be declared once."""
    seen: dict[str, str] = {}
    clashes: list[str] = []
    for layer in selected:
        path = out / ("devil_%s.inc" % layer)
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            match = TYPE_DECL_RE.match(line)
            if not match:
                continue
            name = line.strip().split("=", 1)[0].strip()
            name = name.split("<", 1)[0].strip()
            owner = seen.get(name)
            if owner and owner != layer:
                clashes.append("%s declared by both %s and %s"
                               % (name, owner, layer))
            seen[name] = owner or layer
    if clashes:
        raise SystemExit("name clash between layers:\n  "
                         + "\n  ".join(sorted(set(clashes))))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cases", type=int, default=400,
                        help="cases per layer")
    parser.add_argument("--layers", default="all")
    parser.add_argument("--shuffle-order", action="store_true",
                        help="emit the same forms in a different order: the "
                             "values must not depend on it")
    parser.add_argument("--out", type=Path,
                        default=ROOT / "results" / "runs" / "devil-generated")
    args = parser.parse_args()

    global OUTPUT_DIR
    OUTPUT_DIR = args.out
    selected = list(LAYERS) if args.layers == "all" else args.layers.split(",")
    if args.shuffle_order:
        random.Random(args.seed ^ 0x5A5A).shuffle(selected)
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    if out.resolve() != DEVIL.resolve():
        shutil.copy(DEVIL / "devil_runtime.pas", out / "devil_runtime.pas")
    (out / "devil_support.inc").write_text(SUPPORT, encoding="utf-8")

    records: list[CaseRecord] = []
    includes: list[str] = []
    runs: list[str] = []
    portable = [l for l in selected if l not in FPC_ONLY_LAYERS]
    fenced_names = ["{$ifdef FPC} + ',%s'{$endif}" % l
                    for l in selected if l in FPC_ONLY_LAYERS]
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
        # 128-bit integers are an extension of this compiler; Delphi has
        # no such type, and the arbiter must compile the same source
        if layer in FPC_ONLY_LAYERS:
            includes.append(FPC_ONLY_INCLUDE % layer)
            runs.append(FPC_ONLY_RUN % LAYER_RUNNERS[layer])
        else:
            includes.append(f"{{$I devil_{layer}.inc}}")
            # a subtotal per layer: the root digest says something broke, this
            # says which layer it happened in
            # a subtotal per layer: the root digest says something broke,
            # this says which layer it happened in
            runs.append(LAYER_RUN_TEMPLATE
                        % (layer, LAYER_RUNNERS[layer]))

    check_unique_declarations(out, selected)
    check_case_names(records)
    if "ppu" in selected:
        write_ppu_unit(out)
    if "opt" in selected:
        write_opt_effect_unit(out)
    if "deliver" in selected:
        write_provenance_unit(out)
    if "scope" in selected:
        write_scope_units(out)
    if "init" in selected:
        write_init_units(out)
        write_cycle_units(out)
    # the matrix layer crosses the same unit boundary as the chain does
    if ("chain" in selected or "matrix" in selected
            or "composite" in selected or "genpath" in selected
            or "narrowpath" in selected):
        write_chain_unit(out)
        write_chain_types_unit(out)
    (out / "devil.dpr").write_text(
        PROGRAM_TEMPLATE.format(
            seed=args.seed, layers=",".join(portable),
            layers_extra="".join(fenced_names),
            includes="\n".join(includes),
            runs="\n".join(runs),
            uses_extra="".join(
                ", " + u for u in (("devil_gen_unit",) if "unit" in selected
                                   else ())
                + ((INIT_UNITS[::-1] + ("devil_cycle_x", "devil_cycle_y"))
                   if "init" in selected else ())
                + (("devil_ppu_source",) if "ppu" in selected else ())
                + (("devil_opt_effect_unit",) if "opt" in selected else ())
                + (("devil_provenance",) if "deliver" in selected else ())
                + (("devil_scope_a", "devil_scope_b")
                   if "scope" in selected else ())
                + (("devil_chain_gates", "devil_chain_types")
                   if ("chain" in selected or "matrix" in selected
                       or "composite" in selected or "genpath" in selected
                       or "narrowpath" in selected)
                   else ()))),
        encoding="utf-8")
    # coverage of the passenger x transfer matrix: white spots are the honest
    # answer to "what else could be added", and they are closed on purpose
    covered = {(r.detail.get("passenger"), r.detail.get("transfer"))
               for r in records if r.layer == "matrix"}
    wanted = matrix_pairs()
    missing = [{"passenger": p, "transfer": t}
               for p, t in wanted if (p, t) not in covered]

    # the composite space is too large for one program: each seed takes a
    # slice, and the manifest says how big the space is and what this seed hit
    composite_seen = {(r.detail.get("passenger"), r.detail.get("first"),
                       r.detail.get("second"))
                      for r in records if r.layer == "composite"}
    composite_total = len([
        (p, a, b) for p in COMPOSITE_PASSENGERS
        for a in COMPOSITE_TRANSFERS for b in COMPOSITE_TRANSFERS
        if a != b and (p, a) not in COMPOSITE_SKIP
        and (p, b) not in COMPOSITE_SKIP])

    optimizer_effects = opt_effect_coverage(records)
    if "opt" in selected and (
            optimizer_effects["critical_triples_missing"]
            or optimizer_effects["pairs_missing"]
            or not optimizer_effects["exact_stale_global_anchor"]):
        raise SystemExit("optimizer effects matrix has uncovered contracts")

    manifest = {
        "schema": 2,
        "composite": {
            "triples_possible": composite_total,
            "triples_this_seed": len(composite_seen),
        },
        "matrix": {
            "pairs_possible": len(wanted),
            "pairs_covered": len(wanted) - len(missing),
            "pairs_missing": missing,
            "skipped_by_design": sorted(["%s/%s" % pair for pair in MATRIX_SKIP]),
        },
        "optimizer_effects": optimizer_effects,
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
