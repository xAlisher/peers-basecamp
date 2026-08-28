#!/usr/bin/env python3
"""Atomically clear an isolated Basecamp QML cache without following symlinks."""

from __future__ import annotations

from pathlib import Path
import shutil
import sys
import tempfile

from atomic_replace import atomic_replace
from validate_iso_target import validate as validate_iso


def clear(raw_iso: Path) -> None:
    iso = validate_iso(raw_iso)
    parent = iso
    for relative in ("cache", "Logos", "LogosBasecamp"):
        parent = parent / relative
        if parent.exists() or parent.is_symlink():
            if parent.is_symlink() or not parent.is_dir():
                raise ValueError(f"cache component is not a real directory: {relative}")
        else:
            parent.mkdir(mode=0o700)

    destination = parent / "qmlcache"
    if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
        raise ValueError("QML cache must be absent or a real directory")
    staged = Path(tempfile.mkdtemp(prefix=".qmlcache.empty-", dir=parent))
    try:
        atomic_replace(staged, destination)
    except Exception:
        if staged.exists() and not staged.is_symlink():
            shutil.rmtree(staged)
        raise


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <iso-dir>", file=sys.stderr)
        return 2
    try:
        clear(Path(sys.argv[1]).absolute())
    except Exception as exc:
        print(f"QML cache cleanup failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
