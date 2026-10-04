"""Code-identity attacks that a blanket immediate scrub would accept."""
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import code_placement as cp
import linked_image
import check_program_placement
import test_fail_closed as fixtures


def image(instructions, procedures=None, symbols=None):
    anchor = 'PULSE_HARNESS_$$_PULSERUNCASE$TEST'
    procedures = procedures or [('CASE', 0x1000, 0x1100), ('FIRST', 0x2000, 0x2010),
                                ('SECOND', 0x3000, 0x3010), (anchor, 0x4000, 0x4010)]
    symbols = symbols or '\n'.join(f'{begin:016x} T {name}' for name, begin, _ in procedures)
    with mock.patch.object(cp, 'procedures', return_value=procedures), \
         mock.patch.object(linked_image, 'absolute_relocations', return_value={}), \
         mock.patch.object(cp, 'linear_disassembly', return_value=instructions), \
         mock.patch.object(cp, 'run', return_value=symbols), \
         mock.patch.object(cp, 'tool', return_value='nm'):
        shapes = linked_image.ImageShapes(Path('test-image'))
        # These fixtures supply decoded instructions rather than executable bytes.
        shapes.decoded.update(shapes.procedures)
        return shapes


class LinkedIdentityTests(unittest.TestCase):
    def test_lazy_hot_scope_ignores_unrequested_data_and_rejects_bad_scope(self):
        procedures = [('CASE', 0x10, 0x11), ('DATA', 0x20, 0x2a),
                      ('PULSE_HARNESS_$$_PULSERUNCASE$TEST', 0x30, 0x31), ('DEBUGEND_$UNIT', 0x10, 0x11)]
        instructions = {0x10: ('ret', '', b'\xc3'), 0x20: ('jne', '29', b'\x75\x07'),
                        0x28: ('add', '[rax],al', b'\x00\x00'), 0x30: ('ret', '', b'\xc3')}
        symbols = '\n'.join(f'{begin:016x} T {name}' for name, begin, _ in procedures)
        with mock.patch.object(cp, 'procedures', return_value=procedures), \
             mock.patch.object(linked_image, 'absolute_relocations', return_value={}), \
             mock.patch.object(cp, 'linear_disassembly', return_value=instructions), \
             mock.patch.object(cp, 'run', return_value=symbols), \
             mock.patch.object(cp, 'tool', return_value='objdump'):
            shapes = linked_image.ImageShapes(Path('fixture'))
            self.assertEqual(shapes[0x10]['instructions'], 1)
            self.assertEqual(shapes[0x10]['name'], 'CASE')
            with self.assertRaisesRegex(RuntimeError, 'cannot decode branch target'):
                shapes[0x20]
        del shapes.instructions[0x30]
        with self.assertRaisesRegex(RuntimeError, 'missing instruction at procedure entry'):
            shapes[0x30]

    def test_same_named_callee_constant_change_is_rejected_for_both_roots(self):
        for called_by_worker in (False, True):
            with self.subTest(worker=called_by_worker), tempfile.TemporaryDirectory() as temporary:
                exe = Path(temporary) / 'image'
                exe.write_bytes(b'fixture')
                collected, runs, images = {}, [], []
                for index, suffix in enumerate(('', '1', '2', '3')):
                    shift = index * 0x80
                    constant = 0x1234 + int(index == 2)
                    call = ('call', f'{0x2000 + shift:x}', b'\xe8\0\0\0\0')
                    ret = ('ret', '', b'\xc3')
                    procedures = [(name, begin + shift, end + shift) for name, begin, end in
                                  [('CASE', 0x1000, 0x1100), ('FIRST', 0x2000, 0x2100),
                                   ('WORKER', 0x3000, 0x3100),
                                   ('PULSE_HARNESS_$$_PULSERUNCASE$TEST', 0x4000, 0x4010)]]
                    shapes = image({0x1000 + shift: ret if called_by_worker else call,
                                    0x2000 + shift: ('add', f'eax,0x{constant:x}',
                                                    b'\x05' + constant.to_bytes(4, 'little')),
                                    0x3000 + shift: call if called_by_worker else ret}, procedures)
                    images.append((shapes.anchor, shapes))
                    system = 'B' + suffix
                    runs.append({'system': system, 'program': 'threads', 'executable': str(exe),
                                 'executable_sha256': check_program_placement.pulse.sha256(exe)})
                    collected[system, 'threads', 'one'] = {
                        'body_offsets': [-0x3000], 'bodies': [0x1000 + shift],
                        'work_body_offsets': [-0x1000], 'work_bodies': [0x3000 + shift]}
                with mock.patch.object(check_program_placement.pulse, 'collect',
                                       return_value=(collected, {'runs': runs})), \
                     mock.patch.object(check_program_placement, 'image_shapes', side_effect=images):
                    with self.assertRaisesRegex(ValueError, 'direct_callees changed'):
                        check_program_placement.check(Path(temporary), ['B'])

    def test_changed_integer_is_not_a_relocation(self):
        left = ('add', 'eax,0x123456', bytes.fromhex('0556341200'))
        right = ('add', 'eax,0x234567', bytes.fromhex('0567452300'))
        self.assertEqual(cp.normalize(left[0], left[1]), cp.normalize(right[0], right[1]))
        self.assertNotEqual(image({0x1000: left}).proof_hash(0x1000, 0x1100),
                            image({0x1000: right}).proof_hash(0x1000, 0x1100))

    def test_absolute_operand_is_relocated_only_with_linker_evidence(self):
        left = image({0x1000: ('mov', 'eax,0x2000', bytes.fromhex('b800200000')), 0x2000: ('ret', '', b'\xc3')})
        right = image({0x1000: ('mov', 'eax,0x2080', bytes.fromhex('b880200000')), 0x2080: ('ret', '', b'\xc3')},
                      [(name, begin + (0x80 if begin == 0x2000 else 0), end + (0x80 if begin == 0x2000 else 0))
                       for name, begin, end in left.procedures.values()])
        self.assertNotEqual(left.proof_hash(0x1000, 0x1100), right.proof_hash(0x1000, 0x1100))
        left.relocations = right.relocations = {0x1001: 4}
        self.assertEqual(left.proof_hash(0x1000, 0x1100), right.proof_hash(0x1000, 0x1100))

    def test_changed_direct_callee_is_not_a_relocation(self):
        left = image({0x1000: ('call', '2000', bytes.fromhex('e8fb0f0000')), 0x2000: ('ret', '', b'\xc3')})
        right = image({0x1000: ('call', '3000', bytes.fromhex('e8fb1f0000')), 0x3000: ('ret', '', b'\xc3')})
        self.assertNotEqual(left.proof_hash(0x1000, 0x1100), right.proof_hash(0x1000, 0x1100))

    def test_branch_into_instruction_middle_is_rejected(self):
        broken = image({0x1000: ('jmp', '1002', bytes.fromhex('e9fdffffff'))})
        with self.assertRaisesRegex(ValueError, 'undecoded instruction'):
            broken.proof_hash(0x1000, 0x1100)

    def test_exception_location_pointer_can_identify_instruction_byte(self):
        linked = image({0x1000: ('mov', 'eax,0x1', bytes.fromhex('b801000000'))})
        self.assertEqual(linked.address_identity(0x1001), 'CASE@instruction0+byte1')

    def test_direct_branch_outside_procedure_into_symbol_gap_is_rejected(self):
        linked = image({0x1000: ('call', '5004', bytes.fromhex('e8ff3f0000'))})
        linked.symbols[0x5000] = 'OTHER'
        linked.symbol_starts = sorted(linked.symbols)
        with self.assertRaisesRegex(ValueError, 'unresolved direct branch target'):
            linked.proof_hash(0x1000, 0x1100)

    def test_owner_graph_difference_prevents_automatic_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixtures.write_family_result(root, 'B', 'C', {('threads', 'parallel-alloc-free-8'): (1000, 1000)})
            cases, _, _ = fixtures.STAND_COMPARE.collect_systems(root)
            for system, row in cases[('threads', 'parallel-alloc-free-8')].items():
                row['allocator'] = {'rows': list(range(8)), 'class': [0, 1],
                                    'owner': [0, 0] if system == 'C' else [0, 1]}
            rows = fixtures.STAND_COMPARE.family_rows(cases, 'B', 'C', paired=True)
            result = rows['threads/parallel-alloc-free-8']
            self.assertEqual(result['verdict'], 'UNRESOLVED')
            self.assertTrue(any('backing-owner collisions differ' in issue for issue in result['issues']))

    def test_unknown_rip_target_is_rejected(self):
        broken = image({0x1000: ('mov', 'eax,DWORD PTR [rip-0x1000]', bytes.fromhex('8b0500f0ffff'))})
        with self.assertRaisesRegex(ValueError, 'no linked symbol identity'):
            broken.proof_hash(0x1000, 0x1100)

    def test_changed_generic_identity_is_not_hidden_by_crc_scrubbing(self):
        old = image({0x1000: ('call', '2000', b'\xe8\0\0\0\0'), 0x2000: ('ret', '', b'\xc3')})
        first = old.procedures[0x2000]
        old.procedures[0x2000] = ('MAP$CRC153DB68B', first[1], first[2])
        before = old.proof_hash(0x1000, 0x1100)
        old.procedures[0x2000] = ('MAP$CRCDA54819A', first[1], first[2])
        self.assertNotEqual(before, old.proof_hash(0x1000, 0x1100))

    def test_real_nop_is_ignored_but_zero_extending_lea_is_not(self):
        plain = image({0x1000: ('ret', '', b'\xc3')})
        padded = image({0x1000: ('nop', '', b'\x90'), 0x1001: ('ret', '', b'\xc3')})
        changed = image({0x1000: ('lea', 'eax,[eax]', bytes.fromhex('678d00')), 0x1003: ('ret', '', b'\xc3')})
        self.assertEqual(plain.proof_hash(0x1000, 0x1100), padded.proof_hash(0x1000, 0x1100))
        self.assertNotEqual(plain.proof_hash(0x1000, 0x1100), changed.proof_hash(0x1000, 0x1100))

    def test_code_and_data_relocation_preserves_identity(self):
        left = image({0x1000: ('mov', 'eax,DWORD PTR [rip+0x3ffa]', bytes.fromhex('8b05fa3f0000')),
                      0x1006: ('call', '2000', bytes.fromhex('e8f50f0000')), 0x2000: ('ret', '', b'\xc3')})
        left.symbols[0x5000] = 'DATA'
        left.symbol_starts = sorted(left.symbols)
        shifted = [(name, begin + 0x80, end + 0x80) for name, begin, end in left.procedures.values()]
        right = image({0x1080: ('mov', 'eax,DWORD PTR [rip+0x3ffa]', bytes.fromhex('8b05fa3f0000')),
                       0x1086: ('call', '2080', bytes.fromhex('e8f50f0000')), 0x2080: ('ret', '', b'\xc3')}, shifted)
        right.symbols[0x5080] = 'DATA'
        right.symbol_starts = sorted(right.symbols)
        self.assertEqual(left.proof_hash(0x1000, 0x1100), right.proof_hash(0x1080, 0x1180))

    def test_mode_substitution_rejected_in_every_record_type(self):
        for record in ('PULSE_CASE ', 'PULSE_SAMPLE ', 'PULSE_TOTAL '):
            with self.subTest(record=record), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                fixtures.write_result(root, ['A'], {'A': ['one']})
                log = next(root.glob('*.log'))
                lines = log.read_text(encoding='utf-8').splitlines()
                log.write_text('\n'.join(line.replace('mode=quick', 'mode=medium')
                               if line.startswith(record) else line for line in lines), encoding='utf-8')
                with self.assertRaisesRegex(ValueError, 'mode'):
                    fixtures.PULSE.collect(root)

    def test_missing_duplicate_and_wrong_home_worker_rejected(self):
        workers = [{'worker': i, 'row': i, **{f'{kind}{size}': 100 + i * 3 + size
                    for kind in ('class', 'owner') for size in range(3)}} for i in range(8)]
        variants = [workers[:-1], workers + [workers[-1]], [dict(w, row=9) for w in workers]]
        for invalid in variants:
            with self.subTest(workers=invalid):
                self.assertIn('error', fixtures.STAND_COMPARE.allocator_signature(
                    'threads', 'parallel-alloc-free-8', {'workers': [invalid]}))


if __name__ == '__main__':
    unittest.main()
