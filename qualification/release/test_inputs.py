import tempfile
from pathlib import Path
import unittest

from qualification.release.inputs import digest_paths, product_identity


class ProductIdentityTests(unittest.TestCase):
    def test_only_the_installed_profile_build_time_is_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "toolchain").mkdir()
            (root / "runtime/mm").mkdir(parents=True)
            source = root / "runtime/mm/mm.pas"
            source.write_bytes(b"built_utc=source\n")
            profile = root / "toolchain/profile.txt"
            profile.write_bytes(b"rtl_packages_opt=OPT=-O3\r\nbuilt_utc=first\r\n")
            identity = product_identity(root)
            raw = digest_paths([root / "toolchain"])
            profile.write_bytes(b"rtl_packages_opt=OPT=-O3\r\nbuilt_utc=second\r\n")
            self.assertEqual(product_identity(root), identity)
            self.assertNotEqual(digest_paths([root / "toolchain"]), raw)
            source.write_bytes(b"built_utc=changed source\n")
            self.assertNotEqual(product_identity(root), identity)


if __name__ == "__main__":
    unittest.main()
