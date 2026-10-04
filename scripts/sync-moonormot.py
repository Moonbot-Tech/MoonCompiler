#!/usr/bin/env python3
"""Keep the three MoonORMot records of this repository on the tip of MoonORMot main.

The records:

  qualification/suite/runner_manifest.json  mormot.sources.current.commit,
                                             the commit the qualification runs on
  runtime/moonormot.need.inc                 the MoonORMot version the runtime
                                             units over mORMot refuse to go below
  runtime/mm/mormot.core.fpcx64mm.pas        the bundled memory manager, a copy
                                             of core/mormot.core.fpcx64mm.pas

    sync-moonormot.py --check   compare the records with the tip of main and
                                change nothing; exit 1 when any of them differs
    sync-moonormot.py           bring all three to the tip of main

The memory manager is copied only when the copy here still equals the one of
the old pin.  A copy edited in this repository and not carried to MoonORMot
would be overwritten by the copy, so the script refuses (exit 2), names both
files and leaves every record as it was.

Exit codes: 0 the records are (now) on the tip, 1 drift (--check only),
2 refused or failed.  The MoonORMot checkout is the qualification one
(.qualification/deps/moonormot), advanced to the tip as runner.py prepare does.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPOSITORY_ROOT / "qualification/suite"))

import runner  # noqa: E402  (qualification/suite/runner.py owns the pin semantics)

MANIFEST = "qualification/suite/runner_manifest.json"
SOURCE_ID = "current"


class SyncError(RuntimeError):
    pass


def git(*args: str, binary: bool = False) -> str | bytes:
    completed = subprocess.run(
        ["git", *args], check=False, capture_output=True, text=not binary,
    )
    if completed.returncode != 0:
        detail = completed.stderr if binary else completed.stderr.strip()
        raise SyncError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout


def remote_tip(url: str, branch: str) -> str:
    output = git("ls-remote", "--exit-code", url, f"refs/heads/{branch}")
    fields = output.split()
    if len(fields) != 2 or fields[1] != f"refs/heads/{branch}":
        raise SyncError(f"unexpected answer for {url} {branch}: {output.strip()}")
    return fields[0]


def file_at(checkout: Path, commit: str, name: str) -> bytes | None:
    """The bytes of NAME at COMMIT in CHECKOUT, or None when COMMIT is not there."""
    try:
        git("-C", str(checkout), "fetch", "--quiet", "--depth=1", "origin", commit)
    except SyncError:
        pass
    try:
        return git("-C", str(checkout), "show", f"{commit}:{name}", binary=True)
    except SyncError:
        return None


def dump_manifest(manifest: dict) -> str:
    return json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"


def load_manifest(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    manifest = json.loads(text)
    if dump_manifest(manifest) != text:
        raise SyncError(
            f"{path} is not in its canonical layout (json.dumps indent=2); "
            "re-dump it before the pin can be moved by one line"
        )
    return manifest


class Records:
    """The three records, the tip they are compared with, and their state."""

    def __init__(self, root: Path, repository: str | None, branch: str | None):
        self.root = root
        self.manifest_path = root / MANIFEST
        self.manifest = load_manifest(self.manifest_path)
        try:
            self.source = self.manifest["mormot"]["sources"][SOURCE_ID]
        except KeyError as error:
            raise SyncError(
                f"{self.manifest_path} has no mormot source {SOURCE_ID}"
            ) from error
        self.url = repository or self.source.get("url")
        self.branch = branch or self.source.get("require_branch_tip")
        if not self.url or not self.branch:
            raise SyncError("the manifest source names no url or require_branch_tip")
        for key in ("commit", "path", "memory_manager", "memory_manager_reference",
                    "runtime_version", "version_reference"):
            if key not in self.source:
                raise SyncError(f"the manifest source has no {key}")
        suite = self.manifest_path.parent
        self.checkout = (suite / self.source["path"]).resolve()
        self.mm = (suite / self.source["memory_manager"]).resolve()
        self.need = (suite / self.source["runtime_version"]).resolve()
        self.old_commit = self.source["commit"]

        self.tip = remote_tip(self.url, self.branch)
        runner.ensure_clean_git_source(self.checkout, self.tip, self.url)
        self.tip_version = runner.read_mormot_version(
            self.checkout / self.source["version_reference"], "MoonORMot",
        )
        self.tip_mm = runner.normalized_source_bytes(
            self.checkout / self.source["memory_manager_reference"],
        )
        self.our_version = runner.read_mormot_version(self.need, "runtime")
        self.our_mm = runner.normalized_source_bytes(self.mm)

    def lines(self) -> list[tuple[str, bool]]:
        mm_state = "equal to" if self.our_mm == self.tip_mm else "differs from"
        return [
            (f"qualification pin   {self.old_commit[:10]}  main {self.tip[:10]}",
             self.old_commit == self.tip),
            (f"runtime version     {self.our_version}  MoonORMot {self.tip_version}",
             self.our_version == self.tip_version),
            (f"memory manager      {mm_state} MoonORMot", self.our_mm == self.tip_mm),
        ]

    def in_sync(self) -> bool:
        return all(equal for _, equal in self.lines())

    def report(self) -> None:
        for text, equal in self.lines():
            state = "OK" if equal else "DIFFERS"
            print(f"{text:62} {state}")

    def apply(self) -> None:
        changed: list[str] = []
        if self.our_mm != self.tip_mm:
            reference = self.source["memory_manager_reference"]
            old_mm = file_at(self.checkout, self.old_commit, reference)
            if old_mm is None:
                raise SyncError(
                    f"the old pin {self.old_commit[:10]} is not reachable in {self.url}, "
                    f"so it cannot be proven that {self.mm} carries no edit of its own; "
                    "the memory manager was not copied and no record was changed"
                )
            if self.our_mm != old_mm.replace(b"\r\n", b"\n"):
                raise SyncError(
                    f"{self.mm} differs from the memory manager of the old pin "
                    f"{self.old_commit[:10]}: an edit made here was not carried to "
                    f"MoonORMot ({reference}); carry it over first, no record was changed"
                )
            self.mm.write_bytes(self.tip_mm)
            changed.append(f"{self.rel(self.mm)}: copied from MoonORMot {self.tip[:10]}")
        if self.our_version != self.tip_version:
            self.need.write_text(str(self.tip_version), encoding="utf-8", newline="\n")
            changed.append(
                f"{self.rel(self.need)}: {self.our_version} -> {self.tip_version}"
            )
        if self.old_commit != self.tip:
            self.source["commit"] = self.tip
            self.manifest_path.write_text(
                dump_manifest(self.manifest), encoding="utf-8", newline="\n",
            )
            changed.append(f"{MANIFEST}: {self.old_commit[:10]} -> {self.tip[:10]}")
        for line in changed:
            print(line)

    def rel(self, path: Path) -> str:
        try:
            return path.relative_to(self.root).as_posix()
        except ValueError:
            return str(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true",
                        help="compare only; exit 1 when a record differs from main")
    parser.add_argument("--root", type=Path, default=REPOSITORY_ROOT,
                        help="repository root (default: this repository)")
    parser.add_argument("--repository", help="MoonORMot URL (default: from the manifest)")
    parser.add_argument("--branch", help="MoonORMot branch (default: from the manifest)")
    args = parser.parse_args()
    try:
        records = Records(args.root.resolve(), args.repository, args.branch)
        records.report()
        if records.in_sync():
            print(f"MoonORMot records are on {records.branch} {records.tip[:10]}")
            return 0
        if args.check:
            return 1
        records.apply()
        print(f"MoonORMot records moved to {records.branch} {records.tip[:10]}, "
              f"version {records.tip_version}")
        return 0
    except (SyncError, RuntimeError, OSError) as error:
        print(f"sync-moonormot: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
