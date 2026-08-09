#!/usr/bin/env bash
# Every non-build gate in one command, so "did I break something" is one line.
# Run before every commit.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
echo "== identicon equivalence =="; node tests/identicon-equivalence.mjs;  [ $? -ne 0 ] && fail=1
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
