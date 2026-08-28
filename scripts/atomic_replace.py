#!/usr/bin/env python3
"""Atomically replace one directory with another on Linux."""

from __future__ import annotations

import ctypes
import errno
import os
from pathlib import Path
import shutil
import sys
import time

AT_FDCWD = -100
RENAME_EXCHANGE = 2


def test_pause(point: str) -> None:
    if os.environ.get("PEERS_ATOMIC_REPLACE_TEST_PAUSE") != point:
        return
    print(f"PEERS_ATOMIC_REPLACE_TEST_PAUSE:{point}", flush=True)
    while True:
        time.sleep(1)


def atomic_replace(staged: Path, destination: Path) -> None:
    if staged.parent != destination.parent:
        raise ValueError("staged and destination directories must share a parent")
    if staged.is_symlink() or not staged.is_dir():
        raise ValueError("staged path must be a real directory")
    if destination.is_symlink():
        raise ValueError("destination must not be a symlink")

    if os.environ.get("PEERS_ATOMIC_REPLACE_TEST_FAIL") == "before-exchange":
        raise RuntimeError("injected pre-exchange failure")
    test_pause("before-exchange")

    if not destination.exists():
        os.replace(staged, destination)
        return
    if not destination.is_dir():
        raise ValueError("destination must be a directory")

    libc = ctypes.CDLL(None, use_errno=True)
    renameat2 = libc.renameat2
    renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p,
                          ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    renameat2.restype = ctypes.c_int
    result = renameat2(AT_FDCWD, os.fsencode(staged),
                       AT_FDCWD, os.fsencode(destination), RENAME_EXCHANGE)
    if result != 0:
        error = ctypes.get_errno()
        if error in (errno.ENOSYS, errno.EINVAL, errno.EXDEV):
            raise OSError(error, "atomic directory exchange is unavailable")
        raise OSError(error, os.strerror(error))

    test_pause("after-exchange")
    if os.environ.get("PEERS_ATOMIC_REPLACE_TEST_FAIL") == "after-exchange":
        raise RuntimeError("injected post-exchange interruption")

    # The new core is already active. The staging path now contains the old core;
    # failure or interruption during cleanup cannot make destination disappear.
    shutil.rmtree(staged)


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <staged-dir> <destination-dir>", file=sys.stderr)
        return 2
    try:
        atomic_replace(Path(sys.argv[1]).absolute(), Path(sys.argv[2]).absolute())
    except Exception as exc:
        print(f"atomic replacement failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
