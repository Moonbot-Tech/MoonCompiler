"""No case loop reloads a global: the judge on a synthetic image, then on the corpus as the tree builds it."""
from __future__ import annotations

import functools
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_case_loads as judge
import code_placement as cp
import pulse

ANCHOR = "PULSE_HARNESS_$$_PULSERUNCASE$TEST"
# CaseMove of r7 in miniature: the size reloaded from a global (.bss + 0x50) in the loop.
RELOADED = """
    1000:\t41 89 cc             \tmov    r12d,ecx
    1003:\t4c 8b 05 46 40 00 00 \tmov    r8,QWORD PTR [rip+0x4046]        # 5050 <U_$P$T_$$_ACTIVESIZE>
    100a:\te8 f1 ff ff ff       \tcall   1000 <FPC_MOVE>
    100f:\t41 83 ec 01          \tsub    r12d,0x1
    1013:\t75 ee                \tjne    1003 <CASE+0x3>
    1015:\tc3                   \tret
"""
# r8: read once before the loop, the loop keeps it in a register.
HOISTED = """
    1000:\t4c 8b 2d 49 40 00 00 \tmov    r13,QWORD PTR [rip+0x4049]        # 5050 <U_$P$T_$$_ACTIVESIZE>
    1007:\t41 89 cc             \tmov    r12d,ecx
    100a:\t4d 89 e8             \tmov    r8,r13
    100d:\te8 ee ff ff ff       \tcall   1000 <FPC_MOVE>
    1012:\t41 83 ec 01          \tsub    r12d,0x1
    1016:\t75 f2                \tjne    100a <CASE+0xa>
    1018:\tc3                   \tret
"""
# ELF without PIC: the array's address relocated into the instruction beside the index the loop
# steps - an element per pass, the case walking its data (the linker relocated 0x1006, 4 bytes).
ELF_WALK = """
    1000:\t31 c0                \txor    eax,eax
    1002:\t48 8b 0c c5 b0 50 00 00 \tmov    rcx,QWORD PTR [rax*8+0x50b0]
    100a:\t48 01 ce             \tadd    rsi,rcx
    100d:\t83 c0 01             \tadd    eax,0x1
    1010:\t83 f8 3f             \tcmp    eax,0x3f
    1013:\t7e ed                \tjle    1002 <CASE+0x2>
    1015:\tc3                   \tret
"""
# The same element with an index the loop does not write: one address on every pass (reloc 0x1009).
ELF_SAME_ELEMENT = """
    1000:\tb8 05 00 00 00       \tmov    eax,0x5
    1005:\t48 8b 0c c5 b0 50 00 00 \tmov    rcx,QWORD PTR [rax*8+0x50b0]
    100d:\t48 01 ce             \tadd    rsi,rcx
    1010:\t83 ea 01             \tsub    edx,0x1
    1013:\t75 f0                \tjne    1005 <CASE+0x5>
    1015:\tc3                   \tret
"""
# The key the inner loop reads on every pass: its index recomputed from the outer counter (reloc 0x1014).
ELF_SAME_KEY = """
    1000:\t45 31 ed             \txor    r13d,r13d
    1003:\t41 83 c5 01          \tadd    r13d,0x1
    1007:\t45 31 e4             \txor    r12d,r12d
    100a:\t44 89 e8             \tmov    eax,r13d
    100d:\t83 e0 0f             \tand    eax,0xf
    1010:\t48 8b 34 c5 b0 50 00 00 \tmov    rsi,QWORD PTR [rax*8+0x50b0]
    1018:\t41 83 c4 01          \tadd    r12d,0x1
    101c:\t41 83 fc 3f          \tcmp    r12d,0x3f
    1020:\t7e e8                \tjle    100a <CASE+0xa>
    1022:\t44 39 ef             \tcmp    edi,r13d
    1025:\t7f dc                \tjg     1003 <CASE+0x3>
    1027:\tc3                   \tret
"""
# CaseMove16 on Linux: every pass loads the global's address with movabs (reloc 0x1004, 8 bytes).
ELF_MOVABS = """
    1000:\t89 f8                \tmov    eax,edi
    1002:\t48 ba 50 50 00 00 00 00 00 00 \tmovabs rdx,0x5050
    100c:\t48 8b 0a             \tmov    rcx,QWORD PTR [rdx]
    100f:\t83 e8 01             \tsub    eax,0x1
    1012:\t75 ee                \tjne    1002 <CASE+0x2>
    1014:\tc3                   \tret
"""
# A pointer the loop steps through the array from its address (reloc 0x1002, 8 bytes).
ELF_POINTER_WALK = """
    1000:\t48 b9 b0 50 00 00 00 00 00 00 \tmovabs rcx,0x50b0
    100a:\t8b 31                \tmov    esi,DWORD PTR [rcx]
    100c:\t48 83 c1 04          \tadd    rcx,0x4
    1010:\t83 ea 01             \tsub    edx,0x1
    1013:\t75 f5                \tjne    100a <CASE+0xa>
    1015:\tc3                   \tret
"""
# Win64: the address taken by lea before the loop into a register the call keeps.
PE_ADDRESS_KEPT = """
    1000:\t48 8d 1d 49 40 00 00 \tlea    rbx,[rip+0x4049]        # 5050 <U_$P$T_$$_ACTIVESIZE>
    1007:\te8 f4 ff ff ff       \tcall   1000 <FPC_MOVE>
    100c:\t8b 13                \tmov    edx,DWORD PTR [rbx]
    100e:\t83 ef 01             \tsub    edi,0x1
    1011:\t75 f4                \tjne    1007 <CASE+0x7>
    1013:\tc3                   \tret
"""
# A loop entered at its condition: the address the body loads through is taken after the load, for the
# next pass.
PE_ROTATED = """
    1000:\teb 0e                \tjmp    1010 <CASE+0x10>
    1002:\t8b 13                \tmov    edx,DWORD PTR [rbx]
    1004:\t01 d0                \tadd    eax,edx
    1006:\t83 c1 01             \tadd    ecx,0x1
    1009:\t0f 1f 80 00 00 00 00 \tnop    DWORD PTR [rax+0x0]
    1010:\t48 8d 1d 39 40 00 00 \tlea    rbx,[rip+0x4039]        # 5050 <U_$P$T_$$_ACTIVESIZE>
    1017:\t83 f9 3f             \tcmp    ecx,0x3f
    101a:\t7e e6                \tjle    1002 <CASE+0x2>
    101c:\tc3                   \tret
"""
# The key of the pass computed with lea from the outer counter the inner loop keeps (reloc 0x1012).
ELF_LEA_KEY = """
    1000:\t45 31 ed             \txor    r13d,r13d
    1003:\t41 83 c5 01          \tadd    r13d,0x1
    1007:\t45 31 e4             \txor    r12d,r12d
    100a:\t41 8d 45 01          \tlea    eax,[r13+0x1]
    100e:\t48 8b 34 c5 b0 50 00 00 \tmov    rsi,QWORD PTR [rax*8+0x50b0]
    1016:\t41 83 c4 01          \tadd    r12d,0x1
    101a:\t41 83 fc 3f          \tcmp    r12d,0x3f
    101e:\t7e ea                \tjle    100a <CASE+0xa>
    1020:\t44 39 ef             \tcmp    edi,r13d
    1023:\t7f de                \tjg     1003 <CASE+0x3>
    1025:\tc3                   \tret
"""
# The same, widened with cdqe (reloc 0x1013).
ELF_CDQE_KEY = """
    1000:\t45 31 ed             \txor    r13d,r13d
    1003:\t41 83 c5 01          \tadd    r13d,0x1
    1007:\t45 31 e4             \txor    r12d,r12d
    100a:\t44 89 e8             \tmov    eax,r13d
    100d:\t48 98                \tcdqe
    100f:\t48 8b 34 c5 b0 50 00 00 \tmov    rsi,QWORD PTR [rax*8+0x50b0]
    1017:\t41 83 c4 01          \tadd    r12d,0x1
    101b:\t41 83 fc 3f          \tcmp    r12d,0x3f
    101f:\t7e e9                \tjle    100a <CASE+0xa>
    1021:\t44 39 ef             \tcmp    edi,r13d
    1024:\t7f dd                \tjg     1003 <CASE+0x3>
    1026:\tc3                   \tret
"""
# Win64: the first element, its index zeroed on every pass.
PE_ZEROED = """
    1000:\t48 8d 1d 49 40 00 00 \tlea    rbx,[rip+0x4049]        # 5050 <U_$P$T_$$_ACTIVESIZE>
    1007:\t31 c0                \txor    eax,eax
    1009:\t8b 14 83             \tmov    edx,DWORD PTR [rbx+rax*4]
    100c:\t83 ef 01             \tsub    edi,0x1
    100f:\t75 f6                \tjne    1007 <CASE+0x7>
    1011:\tc3                   \tret
"""
# The outer counter kept in the frame, [rsp+0x28], read on every pass of the inner loop (reloc 0x1018).
ELF_FRAME_KEY = """
    1000:\tc7 44 24 28 00 00 00 00 \tmov    DWORD PTR [rsp+0x28],0x0
    1008:\t83 44 24 28 01       \tadd    DWORD PTR [rsp+0x28],0x1
    100d:\t45 31 e4             \txor    r12d,r12d
    1010:\t8b 44 24 28          \tmov    eax,DWORD PTR [rsp+0x28]
    1014:\t48 8b 34 c5 b0 50 00 00 \tmov    rsi,QWORD PTR [rax*8+0x50b0]
    101c:\t41 83 c4 01          \tadd    r12d,0x1
    1020:\t41 83 fc 3f          \tcmp    r12d,0x3f
    1024:\t7e ea                \tjle    1010 <CASE+0x10>
    1026:\t39 7c 24 28          \tcmp    DWORD PTR [rsp+0x28],edi
    102a:\t7c dc                \tjl     1008 <CASE+0x8>
    102c:\tc3                   \tret
"""
SYMBOLS = {0x5050: "U_$P$T_$$_ACTIVESIZE", 0x50b0: "U_$P$T_$$_INPUT"}


def loads(disassembly: str, relocations: dict[int, int] | None = None, elf: bool = False) -> list[dict[str, object]]:
    procedures = [("P$T_$$_CASE", 0x1000, 0x1040), (ANCHOR, 0x2000, 0x2100)]
    with mock.patch.object(cp, "procedures", return_value=procedures), \
         mock.patch.object(judge, "case_bodies", return_value=[("hot-a0-a0-n128", 0x1000 - 0x2000)]), \
         mock.patch.object(judge, "data_sections", return_value=[(".bss", 0x5000, 0x6000)]), \
         mock.patch.object(judge, "symbols", return_value=(sorted(SYMBOLS), SYMBOLS)), \
         mock.patch.object(judge.linked_image, "absolute_relocations", return_value=relocations or {}), \
         mock.patch.object(judge, "is_elf", return_value=elf), \
         mock.patch.object(cp, "tool", return_value="objdump"), \
         mock.patch.object(cp, "run", return_value=disassembly):
        return judge.loop_loads(Path("pulse_t.exe"))


class CaseLoopLoadTests(unittest.TestCase):
    def test_a_global_reloaded_in_the_loop_is_found_and_one_read_before_it_is_not(self) -> None:
        [load] = loads(RELOADED)
        self.assertEqual((load["global"], load["page_offset"], load["loop"]), ("U_$P$T_$$_ACTIVESIZE", 0x050, 0x1003))
        self.assertEqual(load["cases"], ["hot-a0-a0-n128"])
        self.assertEqual(loads(HOISTED), [])

    def test_an_address_the_loop_moves_is_its_data_and_one_it_keeps_is_a_reload(self) -> None:
        self.assertEqual(loads(ELF_WALK, {0x1006: 4}, elf=True), [])
        self.assertEqual(loads(ELF_POINTER_WALK, {0x1002: 8}, elf=True), [])
        [load] = loads(ELF_SAME_ELEMENT, {0x1009: 4}, elf=True)
        self.assertEqual((load["global"], load["address"], load["loop"]), ("U_$P$T_$$_INPUT", 0x1005, 0x1005))
        [load] = loads(ELF_SAME_KEY, {0x1014: 4}, elf=True)
        self.assertEqual((load["global"], load["address"], load["loop"]), ("U_$P$T_$$_INPUT", 0x1010, 0x100A))
        walked = ELF_SAME_KEY.replace("mov    eax,r13d", "mov    eax,r12d").replace("44 89 e8", "44 89 e0")
        self.assertEqual(loads(walked, {0x1014: 4}, elf=True), [])
        [load] = loads(ELF_MOVABS, {0x1004: 8}, elf=True)
        self.assertEqual((load["global"], load["offset"], load["address"]), ("U_$P$T_$$_ACTIVESIZE", 0, 0x100C))
        [load] = loads(PE_ADDRESS_KEPT)
        self.assertEqual((load["global"], load["address"]), ("U_$P$T_$$_ACTIVESIZE", 0x100C))
        # A register the call clobbers holds no address after it.
        clobbered = PE_ADDRESS_KEPT.replace("lea    rbx", "lea    rcx").replace("[rbx]", "[rcx]")
        self.assertEqual(loads(clobbered), [])
        [load] = loads(PE_ROTATED)
        self.assertEqual((load["global"], load["address"], load["loop"]), ("U_$P$T_$$_ACTIVESIZE", 0x1002, 0x1002))
        # The same loop stepping the register instead: a walk.
        stepped = PE_ROTATED.replace(
            "48 8d 1d 39 40 00 00 \tlea    rbx,[rip+0x4039]        # 5050 <U_$P$T_$$_ACTIVESIZE>",
            "48 83 c3 04          \tadd    rbx,0x4\n    1014:\t0f 1f 00             \tnop    DWORD PTR [rax]")
        self.assertEqual(loads(stepped), [])

    def test_an_index_computed_again_or_kept_in_the_frame_keeps_its_address(self) -> None:
        # lea and cdqe from the outer counter the inner loop keeps: one element on every pass.
        for text, at, reloc in ((ELF_LEA_KEY, 0x100E, 0x1012), (ELF_CDQE_KEY, 0x100F, 0x1013)):
            with self.subTest(at=at):
                [load] = loads(text, {reloc: 4}, elf=True)
                self.assertEqual((load["global"], load["address"], load["loop"]), ("U_$P$T_$$_INPUT", at, 0x100A))
        # The inner loop steps the register lea reads: a walk.
        walked = ELF_LEA_KEY.replace("41 83 c4 01          \tadd    r12d,0x1",
                                     "41 83 c5 01          \tadd    r13d,0x1")
        self.assertEqual(loads(walked, {0x1012: 4}, elf=True), [])
        [load] = loads(PE_ZEROED)
        self.assertEqual((load["global"], load["offset"], load["address"]), ("U_$P$T_$$_ACTIVESIZE", 0, 0x1009))
        stepped = PE_ZEROED.replace("31 c0                \txor    eax,eax", "ff c0                \tinc    eax")
        self.assertEqual(loads(stepped), [])
        [load] = loads(ELF_FRAME_KEY, {0x1018: 4}, elf=True)
        self.assertEqual((load["global"], load["address"], load["loop"]), ("U_$P$T_$$_INPUT", 0x1014, 0x1010))
        # A local above the slot whose address is taken cannot reach it.
        above = ELF_FRAME_KEY.replace("c7 44 24 28 00 00 00 00 \tmov    DWORD PTR [rsp+0x28],0x0",
                                      "48 8d 4c 24 30 0f 1f 00 \tlea    rcx,[rsp+0x30]")
        self.assertEqual(len(loads(above, {0x1018: 4}, elf=True)), 1)
        # The inner loop steps the slot itself, the address of the slot or of a local below it is taken (a
        # record over it), or the index comes from other memory: the address moves or may move.
        for old, new in (("41 83 c4 01          \tadd    r12d,0x1",
                          "ff 44 24 28          \tinc    DWORD PTR [rsp+0x28]"),
                         ("c7 44 24 28 00 00 00 00 \tmov    DWORD PTR [rsp+0x28],0x0",
                          "48 8d 4c 24 28 0f 1f 00 \tlea    rcx,[rsp+0x28]"),
                         ("c7 44 24 28 00 00 00 00 \tmov    DWORD PTR [rsp+0x28],0x0",
                          "48 8d 4c 24 10 0f 1f 00 \tlea    rcx,[rsp+0x10]"),
                         ("8b 44 24 28          \tmov    eax,DWORD PTR [rsp+0x28]",
                          "8b 43 08 90          \tmov    eax,DWORD PTR [rbx+0x8]")):
            with self.subTest(new=new):
                self.assertEqual(loads(ELF_FRAME_KEY.replace(old, new), {0x1018: 4}, elf=True), [])

    def test_the_registers_an_instruction_writes(self) -> None:
        for mnemonic, operands, elf, written in (
            ("mov", "rcx,QWORD PTR [rdx]", False, {"rcx"}), ("movabs", "rdx,0x5050", True, {"rdx"}),
            ("add", "eax,0x1", False, {"rax"}), ("cmp", "eax,0x3f", False, set()), ("test", "rcx,rcx", False, set()),
            ("bt", "eax,0x1", False, set()), ("bts", "eax,0x1", False, {"rax"}), ("push", "rbx", False, set()),
            ("mul", "rcx", False, {"rax", "rdx"}), ("div", "rcx", False, {"rax", "rdx"}),
            ("imul", "rcx", False, {"rax", "rdx"}), ("imul", "rcx,rdx", False, {"rcx"}),
            ("mulsd", "xmm0,QWORD PTR [rdx]", False, set()), ("movsd", "xmm0,QWORD PTR [rcx]", False, set()),
            ("xchg", "rax,rbx", False, {"rax", "rbx"}), ("xchg", "ax,ax", False, set()),
            ("call", "1000 <FPC_MOVE>", False, {"rax", "rcx", "rdx", "r8", "r9", "r10", "r11"}),
            ("call", "1000 <FPC_MOVE>", True, {"rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"}),
            ("rep", "stos QWORD PTR es:[rdi],rax", False, {"rax", "rcx", "rsi", "rdi"}),
            ("cqo", "", False, {"rdx"}), ("setne", "r12b", False, {"r12"}), ("jne", "1002 <CASE+0x2>", False, set()),
        ):
            with self.subTest(mnemonic=mnemonic, operands=operands):
                self.assertEqual(judge.written_registers(mnemonic, operands, elf), written)

    def test_only_reads_count(self) -> None:
        for operands, mnemonic, read in (
            ("r8,QWORD PTR [rip+0x10]", "mov", True), ("QWORD PTR [rip+0x10],r8", "mov", False),
            ("XMMWORD PTR [rdx],xmm0", "movups", False), ("YMMWORD PTR [rdx+rax*1-0x20],ymm1", "vmovdqu", False),
            ("QWORD PTR [rip+0x10],rax", "add", True), ("BYTE PTR [rip+0x1],0x1", "cmp", True),
            ("QWORD PTR [rip+0x8]", "call", True), ("QWORD PTR [rip+0x8]", "fld", True),
            ("QWORD PTR [rip+0x8]", "fstp", False), ("BYTE PTR [rip+0x10]", "setne", False),
            ("eax,DWORD PTR ds:0x4b1234", "mov", True), ("DWORD PTR ds:0x4b1234,eax", "mov", False),
            ("rcx,[rip+0x10]", "lea", False), ("WORD PTR [rax+rax*1+0x0]", "nop", False),
        ):
            with self.subTest(mnemonic=mnemonic, operands=operands):
                self.assertEqual(judge.reads_memory(mnemonic, operands), read)

    def test_the_allow_list_names_what_stays_and_goes_stale_with_it(self) -> None:
        found = [{"procedure": "P$T_$$_CASE", "global": "U_$P$T_$$_INPUT", "offset": 0, "page_offset": 0x60,
                  "address": 0x1003, "loop": 0x1003, "cases": ["c"], "instruction": "mov"}]
        with tempfile.TemporaryDirectory() as temporary:
            allow = Path(temporary) / "allow.txt"
            for text, failures in (
                ("t P$T_$$_CASE U_$P$T_$$_INPUT  # case input\n", []),
                ("", ["CASE_LOOP_LOAD t"]),
                ("t P$T_$$_CASE U_$P$T_$$_INPUT  # case input\nt P$T_$$_CASE U_$P$T_$$_GONE  # was\n",
                 ["CASE_LOOP_ALLOW_STALE t P$T_$$_CASE U_$P$T_$$_GONE"]),
                ("t P$T_$$_CASE U_$P$T_$$_INPUT  # case input\nother P$O_$$_CASE U_$P$O_$$_X  # another program\n",
                 []),
            ):
                with self.subTest(allow=text):
                    allow.write_text(text, encoding="utf-8")
                    with mock.patch.object(judge, "loop_loads", return_value=found):
                        result = judge.check([Path("pulse_t.exe")], allow)
                    self.assertEqual(len(result), len(failures), result)
                    for line, prefix in zip(result, failures):
                        self.assertTrue(line.startswith(prefix), line)
            allow.write_text("t P$T_$$_CASE U_$P$T_$$_INPUT\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "# why"):
                judge.check([Path("pulse_t.exe")], allow)
            allow.write_text("", encoding="utf-8")
            overlay = Path(temporary) / "overlay.txt"
            overlay.write_text("t P$T_$$_CASE U_$P$T_$$_INPUT  # indexed case data\n", encoding="utf-8")
            with mock.patch.object(judge, "loop_loads", return_value=found):
                self.assertEqual(judge.check([Path("pulse_t.exe")], allow, overlay), [])
                overlay.write_text("t P$T_$$_CASE U_$P$T_$$_GONE  # stale\n", encoding="utf-8")
                findings = judge.check([Path("pulse_t.exe")], allow, overlay)
                self.assertTrue(any(line.startswith("CASE_LOOP_LOAD") for line in findings))
                self.assertTrue(any(line.startswith("CASE_LOOP_ALLOW_STALE") for line in findings))


class CorpusTests(unittest.TestCase):
    """The selected programs as the tree's own toolchain builds them."""

    def test_no_case_loop_reloads_a_global_the_list_does_not_name(self) -> None:
        toolchain = pulse.ROOT / "toolchain"
        if not pulse.moon_toolchain_paths(toolchain)[1].is_file():
            self.skipTest(f"the product toolchain is not built: {toolchain}")
        requested = os.environ.get("PULSE_CASE_LOOP_PROGRAMS")
        programs = requested.split(",") if requested is not None else list(pulse.PROGRAMS)
        self.assertTrue(programs and all(program in pulse.PROGRAMS for program in programs))
        with mock.patch.object(pulse, "run", functools.partial(pulse.run, capture=True)):
            executables = [pulse.build_moon(program, False, system="case-loads-test", toolchain=toolchain)
                           for program in programs]
        self.assertEqual(judge.check(executables, extra_allow=judge.overlay(executables)), [])


if __name__ == "__main__":
    unittest.main()
