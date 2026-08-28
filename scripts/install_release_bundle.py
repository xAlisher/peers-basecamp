#!/usr/bin/env python3
"""Validate both Peers packages and activate one coherent Basecamp data-root snapshot."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys
import tempfile

from atomic_replace import atomic_replace
from validate_core_package import validate as validate_core
from validate_ui_package import validate as validate_ui


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def install(ui_staged: Path, core_staged: Path, gui_root: Path) -> None:
    validate_ui(ui_staged)
    validate_core(core_staged)
    if gui_root.is_symlink() or not gui_root.is_dir():
        raise ValueError("Basecamp data root must be a real directory")
    if gui_root.parent.is_symlink() or not gui_root.parent.is_dir():
        raise ValueError("Basecamp data-root parent must be a real directory")
    for source in (ui_staged, core_staged):
        if gui_root == source or gui_root in source.parents or source in gui_root.parents:
            raise ValueError("package stage must be outside the Basecamp data root")

    stage = Path(tempfile.mkdtemp(prefix=f".{gui_root.name}.release-", dir=gui_root.parent))
    stage.rmdir()
    exchange_attempted = False
    try:
        shutil.copytree(gui_root, stage, symlinks=True)
        ui_destination = stage / "plugins/peers_ui"
        core_destination = stage / "modules/peers_core"
        remove_path(ui_destination)
        remove_path(core_destination)
        ui_destination.parent.mkdir(parents=True, exist_ok=True)
        core_destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(ui_staged, ui_destination, symlinks=False)
        shutil.copytree(core_staged, core_destination, symlinks=False)
        validate_ui(ui_destination)
        validate_core(core_destination)
        exchange_attempted = True
        atomic_replace(stage, gui_root)
    except Exception:
        # A deliberate post-exchange interruption leaves the new complete root active and
        # the recoverable old root at stage. Never delete that old snapshot here.
        if not (exchange_attempted
                and os.environ.get("PEERS_ATOMIC_REPLACE_TEST_FAIL") == "after-exchange"):
            remove_path(stage)
        raise


def main() -> int:
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} <staged-ui> <staged-core> <basecamp-data-root>",
              file=sys.stderr)
        return 2
    try:
        install(*(Path(value).absolute() for value in sys.argv[1:]))
    except Exception as exc:
        print(f"release installation failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
