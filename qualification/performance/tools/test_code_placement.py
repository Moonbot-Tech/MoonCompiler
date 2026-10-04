"""Regression checks for GNU objdump prefix spelling and fused branches."""

import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch

import check_placement_rules
import code_placement


class PrefixedDisassemblyTest(unittest.TestCase):
    def test_padding_preserves_register_effects(self):
        for mnemonic, operands in (("cs", "mov eax,0x2"), ("cs", "rep nop"),
                                   ("lea", "eax,[eax]"), ("lea", "r8d,[r8d+0x0]")):
            with self.subTest(mnemonic=mnemonic, operands=operands):
                self.assertFalse(code_placement.is_padding(mnemonic, operands))
        for mnemonic, operands in (("cs", "nop WORD PTR [rax+rax*1+0x0]"),
                                   ("ds", "cs nop"), ("lea", "rax,[rax]"), ("lea", "r8,[r8+0x0]")):
            with self.subTest(mnemonic=mnemonic, operands=operands):
                self.assertTrue(code_placement.is_padding(mnemonic, operands))

    def test_only_dummy_prefixes_are_removed(self):
        listing = (
            "  1e:\t3e 3e 48 81 fb 00 01 00 00\tds ds cmp rbx,0x100\n"
            "  27:\t75 05\tjne 2e <target>\n"
            "  30:\tf3 a4\trep movsb BYTE PTR es:[rdi],BYTE PTR ds:[rsi]\n"
            "  32:\t2e 90\tcs nop\n"
            "  34:\tf0 0f b1 0f\tlock cmpxchg DWORD PTR [rdi],ecx\n"
            "  38:\t66 89 d8\tdata16 mov ax,bx\n"
            "  3b:\tf3 ab\trep stos DWORD PTR es:[rdi],eax\n"
        )
        with patch.object(code_placement, "run", return_value=listing):
            instructions = code_placement.disassemble(Path("fixture"))
        self.assertEqual(instructions[0x1e][0], "cmp")
        self.assertEqual(instructions[0x1e][1], "rbx,0x100")
        self.assertEqual(instructions[0x27][0], "jne")
        self.assertEqual(instructions[0x30][0], "rep")
        self.assertEqual(instructions[0x32][0], "nop")
        self.assertEqual(instructions[0x34][0], "lock")
        self.assertEqual(instructions[0x38][0], "data16")
        self.assertEqual(instructions[0x3b][0], "rep")
        self.assertFalse(code_placement.is_padding(*instructions[0x38][:2]))
        self.assertNotEqual(code_placement.analyze("plain", 0x34, 0x38, {
            0x34: ("cmpxchg", "DWORD PTR [rdi],ecx", b"\x0f\xb1\x0f")
        }).normalized_sha256, code_placement.analyze("locked", 0x34, 0x38, instructions).normalized_sha256)
        self.assertEqual(code_placement.leading_prefixes(instructions[0x1e][2]), b"\x3e\x3e")

        with patch.object(code_placement, "procedures", return_value=[("fixture", 0x1e, 0x29)]), \
             patch.object(code_placement, "disassemble", return_value=instructions):
            report = check_placement_rules.check(Path("fixture"), ["fixture"], [])
        self.assertEqual(report["R4_violations"], [("fixture", 0x27, 30, 9, "jne")])

    def test_dead_prefixes_before_jump_target_are_not_an_instruction(self):
        linear = (
            "  10:\teb 11\tjmp 23 <retry>\n"
            "  1d:\tc3\tret\n"
            "  1e:\t3e 3e 3e 3e 3e 85 d2\tds ds ds ds ds test edx,edx\n"
            "  25:\t79 00\tjns 27 <done>\n"
        )
        target = "  23:\t85 d2\ttest edx,edx\n"
        with patch.object(code_placement, "tool", return_value="objdump"), \
             patch.object(code_placement, "run", side_effect=lambda cmd: target if any(
                 arg.startswith("--start-address") for arg in cmd) else linear):
            instructions = code_placement.disassemble(Path("fixture"))
        self.assertNotIn(0x1e, instructions)
        self.assertEqual(instructions[0x23], ("test", "edx,edx", b"\x85\xd2"))
        with patch.object(code_placement, "procedures", return_value=[("fixture", 0x10, 0x27)]), \
             patch.object(code_placement, "disassemble", return_value=instructions):
            report = check_placement_rules.check(Path("fixture"), ["fixture"], [])
        self.assertEqual(report["R4_violations"], [])

    def test_live_overlapping_entry_keeps_both_decodings(self):
        linear = (
            "  10:\t74 01\tje 13 <no-wait>\n"
            "  12:\t9b db e2\tfclex\n"
            "  15:\tc3\tret\n"
        )
        target = "  13:\tdb e2\tfnclex\n"
        with patch.object(code_placement, "tool", return_value="objdump"), \
             patch.object(code_placement, "run", side_effect=lambda cmd: target if any(
                 arg.startswith("--start-address") for arg in cmd) else linear):
            instructions = code_placement.disassemble(Path("fixture"))
        self.assertEqual(instructions[0x12][0], "fclex")
        self.assertEqual(instructions[0x13][0], "fnclex")

    def test_hot_scope_does_not_follow_branches_decoded_from_data(self):
        instructions = {0x10: ('ret', '', b'\xc3'),
                        0x20: ('jne', '29', b'\x75\x07'),
                        0x28: ('add', '[rax],al', b'\x00\x00')}
        with patch.object(code_placement, 'tool', return_value='objdump'), \
             patch.object(code_placement, 'run', return_value=''):
            code_placement.repair_overlaps(Path('fixture'), instructions.copy(), (0x10, 0x11))
            with self.assertRaisesRegex(RuntimeError, 'cannot decode branch target'):
                code_placement.repair_overlaps(Path('fixture'), instructions.copy(), (0x20, 0x2a))

    def test_scoped_decoder_rejects_incomplete_entry_and_real_bad_branch(self):
        instructions = {0x10: ('je', '13', b'\x74\x01'),
                        0x12: ('mov', 'eax,0x12345678', bytes.fromhex('b878563412'))}
        with self.assertRaisesRegex(RuntimeError, 'missing instruction at procedure entry'):
            code_placement.repair_overlaps(Path('fixture'), instructions.copy(), (0x11, 0x17))
        with patch.object(code_placement, 'tool', return_value='objdump'), \
             patch.object(code_placement, 'run', return_value='  13:\t78 56\tjs 6b <outside>\n'):
            with self.assertRaisesRegex(RuntimeError, 'cannot decode branch target'):
                code_placement.repair_overlaps(Path('fixture'), instructions.copy(), (0x10, 0x17))

    def test_operand_size_prefix_can_carry_padding(self):
        instructions = {0x10: ("mov", "ax,bx", b"\x66\x89\xd8"),
                        0x13: ("jne", "18", b"\x75\x03")}
        self.assertEqual(check_placement_rules.prefix_capacity(instructions, [0x10, 0x13], 1, set()),
                         (3, False))
        instructions[0x10] = ("mov", "ax,bx", b"\x3e\x89\xd8")
        self.assertEqual(check_placement_rules.prefix_capacity(instructions, [0x10, 0x13], 1, set()),
                         (0, False))
        for mnemonic, operands, raw in (("lock", "cmpxchg [rax],ecx", b"\xf0\x0f\xb1\x08"),
                                        ("rep", "stos DWORD PTR es:[rdi],eax", b"\xf3\xab")):
            instructions[0x10] = (mnemonic, operands, raw)
            self.assertEqual(check_placement_rules.prefix_capacity(instructions, [0x10, 0x13], 1, set()),
                             (0, False))

    def test_r3l_requires_a_clean_relocation_witness(self):
        def loop(head, length, interior=None):
            instructions = {head + i: ("nop", "", b"\x90") for i in range(length - 2)}
            if interior is not None:
                offset, size, target = interior
                for i in range(offset, offset + size):
                    del instructions[head + i]
                raw = b"\x75\x00" if size == 2 else b"\x0f\x85\x00\x00\x00\x00"
                instructions[head + offset] = ("jne", f"{head + target:x}", raw)
            instructions[head + length - 2] = ("jmp", f"{head:x}", b"\xeb\x00")
            return instructions, sorted(instructions)

        insns, addresses = loop(0x20, 100)
        self.assertEqual(check_placement_rules.r3l_witness(insns, addresses, [], 0x20, 0x84), 0)
        with patch.object(code_placement, "procedures", return_value=[("avoidable", 0x20, 0x84)]), \
             patch.object(code_placement, "disassemble", return_value=insns):
            report = check_placement_rules.check(Path("fixture"), [], [])
        self.assertEqual(len(report["R3L_violations"]), 1)
        self.assertEqual(check_placement_rules.assertion_failures(report, "R3L", []), ["R3L"])
        insns, addresses = loop(0x10, 114, (28, 6, 130))
        self.assertIsNone(check_placement_rules.r3l_witness(insns, addresses, [], 0x10, 0x82))
        insns, addresses = loop(0x20, 126, (10, 2, 58))
        self.assertIsNone(check_placement_rules.r3l_witness(insns, addresses, [0x20 + 58], 0x20, 0x9e))
        with patch.object(code_placement, "procedures", return_value=[("target_pad", 0x20, 0x9e)]), \
             patch.object(code_placement, "disassemble", return_value=insns):
            report = check_placement_rules.check(Path("fixture"), [], [])
        self.assertEqual(report["R3L_violations"], [])
        self.assertEqual(len(report["R3L_unproven"]), 1)
        insns, addresses = loop(0x20, 100, (10, 2, 132))
        self.assertIsNone(check_placement_rules.r3l_witness(insns, addresses, [], 0x20, 0x84))

    def test_r2e_does_not_require_an_r4_impossible_64_byte_line(self):
        head = 0x10
        insns = {head + i: ("nop", "", b"\x90") for i in range(62)}
        insns[head + 62] = ("jmp", f"{head:x}", b"\xeb\x00")
        with patch.object(code_placement, "procedures", return_value=[("loop64", head, head + 64)]), \
             patch.object(code_placement, "disassemble", return_value=insns):
            report = check_placement_rules.check(Path("fixture"), [], [])
        self.assertEqual(len(report["R2_violations"]), 1)
        self.assertEqual(report["R2E_violations"], [])
        self.assertEqual(report["R3H_violations"], [])

        head = 0x18
        insns = {head + i: ("nop", "", b"\x90") for i in range(62)}
        insns[head + 62] = ("jmp", f"{head:x}", b"\xeb\x00")
        with patch.object(code_placement, "procedures", return_value=[("bad_head", head, head + 64)]), \
             patch.object(code_placement, "disassemble", return_value=insns):
            report = check_placement_rules.check(Path("fixture"), [], [])
        self.assertEqual(len(report["R3H_violations"]), 1)

    def test_r4_still_rejects_a_crossing_branch(self):
        insns = {0x1f: ("jne", "23", b"\x75\x02")}
        with patch.object(code_placement, "procedures", return_value=[("crossing", 0x1f, 0x21)]), \
             patch.object(code_placement, "disassemble", return_value=insns):
            report = check_placement_rules.check(Path("fixture"), [], [])
        self.assertEqual(len(report["R4_violations"]), 1)
        self.assertEqual(check_placement_rules.assertion_failures(report, "R4", []), ["R4"])


class WrittenJumpTest(unittest.TestCase):
    """The gates find written-out jumps by their bytes, a comment only names the mnemonic; a listing
    that leaves code out, or misses a compiled written-out jump, is no pass."""

    SOURCE = (
        "function FreeSmallPoolLockedHandoff(P, Pool: pointer): PtrUInt; nostackframe; assembler;\n"
        "asm\n"
        "        db      $75, $76 // jne @Pending\n"
        "        db      $3E, $3E // layout: DS prefixes\n"
        "        db      $65, $8B, $04, $25, $48, $00, $00, $00 // mov eax, gs:[$48]\n"
        "@Pending:\n"
        "end;\n"
        "procedure Move(const source;var dest;count:SizeInt);assembler;nostackframe;\n"
        "asm\n"
        "    .byte  0x7F,0x77              { jg .L33OrMoreCheckAvx, a comment }\n"
        "    .byte  62,62,62               { layout }\n"
        "    .byte  15,31,68,0,0           { dead nops }\n"
        "    .byte  0xEB,0x7F              { jmp .LAvxReturn (rel8 written out) }\n"
        "end;\n"
    )

    def test_a_written_jump_without_the_marker_is_found(self):
        # the historical false pass: `(rel8 written out ...)` taken out of the comment, bytes kept
        text, found, problems = code_placement.written_jumps(self.SOURCE, "mm.pas")
        self.assertEqual(problems, [])
        self.assertEqual(found, ["mm.pas:3 (FreeSmallPoolLockedHandoff)", "mm.pas:10 (Move)", "mm.pas:13 (Move)"])
        lines = text.split("\n")
        # the mark in front of the mnemonic: nop dword ptr [rax+3], 3 being the line
        self.assertEqual(lines[2], "        db 15,31,128,3,0,0,0; jne @Pending "
                                   "{$info MOON_WRITTEN_JUMP mm.pas:3 (FreeSmallPoolLockedHandoff)} // jne @Pending")
        self.assertTrue(lines[9].startswith(
            "    .byte 15,31,128,10,0,0,0; jg .L33OrMoreCheckAvx {$info MOON_WRITTEN_JUMP mm.pas:10 (Move)}"))
        self.assertTrue(lines[12].startswith("    .byte 15,31,128,13,0,0,0; jmp .LAvxReturn {$info"))
        self.assertEqual([n for n, (a, b) in enumerate(zip(self.SOURCE.split("\n"), lines), 1) if a != b], [3, 10, 13])

    def test_a_written_jump_without_its_mnemonic_fails(self):
        source = self.SOURCE.replace("// jne @Pending", "// to the pending branch")
        text, found, problems = code_placement.written_jumps(source, "mm.pas")
        self.assertNotIn("mm.pas:3 (FreeSmallPoolLockedHandoff)", found)
        self.assertEqual(len(problems), 1)
        self.assertIn("mm.pas:3 (FreeSmallPoolLockedHandoff)", problems[0])
        self.assertIn("names no mnemonic and label", problems[0])
        self.assertEqual(text.split("\n")[2], source.split("\n")[2])

    def test_a_jump_with_other_bytes_on_its_line_fails(self):
        source = self.SOURCE.replace("db      $75, $76", "db      $3E, $75, $76")
        _, found, problems = code_placement.written_jumps(source, "mm.pas")
        self.assertEqual(len(found), 2)
        self.assertIn("other bytes on its line", problems[0])

    def test_the_compiler_names_the_compiled_ones(self):
        output = ("Compiling system.pp\nUser defined: MOON_WRITTEN_JUMP x86_64.inc:118 (Move)\n"
                  "x: MOON_WRITTEN_JUMP m.pas:7 (no routine)\n")
        self.assertEqual(code_placement.compiled_written_jumps(output), {"x86_64.inc:118 (Move)", "m.pas:7 (no routine)"})

    def test_a_byte_line_the_gate_cannot_read_fails(self):
        # a jump in bytes the finder does not read would stay bytes in the copy too, and compare equal;
        # the line is one by its directive, so no spelling behind it takes it out of the finder's sight
        # (the audit of r7: `$75 / 1` - `/` divides in both assembler dialects - left the line unseen)
        for spelling in ("db      75h, 76h // jne @Pending", "db      $70+5, $76 // jne @Pending",
                         "db      $75, $76 (* jne @Pending *)", "db      $75, $76; nop // jne @Pending",
                         "db      $75 / 1, $76 // jne @Pending", "db      $75/1,$76 // jne @Pending",
                         "db      $70+10/2, $76 // jne @Pending", "db      75h / 1, $76 // jne @Pending",
                         "db      0x75 / 1, $76 // jne @Pending", "db      ($75), $76 // jne @Pending",
                         "db      $75, $76 { jne @Pending } nop", "@Entry: db $75 / 1, $76 // jne @Pending",
                         "db      $75, $76 / 1 { jne @Pending }", "db      // jne @Pending"):
            _, found, problems = code_placement.written_jumps(
                self.SOURCE.replace("        db      $75, $76 // jne @Pending", "        " + spelling), "mm.pas")
            self.assertEqual(len(found), 2, spelling)
            self.assertEqual(len(problems), 1, spelling)
            self.assertIn("mm.pas:3 (FreeSmallPoolLockedHandoff)", problems[0])
            self.assertIn("bytes the gate cannot read", problems[0])
        # AT&T: a leading zero is octal (`.byte 017` assembles to 0x4F, not 17), a symbol is no number
        for spelling in (".byte  017,0x77", ".byte  .Lb-.La,0x77", ".byte  0x7F-0x10,0x77"):
            _, found, problems = code_placement.written_jumps(
                self.SOURCE.replace(".byte  0x7F,0x77", spelling), "x86_64.inc")
            self.assertEqual(len(found), 2, spelling)
            self.assertEqual(len(problems), 1, spelling)
            self.assertIn("x86_64.inc:10 (Move)", problems[0])
            self.assertIn("bytes the gate cannot read", problems[0])

    def test_a_label_in_front_is_read(self):
        text, found, problems = code_placement.written_jumps(
            self.SOURCE.replace("        db      $75, $76", "@Entry: db      $75, $76"), "mm.pas")
        self.assertEqual((problems, found[0]), ([], "mm.pas:3 (FreeSmallPoolLockedHandoff)"))
        self.assertTrue(text.split("\n")[2].startswith("@Entry: db 15,31,128,3,0,0,0; jne @Pending {$info"))
        # the directive is the start of the line, whatever follows it: no space needed before the bytes
        text, found, problems = code_placement.written_jumps(
            self.SOURCE.replace("db      $75, $76", "db$75,$76"), "mm.pas")
        self.assertEqual((problems, found[0]), ([], "mm.pas:3 (FreeSmallPoolLockedHandoff)"))
        self.assertTrue(text.split("\n")[2].startswith("        db 15,31,128,3,0,0,0; jne @Pending {$info"))

    # objdump -h -d -z -M intel -w of a unit with one routine, as built from the source (the jump written
    # out) and from the copy (its mnemonic behind the mark of line 3); the section ends in zeros
    WRITTEN = ("   0:\t75 04\tjne    6 <MOD_$$_F+0x6>\n"
               "   2:\t90\tnop\n"
               "   3:\t48 89 c8\tmov    rax,rcx\n"
               "   6:\tc3\tret\n"
               "   7:\tc3\tret\n"
               "   8:\t00 00\tadd    BYTE PTR [rax],al\n"
               "   a:\t00\t.byte 0x0\n")
    PLACED = ("   0:\t0f 1f 80 03 00 00 00\tnop    DWORD PTR [rax+0x3]\n"
              "   7:\t75 04\tjne    d <MOD_$$_F+0xd>\n"
              "   9:\t90\tnop\n"
              "   a:\t48 89 c8\tmov    rax,rcx\n"
              "   d:\tc3\tret\n"
              "   e:\tc3\tret\n"
              "   f:\t00\t.byte 0x0\n")
    COMPILED = {"mm.pas:3 (F)"}

    @staticmethod
    def listing(code: str, size: int | None = None) -> str:
        """The listing of a unit whose one code section is `code`, `size` bytes (by default up to the end
        of its last instruction)."""
        if size is None:
            last = code_placement.LISTING_INSN.match(code.splitlines()[-1])
            size = int(last.group(1), 16) + len(last.group(2).split())
        return ("w.o:     file format pe-x86-64\n\nSections:\n"
                "Idx Name          Size      VMA               LMA               File off  Algn  Flags\n"
                "  0 .text         00000000  0000000000000000  0000000000000000  00000000  2**4  "
                "ALLOC, LOAD, READONLY, CODE\n"
                f"  1 .text.n_mod_$$_f {size:08x}  0000000000000000  0000000000000000  00000100  2**5  "
                "CONTENTS, ALLOC, LOAD, READONLY, CODE\n\n"
                "Disassembly of section .text.n_mod_$$_f:\n\n0000000000000000 <MOD_$$_F>:\n" + code)

    def same_jumps(self, written: str, placed: str, compiled: set[str] = COMPILED):
        with patch.object(code_placement, "tool", return_value="objdump"), \
             patch.object(code_placement, "run", side_effect=[written, placed]):
            return code_placement.same_jumps(Path("w.o"), Path("p.o"), compiled)

    def test_a_marked_jump_is_compared(self):
        # the nop is fill: the ret at 6 (at d) is instruction #2 in both builds
        self.assertEqual(self.same_jumps(self.listing(self.WRITTEN), self.listing(self.PLACED)), (1, []))

    def test_a_jump_over_a_useful_prefixed_or_narrow_instruction_is_different(self):
        # cs does not erase MOV; a 32-bit LEA clears the register's upper half.
        for raw, instruction in (("2e b8 02 00 00 00", "cs mov eax,0x2"),
                                 ("67 8d 00", "lea eax,[eax]")):
            with self.subTest(instruction=instruction):
                size = len(raw.split())
                written = ("   0:\teb 00\tjmp 2 <MOD_$$_F+0x2>\n"
                           f"   2:\t{raw}\t{instruction}\n"
                           f"   {2 + size:x}:\tc3\tret\n")
                placed = ("   0:\t0f 1f 80 03 00 00 00\tnop DWORD PTR [rax+0x3]\n"
                          f"   7:\teb {size:02x}\tjmp {9 + size:x} <MOD_$$_F+0x{9 + size:x}>\n"
                          f"   9:\t{raw}\t{instruction}\n"
                          f"   {9 + size:x}:\tc3\tret\n")
                self.assertEqual(self.same_jumps(self.listing(written), self.listing(placed)),
                                 (1, ["F jmp #0 goes to #1, as a mnemonic to #2"]))
                correct = written.replace("eb 00\tjmp 2 <MOD_$$_F+0x2>",
                                          f"eb {size:02x}\tjmp {2 + size:x} <MOD_$$_F+0x{2 + size:x}>")
                self.assertEqual(self.same_jumps(self.listing(correct), self.listing(placed)), (1, []))

    def test_a_jump_to_another_instruction_is_named(self):
        placed = self.PLACED.replace("75 04\tjne    d <MOD_$$_F+0xd>", "75 05\tjne    e <MOD_$$_F+0xe>")
        count, wrong = self.same_jumps(self.listing(self.WRITTEN), self.listing(placed))
        self.assertEqual(wrong, ["F jne #0 goes to #2, as a mnemonic to #3"])

    def test_an_empty_listing_is_no_pass(self):
        # control (a) of the audit: objdump exits 0 and prints nothing; r5 took it for 0 jumps, PASS
        with self.assertRaisesRegex(RuntimeError, r"objdump listed no code section.*1 of the 1 written-out jumps "
                                                  r"compiled not compared: mm\.pas:3 \(F\)"):
            self.same_jumps("", "")
        # an object whose section table holds no code section
        data = ("w.o:     file format pe-x86-64\n\nSections:\n"
                "Idx Name          Size      VMA               LMA               File off  Algn  Flags\n"
                "  0 .data         00000010  0000000000000000  0000000000000000  00000100  2**4  "
                "CONTENTS, ALLOC, LOAD, DATA\n")
        with self.assertRaisesRegex(RuntimeError, r"^w\.o: objdump listed no code section of it; 1 of the 1"):
            self.same_jumps(data, data)
        # an objdump that does not know one of the options (-z) exits with an error
        with patch.object(code_placement, "tool", return_value="objdump"), \
             patch.object(code_placement, "run", side_effect=subprocess.CalledProcessError(1, "objdump")):
            with self.assertRaisesRegex(RuntimeError, r"^w\.o: objdump exited 1; 1 of the 1"):
                code_placement.same_jumps(Path("w.o"), Path("p.o"), self.COMPILED)

    def test_a_listing_short_of_a_jump_line_is_no_pass(self):
        # control (b): the line of the written-out jump lost in both listings; r5 compared the rest, PASS
        written = self.WRITTEN.replace("   0:\t75 04\tjne    6 <MOD_$$_F+0x6>\n", "")
        placed = self.PLACED.replace("   7:\t75 04\tjne    d <MOD_$$_F+0xd>\n", "")
        with self.assertRaisesRegex(RuntimeError, r"\.text\.n_mod_\$\$_f is listed on at 0x2, its code at 0x0.*"
                                                  r"not compared: mm\.pas:3 \(F\)"):
            self.same_jumps(self.listing(written), self.listing(placed))
        tail = "   8:\t00 00\tadd    BYTE PTR [rax],al\n   a:\t00\t.byte 0x0\n"
        with self.assertRaisesRegex(RuntimeError, r"listed up to 0x8 of 0xb"):
            self.same_jumps(self.listing(self.WRITTEN.replace(tail, ""), 0xb), self.listing(self.PLACED))

    def test_a_skip_of_objdump_is_no_pass(self):
        # the audit of r6: objdump -z lists zeros too, so a `...` stands for bytes nobody read - here a
        # jump of the copy to another instruction (r6 took `...` for zeros: (1, []), PASS)
        written = self.WRITTEN.replace("   8:\t00 00\tadd    BYTE PTR [rax],al\n   a:\t00\t.byte 0x0\n",
                                       "   8:\teb 00\tjmp    a <MOD_$$_F+0xa>\n   a:\tc3\tret\n")
        placed = self.PLACED.replace("   f:\t00\t.byte 0x0\n", "   f:\teb 01\tjmp    12 <MOD_$$_F+0x12>\n"
                                                              "  11:\tc3\tret\n  12:\tc3\tret\n")
        self.assertEqual(self.same_jumps(self.listing(written), self.listing(placed)),
                         (2, ["F jmp #4 goes to #5, as a mnemonic to #6"]))
        for skipped in ("   8:\teb 00\tjmp    a <MOD_$$_F+0xa>\n", "   a:\tc3\tret\n"):
            with self.assertRaisesRegex(RuntimeError, r"not understood: \.\.\."):
                self.same_jumps(self.listing(written.replace(skipped, "\t...\n"), 0xb),
                                self.listing(placed.replace("   f:\teb 01\tjmp    12 <MOD_$$_F+0x12>\n", "\t...\n"),
                                             0x13))

    def test_a_jump_text_off_its_bytes_is_no_pass(self):
        written = self.WRITTEN.replace("jne    6 <MOD_$$_F+0x6>", "jne    0x6")
        with self.assertRaisesRegex(RuntimeError, r"F\+0x0 `jne    0x6` \(75 04\): its bytes and the text"):
            self.same_jumps(self.listing(written), self.listing(self.PLACED))
        with self.assertRaisesRegex(RuntimeError, r"not understood: garbage"):
            self.same_jumps(self.listing(self.WRITTEN + "garbage\n", 0xb), self.listing(self.PLACED))
        # an objdump that names another target than the bytes reach (another version, another format)
        placed = self.PLACED.replace("jne    d <MOD_$$_F+0xd>", "jne    e <MOD_$$_F+0xe>")
        with self.assertRaisesRegex(RuntimeError, r"F\+0x7 `jne    e <MOD_\$\$_F\+0xe>` \(75 04\): its bytes and the text"):
            self.same_jumps(self.listing(self.WRITTEN), self.listing(placed))

    def test_a_compiled_jump_without_its_mark_is_named(self):
        # the jump the compiler compiled is not the one behind a mark: not compared, whatever the rest says
        placed = self.PLACED.replace("0f 1f 80 03 00 00 00\tnop    DWORD PTR [rax+0x3]",
                                     "0f 1f 80 04 00 00 00\tnop    DWORD PTR [rax+0x4]")
        with self.assertRaisesRegex(RuntimeError, r"^1 of the 1 written-out jumps compiled not compared: mm\.pas:3 \(F\); "
                                                  r"p\.o: 1 marked written-out jumps the compiler did not name as "
                                                  r"compiled, lines 4$"):
            self.same_jumps(self.listing(self.WRITTEN), self.listing(placed))
        self.assertEqual(self.same_jumps(self.listing(self.WRITTEN), self.listing(placed), {"mm.pas:4 (F)"}), (1, []))

    def test_a_marked_jump_the_compiler_did_not_name_is_no_pass(self):
        # the audit of r6: the messages of the compiler lost, the jump marked in the listing (r6: (1, []), PASS)
        with self.assertRaisesRegex(RuntimeError, r"^p\.o: 1 marked written-out jumps the compiler did not name as "
                                                  r"compiled, lines 3$"):
            self.same_jumps(self.listing(self.WRITTEN), self.listing(self.PLACED), set())
        # a profile that compiles no written-out jump: nothing marked, nothing named, the jumps compared
        self.assertEqual(self.same_jumps(self.listing(self.WRITTEN), self.listing(self.WRITTEN), set()), (1, []))
        # the line is the place, the routine in the message only labels it for a reader
        self.assertEqual(self.same_jumps(self.listing(self.WRITTEN), self.listing(self.PLACED), {"mm.pas:3 (G)"}),
                         (1, []))

    def test_two_marks_of_one_routine(self):
        # the second marked jump of a routine goes elsewhere: named, not hidden behind the first
        written = self.WRITTEN.replace("   8:\t00 00\tadd    BYTE PTR [rax],al\n   a:\t00\t.byte 0x0\n",
                                       "   8:\teb 00\tjmp    a <MOD_$$_F+0xa>\n   a:\tc3\tret\n   b:\tc3\tret\n")
        placed = self.PLACED.replace("   f:\t00\t.byte 0x0\n", "   f:\t0f 1f 80 04 00 00 00\tnop    DWORD PTR [rax+0x4]\n"
                                     "  16:\teb 01\tjmp    19 <MOD_$$_F+0x19>\n  18:\tc3\tret\n  19:\tc3\tret\n")
        self.assertEqual(self.same_jumps(self.listing(written), self.listing(placed), {"mm.pas:3 (F)", "mm.pas:4 (F)"}),
                         (2, ["F jmp #4 goes to #5, as a mnemonic to #6"]))


if __name__ == "__main__":
    unittest.main()
