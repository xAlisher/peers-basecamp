#!/usr/bin/env bash
# Every non-build gate in one command, so "did I break something" is one line.
# Run before every commit.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
echo "== identicon equivalence =="; node tests/identicon-equivalence.mjs;  [ $? -ne 0 ] && fail=1
# Our inline-payload markers must parse with Peers Android's OWN parsers. The
# separator was U+001F for a long time where the phone uses U+241F — desktop
# ⇄desktop never noticed, and every photo and voice note arrived on the phone as
# unreadable text.
echo "== wire format vs Peers Android =="
node tests/wire-separator.mjs; rc=$?
[ $rc -eq 2 ] && echo "  (skipped: no Android checkout)"
[ $rc -eq 1 ] && fail=1
echo "== parity matrix =="       ; ./scripts/check-parity.sh;              [ $? -ne 0 ] && fail=1
# The qmldir trap: qml/qmldir is builder-owned. Shipping our own silently breaks
# the plugin load (see fails/2026-08-09-*.md and the basecamp skill).
echo "== qmldir guard =="
if [ -e plugins/peers_ui/src/qml/qmldir ]; then
  echo "FAIL: plugins/peers_ui/src/qml/qmldir exists — it will replace the builder's"
  echo "      'module com.logos.module.peers_ui' line and the plugin will not load."
  fail=1
else
  echo "ok: no hand-written qml/qmldir"
fi
# The flake's `src` is a GIT source: it only sees files that have been `git
# add`-ed. An untracked .qml is simply absent from the build, so its type does
# not exist and the whole view fails to load — with no QML error, just a
# capability_module SIGSEGV. Cost a long bisect on 2026-08-09 (AddressCard.qml).
# A .cpp that is not in CMakeLists.txt SOURCES still passes `nix build`: the
# plugin links as a shared object with unresolved symbols, then fails to dlopen
# at runtime. The host prints NOTHING — the app simply stops before the UI loads
# and hangs. Cost a full bisect on 2026-08-09 (VoiceRecorder.cpp).
echo "== cmake source-list guard =="
missing=""
for f in plugins/peers_ui/src/*.cpp plugins/peers_ui/src/*.h; do
  base="src/$(basename "$f")"
  grep -q "$base\b" plugins/peers_ui/CMakeLists.txt || missing="$missing $base"
done
if [ -n "$missing" ]; then
  echo "FAIL: not listed in plugins/peers_ui/CMakeLists.txt SOURCES:$missing"
  echo "      The plugin will build, then fail to dlopen with undefined symbols."
  fail=1
else
  echo "ok: every module source is in the CMake source list"
fi

echo "== untracked source guard =="
untracked=$(git ls-files --others --exclude-standard plugins/peers_ui/src 2>/dev/null)
if [ -n "$untracked" ]; then
  echo "FAIL: untracked files under plugins/peers_ui/src — the nix build will NOT see them:"
  echo "$untracked" | sed 's/^/      /'
  echo "      git add them before building."
  fail=1
else
  echo "ok: no untracked module sources"
fi

[ $fail -eq 0 ] && echo "ALL GREEN" || echo "SOMETHING FAILED"
exit $fail
