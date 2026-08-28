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
#   ./scripts/install-iso.sh <iso-dir> [basecamp-appimage]
#                                              # e.g. /extra/tmp/bc-iso-ab12cd34ef56
#
# Refuses to touch the live install. Does not launch anything — that is the
# caller's job (see the run-isolated skill).
#
set -euo pipefail
cd "$(dirname "$0")/.."

SC=""
SC2=""
CORE_STAGE=""
UI_STAGE=""
cleanup() {
  [ -z "$SC" ] || rm -rf "$SC"
  [ -z "$SC2" ] || rm -rf "$SC2"
  [ -z "$CORE_STAGE" ] || rm -rf "$CORE_STAGE"
  [ -z "$UI_STAGE" ] || rm -rf "$UI_STAGE"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ISO=${1:-}
BASECAMP_APPIMAGE=${2:-${BASECAMP_APPIMAGE:-}}
if [ -z "$ISO" ]; then
  echo "usage: $0 <iso-dir>" >&2
  exit 2
fi

ISO=$(python3 scripts/validate_iso_target.py "$ISO")
GUI="$ISO/data/Logos/LogosBasecamp"
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
python3 -B scripts/safe_extract_lgx.py "$UI_LGX" "$SC"
UI_STAGE=$(mktemp -d /extra/tmp/peers-ui-stage-XXXX)
cp -rf "$SC/variants/linux-amd64/." "$UI_STAGE/"
cp -f "$SC/manifest.json" "$UI_STAGE/manifest.json"
printf 'linux-amd64' > "$UI_STAGE/variant"
chmod -R u+w "$UI_STAGE"

# ── the core module it depends on ───────────────────────────────────────────
#
# peers_core is a SEPARATE artifact from a SEPARATE repo. Install the exact
# revision pinned by peers_ui's flake.lock every time: retaining an older module
# package silently defeats fixes such as conversation persistence while the UI
# itself appears current. Identity/history data live under module_data, not here.
CORE_REV=$(python3 - "plugins/peers_ui/flake.lock" <<'PY'
import json
import sys
lock = json.load(open(sys.argv[1]))
print(lock["nodes"]["peers_core"]["locked"]["rev"])
PY
)
[ -n "$CORE_REV" ] || { echo "cannot resolve pinned peers_core revision" >&2; exit 1; }
echo "building peers_core (pinned $CORE_REV)…"
TMPDIR=/extra/tmp nix build \
  "github:xAlisher/peers-core/${CORE_REV}#packages.x86_64-linux.lgx-portable" \
  --accept-flake-config -o /extra/tmp/peers-core-lgx || {
    echo "FAILED to build peers_core. The existing UI/core release remains active." >&2
    exit 1
  }
CORE_LGX=$(find /extra/tmp/peers-core-lgx/ -name '*.lgx' | head -1)
[ -n "$CORE_LGX" ] && [ -f "$CORE_LGX" ] || {
  echo "no peers_core .lgx produced" >&2
  exit 1
}
SC2=$(mktemp -d /extra/tmp/peers-core-XXXX)
python3 -B scripts/safe_extract_lgx.py "$CORE_LGX" "$SC2"
[ -d "$SC2/variants/linux-amd64" ] && [ -s "$SC2/manifest.json" ] || {
  echo "invalid peers_core package: variant or manifest missing" >&2
  exit 1
}
CORE_STAGE=$(mktemp -d /extra/tmp/peers-core-stage-XXXX)
cp -rf "$SC2/variants/linux-amd64/." "$CORE_STAGE/"
cp -f "$SC2/manifest.json" "$CORE_STAGE/manifest.json"
printf 'linux-amd64' > "$CORE_STAGE/variant"
chmod -R u+w "$CORE_STAGE"
[ -s "$CORE_STAGE/manifest.json" ] && [ -s "$CORE_STAGE/variant" ] \
  && [ -n "$(find "$CORE_STAGE" -type f ! -name manifest.json ! -name variant -print -quit)" ] || {
  echo "invalid staged peers_core tree" >&2
  exit 1
}
rm -rf "$ISO/cache/Logos/LogosBasecamp/qmlcache/"* 2>/dev/null
python3 -B scripts/install_release_bundle.py "$UI_STAGE" "$CORE_STAGE" "$GUI"
echo "  plugins/peers_ui  ok"
echo "  modules/peers_core  ok"

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
if [ -n "$BASECAMP_APPIMAGE" ]; then
  python3 scripts/artifact_identity.py \
    --ui-lgx "$UI_LGX" \
    --core-lgx "$CORE_LGX" \
    --iso "$ISO" \
    --appimage "$BASECAMP_APPIMAGE" \
    --core-rev "$CORE_REV" \
    --output "${PEERS_IDENTITY_REPORT:-/extra/tmp/peers-release-identity.json}"
fi
echo "installed into $ISO — launch it with the run-isolated recipe."
