#!/usr/bin/env python3
"""Validate a staged peers_ui package, then atomically install it."""

from __future__ import annotations

from pathlib import Path
import sys

from atomic_replace import atomic_replace
from validate_ui_package import validate


def install(staged: Path, destination: Path) -> None:
    validate(staged)
    atomic_replace(staged, destination)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <staged-dir> <destination-dir>", file=sys.stderr)
        return 2
    try:
        install(Path(sys.argv[1]).absolute(), Path(sys.argv[2]).absolute())
    except Exception as exc:
        print(f"UI installation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
