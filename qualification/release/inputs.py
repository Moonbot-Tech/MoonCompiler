"""Content identities for qualification; paths and file bytes are both inputs."""

from __future__ import annotations

import hashlib
from pathlib import Path


def digest_paths(paths: list[Path], *, build_profile: Path | None = None) -> str:
    digest = hashlib.sha256()
    for index, path in enumerate(paths):
        if not path.exists():
            raise FileNotFoundError(path)
        files = sorted(item for item in path.rglob("*") if item.is_file()
                       and not {"__pycache__", ".git"}.intersection(item.relative_to(path).parts)
                       and item.suffix != ".pyc") if path.is_dir() else [path]
        if not files:
            raise ValueError(f"empty qualification input: {path}")
        for item in files:
            name = item.relative_to(path).as_posix() if path.is_dir() else path.name
            digest.update(f"{index}:{name}\0".encode())
            content = hashlib.sha256()
            with item.open("rb") as stream:
                if item == build_profile:
                    # Keep the receipt, but do not mistake a rebuild time for
                    # different compiler, units or profile options.
                    for line in stream:
                        if not line.startswith(b"built_utc="):
                            content.update(line)
                else:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        content.update(block)
            digest.update(content.digest())
    return digest.hexdigest()


def product_identity(root: Path) -> str:
    return digest_paths([root / "toolchain", root / "runtime/mm"],
                        build_profile=root / "toolchain/profile.txt")
