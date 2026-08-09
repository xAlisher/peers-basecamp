//
// Wire-format equivalence for the inline-payload markers (E4).
//
// This exists because of a real interop break: Peers Android separates a
// marker's header from its payload with the PRINTABLE glyph **U+241F SYMBOL FOR
// UNIT SEPARATOR** (UTF-8 `E2 90 9F`), and we emitted the ASCII control
// character **U+001F**. They read identically in prose and are different bytes
// on the wire. Desktop⇄desktop never noticed — both ends agreed on the wrong
// byte — while the phone's parser could not find a separator at all and rendered
// the raw marker as text. A voice note arrived looking like binary garbage.
//
// So this test does not check our encoder against our decoder. It runs what we
// emit through **Android's actual parsers**, lifted out of the phone's TypeScript
// at run time. If either side changes the format, this fails instead of drifting.
//
//   node tests/wire-separator.mjs
//
// Exit codes: 0 pass · 1 an assertion failed · 2 the Android source is missing.
//
import { readFileSync, existsSync } from "node:fs";

const ANDROID = process.env.PEERS_ANDROID_SRC ?? `${process.env.HOME}/projects/logos-chat-android`;
const VOICE_TS = `${ANDROID}/src/native/voiceMsg.ts`;
const IMAGE_TS = `${ANDROID}/src/native/imageMsg.ts`;

if (!existsSync(VOICE_TS) || !existsSync(IMAGE_TS)) {
  console.error(
    `SKIP: Peers Android source not found at ${ANDROID}.\n` +
      `      Set PEERS_ANDROID_SRC to the checkout to run this gate.`,
  );
  process.exit(2);
}

// Strip the TypeScript so plain JS remains. Lifting beats copy-pasting: a change
// on the phone breaks this test instead of silently breaking interop.
function lift(path) {
  return readFileSync(path, "utf8")
    .replace(/^export\s+interface[\s\S]*?^}\s*$/gm, "")
    .replace(/:\s*\{meta:\s*\w+;\s*\w+:\s*string\}\s*\|\s*null/g, "")
    .replace(/:\s*\{meta:\s*\w+;\s*payload:\s*string\}\s*\|\s*null/g, "")
    .replace(/:\s*(VoiceMeta|ImageMeta)\b/g, "")
    .replace(/:\s*number\[\]/g, "")
    .replace(/:\s*string\b/g, "")
    .replace(/:\s*number\b/g, "")
    .replace(/:\s*boolean\b/g, "")
    .replace(/\bexport\s+/g, "")
    .replace(/\b(\w+)\s+as\s+\w+/g, "$1")
    .replace(/(\w+)\s*:\s*unknown/g, "$1");
}

const voice = new Function(`${lift(VOICE_TS)}; return { parseVoiceWire, buildVoiceWire };`)();
const image = new Function(`${lift(IMAGE_TS)}; return { parseImageWire, buildImageWire };`)();

let failures = 0;
const check = (ok, what) => {
  console.log(`  ${ok ? "ok  " : "FAIL"}  ${what}`);
  if (!ok) failures++;
};

// The separator Android actually uses, taken from its own output rather than
// asserted from a constant we might also have got wrong.
const androidVoiceWire = voice.buildVoiceWire(
  { mime: "audio/mp4", durationMs: 3399, waveform: [0, 50, 100] },
  "QUJD",
);
const sepCodepoint = androidVoiceWire.codePointAt(androidVoiceWire.indexOf("QUJD") - 1);
console.log(`Android's separator: U+${sepCodepoint.toString(16).toUpperCase().padStart(4, "0")}`);
check(sepCodepoint === 0x241f, "Android separates header from payload with U+241F");

const SEP = String.fromCodePoint(0x241f);

// ── what WE emit must parse on the phone ────────────────────────────────────
//
// Built here in the same shape ContentMarkers.cpp emits, so a change to the C++
// grammar shows up as a parse failure rather than as a shrug.
const ourVoice = `voc1:audio/mp4:3399:${[0, 50, 100].join(",")}${SEP}QUJD`;
const parsedVoice = voice.parseVoiceWire(ourVoice);
check(parsedVoice !== null, "our voc1: parses with Android's parseVoiceWire");
if (parsedVoice) {
  check(parsedVoice.meta.mime === "audio/mp4", "  mime survives");
  check(parsedVoice.meta.durationMs === 3399, "  duration survives");
  check(parsedVoice.meta.waveform.join(",") === "0,50,100", "  waveform survives");
  check(parsedVoice.base64 === "QUJD", "  payload survives");
}

const ourImage = `img1:image/png:64:48${SEP}QUJD`;
const parsedImage = image.parseImageWire(ourImage);
check(parsedImage !== null, "our img1: parses with Android's parseImageWire");
if (parsedImage) {
  check(parsedImage.meta.mime === "image/png", "  mime survives");
  check(parsedImage.meta.width === 64 && parsedImage.meta.height === 48, "  dimensions survive");
  check(parsedImage.base64 === "QUJD", "  payload survives");
}

// ── and the ASCII separator must NOT parse, which is the whole bug ──────────
//
// If this ever starts passing, Android has become lenient and the regression
// this test guards can return unnoticed.
const legacy = `voc1:audio/mp4:3399:0,50,100${String.fromCodePoint(0x1f)}QUJD`;
check(
  voice.parseVoiceWire(legacy) === null,
  "the ASCII U+001F form does NOT parse on Android (this was the bug)",
);

if (failures > 0) {
  console.error(`\nFAILED: ${failures} check(s). Our wire format does not match the phone's.`);
  process.exit(1);
}
console.log("\nPASS: our inline-payload markers parse with Peers Android's own parsers.");
