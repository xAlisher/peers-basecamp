# Parity matrix — Peers Android ↔ Peers for Basecamp

The living record of how far the desktop client has caught up with the Android app, and the
explicit list of what is deliberately **not** being ported.

Checked by `scripts/check-parity.sh`, so drift surfaces as a failure rather than as quiet rot.

**Status vocabulary**

| | Meaning |
|---|---|
| `done` | Implemented **and** verified with evidence (test output or a screenshot on the issue) |
| `wip` | Partly implemented; not yet verified |
| `todo` | Not started |
| `blocked` | Cannot proceed — reason and next step required |
| `dropped` | Deliberately out of scope for desktop |

Android ground truth: `docs/FEATURE-INVENTORY.md` (extracted from source with `path:line` citations).

---

## E1 — Core messaging

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Conversation list + rows | yes | `done` | Row with identicon, name, preview and timestamp — screenshot |
| Conversation row menu (open/group info/delete) | yes | `todo` | Android has no archive/mute/pin-conversation |
| Chat thread + bubbles | yes | `done` | Own bubble accent + white text, peer bubble #1F1F1F, sender identicon — screenshot `interop-desktop/05-bob-roundtrip.png` |
| Day separator chips | yes | `todo` | |
| Composer + drafts | yes | `wip` | Composer renders and sends (screenshot); draft persistence across switching unverified |
| Send / receive | yes | `done` | Two-instance round-trip, 2 consecutive green runs (`scripts/run-exchange.sh`) |
| Send state: pending / failed / retry | yes | `wip` | |
| **Delivered / read receipts** | **no** | **`dropped`** | Android has none (`ChatScreen.tsx:3`). Do not invent them |
| Reply / quote (`reply1:`) | yes | `done` | Encode+decode verified cross-device; the quote resolves and shows the ORIGINAL text — `tests/interactions.mjs`, screenshot 20/21 |
| Forward | yes | `todo` | |
| Copy | yes | `todo` | |
| Delete for me (local only) | yes | `todo` | Android has no remote unsend |
| **Message editing** | **no** | **`dropped`** | Does not exist in Android |

## E2 — Groups

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Create group (name + description) | yes | `done` | Verified two-instance: shared name renders on both sides — `scripts/run-exchange.sh` with `TEST=tests/group.mjs` |
| Add members | yes | `done` | Alice joins, roster reaches 2 committed, messages flow both ways |
| Group info / roster, pending invites | yes | `wip` | Committed count (2) **and the pending window** both verified — the backend nudges `refreshMembers` after an invite so the in-flight state is visible (`14-bob-pending-invite.png`). Roster UI still to integrate |
| Leave group (remote) | yes | `blocked` | **No core primitive.** `chat_module` 0.2.2 offers only `delete_conversation`, which is local. Next step: upstream request, or a `leave1:` marker convention matching Android |
| Rename group / remove member / wipe | yes | `todo` | Check against the contract before promising |
| Pinned messages + pinned bar (`pin1:`) | yes | `done` | Pin/unpin propagate cross-device; the bar renders above the thread and **tapping it scrolls to the pinned message** and outlines it briefly. Verified on the peer — bar visible, jump lands, highlight set — `tests/interactions.mjs`, screenshot 22 |
| Group avatar | yes | `done` | Group identicon renders in row and header — screenshot `interop-desktop/13-bob-group-roundtrip.png` |
| Group storage opt-out (`gcfg1:`) | yes | `todo` | |
| Desync auto-recovery / re-add request (`readd1:`) | yes | `todo` | Control marker; folded, never a bubble |

## E3 — Contacts & identity

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Contacts list + search | yes | `wip` | Panel renders with search, verified badge and empty states (`41-contacts.png`); contacts are only populated locally so far |
| Add contact by address paste | yes | `done` | `create_conversation` verified end to end against a real peer |
| My address + short label | yes | `done` | Live address read from `chat_module` and rendered; screenshot |
| My address QR card | yes | `wip` | AddressCard renders the identicon badge, full hex and Copy; the QR itself is an honest **placeholder** — no encoder, and a wrong QR would send messages to the wrong identity |
| QR scan | yes | `todo` | Desktop has no rear camera — needs an ADR (webcam / file / screen region) |
| Shared contact card (`addr1:`) | yes | `done` | Share from a contact row into any conversation via the same picker forwarding uses; renders as Android's in-chat card — identicon, the label that travelled, the short hex, Add and View — and jumps into the chat it was sent to (#343). Verified on the peer in `tests/interactions.mjs`, screenshot 27 |
| Display name | yes | `wip` | Wired to `set_installation_name` |
| Custom avatar (`pfp1:` / `pfp1:clear`) | yes | `todo` | Codec decodes it |
| Labels + verified badge | yes | `wip` | A label set from the bubble menu now renames the peer everywhere — bubbles, quoted replies, reaction attribution, group member rows — and mirrors onto the conversation nickname the way Android's LabelModal does. The verified badge is not built |

## E4 — Media & reactions

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Content-marker codec | yes | `wip` | Decode for every marker + encode for reply/reaction/pin/contact-card, verified cross-device. Media encode and malformed-input unit tests still open |
| Photo, inline (`img1:` wire / `img1v:` local row) | yes | `done` | Sent, decoded and rendered on the peer; PNG/JPEG dimensions read from the header (no QtGui) — `tests/media.mjs`, screenshots 30/31 |
| Hosted media (`store2:` current, `store1:` legacy) | yes | `done` | Full Android blob format — Padmé padding, AES-256-GCM, `iv‖ct‖tag`, `POST /data`. Verified BOTH ways incl. reading a blob written by an independent implementation (`tests/hosted-media.mjs`). Needs `PEERS_STORAGE_TOKEN`; without it, disabled and said so |
| GIF | yes | `wip` | Transport works and the bubble animates it (`AnimatedImage`); animation not yet asserted by a test |
| Video | yes | `wip` | Sends with its real mime and always goes hosted (never inline, which would mislabel it as an image); the bubble opens it in the desktop's player — no inline playback, the host has no QtMultimedia |
| Voice notes, 2:00 cap (`voc1:` wire / `voc1v:` local row) | yes | `done` | Records from a real mic via an external tool (ffmpeg/parecord/arecord — the host has no QtMultimedia), measures duration and 40 waveform bars from the PCM, transcodes to mono AAC and renders on the peer — `tests/voice.mjs`, screenshots 24-26. Playback opens in the desktop's player |
| Media viewer (zoom / page / save) | yes | `done` | Android's gestures translated to their desktop equivalents: wheel + double-click zoom, drag pan, arrow keys and chevrons to page every image in the thread, and Save. Swipe-to-dismiss has no desktop equivalent and is not faked — `tests/media.mjs`, screenshot 32 |
| Reactions (`react1:`) | yes | `done` | Pill renders on the peer with count>1 rule; folded so no raw bubble — `tests/interactions.mjs` |
| Location (`loc1:`) | yes | `done` | Send from the composer (lat/lng dialog); the bubble links out to OpenStreetMap and the menu offers Open in maps / Copy coordinates |

## E5 — Settings & security

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Notification settings | yes | `done` | Four toggles wired to `setSetting` — `42-settings.png` |
| Delivery-node setting | yes | `wip` | Shown read-only with a note that it is chosen at core start; changing it is not wired |
| PIN app-lock | yes | `todo` | |
| Duress / wipe PIN | yes | `todo` | Security-sensitive; test on a disposable instance only |
| Lock screen | yes | `todo` | An **overlay**, not a route (`App.tsx:167-168`) |
| Reset identity + data | yes | `todo` | |
| **Light mode** | **no** | **`dropped`** | Android is dark-only; there is no light palette |

## E6 — Identity portability

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Backup export (passphrase) | yes | `todo` | |
| Read a `.peersenc` backup | yes | `done` | Decrypts a **Node-written** envelope (cross-implementation, so drift on either side fails); refuses wrong passphrase, junk and legacy plaintext by name — `tests/backup.mjs` |
| **Adopt the backup identity (same address)** | yes | **`blocked`** | **`chat_module` 0.2.2 exposes no identity-import method** — the whole surface is `get/set_installation_name` + `get_address`, and `init(ChatConfig)` takes only `delivery_preset` and `log_level`. See ADR 0004. Next step: upstream feature request |
| Import history / contacts / nicknames | yes | `todo` | Not blocked — needs only the decryptor |
| About | yes | `todo` | |

## E7 — Shell & layout

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Theme tokens | yes | `done` | `Theme.qml` from `src/theme/colors.ts`; accent `#FF5000` |
| HexAvatar identicon | yes | `done` | **Proven byte-identical** over 8,026 (seed, kind) pairs |
| Lucide icon set | yes | `wip` | Nav-rail + empty-state glyphs render (screenshot). Full set unverified; a Repeater of ShapePath rendered blank until fixed |
| App / sidebar icon | yes | `done` | Generated by the identicon algorithm itself |
| Three-panel shell | n/a | `done` | Loads and renders; screenshot `docs/screenshots/peers-ui-loaded.png` |
| Empty / loading states | yes | `done` | Chats, contacts and settings empty states all render — `40-43` |
| Error toast / strip | yes | `wip` | Android's is persistent with a manual ✕, not auto-dismiss |
| Navigation, deep links, swipe-back | yes | `dropped` | Mobile navigation model; replaced by the three-panel layout |

---

## Deliberately dropped (whole subsystems)

Per the build plan, none of the following is ported:

- **Tor / "private mode" / route-media-over-Tor.** Note the Android toggle is already dead code
  (`TOR_TOGGLE_READY = false`).
- **BLE / Bluetooth mesh** — `NearbyScreen`, BLE stores, BLE identity, fragment transport.
- **MeshCore / LoRa** — `MeshCoreScreen`, `MeshConfigScreen`, mesh mapping, mesh mirroring,
  channel invites, the mesh/BLE avatar ramps, and the `transport` field branching.

`docs/FEATURE-INVENTORY.md` §6 lists every file, store, component and in-screen feature to strip,
so the drop is auditable rather than approximate.
