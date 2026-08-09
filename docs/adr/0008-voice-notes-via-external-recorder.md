# ADR 0008 — Voice notes are captured by an external recorder, not QtMultimedia

- **Status:** Accepted — implemented and verified 2026-08-09
- **Relates to:** issue #41 (voice notes), [ADR 0005](0005-screenshot-verification.md) (why we do not rely on host-optional Qt modules)

## Context

Peers Android records voice notes with the platform recorder: mono AAC in an MP4
container, a duration in milliseconds, and ~40 amplitude bars normalised to
0..100 for the bubble (`src/native/Audio.ts`, `MAX_RECORDING_MS = 120000`). The
wire format is fixed by the phone — `voc1:<mime>:<durMs>:<w,w,…>␟<base64>` — so
anything we produce has to decode there unchanged.

The Basecamp Qt host **does not ship QtMultimedia**. There is no in-process
recorder, no `QAudioInput`, and no player. Three options were on the table:

1. **Declare voice notes impossible on the desktop.** Honest, and wrong: the
   capability exists on every desktop, just not inside our process.
2. **Add QtMultimedia to the module's closure.** Pulls a large dependency tree
   into the `.lgx` for one feature, and the host may still not load a second
   copy of a Qt module cleanly.
3. **Drive an external recorder.** Every Linux desktop that can record has one
   of ffmpeg, parecord or arecord.

## Decision

**Capture through an external tool over `QProcess`, and measure the result
ourselves.**

- Preference order **ffmpeg → parecord → arecord**, resolved at runtime with
  `QStandardPaths::findExecutable`. ffmpeg is first because it stops cleanly on
  `q` and finalises the RIFF header.
- **Audio always lands as WAV first.** This is the part that matters: the
  waveform is then *measured* from the PCM samples — 40 buckets, peak per
  bucket, normalised so the loudest bar is 100 — and the duration comes from the
  sample count rather than from how long the button was held. A recorder that
  drops the first second produces a shorter bar strip, not a lie.
- The WAV is transcoded to **mono AAC (`audio/mp4`)** so the phone plays it with
  no special handling. **Without ffmpeg the WAV is sent as-is** (`audio/wav`,
  larger but playable) rather than refusing to send.
- Capture stops at Android's **two-minute cap**, and says so instead of
  discarding what was recorded.
- Playback is the reverse trade: the note is materialised into the cache and the
  bubble offers to open it in the desktop's own player. The waveform and
  duration render inline, as Android draws them.

## Consequences

- **A machine with none of the three tools cannot record.** The failure names all
  three rather than saying "unavailable", so it is actionable. Nothing is
  bundled: ffmpeg in the closure would dwarf the rest of the module.
- **Normalising against the take, not full scale**, means a quietly-spoken note
  still renders as a waveform instead of a flat line. It also means the bars are
  relative — two notes at different volumes look similar. Android does the same.
- Recording is **not** sandboxed the way in-process capture would be: we spawn a
  process that opens the default input. That is visible to the user (the module
  is what started it) and is the same trade any desktop screen-recorder makes.
- The test (`tests/voice.mjs`) records from a real microphone and asserts on the
  **peer** — duration, all 40 bars, mime and the decoded file. On a machine with
  no capture device it exits `EXIT_NETWORK` (environment) rather than failing or,
  worse, passing quietly.

## Alternatives not taken

- **Synthesising a waveform** from the encoded file size or from a fixed pattern.
  It would look right and mean nothing; the bars are supposed to be the audio.
- **Sending a zero waveform and zero duration** (what the earlier `sendMedia`
  path did for `kind == "voice"`). The phone renders that as a dead strip.
