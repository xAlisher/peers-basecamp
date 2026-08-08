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
| Conversation list + rows | yes | `wip` | Row component + JSON view-model built; view does not load (`HALT.md`) |
| Conversation row menu (open/group info/delete) | yes | `todo` | Android has no archive/mute/pin-conversation |
| Chat thread + bubbles | yes | `wip` | `MessageBubble` built to spec; unverified |
| Day separator chips | yes | `todo` | |
| Composer + drafts | yes | `wip` | Draft persistence in the backend; UI unverified |
| Send / receive | yes | `wip` | Backend wired to `send_message` + events |
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
| Create group (name + description) | yes | `wip` | Backend wired to `create_group_conversation` |
| Add members | yes | `wip` | Backend wired to `add_group_member` |
| Group info / roster, pending invites | yes | `wip` | Roster distinguishes committed vs pending |
| Leave group (remote) | yes | `blocked` | **No core primitive.** `chat_module` 0.2.2 offers only `delete_conversation`, which is local. Next step: upstream request, or a `leave1:` marker convention matching Android |
| Rename group / remove member / wipe | yes | `todo` | Check against the contract before promising |
| Pinned messages + pinned bar | yes | `todo` | Codec decodes `pin1:` |
| Group avatar | yes | `wip` | `HexAvatar` with `kind: "group"`, shared convo id as seed |
| Group storage opt-out (`gcfg1:`) | yes | `todo` | |
| Desync auto-recovery / re-add request (`readd1:`) | yes | `todo` | Control marker; folded, never a bubble |

## E3 — Contacts & identity

| Feature | Android | Basecamp | Notes |
|---|---|---|---|
| Contacts list + search | yes | `todo` | Backend stores contacts locally |
| Add contact by address paste | yes | `wip` | Backend wired to `create_conversation` |
| My address + short label | yes | `wip` | From `get_address()` |
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
| Lucide icon set | yes | `wip` | Vector paths, no `MultiEffect` (ADR 0005); unverified on screen |
| App / sidebar icon | yes | `done` | Generated by the identicon algorithm itself |
| Three-panel shell | n/a | `wip` | Desktop-only; **does not load** (`HALT.md`) |
| Empty / loading states | yes | `wip` | |
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
