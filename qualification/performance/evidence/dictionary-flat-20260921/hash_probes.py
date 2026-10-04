#!/usr/bin/env python3
"""hash_probes.py - linear-probing probe counts of candidate flat hashes over
the key populations a dictionary meets, at load 0.5 (the middle of the
0.375..0.75 band the table lives in), for tables from 1 K to 256 K slots.

The table index is the low bits of the 32-bit hash (`AHash and (m - 1)`),
so a hash is judged by what it puts into its low bits.  Reported per hash and
population: average probes of a successful lookup / of a lookup of an absent
key with the same structure.  The last block lists each hash's worst cases.

Candidates: the CRC32C of the key bytes (the default comparer, GF(2)-linear:
perfect on some progressions, collapsing on others), the MurmurHash3 finalizer
(the flat path), Fibonacci multiplication taking bits 32..63 of the 64-bit
product, and multiply-fold variants.  A hash that is perfect on every
arithmetic progression (sequential ids, allocator strides) and never
collapses does not exist: for a stride s the low index bits of a
multiplicative hash only see s * K, and a GF(2)-linear map is injective on a
bit window only when its columns happen to be independent.  The finalizer has
the smallest worst case (2.7 probes) with 1.5/2.5 everywhere, which is the
behaviour class of Delphi's FNV-1a as well.
"""
import random
import struct

M32 = 0xFFFFFFFF
M64 = 0xFFFFFFFFFFFFFFFF
K64 = 0x9E3779B97F4A7C15


def fmix32(x):
    x &= M32
    x ^= x >> 16
    x = (x * 0x85EBCA6B) & M32
    x ^= x >> 13
    x = (x * 0xC2B2AE35) & M32
    x ^= x >> 16
    return x


def fmix64(x):
    x &= M64
    x ^= x >> 33
    x = (x * 0xFF51AFD7ED558CCD) & M64
    x ^= x >> 33
    x = (x * 0xC4CEB9FE1A85EC53) & M64
    x ^= x >> 33
    return x & M32


def crc32c_bytes(data):
    crc = M32
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ (0x82F63B78 if crc & 1 else 0)
    return crc ^ M32


def crc32c4(x):
    return crc32c_bytes(struct.pack('<I', x & M32))


def crc32c8(x):
    return crc32c_bytes(struct.pack('<Q', x & M64))


def fib_hi(k):
    return ((k * K64) & M64) >> 32


def mul_fold(k):
    h = (k * K64) & M64
    h ^= h >> 32
    return h & M32


def mul_fold2(k):
    h = (k * K64) & M64
    h ^= h >> 32
    h = (h * K64) & M64
    h ^= h >> 32
    return h & M32


def probes(hashes, misses, cap):
    table = [None] * cap
    for h in hashes:
        i = h & (cap - 1)
        while table[i] is not None:
            i = (i + 1) & (cap - 1)
        table[i] = h
    hit = 0
    for h in hashes:
        i = h & (cap - 1)
        p = 1
        while table[i] != h:
            i = (i + 1) & (cap - 1)
            p += 1
        hit += p
    miss = 0
    for h in misses:
        i = h & (cap - 1)
        p = 1
        while table[i] is not None and table[i] != h:
            i = (i + 1) & (cap - 1)
            p += 1
        miss += p
    return hit / len(hashes), miss / len(misses)


def populations(n, rng):
    return {
        'int seq 0..n': (list(range(n)), list(range(n, 2 * n))),
        'int seq 1000000+': ([1000000 + i for i in range(n)], [1000000 + n + i for i in range(n)]),
        'int *7919': ([(i * 7919 - 1000000) & M32 for i in range(n)], [((n + i) * 7919 - 1000000) & M32 for i in range(n)]),
        'int *1024': ([i * 1024 for i in range(n)], [(n + i) * 1024 for i in range(n)]),
        'int random': ([rng.getrandbits(32) for _ in range(n)], [rng.getrandbits(32) for _ in range(n)]),
        'i64 seq': (list(range(n)), list(range(n, 2 * n))),
        'i64 *1000003': ([i * 1000003 for i in range(n)], [(n + i) * 1000003 for i in range(n)]),
        'i64 high half only': ([i << 32 for i in range(n)], [(n + i) << 32 for i in range(n)]),
        'ptr stride 32': ([0x1C8A3F40000 + 32 * i for i in range(n)], [0x1C8A3F40000 + 32 * (n + i) for i in range(n)]),
        'ptr stride 64': ([0x1C8A3F40000 + 64 * i for i in range(n)], [0x1C8A3F40000 + 64 * (n + i) for i in range(n)]),
        'ptr stride 32 b2': ([0x2A5B3C7D8E0 + 32 * i for i in range(n)], [0x2A5B3C7D8E0 + 32 * (n + i) for i in range(n)]),
        'ptr allocator-like': ([0x7FF6A2C00000 + 32 * i + 4096 * (i // 100) for i in range(n)],
                               [0x7FF6A2C00000 + 32 * (n + i) + 4096 * ((n + i) // 100) for i in range(n)]),
        'i64 random': ([rng.getrandbits(48) for _ in range(n)], [rng.getrandbits(48) for _ in range(n)]),
    }


HASHES32 = {'crc32c': crc32c4, 'fmix': fmix32, 'fib_hi': fib_hi, 'mul_fold': mul_fold, 'mul_fold2': mul_fold2}
HASHES64 = {'crc32c': crc32c8, 'fmix': fmix64, 'fib_hi': fib_hi, 'mul_fold': mul_fold, 'mul_fold2': mul_fold2}


def main():
    rng = random.Random(3)
    worst = {name: [] for name in HASHES32}
    for n, cap in ((512, 1024), (2048, 4096), (8192, 16384), (32768, 65536), (131072, 262144)):
        print('==== %d keys in %d slots (hit probes / miss probes)' % (n, cap))
        for name, (keys, absent) in populations(n, rng).items():
            hashes = HASHES32 if name.startswith('int') else HASHES64
            row = '%-20s' % name
            for hash_name, f in hashes.items():
                hit, miss = probes([f(k) for k in keys], [f(k) for k in absent], cap)
                worst[hash_name].append((max(hit, miss), '%s@%d' % (name, cap), hit, miss))
                row += '  %s %5.2f/%5.2f' % (hash_name, hit, miss)
            print(row, flush=True)
    print('==== worst cases')
    for name, rows in worst.items():
        rows.sort(reverse=True)
        print('%-10s worst %s   mean hit %.2f miss %.2f' % (
            name, '; '.join('%s %.2f/%.2f' % (r[1], r[2], r[3]) for r in rows[:3]),
            sum(r[2] for r in rows) / len(rows), sum(r[3] for r in rows) / len(rows)))


if __name__ == '__main__':
    main()
