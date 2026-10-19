import unittest
from verify_2411_scope import RELEASE_FILES, TESTED_FILES, VERSION_FILES, validate


class ScopedReleaseTests(unittest.TestCase):
    def setUp(self):
        self.base = {p: b'prefix ' + old + b' suffix' for p, (old, _) in VERSION_FILES.items()}
        self.base['doc/RELEASE_NOTES.md'] = b'# MoonCompiler 2.4.10: previous notes\n'
        self.tested = {p: b'already tested content ' + p.encode() for p in TESTED_FILES}
        self.current = dict(self.tested)
        self.current.update({p: self.base[p].replace(old, new) for p, (old, new) in VERSION_FILES.items()})
        self.current['doc/RELEASE_NOTES.md'] = b'# MoonCompiler 2.4.11: expected exceptions\n\n---\n\n' + self.base['doc/RELEASE_NOTES.md']
        self.changed = TESTED_FILES | VERSION_FILES.keys() | RELEASE_FILES

    def check(self):
        validate(self.changed, self.base.__getitem__, self.tested.__getitem__, self.current.__getitem__)

    def test_qualified_diagnostics_and_version_only(self):
        self.check()

    def test_extra_product_or_build_change_fails(self):
        for path in ('rtl/inc/except.inc', 'compiler/ncgcal.pas', 'build.ps1', '.github/workflows/qualification.yml'):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'outside'):
                validate(self.changed | {path}, self.base.__getitem__, self.tested.__getitem__, self.current.__getitem__)

    def test_any_change_to_previously_tested_files_fails(self):
        for path in TESTED_FILES:
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'diagnostics changed'):
                validate(self.changed, self.base.__getitem__, self.tested.__getitem__,
                         lambda p: self.current[p] + (b'changed' if p == path else b''))

    def test_version_file_cannot_hide_another_change(self):
        self.current['compiler/version.pas'] += b'new compiler code'
        with self.assertRaisesRegex(ValueError, 'beyond'):
            self.check()

    def test_missing_bump_fails(self):
        self.current['compiler/version.pas'] = self.base['compiler/version.pas']
        with self.assertRaisesRegex(ValueError, 'beyond'):
            self.check()

    def test_release_history_cannot_be_rewritten(self):
        self.current['doc/RELEASE_NOTES.md'] = b'# MoonCompiler 2.4.11: without history'
        with self.assertRaisesRegex(ValueError, 'prior releases'):
            self.check()


if __name__ == '__main__':
    unittest.main()
