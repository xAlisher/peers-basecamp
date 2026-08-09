#!/usr/bin/env bash
#
# Does the module actually LOAD? Run after every build, before any scenario.
#
# The trap this exists to close: grepping a log for failure strings PASSES ON AN
# EMPTY LOG. Two different silent failures (an unlisted .cpp, a hand-written
# qmldir) produce no error output at all — the app just stops before the UI and
# hangs. So this asserts a POSITIVE marker that only appears once the plugin has
# loaded and driven the core, and treats its absence as failure.
#
set -uo pipefail
cd "$(dirname "$0")/.."

DIR=${1:-/extra/tmp/peers-loadcheck}
LOG=$DIR.log
# The core only logs this after the UI plugin has loaded and its context is
# ready, so it is proof of a working plugin, not just a running process.
MARKER="peers_core: init"

pkill -f '[l]ogos-standalone-app-bin' 2>/dev/null
sleep 2
rm -rf "$DIR" && mkdir -p "$DIR"

( cd plugins/peers_ui \
  && QT_QPA_PLATFORM=offscreen TMPDIR=/extra/tmp PEERS_DELIVERY_NODE="" \
     timeout 90 nix run . --accept-flake-config -- --user-dir "$DIR" ) > "$LOG" 2>&1
pkill -f '[l]ogos-standalone-app-bin' 2>/dev/null

if ! grep -q "$MARKER" "$LOG"; then
  echo "FAIL: the module never loaded — '$MARKER' never appeared."
  echo "      Log: $LOG ($(wc -l < "$LOG") lines). Last 5:"
  tail -5 "$LOG" | sed 's/^/      /'
  echo
  echo "      Most likely causes, in order:"
  echo "        1. a new .cpp missing from plugins/peers_ui/CMakeLists.txt SOURCES"
  echo "           (check: nm -D --undefined-only <plugin>.so)"
  echo "        2. an untracked file under src/ (the flake src is a git source)"
  echo "        3. a hand-written src/qml/qmldir"
  exit 1
fi

if grep -qiE "Failed to load UI plugin|crashed \(signal|is not a type|\.qml:[0-9]+:[0-9]+" "$LOG"; then
  echo "FAIL: the module loaded but reported QML/plugin errors:"
  grep -iE "Failed to load UI plugin|crashed \(signal|is not a type|\.qml:[0-9]+:[0-9]+" "$LOG" \
    | head -10 | sed 's/^/      /'
  exit 1
fi

echo "ok: module loads clean ($(wc -l < "$LOG") log lines, '$MARKER' seen)"
