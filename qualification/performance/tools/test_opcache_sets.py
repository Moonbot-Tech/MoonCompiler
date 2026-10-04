"""opcache_sets: the set model on a synthetic image, and its negative controls."""
from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


OPCACHE = load("opcache_sets")
ZEN3 = OPCACHE.CPUS["zen3"]


class FakeImage(OPCACHE.Image):
    """An image from a list of (name, begin, instructions) where every
    instruction is (mnemonic, operands, size); addresses run consecutively."""

    def __init__(self, procedures):
        self.exe = Path("fake.exe")
        self.instructions = {}
        self.procedures = []
        for name, begin, insns in procedures:
            address = begin
            for mnemonic, operands, size in insns:
                self.instructions[address] = (mnemonic, operands, b"\x90" * size)
                address += size
            self.procedures.append((name, begin, address))
        self.procedures.sort(key=lambda p: p[1])
        self.starts = [begin for _, begin, _ in self.procedures]
        self.addresses = sorted(self.instructions)
        self.preferred_base = 0x100000000
        self.entry_points = set(self.starts)
        for address, (mnemonic, operands, raw) in self.instructions.items():
            if mnemonic == "call":
                self.entry_points.add(address + len(raw))
            if mnemonic.startswith("j"):
                match = OPCACHE.cp.BRANCH_TARGET.match(operands)
                if match:
                    self.entry_points.add(int(match.group(1), 16))


def straight(count, size=4):
    return [("mov", "eax,ebx", size)] * count


class SetModelTest(unittest.TestCase):
    def test_entries_count_entry_points_and_ops_per_way(self):
        # 20 instructions of 3 bytes in one 64-byte window with a call in the
        # middle: entry (1) + return address (1) split the window in two runs
        # of 10 and 10 -> ceil(10/8) + ceil(10/8) = 4 entries, 2 entry points
        insns = straight(9, 3) + [("call", "100000fff", 3)] + straight(10, 3)
        image = FakeImage([("F", 0x100001000, insns)])
        instructions, points, entries = image.line_entries(0x100001000, 64, 8)
        self.assertEqual((instructions, points, entries), (20, 2, 4))

    def test_padding_is_not_an_instruction_of_the_window(self):
        insns = straight(4, 4) + [("nop", "", 4)] * 3 + straight(4, 4)
        image = FakeImage([("F", 0x100001000, insns)])
        self.assertEqual(image.line_entries(0x100001000, 64, 8), (11, 1, 1))

    def test_set_index_is_page_offset_of_the_window(self):
        image = FakeImage([
            ("A", 0x1000016c0, straight(4)),
            ("B", 0x1000026c0, straight(4)),   # another page, same offset
            ("C", 0x100001700, straight(4)),   # next window
        ])
        hot = {begin: 1 for _, begin, _ in image.procedures}
        sets = OPCACHE.occupancy(image, hot, ZEN3, {})
        self.assertEqual(sorted(sets), [0x1b, 0x1c])
        self.assertEqual({t["function"] for t in sets[0x1b]}, {"A", "B"})
        self.assertEqual([t["function"] for t in sets[0x1c]], ["C"])

    def test_overflow_and_suggest(self):
        # three windows of four entries each in set 0x1b (21 three-byte
        # instructions, a call in the middle: two runs of ten): 12 > 8 ways
        body = straight(10, 3) + [("call", "100000fff", 3)] + straight(10, 3)
        image = FakeImage([
            ("A", 0x1000016c0, body),
            ("B", 0x1000026c0, body),
            ("C", 0x1000036c0, body),
            ("cold", 0x100004000, straight(4)),
        ])
        hot = {a: 1 for a in image.addresses if a < 0x100004000}
        sets = OPCACHE.occupancy(image, hot, ZEN3, {})
        over = OPCACHE.overflow(sets, ZEN3["ways"])
        self.assertEqual(list(over), [0x1b])
        self.assertGreater(over[0x1b], ZEN3["ways"])
        proposals = OPCACHE.suggest(image, hot, ZEN3, {}, ZEN3["ways"])
        self.assertTrue(proposals)
        self.assertEqual(proposals[0]["shift"], 64)
        # the proposed move really clears the overflow
        begin = next(b for n, b, _ in image.procedures if n == proposals[0]["function"])
        after = OPCACHE.occupancy(image, hot, ZEN3, {begin: proposals[0]["shift"]})
        self.assertEqual(OPCACHE.overflow(after, ZEN3["ways"]), {})

    def test_no_overflow_without_hot_collision(self):
        # negative control: the same three windows in three different sets
        body = straight(10, 3) + [("call", "100000fff", 3)] + straight(10, 3)
        image = FakeImage([
            ("A", 0x1000016c0, body),
            ("B", 0x100002700, body),
            ("C", 0x100003740, body),
        ])
        hot = {a: 1 for a in image.addresses}
        sets = OPCACHE.occupancy(image, hot, ZEN3, {})
        self.assertEqual(OPCACHE.overflow(sets, ZEN3["ways"]), {})
        self.assertEqual(OPCACHE.suggest(image, hot, ZEN3, {}, ZEN3["ways"]), [])

    def test_cold_code_of_a_hot_function_is_not_counted(self):
        # only sampled addresses mark windows: the second window of F is cold
        image = FakeImage([("F", 0x1000016c0, straight(40, 4))])
        hot = {0x1000016c0: 5, 0x1000016c4: 3}
        sets = OPCACHE.occupancy(image, hot, ZEN3, {})
        self.assertEqual(list(sets), [0x1b])
        self.assertEqual(sets[0x1b][0]["samples"], 8)

    def test_skylake_windows_and_cap(self):
        sky = OPCACHE.CPUS["skylake"]
        # 12 instructions of 2 bytes with four branch targets in one 32-byte
        # window: 4 entry points but at most 3 ways per window
        insns = []
        for i in range(12):
            insns.append(("mov", "eax,ebx", 2))
        image = FakeImage([("F", 0x100001000, insns)])
        for offset in (0, 6, 12, 18):
            image.entry_points.add(0x100001000 + offset)
        hot = {a: 1 for a in image.addresses}
        sets = OPCACHE.occupancy(image, hot, sky, {})
        self.assertEqual(list(sets), [(0x100001000 >> 5) & 31])
        self.assertEqual(sets[list(sets)[0]][0]["entries"], 3)


class ProfileParsingTest(unittest.TestCase):
    def test_xperf_rows_are_mapped_through_the_image_load_row(self):
        image = FakeImage([("F", 0x100001000, straight(8, 4))])
        dump = "\n".join([
            "                I-Start,  TimeStamp,     Process Name ( PID),           BaseAddr,            EndAddr,   Checksum, TimeDateStamp,        DefaultBase, FileName, Relocated, NT FileName",
            '                I-Start,     146625,           bench.exe (23276), 0x0000000140000000, 0x0000000140464000, 0x00000000,    0x00000000, 0x0000000100000000, "\\Device\\HarddiskVolume9\\x\\bench.exe", , "\\Device\\HarddiskVolume9\\x\\bench.exe"',
            "         SampledProfile,     147172,           bench.exe (23276),       8084, 0x0000000140001004,   4,           bench.exe!0x0000000100001900,     bench.exe!0x0000000140001004,     1, Unbatched",
            "         SampledProfile,     147173,           bench.exe (23276),       8084, 0x0000000140001004,   4,           bench.exe!0x0000000100001900,     bench.exe!0x0000000140001004,     1, Unbatched",
            "         SampledProfile,     147174,           bench.exe (23276),       8084, 0xfffff800ece957ca,   4,           bench.exe!0x0000000100001900,     ntoskrnl.exe!0xfffff800ece957ca,     1, Unbatched",
            "         SampledProfile,     147175,           other.exe (1),       8084, 0x0000000140001008,   4,           other.exe!0x0,     other.exe!0x0,     1, Unbatched",
        ])
        path = Path(__file__).with_name("_profile_probe.txt")
        path.write_text(dump, encoding="utf-8")
        try:
            hot = OPCACHE.hot_from_profile(image, path, "bench.exe", "xperf")
        finally:
            path.unlink()
        # relocated by 0x40000000: the sampled 0x140001004 is the image's 0x100001004
        self.assertEqual(hot, {0x100001004: 2})

    def test_perf_script_ip_listing(self):
        image = FakeImage([("F", 0x40de00, straight(8, 4))])
        path = Path(__file__).with_name("_perf_probe.txt")
        path.write_text("     ffffffff97c17188\n           40de04\n           40de04\n           40de08\n",
                        encoding="utf-8")
        try:
            hot = OPCACHE.hot_from_profile(image, path, "x", "perf")
        finally:
            path.unlink()
        self.assertEqual(hot, {0xffffffff97c17188: 1, 0x40de04: 2, 0x40de08: 1})
        # kernel addresses fall outside every procedure and are not tenants
        sets = OPCACHE.occupancy(image, hot, ZEN3, {})
        self.assertEqual(list(sets), [(0x40de00 >> 6) & 63])
        self.assertEqual(sets[list(sets)[0]][0]["samples"], 3)


if __name__ == "__main__":
    unittest.main()
