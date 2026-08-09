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
| Reply / quote | yes | `todo` | Codec decodes `reply1:`; send path not wired |
| Forward | yes | `todo` | |
| Copy | yes | `todo` | |
| Delete for me (local only) | yes | `todo` | Android has no remote unsend |
| **Message editing** | **no** | **`dropped`** | Does not exist in Android |

## E2 — Groups

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Create group (name + description) | yes | `done` | Verified two-instance: shared name renders on both sides — `scripts/run-exchange.sh` with `TEST=tests/group.mjs` |
| Add members | yes | `done` | Alice joins, roster reaches 2 committed, messages flow both ways |
| Group info / roster, pending invites | yes | `wip` | Committed count verified (2). The **pending** state was never observed — the roster only refreshes on `members_changed`/selection, so the invite window is missed. No roster UI yet |
| Leave group (remote) | yes | `blocked` | **No core primitive.** `chat_module` 0.2.2 offers only `delete_conversation`, which is local. Next step: upstream request, or a `leave1:` marker convention matching Android |
| Rename group / remove member / wipe | yes | `todo` | Check against the contract before promising |
| Pinned messages + pinned bar | yes | `todo` | Codec decodes `pin1:` |
| Group avatar | yes | `done` | Group identicon renders in row and header — screenshot `interop-desktop/13-bob-group-roundtrip.png` |
| Group storage opt-out (`gcfg1:`) | yes | `todo` | |
| Desync auto-recovery / re-add request (`readd1:`) | yes | `todo` | Control marker; folded, never a bubble |

## E3 — Contacts & identity

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Contacts list + search | yes | `todo` | Backend stores contacts locally |
| Add contact by address paste | yes | `done` | `create_conversation` verified end to end against a real peer |
| My address + short label | yes | `done` | Live address read from `chat_module` and rendered; screenshot |
| My address QR card | yes | `todo` | |
| QR scan | yes | `todo` | Desktop has no rear camera — needs an ADR (webcam / file / screen region) |
| Shared contact card (`addr1:`) | yes | `todo` | Codec decodes it, including the `peers:addr?label=` form |
| Display name | yes | `wip` | Wired to `set_installation_name` |
| Custom avatar (`pfp1:` / `pfp1:clear`) | yes | `todo` | Codec decodes it |
| Labels + verified badge | yes | `todo` | |

## E4 — Media & reactions

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Content-marker codec | yes | `wip` | **Decode implemented** for every marker, with defensive bounds; encode not yet |
| Photo, inline (`img1:` wire / `img1v:` local row) | yes | `todo` | |
| Hosted media (`store2:` current, `store1:` legacy) | yes | `todo` | Every current Android send emits `store2:` |
| GIF | yes | `todo` | Rides the hosted-media marker |
| Video | yes | `todo` | Rides the hosted-media marker |
| Voice notes, 2:00 cap (`voc1:` wire / `voc1v:` local row) | yes | `todo` | `MAX_RECORDING_MS = 120000` |
| Media viewer (zoom / page / save) | yes | `todo` | |
| Reactions (`react1:`) | yes | `todo` | Codec decodes; `messageKey` implemented |
| Location (`loc1:`) | yes | `todo` | Codec decodes and range-validates |

## E5 — Settings & security

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Notification settings | yes | `todo` | Backend has a JSON settings store |
| Delivery-node setting | yes | `todo` | Maps to `ChatConfig.delivery_preset` |
| PIN app-lock | yes | `todo` | |
| Duress / wipe PIN | yes | `todo` | Security-sensitive; test on a disposable instance only |
| Lock screen | yes | `todo` | An **overlay**, not a route (`App.tsx:167-168`) |
| Reset identity + data | yes | `todo` | |
| **Light mode** | **no** | **`dropped`** | Android is dark-only; there is no light palette |

## E6 — Identity portability

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Backup export (passphrase) | yes | `todo` | |
| Read a `.peersenc` backup | yes | `todo` | Format fully specified in `docs/BACKUP-FORMAT.md` |
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
| Empty / loading states | yes | `done` | Both empty states render; screenshot |
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
