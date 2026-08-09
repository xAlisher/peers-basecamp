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
[ $fail -eq 0 ] && echo "ALL GREEN" || echo "SOMETHING FAILED"
exit $fail
