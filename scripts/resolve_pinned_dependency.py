#!/usr/bin/env python3
"""Resolve compiler search roots inside one physically contained checkout."""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path


EXCLUDED_DIRECTORIES = {".git", ".moonbot", "build", "dcu"}


class ContainmentError(RuntimeError):
    pass


def physical(path: Path) -> Path:
    try:
        return path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ContainmentError(f"cannot resolve dependency path {path}: {exc}") from exc


def contained(path: Path, root: Path) -> bool:
    try:
        common = os.path.commonpath((os.fspath(path), os.fspath(root)))
        return os.path.normcase(common) == os.path.normcase(os.fspath(root))
    except ValueError:
        return False


def path_components(value: str) -> list[str]:
    separators = {os.sep}
    if os.altsep:
        separators.add(os.altsep)
    components = [value]
    for separator in separators:
        components = [part for item in components for part in item.split(separator)]
    return components


def logical_source(checkout: Path, value: str) -> Path:
    if not value:
        raise ContainmentError("empty dependency source component")
    if os.path.isabs(value) or (os.name == "nt" and os.path.splitdrive(value)[0]):
        raise ContainmentError(f"dependency source must be relative: {value}")
    if any(component == "" for component in path_components(value)):
        raise ContainmentError(f"dependency source contains an empty component: {value}")
    result = Path(os.path.abspath(os.path.join(checkout, os.path.normpath(value))))
    if not contained(result, checkout):
        raise ContainmentError(f"dependency source escapes checkout: {value}")
    return result


def is_link_or_reparse(entry: os.DirEntry[str]) -> bool:
    if entry.is_symlink():
        return True
    try:
        attributes = entry.stat(follow_symlinks=False).st_file_attributes
    except AttributeError:
        return False
    return bool(attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)


def scan_roots(checkout: Path, sources: list[str]) -> list[str]:
    checkout = Path(os.path.abspath(checkout))
    checkout_physical = physical(checkout)
    if not checkout_physical.is_dir():
        raise ContainmentError(f"dependency checkout is not a directory: {checkout}")

    output: list[str] = []
    emitted: set[str] = set()

    def scan(logical: Path, ancestors: frozenset[str]) -> None:
        target = physical(logical)
        target_key = os.path.normcase(os.fspath(target))
        if not contained(target, checkout_physical):
            raise ContainmentError(
                f"dependency path resolves outside checkout: {logical} -> {target}"
            )
        if not target.is_dir():
            raise ContainmentError(f"dependency source is not a directory: {logical}")
        if target_key in ancestors:
            raise ContainmentError(f"dependency directory link cycle at {logical}")
        if target_key in emitted:
            return
        emitted.add(target_key)
        output.append(os.fspath(logical))
        next_ancestors = ancestors | {target_key}
        try:
            with os.scandir(logical) as iterator:
                entries = sorted(iterator, key=lambda item: item.name.casefold())
        except OSError as exc:
            raise ContainmentError(f"cannot scan dependency directory {logical}: {exc}") from exc
        for entry in entries:
            entry_path = Path(entry.path)
            linked = is_link_or_reparse(entry)
            if linked:
                entry_target = physical(entry_path)
                if not contained(entry_target, checkout_physical):
                    raise ContainmentError(
                        f"dependency link resolves outside checkout: "
                        f"{entry_path} -> {entry_target}"
                    )
                if entry_target.is_dir() and entry.name not in EXCLUDED_DIRECTORIES:
                    scan(entry_path, next_ancestors)
                continue
            if entry.is_dir(follow_symlinks=False) and entry.name not in EXCLUDED_DIRECTORIES:
                scan(entry_path, next_ancestors)

    for source in sources:
        scan(logical_source(checkout, source), frozenset())
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkout", required=True, type=Path)
    parser.add_argument("--source", action="append", required=True)
    parser.add_argument("--format", choices=("json", "nul"), required=True)
    args = parser.parse_args()
    try:
        roots = scan_roots(args.checkout, args.source)
    except ContainmentError as exc:
        print(f"pinned dependency containment failed: {exc}", file=sys.stderr)
        return 2
    if args.format == "json":
        json.dump(roots, sys.stdout, ensure_ascii=False)
        sys.stdout.write("\n")
    else:
        for root in roots:
            sys.stdout.buffer.write(os.fsencode(root) + b"\0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
