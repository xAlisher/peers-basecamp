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
| Two `peers_ui` instances both reach Online | ✅ pass | `scripts/run-exchange.sh` |
| Distinct identities (different `get_address()`) | ✅ pass | alice `3ef6eb6c…`, bob `c99690f3…` |
| Storage isolation per `--user-dir` | ✅ pass | separate `module_data/chat_module/<id>` per instance |
| **MLS invite propagates between two `peers_ui` instances** | ✅ pass | `alice joined the conversation` on attempt 1 |
| **1:1 text, A → B** | ✅ pass | `scripts/run-exchange.sh` — 2 consecutive green runs |
| **1:1 text, B → A** | ✅ pass | reply received by the sender |
| **Group: create** | ✅ pass | shared name renders on both sides — `10-bob-group-created.png`, `11-alice-joined-group.png` |
| **Group: add member** | ✅ pass | alice joins; bob's roster reaches 2 committed |
| **Group: messages both ways** | ✅ pass | `12-alice-group-message.png`, `13-bob-group-roundtrip.png` |
| Photo, both directions | — | |
| GIF, both directions | — | |
| Video, both directions | — | |
| Voice note, both directions | — | |
| **Reply renders as a quote on the peer** | ✅ pass | quote shows the ORIGINAL text — `20-bob-sees-reply.png` |
| **Reaction renders on the peer** | ✅ pass | pill on the right message, folded — `21-bob-sees-reaction.png` |
| **Pin / unpin propagate** | ✅ pass | drives `currentPinnedJson` both ways — `22-alice-sees-pin.png` (no pinned-bar UI yet) |
| Forward | — | |
| Ordering + offline catch-up | — | |

### Known gap: the conversation preview goes blank after a control marker

`chat_module`'s `preview` is the last message in the conversation, so after a reaction or pin the
row preview empties — folded markers have no display text. Android shows the last *renderable*
message instead. Visible in `21-bob-sees-reaction.png`.

### Known gap: the pending-invite window is not observed

`add_group_member` commits and delivers asynchronously, so a member should appear as **pending**
before the group commits them. The group run never saw that state: our roster only refreshes on
`members_changed` or on selection, so the invite window is missed and the count jumps straight to
committed. Messages and the final roster are correct, but the pending affordance Peers shows on
Android is not reproduced yet.

### Resolved: the "messages never arrive" symptom was a stale instance

Every symptom in the first investigation — the selection reading back empty, three conversations
appearing, messages never showing — came from **testing a leaked process, not the new build**.

`logos-standalone-app-bin` forks `logos_host_qt` children per module. Killing the `nix run` wrapper
left all of them alive holding the inspector ports, so each rebuild launched instances that could not
bind and the harness silently connected to the **old** ones. Identity and conversations therefore
looked like they persisted across a wipe, and fixes appeared to do nothing.

`scripts/run-exchange.sh` now launches under `setsid`, kills the process group, matches on **argv**
(`comm`/`exe` are the ld-linux loader), and **preflights the ports — aborting rather than proceeding
onto a stale instance.**

Two further harness bugs it flushed out, both of which produced convincing false negatives:

- Waiting on `currentConversationId` rather than the conversation **list** conflated "the core never
  created it" with "the view didn't select it", and reported a network fault for our own bug.
- After a join retry there are two conversations; alice picked `conversations[0]` while bob sent to a
  different one. Both sides now pin the **shared convo id** — identified by diffing bob's id set
  before and after the call, since `list_conversations` has no documented ordering.

The join step itself is genuinely flaky: across five runs it landed first try three times, needed a
retry once, and failed all three attempts once. The retry loop and the distinct `EXIT_NETWORK` code
exist for exactly that.

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
