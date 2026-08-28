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
# PROCESS HYGIENE — read this before touching the launch/cleanup code.
#
# The app is `logos-standalone-app-bin`, which forks `logos_host_qt` children per
# module. Killing the `nix run` wrapper leaves ALL of them alive, still holding
# the inspector ports. A later run then launches instances that cannot bind, and
# the harness silently connects to the STALE ones — so you test an old build and
# watch state accumulate across runs while your fixes appear to do nothing.
# That cost a debugging cycle on 2026-08-09.
#
# Hence: launch under setsid and kill the whole process group, match on ARGV (not
# comm/exe, which are the ld-linux loader), and preflight the ports.
#
set -uo pipefail
cd "$(dirname "$0")/.."

MOD=plugins/peers_ui
WORK=${WORK:-/extra/tmp/peers-exchange}
A_PORT=${A_PORT:-5591}
B_PORT=${B_PORT:-5592}

reap() { # kill anything of ours still running
  for n in alice bob; do
    if [ -f "$WORK/$n.pgid" ]; then
      kill -- -"$(cat "$WORK/$n.pgid")" 2>/dev/null
    fi
  done
  pkill -f '[l]ogos-standalone-app-bin' 2>/dev/null
  pkill -f '[l]ogos_host_qt' 2>/dev/null
  sleep 2
}

# ── preflight ───────────────────────────────────────────────────────────────
# A busy inspector port means a previous run leaked. Never proceed onto a stale
# instance — that is how you spend an hour testing a build you already replaced.
for p in "$A_PORT" "$B_PORT"; do
  if ss -tln | grep -q ":$p "; then
    echo "preflight: port $p is in use by a leaked instance — reaping"
    reap
    break
  fi
done
for p in "$A_PORT" "$B_PORT"; do
  if ss -tln | grep -q ":$p "; then
    echo "ABORT: port $p is still held after reaping. Investigate before re-running;"
    echo "       continuing would test a stale instance."
    ss -tlnp | grep ":$p " || true
    exit 1
  fi
done

rm -rf "$WORK"; mkdir -p "$WORK/alice" "$WORK/bob"
trap reap EXIT

# Hosted uploads use anonymous one-use grants. Keep the legacy bearer explicitly
# absent so this harness cannot accidentally prove a credential-dependent path.
# Capability-bearing downloads remain tokenless; capless legacy downloads fail.
export PEERS_STORAGE_BASE="${PEERS_STORAGE_BASE:-https://msg.logos.live/s/api/storage/v1}"

# Two instances on ONE host must NOT pin a delivery entry node. Pinning switches
# delivery to the flat config shape, whose listening ports are FIXED — so the
# second instance collides with the first. Unpinned uses the layered shape, which
# leaves every port OS-assigned. Empty here means "use the preset's own nodes".
export PEERS_DELIVERY_NODE="${PEERS_DELIVERY_NODE-}"

launch() { # name, user-dir, inspector port
  ( cd "$MOD" && \
    env -u PEERS_STORAGE_TOKEN \
    QT_QPA_PLATFORM=offscreen QML_INSPECTOR_PORT="$3" TMPDIR=/extra/tmp \
    PEERS_STORAGE_BASE="$PEERS_STORAGE_BASE" \
    PEERS_DELIVERY_NODE="$PEERS_DELIVERY_NODE" \
    setsid nix run . --accept-flake-config -- --user-dir "$2" \
      > "$WORK/$1.log" 2>&1 &
    echo $! > "$WORK/$1.pgid" )   # setsid makes the child its own group leader
}

echo "launching two instances (inspectors on $A_PORT / $B_PORT)..."
launch alice "$WORK/alice" "$A_PORT"
launch bob   "$WORK/bob"   "$B_PORT"

for i in $(seq 1 60); do
  if ss -tln | grep -q ":$A_PORT " && ss -tln | grep -q ":$B_PORT "; then
    echo "both inspectors listening"; break
  fi
  sleep 5
done

TEST=${TEST:-tests/exchange.mjs}
node "$TEST" "$A_PORT" "$B_PORT"
rc=$?

if [ $rc -ne 0 ]; then
  echo "--- alice tail ---"; grep -vE "\[delivery_module\]" "$WORK/alice.log" | tail -15
  echo "--- bob tail ---";   grep -vE "\[delivery_module\]" "$WORK/bob.log"   | tail -15
fi
exit $rc
