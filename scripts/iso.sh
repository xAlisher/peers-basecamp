#!/usr/bin/env bash
#
# Launch an isolated Basecamp carrying ONLY what Peers needs.
#
#   ./scripts/iso.sh [suffix]        # suffix lets one session run several (a, b, …)
#   ./scripts/iso.sh a --rebuild     # wipe the tree first, keeping the identity
#   ./scripts/iso.sh a --stop        # stop just this one
#
# Two things this gets right that an ad-hoc copy does not:
#
#  1. MINIMAL TREE. Copying the whole install is ~1.4 GB of 28 modules and 31
#     plugins we never load. This copies four things — peers_ui, peers_core,
#     delivery_module and lib/ — which is ~106 MB and starts faster. capability_
#     module, package_manager and package_downloader come from the AppImage
#     itself, not the tree, so they need no copy.
#
#  2. IDENTITY SURVIVES A REBUILD. peers_core keeps its account and device keys
#     in `identity.key` under its persistence path. That path lives INSIDE the
#     disposable tree, so wiping the tree used to mint a new address and the
#     phone's saved contact went dead. The identity directory is kept OUTSIDE
#     the tree and symlinked in, so redeploying a new build keeps the address.
#
# Never touches the live install, and never touches another session's iso: every
# kill is gated on an exact XDG_DATA_HOME match.
#
set -uo pipefail
cd "$(dirname "$0")/.."

SUFFIX=""
MODE="run"
for a in "$@"; do
  case "$a" in
    --rebuild) MODE="rebuild" ;;
    --stop)    MODE="stop" ;;
    -*)        echo "unknown flag: $a" >&2; exit 2 ;;
    *)         SUFFIX="$a" ;;
  esac
done

# A stable id per (session, suffix). Hex, non-empty — LOGOS_INSTANCE_ID namespaces
# the Qt abstract sockets, so a collision means two Basecamps sharing IPC.
SESS=${CLAUDE_SESSION_ID:-$(basename "$(dirname "${SCRATCHPAD:-/tmp/peers}")")}
BASE=$(printf '%s' "$SESS" | tr -dc 'a-f0-9' | cut -c1-11)
[ -n "$BASE" ] || BASE="peers0000000"
# LOGOS_INSTANCE_ID namespaces Qt's abstract sockets and is expected to be
# hex-ish, so a free-form suffix is folded into a hex digit rather than passed
# through — "a" and "b" stay themselves, "left"/"right" become stable digits.
if [ -z "$SUFFIX" ]; then
  SFX=0
elif [ "${#SUFFIX}" = 1 ] && [[ "$SUFFIX" =~ ^[a-f0-9]$ ]]; then
  SFX="$SUFFIX"
else
  SFX=$(printf '%s' "$SUFFIX" | cksum | cut -d' ' -f1)
  SFX=$(printf '%x' $((SFX % 16)))
fi
ISOID="${BASE}${SFX}"
ISO=/extra/tmp/bc-iso-$ISOID
GUI="$ISO/data/Logos/LogosBasecamp"
LOG=/extra/tmp/bc-iso-$ISOID.log
# Outside $ISO on purpose: this is what survives --rebuild.
IDENTITY=/extra/tmp/peers-iso-identity/$ISOID
LIVE="$HOME/.local/share/Logos/LogosBasecamp"

stop_mine() {
  local n=0
  for pid in $(pgrep -f "\.logos_host\.elf|\.ui-host\.elf|\.LogosBasecamp\.elf" 2>/dev/null); do
    if grep -qz "XDG_DATA_HOME=$ISO/data" /proc/"$pid"/environ 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null && n=$((n + 1))
    fi
  done
  [ "$n" -gt 0 ] && sleep 2
  echo "stopped $n process(es) belonging to $ISO"
}

if [ "$MODE" = "stop" ]; then
  stop_mine
  exit 0
fi

[ -d "$LIVE" ] || { echo "no live Basecamp install at $LIVE to copy from" >&2; exit 2; }

stop_mine
[ "$MODE" = "rebuild" ] && rm -rf "$ISO"

# ── the minimal tree ────────────────────────────────────────────────────────
mkdir -p "$GUI/modules" "$GUI/plugins" "$ISO/config" "$ISO/cache" "$IDENTITY"
[ -d "$GUI/lib" ] || cp -a "$LIVE/lib" "$GUI/" 2>/dev/null
# delivery_module is peers_core's own dependency and is not ours to build.
[ -d "$GUI/modules/delivery_module" ] || cp -a "$LIVE/modules/delivery_module" "$GUI/modules/" 2>/dev/null
printf 'session=%s id=%s peers-basecamp (minimal)\n' "$SESS" "$ISOID" > "$ISO/.owner"

# ── peers_ui + peers_core, and the dependency assertion ─────────────────────
./scripts/install-iso.sh "$ISO" || exit 1

# ── keep the identity outside the disposable tree ───────────────────────────
#
# peers_core writes identity.key under module_data/peers_core/<instance-hash>/.
# The hash is derived by the host, so rather than predict it, the whole
# module_data/peers_core directory is the symlink.
mkdir -p "$GUI/module_data"
if [ ! -L "$GUI/module_data/peers_core" ]; then
  # Adopt an identity the tree already has, so switching to this script does not
  # throw away the address you have been testing with.
  if [ -d "$GUI/module_data/peers_core" ]; then
    cp -a "$GUI/module_data/peers_core/." "$IDENTITY/" 2>/dev/null
    rm -rf "$GUI/module_data/peers_core"
  fi
  ln -s "$IDENTITY" "$GUI/module_data/peers_core"
fi
keys=$(find "$IDENTITY" -name identity.key 2>/dev/null | wc -l)
echo "identity: $IDENTITY ($keys key file(s) — 0 is fine on a first run)"

# ── launch ──────────────────────────────────────────────────────────────────
#
# XDG_RUNTIME_DIR is REQUIRED for audio: without it the instance cannot reach the
# PipeWire/Pulse socket, so voice notes record and play silently into nothing.
env LOGOS_INSTANCE_ID="$ISOID" \
    XDG_DATA_HOME="$ISO/data" XDG_CONFIG_HOME="$ISO/config" XDG_CACHE_HOME="$ISO/cache" \
    XDG_RUNTIME_DIR="/run/user/$(id -u)" \
    setsid nohup "$HOME/logos-basecamp-current.AppImage" >"$LOG" 2>&1 </dev/null &
disown
sleep 12

echo "tree:  $(du -sh "$GUI" 2>/dev/null | cut -f1)  ($(ls "$GUI/modules" | wc -l) modules, $(ls "$GUI/plugins" | wc -l) plugins)"
echo "log:   $LOG"
if grep -q "Core started" "$LOG" 2>/dev/null; then
  echo "started. Open Peers from the sidebar."
else
  echo "WARNING: 'Core started' not seen yet — check $LOG"
fi
echo "stop:  ./scripts/iso.sh ${SUFFIX:-} --stop"
