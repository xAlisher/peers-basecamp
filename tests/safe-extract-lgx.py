#!/usr/bin/env python3
"""Executable hostile LGX extraction regressions."""

from __future__ import annotations

import io
import importlib.util
from pathlib import Path
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EXTRACTOR = ROOT / "scripts/safe_extract_lgx.py"
SPEC = importlib.util.spec_from_file_location("safe_extract_lgx", EXTRACTOR)
assert SPEC and SPEC.loader
EXTRACTOR_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXTRACTOR_MODULE)


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
    for name in ("variants", "variants/linux-amd64", "variants/linux-amd64/qml"):
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

    def hardlink(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/hardlink")
        member.type = tarfile.LNKTYPE
        member.linkname = "manifest.json"
        package.addfile(member)
    run_case(root, "hardlink", hardlink, False)

    def character_device(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/device")
        member.type = tarfile.CHRTYPE
        package.addfile(member)
    run_case(root, "character-device", character_device, False)

    def block_device(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/block-device")
        member.type = tarfile.BLKTYPE
        package.addfile(member)
    run_case(root, "block-device", block_device, False)

    def socket_node(package: tarfile.TarFile) -> None:
        valid(package)
        member = tarfile.TarInfo("variants/linux-amd64/socket")
        member.type = b"s"
        package.addfile(member)
    run_case(root, "socket-node", socket_node, False)

    def absolute_path(package: tarfile.TarFile) -> None:
        valid(package)
        add_bytes(package, "/variants/linux-amd64/escape", b"absolute")
    run_case(root, "absolute-path", absolute_path, False)

    def path_conflict(package: tarfile.TarFile) -> None:
        add_bytes(package, "manifest.json", b"{}")
        add_bytes(package, "variants/linux-amd64/qml", b"file ancestor")
        add_bytes(package, "variants/linux-amd64/qml/view.qml", b"child")
    run_case(root, "path-conflict", path_conflict, False)

    def bounded_case(label: str, constant: str, value: int) -> None:
        archive = root / f"{label}.lgx"
        destination = root / f"{label}-out"
        destination.mkdir()
        with tarfile.open(archive, "w:gz") as package:
            valid(package)
        original = getattr(EXTRACTOR_MODULE, constant)
        setattr(EXTRACTOR_MODULE, constant, value)
        try:
            try:
                EXTRACTOR_MODULE.extract(archive, destination)
            except ValueError:
                pass
            else:
                raise AssertionError(f"archive bound was not enforced: {label}")
        finally:
            setattr(EXTRACTOR_MODULE, constant, original)
        assert not any(destination.iterdir()), f"bounded archive wrote output: {label}"

    bounded_case("entry-bound", "MAX_ENTRIES", 4)
    bounded_case("file-bound", "MAX_FILE_BYTES", 2)
    bounded_case("total-bound", "MAX_TOTAL_BYTES", 4)

print("ok: LGX extraction rejects hostile members before writing")
