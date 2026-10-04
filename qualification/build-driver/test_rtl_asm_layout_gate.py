import unittest

import rtl_asm_layout_gate as gate


class NamedRule4Sites(unittest.TestCase):
    def test_only_the_accepted_move_setup_sites_are_named(self):
        begin = 0x400000
        for offset, branch in ((2145, "je"), (2174, "jmp")):
            line = f"R4: {('FPC_MOVE', begin + offset, 0, 0, branch)!r}"
            self.assertTrue(gate.documented_rule4_site("FPC_MOVE", begin, line))
        for routine, offset, branch in (("FPC_MOVE", 2146, "je"),
                                       ("FPC_MOVE", 2145, "jne"),
                                       ("OTHER", 2145, "je")):
            line = f"R4: {(routine, begin + offset, 0, 0, branch)!r}"
            self.assertFalse(gate.documented_rule4_site(routine, begin, line))
        self.assertFalse(gate.documented_rule4_site("FPC_MOVE", begin, "R2: loop"))


if __name__ == "__main__":
    unittest.main()
