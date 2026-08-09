# Status — Peers for Basecamp

**Repo:** https://github.com/xAlisher/peers-basecamp (public) · **Updated:** 2026-08-09

---

## Where it stands

**The module works.** It builds, installs, loads, renders in the Peers design language, and two
instances exchange real end-to-end-encrypted traffic over the live `logos.test` fleet — 1:1 and
group messages, replies, reactions, pins, and inline photos, each verified by observing the **peer**,
not our own optimistic state.

Six live gates, all green:

| Gate | What it proves |
|---|---|
| `tests/ui-tour.mjs` | every panel renders (chats, contacts, settings, dialogs) |
| `tests/exchange.mjs` | 1:1 bidirectional round-trip between two instances |
| `tests/group.mjs` | group create, invite (incl. the **pending** window), messages both ways |
| `tests/interactions.mjs` | reply, reaction, pin, unpin — all rendering on the peer |
| `tests/media.mjs` | inline photo sent, decoded and rendered; oversize refused |
| `tests/backup.mjs` | a **Node-written** `.peersenc` decrypted by our C++ reader |

Plus offline gates in `scripts/check-all.sh`: identicon equivalence (8,026 pairs against the real
Android implementation), the parity matrix, and two build-trap guards.

Run everything: `./scripts/run-all-scenarios.sh`

---

## The architecture correction that shaped everything

The build plan specified riding `chat_module` through a **C FFI** and called building
`liblogoschat` "the one real porting risk". That API exists only in the stale June ref clone.
**Upstream rewrote the module in Rust** — v0.2.2, `interface: cdylib`, a **lidl** contract. The
porting risk was moot; the real constraints were different ones:

| ADR | |
|---|---|
| [0001](docs/adr/0001-ride-upstream-chat-module-0-2-2.md) | Ride upstream v0.2.2; model on `logos-chat-ui` 0.2.2 |
| [0002](docs/adr/0002-rich-content-rides-the-message-body.md) | The contract is **text only** — media, reactions, replies and pins ride markers in the body |
| [0003](docs/adr/0003-two-instance-desktop-interop-is-the-primary-gate.md) | Two local instances **do** coexist; the plan's port-60000 claim is false |
| [0004](docs/adr/0004-identity-import-and-phone-interop.md) | **No identity-import method exists** — "same address from a backup" is not achievable |
| [0005](docs/adr/0005-three-panel-layout-and-peers-skin.md) | Three panels; Peers parity beats the Logos DS; no `MultiEffect` |
| 0006 (in the `.rep`) | List data crosses as JSON, not remoted models |

---

## Not done

- **Voice notes, video, GIF** — the codec handles them; capture/playback is not built.
- **Hosted media (`store2:`)** — needs a storage-module dependency. Until then anything over 256 KB
  is **refused with a message naming the size and limit**, not silently dropped.
- **QR** — the address card shows an honest placeholder. No encoder, and no scanner. A wrong QR
  would send messages to the wrong identity, so a fake one is worse than none.
- **PIN app-lock, duress PIN, lock screen, reset** — rendered as disabled with "not available yet"
  rather than controls that do nothing.
- **Forward, copy, delete-for-me** — not wired.
- **Leaving a group remotely** — `chat_module` 0.2.2 has **no leave primitive**; only a local
  delete. Presented as local, not as "the group was told".
- **Adopting a backup's identity** — upstream-blocked (ADR 0004). Decryption, schema parsing and
  the reporting all work.
- **Phone interop** — not attempted. `docs/INTEROP.md` holds the matrix and the fleet discipline.

`docs/PARITY.md` is the authoritative per-feature list and is checked by a script.

---

## Things worth knowing before you touch it

- **The join step is genuinely flaky.** Across many runs it lands first try most of the time, needs
  a retry sometimes, and fails outright occasionally. The harness retries, and exit code **2** means
  "the network did not deliver", distinct from **1**, "an assertion failed". Re-run before digging.
- **`qml/qmldir` is builder-owned.** Shipping your own breaks the plugin load with a misleading
  `capability_module` SIGSEGV. So does an **untracked** source file, since the flake's `src` is a
  git source. Both are now guarded in `scripts/check-all.sh`; both cost real time first.
- **Killing the `nix run` wrapper leaves the app alive** holding the inspector ports, so a rebuild
  silently tests the *old* binary. `run-exchange.sh` preflights the ports and aborts rather than
  lying to you.

The failure that dominated the first half of this build, and what I'd change, is written up in
[`fails/`](fails/).
