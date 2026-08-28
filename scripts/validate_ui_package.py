#!/usr/bin/env python3
"""Validate the peers_ui linux-amd64 package before installation."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import stat
import sys

from validate_core_package import (
    MAX_MANIFEST_BYTES,
    MAX_PACKAGE_ENTRIES,
    REQUIRED_LIBRARIES,
    VARIANT,
    readelf,
    real_nonempty,
    validate_shared_object,
)

PLUGIN = "peers_ui_plugin.so"
REPLICA = "peers_ui_replica_factory.so"
VIEW = "qml/PeersView.qml"
ICON = "Peers_sidebar.png"
METADATA = "metadata.json"
RUNTIME_ASSETS = frozenset({
    ICON,
    METADATA,
    "qml/AddressCard.qml",
    "qml/BubbleActionMenu.qml",
    "qml/ClipboardProxy.qml",
    "qml/Composer.qml",
    "qml/ContactsPanel.qml",
    "qml/ConversationRow.qml",
    "qml/EmojiGrid.qml",
    "qml/EmptyState.qml",
    "qml/ForwardPicker.qml",
    "qml/GroupInfoPanel.qml",
    "qml/HexAvatar.qml",
    "qml/Identicon.js",
    "qml/MediaViewer.qml",
    "qml/MessageBubble.qml",
    "qml/MessageLayout.js",
    "qml/PeersIcon.qml",
    VIEW,
    "qml/PinnedBar.qml",
    "qml/SettingsPanel.qml",
    "qml/Theme.js",
    "qml/Toast.qml",
    "qml/icons/Peers_sidebar.png",
    "qml/qmldir",
})
EXPECTED_FILES = frozenset({
    "manifest.json",
    "variant",
    PLUGIN,
    REPLICA,
    *REQUIRED_LIBRARIES,
    *RUNTIME_ASSETS,
})
EXPECTED_DIRECTORIES = frozenset(
    parent.as_posix()
    for relative in EXPECTED_FILES
    for parent in Path(relative).parents
    if parent != Path(".")
)


def validate(root: Path) -> None:
    if root.is_symlink() or not root.is_dir():
        raise ValueError("staged package must be a real directory")

    entries = 0
    actual_files: set[str] = set()
    actual_directories: set[str] = set()
    for current, directories, files in os.walk(root, followlinks=False):
        for name in [*directories, *files]:
            entries += 1
            if entries > MAX_PACKAGE_ENTRIES:
                raise ValueError("staged package has too many entries")
            path = Path(current) / name
            mode = path.lstat().st_mode
            if name in directories:
                if not stat.S_ISDIR(mode):
                    raise ValueError("staged package contains an invalid directory")
                actual_directories.add(path.relative_to(root).as_posix())
            elif not stat.S_ISREG(mode):
                raise ValueError("staged package contains a non-regular file")
            else:
                actual_files.add(path.relative_to(root).as_posix())
    boost = [name for name in actual_files if name.startswith("libboost_system.so.")]
    if len(boost) != 1:
        raise ValueError("expected exactly one bundled Boost.System library")
    expected_files = EXPECTED_FILES | {boost[0]}
    if actual_files != expected_files:
        missing = sorted(expected_files - actual_files)
        unexpected = sorted(actual_files - expected_files)
        raise ValueError(f"unexpected package tree: missing={missing}, unexpected={unexpected}")
    if actual_directories != EXPECTED_DIRECTORIES:
        missing = sorted(EXPECTED_DIRECTORIES - actual_directories)
        unexpected = sorted(actual_directories - EXPECTED_DIRECTORIES)
        raise ValueError(f"unexpected package directories: missing={missing}, unexpected={unexpected}")

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
    if manifest.get("name") != "peers_ui" or manifest.get("type") != "ui_qml":
        raise ValueError("manifest is not the peers_ui package")
    dependencies = manifest.get("dependencies")
    if not isinstance(dependencies, list) or len(dependencies) != 2 \
            or set(dependencies) != {"peers_core", "delivery_module"}:
        raise ValueError("manifest does not declare required dependencies")
    main = manifest.get("main")
    if main != {VARIANT: PLUGIN}:
        raise ValueError("manifest has an unexpected linux-amd64 entry point")
    if manifest.get("view") != VIEW or manifest.get("icon") != ICON:
        raise ValueError("manifest has an unexpected view or icon")

    for relative in RUNTIME_ASSETS:
        if not real_nonempty(root / relative):
            raise ValueError(f"missing or invalid {relative}")
    for relative in (PLUGIN, REPLICA, *REQUIRED_LIBRARIES):
        validate_shared_object(root / relative)
    boost_path = root / boost[0]
    validate_shared_object(boost_path)

    dynamic = readelf(root / PLUGIN, "-dW")
    needed = set(re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", dynamic))
    expected = {*REQUIRED_LIBRARIES, boost_path.name}
    if not expected.issubset(needed):
        missing = ", ".join(sorted(expected - needed))
        raise ValueError(f"plugin does not declare bundled runtime libraries: {missing}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <staged-peers-ui>", file=sys.stderr)
        return 2
    try:
        validate(Path(sys.argv[1]).absolute())
    except Exception as exc:
        print(f"invalid peers_ui package: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
