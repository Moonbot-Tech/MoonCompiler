"""scripts/sync-moonormot.py on a throw-away MoonORMot repository and a
throw-away compiler root: the three records are compared with the tip of
main, moved to it by one command, and never moved when the bundled memory
manager carries an edit of its own."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[3]
SCRIPT = REPOSITORY / "scripts/sync-moonormot.py"
MM_NAME = "core/mormot.core.fpcx64mm.pas"


def git(repository: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repository), *args],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


class MoonORMotFixture:
    """A MoonORMot with a version file and a memory manager, one commit per step."""

    def __init__(self, root: Path) -> None:
        self.path = root / "MoonORMot"
        subprocess.run(["git", "init", "--quiet", "-b", "main", str(self.path)], check=True)
        git(self.path, "config", "user.email", "sync@example.invalid")
        git(self.path, "config", "user.name", "Sync")
        # the qualification checkout fetches commits by hash; a local
        # repository allows that only when told to
        git(self.path, "config", "uploadpack.allowReachableSHA1InWant", "true")
        (self.path / "core").mkdir()

    def commit(self, version: int, mm: str) -> str:
        (self.path / "moonormot.version.inc").write_text(str(version), encoding="utf-8")
        (self.path / MM_NAME).write_text(mm, encoding="utf-8", newline="\n")
        git(self.path, "add", "-A")
        git(self.path, "commit", "--quiet", "-m", f"version {version}")
        return git(self.path, "rev-parse", "HEAD")


class CompilerFixture:
    """The part of the repository the script reads: manifest and runtime records."""

    def __init__(self, root: Path, moonormot: MoonORMotFixture, commit: str) -> None:
        self.root = root / "MoonCompiler"
        self.manifest = self.root / "qualification/suite/runner_manifest.json"
        self.need = self.root / "runtime/moonormot.need.inc"
        self.mm = self.root / "runtime/mm/mormot.core.fpcx64mm.pas"
        self.checkout = self.root / ".qualification/deps/moonormot"
        self.manifest.parent.mkdir(parents=True)
        self.mm.parent.mkdir(parents=True)
        self.url = str(moonormot.path)
        self.write_manifest(commit)

    def write_manifest(self, commit: str) -> None:
        manifest = {
            "mormot": {
                "sources": {
                    "current": {
                        "commit": commit,
                        "memory_manager": "../../runtime/mm/mormot.core.fpcx64mm.pas",
                        "memory_manager_reference": MM_NAME,
                        "path": "../../.qualification/deps/moonormot",
                        "require_branch_tip": "main",
                        "runtime_version": "../../runtime/moonormot.need.inc",
                        "url": self.url,
                        "version_reference": "moonormot.version.inc",
                    },
                },
            },
            "other": {"untouched": [1, 2, 3]},
        }
        self.manifest.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8", newline="\n",
        )

    def pin(self) -> str:
        return json.loads(self.manifest.read_text(encoding="utf-8"))["mormot"]["sources"]["current"]["commit"]

    def set_records(self, version: int, mm: str) -> None:
        self.need.write_text(str(version), encoding="utf-8")
        self.mm.write_text(mm, encoding="utf-8", newline="\n")

    def state(self) -> tuple[str, str, str, bytes]:
        return (
            self.manifest.read_text(encoding="utf-8"),
            self.pin(),
            self.need.read_text(encoding="utf-8"),
            self.mm.read_bytes(),
        )

    def run(self, *options: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root), *options],
            capture_output=True, text=True,
        )


class SyncMoonORMotTest(unittest.TestCase):
    def test_records_follow_the_tip_of_main_by_one_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            moonormot = MoonORMotFixture(root)
            first = moonormot.commit(1, "unit mm; // one\n")
            compiler = CompilerFixture(root, moonormot, first)
            compiler.set_records(1, "unit mm; // one\n")

            # in sync: --check and the plain run change nothing and exit 0
            before = compiler.state()
            check = compiler.run("--check")
            self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
            self.assertIn("MoonORMot records are on main", check.stdout)
            self.assertEqual(compiler.run().returncode, 0)
            self.assertEqual(compiler.state(), before)
            self.assertEqual(git(compiler.checkout, "rev-parse", "HEAD"), first)

            # MoonORMot moves on: the memory manager changes and the version rises
            second = moonormot.commit(2, "unit mm; // two\n")
            check = compiler.run("--check")
            self.assertEqual(check.returncode, 1, check.stdout + check.stderr)
            self.assertEqual(check.stdout.count("DIFFERS"), 3, check.stdout)
            self.assertEqual(compiler.state(), before, "--check must not write")

            moved = compiler.run()
            self.assertEqual(moved.returncode, 0, moved.stdout + moved.stderr)
            self.assertEqual(compiler.pin(), second)
            self.assertEqual(compiler.need.read_text(encoding="utf-8"), "2")
            self.assertEqual(compiler.mm.read_bytes(), b"unit mm; // two\n")
            self.assertEqual(git(compiler.checkout, "rev-parse", "HEAD"), second)
            self.assertIn("runtime/moonormot.need.inc: 1 -> 2", moved.stdout)
            self.assertIn("moved to main", moved.stdout)
            # the manifest changed by its pin line and nothing else
            changed = [
                (old, new) for old, new in zip(
                    before[0].splitlines(),
                    compiler.manifest.read_text(encoding="utf-8").splitlines(),
                ) if old != new
            ]
            self.assertEqual(len(changed), 1, changed)
            self.assertIn(first, changed[0][0])
            self.assertIn(second, changed[0][1])
            self.assertEqual(compiler.run("--check").returncode, 0)

            # a version bump alone (the MoonORMot Action's own commit) moves
            # the pin and the floor and leaves the memory manager as it is
            third = moonormot.commit(3, "unit mm; // two\n")
            moved = compiler.run()
            self.assertEqual(moved.returncode, 0, moved.stdout + moved.stderr)
            self.assertEqual(compiler.pin(), third)
            self.assertEqual(compiler.need.read_text(encoding="utf-8"), "3")
            self.assertNotIn("copied from MoonORMot", moved.stdout)

    def test_an_edited_memory_manager_stops_the_sync(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            moonormot = MoonORMotFixture(root)
            first = moonormot.commit(1, "unit mm; // one\n")
            compiler = CompilerFixture(root, moonormot, first)
            # the copy here was edited and the edit never reached MoonORMot
            compiler.set_records(1, "unit mm; // one, repaired here\n")
            moonormot.commit(2, "unit mm; // two\n")

            before = compiler.state()
            refused = compiler.run()
            self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
            self.assertIn("not carried to MoonORMot", refused.stderr)
            self.assertIn("no record was changed", refused.stderr)
            self.assertEqual(compiler.state(), before)

            # carried over (MoonORMot now holds the repaired text): the copy
            # equals the tip, so only the pin and the floor move
            third = moonormot.commit(3, "unit mm; // one, repaired here\n")
            moved = compiler.run()
            self.assertEqual(moved.returncode, 0, moved.stdout + moved.stderr)
            self.assertEqual(compiler.pin(), third)
            self.assertEqual(compiler.need.read_text(encoding="utf-8"), "3")
            self.assertEqual(compiler.mm.read_bytes(), b"unit mm; // one, repaired here\n")

    def test_a_non_canonical_manifest_is_refused_before_anything_moves(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            moonormot = MoonORMotFixture(root)
            first = moonormot.commit(1, "unit mm;\n")
            compiler = CompilerFixture(root, moonormot, first)
            compiler.set_records(1, "unit mm;\n")
            compiler.manifest.write_text(
                json.dumps(json.loads(compiler.manifest.read_text(encoding="utf-8")), indent=4),
                encoding="utf-8",
            )
            moonormot.commit(2, "unit mm;\n")
            refused = compiler.run()
            self.assertEqual(refused.returncode, 2, refused.stdout + refused.stderr)
            self.assertIn("canonical layout", refused.stderr)
            self.assertEqual(compiler.pin(), first)


if __name__ == "__main__":
    unittest.main()
