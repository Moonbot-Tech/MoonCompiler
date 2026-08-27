from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))

from resolve_pinned_dependency import ContainmentError, scan_roots


class PinnedDependencyResolverTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.checkout = self.base / "checkout"
        (self.checkout / "src" / "sub").mkdir(parents=True)
        (self.checkout / "src" / "build" / "ignored").mkdir(parents=True)
        (self.checkout / "src" / "unit.pas").write_text("unit unit1;", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def roots(self, *sources: str) -> list[Path]:
        return [Path(value) for value in scan_roots(self.checkout, list(sources))]

    def symlink(self, target: Path, link: Path, directory: bool) -> None:
        try:
            os.symlink(target, link, target_is_directory=directory)
        except OSError as exc:
            self.skipTest(f"symbolic links are unavailable: {exc}")

    def junction(self, target: Path, link: Path) -> None:
        result = subprocess.run(
            ["cmd.exe", "/c", "mklink", "/J", os.fspath(link), os.fspath(target)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            self.skipTest(f"cannot create junction: {result.stdout}")

    def test_ordinary_tree_is_ordered_and_excludes_build_outputs(self) -> None:
        self.assertEqual(
            self.roots("src"),
            [self.checkout / "src", self.checkout / "src" / "sub"],
        )

    def test_dot_segments_normalize_but_escape_is_rejected(self) -> None:
        self.assertEqual(self.roots("src/../src"), self.roots("src"))
        with self.assertRaisesRegex(ContainmentError, "escapes checkout"):
            self.roots("../outside")

    def test_absolute_and_empty_components_are_rejected(self) -> None:
        with self.assertRaisesRegex(ContainmentError, "must be relative"):
            self.roots(os.fspath((self.checkout / "src").resolve()))
        with self.assertRaisesRegex(ContainmentError, "empty component"):
            self.roots("src//sub")
        with self.assertRaisesRegex(ContainmentError, "empty"):
            self.roots("")

    def test_internal_file_and_directory_links_are_allowed(self) -> None:
        self.symlink(self.checkout / "src" / "unit.pas", self.checkout / "src" / "unit-link.pas", False)
        self.symlink(self.checkout / "src" / "sub", self.checkout / "src" / "sub-link", True)
        roots = self.roots("src")
        self.assertEqual(roots, [self.checkout / "src", self.checkout / "src" / "sub"])

    def test_external_file_and_directory_links_are_rejected(self) -> None:
        outside_file = self.base / "outside.pas"
        outside_file.write_text("unit outside;", encoding="utf-8")
        self.symlink(outside_file, self.checkout / "src" / "outside.pas", False)
        with self.assertRaisesRegex(ContainmentError, "outside checkout"):
            self.roots("src")
        (self.checkout / "src" / "outside.pas").unlink()

        outside_dir = self.base / "outside"
        outside_dir.mkdir()
        self.symlink(outside_dir, self.checkout / "src" / "outside-dir", True)
        with self.assertRaisesRegex(ContainmentError, "outside checkout"):
            self.roots("src")

    def test_broken_link_and_directory_cycle_are_rejected(self) -> None:
        self.symlink(self.checkout / "missing", self.checkout / "src" / "broken", False)
        with self.assertRaisesRegex(ContainmentError, "cannot resolve"):
            self.roots("src")
        (self.checkout / "src" / "broken").unlink()

        self.symlink(self.checkout / "src", self.checkout / "src" / "sub" / "loop", True)
        with self.assertRaisesRegex(ContainmentError, "cycle"):
            self.roots("src")

    def test_physical_duplicate_roots_keep_first_logical_path(self) -> None:
        self.symlink(self.checkout / "src", self.checkout / "alias", True)
        self.assertEqual(self.roots("src", "alias"), self.roots("src"))

    @unittest.skipUnless(os.name == "nt", "junctions are Windows-only")
    def test_external_windows_junction_is_rejected(self) -> None:
        outside = self.base / "junction-target"
        outside.mkdir()
        junction = self.checkout / "src" / "junction"
        self.junction(outside, junction)
        try:
            with self.assertRaisesRegex(ContainmentError, "outside checkout"):
                self.roots("src")
        finally:
            os.rmdir(junction)

    @unittest.skipUnless(os.name == "nt", "junctions are Windows-only")
    def test_internal_windows_junction_and_cycle(self) -> None:
        alias = self.checkout / "alias"
        self.junction(self.checkout / "src", alias)
        try:
            self.assertEqual(self.roots("src", "alias"), self.roots("src"))
        finally:
            os.rmdir(alias)

        cycle = self.checkout / "src" / "sub" / "loop"
        self.junction(self.checkout / "src", cycle)
        try:
            with self.assertRaisesRegex(ContainmentError, "cycle"):
                self.roots("src")
        finally:
            os.rmdir(cycle)


if __name__ == "__main__":
    unittest.main()
