//
// Two-instance exchange — the primary interop gate (ADR 0003).
//
// Drives two live peers_ui instances over the QML inspector (the logos-qt-mcp
// protocol: newline-delimited JSON over TCP), reads Alice's address out of her
// window, hands it to Bob, and verifies a real bidirectional round-trip over
// the live delivery network.
//
//   node tests/exchange.mjs <alicePort> <bobPort>
//
// Exits 0 on a completed round-trip, 1 on a genuine failure, and 2 when the
// network never delivered the invite — see JOIN FLAKINESS below.
//
// JOIN FLAKINESS. The join step depends on fetching the peer's key package from
// the registry over the live fleet, and it does not always land: on 2026-08-09
// the equivalent upstream harness failed this exact step on one run and passed
// unchanged on the next. So this script retries the invite, and reports "the
// invite never landed" with a DISTINCT exit code from "an assertion failed".
// A suite that goes red at random teaches people to ignore it, which is worse
// than having no suite.
//
import net from "node:net";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const BOB_MSG = "Hi Alice, it's Bob";
const ALICE_REPLY = "Hi Bob, got it";

const EXIT_OK = 0;
const EXIT_FAIL = 1;
const EXIT_NETWORK = 2;

class Inspector {
  constructor(port, name) {
    this.port = port;
    this.name = name;
    this.socket = null;
    this.pending = new Map();
    this.nextId = 1;
    this.buf = "";
  }

  connect() {
    return new Promise((resolve, reject) => {
      const sock = net.createConnection({ host: "127.0.0.1", port: this.port });
      sock.once("connect", () => {
        this.socket = sock;
        resolve();
      });
      sock.once("error", (err) =>
        reject(new Error(`connect ${this.name}:${this.port}: ${err.message}`)),
      );
      sock.on("data", (chunk) => {
        this.buf += chunk.toString();
        let i;
        while ((i = this.buf.indexOf("\n")) >= 0) {
          const line = this.buf.slice(0, i);
          this.buf = this.buf.slice(i + 1);
          if (!line.trim()) continue;
          let msg;
          try {
            msg = JSON.parse(line);
          } catch {
            continue;
          }
          const p = this.pending.get(msg.id);
          if (!p) continue;
          this.pending.delete(msg.id);
          clearTimeout(p.timer);
          p.resolve(msg);
        }
      });
      sock.on("close", () => {
        this.socket = null;
        for (const [, p] of this.pending) {
          clearTimeout(p.timer);
          p.reject(new Error("connection closed"));
        }
        this.pending.clear();
      });
    });
  }

  send(command, params, timeoutMs = 20000) {
    return new Promise((resolve, reject) => {
      if (!this.socket) return reject(new Error("not connected"));
      const id = this.nextId++;
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${this.name}: ${command} timed out`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.socket.write(JSON.stringify({ id, command, params }) + "\n");
    });
  }

  disconnect() {
    if (this.socket) this.socket.destroy();
  }
}

async function evalq(insp, expression) {
  const r = await insp.send("evaluate", { expression });
  if (r.error) throw new Error(`${insp.name} eval(${expression}): ${r.error}`);
  return r.result !== undefined ? r.result : r.value;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(fn, { timeout = 30000, interval = 1000, what } = {}) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try {
      if (await fn()) return true;
    } catch (e) {
      last = e;
    }
    await sleep(interval);
  }
  const err = new Error(`timed out waiting for ${what}${last ? ` (last: ${last.message})` : ""}`);
  err.what = what;
  throw err;
}

function step(msg) {
  console.log(msg);
}

async function main() {
  const alice = new Inspector(ALICE_PORT, "alice");
  const bob = new Inspector(BOB_PORT, "bob");

  globalThis.__alice = alice;
  globalThis.__bob = bob;

  await alice.connect();
  await bob.connect();
  step("connected to both inspectors");

  // Both instances must reach Online before the key-package registry can serve
  // an invite. This is the slow part — the fleet takes 5-20s.
  await waitFor(async () => (await evalq(alice, "root.online")) === true, {
    timeout: 180000,
    what: "alice Online",
  });
  await waitFor(async () => (await evalq(bob, "root.online")) === true, {
    timeout: 180000,
    what: "bob Online",
  });
  step("both Online");

  const address = await evalq(alice, "root.backend.myAddress");
  if (!address || String(address).length < 32)
    throw new Error(`alice's address looks wrong: ${JSON.stringify(address)}`);
  step(`alice address: ${String(address).length} chars`);

  // ── the invite, with retries (see JOIN FLAKINESS above) ──────────────────
  let joined = false;
  const ATTEMPTS = 3;
  for (let attempt = 1; attempt <= ATTEMPTS && !joined; attempt++) {
    step(`bob: create_conversation (attempt ${attempt}/${ATTEMPTS})...`);
    await evalq(bob, `root.backend.createConversation(${JSON.stringify(address)})`);
    try {
      // Wait on the CONVERSATION LIST, not on currentConversationId: the list is
      // what create_conversation actually produces (via conversation_created).
      // Gating on the selection conflates "the core never created it" with "the
      // view didn't auto-select it", which sent an earlier run down a false
      // "the network is flaky" path when the real cause was ours.
      await waitFor(async () => (await evalq(bob, "root.conversations.length")) >= 1, {
        timeout: 45000,
        what: "bob's conversation to exist locally",
      });
    } catch {
      continue;
    }
    try {
      await waitFor(async () => (await evalq(alice, "root.conversations.length")) >= 1, {
        timeout: 120000,
        what: "alice to join the conversation",
      });
      joined = true;
    } catch {
      step(`  invite did not land on attempt ${attempt}`);
    }
  }

  if (!joined) {
    console.error(
      "\nNETWORK: the invite never reached alice after " +
        ATTEMPTS +
        " attempts.\n" +
        "This is the known-flaky join step (key-package fetch over the live fleet),\n" +
        "NOT an assertion failure in our code. Re-run before investigating.",
    );
    alice.disconnect();
    bob.disconnect();
    process.exit(EXIT_NETWORK);
  }
  step("alice joined the conversation");

  // ── bob → alice ─────────────────────────────────────────────────────────
  let bobConvo = await evalq(bob, "root.backend.currentConversationId");
  if (!bobConvo) {
    bobConvo = await evalq(bob, "root.conversations[0].convoId");
    await evalq(bob, `root.backend.selectConversation(${JSON.stringify(bobConvo)})`);
  }
  await evalq(
    bob,
    `root.backend.sendMessage(${JSON.stringify(bobConvo)}, ${JSON.stringify(BOB_MSG)})`,
  );
  await waitFor(async () => (await evalq(bob, "root.messages.length")) >= 1, {
    timeout: 30000,
    what: "bob's message in his own thread",
  });
  step("bob: sent");

  // Alice selects the conversation and must actually see it.
  const aliceConvo = await evalq(alice, "root.conversations[0].convoId");
  await evalq(alice, `root.backend.selectConversation(${JSON.stringify(aliceConvo)})`);
  await waitFor(
    async () => {
      const n = await evalq(alice, "root.messages.length");
      if (n < 1) return false;
      const text = await evalq(alice, "root.messages[0].text");
      return text === BOB_MSG;
    },
    { timeout: 120000, what: "alice to receive bob's message" },
  );
  step("alice: received bob's message");

  // ── alice → bob ─────────────────────────────────────────────────────────
  await evalq(
    alice,
    `root.backend.sendMessage(${JSON.stringify(aliceConvo)}, ${JSON.stringify(ALICE_REPLY)})`,
  );
  await waitFor(async () => (await evalq(alice, "root.messages.length")) >= 2, {
    timeout: 30000,
    what: "alice's reply in her thread",
  });
  step("alice: replied");

  await waitFor(
    async () => {
      const n = await evalq(bob, "root.messages.length");
      if (n < 2) return false;
      const texts = [];
      for (let i = 0; i < n; i++) texts.push(await evalq(bob, `root.messages[${i}].text`));
      return texts.includes(ALICE_REPLY);
    },
    { timeout: 120000, what: "bob to receive the reply" },
  );
  step("bob: received the reply");

  console.log("\nPASS: bidirectional round-trip between two peers_ui instances.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

// On failure, dump both sides' state. Guessing at a distributed failure from a
// one-line timeout is how you end up blaming the network for your own bug.
async function dump(insp) {
  const probes = [
    "root.online",
    "root.backend.chatStatus",
    "root.backend.statusDetail",
    "root.backend.myAddress",
    "root.backend.currentConversationId",
    "root.backend.loadedConversationId",
    "root.conversations.length",
    "root.messages.length",
    "root.backend.conversationsJson",
    "root.backend.messagesJson",
    "JSON.stringify(root.backend.errors)",
  ];
  console.error(`--- ${insp.name} state ---`);
  for (const p of probes) {
    try {
      const v = await evalq(insp, p);
      console.error(`  ${p} = ${JSON.stringify(v)}`);
    } catch (e) {
      console.error(`  ${p} !! ${e.message}`);
    }
  }
}

main().catch(async (e) => {
  console.error(`\nFAILED: ${e.message}`);
  try {
    await dump(globalThis.__alice);
    await dump(globalThis.__bob);
  } catch {
    /* best effort */
  }
  process.exit(EXIT_FAIL);
});
