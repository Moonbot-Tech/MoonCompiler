#!/usr/bin/env python3
"""Op-cache set occupancy of the hot code of one executable: which 64-byte
lines of the hot path share a set of the decoded-instruction cache, and which
function has to move to break the collision.

Why.  A hot path that fits the op cache runs from it; when the hot lines of
its functions need more ways of one set than the set has, they evict each
other every iteration and the front end falls back to the decoders (Zen 3:
ICFetch 100 per 1000 cycles instead of 0.3, +20% on the dictionary update
row, `doc-int/experiments/prefix-lab/DICT_REGRESSION.md`).  The set is
selected by address bits inside the page, so the collision depends on where
the linker put each function, not on the instructions: the same bytes at
another page offset run 4% faster than the baseline.  A red row whose code
did not change is therefore first checked here, not in the emitter.

Model.  The op cache is `sets` x `ways`; a 64-byte aligned window maps to set
`(address >> 6) & (sets - 1)` (Zen 2/3/4: 64 sets, 8 ways, bits 6..11 of the
address, i.e. the window's offset inside the 4 KiB page); an entry holds up to
`ops_per_way` consecutive macro-ops of one window and starts where the fetch
enters the window: the function entry, a jump target, the return address
after a call.  A window with k entry points and n instructions needs at least
k entries, and one more for every `ops_per_way` instructions between entry
points.  Intel Skylake/Cascade Lake use 32-byte windows in 32 sets (bits 5..9),
8 ways of 6 uops and at most 3 ways per window (`--cpu skylake`).  The set
count of a real chip may be documented differently; the numbers are the
vendor optimization guides' and the Zen 3 ones were confirmed by the lab
(a function moved to another page at the same offset collides, at another
offset it does not).

Hot lines come from one of:

* `--profile DUMP` - an xperf text dump (`profile_xperf.ps1`; `SampledProfile`
  rows of the process, mapped to the image through its `I-Start`/`I-DCStart`
  row), or a `perf script -F ip` listing on Linux (`--profile-format perf`);
  every sampled instruction pointer marks its line hot, weighted by samples;
* `--hot REGEX` - functions by symbol regex (every line of the function
  counts, weight 1);
* `--pulse RESULT --case NAME` - the measured body of a Pulse case and its
  direct callees from the run manifest (virtual and indirect calls are not
  followed; a profile is exact, this is a first look without one).

Output: every set with its hot lines (function, address, page offset, entry
points, estimated entries) and the sets over `--warn` entries; `--shift
SYMBOL=BYTES` moves a function and reports the occupancy again (what-if for a
placement change), `--suggest` finds, for each overflowing set, the smallest
shift of one of its tenants that empties every overflow.  Compare the two
sides of an A/B with `--json` outputs.

    python opcache_sets.py EXE --hot 'FINDBUCKETINDEX|SETVALUE|HASHFACTORY'
    python opcache_sets.py EXE --profile profile.txt --process dict_bench.exe
    python opcache_sets.py EXE --pulse .qualification/pulse-XXXX --case dictionary/u64-u64-lookup-mixed-10000
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from bisect import bisect_right
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import code_placement as cp  # noqa: E402

CPUS = {
    # sets, ways, window bytes, macro-ops per way, max ways one window may hold
    'zen3': dict(sets=64, ways=8, window=64, ops_per_way=8, ways_per_window=8),
    'zen4': dict(sets=64, ways=8, window=64, ops_per_way=8, ways_per_window=8),
    'skylake': dict(sets=32, ways=8, window=32, ops_per_way=6, ways_per_window=3),
}


class Image:
    def __init__(self, exe: Path):
        self.exe = exe
        self.procedures = sorted(cp.procedures(exe), key=lambda p: p[1])
        self.starts = [begin for _, begin, _ in self.procedures]
        self.instructions = cp.disassemble(exe)
        self.addresses = sorted(self.instructions)
        self.preferred_base = self.read_preferred_base()
        # entry points: function entries, direct branch targets, return addresses
        self.entry_points: set[int] = set(self.starts)
        for address, (mnemonic, operands, raw) in self.instructions.items():
            if mnemonic == 'call':
                self.entry_points.add(address + len(raw))
            if mnemonic.startswith('j') or mnemonic in cp.JUMPS:
                match = cp.BRANCH_TARGET.match(operands)
                if match:
                    self.entry_points.add(int(match.group(1), 16))

    def read_preferred_base(self) -> int:
        data = self.exe.read_bytes()
        if data[:2] == b'MZ':
            pe = int.from_bytes(data[0x3c:0x40], 'little')
            optional = pe + 24
            magic = int.from_bytes(data[optional:optional + 2], 'little')
            if magic == 0x20b:
                return int.from_bytes(data[optional + 24:optional + 32], 'little')
            return int.from_bytes(data[optional + 28:optional + 32], 'little')
        return 0

    def procedure_at(self, address: int):
        position = bisect_right(self.starts, address) - 1
        if position >= 0:
            name, begin, end = self.procedures[position]
            if begin <= address < end:
                return name, begin, end
        return None

    def lines_of(self, begin: int, end: int, window: int) -> list[int]:
        return sorted({address & ~(window - 1) for address in self.addresses
                       if begin <= address < end})

    def line_entries(self, line: int, window: int, ops_per_way: int) -> tuple[int, int, int]:
        """(instructions, entry points, estimated entries) of one window."""
        addresses = [a for a in self.addresses if line <= a < line + window]
        if not addresses:
            return 0, 0, 0
        entries = 0
        run = 0
        points = 0
        for address in addresses:
            mnemonic, operands, raw = self.instructions[address]
            if cp.is_padding(mnemonic, operands):
                continue
            if address in self.entry_points:
                points += 1
                if run:
                    entries += -(-run // ops_per_way)
                run = 0
            run += 1
        if run:
            entries += -(-run // ops_per_way)
        return len(addresses), points, max(entries, 1)


def hot_from_profile(image: Image, path: Path, process: str, fmt: str) -> dict[int, int]:
    """line -> samples for the image's own code."""
    counts: dict[int, int] = defaultdict(int)
    if fmt == 'perf':
        for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
            match = re.search(r'\b([0-9a-f]{6,16})\b', line)
            if match:
                counts[int(match.group(1), 16)] += 1
        return dict(counts)
    base = None
    limit = None
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        fields = [f.strip() for f in line.split(',')]
        if len(fields) < 9:
            continue
        if fields[0] in ('I-Start', 'I-DCStart') and process.lower() in fields[2].lower():
            if process.lower() in fields[8].lower().replace('"', ''):
                base = int(fields[3], 16)
                limit = int(fields[4], 16)
        elif fields[0] == 'SampledProfile' and process.lower() in fields[2].lower():
            try:
                pc = int(fields[4], 16)
            except ValueError:
                continue
            if base is not None and base <= pc < limit:
                counts[pc - base + image.preferred_base] += 1
    if base is None:
        raise SystemExit(f'{path}: no image load row of {process}; record with PROC_THREAD+LOADER+PROFILE')
    return dict(counts)


def hot_from_symbols(image: Image, patterns: list[str]) -> dict[int, int]:
    regex = [re.compile(p, re.I) for p in patterns]
    counts: dict[int, int] = {}
    for name, begin, end in image.procedures:
        if any(r.search(name) for r in regex):
            for address in image.addresses:
                if begin <= address < end:
                    counts[address] = counts.get(address, 0) + 1
    if not counts:
        raise SystemExit('no procedure matches ' + ', '.join(patterns))
    return counts


def hot_from_pulse(image: Image, result: Path, case: str) -> dict[int, int]:
    import pulse  # noqa: WPS433 - the Pulse manifest reader lives beside this tool
    collected, manifest = pulse.collect(result)
    rows = [(key, row) for key, row in collected.items()
            if f'{key[1]}/{key[2]}' == case or key[2] == case]
    if not rows:
        raise SystemExit(f'{result}: no measured row for case {case}')
    anchors = [begin for name, begin, _ in image.procedures
               if 'PULSE_HARNESS' in name.upper() and '_$$_PULSERUNCASE$' in name.upper()]
    if len(anchors) != 1:
        raise SystemExit(f'{image.exe}: missing or ambiguous PulseRunCase anchor')
    counts: dict[int, int] = {}
    seen = set()
    for key, row in rows:
        for offset in row['body_offsets'][:1]:
            body = anchors[0] + offset
            proc = image.procedure_at(body)
            if proc is None:
                raise SystemExit(f'{case}: measured body {body:x} is not inside a procedure')
            queue = [proc]
            while queue:
                name, begin, end = queue.pop()
                if begin in seen:
                    continue
                seen.add(begin)
                for address in image.addresses:
                    if begin <= address < end:
                        counts[address] = counts.get(address, 0) + 1
                        mnemonic, operands, raw = image.instructions[address]
                        if mnemonic == 'call':
                            match = cp.BRANCH_TARGET.match(operands)
                            if match:
                                callee = image.procedure_at(int(match.group(1), 16))
                                if callee and callee[1] not in seen:
                                    queue.append(callee)
    return counts


def occupancy(image: Image, hot: dict[int, int], cpu: dict, shifts: dict[int, int]) -> dict[int, list[dict]]:
    """set -> tenants (one per hot window), after moving functions by `shifts` (begin -> bytes)."""
    window = cpu['window']
    lines: dict[int, dict] = {}
    for address, weight in hot.items():
        proc = image.procedure_at(address)
        if proc is None:
            continue
        name, begin, end = proc
        shift = shifts.get(begin, 0)
        line = (address + shift) & ~(window - 1)
        source_line = address & ~(window - 1)
        tenant = lines.get(line)
        if tenant is None:
            instructions, points, entries = image.line_entries(source_line, window, cpu['ops_per_way'])
            entries = min(entries, cpu['ways_per_window'])
            tenant = lines[line] = dict(line=line, function=name, offset=source_line - begin,
                                        page_offset=line & 0xfff, instructions=instructions,
                                        entry_points=points, entries=entries, samples=0,
                                        shifted=shift)
        tenant['samples'] += weight
    sets: dict[int, list[dict]] = defaultdict(list)
    for tenant in lines.values():
        index = (tenant['line'] >> window.bit_length() - 1) & (cpu['sets'] - 1)
        sets[index].append(tenant)
    for tenants in sets.values():
        tenants.sort(key=lambda t: -t['samples'])
    return dict(sets)


def overflow(sets: dict[int, list[dict]], limit: int) -> dict[int, int]:
    return {index: sum(t['entries'] for t in tenants)
            for index, tenants in sets.items() if sum(t['entries'] for t in tenants) > limit}


def suggest(image: Image, hot: dict[int, int], cpu: dict, shifts: dict[int, int], warn: int) -> list[dict]:
    base_sets = occupancy(image, hot, cpu, shifts)
    over = overflow(base_sets, warn)
    if not over:
        return []
    proposals = []
    tenants = {t['function']: t for index in over for t in base_sets[index]}
    functions = {name: begin for name, begin, _ in image.procedures if name in tenants}
    for name, begin in sorted(functions.items()):
        for steps in range(1, cpu['sets']):
            trial = dict(shifts)
            trial[begin] = trial.get(begin, 0) + steps * cpu['window']
            if not overflow(occupancy(image, hot, cpu, trial), warn):
                proposals.append(dict(function=name, shift=steps * cpu['window']))
                break
    proposals.sort(key=lambda p: p['shift'])
    return proposals


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('exe', type=Path)
    parser.add_argument('--cpu', choices=sorted(CPUS), default='zen3')
    parser.add_argument('--profile', type=Path, help='xperf dumper text or perf script listing')
    parser.add_argument('--profile-format', choices=('xperf', 'perf'), default='xperf')
    parser.add_argument('--process', help='process name in the xperf dump (default: the exe file name)')
    parser.add_argument('--hot', action='append', default=[], help='symbol regex of a hot function (repeatable, | inside)')
    parser.add_argument('--pulse', type=Path, help='Pulse result directory (with --case)')
    parser.add_argument('--case', help='program/case of the Pulse result')
    parser.add_argument('--min-samples', type=int, default=1,
                        help='profile: ignore lines with fewer samples (noise floor)')
    parser.add_argument('--warn', type=int, help='flag sets whose hot entries exceed this (default: the ways of the set)')
    parser.add_argument('--shift', action='append', default=[], help='SYMBOL=BYTES: move a function before counting')
    parser.add_argument('--suggest', action='store_true', help='find the smallest single-function move that clears every overflow')
    parser.add_argument('--json', type=Path, help='write the occupancy report')
    args = parser.parse_args()

    cpu = CPUS[args.cpu]
    warn = args.warn if args.warn is not None else cpu['ways']
    image = Image(args.exe)
    hot: dict[int, int] = {}
    if args.profile:
        hot.update(hot_from_profile(image, args.profile, args.process or args.exe.name, args.profile_format))
        total = sum(hot.values())
        hot = {a: n for a, n in hot.items() if n >= args.min_samples}
        print(f'profile: {total} samples inside {args.exe.name}, {len(hot)} sampled addresses kept')
    if args.hot:
        hot.update(hot_from_symbols(image, args.hot))
    if args.pulse:
        if not args.case:
            raise SystemExit('--pulse needs --case')
        hot.update(hot_from_pulse(image, args.pulse, args.case))
    if not hot:
        raise SystemExit('nothing marks the hot code: give --profile, --hot or --pulse/--case')
    orphans = [a for a in hot if image.procedure_at(a) is None]
    if orphans:
        print(f'{len(orphans)} of {len(hot)} hot addresses lie outside every known procedure '
              f'(first {min(orphans):x}); the image needs symbols (-gw3) and the profile must be its own')
        if len(orphans) == len(hot):
            raise SystemExit('no hot address maps to a procedure of ' + args.exe.name)

    shifts: dict[int, int] = {}
    for spec in args.shift:
        symbol, _, amount = spec.partition('=')
        matches = [begin for name, begin, _ in image.procedures if re.search(symbol, name, re.I)]
        if len(matches) != 1:
            raise SystemExit(f'--shift {symbol}: {len(matches)} procedures match')
        shifts[matches[0]] = int(amount, 0)

    sets = occupancy(image, hot, cpu, shifts)
    over = overflow(sets, warn)
    print(f'{args.exe.name}: {args.cpu} op cache {cpu["sets"]} sets x {cpu["ways"]} ways, '
          f'{cpu["window"]}-byte windows; hot windows {sum(len(t) for t in sets.values())}, '
          f'sets used {len(sets)}, sets over {warn} entries: {len(over)}')
    for index in sorted(sets, key=lambda i: (-sum(t["entries"] for t in sets[i]), i)):
        tenants = sets[index]
        entries = sum(t['entries'] for t in tenants)
        flag = '  <-- OVERFLOW' if index in over else ('  (full)' if entries == warn else '')
        print(f'set {index:02x}: {entries} entries in {len(tenants)} hot windows{flag}')
        for t in tenants:
            moved = f' (moved {t["shifted"]:+d})' if t['shifted'] else ''
            print(f'    {t["line"]:x} page+{t["page_offset"]:03x}  {t["function"]}{t["offset"]:+x}{moved}: '
                  f'{t["instructions"]} insns, {t["entry_points"]} entry points, {t["entries"]} entries, '
                  f'{t["samples"]} samples')
    if args.suggest:
        proposals = suggest(image, hot, cpu, shifts, warn)
        if not proposals and over:
            print('suggest: no single-function move clears every overflow')
        for p in proposals:
            print(f'suggest: move {p["function"]} by {p["shift"]:+d} bytes')
    if args.json:
        report = dict(exe=str(args.exe), cpu=args.cpu, warn=warn,
                      sets={f'{i:02x}': t for i, t in sets.items()},
                      overflow={f'{i:02x}': n for i, n in over.items()},
                      shifts={f'{b:x}': s for b, s in shifts.items()})
        args.json.write_text(json.dumps(report, indent=1), encoding='utf-8')
    return 1 if over else 0


if __name__ == '__main__':
    raise SystemExit(main())
