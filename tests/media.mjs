//
// Media gate (E4): inline photo send + render on the peer.
//
// Generates a small PNG fixture, sends it from Bob, and asserts Alice's client
// decoded it into a renderable image — not a raw marker string, and not a
// placeholder.
//
//   node tests/media.mjs [alicePort] [bobPort]
//
// Exit codes: 0 pass · 1 an assertion failed · 2 the invite never landed.
//
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
  dump,
  fail,
  inviteAndJoin,
  EXIT_OK,
  EXIT_FAIL,
  EXIT_NETWORK,
} from "./inspector.mjs";

const ALICE_PORT = Number(process.argv[2] ?? 5591);
const BOB_PORT = Number(process.argv[3] ?? 5592);

const W = 64;
const H = 48;

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

// A real PNG, written by hand so the test has no image dependency. Also
// exercises the backend's header parser: it must read 64x48 back out.
function makePng(file) {
  const raw = Buffer.alloc((W * 3 + 1) * H);
  let o = 0;
  for (let y = 0; y < H; y++) {
    raw[o++] = 0; // filter: none
    for (let x = 0; x < W; x++) {
      // Peers orange on the diagonal, dark canvas elsewhere — visibly ours.
      const on = Math.abs(x * (H / W) - y) < 6;
      raw[o++] = on ? 0xff : 0x0a;
      raw[o++] = on ? 0x50 : 0x0a;
      raw[o++] = on ? 0x00 : 0x0a;
    }
  }

  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0);
  ihdr.writeUInt32BE(H, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
  return png.length;
}

let CRC_TABLE = null;
function crc32(buf) {
  if (!CRC_TABLE) {
    CRC_TABLE = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return c ^ 0xffffffff;
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
  const file = path.join(os.tmpdir(), `peers-test-${W}x${H}.png`);
  const size = makePng(file);
  step(`fixture: ${file} (${size} bytes, ${W}x${H})`);

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

  // ── send ────────────────────────────────────────────────────────────────
  await evalq(
    bob,
    `root.backend.sendMedia(${JSON.stringify(convoId)}, ${JSON.stringify(file)}, "photo")`,
  );
  await waitFor(async () => (await findByKind(bob, "photo")) !== null, {
    timeout: 60000,
    what: "bob's photo in his own thread",
  });
  const sent = await findByKind(bob, "photo");

  // The backend reads dimensions straight out of the PNG header (no QtGui), so
  // a wrong parser shows up right here.
  if (sent.width !== W || sent.height !== H)
    throw new Error(
      `PNG header parsed wrong: expected ${W}x${H}, got ${sent.width}x${sent.height}`,
    );
  step(`bob: sent, dimensions parsed ${sent.width}x${sent.height}`);
  await shoot(bob, "30-bob-sent-photo.png");

  // ── receive ─────────────────────────────────────────────────────────────
  await waitFor(async () => (await findByKind(alice, "photo")) !== null, {
    timeout: 150000,
    network: true,
    what: "alice to receive the photo",
  });
  const got = await findByKind(alice, "photo");

  if (got.width !== W || got.height !== H)
    throw new Error(`peer sees wrong dimensions: ${got.width}x${got.height}`);
  if (!got.hasData) throw new Error("peer received the marker but no image data");
  if (!String(got.dataUri || "").startsWith("data:image/png;base64,"))
    throw new Error(`peer's dataUri looks wrong: ${String(got.dataUri).slice(0, 60)}`);

  // The whole point of the codec: a raw marker must never reach the UI.
  const n = await evalq(alice, "root.messages.length");
  for (let i = 0; i < n; i++) {
    const t = String(await evalq(alice, `root.messages[${i}].text`));
    if (t.includes("img1:")) throw new Error(`raw marker leaked into the thread: ${t.slice(0, 40)}`);
  }
  step("alice: received the photo, decoded to a data URI, no raw marker");
  await shoot(alice, "31-alice-received-photo.png");

  // ── oversize is refused, not silently dropped ───────────────────────────
  // A .png, not a .bin: the send path picks the type from the extension, and a
  // generic blob is now (correctly) routed to hosted media instead of inline —
  // which is a different refusal with a different message.
  const big = path.join(os.tmpdir(), "peers-test-oversize.png");
  fs.writeFileSync(big, Buffer.alloc(300 * 1024, 7));
  const errsBefore = JSON.parse(await evalq(bob, "JSON.stringify(root.backend.errors)")).length;
  await evalq(
    bob,
    `root.backend.sendMedia(${JSON.stringify(convoId)}, ${JSON.stringify(big)}, "photo")`,
  );
  await waitFor(
    async () => {
      const errs = JSON.parse(await evalq(bob, "JSON.stringify(root.backend.errors)"));
      return errs.length > errsBefore && /too large/i.test(errs[0].message);
    },
    { timeout: 20000, what: "an oversize file to be refused with a clear message" },
  );
  step("oversize: refused with a clear message rather than silently dropped");

  // ── the viewer pages and zooms ──────────────────────────────────────────
  //
  // Android's viewer is a pager with pinch and double-tap zoom; the desktop
  // equivalents are the arrow keys and the wheel. Paging needs two images, so
  // send a second one.
  await evalq(
    alice,
    `root.backend.sendMedia(${JSON.stringify(convoId)}, ${JSON.stringify(file)}, "photo")`,
  );
  await waitFor(
    async () => {
      const imgs = JSON.parse(await evalq(alice, "JSON.stringify(root.imagesInThread())"));
      return imgs.length >= 2;
    },
    { timeout: 60000, what: "alice's thread to hold two images" },
  );

  const imgs = JSON.parse(await evalq(alice, "JSON.stringify(root.imagesInThread())"));
  await evalq(
    alice,
    `root.openViewer(${JSON.stringify(imgs[0].uri)}, ${JSON.stringify(imgs[0].key)})`,
  );
  await waitFor(async () => (await evalq(alice, "mediaViewer.visible")) === true, {
    timeout: 10000,
    what: "the media viewer to open",
  });
  if ((await evalq(alice, "mediaViewer.index")) !== 0)
    throw new Error("the viewer opened on the wrong image");
  step(`viewer: opened on the clicked image (1 of ${imgs.length})`);

  await evalq(alice, "mediaViewer.next()");
  if ((await evalq(alice, "mediaViewer.index")) !== 1)
    throw new Error("paging forward did not advance the viewer");
  if ((await evalq(alice, "mediaViewer.current")) !== imgs[1].uri)
    throw new Error("paging advanced the index but not the displayed image");
  step("viewer: pages to the next image");

  await evalq(alice, "mediaViewer.zoom = 2.5");
  if (Number(await evalq(alice, "mediaViewer.zoom")) !== 2.5)
    throw new Error("zoom did not take");
  // Paging must reset the zoom, or the next image opens mid-zoom on a random
  // corner of itself.
  await evalq(alice, "mediaViewer.prev()");
  if (Number(await evalq(alice, "mediaViewer.zoom")) !== 1)
    throw new Error("paging left the previous image's zoom applied");
  step("viewer: zooms, and paging resets the zoom");

  // Re-open on the first image and let the frame settle: a screenshot taken in
  // the same tick as the property change captures the PREVIOUS frame, which is
  // how a viewer that never painted once looked like it had.
  await new Promise((r) => setTimeout(r, 1500));
  if ((await evalq(alice, "mediaViewer.visible")) !== true)
    throw new Error("the viewer closed itself before it could be captured");
  await shoot(alice, "32-alice-media-viewer.png");
  await evalq(alice, "mediaViewer.closed()");

  console.log("\nPASS: inline photo sent, decoded and rendered on the peer; "
    + "oversize refused; viewer pages and zooms.");
  alice.disconnect();
  bob.disconnect();
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
