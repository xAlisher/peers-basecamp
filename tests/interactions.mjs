//
// Message interactions gate: reply, reaction, pin (E1/E2/E4).
//
// All three ride marker-prefixed payloads inside the message body (ADR 0002),
// so the real test is not "our own UI updated" but "the PEER parsed it and shows
// the right thing". Each assertion is therefore made on the opposite instance.
//
//   node tests/interactions.mjs [alicePort] [bobPort]
//
// Exit codes: 0 pass · 1 an assertion failed · 2 the invite never landed.
//
import {
  Inspector,
  evalq,
  waitFor,
  waitOnline,
  step,
  shoot,
  dump,
  inviteAndJoin,
  EXIT_OK,
  EXIT_FAIL,
  EXIT_NETWORK,
} from "./inspector.mjs";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const BOB_MSG = "Original message from Bob";
const ALICE_REPLY = "Quoting you here";
const EMOJI = "\u{1F44D}"; // thumbs up

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

// Find a rendered message by its text and return its row as JSON.
async function findMessage(insp, text) {
  const n = await evalq(insp, "root.messages.length");
  for (let i = 0; i < n; i++) {
    if ((await evalq(insp, `root.messages[${i}].text`)) === text) {
      return JSON.parse(await evalq(insp, `JSON.stringify(root.messages[${i}])`));
    }
  }
  return null;
}

async function main() {
  await alice.connect();
  await bob.connect();
  await waitOnline(alice);
  await waitOnline(bob);
  step("both Online");

  const address = await evalq(alice, "root.backend.myAddress");
  const convoId = await inviteAndJoin(bob, alice, address);
  if (!convoId) {
    console.error("\nNETWORK: the invite never reached alice. Re-run before investigating.");
    process.exit(EXIT_NETWORK);
  }
  step("conversation established");

  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(convoId)})`);
  await evalq(alice, `root.backend.selectConversation(${JSON.stringify(convoId)})`);

  // ── a message to interact with ──────────────────────────────────────────
  await evalq(
    bob,
    `root.backend.sendMessage(${JSON.stringify(convoId)}, ${JSON.stringify(BOB_MSG)})`,
  );
  await waitFor(async () => (await findMessage(alice, BOB_MSG)) !== null, {
    timeout: 150000,
    what: "alice to receive bob's message",
  });
  const onAlice = await findMessage(alice, BOB_MSG);
  if (!onAlice.key || onAlice.key.length !== 16)
    throw new Error(`message key looks wrong: ${JSON.stringify(onAlice.key)}`);
  step(`alice sees bob's message (key ${onAlice.key})`);

  // The key is hashed over (author, raw body) and must agree ACROSS DEVICES —
  // that is the whole point of it. If the two sides disagree, every reaction and
  // pin lands on the wrong message.
  const onBob = await findMessage(bob, BOB_MSG);
  if (!onBob || onBob.key !== onAlice.key)
    throw new Error(
      `message key differs across devices: bob=${onBob && onBob.key} alice=${onAlice.key}`,
    );
  step("message key agrees on both sides");

  // ── reply ───────────────────────────────────────────────────────────────
  await evalq(
    alice,
    `root.backend.sendReply(${JSON.stringify(convoId)}, ${JSON.stringify(ALICE_REPLY)}, ${JSON.stringify(onAlice.key)})`,
  );
  await waitFor(
    async () => {
      const r = await findMessage(bob, ALICE_REPLY);
      return r !== null && r.kind === "reply" && r.replyToKey === onAlice.key;
    },
    { timeout: 150000, what: "bob to render alice's reply as a quote of his message" },
  );
  // The quote must show the QUOTED text, not the reply's own body. Binding the
  // reply's text into the quote box is an easy mistake and it shipped once —
  // a screenshot caught it, so assert it here from now on.
  const replyRow = await findMessage(bob, ALICE_REPLY);
  if (replyRow.quotedText !== BOB_MSG)
    throw new Error(
      `reply quote shows the wrong text: expected ${JSON.stringify(BOB_MSG)}, ` +
        `got ${JSON.stringify(replyRow.quotedText)}`,
    );
  step("reply: renders on the peer, quoting the right message");
  await shoot(bob, "20-bob-sees-reply.png");

  // ── reaction ────────────────────────────────────────────────────────────
  await evalq(
    alice,
    `root.backend.reactToMessage(${JSON.stringify(convoId)}, ${JSON.stringify(onAlice.key)}, ${JSON.stringify(EMOJI)})`,
  );
  await waitFor(
    async () => {
      const r = await findMessage(bob, BOB_MSG);
      if (!r || !r.reactions) return false;
      return r.reactions.some((x) => x.emoji === EMOJI && x.count >= 1);
    },
    { timeout: 150000, what: "bob to see the reaction on his message" },
  );
  step("reaction: renders on the peer, attached to the right message");
  await shoot(bob, "21-bob-sees-reaction.png");

  // A reaction is a control marker and must NEVER occupy a bubble.
  const bobBubbleTexts = [];
  const n = await evalq(bob, "root.messages.length");
  for (let i = 0; i < n; i++) bobBubbleTexts.push(await evalq(bob, `root.messages[${i}].text`));
  if (bobBubbleTexts.some((t) => String(t).includes("react1:")))
    throw new Error(`a reaction leaked into the thread as a bubble: ${JSON.stringify(bobBubbleTexts)}`);
  step("reaction: folded — no raw marker bubble");

  // ── pin ─────────────────────────────────────────────────────────────────
  await evalq(
    bob,
    `root.backend.pinMessage(${JSON.stringify(convoId)}, ${JSON.stringify(onBob.key)})`,
  );
  await waitFor(
    async () => {
      const pinned = JSON.parse(await evalq(alice, "root.backend.currentPinnedJson"));
      return pinned && pinned.key === onAlice.key;
    },
    { timeout: 150000, what: "alice to see the pin" },
  );
  step("pin: propagates to the peer");
  await shoot(alice, "22-alice-sees-pin.png");

  // ── unpin ───────────────────────────────────────────────────────────────
  await evalq(bob, `root.backend.unpinMessage(${JSON.stringify(convoId)})`);
  await waitFor(
    async () => {
      const pinned = JSON.parse(await evalq(alice, "root.backend.currentPinnedJson"));
      return !pinned || !pinned.key;
    },
    { timeout: 150000, what: "alice's pin to clear" },
  );
  step("unpin: clears on the peer");

  console.log("\nPASS: reply, reaction, pin and unpin all render on the peer.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch(async (e) => {
  console.error(`\nFAILED: ${e.message}`);
  try {
    await dump(alice);
    await dump(bob);
  } catch {
    /* best effort */
  }
  process.exit(EXIT_FAIL);
});
