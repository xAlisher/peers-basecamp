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
  fail,
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
    network: true,
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
    { timeout: 150000, network: true, what: "bob to render alice's reply as a quote of his message" },
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
    { timeout: 150000, network: true, what: "bob to see the reaction on his message" },
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
    { timeout: 150000, network: true, what: "alice to see the pin" },
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
    { timeout: 150000, network: true, what: "alice's pin to clear" },
  );
  step("unpin: clears on the peer");

  // ── the context menu renders over a real message ────────────────────────
  await evalq(bob, `bubbleMenu.msg = root.messages[0]`);
  await evalq(bob, `bubbleMenu.isGroup = false`);
  await evalq(bob, `bubbleMenu.canPin = true`);
  await evalq(bob, `bubbleMenu.hasLabel = false`);
  await evalq(bob, `bubbleMenu.openAt(320, 200)`);
  await waitFor(async () => (await evalq(bob, "bubbleMenu.visible")) === true, {
    timeout: 5000,
    what: "the bubble action menu to open",
  });
  await new Promise((r) => setTimeout(r, 1200));   // let the frame settle
  await shoot(bob, "23-bubble-action-menu.png");
  step("context menu: opens over a message");
  await evalq(bob, `bubbleMenu.close()`);

  // ── delete for me is LOCAL: it hides here and nowhere else ──────────────
  const before = await evalq(bob, "root.messages.length");
  const victim = JSON.parse(await evalq(bob, "JSON.stringify(root.messages[0])"));
  await evalq(
    bob,
    `root.backend.deleteMessageForMe(${JSON.stringify(convoId)}, ${JSON.stringify(victim.key)})`,
  );
  await waitFor(async () => (await evalq(bob, "root.messages.length")) < before, {
    timeout: 20000,
    what: "the deleted message to disappear locally",
  });
  step(`delete for me: hidden locally (${before} -> ${await evalq(bob, "root.messages.length")})`);

  // …and the peer must still have it. Deleting for everyone is not a thing Peers
  // does, and claiming otherwise would be a lie about a privacy-relevant action.
  let stillOnAlice = false;
  const n2 = await evalq(alice, "root.messages.length");
  for (let i = 0; i < n2; i++) {
    if ((await evalq(alice, `root.messages[${i}].key`)) === victim.key) stillOnAlice = true;
  }
  if (!stillOnAlice)
    throw new Error("delete-for-me removed the message from the PEER — it must be local only");
  step("delete for me: peer still has it (local only, as Peers intends)");

  // ── forward carries the MESSAGE, not its rendered text ─────────────────
  //
  // A self-only group is a legitimate second conversation and needs no network,
  // so this stays a local assertion about what forwarding actually sends.
  const convosBefore = await evalq(bob, "root.conversations.length");
  await evalq(bob, `root.backend.createGroupConversation("Forward target", "")`);
  await waitFor(async () => (await evalq(bob, "root.conversations.length")) > convosBefore, {
    timeout: 30000,
    what: "the forward-target group to be created",
  });
  const target = JSON.parse(
    await evalq(
      bob,
      "JSON.stringify(root.conversations.map(c => ({id: c.convoId, name: c.displayName})))",
    ),
  ).find((c) => c.name === "Forward target");
  if (!target) throw new Error("the forward-target group is not in the conversation list");

  // Forward an INCOMING message. The message key is FNV-1a over
  // "<author> <body>", so forwarding your OWN message verbatim necessarily
  // produces the same key — a documented collision, not a bug. Forwarding a
  // peer's message changes the author, which is the case worth asserting.
  let source = null;
  {
    const n = await evalq(bob, "root.messages.length");
    for (let i = 0; i < n; i++) {
      const m = JSON.parse(await evalq(bob, `JSON.stringify(root.messages[${i}])`));
      if (m.fromSelf === false) { source = m; break; }
    }
  }
  if (!source) throw new Error("no incoming message to forward");
  await evalq(
    bob,
    `root.backend.forwardMessage(${JSON.stringify(convoId)}, ${JSON.stringify(source.key)}, ` +
      `${JSON.stringify(target.id)})`,
  );
  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(target.id)})`);
  // Gate on the LOADED conversation, not just on there being messages: the old
  // thread still has messages, so "length > 0" is true the instant we ask and
  // the assertions below would run against the source message itself.
  await waitFor(
    async () =>
      (await evalq(bob, "root.backend.loadedConversationId")) === target.id
      && (await evalq(bob, "root.messages.length")) > 0,
    { timeout: 30000, what: "the forwarded message to land in the target conversation" },
  );
  const landed = JSON.parse(await evalq(bob, "JSON.stringify(root.messages[0])"));
  if (landed.text !== source.text)
    throw new Error(`forward changed the text: "${source.text}" -> "${landed.text}"`);
  if (source.kind === "reply") {
    // Forwarding a reply UNWRAPS it: the quote key identifies a message in the
    // original thread and means nothing in this one, so carrying it over would
    // render "Original message unavailable" on every forwarded reply.
    if (landed.kind !== "text")
      throw new Error(`a forwarded reply should arrive as text, got ${landed.kind}`);
    if (landed.quotedText)
      throw new Error("a forwarded reply carried its quote into the new thread");
  } else if (landed.kind !== source.kind) {
    throw new Error(`forward changed the kind: ${source.kind} -> ${landed.kind}`);
  }
  // A forward is a NEW message from us: same body, different author, so a
  // different key. Reactions on the original must not follow it around.
  if (landed.key === source.key)
    throw new Error("the forwarded message kept the original's key");
  if (landed.fromSelf !== true) throw new Error("the forwarded message is not marked as ours");
  step(`forward: carried into another conversation (${source.kind} -> ${landed.kind}, new key)`);
  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(convoId)})`);

  // ── a shared contact card must decode into an address, not a marker ─────
  const cardAddress = String(await evalq(alice, "root.backend.myAddress"));
  await evalq(bob, `root.backend.setContactLabel(${JSON.stringify(cardAddress)}, "Alice")`);
  await evalq(
    bob,
    `root.backend.sendContactCard(${JSON.stringify(convoId)}, ${JSON.stringify(cardAddress)})`,
  );

  async function findContact(insp) {
    const n = await evalq(insp, "root.messages.length");
    for (let i = 0; i < n; i++) {
      if ((await evalq(insp, `root.messages[${i}].kind`)) === "contact") {
        return JSON.parse(await evalq(insp, `JSON.stringify(root.messages[${i}])`));
      }
    }
    return null;
  }

  await waitFor(async () => (await findContact(alice)) !== null, {
    timeout: 120000,
    network: true,
    what: "the contact card to reach alice",
  });
  const card = await findContact(alice);
  if (String(card.address).toLowerCase() !== cardAddress.toLowerCase())
    throw new Error(`the card decoded to ${card.address}, expected ${cardAddress}`);
  if (card.label !== "Alice")
    throw new Error(`the card lost its label: got "${card.label}"`);
  if (String(card.text || "").includes("addr1:"))
    throw new Error("the raw addr1: marker leaked into the rendered text");
  step(`contact card: decoded on the peer (${card.label}, ${String(card.address).slice(0, 8)}…)`);
  await shoot(alice, "27-alice-contact-card.png");

  console.log("\nPASS: reply, reaction, pin, unpin, context menu, local delete, "
    + "forward and a shared contact card.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
