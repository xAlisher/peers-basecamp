//
// Voice-note gate (E13): record from a real microphone, send, render on the peer.
//
// This exercises the whole capture path — the external recorder, the WAV parse,
// the measured waveform and the AAC transcode — and then asserts the RESULT on
// the OTHER client, so a note that encodes but does not decode fails here.
//
//   node tests/voice.mjs [alicePort] [bobPort]
//
// Exit codes: 0 pass · 1 an assertion failed · 2 the invite never landed, or
// the machine has no capture device (which is an environment fact, not a bug).
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

const alice = new Inspector(ALICE_PORT, "alice");
const bob = new Inspector(BOB_PORT, "bob");

// Long enough that the duration and the waveform are meaningful, short enough
// that the suite does not crawl.
const RECORD_MS = 2500;

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

  // ── record ──────────────────────────────────────────────────────────────
  const errsBefore = Number(await evalq(bob, "root.backend.errors.length"));
  await evalq(bob, "root.backend.startRecording()");

  let started = false;
  try {
    await waitFor(async () => String(await evalq(bob, "root.backend.recording")) === "true", {
      timeout: 8000,
      what: "capture to start",
    });
    started = true;
  } catch {
    /* handled below */
  }

  if (!started) {
    // No microphone here. That is the environment, not the client — say which,
    // and do not dress a skipped test up as a pass.
    const errs = JSON.parse(await evalq(bob, "JSON.stringify(root.backend.errors)"));
    console.error(
      `\nNETWORK: no capture device on this machine, so voice notes cannot be exercised.\n` +
        `  backend said: ${errs.slice(errsBefore).join(" | ") || "(nothing)"}`,
    );
    process.exit(EXIT_NETWORK);
  }
  step("capture started");

  await shoot(bob, "24-recording.png");
  await new Promise((r) => setTimeout(r, RECORD_MS));

  // The composer's timer is driven by the backend, so a stuck clock shows here.
  const ms = Number(await evalq(bob, "root.backend.recordingMs"));
  if (!(ms >= 1000))
    throw new Error(`the recording clock read ${ms} ms after ${RECORD_MS} ms of capture`);
  step(`clock advanced (${ms} ms)`);

  await evalq(bob, `root.backend.sendRecording(${JSON.stringify(convoId)})`);
  await waitFor(async () => String(await evalq(bob, "root.backend.recording")) === "false", {
    timeout: 30000,
    what: "capture to finish and encode",
  });

  const mine = await findByKind(bob, "voice");
  if (!mine) {
    dump(await evalq(bob, "JSON.stringify(root.backend.errors)"));
    throw new Error("bob's own voice note never appeared in his thread");
  }

  // Duration is measured from the PCM samples, not from the button press, so a
  // broken WAV parse produces a wrong number rather than a plausible one.
  if (!(mine.durationMs >= 1000 && mine.durationMs <= RECORD_MS + 4000))
    throw new Error(`duration ${mine.durationMs} ms does not match ~${RECORD_MS} ms of capture`);
  step(`duration measured from the audio (${mine.durationMs} ms)`);

  // 40 bars, as Android renders (src/native/Audio.ts).
  const wf = mine.waveform || [];
  if (wf.length !== 40) throw new Error(`waveform has ${wf.length} bars, expected 40`);
  if (!wf.every((n) => n >= 0 && n <= 100)) throw new Error("waveform bars are outside 0..100");
  if (Math.max(...wf) !== 100)
    throw new Error("waveform is not normalised — the loudest bar should be 100");
  step(`waveform measured (40 bars, peak ${Math.max(...wf)}, floor ${Math.min(...wf)})`);

  // ── the peer is the judge ───────────────────────────────────────────────
  await waitFor(async () => (await findByKind(alice, "voice")) !== null, {
    timeout: 90000,
    what: "the voice note to arrive at alice",
  });
  const theirs = await findByKind(alice, "voice");

  if (theirs.durationMs !== mine.durationMs)
    throw new Error(`duration disagrees across the wire: ${mine.durationMs} vs ${theirs.durationMs}`);
  if ((theirs.waveform || []).join(",") !== wf.join(","))
    throw new Error("the waveform did not survive the wire");
  if (!theirs.mime || !/^audio\//.test(theirs.mime))
    throw new Error(`the peer sees mime "${theirs.mime}", which is not audio`);
  // The decoded audio must land on disk, or the bubble has nothing to play.
  if (!theirs.localPath) throw new Error("the peer decoded no audio file to play");
  step(`peer renders it (${theirs.mime}, ${theirs.durationMs} ms, file present)`);

  await shoot(alice, "25-alice-voice-note.png");
  await shoot(bob, "26-bob-voice-note.png");

  console.log("\nPASS: recorded from the mic, measured, transcoded and rendered on the peer.");
  process.exit(EXIT_OK);
}

main().catch((e) => fail(e, [alice, bob]));
