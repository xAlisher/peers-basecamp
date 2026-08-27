//
// Hosted media gate (E4) — the `store2:` path, for media too big to ride inline.
//
// TWO DIRECTIONS, both verified:
//
//   WRITE  the desktop uploads an oversize file and emits a store2: marker that
//          its peer can fetch, decrypt and render.
//   READ   **Node** independently produces a blob to the Android spec — Padmé
//          padding, AES-256-GCM, iv||ct||tag, POST /data — hands the desktop the
//          resulting marker, and the desktop must read it back byte-for-byte.
//
// The READ direction is the one that matters for phone interop and it needs no
// phone: it proves our reader against a writer that is not ours. Our writer is
// in turn proved by our reader in the WRITE direction.
//
//   node tests/hosted-media.mjs [alicePort] [bobPort]
//
// Uploads are tokenless: both Desktop and the independent Node writer must
// acquire a short-lived exact-size one-use grant.
//
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";

import {
  Inspector,
  evalq,
  waitFor,
  waitOnline,
  step,
  shoot,
  fail,
  inviteAndJoin,
  EXIT_OK,
  EXIT_NETWORK,
} from "./inspector.mjs";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const BASE = process.env.PEERS_STORAGE_BASE || "https://msg.logos.live/s/api/storage/v1";

function strictObject(value, keys, what) {
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error(`invalid ${what}`);
  const actual = Object.keys(value).sort().join(",");
  if (actual !== [...keys].sort().join(",")) throw new Error(`invalid ${what} keys`);
  return value;
}

function leadingZeroBits(bytes) {
  let bits = 0;
  for (const value of bytes) {
    if (value === 0) {
      bits += 8;
      continue;
    }
    bits += Math.clz32(value) - 24;
    break;
  }
  return bits;
}

function solveProof(challenge, bytes, difficulty) {
  for (let nonce = 0; Number.isSafeInteger(nonce); nonce++) {
    const digest = crypto
      .createHash("sha256")
      .update(`${challenge}:${bytes}:${nonce}`, "utf8")
      .digest();
    if (leadingZeroBits(digest) >= difficulty) return nonce;
  }
  throw new Error("proof nonce exhausted");
}

async function requestUploadGrant(bytes) {
  const challengeRes = await fetch(`${BASE}/data/upload-challenges`, { method: "POST" });
  if (!challengeRes.ok)
    throw new Error(`challenge failed: HTTP ${challengeRes.status}`);
  const challenge = strictObject(
    JSON.parse(await challengeRes.text()),
    ["challenge", "difficulty", "expires_at"],
    "challenge",
  );
  const now = Math.floor(Date.now() / 1000);
  if (
    !/^[0-9a-f]{64}$/.test(challenge.challenge) ||
    !Number.isInteger(challenge.difficulty) ||
    challenge.difficulty < 1 ||
    challenge.difficulty > 24 ||
    !Number.isInteger(challenge.expires_at) ||
    challenge.expires_at <= now ||
    challenge.expires_at > now + 120
  )
    throw new Error("invalid challenge caveats");
  const nonce = solveProof(challenge.challenge, bytes, challenge.difficulty);
  const grantRes = await fetch(`${BASE}/data/upload-grants`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ challenge: challenge.challenge, bytes, nonce }),
  });
  if (!grantRes.ok) throw new Error(`grant failed: HTTP ${grantRes.status}`);
  const grant = strictObject(
    JSON.parse(await grantRes.text()),
    ["grant", "max_bytes", "expires_at"],
    "grant",
  );
  const grantNow = Math.floor(Date.now() / 1000);
  if (
    !/^[0-9a-f]{64}$/.test(grant.grant) ||
    grant.max_bytes !== bytes ||
    !Number.isInteger(grant.expires_at) ||
    grant.expires_at <= grantNow ||
    grant.expires_at > grantNow + 120
  )
    throw new Error("invalid grant caveats");
  return grant.grant;
}

// Comfortably over the 256 KiB inline cap, so sendMedia must take the hosted path.
const W = 700;
const H = 500;

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

// ── Padmé, transcribed from MediaPadding.kt independently of our C++ ────────
function padmeBucket(l) {
  if (l < 2n) return 2n;
  const bits = (x) => BigInt(x.toString(2).length) - 1n; // floor(log2 x)
  const e = bits(l);
  const s = bits(e) + 1n;
  const lastBits = e - s;
  if (lastBits <= 0n) return l;
  const mask = (1n << lastBits) - 1n;
  return (l + mask) & ~mask;
}

function pad(data) {
  const total = BigInt(4 + data.length);
  const bucket = Number(padmeBucket(total));
  const out = Buffer.alloc(bucket);
  out.writeUInt32BE(data.length, 0);
  data.copy(out, 4);
  return out;
}

function makePng(w, h) {
  const raw = Buffer.alloc((w * 3 + 1) * h);
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0;
    for (let x = 0; x < w; x++) {
      // Noise, so it does not compress down under the inline cap.
      raw[o++] = (x * 7 + y * 13) & 0xff;
      raw[o++] = (x * 31 + y * 17) & 0xff;
      raw[o++] = (x * 3 + y * 29) & 0xff;
    }
  }
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  const crc = (b) => {
    let c = 0xffffffff;
    for (let i = 0; i < b.length; i++) c = table[(c ^ b[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const c = Buffer.alloc(4);
    c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 0 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// Upload exactly as StorageModule.uploadEncrypted does.
async function uploadLikeAndroid(bytes) {
  const plain = pad(bytes);
  const key = crypto.randomBytes(32);
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ct = Buffer.concat([c.update(plain), c.final()]);
  const blob = Buffer.concat([iv, ct, c.getAuthTag()]);
  const grant = await requestUploadGrant(blob.length);

  const res = await fetch(`${BASE}/data`, {
    method: "POST",
    headers: {
      "X-Upload-Grant": grant,
      "Content-Type": "application/octet-stream",
    },
    body: blob,
  });
  if (!res.ok) throw new Error(`upload failed: HTTP ${res.status} ${await res.text()}`);
  const body = (await res.text()).trim();
  const i = body.indexOf(":");
  return {
    cid: i < 0 ? body : body.slice(0, i),
    cap: i < 0 ? "" : body.slice(i + 1),
    key: key.toString("base64"),
    blobLen: blob.length,
    paddedLen: plain.length,
  };
}

async function findByKind(insp, kind) {
  const n = await evalq(insp, "root.messages.length");
  for (let i = 0; i < n; i++) {
    if ((await evalq(insp, `root.messages[${i}].kind`)) === kind) {
      return JSON.parse(await evalq(insp, `JSON.stringify(root.messages[${i}])`));
    }
  }
  return null;
}

async function main() {
  const png = makePng(W, H);
  const file = path.join(os.tmpdir(), "peers-test-hosted.png");
  fs.writeFileSync(file, png);
  step(`fixture: ${png.length} bytes (${W}x${H}) — over the 256 KiB inline cap`);

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
  await evalq(bob, `root.backend.selectConversation(${JSON.stringify(convoId)})`);
  await evalq(alice, `root.backend.selectConversation(${JSON.stringify(convoId)})`);
  step("conversation established");

  // ── WRITE: the desktop uploads and the peer reads it back ───────────────
  await evalq(
    bob,
    `root.backend.sendMedia(${JSON.stringify(convoId)}, ${JSON.stringify(file)}, "photo")`,
  );
  await waitFor(async () => (await findByKind(bob, "media")) !== null, {
    timeout: 120000,
    network: true,
    what: "bob's upload to finish and produce a store2: message",
  });
  const sent = await findByKind(bob, "media");
  if (!sent.cid) throw new Error(`no cid in the sent marker: ${JSON.stringify(sent)}`);
  if (sent.padded !== true) throw new Error("the desktop must emit store2 (padded), not store1");
  if (sent.width !== W || sent.height !== H)
    throw new Error(`dimensions wrong in the marker: ${sent.width}x${sent.height}`);
  step(`desktop uploaded an encrypted padded object`);

  await waitFor(
    async () => {
      const m = await findByKind(alice, "media");
      return m !== null && !!m.localPath;
    },
    { timeout: 150000, network: true, what: "alice to fetch and decrypt the hosted media" },
  );
  const got = await findByKind(alice, "media");
  const fetched = fs.readFileSync(got.localPath);
  if (!fetched.equals(png))
    throw new Error(
      `round-tripped bytes differ: sent ${png.length}, got ${fetched.length}`,
    );
  step(`peer fetched and decrypted ${fetched.length} bytes — identical to the original`);
  await shoot(alice, "50-alice-hosted-media.png");

  // ── READ: an INDEPENDENT writer's blob must be readable ─────────────────
  const other = makePng(320, 240);
  const up = await uploadLikeAndroid(other);
  // Padmé must agree, or the two clients disagree about blob layout.
  const expected = Number(padmeBucket(BigInt(4 + other.length)));
  if (up.paddedLen !== expected)
    throw new Error(`node padding disagrees with its own Padmé: ${up.paddedLen} vs ${expected}`);
  step(`node uploaded an Android-format blob: ${other.length} -> padded ${up.paddedLen}`);

  const marker = `store2:${up.cid}:${up.key}:image/png:320:240${up.cap ? ":" + up.cap : ""}`;
  await evalq(
    bob,
    `root.backend.sendMessage(${JSON.stringify(convoId)}, ${JSON.stringify(marker)})`,
  );

  await waitFor(
    async () => {
      const n = await evalq(alice, "root.messages.length");
      for (let i = 0; i < n; i++) {
        const r = JSON.parse(await evalq(alice, `JSON.stringify(root.messages[${i}])`));
        if (r.kind === "media" && r.width === 320 && r.localPath) return true;
      }
      return false;
    },
    {
      timeout: 150000,
      network: true,
      what: "alice to fetch the independently-written blob",
    },
  );

  const n = await evalq(alice, "root.messages.length");
  let independent = null;
  for (let i = 0; i < n; i++) {
    const r = JSON.parse(await evalq(alice, `JSON.stringify(root.messages[${i}])`));
    if (r.kind === "media" && r.width === 320 && r.localPath) independent = r;
  }
  const readBack = fs.readFileSync(independent.localPath);
  if (!readBack.equals(other))
    throw new Error(
      `could not read an independently-written blob: sent ${other.length}, got ${readBack.length}`,
    );
  step(`read back ${readBack.length} bytes written by an INDEPENDENT implementation — identical`);

  console.log(
    "\nPASS: hosted media round-trips, and our reader matches an independent Android-format writer.",
  );
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
