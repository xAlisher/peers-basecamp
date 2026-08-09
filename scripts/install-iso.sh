#!/usr/bin/env bash
#
# Install Peers into an ISOLATED Basecamp tree — BOTH halves of it.
#
# The bug this exists to prevent: peers_ui declares a dependency on peers_core,
# and deploying only the UI plugin leaves that dependency unsatisfiable. The app
# then does NOTHING when you click Peers, and the only trace is a line in the
# log you have to already know to look for:
#
#     [warning] [logos] Module not found in known modules: peers_core
#     [warning] [logos] Cannot resolve dependencies for: peers_core
#
# Nothing crashes, nothing is highlighted, and a post-launch health check run
# BEFORE anyone clicks the module looks perfectly clean — module loading is lazy.
#
#   ./scripts/install-iso.sh <iso-dir>          # e.g. /extra/tmp/bc-iso-ab12cd34ef56
#
# Refuses to touch the live install. Does not launch anything — that is the
# caller's job (see the run-isolated skill).
#
set -uo pipefail
cd "$(dirname "$0")/.."

ISO=${1:-}
if [ -z "$ISO" ]; then
  echo "usage: $0 <iso-dir>" >&2
  exit 2
fi

GUI="$ISO/data/Logos/LogosBasecamp"
case "$ISO" in
  "$HOME"/.local/share*|"$HOME"/.local/share)
    echo "REFUSING: that is the live install, not an iso." >&2; exit 2 ;;
esac
if [ ! -d "$GUI/plugins" ] || [ ! -d "$GUI/modules" ]; then
  echo "REFUSING: $GUI does not look like a Basecamp tree." >&2; exit 2
fi
if pgrep -f "\.LogosBasecamp\.elf" >/dev/null 2>&1; then
  for pid in $(pgrep -f "\.logos_host\.elf|\.ui-host\.elf|\.LogosBasecamp\.elf" 2>/dev/null); do
    if grep -qz "XDG_DATA_HOME=$ISO/data" /proc/"$pid"/environ 2>/dev/null; then
      echo "REFUSING: that iso is RUNNING (pid $pid). Stop it first." >&2; exit 2
    fi
  done
fi

# ── the UI plugin, from this working tree ───────────────────────────────────
echo "building peers_ui…"
( cd plugins/peers_ui \
  && TMPDIR=/extra/tmp nix build .#packages.x86_64-linux.lgx-portable \
       --accept-flake-config -o /extra/tmp/peers-ui-lgx ) || exit 1
UI_LGX=$(find /extra/tmp/peers-ui-lgx/ -name '*.lgx' | head -1)
[ -n "$UI_LGX" ] || { echo "no .lgx produced" >&2; exit 1; }

SC=$(mktemp -d /extra/tmp/peers-lgx-XXXX)
tar xzf "$UI_LGX" -C "$SC"
mkdir -p "$GUI/plugins/peers_ui"
chmod -R u+w "$GUI/plugins/peers_ui"
cp -rf "$SC/variants/linux-amd64/." "$GUI/plugins/peers_ui/"
cp -f  "$SC/manifest.json" "$GUI/plugins/peers_ui/manifest.json"
printf 'linux-amd64' > "$GUI/plugins/peers_ui/variant"
chmod -R u+w "$GUI/plugins/peers_ui"
echo "  plugins/peers_ui  ok"

# ── the core module it depends on ───────────────────────────────────────────
#
# peers_core is a SEPARATE artifact from a SEPARATE repo. It is the half that
# gets forgotten, because the UI is what you were working on.
if [ "$(ls -A "$GUI/modules/peers_core" 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "  modules/peers_core already present — leaving it"
else
  echo "building peers_core (github:xAlisher/peers-core)…"
  TMPDIR=/extra/tmp nix build "github:xAlisher/peers-core#packages.x86_64-linux.lgx-portable" \
    --accept-flake-config -o /extra/tmp/peers-core-lgx || {
      echo "FAILED to build peers_core. The UI will install but Peers will do" >&2
      echo "NOTHING when clicked — it cannot resolve its dependency." >&2
      exit 1
    }
  CORE_LGX=$(find /extra/tmp/peers-core-lgx/ -name '*.lgx' | head -1)
  SC2=$(mktemp -d /extra/tmp/peers-core-XXXX)
  tar xzf "$CORE_LGX" -C "$SC2"
  mkdir -p "$GUI/modules/peers_core"
  chmod -R u+w "$GUI/modules/peers_core"
  cp -rf "$SC2/variants/linux-amd64/." "$GUI/modules/peers_core/"
  cp -f  "$SC2/manifest.json" "$GUI/modules/peers_core/manifest.json"
  printf 'linux-amd64' > "$GUI/modules/peers_core/variant"
  chmod -R u+w "$GUI/modules/peers_core"
  echo "  modules/peers_core  ok"
fi

rm -rf "$ISO/cache/Logos/LogosBasecamp/qmlcache/"* 2>/dev/null

# ── assert BOTH halves, and every dependency the manifest names ─────────────
fail=0
for dep in $(python3 -c "
import json
print(' '.join(json.load(open('$GUI/plugins/peers_ui/manifest.json')).get('dependencies', [])))
" 2>/dev/null); do
  n=$(ls -A "$GUI/modules/$dep" 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then
    echo "FAIL: peers_ui depends on '$dep' and $GUI/modules/$dep is missing or empty."
    echo "      Clicking Peers will do nothing, silently."
    fail=1
  else
    echo "  dep $dep  ok ($n files, variant=$(cat "$GUI/modules/$dep/variant" 2>/dev/null))"
  fi
done

[ "$fail" -eq 0 ] || exit 1
echo "installed into $ISO — launch it with the run-isolated recipe."
