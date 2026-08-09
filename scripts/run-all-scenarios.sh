#!/usr/bin/env bash
# Every live scenario, in order of cost. Each needs two instances on the live
# fleet, so the whole suite takes a while.
#
# Exit 2 from any scenario means the invite never landed (flaky join) — re-run
# that one before investigating.
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for t in tests/backup.mjs tests/hosted-media.mjs tests/ui-tour.mjs tests/exchange.mjs tests/group.mjs tests/interactions.mjs tests/media.mjs; do
  echo "═══════════════════════════════════════ $t"
  TEST="$t" ./scripts/run-exchange.sh 2>&1 | grep -vE "\[delivery_module\]|\[chat_module\]" | tail -25
  s=${PIPESTATUS[0]}
  echo "── $t exit=$s"
  [ "$s" -ne 0 ] && rc=$s
done
exit $rc
