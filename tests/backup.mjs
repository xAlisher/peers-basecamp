//
// Peers mobile backup (`.peersenc`) reader gate (E6).
//
// This is a CROSS-IMPLEMENTATION test: Node writes the envelope exactly as
// Android's BackupCrypto.kt does, and the module's C++ reader decrypts it. If
// either side drifts — iteration count, salt/IV handling, tag placement, the
// UTF-8 passphrase encoding — this fails. A self-consistent round-trip inside
// one implementation would prove nothing about reading a real phone backup.
//
// Format (docs/BACKUP-FORMAT.md): a single UTF-8 JSON envelope, no framing.
//   PBKDF2-HMAC-SHA256(passphrase, salt, iters) -> 32-byte key
//   AES-256-GCM(iv=12B), tag APPENDED to the ciphertext (Java Cipher convention)
//
//   node tests/backup.mjs [port]
//
// Exit codes: 0 pass · 1 an assertion failed.
//
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { Inspector, evalq, waitFor, waitOnline, step, dump, fail, EXIT_OK } from "./inspector.mjs";

const PORT = Number(process.argv[2] ?? 5591);
const app = new Inspector(PORT, "app");

const PASSPHRASE = "correct horse battery staple";
const WRONG = "incorrect horse battery staple";
const ITERS = 600000; // BackupCrypto.kt:30
const CONVOS = 3;
const MESSAGES = 7;

function makeBackup(file, passphrase) {
  // The identity is base64 of the raw 64-byte seed file (BACKUP-FORMAT §5).
  const identity = crypto.randomBytes(64).toString("base64");

  const payload = {
    format: "logos-chat-backup",
    version: 1,
    schemaVersion: 1,
    exportedAt: 1786255561000,
    identity,
    conversations: Array.from({ length: CONVOS }, (_, i) => ({
      id: `convo-${i}`,
      nickname: `Peer ${i}`,
    })),
    messages: Array.from({ length: MESSAGES }, (_, i) => ({
      convoId: `convo-${i % CONVOS}`,
      body: `message ${i}`,
      direction: i % 2 ? "out" : "in",
    })),
    group_members: [],
    kv: { theme: "dark" },
  };

  const salt = crypto.randomBytes(16); // BackupCrypto.kt:32
  const iv = crypto.randomBytes(12);
  const key = crypto.pbkdf2Sync(Buffer.from(passphrase, "utf8"), salt, ITERS, 32, "sha256");

  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  const body = Buffer.concat([
    cipher.update(Buffer.from(JSON.stringify(payload), "utf8")),
    cipher.final(),
  ]);
  // Java's Cipher appends the tag; OpenSSL keeps it separate. The FILE carries
  // it appended, so the reader has to split it back off.
  const ct = Buffer.concat([body, cipher.getAuthTag()]);

  const envelope = {
    format: "peers-backup-enc",
    v: 1,
    kdf: "pbkdf2-hmac-sha256",
    iters: ITERS,
    salt: salt.toString("base64"),
    iv: iv.toString("base64"),
    ct: ct.toString("base64"),
  };
  fs.writeFileSync(file, JSON.stringify(envelope), "utf8");
  return file;
}

async function openBackup(file, passphrase) {
  await evalq(app, 'root.lastBackup = ""');
  await evalq(
    app,
    `root.backend.openBackup(${JSON.stringify(file)}, ${JSON.stringify(passphrase)})`,
  );
  await waitFor(async () => (await evalq(app, "root.lastBackup")) !== "", {
    timeout: 60000,
    what: "the backup reader to report a result",
  });
  return String(await evalq(app, "root.lastBackup"));
}

async function main() {
  await app.connect();
  await waitOnline(app);
  step("Online");

  const good = makeBackup(path.join(os.tmpdir(), "peers-test-backup.peersenc"), PASSPHRASE);
  step(`fixture written (${ITERS} iters, ${CONVOS} conversations, ${MESSAGES} messages)`);

  // ── correct passphrase ──────────────────────────────────────────────────
  const ok = await openBackup(good, PASSPHRASE);
  if (ok !== `ok:${CONVOS}:${MESSAGES}`)
    throw new Error(`expected ok:${CONVOS}:${MESSAGES}, got ${JSON.stringify(ok)}`);
  step(`decrypted a Node-written envelope: ${ok}`);

  // The identity must be reported as present but NOT adopted (ADR 0004), and
  // must never reach QML.
  const errs = JSON.parse(await evalq(app, "JSON.stringify(root.backend.errors)"));
  const note = errs.find((e) => /identity \(64 bytes\)/.test(e.message));
  if (!note) throw new Error(`expected an identity note in errors, got ${JSON.stringify(errs)}`);
  if (!/cannot adopt it/.test(note.message))
    throw new Error(`the identity note should say it cannot be adopted: ${note.message}`);
  step("identity reported as present (64 bytes) and explicitly NOT adopted");

  // ── wrong passphrase fails cleanly ──────────────────────────────────────
  const bad = await openBackup(good, WRONG);
  if (!bad.startsWith("fail:"))
    throw new Error(`a wrong passphrase must fail, got ${JSON.stringify(bad)}`);
  if (!/passphrase/i.test(bad))
    throw new Error(`the failure should name the passphrase: ${bad}`);
  step(`wrong passphrase refused: ${bad.slice(5)}`);

  // ── a non-backup file is refused, not misread ───────────────────────────
  const junk = path.join(os.tmpdir(), "peers-test-not-a-backup.txt");
  fs.writeFileSync(junk, "this is not JSON at all");
  const j = await openBackup(junk, PASSPHRASE);
  if (!j.startsWith("fail:")) throw new Error(`junk must be refused, got ${j}`);
  step(`junk refused: ${j.slice(5)}`);

  // ── a legacy plaintext backup is NAMED, not called corrupt ──────────────
  const legacy = path.join(os.tmpdir(), "peers-test-legacy.json");
  fs.writeFileSync(legacy, JSON.stringify({ format: "logos-chat-backup", version: 1 }));
  const l = await openBackup(legacy, PASSPHRASE);
  if (!/older unencrypted backup/i.test(l))
    throw new Error(`a legacy plaintext backup should be named as such, got ${l}`);
  step("legacy plaintext backup identified by name");

  console.log("\nPASS: reads a Node-written .peersenc; refuses wrong passphrase, junk and legacy.");
  app.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [app]));
