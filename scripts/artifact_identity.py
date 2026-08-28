#!/usr/bin/env python3
"""Generate a secret-safe identity report for final Basecamp release artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile
import tempfile
import sys

VARIANT = "linux-amd64"
MAX_FILES = 2048
MAX_FILE_BYTES = 512 * 1024 * 1024


def sha256_file(path: Path) -> tuple[str, int]:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"artifact is missing, non-file, or symlinked: {path}")
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            size += len(chunk)
            digest.update(chunk)
    return digest.hexdigest(), size


def hash_bytes(data: bytes) -> dict[str, object]:
    return {"sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}


def package_payload(archive: Path) -> dict[str, dict[str, object]]:
    archive_hash, _ = sha256_file(archive)
    del archive_hash
    payload: dict[str, dict[str, object]] = {}
    count = 0
    with tarfile.open(archive, "r:gz") as package:
        for member in package:
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            if not name or member.isdir():
                continue
            count += 1
            if count > MAX_FILES:
                raise ValueError(f"too many files in {archive.name}")
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or member.issym() or member.islnk() \
                    or not member.isfile():
                raise ValueError(f"unsafe package entry: {member.name}")
            if member.size < 0 or member.size > MAX_FILE_BYTES:
                raise ValueError(f"oversized package entry: {member.name}")
            if path == PurePosixPath("manifest.json"):
                installed_name = "manifest.json"
            elif len(path.parts) >= 3 and path.parts[:2] == ("variants", VARIANT):
                installed_name = PurePosixPath(*path.parts[2:]).as_posix()
            else:
                raise ValueError(f"unexpected package entry: {member.name}")
            if not installed_name or installed_name in payload:
                raise ValueError(f"duplicate package payload path: {installed_name}")
            source = package.extractfile(member)
            if source is None:
                raise ValueError(f"cannot read package entry: {member.name}")
            digest = hashlib.sha256()
            read_size = 0
            while chunk := source.read(1024 * 1024):
                read_size += len(chunk)
                if read_size > member.size or read_size > MAX_FILE_BYTES:
                    raise ValueError(f"package entry exceeds declared size: {member.name}")
                digest.update(chunk)
            if read_size != member.size:
                raise ValueError(f"truncated package entry: {member.name}")
            payload[installed_name] = {"sha256": digest.hexdigest(), "size": read_size}
    payload["variant"] = hash_bytes(VARIANT.encode())
    return payload


def installed_payload(root: Path, ignored_top_levels: frozenset[str] = frozenset()) -> dict[str, dict[str, object]]:
    if root.is_symlink() or not root.is_dir():
        raise ValueError(f"installed component is missing or symlinked: {root}")
    payload: dict[str, dict[str, object]] = {}
    for current, directories, files in os.walk(root, followlinks=False):
        current_path = Path(current)
        if current_path == root:
            directories[:] = [name for name in directories if name not in ignored_top_levels]
        for name in directories:
            path = current_path / name
            if path.is_symlink():
                raise ValueError(f"installed payload contains symlink: {path.relative_to(root)}")
        for name in files:
            path = current_path / name
            if path.is_symlink() or not path.is_file():
                raise ValueError(f"installed payload contains non-file or symlink: {path.relative_to(root)}")
            relative = path.relative_to(root).as_posix()
            digest, size = sha256_file(path)
            payload[relative] = {"sha256": digest, "size": size}
            if len(payload) > MAX_FILES:
                raise ValueError(f"too many installed files in {root.name}")
    return payload


def component_report(archive: Path, installed: Path,
                     ignored_top_levels: frozenset[str] = frozenset()) -> dict[str, object]:
    expected = package_payload(archive)
    actual = installed_payload(installed, ignored_top_levels)
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(name for name in set(expected) & set(actual) if expected[name] != actual[name])
        raise ValueError(
            f"payload mismatch for {installed.name}: missing={missing}, extra={extra}, changed={changed}"
        )
    return {
        "file_count": len(actual),
        "files": {name: actual[name] for name in sorted(actual)},
    }


def artifact(path: Path) -> dict[str, object]:
    digest, size = sha256_file(path)
    return {"name": path.name, "sha256": digest, "size": size}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ui-lgx", required=True, type=Path)
    parser.add_argument("--core-lgx", required=True, type=Path)
    parser.add_argument("--iso", required=True, type=Path)
    parser.add_argument("--appimage", required=True, type=Path)
    parser.add_argument("--core-rev", required=True)
    parser.add_argument("--output", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if re.fullmatch(r"[0-9a-f]{40}", args.core_rev) is None:
        raise ValueError("peers_core revision must be an exact 40-character lowercase commit")
    output = args.output.absolute()
    extra = Path("/extra").resolve()
    if extra not in output.resolve(strict=False).parents:
        raise ValueError("identity report must be written under /extra")

    gui = args.iso.absolute() / "data/Logos/LogosBasecamp"
    report = {
        "schema": 1,
        "peers_core_revision": args.core_rev,
        "artifacts": {
            "basecamp_appimage": artifact(args.appimage),
            "peers_core_lgx": artifact(args.core_lgx),
            "peers_ui_lgx": artifact(args.ui_lgx),
        },
        "components": {
            "peers_core": component_report(args.core_lgx, gui / "modules/peers_core"),
            "peers_ui": component_report(
                args.ui_lgx,
                gui / "plugins/peers_ui",
                frozenset({"media-cache"}),
            ),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=output.parent, prefix=f".{output.name}.",
                                     delete=False, encoding="utf-8") as handle:
        temporary = Path(handle.name)
        os.fchmod(handle.fileno(), 0o600)
        json.dump(report, handle, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    try:
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"artifact identity verified: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"artifact identity failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
