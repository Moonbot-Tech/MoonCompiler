#!/usr/bin/env python3
"""Code placement gate: verify the branch and loop placement rules in a binary.

Rules (R = as implemented by the compiler today, E/Z/T = the corrected
targets measured on the loop maps of 2026-09-15, doc-int/experiments/):

  R4   no jmp/jcc/call/ret (or fused ALU+jcc) crosses or ends on a 32-byte
       boundary (Intel JCC erratum; free on AMD)
  R2   a loop of at most 64 bytes lies inside one 64-byte line
  R2E  R2 when R2 is feasible with R4, and its back-edge does not end on
       byte 29-31 or 62-63 of the line (Zen 3: +25% / +66% even inside one
       line); a 64-byte loop cannot fit one line without its back-edge
       ending on a forbidden R4 boundary, and 63/64-byte loops cannot
       avoid the bad end bytes when inside one line
  R2X  a loop inside one line, or a procedure inside one line, carries no
       padding prefix that no rule needs: every DS prefix on an
       instruction of it must be there for rule 4 of a branch behind it
       in the same loop or procedure (without it that
       branch would cross or end on a 32-byte boundary); a prefix left
       behind by a pad that went away is code the loop executes and
       bytes the loop must find room for (a 44-byte loop kept 3 of them,
       could no longer lie in its line from its natural place and moved a
       line down behind 48 nops: managed-static-array +19% on the stand)
  R3   a longer loop ends in the last 16 bytes of a line (old target)
  R3Z  a loop of 65..120 bytes: its back-edge ends on byte 7..36 of a line
       (66-byte map: the fast zone) - reported only: the zone did not
       transfer to other loop shapes on the stand
  R3H  a loop using long placement (longer than 64 bytes, or 64 bytes
       outside one line) starts on byte 0, 16 or 32 of a line
       (a 16-byte boundary in the first half of the line: never in the
       tail, inside the fast head zones of both maps; the rule-4-only
       stand had heads on 32 and won on every case the end-of-line target
       lost, and the fill to byte 0 costs on every entry)
  R3L  a loop longer than 64 bytes does not use an extra 64-byte line when
       moving its existing bytes to an allowed head (0, 16, 32) proves a
       smaller footprint with R4 and RT still satisfied. A smaller count
       from length alone is diagnostic: required branch/target pads can
       increase the length when the head moves.
  RT   every taken-branch target inside a loop longer than a line (a loop
       inside one line has its whole line fetched anyway) lies in the
       first 52 bytes of its line, when the basic block in front of it can carry the pad
       as prefixes (three per ordinary instruction) or nothing executes
       the place (after a jump or return); a target whose block cannot
       carry the pad is counted as unpaddable, not as a violation (a pad
       of nops in the path cost more than it gained on the stand).  The
       question is put the way the assembler puts it: from the natural
       place of the label (without the nops of a branch pad that stand
       directly in front of it), with instructions that already carry DS
       prefixes not counted as carriers (they carry them for another pad),
       a call or forward jump looked through only when it has no pad of
       its own, no jump target on it, and stays off the 32-byte
       boundaries when moved by what is still needed; a target inside an
       inner loop that lies in one line is exempt whatever loop is around
       (a target in the last 12 bytes shortens the fetch block;
       16-aligned targets at byte 48 were fast in the F stand, 54..60 were not)
  R1   every procedure starts on a 64-byte line (a hand-written routine
       whose author counted bytes from the entry keeps its layout from one
       link to the next only then; a longer compiled procedure used to be
       allowed on 32)
  R1E  every procedure entry is on a 64-byte line (a 32-byte entry halves
       the first fetch block of a hot callee)

Backward jumps that only re-enter exception cleanup (a block ending in a
call to _Unwind_Resume / fpc_reraise, on Linux through the PLT) are not
loops and are skipped; their count is printed with R1E as "unwind
re-entry jumps skipped".

Placement metrics and assertions:

* R4  every jcc/jmp/call/ret, or a macro-fused ALU+jcc pair, must neither
       cross a 32-byte boundary nor end exactly on one;
* R2  reports a loop whose body (head .. end of back-edge) is at most 64
       bytes and does not lie inside one 64-byte line. R2E is the asserted
       form because R4 can make a 64-byte one-line loop impossible;
* R3  reports a longer loop not ending in the last 16 bytes of a 64-byte line (the
       assembler aims at offset 62, one byte before the boundary so that
       the back-edge does not end on a 32-byte boundary, and takes the
       highest offset the branch pads inside leave reachable); a loop that
       contains another loop cannot control its own end (the inner loop
       pins it), so it is counted as an outer loop and skipped by the
       head/end rules; R3H/R3L are the asserted head/footprint forms, with
       R3L requiring a clean relocation witness;
* R1  every procedure starts on a 64-byte boundary.

The gate disassembles the executable with objdump (same sources as
code_placement.py), applies the rules to the procedures selected by
--match / --exclude and prints per-rule counts.  With --assert RULES it
exits non-zero when any selected procedure violates one of the listed rules.
Hand-written assembler routines are not padded by the compiler, so exclude
them (or the whole unit) when asserting.

Usage:
    check_placement_rules.py EXE [--match REGEX ...] [--exclude REGEX ...]
                             [--assert R4,R2,R3,R1] [--list-violations]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))

import code_placement  # noqa: E402

FUSABLE = {"cmp", "test", "add", "sub", "and", "or", "xor", "inc", "dec"}
BRANCHES = {"jmp", "call", "ret", "retq", "loop", "loope", "loopne", "loopz", "loopnz"}
UNWIND_CALLS = ("unwind_resume", "reraise", "raiseexception", "fpc_popaddrstack")
BAD_END_BYTES = {29, 30, 31, 62, 63}


def is_branch(mnemonic: str) -> bool:
    return mnemonic.startswith("j") or mnemonic in BRANCHES


NO_PREFIX = {"tzcnt", "lzcnt", "popcnt", "crc32", "int", "int3", "lock", "nop", "data16", "xchg"}


def is_nop(mnemonic: str, operands: str) -> bool:
    if mnemonic in code_placement.REPEAT_OR_LOCK:
        return False
    mnemonic, operands = code_placement.effective_instruction(mnemonic, operands)
    return mnemonic == "nop" or (mnemonic == "xchg" and operands.replace(" ", "") == "ax,ax")


def prefix_capacity(insns: dict, addresses: list[int], index: int, labels: set[int], needed: int = 12) -> tuple[int, bool]:
    """Prefix bytes the block before addresses[index] can carry, as the
    internal assembler counts them (three per ordinary instruction that does
    not already carry the prefixes of another pad, up to a branch, a jump
    target or a hand-written block; a call or a forward jump is looked
    through when it has no pad of its own and, moved by what is still needed,
    neither crosses nor ends on a 32-byte boundary), and whether the place is
    dead (right after a jump or return)."""
    count = 0
    i = index - 1
    while i >= 0 and count < 32:
        a = addresses[i]
        mnemonic, operands, raw = insns[a]
        mnemonic, operands = code_placement.effective_instruction(mnemonic, operands)
        if is_nop(mnemonic, operands):
            i -= 1
            continue
        if is_branch(mnemonic):
            if count == 0 and mnemonic in ("jmp", "ret", "retq"):
                return 0, True
            need = needed - count * 3
            m = code_placement.BRANCH_TARGET.match(operands) if mnemonic.startswith("j") else None
            forward = m is not None and int(m.group(1), 16) > a
            if mnemonic == "call" or forward:
                # a call or a forward jump, moved by what is still needed, must keep its rule
                # (the fused ALU instruction in front of a jcc is skipped as a carrier)
                start = a
                fused = None
                if mnemonic != "jmp" and mnemonic != "call" and i >= 1:
                    pa = addresses[i - 1]
                    pm, po, pr = insns[pa]
                    if pm in FUSABLE and pa + len(pr) == a:
                        start = pa
                        fused = pa
                stop = a + len(raw)
                # a branch that carries a pad of its own - DS prefixes or nops directly in
                # front of it - is not looked through: the two pads would trade bytes
                # (its prefixes sit on the plain instructions of its own block, its nops
                # directly in front of it or in front of the label its block starts with)
                own_pad = False
                k = i - 1 if fused is None else i - 2
                block_start = start
                while k >= 0:
                    km, ko, kr = insns[addresses[k]]
                    if is_nop(km, ko):
                        own_pad = True
                        break
                    if is_branch(km) or block_start in labels:
                        break
                    if len(kr) > 0 and kr[0] == 0x3E:
                        own_pad = True
                        break
                    block_start = addresses[k]
                    k -= 1
                if need > 0 and not own_pad and ((start + need) // 32) == ((stop + need - 1) // 32) and ((stop + need) % 32) != 0:
                    # a jump target on the looked-through branch (or on the instruction fused
                    # with it) ends the block like any other label
                    if a in labels or start in labels:
                        return count * 3, False
                    i -= 1
                    if fused is not None:
                        i -= 1
                    continue
                return count * 3, False
            return count * 3, (count == 0 and mnemonic in ("jmp", "ret", "retq"))
        if a in labels:
            break
        # A DS-padded instruction carries another pad, not this one.  An operand-size
        # prefix (66), however, does not by itself disqualify an instruction.
        if not (mnemonic in NO_PREFIX or mnemonic.startswith("v") or not operands.strip()
                or any(byte in (0xF0, 0xF2, 0xF3) for byte in code_placement.leading_prefixes(raw))
                or (len(raw) > 0 and raw[0] == 0x3E)):
            count += 1
        i -= 1
    return count * 3, False


def r3l_witness(insns: dict, addresses: list[int], targets: list[int], head: int, body_end: int) -> int | None:
    """A smaller footprint using the same bytes, without pads or short-jump growth."""
    length = body_end - head
    current_lines = (head % 64 + length - 1) // 64 + 1
    body = [a for a in addresses if head <= a < body_end]
    for new_offset in (0, 16, 32):
        if (new_offset + length - 1) // 64 + 1 >= current_lines:
            continue
        delta = new_offset - head % 64
        if any((target + delta) % 64 >= 52 for target in targets if head < target < body_end):
            continue
        # A short branch crossing this body's boundary keeps its other end fixed.
        # If it needs a near encoding after the move, these are not the same bytes.
        short_links_fit = True
        for a in addresses:
            mnemonic, operands, raw = insns[a]
            if not is_branch(mnemonic) or len(raw) != 2:
                continue
            match = code_placement.BRANCH_TARGET.match(operands)
            if match is None:
                continue
            target = int(match.group(1), 16)
            source_inside = head <= a < body_end
            target_inside = head <= target < body_end
            if source_inside == target_inside:
                continue
            new_source = a + delta if source_inside else a
            new_target = target + delta if target_inside else target
            if not -128 <= new_target - (new_source + len(raw)) <= 127:
                short_links_fit = False
                break
        if not short_links_fit:
            continue
        previous = None
        for a in body:
            mnemonic, _, raw = insns[a]
            if is_branch(mnemonic):
                start = a
                if (mnemonic.startswith("j") and mnemonic != "jmp" and previous is not None
                        and previous[1] in FUSABLE and previous[0] + previous[2] == a):
                    start = previous[0]
                stop = a + len(raw)
                if (start + delta) // 32 != (stop + delta - 1) // 32 or (stop + delta) % 32 == 0:
                    break
            previous = (a, mnemonic, len(raw))
        else:
            return new_offset
    return None


def check(exe: Path, patterns: list[str], excludes: list[str]) -> dict[str, object]:
    procedures = code_placement.procedures(exe)
    include = [re.compile(p, re.IGNORECASE) for p in patterns]
    exclude = [re.compile(p, re.IGNORECASE) for p in excludes]
    selected = [
        (name, begin, end) for name, begin, end in procedures
        if (not include or any(r.search(name) for r in include))
        and not any(r.search(name) for r in exclude)
        and not name.startswith(("DEBUGSTART_", "DEBUGEND_"))
    ]
    insns = {address: (*code_placement.effective_instruction(mnemonic, operands), raw)
             for address, (mnemonic, operands, raw) in code_placement.disassemble(exe).items()}
    result = {
        "procedures": len(selected),
        "branches": 0, "R4_violations": [],
        "loops": 0, "short_loops": 0, "R2_violations": [], "R2E_violations": [],
        "R2X_prefixed": 0, "R2X_violations": [],
        "long_loops": 0, "R3_violations": [], "R3Z_loops": 0, "R3Z_violations": [], "R3H_violations": [],
        "R3L_violations": [], "R3L_unproven": [],
        "loop_targets": 0, "RT_violations": [], "RT_unpaddable": 0, "RTU_violations": [],
        "outer_loops": 0, "unwind_jumps": 0,
        "short_procs": 0, "long_procs": 0, "R1_violations": [], "R1E_violations": [],
    }
    for name, begin, end in selected:
        addresses = [a for a in range(begin, end) if a in insns]
        prev = None
        loops: dict[int, int] = {}
        taken_targets: list[int] = []
        unwind_block = False
        for a in addresses:
            mnemonic, operands, raw = insns[a]
            size = len(raw)
            unwind_call = False
            if mnemonic == "call":
                # the symbol of the call target lives next to the instruction
                # table (code_placement.CALL_SYMBOLS): the operands carry only
                # the address, so on Linux, where every unwind call goes
                # through the PLT, the name was never seen and every psabieh
                # landing pad that jumps back into the body counted as a loop
                callee = (operands + " " + code_placement.CALL_SYMBOLS.get(a, "")).lower()
                unwind_call = any(u in callee for u in UNWIND_CALLS)
            if is_branch(mnemonic):
                start = a
                if mnemonic.startswith("j") and mnemonic != "jmp" and prev is not None and prev[1] in FUSABLE and prev[0] + prev[2] == a:
                    start = prev[0]
                stop = a + size  # exclusive
                result["branches"] += 1
                if (start // 32) != ((stop - 1) // 32) or (stop % 32) == 0:
                    result["R4_violations"].append((name, a, start % 32, stop % 32, mnemonic))
                m = code_placement.BRANCH_TARGET.match(operands)
                if m and mnemonic.startswith("j"):
                    target = int(m.group(1), 16)
                    if begin <= target < end:
                        taken_targets.append(target)
                    if begin <= target < a:
                        if mnemonic == "jmp" and unwind_block:
                            result["unwind_jumps"] += 1
                        else:
                            body_end = stop
                            if target not in loops or body_end > loops[target]:
                                loops[target] = body_end
                # a call is a branch too: the flag it raises must survive
                # the reset below, it is the jmp behind the call that is judged
                unwind_block = unwind_call
            prev = (a, mnemonic, size)
        index_of = {a: i for i, a in enumerate(addresses)}
        target_set = set(taken_targets)

        def check_prefixes(name: str, head: int, body_end: int) -> None:
            # R2X: every DS prefix inside a one-line loop or procedure must
            # serve rule 4 of a branch behind it: without these k bytes
            # everything behind them moves up by k, some branch must then
            # cross or end on a 32-byte boundary
            body = [a for a in addresses if head <= a < body_end]
            for idx, a in enumerate(body):
                raw = insns[a][2]
                k = 0
                while k < len(raw) and raw[k] == 0x3E:
                    k += 1
                if k == 0 or is_branch(insns[a][0]):
                    continue
                result["R2X_prefixed"] += 1
                needed = False
                for j in range(idx + 1, len(body)):
                    b = body[j]
                    mn, _, r = insns[b]
                    if not is_branch(mn):
                        continue
                    start = b - k
                    pb = body[j - 1]
                    pm, _, pr = insns[pb]
                    if mn.startswith("j") and mn != "jmp" and pm in FUSABLE and pb + len(pr) == b:
                        start = pb - k if pb != a else a
                    stop = b + len(r) - k
                    if (start // 32) != ((stop - 1) // 32) or (stop % 32) == 0:
                        needed = True
                        break
                if not needed:
                    result["R2X_violations"].append((name, head, a - head, k))

        # a procedure whose own bytes (without its padding prefixes and the
        # nops behind its last instruction) fit a line: every prefix in it
        # must serve rule 4, otherwise the pad may be what pushed it over
        # the line (a 61-byte leaf reached 68 bytes and two fetch blocks)
        if not loops:
            code_end = begin
            prefix_bytes = 0
            for a in addresses:
                mnemonic, _, raw = insns[a]
                if mnemonic in ("nop", "data16") or mnemonic.startswith("nop"):
                    continue
                code_end = a + len(raw)
                k = 0
                while k < len(raw) and raw[k] == 0x3E:
                    k += 1
                if not is_branch(mnemonic):
                    prefix_bytes += k
            if code_end - begin - prefix_bytes <= 64:
                check_prefixes(name, begin, code_end)
        for head, body_end in loops.items():
            result["loops"] += 1
            length = body_end - head
            end_byte = (body_end - 1) % 64
            one_line = (body_end - head) <= 64 and head // 64 == (body_end - 1) // 64
            for target in taken_targets:
                if head < target < body_end:
                    result["loop_targets"] += 1
                    if one_line:
                        continue  # the whole line is fetched anyway: no pad wanted there
                    # ... and the same for a target inside an inner loop that lies in one line,
                    # whatever the loop around it is (the assembler marks the targets of the
                    # inner loop last)
                    if any(h < target < e and (e - h) <= 64 and h // 64 == (e - 1) // 64 for h, e in loops.items()):
                        continue
                    if target % 64 >= 52:
                        # The assembler decides from the natural place of the label: without the
                        # nops of a branch pad that stand directly in front of it (the pad of the
                        # first branch of the target's block).  The pad it would need from there
                        # is what the block in front has to carry, and what a call or jump that
                        # is looked through has to survive.
                        natural = target
                        j = index_of[target] - 1
                        while j >= 0 and is_nop(insns[addresses[j]][0], insns[addresses[j]][1]):
                            natural = addresses[j]
                            j -= 1
                        if j >= 0 and insns[addresses[j]][0] in ("jmp", "ret", "retq"):
                            natural = target      # dead space: those nops are an alignment, not a pad
                        needed = 64 - natural % 64
                        capacity, dead = prefix_capacity(insns, addresses, index_of[target], target_set, needed)
                        if dead or capacity >= needed:
                            result["RT_violations"].append((name, head, target - head, target % 64))
                        else:
                            result["RT_unpaddable"] += 1
                            result["RTU_violations"].append((name, head, target - head, target % 64, capacity))
            if length > 64:
                lines = (head % 64 + length - 1) // 64 + 1
                if lines > (length - 1) // 64 + 1:
                    issue = (name, head, length, head % 64, lines)
                    if r3l_witness(insns, addresses, taken_targets, head, body_end) is None:
                        result["R3L_unproven"].append(issue)
                    else:
                        result["R3L_violations"].append(issue)
            if any(head < other < body_end for other in loops):
                result["outer_loops"] += 1
                continue
            if length <= 64:
                result["short_loops"] += 1
                inside = head // 64 == (body_end - 1) // 64
                if not inside:
                    result["R2_violations"].append((name, head, length, head % 64))
                if (not inside and length < 64) or (inside and end_byte in BAD_END_BYTES and length < 63):
                    result["R2E_violations"].append((name, head, length, head % 64, end_byte))
                if not inside and length == 64 and head % 64 not in (0, 16, 32):
                    result["R3H_violations"].append((name, head, length, head % 64))
                if inside:
                    check_prefixes(name, head, body_end)
            else:
                result["long_loops"] += 1
                if body_end % 64 < 48:
                    result["R3_violations"].append((name, head, length, body_end % 64))
                if head % 64 not in (0, 16, 32):
                    result["R3H_violations"].append((name, head, length, head % 64))
                if length <= 120:
                    result["R3Z_loops"] += 1
                    if not (7 <= end_byte <= 36):
                        result["R3Z_violations"].append((name, head, length, head % 64, end_byte))
        if begin % 64 != 0:
            result["R1E_violations"].append((name, begin, end - begin, begin % 64))
        if end - begin <= 64:
            result["short_procs"] += 1
        else:
            result["long_procs"] += 1
        if begin % 64 != 0:
            result["R1_violations"].append((name, begin, end - begin, begin % 64))
    return result


def assertion_failures(
    result: dict[str, object],
    assert_rules: str,
    expected_violations: list[str],
) -> list[str]:
    failed: list[str] = []
    if assert_rules and result["procedures"] == 0:
        failed.append("no-procedures-selected")
    for rule in (item.strip() for item in assert_rules.split(",")):
        if not rule:
            continue
        name, _, ceiling = rule.partition("=")
        if f"{name}_violations" not in result:
            raise ValueError(f"unknown asserted placement rule: {name}")
        count = len(result[f"{name}_violations"])
        if count > (int(ceiling) if ceiling else 0):
            failed.append(rule if ceiling else name)
    for expectation in expected_violations:
        name, separator, pattern = expectation.partition("=")
        if not separator or not name or not pattern:
            raise ValueError(
                f"bad --expect-violation {expectation!r}; use RULE=REGEX"
            )
        if f"{name}_violations" not in result:
            raise ValueError(f"unknown expected placement rule: {name}")
        matches = [
            item for item in result[f"{name}_violations"]
            if re.search(pattern, str(item[0]), re.IGNORECASE)
        ]
        if len(matches) != 1:
            failed.append(
                f"{name} identity /{pattern}/ matched {len(matches)}"
            )
    return failed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("exe", type=Path)
    parser.add_argument("--match", action="append", default=[])
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--exclude-file", type=Path, action="append", default=[],
                        help="file of regular expressions to exclude, one per line; '#' starts a comment")
    parser.add_argument("--assert", dest="assert_rules", default="",
                        help="rules that must hold, comma separated; RULE=N allows N documented violations")
    parser.add_argument(
        "--expect-violation",
        action="append",
        default=[],
        metavar="RULE=REGEX",
        help="require exactly one documented violation of RULE whose procedure matches REGEX",
    )
    parser.add_argument("--list-violations", action="store_true")
    args = parser.parse_args()
    excludes = list(args.exclude)
    for listing in args.exclude_file:
        for line in listing.read_text(encoding="utf-8").splitlines():
            pattern = line.split(" #", 1)[0].strip()
            if pattern and not pattern.startswith("#"):
                excludes.append(pattern)
    r = check(args.exe.resolve(), args.match, excludes)
    print(f"# {args.exe}")
    print(f"procedures selected: {r['procedures']}")
    print(f"R4 branches: {r['branches']}, crossing/ending on 32B: {len(r['R4_violations'])}")
    print(f"R2 short loops (<=64B): {r['short_loops']}, not inside one 64B line: {len(r['R2_violations'])}")
    print(f"R3 long loops (>64B): {r['long_loops']}, not ending in the last 16B of a line: {len(r['R3_violations'])}"
          f" (outer loops with a loop inside, head/end rules skipped: {r['outer_loops']})")
    print(f"R1 procedures: {r['short_procs']} short (<=64B) + {r['long_procs']} long, "
          f"entry not on a 64B line: {len(r['R1_violations'])}")
    print(f"R2E short loops with avoidable bad back-edge placement: {len(r['R2E_violations'])}")
    print(f"R2X prefixed instructions inside one-line loops and procedures: {r['R2X_prefixed']}, prefixes no rule needs: {len(r['R2X_violations'])}")
    print(f"R3Z loops of 65..120B: {r['R3Z_loops']}, back-edge not ending on byte 7..36 of a line: {len(r['R3Z_violations'])}")
    print(f"R3H long-placement loops whose head is not on byte 0, 16 or 32 of a line: {len(r['R3H_violations'])}")
    print(f"R3L extra-line loops with an R4/RT-clean relocation witness: {len(r['R3L_violations'])}"
          f" (length-only lower bound, no witness: {len(r['R3L_unproven'])})")
    print(f"RT taken-branch targets inside loops: {r['loop_targets']}, in the last 12B of a line: {len(r['RT_violations'])}"
          f" (unpaddable, the block in front cannot carry the prefixes: {r['RT_unpaddable']})")
    print(f"R1E procedure entries not on a 64B line: {len(r['R1E_violations'])}"
          f" (unwind re-entry jumps skipped: {r['unwind_jumps']})")
    if args.list_violations:
        for rule in ("R4", "R2", "R2E", "R2X", "R3", "R3Z", "R3H", "R3L", "RT", "RTU", "R1", "R1E"):
            for item in r[f"{rule}_violations"][:40]:
                print(f"  {rule}: {item}")
        for item in r["R3L_unproven"][:40]:
            print(f"  R3L length-only, no R4/RT-clean relocation witness: {item}")
    # A rule may carry a documented ceiling: --assert R4,RT=2 fails on a
    # third RT violation.  --expect-violation pins the identities below that
    # ceiling, so disappearance of one documented site cannot be replaced by
    # an unrelated regression without failing the gate.
    failed = assertion_failures(r, args.assert_rules, args.expect_violation)
    if failed:
        print(f"PLACEMENT_GATE_FAIL rules={failed}")
        return 1
    if args.assert_rules:
        print("PLACEMENT_GATE_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
