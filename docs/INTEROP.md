# Interop matrix

Two axes, per ADR 0003 and ADR 0004:

- **Desktop ⇄ desktop** — two local instances with separate `--user-dir`. The primary gate. Fast,
  headless, deterministic, and it tests *our* code.
- **Desktop ⇄ Peers Android** — the second gate. The phone runs a **different libchat generation**
  (our patched fork @ `462a4884`) than `chat_module` 0.2.2 (@ `5c55c2ee`), so compatibility is an
  open empirical question. A negative result here is a documented finding, not a build failure.

A cell is only "pass" when the traffic was **observed rendering on both ends** — a desktop
screenshot plus, for the phone axis, an `adb exec-out screencap`. A message is not "sent" until it
renders on the other client.

---

## Baseline: the stack itself (verified 2026-08-09)

Before any of our code, the platform path was proven end to end using upstream's own
`chat-ui-exchange` harness, offscreen on `wild`.

| Step | Result | Evidence |
|---|---|---|
| Two instances coexist on one host | ✅ pass | distinct libp2p peer IDs, no fixed-port contention in `ss -tln` |
| Both reach **Online** on `logos.test` | ✅ pass | `01-alice-address.png` |
| `get_address()` returns a 64-char address | ✅ pass | `01-alice-address.png` |
| `create_conversation(peer_address)` | ✅ pass | driver log |
| Peer joins the conversation | ⚠️ **flaky** | failed on run 1, passed on run 2 — see below |
| Message desktop → desktop | ✅ pass | `02-bob-sent.png`, `03-alice-received.png` |
| Reply desktop → desktop | ✅ pass | `04-alice-replied.png`, `05-bob-roundtrip.png` |

Screenshots: [`screenshots/interop-desktop/`](screenshots/interop-desktop/).

### The flaky join — read this before trusting a red run

Run 1 failed with `FAILED: timed out waiting for alice joins conversation`. Both instances were
Online and `create_conversation` had succeeded; the MLS invite simply did not reach the peer inside
the harness timeout. Run 2, with no changes, passed the full round-trip.

The join step depends on fetching the peer's key package from the registry over the live fleet, and
the delivery logs during the failed run were full of
`no subscribed peers found … contentTopic=/mix/rln/metadata/v1`.

**Consequence for our harness:** retry the join with backoff, and report "invite did not land"
distinctly from "assertion failed". A suite that goes red at random teaches people to ignore it,
which is worse than having no suite.

---

## Desktop ⇄ desktop matrix

Status: `—` not yet run · `✅` passed with evidence · `❌` failed · `⚠️` flaky · `🚧` blocked

| Cell | Status | Evidence |
|---|---|---|
| 1:1 text, A → B | — | |
| 1:1 text, B → A | — | |
| Group: create | — | |
| Group: add member, roster visible to all | — | |
| Group: message to all members | — | |
| Photo, both directions | — | |
| GIF, both directions | — | |
| Video, both directions | — | |
| Voice note, both directions | — | |
| Reply renders as a quote on the peer | — | |
| Reaction renders on the peer | — | |
| Pin renders on the peer | — | |
| Forward | — | |
| Ordering + offline catch-up | — | |

## Desktop ⇄ Peers Android matrix

| Cell | Status | Evidence |
|---|---|---|
| 1:1 text, desktop → phone | — | |
| 1:1 text, phone → desktop | — | |
| Group with a phone member | — | |
| Photo / GIF / video | — | |
| Voice note | — | |
| Reply / reaction / pin | — | |
| Same address from a mobile backup | 🚧 blocked | ADR 0004 — `chat_module` 0.2.2 has no identity-import method |

### Fleet discipline

- **Never reset the Pixel.** `install -r` only; PIN `111111`; verification use only.
- **Samsung is the destructive-test device** — resets, wipes and migration tests go there.
- Never guess a PIN: three wrong attempts wipe the device.
- `adb input text` drops parentheses, cannot type emoji, and autocapitalises URLs — keep driven
  messages ASCII and pick emoji by tapping.
