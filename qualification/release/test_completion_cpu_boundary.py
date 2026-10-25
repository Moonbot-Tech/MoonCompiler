"""Crash-window consumer boundary: an old source never changes its CPU plan."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import pulse_completion as completion


class CompletionCpuBoundaryTests(unittest.TestCase):
    def test_explicit_mismatch_rejected_and_automatic_preserves_original_plan(self):
        raw = {'machine': {'single_affinity': [2, 6, 8, 14], 'multithread_affinity': [0, 2]}}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with (patch.object(completion, 'source_raw', return_value=(raw, {})),
                  patch.object(completion, 'verify_binaries', return_value={}),
                  patch.object(completion, 'freeze_missing', return_value=({}, {})),
                  patch.object(completion, 'case_descriptors', return_value={}),
                  patch.object(completion, 'move_batches', return_value=([], [])),
                  patch.object(completion.method, 'keep_runner_off',
                               side_effect=RuntimeError('stop before measurement')) as first_cpu):
                arguments = [root, 'a' * 64, 'b' * 64, root / 'out', root, root, root, root]
                with self.assertRaisesRegex(ValueError, 'requested single-CPU plan differs'):
                    completion.complete(*arguments, '0,4,10,12')
                first_cpu.assert_not_called()
                self.assertFalse((root / 'out').exists())
                with self.assertRaisesRegex(RuntimeError, 'stop before measurement'):
                    completion.complete(*arguments, '')
                first_cpu.assert_called_once_with(2)


if __name__ == '__main__':
    unittest.main()
