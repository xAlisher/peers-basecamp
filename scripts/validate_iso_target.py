#!/usr/bin/env python3
"""Canonicalize and validate an isolated Basecamp installation target."""

from __future__ import annotations

import os
from pathlib import Path
import sys


def validate(raw_iso: Path) -> Path:
    if "\n" in str(raw_iso) or "\r" in str(raw_iso):
        raise ValueError("ISO path contains a line break")
    if raw_iso.is_symlink() or not raw_iso.is_dir():
        raise ValueError("ISO root must be a real directory")
    iso = raw_iso.resolve(strict=True)
    if "\n" in str(iso) or "\r" in str(iso):
        raise ValueError("canonical ISO path contains a line break")

    components = (
        iso / "data",
        iso / "data/Logos",
        iso / "data/Logos/LogosBasecamp",
        iso / "data/Logos/LogosBasecamp/plugins",
        iso / "data/Logos/LogosBasecamp/modules",
    )
    for component in components:
        if component.is_symlink() or not component.is_dir():
            raise ValueError(f"isolated target component is missing or symlinked: {component.name}")

    gui = components[2].resolve(strict=True)
    live = (Path(os.environ["HOME"]) / ".local/share/Logos/LogosBasecamp").resolve(strict=False)
    live_share = (Path(os.environ["HOME"]) / ".local/share").resolve(strict=False)
    if iso == live_share or live_share in iso.parents:
        raise ValueError("ISO root resolves inside the live data tree")
    if gui == live or live in gui.parents or gui in live.parents:
        raise ValueError("isolated GUI resolves to or overlaps the live installation")

    for component in components[3:]:
        resolved = component.resolve(strict=True)
        if gui not in resolved.parents:
            raise ValueError("plugin/module root escapes the isolated GUI")
    return iso


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <iso-dir>", file=sys.stderr)
        return 2
    try:
        print(validate(Path(sys.argv[1]).absolute()))
    except Exception as exc:
        print(f"invalid isolated target: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
