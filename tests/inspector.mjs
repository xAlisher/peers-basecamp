//
// Shared harness for driving live peers_ui instances over the QML inspector
// (the logos-qt-mcp protocol: newline-delimited JSON over TCP).
//
// Used by tests/exchange.mjs (1:1) and tests/group.mjs (groups).
//
import net from "node:net";
import fs from "node:fs";

export const EXIT_OK = 0;
export const EXIT_FAIL = 1;
// "The network never delivered it" is NOT "an assertion failed". Keeping them
// apart is what stops a randomly-red suite from training everyone to ignore it.
export const EXIT_NETWORK = 2;

export class Inspector {
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

export async function evalq(insp, expression) {
  const r = await insp.send("evaluate", { expression });
  if (r.error) throw new Error(`${insp.name} eval(${expression}): ${r.error}`);
  return r.result !== undefined ? r.result : r.value;
}

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// `network: true` marks a wait on something that has to CROSS THE NETWORK. A
// timeout there is a delivery failure, not a logic failure, and the two must not
// look alike: reporting flaky delivery as "an assertion failed" is exactly what
// trains people to ignore a suite. Such a timeout carries `isNetwork` so the
// scenario can exit with EXIT_NETWORK instead.
export async function waitFor(fn, { timeout = 30000, interval = 1000, what, network = false } = {}) {
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
  const err = new Error(
    `timed out waiting for ${what}${last ? ` (last: ${last.message})` : ""}`,
  );
  err.isNetwork = network;
  throw err;
}

// Standard tail for a scenario: classify the failure before choosing an exit
// code, and dump both sides' state either way.
export async function fail(e, instances) {
  if (e.isNetwork) {
    console.error(
      `\nNETWORK: ${e.message}\n` +
        "Something did not cross the live fleet in time. This is the known-flaky\n" +
        "delivery path, NOT an assertion failure in our code. Re-run before investigating.",
    );
  } else {
    console.error(`\nFAILED: ${e.message}`);
  }
  for (const i of instances) {
    try {
      await dump(i);
    } catch {
      /* best effort */
    }
  }
  process.exit(e.isNetwork ? EXIT_NETWORK : EXIT_FAIL);
}

export function step(msg) {
  console.log(msg);
}

// Per-instance capture. Works offscreen, so each side is grabbed independently —
// two windows on one X display would overlap.
export async function shoot(insp, name, outDir = process.env.OUT_DIR || "docs/screenshots/interop-desktop") {
  try {
    const r = await insp.send("screenshot", {});
    if (r.error || !r.image) {
      console.log(`  (screenshot ${name} unavailable: ${r.error || "no image"})`);
      return;
    }
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(`${outDir}/${name}`, Buffer.from(r.image, "base64"));
    console.log(`  screenshot ${name} (${r.width}x${r.height})`);
  } catch (e) {
    console.log(`  (screenshot ${name} failed: ${e.message})`);
  }
}

// The list of convo ids an instance currently holds.
export async function convoIds(insp) {
  const raw = await evalq(
    insp,
    "root.conversations.map(function (c) { return c.convoId; }).join(',')",
  );
  return String(raw).split(",").filter(Boolean);
}

// Wait for an instance to come Online. This is the slow part — the fleet takes
// 5-20s, and nothing involving the key-package registry works before it.
export async function waitOnline(insp, timeout = 180000) {
  await waitFor(async () => (await evalq(insp, "root.online")) === true, {
    timeout,
    what: `${insp.name} Online`,
  });
}

// Dump both sides' state. Guessing at a distributed failure from a one-line
// timeout is how you end up blaming the network for your own bug.
export async function dump(insp) {
  const probes = [
    "root.online",
    "root.backend.chatStatus",
    "root.backend.statusDetail",
    "root.backend.myAddress",
    "root.backend.currentConversationId",
    "root.backend.loadedConversationId",
    "root.backend.memberCount",
    "root.backend.pendingMemberCount",
    "root.conversations.length",
    "root.messages.length",
    "root.backend.membersJson",
    "root.backend.messagesJson",
    "JSON.stringify(root.backend.errors)",
  ];
  console.error(`--- ${insp.name} state ---`);
  for (const p of probes) {
    try {
      console.error(`  ${p} = ${JSON.stringify(await evalq(insp, p))}`);
    } catch (e) {
      console.error(`  ${p} !! ${e.message}`);
    }
  }
}

// Create a conversation from `from` to `address` and wait for `to` to join.
// Retries, because the join genuinely is flaky (key-package fetch over the live
// fleet). Returns the SHARED convo id, or null if the invite never landed.
//
// Identifying the new conversation by diffing the id set before/after matters:
// list_conversations has no documented ordering, and a retry leaves more than
// one conversation behind, so "the last one" can disagree with the one the peer
// actually joined.
export async function inviteAndJoin(from, to, address, { attempts = 3 } = {}) {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    step(`${from.name}: create_conversation (attempt ${attempt}/${attempts})...`);
    const before = await convoIds(from);
    await evalq(from, `root.backend.createConversation(${JSON.stringify(address)})`);

    let convoId = null;
    try {
      await waitFor(
        async () => {
          const fresh = (await convoIds(from)).filter((id) => !before.includes(id));
          if (fresh.length === 0) return false;
          convoId = fresh[0];
          return true;
        },
        { timeout: 45000, what: `${from.name}'s new conversation to exist locally` },
      );
    } catch {
      continue;
    }

    try {
      await waitFor(async () => (await convoIds(to)).includes(convoId), {
        timeout: 120000,
        network: true,
        what: `${to.name} to join conversation ${convoId}`,
      });
      return convoId;
    } catch {
      step(`  invite did not land on attempt ${attempt}`);
    }
  }
  return null;
}
