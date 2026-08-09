#!/usr/bin/env bash
#
# Launch ONE peers_ui instance with the QML inspector open, print its address,
# and leave it running. For phone-interop testing, where the second peer is a
# physical device rather than another local instance.
#
#   scripts/run-one.sh [port] [user-dir]
#
# Stop it with scripts/stop-one.sh.
#
set -uo pipefail
cd "$(dirname "$0")/.."

PORT=${1:-5591}
DIR=${2:-/extra/tmp/peers-one}
MOD=plugins/peers_ui

export PEERS_STORAGE_BASE="${PEERS_STORAGE_BASE:-https://msg.logos.live/s/api/storage/v1}"
export PEERS_STORAGE_TOKEN="${PEERS_STORAGE_TOKEN:-}"

# Never proceed onto a leaked instance — you would be driving an old build.
if ss -tln | grep -q ":$PORT "; then
  echo "port $PORT is already in use; reaping leftovers"
  pkill -f '[l]ogos-standalone-app-bin' 2>/dev/null
  pkill -f '[l]ogos_host_qt' 2>/dev/null
  sleep 3
fi
if ss -tln | grep -q ":$PORT "; then
  echo "ABORT: port $PORT still held. Investigate before running."
  exit 1
fi

rm -rf "$DIR"; mkdir -p "$DIR"
( cd "$MOD" && \
  QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT="$PORT" TMPDIR=/extra/tmp \
  PEERS_STORAGE_BASE="$PEERS_STORAGE_BASE" PEERS_STORAGE_TOKEN="$PEERS_STORAGE_TOKEN" \
  setsid nix run . --accept-flake-config -- --user-dir "$DIR" \
    > /extra/tmp/peers-one.log 2>&1 & echo $! > /extra/tmp/peers-one.pgid )

for i in $(seq 1 60); do
  ss -tln | grep -q ":$PORT " && break
  sleep 5
done

node tests/whoami.mjs "$PORT"
