#!/usr/bin/env bash
#
# Prove the identity survives a restart: launch against a FIXED user-dir, read
# the address, kill, relaunch against the SAME dir, read it again.
#
#   ./scripts/run-identity.sh
#
# A "does identity.key exist" check would be worthless — a file holding key
# material proves nothing unless the address it produces is the same afterwards.
#
set -uo pipefail
cd "$(dirname "$0")/.."
MOD=plugins/peers_ui
PORT=${PORT:-5595}
DIR=${DIR:-/extra/tmp/peers-identity-run}
STATE=/extra/tmp/peers-identity-check.json
LOG=/extra/tmp/peers-identity.log

# The app leaks its module hosts when the `nix run` wrapper is killed, and they
# keep holding the inspector port — a later run then reads the OLD instance.
kill_all() {
  pkill -f "[l]ogos-standalone-app-bin.*$DIR" 2>/dev/null
  for i in $(seq 1 20); do
    ss -tln 2>/dev/null | grep -q ":$PORT " || return 0
    sleep 1
  done
  echo "WARNING: port $PORT still held after 20s" >&2
}

launch() {
  ( cd "$MOD" && \
    QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT="$PORT" TMPDIR=/extra/tmp \
    PEERS_DELIVERY_NODE="" \
    setsid nix run . --accept-flake-config -- --user-dir "$DIR" > "$LOG" 2>&1 & )
  for i in $(seq 1 60); do
    ss -tln 2>/dev/null | grep -q ":$PORT " && return 0
    sleep 5
  done
  echo "FAILED: the instance never opened its inspector port" >&2
  return 1
}

kill_all
rm -rf "$DIR" "$STATE"      # a first run must start with no identity at all
mkdir -p "$DIR"

echo "── first launch (fresh: mints and persists an identity) ──"
launch || exit 1
node tests/identity-persists.mjs "$PORT" first "$STATE" || { kill_all; exit 1; }
kill_all

keys=$(find "$DIR" -name identity.key 2>/dev/null | head -1)
if [ -z "$keys" ]; then
  echo "FAILED: no identity.key was written — nothing can survive a restart." >&2
  exit 1
fi
echo "identity.key: $keys ($(stat -c%s "$keys") bytes, mode $(stat -c%a "$keys"))"

echo "── second launch (SAME user-dir: must rehydrate) ──"
launch || exit 1
node tests/identity-persists.mjs "$PORT" second "$STATE"; rc=$?
kill_all
exit $rc
