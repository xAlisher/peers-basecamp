#!/usr/bin/env python3
"""Preflight and safely extract a bounded Logos LGX package into an empty directory."""

from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import stat
import sys
import tarfile

MAX_ENTRIES = 4096
MAX_FILE_BYTES = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 1024 * 1024 * 1024
VARIANT_PREFIX = PurePosixPath("variants/linux-amd64")


def normalized(name: str) -> PurePosixPath:
    while name.startswith("./"):
        name = name[2:]
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts:
        raise ValueError(f"unsafe package path: {name!r}")
    return path


def extract(archive: Path, destination: Path) -> None:
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("package archive must be a real file")
    if destination.is_symlink() or not destination.is_dir() or any(destination.iterdir()):
        raise ValueError("extraction destination must be a real empty directory")

    with tarfile.open(archive, "r:gz") as package:
        members: list[tuple[tarfile.TarInfo, PurePosixPath]] = []
        seen: set[PurePosixPath] = set()
        regular_paths: set[PurePosixPath] = set()
        total_size = 0
        for member in package:
            if len(members) >= MAX_ENTRIES:
                raise ValueError("package has too many entries")
            path = normalized(member.name)
            if path in seen:
                raise ValueError(f"duplicate package path: {path}")
            seen.add(path)
            if not member.isdir() and not member.isfile():
                raise ValueError(f"package contains link or special node: {path}")
            if member.isdir():
                if path not in {PurePosixPath("variants"), VARIANT_PREFIX} \
                        and VARIANT_PREFIX not in path.parents:
                    raise ValueError(f"unexpected package directory: {path}")
            elif path != PurePosixPath("manifest.json") and VARIANT_PREFIX not in path.parents:
                raise ValueError(f"unexpected package file: {path}")
            if member.isfile():
                if member.size < 0 or member.size > MAX_FILE_BYTES:
                    raise ValueError(f"oversized package member: {path}")
                total_size += member.size
                if total_size > MAX_TOTAL_BYTES:
                    raise ValueError("package payload is too large")
                regular_paths.add(path)
            members.append((member, path))
        for path in seen:
            if any(parent in regular_paths for parent in path.parents):
                raise ValueError(f"package path conflicts with regular file: {path}")

        for member, path in members:
            target = destination.joinpath(*path.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            source = package.extractfile(member)
            if source is None:
                raise ValueError(f"cannot read package member: {path}")
            written = 0
            with target.open("xb") as output:
                while chunk := source.read(1024 * 1024):
                    written += len(chunk)
                    if written > member.size or written > MAX_FILE_BYTES:
                        raise ValueError(f"package member exceeds declared size: {path}")
                    output.write(chunk)
            if written != member.size:
                raise ValueError(f"truncated package member: {path}")
            os.chmod(target, stat.S_IMODE(member.mode) & 0o755)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <archive.lgx> <empty-destination>", file=sys.stderr)
        return 2
    try:
        extract(Path(sys.argv[1]).absolute(), Path(sys.argv[2]).absolute())
    except Exception as exc:
        print(f"unsafe LGX package: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
