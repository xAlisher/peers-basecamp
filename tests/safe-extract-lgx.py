#!/usr/bin/env python3
"""Executable hostile LGX extraction regressions."""

from __future__ import annotations

import io
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "scripts/safe_extract_lgx.py"


def add_bytes(package: tarfile.TarFile, name: str, data: bytes) -> None:
    member = tarfile.TarInfo(name)
    member.size = len(data)
    member.mode = 0o644
    package.addfile(member, io.BytesIO(data))


def run_case(root: Path, label: str, build, should_pass: bool) -> None:
    archive = root / f"{label}.lgx"
    destination = root / f"{label}-out"
    destination.mkdir()
    with tarfile.open(archive, "w:gz") as package:
        build(package)
    result = subprocess.run(
        ["python3", "-B", str(EXTRACTOR), str(archive), str(destination)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if should_pass:
        assert result.returncode == 0, f"valid archive rejected: {label}"
        assert (destination / "manifest.json").read_bytes() == b"{}"
        assert (destination / "variants/linux-amd64/plugin.so").read_bytes() == b"elf"
    else:
        assert result.returncode != 0, f"hostile archive accepted: {label}"
        assert not any(destination.iterdir()), f"rejected archive wrote output: {label}"


def valid(package: tarfile.TarFile) -> None:
    for name in ("variants", "variants/linux-amd64"):
        directory = tarfile.TarInfo(name)
        directory.type = tarfile.DIRTYPE
        directory.mode = 0o755
        package.addfile(directory)
    add_bytes(package, "manifest.json", b"{}")
    add_bytes(package, "variants/linux-amd64/plugin.so", b"elf")


with tempfile.TemporaryDirectory(prefix="peers-lgx-test-", dir="/extra/tmp") as temporary:
    root = Path(temporary)
    run_case(root, "valid", valid, True)

    def traversal(package: tarfile.TarFile) -> None:
        valid(package)
        add_bytes(package, "../escape", b"bad")
    run_case(root, "traversal", traversal, False)

    def symlink(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/link")
        member.type = tarfile.SYMTYPE
        member.linkname = "/tmp/target"
        package.addfile(member)
    run_case(root, "symlink", symlink, False)

    def fifo(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/fifo")
        member.type = tarfile.FIFOTYPE
        package.addfile(member)
    run_case(root, "fifo", fifo, False)

    def duplicate(package: tarfile.TarFile) -> None:
        valid(package)
        add_bytes(package, "manifest.json", b"replacement")
    run_case(root, "duplicate", duplicate, False)

    def dot_root(package: tarfile.TarFile) -> None:
        valid(package)
        directory = tarfile.TarInfo(".")
        directory.type = tarfile.DIRTYPE
        package.addfile(directory)
    run_case(root, "dot-root", dot_root, False)

    def parent_as_file(package: tarfile.TarFile) -> None:
        add_bytes(package, "manifest.json", b"{}")
        add_bytes(package, "variants", b"not a directory")
    run_case(root, "parent-as-file", parent_as_file, False)

    def prefix_as_file(package: tarfile.TarFile) -> None:
        add_bytes(package, "manifest.json", b"{}")
        add_bytes(package, "variants/linux-amd64", b"not a directory")
    run_case(root, "prefix-as-file", prefix_as_file, False)

    def sibling_variant(package: tarfile.TarFile) -> None:
        valid(package)
        add_bytes(package, "variants/linux-arm64/plugin.so", b"elf")
    run_case(root, "sibling-variant", sibling_variant, False)

    def unexpected_root(package: tarfile.TarFile) -> None:
        valid(package)
        add_bytes(package, "unexpected/file", b"bad")
    run_case(root, "unexpected-root", unexpected_root, False)

print("ok: LGX extraction rejects hostile members before writing")
