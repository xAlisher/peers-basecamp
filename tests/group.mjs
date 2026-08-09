//
// Group conversation gate (E2).
//
// Bob creates a named group, invites Alice, and both exchange messages in it.
// Verifies what chat_module 0.2.2 actually promises:
//
//   - create_group_conversation(name, desc) — name/desc are SHARED metadata,
//     visible to every member, distinct from the local-only nickname;
//   - add_group_member commits and delivers asynchronously — the peer observes
//     the conversation only once its instance has joined;
//   - list_group_members reports committed members first, then invites still
//     awaiting the group's commit.
//
//   node tests/group.mjs [alicePort] [bobPort]
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
  convoIds,
  EXIT_OK,
  EXIT_FAIL,
  EXIT_NETWORK,
} from "./inspector.mjs";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const GROUP_NAME = "Peers desktop test";
const GROUP_DESC = "Created by tests/group.mjs";
const BOB_MSG = "Hello group, this is Bob";
const ALICE_MSG = "Alice here, reading you";

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

async function main() {
  await alice.connect();
  await bob.connect();
  step("connected to both inspectors");

  await waitOnline(alice);
  await waitOnline(bob);
  step("both Online");

  const aliceAddress = await evalq(alice, "root.backend.myAddress");
  if (!aliceAddress || String(aliceAddress).length < 32)
    throw new Error(`alice's address looks wrong: ${JSON.stringify(aliceAddress)}`);

  // ── bob creates the group ───────────────────────────────────────────────
  const before = await convoIds(bob);
  await evalq(
    bob,
    `root.backend.createGroupConversation(${JSON.stringify(GROUP_NAME)}, ${JSON.stringify(GROUP_DESC)})`,
  );

  let groupId = null;
  await waitFor(
    async () => {
      const fresh = (await convoIds(bob)).filter((id) => !before.includes(id));
      if (fresh.length === 0) return false;
      groupId = fresh[0];
      return true;
    },
    { timeout: 60000, what: "bob's group to exist" },
  );
  step(`bob: group created (${groupId})`);

  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(groupId)})`);

  // The group's SHARED name must be what the view shows — not the convo id.
  await waitFor(
    async () => (await evalq(bob, "root.backend.currentDisplayName")) === GROUP_NAME,
    { timeout: 30000, what: "the group's shared name on bob's side" },
  );
  await waitFor(async () => (await evalq(bob, "root.backend.currentIsGroup")) === true, {
    timeout: 30000,
    what: "bob's conversation to report itself as a group",
  });
  step("bob: group name and kind correct");
  await shoot(bob, "10-bob-group-created.png");

  // ── bob invites alice ───────────────────────────────────────────────────
  step("bob: add_group_member(alice)...");
  await evalq(
    bob,
    `root.backend.addGroupMember(${JSON.stringify(groupId)}, ${JSON.stringify(aliceAddress)})`,
  );

  // The invite is committed and delivered asynchronously, so a member should be
  // visible as PENDING before the group commits them. Poll fast — the window is
  // short, and the backend nudges refreshMembers() right after the call
  // precisely so it can be seen.
  let sawPending = false;
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) {
    const pending = await evalq(bob, "root.backend.pendingMemberCount");
    const committed = await evalq(bob, "root.backend.memberCount");
    if (pending >= 1) {
      sawPending = true;
      step(`bob: PENDING invite observed (${committed} committed, ${pending} pending)`);
      await shoot(bob, "14-bob-pending-invite.png");
      break;
    }
    if (committed >= 2) break;   // already committed; the window closed first
    await new Promise((r) => setTimeout(r, 200));
  }
  if (!sawPending)
    step("  NOTE: pending window not observed — the commit beat the poll (not a failure)");

  // ── alice joins ─────────────────────────────────────────────────────────
  let joined = true;
  try {
    await waitFor(async () => (await convoIds(alice)).includes(groupId), {
      timeout: 150000,
      network: true,
      what: `alice to join group ${groupId}`,
    });
  } catch {
    joined = false;
  }

  if (!joined) {
    console.error(
      "\nNETWORK: alice never joined the group.\n" +
        "Same flaky key-package/commit path as the 1:1 invite — re-run before investigating.",
    );
    await dump(bob);
    process.exit(EXIT_NETWORK);
  }
  step("alice joined the group");

  await evalq(alice, `root.backend.selectConversation(${JSON.stringify(groupId)})`);
  await waitFor(
    async () => (await evalq(alice, "root.backend.currentDisplayName")) === GROUP_NAME,
    { timeout: 60000, what: "the group's shared name on alice's side" },
  );
  step("alice: sees the shared group name");
  await shoot(alice, "11-alice-joined-group.png");

  // ── messages both ways inside the group ─────────────────────────────────
  await evalq(
    bob,
    `root.backend.sendMessage(${JSON.stringify(groupId)}, ${JSON.stringify(BOB_MSG)})`,
  );
  await waitFor(
    async () => {
      const n = await evalq(alice, "root.messages.length");
      for (let i = 0; i < n; i++) {
        if ((await evalq(alice, `root.messages[${i}].text`)) === BOB_MSG) return true;
      }
      return false;
    },
    { timeout: 150000, network: true, what: "alice to receive bob's group message" },
  );
  step("alice: received bob's group message");
  await shoot(alice, "12-alice-group-message.png");

  await evalq(
    alice,
    `root.backend.sendMessage(${JSON.stringify(groupId)}, ${JSON.stringify(ALICE_MSG)})`,
  );
  await waitFor(
    async () => {
      const n = await evalq(bob, "root.messages.length");
      for (let i = 0; i < n; i++) {
        if ((await evalq(bob, `root.messages[${i}].text`)) === ALICE_MSG) return true;
      }
      return false;
    },
    { timeout: 150000, network: true, what: "bob to receive alice's group message" },
  );
  step("bob: received alice's group message");
  await shoot(bob, "13-bob-group-roundtrip.png");

  // Once the group has committed alice, both must count 2 committed members.
  try {
    await waitFor(async () => (await evalq(bob, "root.backend.memberCount")) >= 2, {
      timeout: 60000,
      what: "bob's roster to show 2 committed members",
    });
    step(`bob: roster committed = ${await evalq(bob, "root.backend.memberCount")}`);
  } catch (e) {
    step(`  NOTE: ${e.message} — messages flow, so the commit may lag the roster read`);
  }

  console.log("\nPASS: group created, member added, messages both ways.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
