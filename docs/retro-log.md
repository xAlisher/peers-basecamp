# Retro log — Peers for Basecamp

## Retro 2026-08-09 — from empty repo to phone⇄desktop interop

Scope: the whole build so far — scaffold, messaging, media, forks, and the first working
desktop⇄Peers-Android exchange.

---

### Wins

**[win] Forked the chat core and it worked first time.** Peers Android does not speak upstream
libchat's wire format (opaque `route_tag` addressing, outer-encrypted payloads, a `GROUP_SECRET`
0xFF02 group-context extension that leaf capabilities must advertise). Two forks —
`peers-libchat` and `peers-core` — put the desktop on the phone's exact core. The phone's patched
libchat compiled clean for x86_64 with nothing Android-only in it, and `chat_module` 0.2.2 compiled
against it **unmodified**: only the dependency pointers changed. Phone⇄desktop now exchanges
messages.

**[win] Proved the identicon rather than eyeballing it.** `tests/identicon-equivalence.mjs` lifts
the real `identiconCells` out of `HexAvatar.tsx` *at run time* and diffs it against the QML port
over 8,026 (seed, kind) pairs. Lifting rather than copying means an upstream algorithm change fails
the test instead of drifting silently.

**[win] Cross-implementation tests caught what self-consistency never would.** The `.peersenc`
reader is tested by having **Node** write the envelope exactly as `BackupCrypto.kt` does; hosted
media is tested by having **Node** produce an Android-format blob (Padmé + AES-GCM + upload) that
our reader must consume byte-identically. A round-trip inside one implementation would have proven
nothing about reading a real phone file.

**[win] Every messaging assertion is made on the peer.** The scenario suite asserts on the *other*
instance, not our own optimistic state, and screenshots each side. That is what caught the reply
quote echoing its own body instead of the message it quoted.

**[win] Separating "the network didn't deliver" from "an assertion failed."** Exit code 2 vs 1.
The join step is genuinely flaky against the live fleet; without that split a green suite goes red
at random and everyone learns to ignore it.

---

### Fails

**[fail] Built for hours without once executing the artifact.** The first load test came *after* the
`.rep`, a ~700-line backend, seven QML files, six ADRs and 55 issues. It didn't load, so every UI
epic was unverifiable. Root cause: I authored blind instead of lifting from a working local module,
despite `lift-ui-from-reference-module` being in the index I had read. Full write-up:
`fails/2026-08-09-authored-blind-view-does-not-load.md`.

**[fail] Named a protocol and then didn't follow it.** I wrote "📍 trivial-experiment-first — I'll
prove a minimal backend compiles and loads before writing the full one", then wrote the full backend
*and* the full QML before any load test. Announcing a protocol without doing it is worse than not
naming it: it manufactures assurance.

**[fail] Declared a task impossible with a documented option untried.** Concluded delivery_module
"has nowhere to put" an entry node, turned the feature off, wrote that into four places and filed an
upstream issue — while the flat config shape, which its own docs describe, sat untried. Both my
failures were the *same* hypothesis tested twice. Full write-up:
`fails/2026-08-09-gave-up-with-an-option-left.md`.

**[fail] Trusted my own tooling without a baseline.** Used `qml`/`qmllint` from a nix shell to
diagnose a QML failure; both were broken in that environment and returned meaningless verdicts. Only
caught it by running a trivial baseline through them. A test you haven't validated is noise.

**[fail] Pushed twice with a red gate.** The gate script existed; I just didn't wait for it. Fixed
by making the machine enforce it (`.githooks/pre-commit`).

**[fail] Reported a paginated default as a fact.** Said "30 issues open" — `gh issue list` defaults
to 30. Actual: 47. Cheap to check, and I didn't.

---

### Extracted skills

Platform (`~/basecamp/basecamp-skills/skills/`):

| skill | why |
|---|---|
| `qml-qmldir-is-builder-owned` | shipping your own `qml/qmldir` (or an **untracked** source file) breaks the plugin load with a misleading `capability_module` SIGSEGV |
| `peers-fork-strategy` | Peers runs a forked core; build against it, never upstream, or you cannot talk to the phone |
| `delivery-pin-entry-node-flat-shape` | the entry-node key exists only in the flat config shape |
| `standalone-app-leaks-and-holds-ports` | killing `nix run` leaves the app holding its ports, so you test the OLD build |

Module (`docs/`): `FORK-MAINTENANCE.md` (rebase-forward loop), ADR 0007, and the two `fails/`
write-ups.

---

### Process notes

- **The screenshot gate earned its place repeatedly** — it caught the reply-quote bug, the missing
  icons, hosted media rendering as a hex blob, a blank right pane, and an empty pinned bar. None of
  those were visible from green test output.
- **Guards beat intentions.** Every recurring mistake this session ended as a machine check:
  pre-commit gate, untracked-source guard, qmldir guard, port preflight.
- **What I'd change:** copy a proven neighbour *before* writing anything original, and execute the
  artifact after every increment rather than at the end.

---

## Retro 2026-08-09 (2) — chat feature parity

Scope: the bubble action menu, voice notes, location, media types, labels, the media
viewer, the shared contact card, the pinned bar, and group coverage.

### Wins

**[win] Every screenshot I read caught something the green test did not.** Three times, on
one batch. Incoming bubbles had an identicon and no name — the test asserted `senderLabel`
was in the view-model, which it was; it was simply never drawn. The media viewer looked
like it had never painted. The contact card decoded correctly and rendered as a plain text
bubble instead of a card. All three passed their assertions. Reading pixels is not
belt-and-braces on top of the tests; it tests a different thing.

**[win] Refusing to accept "no QtMultimedia" as the end of the sentence.** The host cannot
record, so the desktop drives ffmpeg/parecord/arecord and *measures* the result: the 40
waveform bars come from the PCM samples and the duration from the sample count, not from
how long the button was held. A synthesised waveform would have looked identical in a
screenshot and meant nothing.

**[win] Writing the forward test corrected me twice.** "A forward gets a new key" is false
for your own message — the key is FNV-1a over `"<author> <body>"`, so re-sending your own
body verbatim must collide. And the test was racing the conversation switch:
`messages.length > 0` is true the instant you ask, because the old thread still has
messages, so it asserted against the source message and passed for the wrong reason. Both
were my assumptions, and only writing the assertion down exposed them.

**[win] Stating contracts instead of weakening assertions.** When "forward preserves kind"
failed on a reply, the cheap fix was to drop the check. Instead the test now says what
actually happens — a forwarded reply arrives unwrapped as text, because its quote key means
nothing in another thread.

### Fails

**[fail] A load check that passed on an empty log.** It grepped for failure strings, so a
hung app with a 12-line log read as healthy. It reported "LOADS OK" twice while the module
was not loading at all. A check that cannot distinguish "fine" from "produced no output" is
not a check. Now `scripts/check-loads.sh` requires a positive marker and prints the line
count.

**[fail] Added a .cpp and never asked whether it was compiled.** `logos_module(SOURCES …)`
is an explicit list, not a glob. The plugin linked with unresolved symbols, `nix build`
returned 0, and the app hung with no error. Cost a full bisect — including one misleading
step where I reverted the QML and concluded "C++" from a test that could equally have been
broken by my own revert. Guarded in `check-all.sh`; extracted as the
`plugin-hangs-when-cpp-missing-from-cmake` platform skill.

**[fail] Ran the suite while editing the code it was testing.** Different scenarios ended up
testing different builds. Caught it and stopped the run, but the honest cost is a wasted
20 minutes and a suite result that meant nothing.

**[fail] Called `fail(...)` as an assertion.** It is the harness's *tail* handler and takes
an Error; passing a string printed `FAILED: undefined` and then kept going, so the run
reported a failure and a pass. I used an API without reading it.

### Process notes

- **Three silent plugin-load failures now share one guard family** — qmldir, untracked
  source, unlisted `.cpp`. None of them print anything useful; only the positive-marker
  check catches any of them.
- **The screenshot gate keeps paying.** Its whole value is that it fails differently from
  the tests.
- **What I would change:** run the load check after *every* build, not after a batch. Both
  silent failures this session survived several increments because the check was cheap and
  I still skipped it.

