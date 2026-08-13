#!/usr/bin/env python3
"""Independent exact-result oracle for benchmark_portable.pas."""

from __future__ import annotations

import argparse
import struct


MASK32 = (1 << 32) - 1
MASK64 = (1 << 64) - 1
HASH_OFFSET = 0xCBF29CE484222325
HASH_PRIME = 0x100000001B3
INITIAL_X_BITS = 0x3FD5555555555555
INITIAL_Y_BITS = 0x3FE45D1745D1745D
RESET_FACTOR_BITS = 0x3EB0C6F7A0B5ED8D
PATTERN = bytes([
    66, 84, 67, 45, 85, 83, 68, 84, 58, 49, 50, 51, 52, 53, 46, 54,
    55, 56, 57, 124, 206, 187, 45, 67, 65, 84, 45, 240, 159, 152, 128, 59,
])
SIZES = (0, 1, 2, 7, 8, 15, 16, 31, 32, 63, 64, 127, 128, 255)


def u64(value: int) -> int:
    return value & MASK64


def i32(value: int) -> int:
    value &= MASK32
    return value if value < (1 << 31) else value - (1 << 32)


def mix(digest: int, value: int) -> int:
    return u64((digest ^ u64(value)) * HASH_PRIME)


def integer_mix(iterations: int) -> int:
    a = 0x0123456789ABCDEF
    b = 0xFEDCBA9876543210
    digest = HASH_OFFSET
    for index in range(1, iterations + 1):
        a = u64((a ^ (a >> 7)) * 0x9E3779B185EBCA87 + index)
        b = u64(b + u64(b << 3)) ^ (a >> 11)
        if index & 1023 == 0:
            digest = mix(digest, a ^ b)
    digest = mix(digest, a)
    return mix(digest, b)


def trunc_divmod(dividend: int, divisor: int) -> tuple[int, int]:
    quotient = abs(dividend) // abs(divisor)
    if (dividend < 0) != (divisor < 0):
        quotient = -quotient
    return quotient, dividend - quotient * divisor


def signed_divmod(iterations: int) -> int:
    state = 0xD1B54A32D192ED03
    digest = HASH_OFFSET
    for _ in range(iterations):
        state ^= state >> 12
        state ^= u64(state << 25)
        state ^= state >> 27
        state = u64(state * 0x2545F4914F6CDD1D)
        value = i32(state)
        divisor = ((state >> 32) % 2001) + 1
        if state & 1:
            divisor = -divisor
        if value == -(1 << 31) and divisor == -1:
            divisor = 1
        quotient, remainder = trunc_divmod(value, divisor)
        packed = (quotient & MASK32) | ((remainder & MASK32) << 32)
        digest = mix(digest, packed)
    return digest


def double_from_bits(bits: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", bits))[0]


def double_bits(value: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def float_affine(iterations: int) -> int:
    x = double_from_bits(INITIAL_X_BITS)
    y = double_from_bits(INITIAL_Y_BITS)
    reset_factor = double_from_bits(RESET_FACTOR_BITS)
    for _ in range(iterations):
        x = x * 1.00000011920928955078125 + y
        y = (y + x) * 0.999999940395355224609375 - 0.25
        if x > 1000000.0:
            x *= reset_factor
            y *= reset_factor
    digest = mix(HASH_OFFSET, double_bits(x))
    return mix(digest, double_bits(y))


def byte_scan(iterations: int) -> int:
    data = bytearray(4096)
    state = 0xA0761D6478BD642F
    for index in range(len(data)):
        state = u64(state * 6364136223846793005 + 1442695040888963407)
        data[index] = state >> 56
    digest = HASH_OFFSET
    for index in range(1, iterations + 1):
        position = (index * 131) & 4095
        for offset in range(256):
            digest = mix(digest, data[(position + offset * 17) & 4095])
    return digest


def move_256(iterations: int) -> int:
    source = bytearray((index * 29 + 17) & 255 for index in range(256))
    destination = bytearray(256)
    digest = HASH_OFFSET
    for index in range(1, iterations + 1):
        destination[:] = source
        position = index & 255
        source[position] = destination[(position + 97) & 255] ^ (index & 255)
        if index & 1023 == 0:
            for value in destination:
                digest = mix(digest, value)
    for source_value, destination_value in zip(source, destination):
        digest = mix(digest, source_value)
        digest = mix(digest, destination_value)
    return digest


def utf8_scan(iterations: int) -> int:
    text = PATTERN * 8
    digest = HASH_OFFSET
    for _ in range(iterations):
        ascii_count = 0
        lead_count = 0
        separator_count = 0
        for value in text:
            if value < 0x80:
                ascii_count += 1
            elif value & 0xC0 == 0xC0:
                lead_count += 1
            if value in (ord(":"), ord("-"), ord("|"), ord(";")):
                separator_count += 1
            digest = mix(digest, value)
        packed = ascii_count | (lead_count << 20) | (separator_count << 40)
        digest = mix(digest, packed)
    return digest


def small_alloc(iterations: int) -> int:
    digest = HASH_OFFSET
    for index in range(1, iterations + 1):
        size = SIZES[index % len(SIZES)]
        data = bytearray(size)
        if size:
            data[0] = index & 255
            data[-1] = (index >> 8) & 255
            packed = data[0] | (data[-1] << 8) | (size << 16)
            digest = mix(digest, packed)
        else:
            digest = mix(digest, 0)
    return digest


BENCHMARKS = {
    "int64-mix": integer_mix,
    "int32-divmod": signed_divmod,
    "float64-affine": float_affine,
    "byte-scan": byte_scan,
    "move-256": move_256,
    "utf8-scan": utf8_scan,
    "small-alloc": small_alloc,
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("name", choices=[*BENCHMARKS, "all"])
    parser.add_argument("iterations", type=int)
    args = parser.parse_args()
    if args.iterations <= 0:
        parser.error("iterations must be positive")
    names = BENCHMARKS if args.name == "all" else (args.name,)
    for name in names:
        digest = BENCHMARKS[name](args.iterations)
        print(f"ORACLE name={name} iterations={args.iterations} digest={digest:016X}")


if __name__ == "__main__":
    main()
