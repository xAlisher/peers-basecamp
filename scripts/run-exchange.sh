#!/usr/bin/env bash
#
# Launch two peers_ui instances and run the bidirectional exchange between them.
# The primary interop gate (ADR 0003).
#
#   scripts/run-exchange.sh
#
# Exit codes mirror tests/exchange.mjs:
#   0  round-trip completed
#   1  a real assertion failed
#   2  the invite never landed — the known-flaky join step, re-run before digging
#
set -uo pipefail
cd "$(dirname "$0")/.."

MOD=plugins/peers_ui
WORK=${WORK:-/extra/tmp/peers-exchange}
A_PORT=${A_PORT:-5591}
B_PORT=${B_PORT:-5592}

rm -rf "$WORK"; mkdir -p "$WORK/alice" "$WORK/bob"

launch() { # name, user-dir, inspector port
  ( cd "$MOD" && \
    QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT="$3" TMPDIR=/extra/tmp \
    nix run . --accept-flake-config -- --user-dir "$2" \
    > "$WORK/$1.log" 2>&1 & echo $! > "$WORK/$1.pid" )
}

cleanup() {
  for n in alice bob; do
    [ -f "$WORK/$n.pid" ] && kill "$(cat "$WORK/$n.pid")" 2>/dev/null
  done
  # The standalone runner spawns a ui-host child; match on argv, since comm/exe
  # are the ld-linux loader.
  pkill -f "ui-host --name peers_ui" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT

echo "launching two instances (inspectors on $A_PORT / $B_PORT)..."
launch alice "$WORK/alice" "$A_PORT"
launch bob   "$WORK/bob"   "$B_PORT"

# Wait for both inspectors rather than sleeping a fixed amount — the first run
# after a rebuild has to realise the store paths.
for i in $(seq 1 60); do
  if ss -tln | grep -q ":$A_PORT " && ss -tln | grep -q ":$B_PORT "; then
    echo "both inspectors listening"; break
  fi
  sleep 5
done

node tests/exchange.mjs "$A_PORT" "$B_PORT"
rc=$?

if [ $rc -ne 0 ]; then
  echo "--- alice tail ---"; tail -20 "$WORK/alice.log"
  echo "--- bob tail ---";   tail -20 "$WORK/bob.log"
fi
exit $rc
