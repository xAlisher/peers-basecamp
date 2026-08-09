# VIEW-MODEL — the JSON contract between the C++ backend and QML

List data crosses the QtRO boundary as **JSON strings**, not remoted models (ADR 0006). Each list
lives in one `PROP(QString …Json)` on `PeersUiBackend` and is rebuilt wholesale by the backend; QML
parses it and binds a `Repeater`/`ListView` to the resulting array.

```qml
// PeersView.qml — the only way these props are consumed
readonly property var messages: JSON.parse(backend.messagesJson)
```

Source of truth for everything below:

| What | Where |
|------|-------|
| Which props carry JSON | `plugins/peers_ui/src/peers_ui.rep` |
| Who builds each array | `plugins/peers_ui/src/PeersUiBackend.cpp` — `refreshConversations`, `loadMessages`, `refreshMembers`, `refreshContacts` |
| Per-kind message fields | `plugins/peers_ui/src/ContentMarkers.cpp` — `decodeToJson` |
| The marker grammar itself | `docs/CONTENT-MARKERS.md`, ADR 0002 |

The JSON-bearing props are `conversationsJson`, `messagesJson`, `membersJson`, `contactsJson`,
`currentPinnedJson` and `settingsJson` (settings keys are documented separately in
`docs/SETTINGS.md`). `errors` is a `QVariantList`, not a JSON string.

---

## The invariant: QML never sees a raw marker string

Everything richer than plain text rides inside the message body as a marker-prefixed payload
(`img1:`, `reply1:`, `react1:` …), because `chat_module` 0.2.2 carries only `content: tstr`.

**The codec runs entirely in the backend.** `ContentMarkers::decodeToJson()` is called once per
message in `loadMessages()`, and what lands in `messagesJson` is the *decoded object*. QML must
never parse a marker, never test a prefix, and never fall back to printing `msg.content` — there is
no `content` field.

The decoder never fails open. An unrecognised prefix, a malformed payload, an oversized body — each
degrades to `kind: "unknown"` with human-readable placeholder text (`[unsupported message]`,
`[unreadable message]`, `[unreadable location]`, `[unreadable contact]`, `[oversized message]`).
This matters for forward compatibility: Peers Android will grow markers this build does not know,
and a user must never see wire text in a bubble because of it.

---

## `conversationsJson` — array, one row per conversation

Built by `refreshConversations()` from `chat_module.list_conversations()`.

| Field | Type | Meaning |
|-------|------|---------|
| `convoId` | string | Core conversation id. The selection key — pass it to `selectConversation()`. |
| `displayName` | string | Never empty. Group's shared `name` → local `nickname` → `shortLabel(convoId)` (first 8 hex chars). |
| `isGroup` | bool | `kind == "group"`. |
| `description` | string | Group description; `""` for a direct chat. |
| `nickname` | string | Local-only alias set via `setConversationNickname()`. May be `""`. |
| `messageCount` | number | Core's `message_count`. |
| `lastActivityMs` | number | Unix ms of the last activity. |
| `preview` | string | **Already decoded** — `previewText()` of the raw last body, so a photo reads `📷 Photo`, not `img1:image/png:…`. |
| `avatarSeed` | string | Identicon seed = `convoId` (matches Peers Android). Feed to `HexAvatar.seed`. |
| `avatarKind` | string | `"group"` or `"contact"` — picks the avatar shape. |

Row order is whatever the core returns; the backend does not re-sort. Treat "newest activity first"
as the core's contract, and sort on `lastActivityMs` in QML if you need the guarantee.

---

## `messagesJson` — array, one row per **renderable** message, oldest first

Built by `loadMessages(convoId)` in two passes over `chat_module.get_messages()`:

1. **Fold pass** — collects control markers (reactions, pins) and indexes every renderable message
   by `key`, so a reply can resolve the text it quotes and a reaction can land on a message that
   arrives *after* it (which happens on catch-up).
2. **Render pass** — emits one row per non-folded message: `decodeToJson(content)` plus the
   envelope fields below, plus the folded data attached back onto its target.

### Envelope — present on every row

| Field | Type | Meaning |
|-------|------|---------|
| `key` | string | The cross-device message identity. See **key** below. |
| `kind` | string | One of `text`, `photo`, `voice`, `media`, `location`, `reply`, `contact`, `unknown`. |
| `folded` | bool | Always `false` in this array. See **folded** below. |
| `text` | string | The one-line human rendering for this kind. Always present, never a marker. |
| `fromSelf` | bool | This account sent it. Drives bubble side and colour. |
| `timestampMs` | number | Unix ms. |
| `sender` | string | Peer address; `""` for our own messages. |
| `senderLabel` | string | `shortLabel(sender)` (8 hex chars), or `"Peer"` when the sender is unknown. |

### Conditional envelope fields

| Field | Type | Present when |
|-------|------|--------------|
| `reactions` | array | The message has ≥1 aggregated reaction. See **reactions** below. |
| `pinned` | `true` | This row is the conversation's pinned message. Absent otherwise — test `=== true`. |
| `quotedText`, `quotedSender` | string | `kind === "reply"` only. See **quotedText/quotedSender** below. |

### Per-kind fields — what each `kind` adds on top of the envelope

| `kind` | Marker | Adds | Notes |
|--------|--------|------|-------|
| `text` | *(none)* | — | `text` is the raw body verbatim. |
| `photo` | `img1:` / `img1v:` | `mime`, `width`, `height`, `hasData`, `dataUri`? | `text` = `"📷 Photo"`. `dataUri` is a ready-to-render `data:<mime>;base64,…` — bind it straight to `Image.source`. It is **omitted** unless the payload is non-empty, within the inline cap, and `mime` starts with `image/`; a peer may also have sent an on-disk path instead of base64, so still handle `Image.Error`. `width`/`height` may be `0` — fall back to the image's natural size. |
| `voice` | `voc1:` / `voc1v:` | `mime`, `durationMs`, `waveform`, `hasData` | `text` = `"🎤 Voice message"`. `waveform` is an int array, **bounded to 256 samples** (it drives a Repeater). `durationMs` may be `0`. |
| `media` | `store1:` / `store2:` | `cid`, `mime`, `width`, `height`, `caption` | Hosted media. `text` = the caption, or `"Video"`/`"Media"` when there is none. **The decryption key is deliberately not surfaced to QML.** Fetching hosted media is not wired up yet — render the caption/placeholder. |
| `location` | `loc1:` | `lat`, `lng` | `text` = `"📍 Location"`. Coordinates are range-checked; out-of-range flips the row to `kind: "unknown"` with `[unreadable location]` and **no** `lat`/`lng`. |
| `reply` | `reply1:` | `replyToKey`, `innerKind`, `quotedText`, `quotedSender` | `text` = the reply's **own** body, itself decoded (a reply may quote a photo and be a photo). `innerKind` is the kind of that inner body. |
| `contact` | `addr1:` | `address`, `label` | `text` = `"Contact: <label>"`, or `"Shared a contact"` when unlabelled. `address` is validated hex (≤128 chars) before it is emitted; a non-hex address flips the row to `kind: "unknown"` + `[unreadable contact]`. Tap → `createConversation(address)`. |
| `unknown` | any unimplemented / malformed | — | `text` is one of the bracketed placeholders. Render it as a plain, visually muted bubble. |

The `📷` / `🎤` / `📍` above are literal characters *inside the backend's string*
(`ContentMarkers.cpp` — `decodeToJson`), not an icon slot. Render `text` verbatim and never add an
emoji of your own beside it: every icon in this UI is a vector `PeersIcon`.

---

### `key` — the cross-device message identity

The wire carries no message id, so Peers derives one:

> **Two-word FNV-1a over `"<author> <body>"`, rendered as exactly 16 lowercase hex characters.**

`ContentMarkers::messageKey()` iterates UTF-16 code units with 32-bit wrapping multiplies and must
match Peers Android's `src/messages/reactions.ts` byte for byte — otherwise reactions and pins land
on the wrong message across devices.

Two things to get right:

- **`author`** is this account's own address for `fromSelf` messages (the wire omits the sender on
  our own rows), otherwise the peer's `sender`.
- **`body` is the RAW stored content, not the decoded text.** For a reply that means the key is
  hashed over the whole `"reply1:<targetKey>:<body>"` string. Hashing the unwrapped text instead
  would silently break cross-device reactions on replies.

`key` is what QML passes to `reactToMessage()`, `unreactToMessage()` and `pinMessage()` — it is the
`messageId` argument in the `.rep`.

Known and accepted collision: the same author sending an identical body twice shares a key, so a
reaction lands on both.

---

### `folded` — control markers that must never render as a bubble

Six kinds are **folded**: `reaction`, `pin`, `avatar`, `leave`, `groupConfig`, `readd`. They are
messages on the wire like any other, but they are instructions, not content.

`loadMessages()` drops every folded message from the array — so in practice **every row in
`messagesJson` has `folded: false`**, and `currentPinnedJson` likewise. Their effects are folded back
into the rows they target (`reactions`, `pinned`) or into other props.

QML should still guard defensively — `visible: modelData.folded !== true`, as `PeersView.qml` does.
The cost of the check is nothing; the cost of a `pin1:+a1b2…` bubble appearing in a user's thread is
a bug report.

The `folded` flag is set from the marker class *before* payload validation, so a malformed control
marker can carry `kind: "unknown"` with `folded: true`. That is exactly why the flag, not the kind,
is the render gate.

---

### `reactions` — aggregated, attached to the target message

Each `react1:<+|-><emoji>:<key>` message is folded into a running tally keyed by its `targetKey`.
Adds increment, removes decrement, and an emoji whose count reaches zero disappears. The result is
attached to the row whose `key` matches:

```json
"reactions": [ { "emoji": "👍", "count": 3, "mine": true } ]
```

| Field | Type | Meaning |
|-------|------|---------|
| `emoji` | string | The reaction character (≤16 chars, colons stripped by the encoder). |
| `count` | number | Aggregate across all participants. Always ≥1 — zero-count entries are removed. |
| `mine` | bool | This account is one of the reactors. Drives the pill's active state and picks `reactToMessage` vs `unreactToMessage` on tap. |

The key is absent entirely when there are no reactions — default it (`msg.reactions !== undefined ? msg.reactions : []`).

Emoji here are **content the user picked**, not icons. Every actual icon in the UI is a vector
`PeersIcon`.

---

### `quotedText` / `quotedSender` — resolved by the backend, from the target key

A `reply1:` marker carries only the **key** of the message it answers, plus the reply's own body. It
does **not** carry the quoted text.

So the backend's first pass builds `key → previewText(body)` and `key → senderLabel` maps over the
whole conversation, and the render pass looks the reply's `replyToKey` up in them:

| Field | Type | Meaning |
|-------|------|---------|
| `quotedText` | string | The text of the message being **answered**. Falls back to `"Original message unavailable"` when the target is not in this conversation's history (deleted, or sent before we joined). |
| `quotedSender` | string | `"You"` for our own message, else the sender's short label. `""` when the target is unresolved. |

> **This shipped a bug once (2026-08-09):** the quote box echoed the reply's own text, because
> `text` and `quotedText` were confused. `text` is what the reply *says*; `quotedText` is what it
> *answers*. The quote box binds `quotedText`, never `text`.

---

## `membersJson` — array, roster of the current conversation

Built by `refreshMembers()` from `chat_module.list_group_members(currentConversationId)`. Also sets
the scalar props `memberCount` (committed only), `pendingMemberCount`, and `currentPeerAddress` (the
other party in a direct chat).

| Field | Type | Meaning |
|-------|------|---------|
| `address` | string | Member address. **May be `""`** — the roster's "no confirmed account yet" signal. |
| `label` | string | `shortLabel(address)`, or the literal `"unknown account"` when the address is empty. |
| `isSelf` | bool | This row is us. |
| `pending` | bool | An invite the group has not committed yet. Render distinctly (dimmed / "invited"); it is not yet a member and is **not** counted in `memberCount`. |
| `avatarSeed` | string | `= address`. Feed to `HexAvatar.seed`. |

Rows with an empty `address` are deliberately kept, not dropped — a real participant must not vanish
from the roster silently.

The `.rep` documents committed-first-then-pending ordering; the backend passes the core's order
through unchanged, so sort in QML if the grouping matters visually.

---

## `contactsJson` — array, the local address book

Built by `refreshContacts()` from the persisted `m_contacts` map (`address → object`). It is purely
local state — nothing on the wire populates it.

| Field | Type | Meaning |
|-------|------|---------|
| `address` | string | The map key, injected into every row. Always present. |
| `label` | string | User-set label via `setContactLabel()`; defaults to `shortLabel(address)` when unset. Always present. |

The row is the stored object with `address` (and a defaulted `label`) merged in, so any other key
ever written into a contact object appears here verbatim. The `.rep` comment advertises
`verified`, `avatar` and `lastSeen`; **no current code path writes them**, so QML must treat them as
optional and absent rather than binding to them unguarded.

---

## `currentPinnedJson` — a single object, `{}` when nothing is pinned

Not an array. It is either `{}` or **a full copy of the pinned message row** — identical shape to a
`messagesJson` row, including `key`, `kind`, `text` and `pinned: true`.

Pin state is derived by folding `pin1:<+|->` markers in conversation order: last add wins, and a
matching remove clears it. The same row also appears in `messagesJson` carrying `pinned: true`, so
the pinned banner and the in-thread bubble stay in sync.

`unpinMessage()` reads `key` back out of this object to address the unpin, so the banner must be
driven by this prop and not by a locally cached row.

Guard for emptiness with `Object.keys(pinned).length > 0` or `pinned.key !== undefined`; `{}` parses
to a valid object, not to `null`.

> **Hazard, worth fixing before relying on the pin banner:** `selectConversation()` calls
> `loadMessages()` (which sets `currentPinnedJson` correctly from the folded markers) and then
> `syncCurrentConversationMeta()`, which **overwrites it** from the persisted `m_pinnedByConvo` map —
> and nothing in `PeersUiBackend.cpp` ever inserts into that map. On selection the prop therefore
> collapses back to `{}`, and `unpinMessage()` reports "Nothing is pinned in this conversation."
> (`PeersUiBackend.cpp` — `loadMessages` → `setCurrentPinnedJson`, then `syncCurrentConversationMeta`
> → `setCurrentPinnedJson(m_pinnedByConvo…)`.)

---

## Notes for the QML side

- **Rebuilds are wholesale.** Every refresh replaces the entire string; there is no incremental
  row signal. Bind `JSON.parse(...)` to a `readonly property var` and let the property change drive
  the view.
- **Parse once per change, not per delegate.** `JSON.parse` inside a delegate binding re-parses the
  whole array for every row.
- **Numbers are JS numbers.** `timestampMs` and `lastActivityMs` cross as JSON numbers (doubles);
  they are exact for Unix-ms magnitudes.
- **Optional keys are genuinely absent**, not `null` — test with `!== undefined`, and default in the
  delegate's property declarations rather than at each use site.
- **`loadedConversationId` is the loaded-vs-selected gate.** It is cleared on selection and set only
  after `loadMessages()` succeeds, so `loadedConversationId !== currentConversationId` means
  "loading", and lets the view avoid painting the previous thread's rows under a new header.
- **Paths are plain filesystem paths.** `sendMedia()` takes a path, never a `file://` URL — convert
  with `url.toLocalFile()` first.
