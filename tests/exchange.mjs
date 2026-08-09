//
// Two-instance 1:1 exchange — the primary interop gate (ADR 0003).
//
// Drives two live peers_ui instances over the QML inspector, reads Alice's
// address out of her window, hands it to Bob, and verifies a real bidirectional
// round-trip over the live delivery network.
//
//   node tests/exchange.mjs [alicePort] [bobPort]
//
// Exit codes: 0 round-trip completed · 1 an assertion failed · 2 the invite
// never landed (the known-flaky join step — re-run before investigating).
//
import {
  Inspector,
  evalq,
  waitFor,
  waitOnline,
  step,
  shoot,
  dump,
  fail,
  inviteAndJoin,
  EXIT_OK,
  EXIT_FAIL,
  EXIT_NETWORK,
} from "./inspector.mjs";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const BOB_MSG = "Hi Alice, it's Bob";
const ALICE_REPLY = "Hi Bob, got it";

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

async function main() {
  await alice.connect();
  await bob.connect();
  step("connected to both inspectors");

  await waitOnline(alice);
  await waitOnline(bob);
  step("both Online");

  const address = await evalq(alice, "root.backend.myAddress");
  if (!address || String(address).length < 32)
    throw new Error(`alice's address looks wrong: ${JSON.stringify(address)}`);
  step(`alice address: ${String(address).length} chars`);
  await shoot(alice, "01-alice-address.png");

  const convoId = await inviteAndJoin(bob, alice, address);
  if (!convoId) {
    console.error(
      "\nNETWORK: the invite never reached alice.\n" +
        "This is the known-flaky join step (key-package fetch over the live fleet),\n" +
        "NOT an assertion failure in our code. Re-run before investigating.",
    );
    process.exit(EXIT_NETWORK);
  }
  step("alice joined the conversation");

  // Both sides select the SAME id. After a retry the auto-selected conversation
  // may not be the one that was actually joined.
  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(convoId)})`);
  await evalq(
    bob,
    `root.backend.sendMessage(${JSON.stringify(convoId)}, ${JSON.stringify(BOB_MSG)})`,
  );
  await waitFor(async () => (await evalq(bob, "root.messages.length")) >= 1, {
    timeout: 30000,
    what: "bob's message in his own thread",
  });
  await shoot(bob, "02-bob-sent.png");
  step("bob: sent");

  await evalq(alice, `root.backend.selectConversation(${JSON.stringify(convoId)})`);
  await waitFor(
    async () => {
      if ((await evalq(alice, "root.messages.length")) < 1) return false;
      return (await evalq(alice, "root.messages[0].text")) === BOB_MSG;
    },
    { timeout: 120000, network: true, what: "alice to receive bob's message" },
  );
  await shoot(alice, "03-alice-received.png");
  step("alice: received bob's message");

  await evalq(
    alice,
    `root.backend.sendMessage(${JSON.stringify(convoId)}, ${JSON.stringify(ALICE_REPLY)})`,
  );
  await waitFor(async () => (await evalq(alice, "root.messages.length")) >= 2, {
    timeout: 30000,
    what: "alice's reply in her thread",
  });
  await shoot(alice, "04-alice-replied.png");
  step("alice: replied");

  await waitFor(
    async () => {
      const n = await evalq(bob, "root.messages.length");
      if (n < 2) return false;
      for (let i = 0; i < n; i++) {
        if ((await evalq(bob, `root.messages[${i}].text`)) === ALICE_REPLY) return true;
      }
      return false;
    },
    { timeout: 120000, network: true, what: "bob to receive the reply" },
  );
  await shoot(bob, "05-bob-roundtrip.png");
  step("bob: received the reply");

  console.log("\nPASS: bidirectional round-trip between two peers_ui instances.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
