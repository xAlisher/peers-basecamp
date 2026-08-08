#!/usr/bin/env bash
#
# Parity drift check.
#
# docs/PARITY.md is only useful if it stays honest, so this fails the build when
# it goes stale in the ways it actually goes stale:
#
#   1. a row carries no status, or a status outside the vocabulary;
#   2. a row is `blocked` without saying why or what the next step is;
#   3. an epic section disappears;
#   4. a marker documented in CONTENT-MARKERS.md has no parity row at all.
#
# Exit 0 = matrix is well-formed. Exit 1 = drift.
#
set -uo pipefail

cd "$(dirname "$0")/.."

PARITY=docs/PARITY.md
MARKERS=docs/CONTENT-MARKERS.md

fail=0
err() { echo "PARITY DRIFT: $*" >&2; fail=1; }

[[ -f $PARITY ]] || { err "$PARITY is missing"; exit 1; }

# ── 1 + 2: every table row has a valid status ───────────────────────────────
# A matrix row looks like: | Feature | Android | Status | Notes |
# Statuses may be wrapped in backticks and/or bold.
while IFS= read -r line; do
  # Only rows with at least 4 cells, skipping header and separator rows.
  [[ $line =~ ^\|.*\|.*\|.*\| ]] || continue
  [[ $line =~ ^\|[[:space:]]*-+ ]] && continue
  [[ $line =~ ^\|[[:space:]]*Feature[[:space:]]*\| ]] && continue
  [[ $line =~ ^\|[[:space:]]*\|[[:space:]]*Meaning ]] && continue

  status=$(awk -F'|' '{print $4}' <<<"$line" | tr -d ' `*')
  notes=$(awk -F'|' '{print $5}' <<<"$line")
  feature=$(awk -F'|' '{print $2}' <<<"$line" | sed 's/^ *//;s/ *$//')

  # The vocabulary legend table has no status column; skip anything that
  # clearly isn't a feature row.
  [[ -z $feature ]] && continue

  case "$status" in
    done|wip|todo|blocked|dropped) ;;
    "") err "row '$feature' has no status" ;;
    *)  err "row '$feature' has unknown status '$status'" ;;
  esac

  if [[ $status == blocked ]]; then
    # A blocked row must explain itself — otherwise it is indistinguishable
    # from something nobody looked at.
    if [[ ${#notes} -lt 40 ]]; then
      err "row '$feature' is blocked but its Notes do not explain why (needs a reason and a next step)"
    fi
  fi
done < "$PARITY"

# ── 3: the epic sections still exist ────────────────────────────────────────
for epic in \
  "E1 — Core messaging" \
  "E2 — Groups" \
  "E3 — Contacts & identity" \
  "E4 — Media & reactions" \
  "E5 — Settings & security" \
  "E6 — Identity portability" \
  "E7 — Shell & layout"
do
  grep -Fq "## $epic" "$PARITY" || err "epic section missing: $epic"
done

# ── 4: every documented content marker is represented ───────────────────────
# Android grows markers; if one lands in the spec with no parity row, the
# desktop client will silently render "[unsupported message]" forever.
if [[ -f $MARKERS ]]; then
  # Marker prefixes appear in the quick-reference table as `| `name:` | …`.
  markers=$(grep -oE '^\| `[a-z0-9]+1?:`' "$MARKERS" | tr -d '|` :' | sort -u)
  for m in $markers; do
    # Skip transport-level framing that never reaches a feature row.
    case "$m" in frg1|lr1|lmi) continue ;; esac
    if ! grep -q "$m" "$PARITY"; then
      err "marker '$m:' is documented in CONTENT-MARKERS.md but has no row in PARITY.md"
    fi
  done
fi

if [[ $fail -eq 0 ]]; then
  rows=$(grep -cE '^\|' "$PARITY")
  echo "parity matrix OK ($rows table lines checked)"
fi
exit $fail
