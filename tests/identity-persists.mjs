//
// Identity persistence (E6): the address must survive a restart.
//
// Both keys used to be minted on every launch, so a peer's saved address died
// the moment the app restarted — testing against a phone meant re-adding the
// contact after every redeploy. peers_core now writes `identity.key` under its
// persistence path and rehydrates from it.
//
// This is deliberately a RESTART test, not a "the file exists" test: a file
// holding key material proves nothing unless the address it produces is the
// same one afterwards.
//
//   node tests/identity-persists.mjs <port>
//
// Driven by scripts/run-identity.sh, which owns starting and restarting the
// instance against a FIXED user-dir. Exit codes: 0 pass · 1 failed.
//
import { Inspector, evalq, waitOnline, step, EXIT_OK, EXIT_FAIL } from "./inspector.mjs";

const PORT = Number(process.argv[2] ?? 5591);
const PHASE = process.argv[3] ?? "first";       // "first" | "second"
const STATE = process.argv[4] ?? "/extra/tmp/peers-identity-check.json";

import fs from "node:fs";

async function main() {
  const insp = new Inspector(PORT, PHASE);
  await insp.connect();
  await waitOnline(insp);

  const address = String(await evalq(insp, "root.backend.myAddress"));
  if (!/^[0-9a-fA-F]{16,}$/.test(address))
    throw new Error(`address does not look like an account address: "${address}"`);

  if (PHASE === "first") {
    fs.writeFileSync(STATE, JSON.stringify({ address }));
    step(`first launch: address ${address.slice(0, 16)}…`);
    insp.disconnect();
    process.exit(EXIT_OK);
  }

  const before = JSON.parse(fs.readFileSync(STATE, "utf8")).address;
  if (address !== before) {
    console.error(
      `\nFAILED: the address changed across a restart.\n` +
        `  before: ${before}\n  after:  ${address}\n` +
        `  A peer's saved address is dead after every restart.`,
    );
    process.exit(EXIT_FAIL);
  }
  step(`second launch: same address ${address.slice(0, 16)}… — identity persisted`);
  insp.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => {
  console.error(`\nFAILED: ${e.message}`);
  process.exit(EXIT_FAIL);
});
