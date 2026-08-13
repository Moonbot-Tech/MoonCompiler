#!/usr/bin/env python3
"""Generate the committed, Delphi-oracled code-form expansion for Omni.

The generated Pascal is the product.  This script only makes the large static
matrix reproducible and reviewable.  Every case is a distinct source form;
runtime repetition is deliberately not counted as additional coverage.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OMNI = ROOT / "tests" / "mega" / "omni"
GENERATED = OMNI / "omni_generated_forms.inc"
PROBE = OMNI / "omni_generated_oracle.dpr"
ORACLE = OMNI / "omni_generated_oracle.json"
MANIFEST = OMNI / "omni_generated_manifest.json"


@dataclass(frozen=True)
class IntType:
    pascal: str
    slug: str
    bits: int
    signed: bool
    low: int
    high: int

    def literal(self, value: int) -> str:
        if value < 0:
            return f"{self.pascal}({value})"
        if value > 0x7FFFFFFF:
            digits = max(1, (self.bits + 3) // 4)
            return f"{self.pascal}(${value:0{digits}X})"
        return f"{self.pascal}({value})"

    def opaque(self, expression: str) -> str:
        if self.signed:
            return f"{self.pascal}(OpaqueI(Int64({expression})))"
        return f"{self.pascal}(OpaqueU(UInt64({expression})))"


TYPES = [
    IntType("ShortInt", "i8", 8, True, -128, 127),
    IntType("Byte", "u8", 8, False, 0, 255),
    IntType("SmallInt", "i16", 16, True, -32768, 32767),
    IntType("Word", "u16", 16, False, 0, 65535),
    IntType("Integer", "i32", 32, True, -2147483648, 2147483647),
    IntType("Cardinal", "u32", 32, False, 0, 4294967295),
    IntType("Int64", "i64", 64, True, -9223372036854775808, 9223372036854775807),
    IntType("UInt64", "u64", 64, False, 0, 18446744073709551615),
]


OP_SLUG = {
    "+": "add",
    "-": "sub",
    "*": "mul",
    "div": "div",
    "mod": "mod",
    "and": "and",
    "or": "or",
    "xor": "xor",
}


class Emitter:
    def __init__(self, oracle: dict[str, str]):
        self.lines: list[str] = []
        self.oracle = oracle
        self.names: list[str] = []

    def line(self, value: str = "") -> None:
        self.lines.append(value)

    def expected(self, name: str) -> str:
        self.names.append(name)
        return self.oracle.get(name, "0000000000000000")

    def check(
        self,
        name: str,
        expression: str,
        indent: str = "  ",
        expected_value: int | None = None,
    ) -> None:
        expected = self.expected(name)
        if expected_value is not None:
            expected = f"{expected_value & 0xFFFFFFFFFFFFFFFF:016X}"
        self.line(
            f"{indent}GeneratedCheckU('{name}', UInt64({expression}), "
            f"UInt64(${expected}));"
        )


def cast_int(value: int, t: IntType) -> int:
    value &= (1 << t.bits) - 1
    if t.signed and value >= (1 << (t.bits - 1)):
        value -= 1 << t.bits
    return value


def as_u64(value: int) -> int:
    return value & 0xFFFFFFFFFFFFFFFF


def boundary_pairs(t: IntType) -> list[tuple[int, int]]:
    low = t.low
    high = t.high
    pairs = [
        (0, 0), (0, 1), (1, 0), (1, 1), (2, 3), (3, 2),
        (high, 0), (high, 1), (high - 1, 2), (high // 2, 3),
    ]
    if t.signed:
        pairs += [
            (-1, 0), (-1, 1), (-2, 3), (-3, 2),
            (low, 0), (low, 1), (low + 1, 2), (low // 2, -3),
            (high, -1), (1, -1),
        ]
    else:
        pairs += [(high // 3, 7), (high // 5, 11), (7, high // 3)]
    return pairs


def sample_values(t: IntType) -> list[int]:
    values = [0, 1, 2, t.high, t.high - 1]
    if t.signed:
        values += [-1, -2, t.low, t.low + 1]
    else:
        values += [t.high // 2, t.high // 3]
    return list(dict.fromkeys(values))


def folded_result_fits(t: IntType, op: str, a: int, b: int) -> bool:
    if op == "+":
        value = a + b
    elif op == "-":
        value = a - b
    elif op == "*":
        value = a * b
    elif op == "div":
        value = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            value = -value
    elif op == "mod":
        quotient = abs(a) // abs(b)
        if (a < 0) != (b < 0):
            quotient = -quotient
        value = a - quotient * b
    else:
        mask = (1 << t.bits) - 1
        left = a & mask
        right = b & mask
        if op == "and":
            value = left & right
        elif op == "or":
            value = left | right
        else:
            value = left ^ right
        if t.signed and value >= (1 << (t.bits - 1)):
            value -= 1 << t.bits
    return t.low <= value <= t.high


def emit_integer_types(e: Emitter) -> None:
    e.line("type")
    for t in TYPES:
        e.line(f"  TGenPair_{t.slug} = record")
        e.line(f"    A, B: {t.pascal};")
        e.line("  end;")
    e.line()
    for index, t in enumerate(TYPES, start=1):
        e.line(f"function GenKind(Value: {t.pascal}): Byte; overload;")
        e.line("begin")
        e.line(f"  Result := {index};")
        e.line("end;")
        e.line()


def emit_integer_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    contexts = ("local", "record", "array", "pointer")
    operators = ("+", "-", "*", "div", "mod", "and", "or", "xor")
    case_id = 0
    for t in TYPES:
        for op in operators:
            for pair_index, (a, b) in enumerate(boundary_pairs(t)):
                if op in ("div", "mod") and b == 0:
                    continue
                if op in ("div", "mod") and t.signed and a == t.low and b == -1:
                    continue
                case_id += 1
                proc = f"GenIntForm{case_id:05d}"
                calls.append(proc)
                context = contexts[(pair_index + operators.index(op)) % len(contexts)]
                if context == "local":
                    left, right = "A", "B"
                elif context == "record":
                    left, right = "Rec.A", "Rec.B"
                elif context == "array":
                    left, right = "Values[0]", "Values[1]"
                else:
                    left, right = "PA^", "PB^"
                runtime = f"{t.pascal}({t.opaque(left)} {op} {t.opaque(right)})"
                folded = (
                    f"{t.pascal}({t.literal(a)} {op} {t.literal(b)})"
                )
                e.line(f"procedure {proc};")
                e.line("var")
                e.line(f"  A, B, Value: {t.pascal};")
                if context == "record":
                    e.line(f"  Rec: TGenPair_{t.slug};")
                elif context == "array":
                    e.line(f"  Values: array[0..1] of {t.pascal};")
                elif context == "pointer":
                    e.line(f"  PA, PB: ^{t.pascal};")
                e.line("begin")
                e.line(f"  A := {t.literal(a)};")
                e.line(f"  B := {t.literal(b)};")
                if context == "record":
                    e.line("  Rec.A := A;")
                    e.line("  Rec.B := B;")
                elif context == "array":
                    e.line("  Values[0] := A;")
                    e.line("  Values[1] := B;")
                elif context == "pointer":
                    e.line("  PA := @A;")
                    e.line("  PB := @B;")
                e.line(f"  Value := {runtime};")
                base = f"gen-int-{t.slug}-{OP_SLUG[op]}-{case_id:05d}"
                e.check(base + "-runtime", "Value")
                if folded_result_fits(t, op, a, b):
                    e.line(f"  Value := {folded};")
                    e.check(base + "-folded", "Value")
                e.line("end;")
                e.line()
    return calls


def emit_promotion_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    operators = ("+", "-", "*", "div", "mod", "and", "or", "xor")
    case_id = 0
    for left_type in TYPES:
        for right_type in TYPES:
            for op in operators:
                case_id += 1
                proc = f"GenPromotionForm{case_id:05d}"
                calls.append(proc)
                left_value = 5
                right_value = 2
                left = left_type.opaque("A")
                right = right_type.opaque("B")
                e.line(f"procedure {proc};")
                e.line("var")
                e.line(f"  A: {left_type.pascal};")
                e.line(f"  B: {right_type.pascal};")
                e.line("  K: Byte;")
                e.line("begin")
                e.line(f"  A := {left_type.literal(left_value)};")
                e.line(f"  B := {right_type.literal(right_value)};")
                e.line(f"  K := GenKind({left} {op} {right});")
                base = (
                    f"gen-promote-{left_type.slug}-{right_type.slug}-"
                    f"{OP_SLUG[op]}"
                )
                e.check(base + "-runtime", "K")
                e.line(
                    f"  K := GenKind({left_type.literal(left_value)} {op} "
                    f"{right_type.literal(right_value)});"
                )
                e.check(base + "-folded", "K")
                e.line("end;")
                e.line()
    return calls


def emit_mixed_value_forms(e: Emitter) -> list[str]:
    """Exercise mixed-width expressions by value, not just overload type."""
    calls: list[str] = []
    operators = ("+", "-", "*", "div", "mod", "and", "or", "xor")
    comparisons = ("=", "<>", "<", "<=", ">", ">=")
    case_id = 0
    for left_index, left_type in enumerate(TYPES):
        for right_index, right_type in enumerate(TYPES):
            left_values = sample_values(left_type)
            right_values = sample_values(right_type)
            pairs = [
                (0, 0),
                (1, 1),
                (left_values[-1], right_values[1]),
                (left_values[-1], right_values[-1]),
                (left_values[-2], right_values[1]),
                (left_values[3], right_values[4]),
                (left_values[(left_index + right_index) % len(left_values)],
                 right_values[(left_index * 3 + right_index) % len(right_values)]),
            ]
            pairs = list(dict.fromkeys(pairs))
            for op in operators:
                for pair_index, (a, b) in enumerate(pairs):
                    if op in ("div", "mod") and b == 0:
                        continue
                    if (
                        op in ("div", "mod")
                        and left_type.signed
                        and a == left_type.low
                        and b == -1
                    ):
                        continue
                    case_id += 1
                    proc = f"GenMixedValueForm{case_id:05d}"
                    calls.append(proc)
                    e.line(f"procedure {proc};")
                    e.line("var")
                    e.line(f"  A: {left_type.pascal};")
                    e.line(f"  B: {right_type.pascal};")
                    e.line("  Value: UInt64;")
                    e.line("begin")
                    e.line(f"  A := {left_type.literal(a)};")
                    e.line(f"  B := {right_type.literal(b)};")
                    e.line(
                        f"  Value := UInt64({left_type.opaque('A')} {op} "
                        f"{right_type.opaque('B')});"
                    )
                    name = (
                        f"gen-mixed-{left_type.slug}-{right_type.slug}-"
                        f"{OP_SLUG[op]}-p{pair_index}-{case_id:05d}"
                    )
                    e.check(name + "-runtime", "Value")
                    e.line("end;")
                    e.line()

            for cmp_index, op in enumerate(comparisons):
                for pair_index, (a, b) in enumerate(pairs):
                    expected_compare = int({
                        "=": a == b,
                        "<>": a != b,
                        "<": a < b,
                        "<=": a <= b,
                        ">": a > b,
                        ">=": a >= b,
                    }[op])
                    case_id += 1
                    proc = f"GenMixedCompareForm{case_id:05d}"
                    calls.append(proc)
                    e.line(f"procedure {proc};")
                    e.line("var")
                    e.line(f"  A: {left_type.pascal};")
                    e.line(f"  B: {right_type.pascal};")
                    e.line("  Value: Byte;")
                    e.line("begin")
                    e.line(f"  A := {left_type.literal(a)};")
                    e.line(f"  B := {right_type.literal(b)};")
                    e.line(
                        f"  Value := Ord({left_type.opaque('A')} {op} "
                        f"{right_type.opaque('B')});"
                    )
                    name = (
                        f"gen-compare-{left_type.slug}-{right_type.slug}-"
                        f"c{cmp_index}-p{pair_index}-{case_id:05d}"
                    )
                    e.check(
                        name + "-runtime",
                        "Value",
                        expected_value=expected_compare,
                    )
                    e.line(
                        f"  Value := Ord({left_type.literal(a)} {op} "
                        f"{right_type.literal(b)});"
                    )
                    e.check(
                        name + "-folded",
                        "Value",
                        expected_value=expected_compare,
                    )
                    e.line("end;")
                    e.line()
    return calls


def emit_shift_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    case_id = 0
    for t in TYPES:
        values = sample_values(t)
        counts = sorted({0, 1, max(0, t.bits - 1), t.bits, t.bits + 1, 63})
        for value_index, value in enumerate(values):
            for count in counts:
                for op in ("shl", "shr"):
                    case_id += 1
                    proc = f"GenShiftForm{case_id:04d}"
                    calls.append(proc)
                    e.line(f"procedure {proc};")
                    e.line("var")
                    e.line(f"  A, Value: {t.pascal};")
                    e.line("  Count: Byte;")
                    e.line("begin")
                    e.line(f"  A := {t.literal(value)};")
                    e.line(f"  Count := {count};")
                    e.line(
                        f"  Value := {t.pascal}({t.opaque('A')} {op} "
                        "Byte(OpaqueU(Count)));"
                    )
                    name = (
                        f"gen-shift-{t.slug}-{op}-{value_index:02d}-c{count:02d}"
                    )
                    e.check(name + "-runtime", "Value")
                    e.line(
                        f"  Value := {t.pascal}({t.literal(value)} {op} {count});"
                    )
                    e.check(name + "-folded", "Value")
                    e.line("end;")
                    e.line()
    return calls


def loop_cases(t: IntType) -> list[tuple[int, int]]:
    cases = [(0, 0), (0, 1), (1, 1), (1, 0), (2, 5), (5, 2)]
    if t.pascal == "Byte":
        cases += [(0, 255), (254, 255), (255, 255), (255, 0)]
    elif t.signed:
        cases += [(-1, 1), (1, -1), (t.low, t.low), (t.high, t.high)]
    else:
        cases += [(t.high, t.high), (t.high - 1, t.high)]
    return cases


def emit_loop_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    case_id = 0
    for t in TYPES:
        for low, high in loop_cases(t):
            for direction in ("to", "downto"):
                for bound_form in ("runtime", "folded"):
                    case_id += 1
                    proc = f"GenLoopForm{case_id:04d}"
                    calls.append(proc)
                    e.line(f"procedure {proc};")
                    e.line("var")
                    e.line(f"  K, LowBound, HighBound: {t.pascal};")
                    e.line("  Count, Sum: Int64;")
                    e.line("begin")
                    e.line(f"  LowBound := {t.literal(low)};")
                    e.line(f"  HighBound := {t.literal(high)};")
                    e.line("  Count := 0;")
                    e.line("  Sum := 0;")
                    if bound_form == "runtime":
                        lo_expr = t.opaque("LowBound")
                        hi_expr = t.opaque("HighBound")
                    else:
                        lo_expr = t.literal(low)
                        hi_expr = t.literal(high)
                    e.line(f"  for K := {lo_expr} {direction} {hi_expr} do")
                    e.line("  begin")
                    e.line("    Inc(Count);")
                    e.line("    Sum := Sum + Int64(K);")
                    e.line("  end;")
                    base = (
                        f"gen-loop-{t.slug}-{direction}-{bound_form}-{case_id:04d}"
                    )
                    e.check(base + "-count", "Count")
                    e.check(base + "-sum", "Sum")
                    e.line("end;")
                    e.line()
    return calls


def emit_alias_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    for fields in range(1, 13):
        e.line(f"type TGenAliasRec{fields} = record")
        for field in range(fields):
            e.line(f"  F{field}: Int64;")
        e.line("end;")
        e.line(f"var GenAliasRec{fields}: TGenAliasRec{fields};")
        e.line()
        targets = sorted({0, fields // 2, fields - 1})
        for target in targets:
            for helper_kind in ("plain", "inline"):
                suffix = f"{fields}_{target}_{helper_kind}"
                helper = f"GenAliasMutate_{suffix}"
                e.line(f"procedure {helper};" + (" inline;" if helper_kind == "inline" else ""))
                e.line("begin")
                e.line(f"  Inc(GenAliasRec{fields}.F{target}, 5);")
                e.line("end;")
                e.line()
                for mode in ("value", "var"):
                    func = f"GenAliasRead_{suffix}_{mode}"
                    if mode == "value":
                        param = f"R: TGenAliasRec{fields}"
                    else:
                        param = f"{mode} R: TGenAliasRec{fields}"
                    e.line(f"function {func}({param}): Int64;")
                    if helper_kind == "plain":
                        e.line("{$ifdef FPC}noinline;{$endif}")
                    e.line("begin")
                    e.line(f"  Result := R.F{target};")
                    e.line(f"  {helper};")
                    e.line(f"  Result := Result * 1000 + R.F{target};")
                    e.line("end;")
                    e.line()
                    proc = f"Run_{func}"
                    calls.append(proc)
                    e.line(f"procedure {proc};")
                    e.line("begin")
                    for field in range(fields):
                        e.line(f"  GenAliasRec{fields}.F{field} := {field + 7};")
                    name = f"gen-alias-r{fields}-f{target}-{helper_kind}-{mode}"
                    initial = target + 7
                    expected = initial * 1000 + initial
                    if mode == "var":
                        expected += 5
                    e.check(
                        name,
                        f"{func}(GenAliasRec{fields})",
                        expected_value=expected,
                    )
                    e.line("end;")
                    e.line()
    return calls


def emit_state_machine_forms(e: Emitter) -> list[str]:
    """Emit deterministic, model-oracled chains across storage and call forms."""
    calls: list[str] = []
    helper_kinds = ("inline", "plain", "var")
    storage_kinds = ("local", "record", "array", "pointer")

    for type_index, t in enumerate(TYPES):
        mask = (1 << t.bits) - 1
        e.line(f"type TGenStateRec_{t.slug} = record")
        e.line(f"  Value: {t.pascal};")
        e.line("  Guard: UInt64;")
        e.line("end;")
        e.line()

        inline_helper = f"GenStateInline_{t.slug}"
        plain_helper = f"GenStatePlain_{t.slug}"
        var_helper = f"GenStateVar_{t.slug}"
        expression = (
            f"{t.pascal}(((UInt64(A) xor (Salt * UInt64($9E3779B97F4A7C15))) "
            f"+ UInt64($D1B54A32D192ED03)) and UInt64(${mask:016X}))"
        )
        e.line(
            f"function {inline_helper}(A: {t.pascal}; Salt: UInt64): "
            f"{t.pascal}; inline;"
        )
        e.line("begin")
        e.line(f"  Result := {expression};")
        e.line("end;")
        e.line()
        e.line(
            f"function {plain_helper}(A: {t.pascal}; Salt: UInt64): "
            f"{t.pascal};"
        )
        e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("begin")
        e.line(f"  Result := {expression};")
        e.line("end;")
        e.line()
        e.line(
            f"procedure {var_helper}(var A: {t.pascal}; Salt: UInt64); inline;"
        )
        e.line("begin")
        e.line(f"  A := {expression};")
        e.line("end;")
        e.line()

        for case_index in range(24):
            storage = storage_kinds[case_index % len(storage_kinds)]
            helper_kind = helper_kinds[(case_index // len(storage_kinds)) % 3]
            proc = f"GenStateForm_{t.slug}_{case_index:02d}"
            calls.append(proc)
            e.line(f"procedure {proc};")
            e.line("var")
            e.line(f"  Value: {t.pascal};")
            e.line(f"  Values: array[0..2] of {t.pascal};")
            e.line(f"  Rec: TGenStateRec_{t.slug};")
            e.line(f"  P: ^{t.pascal};")
            e.line("  Guard: UInt64;")
            e.line("begin")
            seed = (
                0xA5A5A5A5A5A5A5A5
                ^ (type_index * 0x1111111111111111)
                ^ (case_index * 0x0102040810204081)
            ) & 0xFFFFFFFFFFFFFFFF
            value = cast_int(seed, t)
            e.line(f"  Value := {t.pascal}(OpaqueU(UInt64(${seed:016X})));" )
            e.line(f"  Values[0] := {t.pascal}($00);")
            e.line(f"  Values[1] := Value;")
            e.line(f"  Values[2] := {t.pascal}($00);")
            e.line("  Rec.Value := Value;")
            e.line("  Rec.Guard := UInt64($0123456789ABCDEF);")
            if storage == "local":
                target = "Value"
            elif storage == "record":
                target = "Rec.Value"
            elif storage == "array":
                target = "Values[1]"
            else:
                e.line("  P := @Value;")
                target = "P^"

            for step in range(1, 13):
                salt = (
                    (case_index + 1) * 131
                    + step * 17
                    + type_index * 29
                ) & 0xFFFF
                mixed = (
                    (as_u64(value) ^ ((salt * 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF))
                    + 0xD1B54A32D192ED03
                ) & 0xFFFFFFFFFFFFFFFF
                value = cast_int(mixed & mask, t)
                if helper_kind == "inline":
                    e.line(
                        f"  {target} := {inline_helper}({target}, UInt64({salt}));"
                    )
                elif helper_kind == "plain":
                    e.line(
                        f"  {target} := {plain_helper}({target}, UInt64({salt}));"
                    )
                else:
                    e.line(f"  {var_helper}({target}, UInt64({salt}));")

                if step in (1, 4, 8, 12):
                    name = (
                        f"gen-state-{t.slug}-{storage}-{helper_kind}-"
                        f"{case_index:02d}-s{step:02d}"
                    )
                    e.check(
                        name,
                        target,
                        expected_value=as_u64(value),
                    )

            if storage == "record":
                e.check(
                    f"gen-state-{t.slug}-{storage}-{helper_kind}-{case_index:02d}-guard",
                    "Rec.Guard",
                    expected_value=0x0123456789ABCDEF,
                )
            elif storage == "array":
                e.check(
                    f"gen-state-{t.slug}-{storage}-{helper_kind}-{case_index:02d}-before",
                    "Values[0]",
                    expected_value=0,
                )
                e.check(
                    f"gen-state-{t.slug}-{storage}-{helper_kind}-{case_index:02d}-after",
                    "Values[2]",
                    expected_value=0,
                )
            e.line("  Guard := UInt64(Rec.Guard xor UInt64($0123456789ABCDEF));")
            e.check(
                f"gen-state-{t.slug}-{storage}-{helper_kind}-{case_index:02d}-local-guard",
                "Guard",
                expected_value=0,
            )
            e.line("end;")
            e.line()
    return calls


def emit_record_abi_forms(e: Emitter) -> list[str]:
    calls: list[str] = []
    for fields in range(1, 17):
        e.line(f"type TGenAbiRec{fields} = record")
        for field in range(fields):
            field_type = ("Byte", "Integer", "Int64", "Cardinal")[field % 4]
            e.line(f"  F{field}: {field_type};")
        e.line("end;")
        e.line()
        maker = f"GenMakeAbiRec{fields}"
        e.line(f"function {maker}(Seed: Integer): TGenAbiRec{fields};")
        e.line("begin")
        for field in range(fields):
            field_type = ("Byte", "Integer", "Int64", "Cardinal")[field % 4]
            e.line(f"  Result.F{field} := {field_type}(Seed + {field * 17 + 3});")
        e.line("end;")
        e.line()
        hasher = f"GenHashAbiRec{fields}"
        e.line(f"function {hasher}(const R: TGenAbiRec{fields}): UInt64;")
        e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("begin")
        e.line("  Result := UInt64($CBF29CE484222325);")
        for field in range(fields):
            e.line(f"  Result := (Result xor UInt64(R.F{field})) * UInt64($100000001B3);")
        e.line("end;")
        e.line()
        proc = f"GenAbiReturnForm{fields}"
        calls.append(proc)
        e.line(f"procedure {proc};")
        e.line("var")
        e.line(f"  R: TGenAbiRec{fields};")
        e.line("begin")
        e.line(f"  R := {maker}(23);")
        e.check(f"gen-abi-return-r{fields}", f"{hasher}(R)")
        e.line("end;")
        e.line()

    scalar_types = ("Byte", "Integer", "Int64", "Cardinal")
    for count in range(1, 17):
        params: list[str] = []
        values: list[str] = []
        body: list[str] = []
        for index in range(count):
            t = scalar_types[index % len(scalar_types)]
            params.append(f"A{index}: {t}")
            values.append(f"{t}({index * 19 + 5})")
            body.append(
                f"  Result := (Result xor UInt64(A{index})) * UInt64($100000001B3);"
            )
        func = f"GenAbiParams{count}"
        e.line(f"function {func}({'; '.join(params)}): UInt64;")
        e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("begin")
        e.line("  Result := UInt64($CBF29CE484222325);")
        for line in body:
            e.line(line)
        e.line("end;")
        e.line()
        proc = f"GenAbiParamForm{count}"
        calls.append(proc)
        e.line(f"procedure {proc};")
        e.line("begin")
        e.check(f"gen-abi-params-{count}", f"{func}({', '.join(values)})")
        e.line("end;")
        e.line()
    return calls


def emit_abi_cross_forms(e: Emitter) -> list[str]:
    """Cross record returns, by-value forwarding and mixed Win64 arguments."""
    calls: list[str] = []
    for case_index in range(64):
        packed = (case_index % 2) == 0
        tail_high = case_index % 23
        type_name = f"TGenAbiCross{case_index:02d}"
        e.line(f"type {type_name} = " + ("packed record" if packed else "record"))
        e.line("  Lead: Byte;")
        e.line("  Wide: UInt64;")
        e.line("  Narrow: Word;")
        e.line("  Signed: Integer;")
        e.line("  RealValue: Double;")
        e.line(f"  Tail: array[0..{tail_high}] of Byte;")
        e.line("end;")
        e.line()

        maker = f"GenAbiCrossMake{case_index:02d}"
        e.line(
            f"function {maker}(A0: Byte; A1: Double; A2: UInt64; "
            f"A3: Word; A4: Integer; A5: Int64): {type_name};"
        )
        e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("var")
        e.line("  K: Integer;")
        e.line("begin")
        e.line("  Result.Lead := Byte(A0 + Byte(A5));")
        e.line("  Result.Wide := A2 xor UInt64(A5);")
        e.line("  Result.Narrow := Word(A3 + Word(A4));")
        e.line("  Result.Signed := A4 - Integer(A0);")
        e.line("  Result.RealValue := A1 + 0.25;")
        e.line("  for K := 0 to High(Result.Tail) do")
        e.line("    Result.Tail[K] := Byte(A0 + K * 7 + A3);")
        e.line("end;")
        e.line()

        forward = f"GenAbiCrossForward{case_index:02d}"
        e.line(
            f"function {forward}(R: {type_name}; Salt: Byte): {type_name};"
        )
        if case_index % 3 == 0:
            e.line("inline;")
        else:
            e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("begin")
        e.line("  Result := R;")
        e.line("  Result.Lead := Byte(Result.Lead xor Salt);")
        e.line("  Result.Wide := Result.Wide + UInt64(Salt);")
        e.line("  Result.Signed := Result.Signed - Integer(Salt);")
        e.line("  Result.Tail[High(Result.Tail)] :=")
        e.line("    Byte(Result.Tail[High(Result.Tail)] + Salt);")
        e.line("end;")
        e.line()

        consume = f"GenAbiCrossHash{case_index:02d}"
        e.line(f"function {consume}(const R: {type_name}): UInt64;")
        e.line("{$ifdef FPC}noinline;{$endif}")
        e.line("var")
        e.line("  K: Integer;")
        e.line("  RealBits: UInt64;")
        e.line("begin")
        e.line("  Move(R.RealValue, RealBits, SizeOf(RealBits));")
        e.line("  Result := UInt64($CBF29CE484222325);")
        e.line("  Result := (Result xor R.Lead) * UInt64($100000001B3);")
        e.line("  Result := (Result xor R.Wide) * UInt64($100000001B3);")
        e.line("  Result := (Result xor R.Narrow) * UInt64($100000001B3);")
        e.line("  Result := (Result xor UInt64(R.Signed)) * UInt64($100000001B3);")
        e.line("  Result := (Result xor RealBits) * UInt64($100000001B3);")
        e.line("  for K := 0 to High(R.Tail) do")
        e.line("    Result := (Result xor R.Tail[K]) * UInt64($100000001B3);")
        e.line("end;")
        e.line()

        proc = f"GenAbiCrossForm{case_index:02d}"
        calls.append(proc)
        seed = case_index * 13 + 7
        lead = (seed * 3 + 5) & 0xFF
        real = (seed % 17) + 0.5
        wide = (0xFEDCBA9876543210 ^ (seed * 0x0101010101010101)) & 0xFFFFFFFFFFFFFFFF
        narrow = (seed * 257 + 11) & 0xFFFF
        signed = seed * 100003 - 700000
        signed64 = seed * 1000000007 - 3000000000
        salt = (case_index * 11 + 3) & 0xFF
        e.line(f"procedure {proc};")
        e.line("var")
        e.line(f"  R: {type_name};")
        e.line("begin")
        e.line(
            f"  R := {forward}({maker}(Byte({lead}), {real:.1f}, "
            f"UInt64(${wide:016X}), Word({narrow}), Integer({signed}), "
            f"Int64({signed64})), Byte({salt}));"
        )
        prefix = f"gen-abi-cross-{case_index:02d}"
        e.check(prefix + "-lead", "R.Lead")
        e.check(prefix + "-wide", "R.Wide")
        e.check(prefix + "-narrow", "R.Narrow")
        e.check(prefix + "-signed", "R.Signed")
        e.check(prefix + "-real", "Round(R.RealValue * 4)")
        e.check(prefix + "-tail-first", "R.Tail[0]")
        e.check(prefix + "-tail-last", "R.Tail[High(R.Tail)]")
        e.check(prefix + "-hash", f"{consume}(R)")
        e.line("end;")
        e.line()
    return calls


def emit_inline_var_forms(e: Emitter) -> list[str]:
    form_calls: list[str] = []
    e.line("{$ifdef HAS_INLINEVAR}")
    for case_index in range(128):
        proc = f"GenInlineVarForm{case_index:03d}"
        form_calls.append(proc)
        seed = case_index * 37 - 1700
        byte_value = (case_index * 19 + 11) & 0xFF
        wide_value = (
            0x123456789ABCDEF0 ^ (case_index * 0x0102040810204081)
        ) & 0xFFFFFFFFFFFFFFFF
        delta = (case_index % 9) - 4
        expected_a = seed + byte_value
        expected_wide = (wide_value ^ (byte_value << (case_index % 8))) & 0xFFFFFFFFFFFFFFFF
        if case_index % 2 == 0:
            expected_a += delta * 3
        else:
            expected_a -= delta * 5
        e.line(f"procedure {proc};")
        e.line("begin")
        e.line(f"  var A := Integer(OpaqueI({seed}));")
        e.line(f"  var B: Byte := Byte(OpaqueU({byte_value}));")
        e.line(f"  var Wide := UInt64(OpaqueU(UInt64(${wide_value:016X})));" )
        e.line("  var P: PInteger := @A;")
        e.line("  P^ := P^ + Integer(B);")
        e.line(
            f"  Wide := Wide xor (UInt64(B) shl {case_index % 8});"
        )
        if case_index % 2 == 0:
            e.line("  begin")
            e.line(f"    var Delta := Integer({delta});")
            e.line("    P^ := P^ + Delta * 3;")
            e.line("  end;")
        else:
            e.line("  if B >= 0 then")
            e.line("  begin")
            e.line(f"    var Delta: Integer := {delta};")
            e.line("    P^ := P^ - Delta * 5;")
            e.line("  end;")
        prefix = f"gen-inlinevar-{case_index:03d}"
        e.check(prefix + "-value", "A", expected_value=as_u64(expected_a))
        e.check(prefix + "-wide", "Wide", expected_value=expected_wide)
        e.check(prefix + "-byte", "B", expected_value=byte_value)
        e.line("end;")
        e.line()
    e.line("procedure RunGeneratedInlineVarForms;")
    e.line("begin")
    for proc in form_calls:
        e.line(f"  {proc};")
    e.line("end;")
    e.line("{$else}")
    e.line("procedure RunGeneratedInlineVarForms;")
    e.line("begin")
    e.line("end;")
    e.line("{$endif}")
    e.line()
    return ["RunGeneratedInlineVarForms"]


def emit_index_forms(e: Emitter) -> list[str]:
    e.line("type")
    e.line("  TGenIndexBox = record")
    e.line("    Before: UInt64;")
    e.line("    Data: array[Byte] of UInt32;")
    e.line("    After: UInt64;")
    e.line("  end;")
    e.line()
    calls: list[str] = []
    expressions: list[tuple[str, int, int]] = []
    for base in (-513, -300, -257, -256, -255, -129, -128, -5, -1, 0,
                 1, 5, 127, 128, 255, 256, 257, 300, 511, 512):
        for delta in (-17, -5, -1, 0, 1, 5, 17):
            expressions.append(("Byte(I + D)", base, delta))
            expressions.append(("Byte(ShortInt(I) + D)", base, delta))
            expressions.append(("Byte((I xor D) + 3)", base, delta))
            expressions.append(("Byte((I and $FFFF) - D)", base, delta))
    for case_id, (expression, base, delta) in enumerate(expressions, start=1):
        proc = f"GenIndexForm{case_id:04d}"
        calls.append(proc)
        index = None
        if expression == "Byte(I + D)":
            index = (base + delta) & 0xFF
        elif expression == "Byte(ShortInt(I) + D)":
            short = base & 0xFF
            if short >= 128:
                short -= 256
            index = (short + delta) & 0xFF
        elif expression == "Byte((I xor D) + 3)":
            index = ((base ^ delta) + 3) & 0xFF
        else:
            index = (((base & 0xFFFF) - delta) & 0xFF)
        value = (case_id * 2654435761) & 0xFFFFFFFF
        e.line(f"procedure {proc};")
        e.line("var")
        e.line("  Box: TGenIndexBox;")
        e.line("  I, D: Integer;")
        e.line("begin")
        e.line("  FillChar(Box, SizeOf(Box), 0);")
        e.line("  Box.Before := UInt64($0123456789ABCDEF);")
        e.line("  Box.After := UInt64($FEDCBA9876543210);")
        e.line(f"  I := {base};")
        e.line(f"  D := {delta};")
        e.line(f"  Box.Data[{expression}] := UInt32(${value:08X});")
        base_name = f"gen-index-{case_id:04d}"
        e.check(base_name + "-value", f"Box.Data[{index}]")
        e.check(base_name + "-before", "Box.Before")
        e.check(base_name + "-after", "Box.After")
        e.line("end;")
        e.line()
    return calls


def generate(oracle: dict[str, str]) -> tuple[str, list[str]]:
    e = Emitter(oracle)
    e.line("{ Generated by scripts/generate_expanded_omni.py. Do not edit. }")
    e.line("{ Each procedure below is a distinct compiler source form. }")
    e.line()
    emit_integer_types(e)
    calls: list[str] = []
    calls += emit_integer_forms(e)
    calls += emit_promotion_forms(e)
    calls += emit_mixed_value_forms(e)
    calls += emit_shift_forms(e)
    calls += emit_loop_forms(e)
    calls += emit_alias_forms(e)
    calls += emit_state_machine_forms(e)
    calls += emit_inline_var_forms(e)
    calls += emit_record_abi_forms(e)
    calls += emit_abi_cross_forms(e)
    calls += emit_index_forms(e)
    e.line("procedure RunGeneratedForms;")
    e.line("begin")
    for call in calls:
        e.line(f"  {call};")
    e.line("end;")
    e.line()
    return "\n".join(e.lines), e.names


def probe_source() -> str:
    return """program omni_generated_oracle;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch INLINEVARS}
  {$define HAS_INLINEVAR}
{$else}
  {$define HAS_INLINEVAR}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

var
  RtZero: UInt64 = 0;

function OpaqueU(V: UInt64): UInt64;
begin
  Result := V xor RtZero;
end;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor RtZero);
end;

procedure GeneratedCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  WriteLn(string(Name), '=', IntToHex(Actual, 16));
end;

{$I omni_generated_forms.inc}

begin
  RunGeneratedForms;
end.
"""


ORACLE_RE = re.compile(r"^([a-z0-9-]+)=([0-9A-F]{16})$")


def capture_oracle(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    raw = path.read_bytes()
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8-sig")
    for raw_line in text.splitlines():
        match = ORACLE_RE.fullmatch(raw_line.strip())
        if match:
            name, value = match.groups()
            if name in result:
                raise SystemExit(f"duplicate oracle name: {name}")
            result[name] = value
    if not result:
        raise SystemExit(f"no oracle rows found in {path}")
    return result


def write_if_changed(path: Path, content: str) -> None:
    encoded = content.encode("utf-8")
    if path.exists() and path.read_bytes() == encoded:
        return
    path.write_bytes(encoded)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    oracle: dict[str, str] = {}
    if ORACLE.exists():
        oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
    if args.capture:
        oracle = capture_oracle(args.capture)
        write_if_changed(
            ORACLE,
            json.dumps(oracle, indent=2, sort_keys=True) + "\n",
        )

    generated, names = generate(oracle)
    missing = sorted(set(names) - set(oracle))
    extra = sorted(set(oracle) - set(names))
    manifest = {
        "schema": 1,
        "generator": "scripts/generate_expanded_omni.py",
        "case_count": len(names),
        "unique_case_count": len(set(names)),
        "oracle_count": len(oracle),
        "oracle_complete": not missing and not extra,
        "missing_oracle_count": len(missing),
        "extra_oracle_count": len(extra),
    }

    expected_files = {
        GENERATED: generated,
        PROBE: probe_source(),
        MANIFEST: json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    }
    if args.check:
        mismatches = [
            str(path.relative_to(ROOT))
            for path, content in expected_files.items()
            if not path.exists() or path.read_bytes() != content.encode("utf-8")
        ]
        if mismatches:
            raise SystemExit("generated files are stale: " + ", ".join(mismatches))
        if not manifest["oracle_complete"]:
            raise SystemExit(
                f"oracle incomplete: missing={len(missing)} extra={len(extra)}"
            )
        return

    for path, content in expected_files.items():
        write_if_changed(path, content)
    print(json.dumps(manifest, sort_keys=True))


if __name__ == "__main__":
    main()
