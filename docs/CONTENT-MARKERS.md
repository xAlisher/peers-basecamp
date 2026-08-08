# Peers — rich content encoded inside the plain-text chat body

Ground truth extracted from `<logos-chat-android>` by reading source.
Every value below is cited as `path:line`. Paths are repo-relative.

The chat core (`libchat` via `NodeBridge.chatSendMessage`) carries **one UTF-8 `content` string
per message**. Peers layers everything else — media, reactions, replies, pins, avatars, contact
cards, group control — as **marker-prefixed payloads inside that string**. There is no side
channel, no attachment field, no message id on the wire.

---

## 0. Ground rules that apply to every marker

| Rule | Source |
|---|---|
| A marker is `<prefix><payload>`; prefix always ends in `:` (except the BLE flood frame `bf1`). | all of `src/messages/*.ts`, `src/native/*.ts` |
| Detection is always `String.startsWith(PREFIX)` — never regex-anchored, never trimmed. | e.g. `src/messages/media.ts:46-48`, `src/messages/pins.ts:24-26` |
| Field separator inside a header is `:`. Fields are ordered so that only the LAST field may contain `:`. | `src/messages/media.ts:10-13`, `src/messages/reply.ts:22` |
| Where a payload can contain arbitrary bytes (base64 blob, file path), the header is terminated by **`␟` = U+241F SYMBOL FOR UNIT SEPARATOR** (a printable glyph, not the C0 0x1F control char). | `src/native/imageMsg.ts:17`, `src/native/voiceMsg.ts:11`, `src/native/relay.ts:17`, `src/native/bleFrag.ts:23` |
| Every `parseX` returns `null` on a non-marker or malformed input; callers then fall back to plain-text rendering. | all parsers |
| **Unrecognised marker → rendered verbatim as a normal text bubble.** There is no catch-all "unknown marker" branch anywhere. This is stated explicitly as the interop design: "Non-bridge / official-app peers that don't understand it just render the raw text — no crash — exactly like the `lmi:` channel invite" (`src/native/relay.ts:13-14`), and again `src/native/bleFrag.ts:16-17`. |
| The regression that pins this behaviour: `readd1:` was registered in the native guards but not the JS render chain, so it "rendered as a raw `readd1:<hex>` bubble on the sender AND every recipient". | `src/messages/markers.ts:6-12`, `__tests__/markers.test.ts:1-9` |

### 0.1 Two classes of marker

**Folded control markers** — persisted, synced, reloaded like any message, but **never** rendered
as a bubble. The canonical list is one array:

```ts
// src/messages/markers.ts:21-28
export const FOLDED_MARKERS: ReadonlyArray<(s: string) => boolean> = [
  isReactionContent, // react1: → folded into the reaction chips
  isPinContent,      // pin1:   → folded into the pinned bar
  isLeaveContent,    // leave1: → folded into a "left" system line
  isPfpContent,      // pfp1:   → folded into the avatar
  isGroupCfgContent, // gcfg1:  → folded into the storage toggle (#344)
  isReaddContent,    // readd1: → folded into the creator's auto re-add (#350)
];
export function isFoldedMarker(text: string): boolean   // markers.ts:31-33
```

Call sites (only two, both in ChatScreen): `src/screens/ChatScreen.tsx:1705` (exclude from the
reply-target index) and `src/screens/ChatScreen.tsx:1820` (exclude from the rendered row list).

**Visible content markers** — real bubbles, just rendered specially: `store1:`/`store2:`,
`img1:`/`img1v:`, `voc1:`/`voc1v:`, `loc1:`, `reply1:`, `addr1:`.

### 0.2 The cross-device message key (the "message id" Peers does not have)

The wire preserves neither send-time nor a message id, and `msg_pk` is per-device. So the only
shared identity is **(author, body)**, hashed:

```ts
// src/messages/reactions.ts:14-32
const R1 = 0x811c9dc5;
const PRIME = 0x01000193;

function hash16(s: string): string {              // two-word FNV-1a → 16 lowercase hex chars
  let h1 = R1 >>> 0;
  let h2 = (R1 ^ 0x9e3779b9) >>> 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, PRIME) >>> 0;
    h2 = Math.imul(h2 ^ (c + 0x9e), PRIME) >>> 0;
  }
  return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
}

export function messageKey(author: string, body: string): string {
  return hash16(`${author} ${body}`);            // note: author + SPACE + body
}
```

Exact semantics a port must reproduce:
- iteration is over **UTF-16 code units** (`charCodeAt`), not code points or UTF-8 bytes;
- `Math.imul` is 32-bit signed multiply, result coerced with `>>> 0`;
- output is exactly 16 lowercase hex chars (8 + 8, each zero-padded).

`author` is resolved as: `msg.direction === 'out' ? myAddress : (msg.senderAccount ?? peerAddress) ?? ''`
(`src/screens/ChatScreen.tsx:1679-1681`). The body used is the **raw stored content**, i.e. for a
reply it is the whole `reply1:…` string (`src/screens/ChatScreen.tsx:2066`).

Known collision, accepted in v1: the same author sending an identical body twice shares a key, so
a reaction lands on both (`src/messages/reactions.ts:8-12`).

---

## 1. `store1:` / `store2:` — Logos-Storage hosted media (GIF, video, HQ photo, avatar blob)

**Files:** `src/messages/media.ts`, `android/app/src/main/java/com/logoschat/StorageModule.kt`,
`android/app/src/main/java/com/logoschat/StorageRef.kt`,
`android/app/src/main/java/com/logoschat/MediaPadding.kt`, `src/native/mediaCache.ts`.

### Grammar

```
store1:<cid>:<key>:<mime>:<w>:<h>[:<cap>]      # legacy, ciphertext NOT size-padded
store2:<cid>:<key>:<mime>:<w>:<h>[:<cap>]      # current, ciphertext IS size-padded
```

Constants: `MEDIA_PREFIX = 'store1:'` (`src/messages/media.ts:15`),
`MEDIA_PREFIX_V2 = 'store2:'` (`src/messages/media.ts:21`).

Field order and rationale (`src/messages/media.ts:10-13`): cid, key(base64), mime, width, height,
[cap] — none of those contain `:` (CID is base58, base64 has no `:`, mimes have no `:`, cap is hex),
so a plain `:` split is unambiguous.

| Field | Meaning | Source |
|---|---|---|
| `cid` | Logos Storage (Codex) content id — hash of the **ciphertext** | `media.ts:25` |
| `key` | base64 (NO_WRAP, standard alphabet) AES-256-GCM key, 32 bytes; travels E2E, never sent to the node | `media.ts:27`, `StorageModule.kt:148`, `StorageRef.kt:24,47-53` |
| `mime` | e.g. `image/gif`, `video/mp4`, `image/jpeg` | `media.ts:29` |
| `width`,`height` | integers, px | `media.ts:30-31` |
| `cap` | optional trailing field — per-blob hex HMAC fetch capability issued by the capgate proxy on upload; legacy 5-field markers omit it | `media.ts:32-33`, `StorageModule.kt:138-144` |

**There is NO caption/filename/duration/size field.** (`MediaViewer` has a `captionFor` prop —
`src/components/MediaViewer.tsx:57` — but nothing in the app ever passes it; grep for `captionFor`
outside `MediaViewer.tsx` returns nothing.)

### Encode

```ts
// src/messages/media.ts:40-44
export function encodeMedia(m: MediaRef): string {
  const prefix = m.padded === false ? MEDIA_PREFIX : MEDIA_PREFIX_V2;   // default = store2
  const head = `${prefix}${m.cid}:${m.key}:${m.mime}:${m.width}:${m.height}`;
  return m.cap ? `${head}:${m.cap}` : head;
}
```

Note the polarity: `padded` must be **explicitly `false`** to emit `store1:`; `undefined` emits
`store2:`. New sends are always `store2:`.

Test vectors (`__tests__/media.test.ts:9,38`):
```
store2:zDvZRwCID:a2V5YjY0:image/gif:320:240
store2:zDvZRwCID:a2V5YjY0:image/gif:320:240:a2a008e66058cdd57e08ace8f0eb57bd
```

### Parse + validation (#388 — peer-controlled fields flow into a URL and a file path)

```ts
// src/messages/media.ts:53-62
const MAX_CID_LEN = 128, MAX_CAP_LEN = 256, MAX_MIME_LEN = 128, MAX_DIM = 100_000;
const CID_RE  = /^[A-Za-z0-9_~-]{1,128}$/;
const CAP_RE  = /^[A-Fa-f0-9]{1,256}$/;
const KEY_RE  = /^[A-Za-z0-9+/=]{4,64}$/;
const MIME_RE = /^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}\/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]{0,63}$/;
```

`parseMedia` (`src/messages/media.ts:65-92`): split remainder on `:`; **exactly 5 or 6 parts** else
null; width/height must be integers in `1..100000`; every regex must match; `cap` only validated
when present. Returns `{cid, key, mime, width, height, padded: v2, ...(cap ? {cap} : {})}`.

The native side re-validates before any network/file use (defence in depth):
`StorageRef.validCid/validCap/validMime/validDim/validKeyB64` (`StorageRef.kt:38-53`), enforced in
`StorageModule.downloadDecrypt` (`StorageModule.kt:164-166`). `validKeyB64` additionally requires
the key to decode to **exactly 32 bytes** (`KEY_BYTES`, `StorageRef.kt:24,48-53`) — the JS regex only
bounds length 4..64. Note `validCap` also accepts the **empty** string (legacy capless markers,
`StorageRef.kt:41`). Also: only `validCid`/`validKeyB64`/`validCap` are actually called from
`downloadDecrypt`; `validMime`/`validDim` exist and are unit-tested (`StorageRefTest.kt:66-76`) but
have no production call site — mime and dimensions are validated **only** in JS (`parseMedia`).

### Blob wire format (what actually lives at the CID)

Upload (`StorageModule.uploadEncrypted`, `StorageModule.kt:96-155`):

1. `plain = MediaPadding.pad(fileBytes)` — always (`StorageModule.kt:102`).
2. fresh random 32-byte AES key + 12-byte IV (`IV_LEN = 12`, `TAG_BITS = 128`, `StorageModule.kt:39-40,104-105`).
3. `ct = AES/GCM/NoPadding(plain)`; `blob = iv || ct(+tag)` (`StorageModule.kt:106-109`).
4. `POST <STORAGE_BASE>/data`, `Authorization: Bearer <STORAGE_TOKEN>`,
   `Content-Type: application/octet-stream`, fixed-length streaming in 64 KiB chunks
   (`StorageModule.kt:111-132`).
5. Response body is `"<cid>:<cap>"` (split on the **first** `:`; no `:` ⇒ cap = `""`)
   (`StorageModule.kt:138-144`).
6. Resolves `{cid, key: base64(NO_WRAP), cap}` (`StorageModule.kt:146-150`).

Padmé size padding (`MediaPadding.kt`):

```
padded plaintext = [4-byte BE realLen][data][zero pad → Padmé bucket]      // MediaPadding.kt:5-9,29-40
HEADER = 4                                                                 // MediaPadding.kt:12

padmeBucket(l):                                                            // MediaPadding.kt:19-27
  if (l < 2) return 2
  e = 63 - numberOfLeadingZeros(l)              // floor(log2 l)
  s = (63 - numberOfLeadingZeros(e)) + 1        // floor(log2 e) + 1
  lastBits = e - s
  if (lastBits <= 0) return l
  mask = (1 << lastBits) - 1
  return (l + mask) & ~mask
```

`pad()` buckets `HEADER + realLen`; `strip()` throws on `padded.size < HEADER` and rejects
`realLen < 0 || HEADER + realLen > padded.size` (`MediaPadding.kt:43-54`).

Download (`StorageModule.downloadDecrypt`, `StorageModule.kt:158-236`):
- cache file = `cacheDir/media/<SHA-256(cid) as lowercase hex>` — never the raw CID
  (`StorageRef.cacheName`, `StorageRef.kt:60-63`; used at `StorageModule.kt:169-170`); an existing
  non-empty cache file short-circuits the whole fetch (`StorageModule.kt:171-174`);
- URL = `buildDataUrl(base, cid, cap)` → `<base>/data/<urlenc cid>` plus `?cap=<urlenc cap>` when
  cap is non-empty (`StorageRef.kt:71-79`); the GET also carries
  `Authorization: Bearer <STORAGE_TOKEN>` (`StorageModule.kt:183`);
- `instanceFollowRedirects = false`; a 3xx throws; `text/html` or `application/json` content-type
  throws; an oversized `Content-Length` is rejected up front and the read is aborted past
  `MAX_CIPHERTEXT_BYTES = 100 MiB` (`StorageRef.kt:28`, `StorageModule.kt:180-215`); a blob
  `<= IV_LEN` throws (`StorageModule.kt:218`);
- decrypt `iv = blob[0..12)`, `ct = blob[12..]`, then `if (padded) MediaPadding.strip(...)`
  (`StorageModule.kt:218-228`).

Both upload and download open their connection through `openConn` (`StorageModule.kt:56-71`), which
routes via a local **Tor SOCKS5** proxy when Private mode is on and throws rather than silently
falling back to a direct connection. `padded` is a parameter of the native `downloadDecrypt`
call — it comes from the JS-parsed marker (`store2` ⇒ true), not from the blob.

### Sender production paths

| Content | Path | Marker emitted |
|---|---|---|
| GIF | `chatStore.sendGif` — `pickRawMedia(8_000_000, 'gif')` → `uploadEncrypted` → `encodeMedia` → `send()` | `src/stores/chatStore.ts:1015-1049` |
| Video | `stageVideo` (pick, preview poster) → `sendStagedVideo`: `VideoTranscoder.transcode` → `uploadEncrypted` → `encodeMedia({mime:'video/mp4', …})` | `src/stores/chatStore.ts:1125-1141`, `1145-1189` |
| Photo, **HQ** | `sendStagedImages(convoPk, images, hq=true)` — original saved, uploaded, `encodeMedia` | `src/stores/chatStore.ts:1240-1263` |
| Photo, standard | same function, `hq=false` — downscaled to 1024px/120 KB and sent **inline as `img1:`** instead | `src/stores/chatStore.ts:1264-1276` |
| Avatar blob | `setAvatar` — `pickImage(256, 50_000)` → upload → `encodePfp(ref)` | `src/stores/chatStore.ts:1054-1103` |

Note the HQ/standard split is decided at **send** time, not at attach time — the original is always
persisted first (`saveBase64Jpeg`) so toggling HQ after attaching still works (`chatStore.ts:1247-1250`).

Media is refused on mesh transports: `'gifs are not supported on mesh'` (`chatStore.ts:1018`),
`'video is not supported on mesh'` (`1128`), `'images are not supported on mesh'`
(`973`, `1196`, `1219`), `'voice notes are not supported on mesh'` (`1324`).

### Receiver / render

`useMediaBlob(ref)` (`src/native/mediaCache.ts:67-105`) — one shared in-flight promise per **cid**,
`MAX_CONCURRENT = 2` distinct decrypts (`mediaCache.ts:20`), memoised `pathByCid`. States:
`idle | loading | ready{path} | error | expired` (`mediaCache.ts:59-65`). **`expired`** is set when
the error message matches `/\b404\b/` — the node evicted the blob by retention
(`mediaCache.ts:95-97`).

Bubble render (`src/screens/ChatScreen.tsx:399-403, 530-547`): while loading → spinner; on
`expired` → text `media expired`; on `error` → `media unavailable`; otherwise `mediaLabel(raw)`.
Dimensions come from `fitImage(mediaRef.width, mediaRef.height)` (`ChatScreen.tsx:404`).

`mediaLabel` (`src/messages/media.ts:95-101`): `video/*` → `Video`; `image/gif` → `GIF`; anything
else → `Media`; a non-marker returns the string unchanged.

`classifyMedia` for the media pager (`src/media/mediaList.ts:21-31`): `img1:`/`img1v:` → `photo`;
`store*` with `video/*` → `video`; `image/gif` or `*/gif` → `gif`; else → `photo`; malformed → null.

Storage opt-out: in a group with `storageOff === true`, a media bubble renders a placeholder and
`useMediaBlob` is passed `null` so **no Storage request ever fires** (`ChatScreen.tsx:400-403`).

---

## 2. `img1:` / `img1v:` — inline photo

**File:** `src/native/imageMsg.ts`; native send `LogosChatModule.sendImageTo`, native receive
`ChatRepo.maybeStoreInboundImage`.

```
WIRE  (transport): img1:<mime>:<w>:<h>␟<base64>          // imageMsg.ts:8, 26-28
LOCAL (DB row):    img1v:<mime>:<w>:<h>␟<absoluteFilePath>  // imageMsg.ts:9, 31-33
```

`IMG_WIRE_PREFIX = 'img1:'`, `IMG_LOCAL_PREFIX = 'img1v:'`, `SEP = '␟'` (`imageMsg.ts:15-17`).

Design (`imageMsg.ts:1-13`): images ride the UTF-8 text pipe as base64 because "the lib's inbound
path is binary-lossy but ASCII survives"; following Status's model the image is **downscaled to fit
ONE message and never chunked — there is no reassembly**.

Parse (`imageMsg.ts:35-55`): find the FIRST `␟`; header = text between prefix and separator; split
the header from the **right** on the last two `:` so a mime containing `:` cannot break w/h;
`parseInt` base 10; reject empty mime, non-finite dims, empty payload.

Send (`LogosChatModule.kt:671-719`): `header = "$mime:$width:$height"`; save base64 →
`ImageFiles.saveBase64` (content-addressed `filesDir/chat-images/<sha256hex>.jpg`,
`ImageFiles.kt:19-32`); record local row `img1v:$header␟$localPath` via `ChatRepo.recordOutgoing`
(`LogosChatModule.kt:704-706`); transmit `img1:$header␟$base64` as UTF-8 bytes
(`LogosChatModule.kt:707-709`).

Receive (`ChatRepo.maybeStoreInboundImage`, `ChatRepo.kt:375-397`): if content starts with `img1:`,
find `␟`, decode base64, write via `ImageFiles.saveBase64`, and **rewrite the persisted content** to
`img1v:<header>␟<path>`. Any decode/save failure returns the raw string unchanged so a malformed
blob can never sink delivery (`ChatRepo.kt:393-396`). Called at `ChatRepo.kt:430` before insert.

Render: `parseImageLocal(raw)` → `<Image source={{uri: 'file://' + path}}>` sized by
`fitImage(meta.width, meta.height)`, `borderRadius: radii.card - 2` (`ChatScreen.tsx:394, 397,
550-559`).

Album: one message per image. Two separate caps, both 10: the picker asks for at most
`MAX_ALBUM = 10` (`chatStore.ts:118`, used at `chatStore.ts:1208`) and the composer clamps the
staged set to `MAX_STAGED_IMAGES = 10` (`ChatScreen.tsx:169, 1556, 1563`).

---

## 3. `voc1:` / `voc1v:` — voice note

**File:** `src/native/voiceMsg.ts`; native send `LogosChatModule.sendVoiceTo`.

```
WIRE  : voc1:<mime>:<durMs>:<w,w,…>␟<base64>              // voiceMsg.ts:5, 23-25
LOCAL : voc1v:<mime>:<durMs>:<w,w,…>␟<absoluteFilePath>   // voiceMsg.ts:6, 27-29
```

`VOICE_WIRE_PREFIX = 'voc1:'`, `VOICE_LOCAL_PREFIX = 'voc1v:'`, `SEP = '␟'` (`voiceMsg.ts:9-11`).

- `durMs` — integer milliseconds.
- waveform — **compact CSV of 0..100 amplitude samples** for the bubble UI (`voiceMsg.ts:7`);
  encoded as `waveform.join(',')` (`voiceMsg.ts:20`); an empty CSV yields `[]` (`voiceMsg.ts:48-50`).

Parse (`voiceMsg.ts:31-53`): first `␟` splits header/payload; header split on the **first two** `:`
(mime has no `:`); non-finite CSV entries are filtered out; reject empty mime, non-finite duration,
empty payload.

Send (`LogosChatModule.kt:726-774`): `header = "$mime:$durationMs:$waveformCsv"`; bytes saved via
`BlobFiles.save(ctx, base64, "chat-audio", "m4a")` → `filesDir/chat-audio/<sha256hex>.m4a`
(`BlobFiles.kt:16-22`); local marker `voc1v:$header␟$localPath`; wire `voc1:$header␟$base64`.

Receive: same `maybeStoreInboundImage` path, kind triple `("voc1:", "voc1v:", "voc")`
(`ChatRepo.kt:379`), stored with `BlobFiles.save(..., "chat-audio", "m4a")` (`ChatRepo.kt:391`).

Duration display helper: `formatDuration(ms)` → `m:ss`, seconds `padStart(2,'0')`, minutes not
padded (`voiceMsg.ts:74-79`).

---

## 4. `loc1:` — location share

**File:** `src/native/locMsg.ts`.

```
loc1:<lat>,<lng>[,<accuracyMeters>]        // locMsg.ts:6, 17-20
```

`LOC_PREFIX = 'loc1:'` (`locMsg.ts:8`). Unlike images/voice there is no blob — **the same string
lives on the wire and in the DB** (`locMsg.ts:2-3`). Accuracy is `Math.round`ed on encode
(`locMsg.ts:18`). Parse: split on `,`, need ≥2 parts, `parseFloat`, non-finite lat/lng → null;
accuracy optional (`locMsg.ts:22-35`).

Render: clickable coordinates, never a map image (`locMsg.ts:3`). Label
`formatLatLng` = `lat.toFixed(5) + ', ' + lng.toFixed(5)` (`locMsg.ts:42-44`).
"Open in maps" uses `geoUri` = `geo:<lat>,<lng>?q=<lat>,<lng>` (`locMsg.ts:47-49`,
menu at `src/components/BubbleActionMenu.tsx:170-184`).

---

## 5. `react1:` — emoji reaction  (folded)

**File:** `src/messages/reactions.ts`.

```
react1:<+|-><emoji>:<key>              // reactions.ts:44-47   e.g. react1:+👍:1a2b…
```

`REACTION_PREFIX = 'react1:'` (`reactions.ts:35`). `key` is a `messageKey` (§0.2).

Parse (`reactions.ts:54-67`): first char after the prefix must be `+` or `-`; the **LAST** `:`
separates emoji from key (emojis never contain `:`, the key is trailing hex); require
`lastIndexOf(':') >= 2`, non-empty emoji, non-empty key.

Sender: `chatStore.sendReaction(convoPk, targetKey, emoji, op)` = `send(convoPk,
encodeReaction(op, emoji, targetKey))` — it reuses the whole normal send path
(`chatStore.ts:1389-1394`). The tap toggles: `sendReaction(convoPk, rKey, emoji, mine ? '-' : '+')`
(`ChatScreen.tsx:2095-2099`).

Receiver fold (`foldReactions`, `reactions.ts:84-114`): replay events **in chronological order**;
`acc: Map<targetKey, Map<emoji, Set<reactorAddress>>>`; `+` adds the reactor, `-` deletes; empty
emoji sets dropped; empty key entries dropped. Output
`Map<key, {emoji, count, mine, reactors[]}[]>` where `mine = set.has(me)`.

ChatScreen sorts markers ascending by `(at, msgPk)` before folding (`ChatScreen.tsx:1687-1698`) —
order matters because a remove must follow its add.

Quick palette: `REACTION_PALETTE = ['👍','❤️','😂','😮','😢','🙏']` (`reactions.ts:117`); a full
emoji grid modal exists for anything else (`ChatScreen.tsx:2598-2610`, `EmojiGridModal`).
"Who reacted" is an `Alert.alert(`${emoji}  ·  ${count}`, names joined by newline)`, with the
local user's own address rendered as `'You'` (`ChatScreen.tsx:2100-2110`).

---

## 6. `pin1:` — pinned message  (folded)

**File:** `src/messages/pins.ts`.

```
pin1:<+|-><key>                        // pins.ts:19-22   e.g. pin1:+1a2b…
```

`PIN_PREFIX = 'pin1:'` (`pins.ts:11`). Parse: op must be `+`/`-`, remainder is the whole key,
non-empty (`pins.ts:28-36`).

Permission v1: **only the group creator sends pin markers (gated in the UI); the fold trusts
whatever markers arrive** (`pins.ts:6-8`). v1 shows a single pinned message, newest wins.

Fold (`foldPins`, `pins.ts:43-67`): maintain an insertion-`order` array + a `pinned` Set;
`+` on an already-pinned key **bumps recency** (splice out, push); `-` removes from both; result is
the last still-pinned key in `order`, else `null`. Callers must sort by `(at, msgPk)` ascending
(`ChatScreen.tsx:1727-1733`).

The pinned bar resolves the message by scanning the loaded page for a message whose `messageKey`
matches (`ChatScreen.tsx:1736-1749`). **Careful:** that scan does *not* use `isFoldedMarker` — it
is a hand-rolled chain of exactly four predicates, `!isReactionContent && !isPinContent &&
!isLeaveContent && !isPfpContent` (`ChatScreen.tsx:1742-1745`), so a `gcfg1:` or `readd1:` message
can still be resolved as the pinned message. This is a fifth, out-of-sync guard list (see §14).

The bar previews it as `📷 Photo` / `🎤 Voice message` / `📍 Location`, else
`parseRelay(text)?.text ?? text` — i.e. **emoji labels and a relay unwrap**, unlike `quotePreview`
(`ChatScreen.tsx:1951-1957`). There is no `store*:` case, so a pinned GIF/video previews as the raw
marker.

---

## 7. `reply1:` — reply / quote  (VISIBLE)

**File:** `src/messages/reply.ts`.

```
reply1:<key>:<body>                    // reply.ts:22-25
```

`REPLY_PREFIX = 'reply1:'` (`reply.ts:13`). Parse (`reply.ts:32-42`): key = up to the **FIRST** `:`;
body = everything after (**body may contain `:`**); `colon < 1` → null.

Unlike react/pin, a reply **is** a bubble — rendered with a quoted header linking to the target
(`reply.ts:4-7`).

`displayBody(s)` (`reply.ts:45-48`) returns the reply's body, or the string unchanged — used
everywhere a "readable text" is needed (list preview `chatStore.ts:144`, quote preview
`ChatScreen.tsx:162`).

Send: `send(convoPk, reply != null ? encodeReply(reply.key, t) : t)` (`ChatScreen.tsx:1503`).

Render (`ChatScreen.tsx:2068-2084`): `parseReply(m.text)` → look up `msgByKey.get(key)`;
quoted author = `'You'` when it matches `myAddress` (case-insensitive), else `describePeer(addr)`,
else literal `'message'`; snippet = `quotePreview(target.text)` or the literal `'(not loaded)'` when
the target is not in the loaded page. Tapping the quote calls `scrollToKey` which re-derives every
row's `messageKey` and scrolls to `viewPosition: 0.5` (`ChatScreen.tsx:1711-1723`).

`quotePreview` (`ChatScreen.tsx:161-167`): `displayBody` first, then `Photo` / `Voice message` /
`Location` / raw text. (Note: it does **not** special-case `store*:` — a quoted GIF/video previews
as the raw marker.)

The bubble renders `replyText = parsedReply?.body` in place of the raw marker
(`ChatScreen.tsx:2090`, consumed at `392`).

`msgByKey` is built only from **non-folded** messages, and **first occurrence wins** on a key
collision (`ChatScreen.tsx:1702-1710`) — so a reply can never quote a control marker, and a
duplicate body resolves to whichever copy the newest-first page hits first.

**Nesting:** a reply's `body` is not re-parsed, so a reply whose body is itself a media marker
(e.g. `reply1:<key>:img1v:…␟/path`) DOES render as media — `raw = replyText ?? msg.text` feeds all
the media parsers (`ChatScreen.tsx:392-399`).

---

## 8. Forward — **no marker at all**

Forwarding is a **re-send of content**, not a wrapper. `chatStore.forwardMessage(content, toConvoPk)`
(`src/stores/chatStore.ts:1351-1386`):

- `parseImageLocal(content)` → re-read the file to base64 and call `sendImageTo` (a brand-new
  `img1:` wire message);
- `parseVoiceLocal(content)` → re-read and `sendVoiceTo`;
- anything else (text, location, `store*:`, `addr1:`) → `send(toConvoPk, content)` verbatim;
- the mesh refusal `'media cannot be forwarded to a mesh chat'` (`chatStore.ts:1356-1360`) is
  gated on `img != null || voc != null` — i.e. **only the inline forms**. A `store1:`/`store2:`
  marker forwarded into a mesh conversation is NOT refused: it falls through to `send()`, which for
  a mesh transport truncates the text to `MESH_TEXT_MTU_BYTES` (`chatStore.ts:1454-1459`) and can
  therefore ship a corrupted marker. Mesh refusal for media lives in the *pickers*
  (`sendGif`/`stageVideo`/`stageImages`), not in the send path.

So a forwarded message is indistinguishable from an original on the wire — **there is no
"forwarded from" attribution anywhere**. The menu item is available on every message including
own ones (`BubbleActionMenu.tsx:142-149`).

The only forward-shaped envelope is the mesh bridge relay, §12.

---

## 9. `pfp1:` — custom avatar broadcast, and `pfp1:clear`  (folded)

**File:** `src/messages/pfp.ts`.

```
pfp1:<store1:…|store2:…>        // pfp.ts:20-23  — prefix + an encoded MediaRef
pfp1:clear                      // pfp.ts:18, 25-28 — the "avatar removed" sentinel
```

`PFP_PREFIX = 'pfp1:'` (`pfp.ts:15`); `PFP_CLEAR = PFP_PREFIX + 'clear'` = literal `pfp1:clear`
(`pfp.ts:18`).

- `isPfpContent(s)` = `startsWith('pfp1:')` (`pfp.ts:30-32`).
- `isPfpClear(s)` = **exact string equality** with `pfp1:clear` (`pfp.ts:35-37`) — check this
  BEFORE `parsePfp`, which returns null for the sentinel.
- `parsePfp(s)` = `parseMedia(s.slice(5))` — the avatar IS a media blob, the media codec is reused
  verbatim (`pfp.ts:41-44`).

**Sender (set):** `chatStore.setAvatar` (`chatStore.ts:1054-1103`) — `pickImage(256, 50_000)`
(downscale to 256 px, ~50 KB budget), persist as JPEG via `saveBase64Jpeg`, `uploadEncrypted`, build
`{cid, key, cap, mime: 'image/jpeg', width, height, padded: true}`, store as `mine`, then
**broadcast the same marker to every conversation whose transport is `'logos'`**, best-effort per
conversation (a throwing convo does not abort the rest) (`chatStore.ts:1089-1099`). Mesh/BLE peers
are excluded because they cannot fetch Storage (`chatStore.ts:1087-1092`).

`padded: true` is set explicitly with a warning comment: `uploadEncrypted` ALWAYS pads, and `mine`
is held as this raw ref (never re-parsed from a marker), so without it "my OWN avatar downloads
without stripping the pad header → corrupt image" (`chatStore.ts:1080-1085`).

**Sender (clear):** `chatStore.clearAvatar` (`chatStore.ts:1108-1121`) — `setMine(null)` then
broadcast `pfp1:clear` to every `'logos'` conversation, so peers "drop the cached photo and fall
back to the identicon (not just a local wipe)" (`pfp.ts:16-17`, `chatStore.ts:1105-1107`).

**Receiver:** the live event handler (`chatStore.ts:2266-2282`) — for an inbound message with a
sender whose content `isPfpContent`: `isPfpClear` → `avatarStore.clearContactAvatar(sender)`;
otherwise `parsePfp` → `avatarStore.setContactAvatar(sender, ref)`.

**Reload fold:** `foldPfps(msgs)` (`pfp.ts:52-74`) — filter `isPfpContent`, sort ascending by
`at` then `seq` (e.g. `msgPk`), skip empty authors; newest wins per author. Value `null` means the
author's newest marker was `pfp1:clear`; a `MediaRef` is their current avatar; **absent** means no
marker was ever seen. ChatScreen runs it over the loaded page on every `messages` change
(`ChatScreen.tsx:1768-1780`) and **skips the local user's own author** — `mine` is authoritative
from KV/`setMine` and is deliberately never re-derived from history, so "Remove avatar" sticks.

**Persistence** (`src/stores/avatarStore.ts`): native KV, JSON-encoded.
Contact refs under `avatar:<lowercased address>` (`KV_AVATAR_PREFIX`, `avatarStore.ts:16`), own ref
under `myAvatar` (`KV_MY_AVATAR`, `avatarStore.ts:18`). Clearing writes the **empty string**, not a
delete (`avatarStore.ts:76`). `mine` hydrates eagerly on boot; contact refs hydrate lazily once per
address (`avatarStore.ts:88-99, 107-126`). A `generation` counter invalidates in-flight KV reads
across an identity wipe (`avatarStore.ts:25-30, 101-105`).

**Render:** `HexAvatar` — the custom avatar overrides the generated identicon when set
(`src/components/HexAvatar.tsx:112-114`), fetched through the same `useMediaBlob`
(`HexAvatar.tsx:22, 130`); falls back to the identicon when there is no avatar, it hasn't
downloaded, or it expired (`pfp.ts:8-9`). The ref is chosen by `isMine ? mine : refs[seed.toLowerCase()]`
(`HexAvatar.tsx:116-121`) and lazily hydrated per address (`HexAvatar.tsx:126-128`). In a
storage-off group the caller passes `disableImage`, which nulls the ref so `useMediaBlob` idles and
no Storage request fires (`HexAvatar.tsx:105-107, 124`).

---

## 10. `addr1:` — shared contact card  (VISIBLE)

**Files:** `src/messages/address.ts`, `src/lib/addressPayload.ts`, `src/components/AddressCard.tsx`.

```
addr1:<address>                                   # bare 64-hex address
addr1:peers:<address>?label=<urlencoded label>    # labelled form
```

`ADDR_PREFIX = 'addr1:'` (`address.ts:10`). The payload is **the exact same encoding the QR uses**
(`address.ts:4-6`).

`encodeAddressPayload(address, label)` (`addressPayload.ts:25-31`): empty/whitespace-only label →
the **bare address** (byte-for-byte the interoperable address-only form); otherwise
`peers:<address>?label=<encodeURIComponent(trimmed)>`. `SCHEME = 'peers:'` (`addressPayload.ts:15`).

`parseAddressPayload(value)` (`addressPayload.ts:40-72`): trim; scheme match is **case-insensitive**
(`raw.toLowerCase().startsWith('peers:')`) but the body is sliced from the ORIGINAL string; no `?`
→ whole body is the address; else split at the first `?`, then scan `&`-separated pairs for key
`label`, `decodeURIComponent` it, trim, and **clamp to `MAX_LABEL_LEN = 64`**
(`addressPayload.ts:18, 63-65`); malformed percent-encoding is swallowed and the label dropped
(`addressPayload.ts:66-68`); only the first `label` pair is considered (`break` at line 69).
The address is returned **verbatim, unvalidated** — the caller validates with `isAddress`.

`parseAddr(s)` (`address.ts:23-30`): null for a non-marker, for an empty remainder, or when the
parsed address is empty. Returns `{address}` or `{address, label}`.

**Sender:** two entry points, both `encodeAddr` then plain `send`:
- Contacts screen "share this contact" → `send(pk, encodeAddr(forwardAddr.address, forwardAddr.label))`
  (`src/screens/ContactsScreen.tsx:348-353`);
- "My address" screen → `encodeAddr(myAddress, includeLabel && hasLabel ? myLabel : undefined)`
  through the `ForwardPicker` (`src/screens/MyAddressScreen.tsx:216-238`);
- also from a chat: `setForwardContent(encodeAddr(address, label))` (`ChatScreen.tsx:2686`).

**Render:** an `AddressCard` bubble, for **both** incoming and outgoing directions
(`ChatScreen.tsx:2044-2064`), with `onAdd` → add the contact and `onView` → open the address modal
(`verified: false`). After forwarding an `addr1:` the app navigates into the target chat
(`ChatScreen.tsx:2620-2632`).

**Preview label** (`chatStore.ts:153-159`): `Contact: <label>` when a label travelled, else
`Shared a contact`. Notification label: `"Shared a contact"` (`LogosChatModule.kt:164-165`).

---

## 11. Group control markers

### 11.1 `leave1:` — group leave  (folded)

```
leave1:1                              // leave.ts:16-19  (encodeLeave() emits exactly this)
```
`LEAVE_PREFIX = 'leave1:'` (`leave.ts:14`). The payload is a bare constant `1`; **the leaver is the
message's sender** (`senderAccount`), not a field.

GroupV1 has no cryptographic self-remove, so leaving is a local delete + permanent tombstone plus
this broadcast (`leave.ts:3-9`).

`foldLeaves(msgs)` (`leave.ts:29-39`) → `Set` of **lowercased** sender addresses — but note it is
**exported and never called**: it has no call site anywhere in `src/` or `__tests__/`. What actually
runs is an inline effect in ChatScreen (`ChatScreen.tsx:1754-1762`): for every `isLeaveContent`
message it takes `leaver = authorOf(m)` — the same `out ? myAddress : senderAccount ?? peerAddress`
resolution used for message keys, **not** `foldLeaves`'s `senderAccount`-only rule — skips it when
it case-insensitively equals `myAddress`, and calls `setMemberStatus(convoPk, leaver, 'left')`
(idempotent on an unchanged status). A port should implement the ChatScreen behaviour; `foldLeaves`
is dead code.

Locally, `ChatRepo.leaveGroupLocal` writes KV key `left:<libConvoId>` (`ChatRepo.kt:400, 408-413`)
and every subsequent inbound for that lib id is dropped outright — no row, no store, no notify
(`ChatRepo.kt:418-424`). Leaving is one-way; there is no rejoin (`leave.ts:11-12`).

### 11.2 `gcfg1:` — per-group storage opt-out  (folded)

```
gcfg1:storage:off
gcfg1:storage:on                      // groupcfg.ts:26-29
```
`GROUPCFG_PREFIX = 'gcfg1:'` (`groupcfg.ts:17`). Parse is **exact string match** on the remainder:
`'storage:off'` → `{storageOff:true}`, `'storage:on'` → `{storageOff:false}`, anything else → null
(`groupcfg.ts:36-42`).

(Note: do **not** take `__tests__/markers.test.ts:16-23` as a grammar reference. That table only
feeds `isFoldedMarker`, which is a bare prefix check, so its samples are deliberately loose and
several are not valid encodings: `'gcfg1:storage=off'` (line 21) would not parse,
`'react1:abc123:👍'` (17) has emoji and key swapped and no `+`/`-` op, and `'pin1:abc123'` (18) has
no op either.)

`foldGroupCfgs` (`groupcfg.ts:52-67`): filter, sort ascending by `(at, seq)`, newest wins
**group-wide** (not per-author); `null` when the group has no gcfg marker at all.

Effect: storage off ⇒ text/location/reactions/replies only; no media sent or fetched, so the
Storage node sees nothing for that group (`groupcfg.ts:4-9`). Enforced in the composer and in
render (`ChatScreen.tsx:400-403`, `HexAvatar.tsx:105`).

Known MVP caveat, documented in code: sender is **not** verified as the creator, so any member's
`gcfg1:` is honoured (`chatStore.ts:2283-2296`).

### 11.3 `readd1:` — desync auto-recovery request  (folded)

```
readd1:<libConvoId>                   // readd.ts:16-19
```
`READD_PREFIX = 'readd1:'` (`readd.ts:14`). Payload is the group's **shared lib-convo-id**;
`parseReadd` trims and returns null when empty (`readd.ts:26-30`). Sent over a **1:1** to group
members; only the group creator acts on it (creator-gated remove-then-add), everyone else ignores
it; the requester is simply the 1:1 sender (`readd.ts:3-9`). Produced at `chatStore.ts:813`.

Because it never notifies and never bumps unread, a replay query exists so a cold-started creator
can still act: `ChatDb.pendingReaddsJson(sinceMsgPk, limit)` —
`WHERE m.direction='in' AND m.content LIKE 'readd1:%' AND m.msg_pk>? ORDER BY m.msg_pk ASC LIMIT ?`
(`ChatDb.kt:974-997`), surfaced as `LogosChatModule.pendingReadds` (`LogosChatModule.kt:1304-1310`,
limit clamped to `1..200`). Each row carries `{msgPk, convoPk, content, sender, peerAddress}` — the
conversation's `peer_address` rides along so a 1:1 row with no per-message sender can still be
attributed to its requester (`ChatDb.kt:986-993`).

### 11.4 `\u0001peers/join-ack` — join acknowledgement (NOT a `:`-marker)

```kotlin
// ChatRepo.kt:48 — literal source is the escape \u0001 (SOH) followed by "peers/join-ack"
const val JOIN_ACK = "\u0001peers/join-ack"
```
A joiner auto-sends this right after joining/rejoining so the creator learns it is in — MLS gives
the adder no signal that an addee accepted the welcome (`ChatRepo.kt:40-47`). Per the source comment, the SOH (U+0001)
prefix keeps it from colliding with real text. Matching is **exact string equality**
(`content == JOIN_ACK`, `ChatRepo.kt:467`), not a prefix test. On receipt it is turned into a `member_joined`
Outcome and returns **before any row is persisted** — no bubble, no unread, no notification
(`ChatRepo.kt:463-471`). The joiner sends it without recording a local row
(`LogosChatModule.kt:541`).

---

## 12. Mesh/bridge envelopes that also ride inside the body

These are not chat content, but they occupy the same `content` string and a desktop port must at
minimum not render them wrong.

### 12.1 `lr1:` — relay envelope (mesh↔logos bridge)

```
lr1:<origin>␟<text>                   // relay.ts:9-11, 20-24
```
`RELAY_PREFIX = 'lr1:'`, `SEP = '␟'` (`relay.ts:16-17`). `origin` is a **display label**, sanitised
by `origin.replace(/[␟\r\n]/g, ' ').trim() || '?'` (`relay.ts:22`). Purpose: attribute the message
to the ORIGINAL sender rather than the relayer, and act as the loop guard (an already-enveloped
message is never re-forwarded) (`relay.ts:3-7`).

Render (`ChatScreen.tsx:405-417`): `displayText = relay?.text ?? raw`; the attribution becomes
`{label: relay.origin, hex: '· via <bridgeName>', verified: false}` — a relay is a local assertion,
not per-message crypto.

### 12.2 `lmi:` — MeshCore channel invite (control, over a mesh DM)

```
lmi:<idx>:<key32hex>:<libConvoId hex|empty>:<name>     // chatStore.ts:940
lmi:<idx>:<key32hex>:<name>                            # legacy fallback
```
`MESH_INVITE_PREFIX = 'lmi:'` (`chatStore.ts:75`). Name is last so it may contain `:`
(`chatStore.ts:938`); truncated to 31 chars on send (`chatStore.ts:930`). Parsed with
`/^(\d+):([0-9a-fA-F]{32}):([0-9a-fA-F]*):(.*)$/`, falling back to
`/^(\d+):([0-9a-fA-F]{32}):(.*)$/` (`chatStore.ts:1936-1948`); key and libId are lowercased, an
empty libId becomes `null`, and an empty name becomes `Channel <idx>`. Handled as a control
message — binds the channel to the mirrored Logos group when the libId matches a local group, joins
the channel, and returns **without rendering a DM bubble** (`chatStore.ts:1925-1969`); if neither
regex matches it falls through and is recorded as an ordinary mesh DM.

### 12.3 BLE transport framing (below the chat body — listed for completeness)

- `frg1:<msgId>:<idx>:<n>␟<chunk>` — MLS-over-sub-MTU fragmentation, `idx` 0-based, `n` total,
  `MAX_INFLIGHT = 32` (`src/native/bleFrag.ts:13, 22-26`).
- `bf1␟<msgId>␟<hopCount>␟<ttl>␟<kind>␟<senderId>␟<payload>` — multi-hop flood datagram,
  `kind ∈ {'presence','msg'}`, payload last so it may contain `:` or a nested `␟` envelope
  (`src/native/bleFlood.ts:30, 33-47, 55-59`).

---

## 13. Delivery / read state — there is **no wire signalling**

Everything is local. There is no delivery receipt, no read receipt, no typing indicator, no
"seen" marker anywhere in the source.

**Outbound status** is a local DB column with a CHECK constraint:

```sql
-- ChatDb.kt:131
status TEXT CHECK(status IN ('pending','sent','failed','received'))
```

- `ChatRepo.recordOutgoing` inserts `direction='out', status='pending'` (`ChatRepo.kt:152-160`);
- `ChatRepo.finalizeOutgoing(msgPk, ok)` sets `'sent'` or `'failed'` (`ChatRepo.kt:162-164`) —
  `ok` is purely `NodeBridge.chatSendMessage(...) == 0` (after at most one stale-conversation
  rebind + retry, `LogosChatModule.kt:574-580`), i.e. **"handed to the node"**, not "delivered to
  the peer";
- inbound rows are inserted with `status='received'` (`ChatRepo.kt:490`); the mesh-recorded path
  is separate and stamps `out → 'sent'`, `in → 'received'` immediately, with no pending phase
  (`ChatDb.kt:437-438`).

**Rendered** as the time-row text (`ChatScreen.tsx:625-630`): `'sending…'` when pending,
`'failed — tap to retry'` when failed (in `colors.unread`), otherwise `formatTime(msg.at)`.
There are no check-mark ticks in the source. Transport tags render beside it: `via BLE ·`
(`ChatScreen.tsx:623`) and a mesh label (`ChatScreen.tsx:622`).

**Read state** is per-conversation unread count, cleared locally only:

- `chatStore.markRead(convoPk)` → `LogosChat.markRead` (`chatStore.ts:1557-1559`);
- `LogosChatModule.markRead` → `ChatDb.markRead` + cancel the notification when resumed
  (`LogosChatModule.kt:1325-1331`);
- `ChatDb.markRead` = `UPDATE conversations SET unread=0 WHERE convo_pk=?` (`ChatDb.kt:840-843`).
  **Nothing is transmitted.**

The only peer-visible "activity" signal is passive: `lastInboundAt` = `MAX(sent_at)` of inbound
messages (`ChatDb.kt:924-925, 953-955`), rendered as `last seen …` buckets
(`src/stores/conversationView.ts:314-331`).

Delete is local-only with an explicit confirm: *"This removes the message from this device only.
The other person still has their copy."* — there is **no remote unsend** (`ChatScreen.tsx:2576-2595`).

---

## 14. Where each marker is suppressed — and the lists that disagree

A port must reproduce this per-surface, because the Android source genuinely has **four**
non-identical guard lists (plus one more inside the pin bar).

| Surface | Guarded prefixes | Source |
|---|---|---|
| **Unread bump** (native) | `react1:`, `pin1:`, `leave1:`, `readd1:` | `ChatRepo.kt:506-508` |
| **Notification** (native) | `react1:`, `pin1:`, `leave1:`, `pfp1:`, `gcfg1:`, `readd1:` | `LogosChatModule.kt:129-135` |
| **Conversation-list preview** (SQL) | `react1:%`, `pin1:%`, `leave1:%`, `pfp1:%`, `gcfg1:%`, `readd1:%` | `ChatDb.kt:914-919` |
| **Timeline rows** (JS) | the 6 `FOLDED_MARKERS` | `src/messages/markers.ts:21-28`, `ChatScreen.tsx:1820` |
| **Reply-target index** (JS) | the 6 `FOLDED_MARKERS` | `ChatScreen.tsx:1705` |
| **Pinned-message lookup** (JS) | `react1:`, `pin1:`, `leave1:`, `pfp1:` only — hand-rolled, *not* `isFoldedMarker` | `ChatScreen.tsx:1742-1745` |

Consequences, read straight off the code:
- **`pfp1:` and `gcfg1:` DO bump the unread counter** (they are absent from `ChatRepo.kt:507`)
  while being invisible in the list preview, the timeline, and notifications.
- a `pin1:+<key>` naming a `gcfg1:`/`readd1:` message resolves in the pin bar and shows the raw
  marker there, because that one scan omits those two prefixes.

### Notification body mapping (native)

```kotlin
// LogosChatModule.kt:145-167
// reply1: → notify with the BODY (substring after the first ':' of the remainder)
t.startsWith("img1")   -> "📷 Photo"            // catches img1: AND img1v:
t.startsWith("voc1")   -> "🎤 Voice message"    // catches voc1: AND voc1v:
t.startsWith("loc1:")  -> "📍 Location"
t.startsWith("store1:") -> if (t.contains(":video/")) "🎬 Video"
                           else if (t.contains(":image/gif:")) "GIF"
                           else "📎 Media"
t.startsWith("addr1:") -> "Shared a contact"
else -> t
```

**Observed inconsistency (not inferred — read the line):** the media branch tests only
`"store1:"` (`LogosChatModule.kt:160`). Since every current send emits `store2:`
(`media.ts:41`), an inbound GIF/video/HQ-photo notification falls through to `else -> t` and shows
the **raw marker string** as the notification body.

### JS conversation-list preview mapping

```ts
// src/stores/chatStore.ts:144-159   (after displayBody() unwraps a reply1:)
isMediaContent → mediaLabel()  // 'GIF' | 'Video' | 'Media'
isImageContent → '📷 Photo'
isVoiceContent → '🎤 Voice message'
isLocationContent → '📍 Location'
isAddrContent → `Contact: ${label}` or 'Shared a contact'
otherwise → the raw text
```

---

## 15. Quick reference — every prefix that rides a message body

| Prefix | Kind | Payload | Folded? | File |
|---|---|---|---|---|
| `store1:` | media ref (unpadded, legacy) | `cid:key:mime:w:h[:cap]` | no | `src/messages/media.ts:15` |
| `store2:` | media ref (Padmé-padded, current) | same | no | `src/messages/media.ts:21` |
| `img1:` | inline photo, wire | `mime:w:h␟base64` | no | `src/native/imageMsg.ts:15` |
| `img1v:` | inline photo, local DB row | `mime:w:h␟absPath` | no | `src/native/imageMsg.ts:16` |
| `voc1:` | voice note, wire | `mime:durMs:wf,csv␟base64` | no | `src/native/voiceMsg.ts:9` |
| `voc1v:` | voice note, local DB row | `mime:durMs:wf,csv␟absPath` | no | `src/native/voiceMsg.ts:10` |
| `loc1:` | location | `lat,lng[,accM]` | no | `src/native/locMsg.ts:8` |
| `reply1:` | reply/quote | `key:body` | no | `src/messages/reply.ts:13` |
| `addr1:` | shared contact card | `address` or `peers:addr?label=…` | no | `src/messages/address.ts:10` |
| `react1:` | reaction | `<+|->emoji:key` | **yes** | `src/messages/reactions.ts:35` |
| `pin1:` | pin/unpin | `<+|->key` | **yes** | `src/messages/pins.ts:11` |
| `leave1:` | group leave | `1` | **yes** | `src/messages/leave.ts:14` |
| `pfp1:` | avatar broadcast | `store{1,2}:…` | **yes** | `src/messages/pfp.ts:15` |
| `pfp1:clear` | avatar un-broadcast | (exact literal) | **yes** | `src/messages/pfp.ts:18` |
| `gcfg1:` | group storage config | `storage:on` / `storage:off` | **yes** | `src/messages/groupcfg.ts:17` |
| `readd1:` | desync re-add request | `libConvoId` | **yes** | `src/messages/readd.ts:14` |
| `\u0001peers/join-ack` | join ack | (exact literal) | never persisted | `ChatRepo.kt:48` |
| `lr1:` | bridge relay envelope | `origin␟text` | no (unwrapped) | `src/native/relay.ts:16` |
| `lmi:` | MeshCore channel invite | `idx:key:libId:name` | consumed, no bubble | `src/stores/chatStore.ts:75` |
| `frg1:` | BLE fragment (transport) | `msgId:idx:n␟chunk` | transport | `src/native/bleFrag.ts:22` |
| `bf1` | BLE flood frame (transport) | `␟`-joined 7 fields | transport | `src/native/bleFlood.ts:30` |

**Not in this table, and easy to mistake for one:** `logos-continues:<oldLibConvoId>`
(`ChatRepo.CONTINUES_PREFIX`, `ChatRepo.kt:33-37`). It never appears in a message body — it is
written into the **group's MLS metadata description** when a dead group is recreated, and read back
at `ChatRepo.kt:235-236` / written at `LogosChatModule.kt:1180`. A body-marker port ignores it.

Verified complete for the JS side: every `startsWith` on a literal prefix in `src/` goes through one
of the exported `isXContent` predicates above — a repo-wide grep for other string-literal
`startsWith` calls returns only `'#'` and `'video/'`.

---

## 16. Things that explicitly do NOT exist in the source

Stated so a port does not invent them:

- **No message id on the wire** — identity is `messageKey(author, body)` only (`reactions.ts:8-12`).
- **No caption field** on any media marker (`captionFor` is a `MediaViewer` prop nothing supplies).
- **No filename, no byte size, no duration** in `store1:`/`store2:` (duration exists only for
  `voc1*`).
- **No forward envelope / "forwarded from"** — forwarding re-sends the content (`chatStore.ts:1351-1386`).
- **No delivery receipt, read receipt, or typing indicator** anywhere (§13).
- **No remote delete/unsend** (`ChatScreen.tsx:2579-2581`).
- **No per-message edit marker.**
- **No versioned/extensible marker registry on the wire** — each new feature mints a new
  `<name><version>:` prefix, and old clients render unknown prefixes as raw text.

---

## Files read for this document

```
src/messages/markers.ts        src/messages/media.ts       src/messages/reactions.ts
src/messages/reply.ts          src/messages/pins.ts        src/messages/pfp.ts
src/messages/address.ts        src/messages/groupcfg.ts    src/messages/leave.ts
src/messages/readd.ts          src/lib/addressPayload.ts
src/native/imageMsg.ts         src/native/voiceMsg.ts      src/native/locMsg.ts
src/native/relay.ts            src/native/bleFrag.ts       src/native/bleFlood.ts
src/native/mediaCache.ts       src/media/mediaList.ts
src/stores/chatStore.ts        src/stores/avatarStore.ts
src/screens/ChatScreen.tsx     src/components/BubbleActionMenu.tsx
src/components/MediaViewer.tsx src/components/HexAvatar.tsx
src/screens/ContactsScreen.tsx src/screens/MyAddressScreen.tsx
android/app/src/main/java/com/logoschat/StorageRef.kt
android/app/src/main/java/com/logoschat/StorageModule.kt
android/app/src/main/java/com/logoschat/MediaPadding.kt
android/app/src/main/java/com/logoschat/BlobFiles.kt
android/app/src/main/java/com/logoschat/ImageFiles.kt
android/app/src/main/java/com/logoschat/ChatRepo.kt
android/app/src/main/java/com/logoschat/ChatDb.kt
android/app/src/main/java/com/logoschat/LogosChatModule.kt
__tests__/markers.test.ts      __tests__/media.test.ts
__tests__/pfp.test.ts          __tests__/address-marker.test.ts
```
