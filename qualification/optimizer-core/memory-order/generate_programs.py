#!/usr/bin/env python3
"""Programs in which one memory has two names.

A routine of a program reads and writes memory under several names: a variable of the module by its name, a
pointer parameter, a field of a record behind a pointer, an element of an array behind a pointer with a constant
and with a variable index, a half of a 64-bit cell, a byte of it, a local by its name and through its own address,
a local whose address a called routine has kept.  Every routine is called four times: with pointers which look at
the cells the routine names, at their neighbours, and elsewhere.

The expected values are counted here: the memory is bytes, the integer arithmetic is 64-bit and wraps, the real
values are exact binary fractions.  They are the order of the statements of the text.  A routine which leaves its
objects while it is counted is dropped.

Families:
  mixed  integer cells of 1, 2, 4 and 8 bytes, signed and unsigned, by name and through pointers; a 32-bit local
  float  cells of Double by name and through pointers, integer to real and back, the bits of a real through an
         integer pointer
  step   Inc and Dec with constants of both signs, doubling, a pointer which steps by a constant and by the
         value it reads

    generate_programs.py --family mixed --seed 1 --functions 300 --out memory_order_mixed_1.dpr
"""
import argparse
import random
import struct
from pathlib import Path

MASK = (1 << 64) - 1


def s64(v):
    v &= MASK
    return v - (1 << 64) if v >> 63 else v


def wrap(v, size, signed):
    bits = 8 * size
    v &= (1 << bits) - 1
    if signed and v >> (bits - 1):
        v -= 1 << bits
    return v


class OutOfBounds(Exception):
    pass


class Memory:
    """the objects of the module and the local L of the routine: name -> bytes"""

    def __init__(self, layout):
        self.data = {k: bytearray(v) for k, v in layout.items()}

    def check(self, obj, off, size):
        if obj not in self.data or off < 0 or off + size > len(self.data[obj]):
            raise OutOfBounds(f"{obj}+{off}:{size}")

    def read(self, obj, off, size, signed):
        self.check(obj, off, size)
        return int.from_bytes(self.data[obj][off:off + size], "little", signed=signed)

    def write(self, obj, off, size, value):
        self.check(obj, off, size)
        self.data[obj][off:off + size] = (value & ((1 << (8 * size)) - 1)).to_bytes(size, "little")

    def readf(self, obj, off):
        self.check(obj, off, 8)
        return struct.unpack_from("<d", self.data[obj], off)[0]

    def writef(self, obj, off, value):
        self.check(obj, off, 8)
        struct.pack_into("<d", self.data[obj], off, value)


# ---------------------------------------------------------------------------------------------------------
# the module of every program: its objects, their first values, the sum over them
# ---------------------------------------------------------------------------------------------------------
LAYOUT = {"Cell": 8, "G": 32, "M": 64, "GS": 8, "CellD": 8, "GD": 32, "T": 128, "L": 8}
INT_SLOTS = [("Cell", 0)] + [("G", o) for o in (0, 8, 16, 24)] + [("M", o) for o in range(0, 64, 8)] + [("GS", 0)]
STEP_VALUES = [8, 16, 0, 8, 24, 8, 0, 16, 8, 8, 16, 0, 8, 0, 0, 0]

DECL = """type
  PInt64 = ^Int64;
  PInteger = ^Integer;
  PCardinal = ^Cardinal;
  PWord = ^Word;
  PSmallInt = ^SmallInt;
  PDouble = ^Double;
  TRec = record
    A, B, C, D: Int64;
  end;
  PRec = ^TRec;
  TRecD = record
    A, B: Double;
  end;
  PRecD = ^TRecD;
  TInt64Array = array[0..15] of Int64;
  PInt64Array = ^TInt64Array;
  TPair32 = record
    Lo, Hi: Integer;
  end;
  PPair32 = ^TPair32;
  TSmall = record
    B0, B1: Byte;
    W1: Word;
    I1: Integer;
  end;

var
  Failures: Integer;
  Cell: Int64;
  G: TRec;
  M: array[0..7] of Int64;
  GS: TSmall;
  CellD: Double;
  GD: array[0..3] of Double;
  T: array[0..15] of Int64;
  GP: PInt64;

procedure InitMem;
var
  I: Integer;
begin
  Cell := 107;
  G.A := 114;
  G.B := 121;
  G.C := 128;
  G.D := 135;
  for I := 0 to 7 do
    M[I] := 142 + 7 * I;
  GS.B0 := 200;
  GS.B1 := 3;
  GS.W1 := 40000;
  GS.I1 := -5;
  CellD := 2.5;
  for I := 0 to 3 do
    GD[I] := 1.5 + I;
{STEPS}
end;

function MemSum: Int64;
var
  I: Integer;
begin
  Result := Cell + G.A * 2 + G.B * 3 + G.C * 4 + G.D * 5;
  for I := 0 to 7 do
    Result := Result + M[I] * (6 + I);
  Result := Result + PInt64(@GS)^ * 14;
  Result := Result + Trunc(CellD * 1024) * 15;
  for I := 0 to 3 do
    Result := Result + Trunc(GD[I] * 1024) * (16 + I);
  for I := 0 to 15 do
    Result := Result + T[I] * (20 + I);
end;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

{ keeps the address of a local of its caller }
procedure Keep(var V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  GP := @V;
end;
"""


def init_memory(mem, k):
    n = 0
    for obj, off in INT_SLOTS[:-1]:
        n += 1
        mem.write(obj, off, 8, 100 + 7 * n)
    mem.write("GS", 0, 1, 200)
    mem.write("GS", 1, 1, 3)
    mem.write("GS", 2, 2, 40000)
    mem.write("GS", 4, 4, -5)
    mem.writef("CellD", 0, 2.5)
    for i in range(4):
        mem.writef("GD", 8 * i, 1.5 + i)
    for i, v in enumerate(STEP_VALUES):
        mem.write("T", 8 * i, 8, v)
    mem.write("L", 0, 8, k + 40)


def checksum(mem):
    total = 0
    k = 0
    for obj, off in INT_SLOTS:
        k += 1
        total += mem.read(obj, off, 8, True) * k
    total += int(mem.readf("CellD", 0) * 1024) * 15
    for i in range(4):
        total += int(mem.readf("GD", 8 * i) * 1024) * (16 + i)
    for i in range(16):
        total += mem.read("T", 8 * i, 8, True) * (20 + i)
    return s64(total)


def address_text(obj, off):
    if off == 0:
        return f"@{obj}"
    return f"PByte(@{obj}) + {off}"


# ---------------------------------------------------------------------------------------------------------
# an access: (text, locate(env) -> (object, offset), size, signed, kind); kind 'i' integer, 'f' double
# ---------------------------------------------------------------------------------------------------------
def by_name(text, obj, off, size, signed, kind="i"):
    return (text, (lambda env, obj=obj, off=off: (obj, off)), size, signed, kind)


def by_pointer(text, param, off, size, signed, kind="i"):
    def locate(env, param=param, off=off):
        obj, base = env["@" + param]
        return obj, base + off
    return (text, locate, size, signed, kind)


def by_index(text, param, index, size, signed):
    def locate(env, param=param, index=index):
        obj, base = env["@" + param]
        return obj, base + 8 * env[index]
    return (text, locate, size, signed, "i")


INT_NAMES = ([by_name("Cell", "Cell", 0, 8, True)] +
             [by_name("G." + "ABCD"[i], "G", 8 * i, 8, True) for i in range(4)] +
             [by_name(f"M[{i}]", "M", 8 * i, 8, True) for i in range(8)])
SMALL_NAMES = [by_name("GS.B0", "GS", 0, 1, False), by_name("GS.B1", "GS", 1, 1, False),
               by_name("GS.W1", "GS", 2, 2, False), by_name("GS.I1", "GS", 4, 4, True)]
FLOAT_NAMES = ([by_name("CellD", "CellD", 0, 8, True, "f")] +
               [by_name(f"GD[{i}]", "GD", 8 * i, 8, True, "f") for i in range(4)])

# a pointer parameter: name -> (type, accesses, bytes it reaches, step of its address, objects it may look at)
INT_OBJECTS = ["Cell", "G", "M", "GS"]
POINTERS = {
    "P": ("PInt64", [by_pointer("P^", "P", 0, 8, True)], 8, 8, INT_OBJECTS),
    "Q": ("PInt64", [by_pointer("Q^", "Q", 0, 8, True)], 8, 8, INT_OBJECTS),
    "R": ("PRec", [by_pointer("R^." + "ABCD"[i], "R", 8 * i, 8, True) for i in range(4)], 32, 8, INT_OBJECTS),
    "A": ("PInt64Array", [by_pointer(f"A^[{i}]", "A", 8 * i, 8, True) for i in range(3)], 24, 8, INT_OBJECTS),
    "H": ("PPair32", [by_pointer("H^.Lo", "H", 0, 4, True), by_pointer("H^.Hi", "H", 4, 4, True)], 8, 4, INT_OBJECTS),
    "C": ("PCardinal", [by_pointer("C^", "C", 0, 4, False)], 4, 4, INT_OBJECTS),
    "W": ("PWord", [by_pointer("W^", "W", 0, 2, False)], 2, 2, INT_OBJECTS),
    "S": ("PSmallInt", [by_pointer("S^", "S", 0, 2, True)], 2, 2, INT_OBJECTS),
    "B": ("PByte", [by_pointer("B^", "B", 0, 1, False)], 1, 1, INT_OBJECTS),
    "PD": ("PDouble", [by_pointer("PD^", "PD", 0, 8, True, "f")], 8, 8, ["CellD", "GD"]),
    "QD": ("PDouble", [by_pointer("QD^", "QD", 0, 8, True, "f")], 8, 8, ["CellD", "GD"]),
    "RD": ("PRecD", [by_pointer("RD^.A", "RD", 0, 8, True, "f"), by_pointer("RD^.B", "RD", 8, 8, True, "f")],
           16, 8, ["GD"]),
    # the bytes of a real under an integer type
    "PI": ("PInt64", [by_pointer("PI^", "PI", 0, 8, True)], 8, 8, ["CellD", "GD"]),
}


class Routine:
    family = "mixed"
    int_locals = ["X", "Y", "Z"]
    float_locals = []
    pointer_pool = ["P", "Q", "R", "A", "H", "C", "W", "S", "B"]

    def __init__(self, rnd, index):
        self.rnd = rnd
        self.name = f"F{index}"
        self.ptrs = sorted(rnd.sample(self.pointer_pool, rnd.choice([1, 2, 2, 3])))
        self.use_index = "A" in self.ptrs and rnd.random() < 0.5
        # the local L: 'own' - the routine takes its address itself, 'kept' - a called routine keeps it
        self.local = rnd.choice(["own", "kept", None, None, None, None, None, None])
        self.use_n = rnd.random() < 0.5            # a 32-bit local
        self.choose_names()
        self.accs = self.accesses()
        self.defined = []
        self.body = []
        self.build()

    def choose_names(self):
        r = self.rnd
        self.names = r.sample(INT_NAMES, r.choice([1, 2, 3]))
        if r.random() < 0.5:
            self.names += r.sample(SMALL_NAMES, r.choice([1, 2]))

    def accesses(self):
        out = list(self.names)
        for p in self.ptrs:
            out += POINTERS[p][1]
        if self.use_index:
            out.append(by_index("A^[I]", "A", "I", 8, True))
        if self.local:
            out.append(by_name("L", "L", 0, 8, True))
            out.append(by_name("PL^" if self.local == "own" else "GP^", "L", 0, 8, True))
        return out

    # ---- values ---------------------------------------------------------------------------------------
    def ints(self):
        return [v for v in self.defined if v in self.int_locals or v == "N"]

    def value(self):
        r = self.rnd
        k = r.random()
        pool = self.ints()
        if pool and k < 0.4:
            v = r.choice(pool)
            # a 32-bit local takes part in 64-bit arithmetic: Integer * Integer is counted in 32 bits
            return ("Int64(N)" if v == "N" else v), (lambda env, v=v: env[v])
        if k < 0.55:
            return "K", (lambda env: env["K"])
        c = r.choice([1, 2, 3, 5, 7, 10, 100, 1000, 255, 65535])
        return str(c), (lambda env, c=c: c)

    def expr(self):
        r = self.rnd
        a_text, a = self.value()
        if r.random() < 0.3:
            return a_text, a
        op = r.choice(["+", "-", "*", "and", "or", "xor"])
        b_text, b = self.value()
        if op == "*":
            c = r.choice([2, 3, 5, 1000])
            b_text, b = str(c), (lambda env, c=c: c)
        fn = {"+": lambda x, y: x + y, "-": lambda x, y: x - y, "*": lambda x, y: x * y,
              "and": lambda x, y: x & y, "or": lambda x, y: x | y, "xor": lambda x, y: x ^ y}[op]
        return f"({a_text} {op} {b_text})", (lambda env, a=a, b=b, fn=fn: s64(fn(a(env), b(env))))

    def target(self):
        """a local which takes an integer value: (name, store(env, value))"""
        r = self.rnd
        names = list(self.int_locals) + (["N"] if self.use_n else [])
        v = r.choice(names)
        if v == "N":
            return v, (lambda env, x: env.__setitem__("N", wrap(x, 4, True)))
        return v, (lambda env, x, v=v: env.__setitem__(v, s64(x)))

    def note(self, v):
        if v not in self.defined:
            self.defined.append(v)

    @staticmethod
    def runtime(e_text, size):
        """a constant expression which does not fit its target is an error of the compiler, not a wrap: the
        same value is counted when the program runs"""
        if size < 8 and not any(c.isalpha() and c.isupper() for c in e_text):
            return f"((K - K) + {e_text})"
        return e_text

    # ---- statements -------------------------------------------------------------------------------------
    def int_accs(self):
        return [a for a in self.accs if a[4] == "i" and a[0] != "PI^"]

    def st_load(self):
        acc = self.rnd.choice(self.int_accs())
        v, put = self.target()
        text = f"  {v} := {acc[0]};"

        def run(env, mem, acc=acc, put=put):
            obj, off = acc[1](env)
            put(env, mem.read(obj, off, acc[2], acc[3]))
        self.note(v)
        return text, run

    def st_store(self):
        r = self.rnd
        acc = r.choice(self.int_accs())
        if r.random() < 0.45:
            c = r.choice([1, 2, 4, 5, 8, 100])
            op = r.choice(["+", "-", "or", "xor"])
            fn = {"+": lambda x, y: x + y, "-": lambda x, y: x - y,
                  "or": lambda x, y: x | y, "xor": lambda x, y: x ^ y}[op]
            text = f"  {acc[0]} := {acc[0]} {op} {c};"

            def run(env, mem, acc=acc, c=c, fn=fn):
                obj, off = acc[1](env)
                mem.write(obj, off, acc[2], fn(mem.read(obj, off, acc[2], acc[3]), c))
        else:
            e_text, e = self.expr()
            text = f"  {acc[0]} := {self.runtime(e_text, acc[2])};"

            def run(env, mem, acc=acc, e=e):
                obj, off = acc[1](env)
                mem.write(obj, off, acc[2], e(env))
        return text, run

    def st_calc(self):
        r = self.rnd
        if r.random() < 0.15:
            e_text, e = self.expr()
            return f"  K := {e_text};", (lambda env, mem, e=e: env.__setitem__("K", e(env)))
        v, put = self.target()
        e_text, e = self.expr()
        if v == "N":
            e_text = self.runtime(e_text, 4)
        self.note(v)
        return f"  {v} := {e_text};", (lambda env, mem, e=e, put=put: put(env, e(env)))

    def st_if(self):
        r = self.rnd
        pool = [v for v in self.defined if v in self.int_locals]
        if not pool:
            return self.st_calc()
        a_text, a = self.value()
        v = r.choice(pool)
        d = r.choice([1, 3, 10])
        if r.random() < 0.5:
            c = r.choice([1, 2, 4, 8])
            text = f"  if ({a_text} and {c}) <> 0 then\n    {v} := {v} + {d}\n  else\n    {v} := {v} - {d};"

            def run(env, mem, a=a, c=c, v=v, d=d):
                env[v] = s64(env[v] + d) if (a(env) & c) != 0 else s64(env[v] - d)
        else:
            b_text, b = self.value()
            text = f"  if {a_text} < {b_text} then\n    {v} := {v} + {d}\n  else\n    {v} := {v} - {d};"

            def run(env, mem, a=a, b=b, v=v, d=d):
                env[v] = s64(env[v] + d) if a(env) < b(env) else s64(env[v] - d)
        return text, run

    def statement(self):
        k = self.rnd.random()
        if k < 0.30:
            return self.st_load()
        if k < 0.60:
            return self.st_store()
        if k < 0.88:
            return self.st_calc()
        return self.st_if()

    def finish(self):
        r = self.rnd
        acc = r.choice(self.int_accs())
        parts = [v for v in self.defined if v in self.int_locals or v == "N"][:3]
        text = "  Result := " + " + ".join(f"{'Int64(N)' if v == 'N' else v} * {m}"
                                           for v, m in zip(parts, (1, 1000, 1000000)))
        text += f" + K + {acc[0]};"

        def fin(env, mem, acc=acc, parts=parts):
            total = 0
            for v, m in zip(parts, (1, 1000, 1000000)):
                total += env[v] * m
            obj, off = acc[1](env)
            env["Result"] = s64(total + env["K"] + mem.read(obj, off, acc[2], acc[3]))
        return text, fin

    def build(self):
        self.body.append(self.st_load())
        for _ in range(self.rnd.randint(4, 9)):
            self.body.append(self.statement())
        self.body.append(self.finish())

    # ---- text -------------------------------------------------------------------------------------------
    def params(self):
        ps = [f"{p}: {POINTERS[p][0]}" for p in self.ptrs]
        ps.append("K: Int64")
        if self.use_index:
            ps.append("I: Int64")
        return "; ".join(ps)

    def declarations(self):
        out = ["  " + ", ".join(self.int_locals + (["L"] if self.local else [])) + ": Int64;"]
        if self.use_n:
            out.append("  N: Integer;")
        if self.float_locals:
            out.append("  " + ", ".join(self.float_locals) + ": Double;")
        if self.local == "own":
            out.append("  PL: PInt64;")
        return out

    def prologue(self):
        out = [f"  {v} := 0;" for v in self.int_locals]
        if self.use_n:
            out.append("  N := 0;")
        out += [f"  {v} := 0;" for v in self.float_locals]
        if self.local:
            out.append("  L := K + 40;")
            out.append("  PL := @L;" if self.local == "own" else "  Keep(L);")
        return out

    def source(self):
        out = [f"function {self.name}({self.params()}): Int64; {{$IFDEF FPC}} noinline; {{$ENDIF}}", "var"]
        out += self.declarations()
        out.append("begin")
        out += self.prologue()
        out += [t for t, _ in self.body]
        out.append("end;")
        return "\n".join(out)

    # ---- calls ------------------------------------------------------------------------------------------
    def scenario(self, r, elsewhere):
        """where the pointers look, the index, K"""
        where = {}
        index = r.choice([0, 1, 2]) if self.use_index else 0
        taken = [a[1]({}) for a in self.names]
        for p in self.ptrs:
            _, _, reach, step, objects = POINTERS[p]
            if p == "A" and self.use_index:
                reach = max(reach, 8 * index + 8)
            fits = []
            for o in objects:
                for off in range(0, LAYOUT[o] - reach + 1, step):
                    fits.append((o, off))
            if elsewhere:
                far = [(o, off) for o, off in fits if o in ("M", "GD")]
                fits = far or fits
            else:
                near = [(o, off) for o, off in fits
                        if any(o == no and abs(off - noff) <= 16 for no, noff in taken + list(where.values()))]
                if near and r.random() < 0.8:
                    fits = near
            where[p] = r.choice(fits)
        return where, index, r.choice([0, 1, 9, 100])

    def first_values(self, env, mem):
        pass

    def call(self, where, index, k):
        env = {"K": k, "I": index, "N": 0}
        for v in self.int_locals:
            env[v] = 0
        for v in self.float_locals:
            env[v] = 0.0
        for p, w in where.items():
            env["@" + p] = w
        mem = Memory(LAYOUT)
        init_memory(mem, k)
        self.first_values(env, mem)
        for _, run in self.body:
            run(env, mem)
        return env["Result"], checksum(mem)

    def arguments(self, where):
        return [f"{POINTERS[p][0]}({address_text(*where[p])})" for p in self.ptrs]

    def call_text(self, where, index, k):
        args = self.arguments(where)
        args.append(str(k))
        if self.use_index:
            args.append(str(index))
        return f"{self.name}({', '.join(args)})"


class FloatRoutine(Routine):
    """cells of Double; Bits carries the bits of a real from one cell to another through the integer pointer"""
    family = "float"
    int_locals = ["X", "Y"]
    float_locals = ["D1", "D2", "D3"]
    pointer_pool = ["PD", "QD", "RD", "PI", "P"]

    def choose_names(self):
        r = self.rnd
        self.names = r.sample(FLOAT_NAMES, r.choice([1, 2, 3]))
        if r.random() < 0.4:
            self.names += r.sample(INT_NAMES, 1)
        self.use_index = False
        self.local = None
        self.use_n = False

    def float_accs(self):
        return [a for a in self.accs if a[4] == "f"]

    def fdefined(self):
        return [v for v in self.defined if v in self.float_locals]

    def fvalue(self):
        r = self.rnd
        pool = self.fdefined()
        if pool and r.random() < 0.5:
            v = r.choice(pool)
            return v, (lambda env, v=v: env[v])
        c = r.choice([0.5, 1.5, 2.0, 3.0, 4.0, 0.25])
        return repr(c), (lambda env, c=c: c)

    def fexpr(self):
        r = self.rnd
        a_text, a = self.fvalue()
        if r.random() < 0.3:
            return a_text, a
        op = r.choice(["+", "-", "*"])
        b_text, b = self.fvalue()
        if op == "*":
            c = r.choice([0.5, 2.0, 1.5])
            b_text, b = repr(c), (lambda env, c=c: c)
        fn = {"+": lambda x, y: x + y, "-": lambda x, y: x - y, "*": lambda x, y: x * y}[op]
        return f"({a_text} {op} {b_text})", (lambda env, a=a, b=b, fn=fn: fn(a(env), b(env)))

    def st_fload(self):
        acc = self.rnd.choice(self.float_accs())
        v = self.rnd.choice(self.float_locals)

        def run(env, mem, acc=acc, v=v):
            obj, off = acc[1](env)
            env[v] = mem.readf(obj, off)
        self.note(v)
        return f"  {v} := {acc[0]};", run

    def st_fstore(self):
        r = self.rnd
        acc = r.choice(self.float_accs())
        if r.random() < 0.45:
            c = r.choice([0.5, 1.0, 2.5])
            op = r.choice(["+", "-"])
            text = f"  {acc[0]} := {acc[0]} {op} {c!r};"

            def run(env, mem, acc=acc, c=c, op=op):
                obj, off = acc[1](env)
                x = mem.readf(obj, off)
                mem.writef(obj, off, x + c if op == "+" else x - c)
        else:
            e_text, e = self.fexpr()
            text = f"  {acc[0]} := {e_text};"

            def run(env, mem, acc=acc, e=e):
                obj, off = acc[1](env)
                mem.writef(obj, off, e(env))
        return text, run

    def st_bits(self):
        if self.rnd.random() < 0.5:
            def run(env, mem):
                obj, off = env["@PI"]
                env["Bits"] = mem.read(obj, off, 8, True)
            return "  Bits := PI^;", run

        def run(env, mem):
            obj, off = env["@PI"]
            mem.write(obj, off, 8, env["Bits"])
        return "  PI^ := Bits;", run

    def st_fcalc(self):
        r = self.rnd
        v = r.choice(self.float_locals)
        k = r.random()
        if k < 0.2 and self.ints():
            x = r.choice(self.ints())
            self.note(v)
            return (f"  {v} := ({x} and 1023);",
                    lambda env, mem, v=v, x=x: env.__setitem__(v, float(env[x] & 1023)))
        e_text, e = self.fexpr()
        self.note(v)
        return f"  {v} := {e_text};", (lambda env, mem, v=v, e=e: env.__setitem__(v, e(env)))

    def st_trunc(self):
        pool = self.fdefined()
        if not pool:
            return self.st_fcalc()
        d = self.rnd.choice(pool)
        v = self.rnd.choice(self.int_locals)
        self.note(v)
        return f"  {v} := Trunc({d} * 4);", (lambda env, mem, v=v, d=d: env.__setitem__(v, s64(int(env[d] * 4))))

    def st_fif(self):
        pool = self.fdefined()
        if not pool:
            return self.st_fcalc()
        r = self.rnd
        a = r.choice(pool)
        b_text, b = self.fvalue()
        v = r.choice(pool)
        text = f"  if {a} < {b_text} then\n    {v} := {v} + 1.0\n  else\n    {v} := {v} - 0.5;"

        def run(env, mem, a=a, b=b, v=v):
            env[v] = env[v] + 1.0 if env[a] < b(env) else env[v] - 0.5
        return text, run

    def statement(self):
        k = self.rnd.random()
        if k < 0.27:
            return self.st_fload()
        if k < 0.54:
            return self.st_fstore()
        if k < 0.72:
            return self.st_fcalc()
        if k < 0.80:
            return self.st_trunc()
        if k < 0.86:
            return self.st_fif()
        if "PI" in self.ptrs and k < 0.92:
            return self.st_bits()
        if self.int_accs() and k < 0.96:
            return self.st_load()
        if self.int_accs():
            return self.st_store()
        return self.st_fcalc()

    def declarations(self):
        out = super().declarations()
        if "PI" in self.ptrs:
            out.append("  Bits: Int64;")
        return out

    def prologue(self):
        out = super().prologue()
        if "PI" in self.ptrs:
            out.append("  Bits := PI^;")
        return out

    def first_values(self, env, mem):
        if "PI" in self.ptrs:
            obj, off = env["@PI"]
            env["Bits"] = mem.read(obj, off, 8, True)

    def build(self):
        self.body.append(self.st_fload())
        for _ in range(self.rnd.randint(4, 9)):
            self.body.append(self.statement())
        self.body.append(self.finish())

    def finish(self):
        acc = self.rnd.choice(self.float_accs())
        fparts = self.fdefined()[:3]
        iparts = [v for v in self.defined if v in self.int_locals][:2]
        text = "  Result := " + " + ".join([f"Trunc({v} * 16) * {m}" for v, m in zip(fparts, (1, 1000, 1000000))] +
                                           [f"{v} * {m}" for v, m in zip(iparts, (7, 7000))])
        text += f" + K + Trunc({acc[0]} * 16);"

        def fin(env, mem, acc=acc, fparts=fparts, iparts=iparts):
            total = 0
            for v, m in zip(fparts, (1, 1000, 1000000)):
                total += int(env[v] * 16) * m
            for v, m in zip(iparts, (7, 7000)):
                total += env[v] * m
            obj, off = acc[1](env)
            env["Result"] = s64(total + env["K"] + int(mem.readf(obj, off) * 16))
        return text, fin


class StepRoutine(Routine):
    """Inc and Dec with constants, doubling, a pointer which steps by what it reads"""
    family = "step"
    int_locals = ["X", "Y", "Z"]
    pointer_pool = ["P", "Q", "R", "A"]

    def choose_names(self):
        self.names = self.rnd.sample(INT_NAMES, self.rnd.choice([1, 2]))
        self.use_n = False
        self.walker = self.rnd.random() < 0.7          # a PByte which walks the table T

    def accesses(self):
        out = super().accesses()
        if self.walker:
            out.append(by_pointer("PInt64(V)^", "V", 0, 8, True))
        return out

    def st_incdec(self):
        r = self.rnd
        v = r.choice(self.int_locals)
        self.note(v)
        k = r.random()
        if k < 0.4:
            c = r.choice([1, 3, 8, -8, -3, 100, -100])
            op = r.choice(["Inc", "Dec"])
            sign = 1 if op == "Inc" else -1
            return (f"  {op}({v}, {c});",
                    lambda env, mem, v=v, c=c, sign=sign: env.__setitem__(v, s64(env[v] + sign * c)))
        if k < 0.6:
            return f"  {v} := {v} + {v};", (lambda env, mem, v=v: env.__setitem__(v, s64(env[v] * 2)))
        w = r.choice(self.int_locals)
        self.note(w)
        op = r.choice(["+", "-"])
        return (f"  {v} := {v} {op} {w};",
                lambda env, mem, v=v, w=w, op=op:
                env.__setitem__(v, s64(env[v] + env[w] if op == "+" else env[v] - env[w])))

    def st_walk(self):
        r = self.rnd
        k = r.random()
        if k < 0.35:
            c = r.choice([8, 16, 8, 24])

            def run(env, mem, c=c):
                obj, off = env["@V"]
                env["@V"] = (obj, off + c)
            return f"  Inc(V, {c});", run
        if k < 0.5:
            def run(env, mem):
                obj, off = env["@V"]
                env["@V"] = (obj, off - 8)
            return "  Dec(V, 8);", run
        if k < 0.85:
            def run(env, mem):
                obj, off = env["@V"]
                env["@V"] = (obj, off + mem.read(obj, off, 8, True))
            return "  Inc(V, PInt64(V)^);", run
        v = r.choice(self.int_locals)
        self.note(v)

        def run(env, mem, v=v):
            obj, off = env["@V"]
            env[v] = mem.read(obj, off, 8, True)
        return f"  {v} := PInt64(V)^;", run

    def statement(self):
        k = self.rnd.random()
        if k < 0.35:
            return self.st_incdec()
        if self.walker and k < 0.6:
            return self.st_walk()
        if k < 0.72:
            return self.st_load()
        if k < 0.84:
            return self.st_store()
        if k < 0.95:
            return self.st_calc()
        return self.st_if()

    def params(self):
        text = super().params()
        if self.walker:
            text = "V: PByte; " + text
        return text

    def scenario(self, r, elsewhere):
        where, index, k = super().scenario(r, elsewhere)
        if self.walker:
            where["V"] = ("T", 8 * r.choice([0, 1, 2, 3, 4]))
        return where, index, k

    def arguments(self, where):
        args = [f"PByte({address_text(*where['V'])})"] if self.walker else []
        return args + [f"{POINTERS[p][0]}({address_text(*where[p])})" for p in self.ptrs]


FAMILIES = {"mixed": Routine, "float": FloatRoutine, "step": StepRoutine}


def generate(family, seed, functions, name):
    """the text of the program, the number of its calls"""
    rnd = random.Random(f"{family}:{seed}")
    cls = FAMILIES[family]
    out = [f"program {name};",
           f"{{ Written by generate_programs.py --family {family} --seed {seed} --functions {functions}. }}",
           "{$IFDEF FPC}", "  {$MODE DELPHI}{$H+}", "{$ELSE}", "  {$APPTYPE CONSOLE}", "{$ENDIF}", "{$Q-}{$R-}", ""]
    steps = "\n".join(f"  T[{i}] := {v};" for i, v in enumerate(STEP_VALUES))
    out.append(DECL.replace("{STEPS}", steps))
    calls = []
    count = 0
    index = 0
    while count < functions:
        index += 1
        f = cls(rnd, index)
        mine = []
        try:
            for s in range(4):
                where, idx, k = f.scenario(rnd, elsewhere=(s == 3))
                want, memsum = f.call(where, idx, k)
                mine.append(f"  InitMem;\n  Check('{f.name}.{s}', {f.call_text(where, idx, k)}, {want});\n"
                            f"  Check('{f.name}.{s}.mem', MemSum, {memsum});")
        except OutOfBounds:
            continue
        out.append(f.source())
        out.append("")
        calls += mine
        count += 1
    # the calls stand in routines of 50: no routine of the program is too large
    groups = [calls[i:i + 50] for i in range(0, len(calls), 50)]
    for gi, g in enumerate(groups):
        out.append(f"procedure Run{gi};\nbegin")
        out += g
        out.append("end;\n")
    out.append("begin")
    for gi in range(len(groups)):
        out.append(f"  Run{gi};")
    tag = name.upper()
    out.append(f"  if Failures = 0 then\n    WriteLn('{tag}_PASS')\n  else\n  begin\n"
               f"    WriteLn('{tag}_FAIL ', Failures);\n    Halt(1);\n  end;")
    out.append("end.")
    return "\n".join(out) + "\n", len(calls)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--family", choices=sorted(FAMILIES), default="mixed")
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--functions", type=int, default=300)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--name", default=None)
    args = ap.parse_args()
    name = args.name or args.out.stem
    text, calls = generate(args.family, args.seed, args.functions, name)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8", newline="\n")
    print(f"{args.out}: {args.functions} routines, {calls} calls")


if __name__ == "__main__":
    main()
