#!/usr/bin/env python3
"""Validate the pinned peers_core linux-amd64 package before installation."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

VARIANT = "linux-amd64"
PLUGIN = "peers_core_plugin.so"
REQUIRED_LIBRARIES = ("libssl.so.3", "libcrypto.so.3")
MAX_MANIFEST_BYTES = 64 * 1024
MAX_READELF_OUTPUT = 64 * 1024
MAX_PACKAGE_ENTRIES = 4096


def real_nonempty(path: Path) -> bool:
    return not path.is_symlink() and path.is_file() and path.stat().st_size > 0


def readelf(path: Path, mode: str) -> str:
    executable = shutil.which("readelf")
    if not executable:
        raise ValueError("readelf is required for package validation")
    temp_root = os.environ.get("TMPDIR", "/extra/tmp")
    with tempfile.TemporaryFile(dir=temp_root) as output:
        result = subprocess.run(
            [executable, mode, str(path)],
            stdin=subprocess.DEVNULL,
            stdout=output,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
        size = output.tell()
        if result.returncode != 0 or size > MAX_READELF_OUTPUT:
            raise ValueError(f"readelf rejected {path.name}")
        output.seek(0)
        return output.read().decode("utf-8", "strict")


def validate_shared_object(path: Path) -> None:
    if not real_nonempty(path):
        raise ValueError(f"missing or invalid {path.name}")
    header = readelf(path, "-hW")
    required = (
        r"Class:\s+ELF64",
        r"Data:\s+2's complement, little endian",
        r"Type:\s+DYN \(Shared object file\)",
        r"Machine:\s+Advanced Micro Devices X86-64",
    )
    if any(re.search(pattern, header) is None for pattern in required):
        raise ValueError(f"{path.name} is not a linux-amd64 shared object")


def validate(root: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("staged package must be a real directory")

    entries = 0
    for current, directories, files in os.walk(root, followlinks=False):
        for name in [*directories, *files]:
            entries += 1
            if entries > MAX_PACKAGE_ENTRIES:
                raise ValueError("staged package has too many entries")
            if (Path(current) / name).is_symlink():
                raise ValueError("staged package contains a symlink")

    variant = root / "variant"
    manifest_path = root / "manifest.json"
    if not real_nonempty(variant) or variant.stat().st_size > 32 \
            or variant.read_text().strip() != VARIANT:
        raise ValueError("invalid or missing variant marker")
    if not real_nonempty(manifest_path) or manifest_path.stat().st_size > MAX_MANIFEST_BYTES:
        raise ValueError("invalid or missing manifest")

    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be an object")
    if manifest.get("name") != "peers_core" or manifest.get("type") != "core":
        raise ValueError("manifest is not the peers_core package")
    dependencies = manifest.get("dependencies")
    if not isinstance(dependencies, list) or "delivery_module" not in dependencies:
        raise ValueError("manifest does not declare delivery_module")
    main = manifest.get("main")
    if not isinstance(main, dict) or main.get(VARIANT) != PLUGIN:
        raise ValueError("manifest has an unexpected linux-amd64 entry point")

    plugin_path = root / PLUGIN
    validate_shared_object(plugin_path)
    for library in REQUIRED_LIBRARIES:
        validate_shared_object(root / library)

    boost = list(root.glob("libboost_system.so.*"))
    if len(boost) != 1:
        raise ValueError("expected exactly one bundled Boost.System library")
    validate_shared_object(boost[0])

    dynamic = readelf(plugin_path, "-dW")
    needed = set(re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", dynamic))
    expected = {*REQUIRED_LIBRARIES, boost[0].name}
    if not expected.issubset(needed):
        missing = ", ".join(sorted(expected - needed))
        raise ValueError(f"plugin does not declare bundled runtime libraries: {missing}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <staged-peers-core>", file=sys.stderr)
        return 2
    try:
        validate(Path(sys.argv[1]).absolute())
    except Exception as exc:
        print(f"invalid peers_core package: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
