# Peers HexAvatar identicon — ground truth spec (for a pixel-identical QML port)

Extracted by reading source only. Every value below cites `path:line` relative to
`<logos-chat-android>`.

Primary sources:
- `src/components/HexAvatar.tsx` — the reference implementation (React Native + `react-native-svg`)
- `android/app/src/main/java/com/logoschat/Identicon.kt` — an existing native Kotlin port
  (self-described as "a Kotlin port of the app's HexAvatar identicon engine … pixel-identical",
  `Identicon.kt:8-16`) — useful as a second reading of the same algorithm
- `src/theme/colors.ts` — the ground/canvas colour
- `src/components/QrCard.tsx` — second consumer of `identiconCells` (QR centre badge)
- `src/messages/pfp.ts`, `src/stores/avatarStore.ts`, `src/stores/chatStore.ts` — the custom-avatar override

---

## 1. Overall shape

The identicon is **NOT a circle and NOT a hexagon** despite the name "HexAvatar" —
"Hex" refers to the *hex identity string* used as the seed, not the shape
(`HexAvatar.tsx:1` "a deterministic identicon generated from a hex identity").

Container (`HexAvatar.tsx:186-199`):

```
width  = size
height = size
borderRadius = size * 0.22        // rounded square
overflow = hidden
backgroundColor = colors.canvas   // #0A0A0A
```

So: **square, corner radius = 22 % of the side, clipped, on a #0A0A0A ground.**
`size` defaults to `40` (`HexAvatar.tsx:98`).

`colors.canvas = '#0A0A0A'` — `src/theme/colors.ts:3`.
Kotlin port agrees: `GROUND = 0xFF0A0A0A` (`Identicon.kt:21`) and `r = size * 0.22f`
(`Identicon.kt:53`).

### Cells

`AVATAR_N = 5` (`HexAvatar.tsx:61`), `N = 5` (`Identicon.kt:22`).

In the app's `HexAvatar` there is **no padding and no gap** — the 5×5 grid fills the
whole square (`HexAvatar.tsx:173`):

```
cell = size / 5
rect x = c.x * cell
rect y = c.y * cell
rect w = cell + 0.5     // +0.5 px overlap, anti-alias seam guard (HexAvatar.tsx:178-181)
rect h = cell + 0.5
```

Cells are **flush squares with no rounding** (`HexAvatar.tsx:3` "a 5×5 left-right-symmetric
grid of FLUSH squares (no gaps, no rounding on the cells)").

Empty cells are simply not drawn — the ground (`#0A0A0A`) shows through
(`HexAvatar.tsx:82-83`).

> Divergences that exist in the repo but are **not** the in-app avatar:
> - `Identicon.kt:48,59-61` insets the grid: `grid = size * fill` (default `fill = 0.66`),
>   `off = (size - grid) / 2`, `cell = grid / 5`. That inset exists only for the launcher /
>   pinned-shortcut bitmap (called once, with `fill = 0.38f`, `LogosChatModule.kt:309`).
>   The in-app avatar uses `fill = 1.0` equivalent (no inset).
> - `Identicon.kt:79-90` rounds the **outer corner only** of a filled cell sitting at a grid
>   corner, with radius `cr = cell * 0.45f` (`Identicon.kt:65`). This is launcher-art-specific
>   ("round the OUTER corner of a filled cell that sits at a grid corner, matching the launcher
>   art's rounded 'head'", `Identicon.kt:63-64`) and is **absent** from `HexAvatar.tsx`.
>   Do not port it to the general avatar.
> - `Identicon.kt:52-57` also has a `rounded` flag (default `false`) choosing
>   `drawRoundRect(r = size * 0.22f)` vs a plain `drawRect` ground; the pinned-shortcut call
>   passes `rounded = false` (`LogosChatModule.kt:309`) because the launcher mask does the
>   shaping. The in-app avatar is always the rounded form.
> - `QrCard.tsx:151-152` uses `cell + 0.02` overlap instead of `+0.5`, because there the
>   Svg user units are QR modules, not px.

---

## 2. Hash function on the seed

`HexAvatar.tsx:43-59` — **xmur3 string hash → mulberry32 PRNG**. Exact code:

```js
function rng(seed: string): () => number {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);   // 0xCC9E2D51
    h = (h << 13) | (h >>> 19);
  }
  let a = Math.imul(h ^ (h >>> 13), 3266489909);          // 0xC2B2AE35
  a = (a ^ (a >>> 16)) >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
```

Semantics required of the QML/C++/JS port:

- `h`, `a`, `t` are **signed 32-bit** ints with wrapping arithmetic.
- `Math.imul(x, y)` = 32-bit wrapping multiply, result truncated to int32.
- `>>>` is a **logical** (unsigned) right shift on the 32-bit pattern.
- `<<` is a 32-bit left shift with truncation.
- `seed.charCodeAt(i)` is the **UTF-16 code unit** (not a UTF-8 byte, not a code point).
  Seeds in practice are ASCII hex addresses / ids, so UTF-8 bytes coincide — but for
  exactness, iterate UTF-16 code units.
- `seed.length` is the **UTF-16 length**.
- The returned double is `uint32 / 2^32`, i.e. in `[0, 1)`.

The Kotlin port confirms the mapping — its doc comment (`Identicon.kt:24-25`) says
"Kotlin Int is 32-bit and `*` wraps like Math.imul; `ushr` == JS `>>>`"; the body is
`Identicon.kt:26-40`. Note the Kotlin version omits the JS `>>> 0` on `a` after the
finaliser (`Identicon.kt:33` is just `a = a xor (a ushr 16)`) — harmless, because the JS
closure immediately does `a |= 0`, so both carry the same 32-bit pattern.

Note the state `a` is **mutable and carried across calls** — the sequence of `r()` calls
is order-sensitive. The Kotlin port explicitly calls this out: "The RNG call ORDER matches
the JS exactly (skip-roll then fill-roll per cell)" (`Identicon.kt:15`).

### Prefixed seed

The RNG is seeded with `PREFIX[kind] + seed`, not the bare seed (`HexAvatar.tsx:77`):

```
PREFIX = {contact: 'c:', group: 'g:', mesh: 'm:', ble: 'b:'}   // HexAvatar.tsx:41
```

So the same address rendered as `contact` and as `mesh` gives different patterns.
`Identicon.kt:58` hard-codes `rng("c:$address")` (it only ever renders the contact kind).

---

## 3. Bits → 5×5 grid, and the mirror

`identiconCells` (`HexAvatar.tsx:72-93`):

```js
const ramp = RAMPS[kind];
const r = rng(PREFIX[kind] + seed);
const cells = [];
for (let x = 0; x < 3; x++) {          // OUTER loop is x (columns 0,1,2)
  for (let y = 0; y < AVATAR_N; y++) { // INNER loop is y (rows 0..4)
    if (r() > 0.5) continue;           // roll #1: skip → empty cell
    const fill = ramp[Math.floor(r() * ramp.length)];  // roll #2: colour
    const xs = x === 2 ? [2] : [x, AVATAR_N - 1 - x];  // mirror
    for (const xx of xs) cells.push({x: xx, y, fill});
  }
}
```

Critical details for a faithful port:

1. **Iteration order is column-major**: `x` outer (0,1,2), `y` inner (0..4).
   15 cell decisions total.
2. **Two rolls per decided cell, but the second roll is consumed only when the cell is
   filled.** `r() > 0.5 → continue` skips the colour roll entirely. Any port that
   pre-draws both rolls unconditionally will diverge.
3. Fill condition is `r() <= 0.5` (i.e. `continue` when strictly `> 0.5`).
4. **Mirroring**: column `x` also paints column `4 - x`, with the *same* colour and row.
   - column 0 → mirrors to column 4
   - column 1 → mirrors to column 3
   - column 2 is the centre column, painted once, no mirror
   Left–right symmetry is therefore exact, including colours.
5. Coordinates are grid units `0..4`; `y` is the row (0 = top), `x` the column (0 = left).

`Identicon.kt:67-72` mirrors this exactly, including `val xs = if (x == 2) intArrayOf(2)
else intArrayOf(x, N - 1 - x)`.

---

## 4. Colour ramps and index selection

`HexAvatar.tsx:26-40` — three ramps of 5 stops each, dark → near-white:

```js
const LOGOS_RAMP = ['#B8420E', '#FF5000', '#FF7A33', '#FFB27A', '#FFE4D0'];
const MESH_RAMP  = ['#166534', '#22C55E', '#4ADE80', '#86EFAC', '#DCFCE7'];
const BLE_RAMP   = ['#0B5C8A', '#0EA5E9', '#38BDF8', '#7DD3FC', '#E0F5FF'];

const RAMPS = {contact: LOGOS_RAMP, group: LOGOS_RAMP, mesh: MESH_RAMP, ble: BLE_RAMP};
```

Kind → ramp (`HexAvatar.tsx:35-40`):

| `AvatarKind` | ramp | meaning (`HexAvatar.tsx:4-11`) |
|---|---|---|
| `contact` | LOGOS (orange) | a Logos 1:1 |
| `group`   | LOGOS (orange) | a Logos group — **shares the orange ramp**, no separate colour |
| `mesh`    | MESH (green)   | MeshCore identity (channel or mesh peer) |
| `ble`     | BLE (azure)    | a Bluetooth-bootstrapped chat |

The comment at `HexAvatar.tsx:5-9` states the rule: **colour = TRANSPORT, not conversation
type.** (`GroupInfoScreen.tsx:327` still says "azure" in a stale comment; the code passes
`kind="group"` which resolves to LOGOS_RAMP — trust the code.)

Colour index (`HexAvatar.tsx:85`):

```js
const fill = ramp[Math.floor(r() * ramp.length)];   // ramp.length === 5
```

i.e. `idx = floor(r() * 5)`, uniform over 0..4. `Identicon.kt:70` adds a defensive
`.coerceIn(0, LOGOS_RAMP.size - 1)` (i.e. `0..4`); mathematically unreachable since `r() < 1`.

**Background / ground colour: `#0A0A0A`** (`colors.canvas`, `src/theme/colors.ts:3`;
`Identicon.kt:21`). It is the container background, not a drawn cell. In the QR badge the
same ground is used for the badge tile (`QrCard.tsx:144` `fill={colors.canvas}`).

There is **no per-seed background colour** and **no hue rotation** — the ramp is fixed per
kind.

---

## 5. Seed selection per context

### 1:1 conversation vs group

`avatarSeed` (`HexAvatar.tsx:205-215`):

```js
export function avatarSeed(convo) {
  if (convo.isGroup) return convo.libConvoId ?? `pk${convo.convoPk}`;
  return convo.peerAddress ?? `pk${convo.convoPk}`;
}
```

- **Group** → the **shared lib conversation id** (`libConvoId`), so every member sees the
  same group avatar (`HexAvatar.tsx:13-14`).
- **1:1** → the peer's stable address (`peerAddress`).
- Fallback when neither is bound yet → the literal string `` `pk${convoPk}` `` (e.g. `pk7`),
  keeping the row deterministic.

`GroupInfoScreen.tsx:331` uses the same expression inline: `seed={convo?.libConvoId ?? `pk${convoPk}`}`.

### Kind selection

`convoKind` (`HexAvatar.tsx:220-231`):

```js
if (convo.transport === 'mesh') return 'mesh';
if (convo.transport === 'ble')  return 'ble';
return convo.isGroup ? 'group' : 'contact';
```

### Contacts / member rows / my own avatar

Observed call sites, with the `kind` each one actually passes. Do **not** assume
`kind="contact"` — seven sites compute it (`ConversationsScreen.tsx:110,496`,
`ChatScreen.tsx:424,1172`, `MediaViewer.tsx:301`, `ForwardPicker.tsx:46`,
`LabelModal.tsx:68`). This table plus the "my own avatar" table below cover all 27
`<HexAvatar …>` usages under `src/`.

| context | seed | kind | size | file:line |
|---|---|---|---|---|
| Contacts list row | `item.address` | `"contact"` | 32 | `src/screens/ContactsScreen.tsx:182` |
| Contacts row menu header | `menuContact.address` | `"contact"` | 32 | `src/screens/ContactsScreen.tsx:322` |
| New conversation row | `address` | `"contact"` | 40 | `src/screens/NewConversationScreen.tsx:71` |
| Add-members row | `item.address` | `"contact"` | 32 | `src/screens/AddMembersScreen.tsx:235` |
| Group member row | `item.address` | `"contact"` | 32 | `src/screens/GroupInfoScreen.tsx:170` |
| Group header | `convo?.libConvoId ?? pk<n>` | `"group"` | 48 | `src/screens/GroupInfoScreen.tsx:330-334` |
| Conversation list row | `avatarSeed(convo)` | `convoKind(convo)` | 32 | `src/screens/ConversationsScreen.tsx:110` |
| Conversation row menu header | `avatarSeed(rowMenu)` | `convoKind(rowMenu)` | 32 | `src/screens/ConversationsScreen.tsx:494-499` |
| Chat header | `avatarSeed(convo)` | `convoKind(convo)` | 28 | `src/screens/ChatScreen.tsx:1172` |
| Message attribution (in-bubble) | `effAttr.address` | `avatarKind` prop ⇒ `convoKind({transport: convo.transport, isGroup: false})` (`ChatScreen.tsx:2111-2113`) | 16 | `src/screens/ChatScreen.tsx:424` |
| Media viewer author chip | `author.address` | `author.kind` (an `AvatarKind` carried on the author object, `MediaViewer.tsx:48`) | 18 | `src/components/MediaViewer.tsx:301` |
| Forward picker row | `item.peerAddress ?? String(item.convoPk)` | `convoKind(item)` | 32 | `src/components/ForwardPicker.tsx:44-48` |
| Address card | `address` | `"contact"` | 40 | `src/components/AddressCard.tsx:27` |
| Address modal | `address` (only when `address != null`) | `"contact"` | 32 | `src/components/AddressModal.tsx:118` |
| Label modal | `address` | `avatarKind` prop, **default `'contact'`** (`LabelModal.tsx:24,34`); ChatScreen passes `convoKind({transport, isGroup:false})` (`ChatScreen.tsx:2693-2695`) | 40 | `src/components/LabelModal.tsx:68` |
| Nearby row | `item.address` | `"contact"` | 32 | `src/screens/NearbyScreen.tsx:213` |
| Nearby trust prompt | `pendingTrust ?? 'x'` | `"contact"` | 56 | `src/screens/NearbyScreen.tsx:252` |
| Mesh map member | `memberAddress` | `"contact"` | 40 | `src/components/MeshMapModal.tsx:88` |
| Mesh map DM | `` `mesh:dm:${item.pubkeyHex}` `` | `"mesh"` | 28 | `src/components/MeshMapModal.tsx:139` |
| MeshCore channel | `` `mesh:chan:${ch.idx}` `` | `"mesh"` | 28 | `src/screens/MeshCoreScreen.tsx:246` |
| MeshCore public channel | `'mesh:public'` | `"mesh"` | 28 | `src/screens/MeshCoreScreen.tsx:260` |
| MeshCore DM | `` `mesh:dm:${c.pubkeyHex}` `` | `"mesh"` | 28 | `src/screens/MeshCoreScreen.tsx:321` |

Note that a **1:1 chat on mesh/ble is still colour-coded by transport in the bubble
attribution and the label modal** — both force `isGroup: false` into `convoKind`, so they
resolve to `mesh`/`ble`/`contact` but never `group`.

**My own avatar** — always `kind="contact"` seeded on **my own address**:

| context | seed | size | file:line |
|---|---|---|---|
| Side menu identity header | `myAddress ?? 'me'` | 48 | `src/components/SideMenu.tsx:314` |
| Conversations header button | `myAddress ?? 'me'` | 32 | `src/screens/ConversationsScreen.tsx:412` |
| Lock screen | `myAddress` (rendered only when truthy) | 56 | `src/screens/LockScreen.tsx:102` |
| About screen | `myAddress` (rendered only when `!= null`) | 56 / 40 | `src/screens/AboutScreen.tsx:133,160` |
| Pinned home-screen shortcut (native) | `addr`, `"c:"` prefix, 288 px, `fill=0.38f`, `rounded=false` | 288 | `LogosChatModule.kt:309` + `Identicon.kt:48,58` |

Two different null-handling conventions, and a port must keep them apart:

- `SideMenu.tsx:314` / `ConversationsScreen.tsx:412` fall back to the **literal seed string
  `'me'`** — it produces a real, stable identicon, not a blank.
- `LockScreen.tsx:101-105` and `AboutScreen.tsx:132-136,156-160` do **not** substitute a
  seed: when `myAddress` is null they render the `<Logo>` mark instead of a HexAvatar
  (`Logo size={48}` / `size={56}`, `color={colors.accent}`, `strokeWidth={2}`).

### Seed case sensitivity

The identicon hash uses the seed **verbatim, un-normalised** (`HexAvatar.tsx:77`).
Only the *custom-avatar lookup* lowercases (`HexAvatar.tsx:117-118`). So a port must feed
exactly the same casing of the address as the Android app does, or patterns diverge.

---

## 6. Custom avatar override (`pfp1:`) — how it beats the identicon

### Marker format (`src/messages/pfp.ts`)

- `PFP_PREFIX = 'pfp1:'` (`pfp.ts:15`)
- Set: `pfp1:` + `encodeMedia(ref)` — the body is an encoded `MediaRef` (a `store1:`/`store2:`
  media pointer), i.e. the avatar *is* an ordinary E2E media blob (`pfp.ts:20-23`).
- Clear: the exact sentinel string `pfp1:clear` (`PFP_CLEAR`, `pfp.ts:18`).
- `foldPfps` (`pfp.ts:52-74`) folds a timeline into `Map<author, MediaRef | null>`,
  sorting ascending by `at` then `seq` so **newest wins**; `null` = the author's newest
  marker was `pfp1:clear`.
- pfp markers are never rendered as bubbles and are suppressed from
  unread/notify/list-preview natively (`pfp.ts:11-12`).

### Storage of the resolved ref (`src/stores/avatarStore.ts`)

- Peer avatars: `refs[address.toLowerCase()]`, persisted to native KV under
  `avatar:<lowercased address>` (`avatarStore.ts:16,60-65`).
- My own avatar: `mine`, persisted under KV key `myAvatar` (`avatarStore.ts:18,81-86`).
- `mine` hydrates eagerly on boot; peer refs hydrate lazily once per address via
  `ensureHydrated` (`avatarStore.ts:88-126`). **HexAvatar itself triggers that lazy read**:
  an effect calls `ensureHydrated(seed)` whenever `!isMine && !disableImage`
  (`HexAvatar.tsx:126-128`). A port that never calls it will render identicons forever for
  peers whose ref is only in KV.
- Clearing writes an **empty string**, it does not delete the key
  (`LogosChat.setSetting(key, '')`, `avatarStore.ts:76,83`); readers treat `''`/absent the
  same (`avatarStore.ts:93,116`).
- `reset()` (`avatarStore.ts:101-105`, #441) drops `refs` + `mine` in memory (no KV write)
  after an identity wipe/restore, and bumps a `generation` counter (`avatarStore.ts:30`)
  that every in-flight KV read captures and re-checks (`avatarStore.ts:89,92,112,115`) so a
  read started before the wipe cannot write the old identity's photo back. A port needs the
  same reset path, or a fresh identity keeps rendering the previous user's avatar.

### The override branch in HexAvatar (`HexAvatar.tsx:112-171`)

```js
const isMine = myAddress != null && seed.toLowerCase() === myAddress.toLowerCase();
const key = seed.toLowerCase();
const storedRef = isMine ? avatarStore.mine : avatarStore.refs[key] ?? null;
const ref = disableImage ? null : storedRef;
...
if (ref != null && media.status === 'ready') {
  return <Image source={{uri: 'file://' + media.path}}
                style={{width: size, height: size, borderRadius: size * 0.22}} />;
}
// else: fall through to the identicon
```

Rules a port must reproduce:

1. The override keys on the **lowercased seed**. If the seed equals my own address
   (case-insensitive) the ref comes from `mine`; otherwise from the per-address map.
2. Group / mesh / ble seeds never have a pfp, so the lookup returns null and the identicon
   renders unchanged (`HexAvatar.tsx:113-114`).
3. The photo is shown **only when the blob is already downloaded** (`media.status === 'ready'`,
   `HexAvatar.tsx:164`). `useMediaBlob` states are
   `'idle' | 'loading' | 'ready' | 'error' | 'expired'` (`src/native/mediaCache.ts:59-65`);
   every state but `ready` falls through to the identicon (`pfp.ts:8-9`).
4. The photo uses the **same corner radius, `size * 0.22`**, and fills the full square
   (`HexAvatar.tsx:166-169`). No ground colour is drawn behind it, and **no `resizeMode` is
   set** — so it is React Native's default `cover` (centre-crop aspect-fill), *not* `contain`.
5. `disableImage` (`HexAvatar.tsx:105-106,124`) forces the identicon and skips any Storage
   fetch — used inside a storage-off group (#344). ChatScreen passes
   `disableImage={storageOff}` (`ChatScreen.tsx:424,1172`).

### Producing my own avatar (`setAvatar`, `src/stores/chatStore.ts:1054-1102`)

- Guard first: if the node status is not `'running'`, it aborts with an error and never
  opens the picker (`chatStore.ts:1055-1058`).
- Pick a photo, downscaled hard to **256 px / ~50 KB budget**: `ImagePicker.pickImage(256, 50_000)`
  (`chatStore.ts:1061`).
- Saved as JPEG via `ImagePicker.saveBase64Jpeg`, uploaded via
  `Storage.uploadEncrypted(path, '')` → `{cid, key, cap}`; the ref is built at
  `chatStore.ts:1073-1085` as `{cid, key, cap, mime: 'image/jpeg', width, height,
  padded: true}` — `padded: true` because `uploadEncrypted` **always** size-pads (store2,
  `StorageModule.kt:93`) and `mine` is held as this raw ref, never re-parsed from a marker.
- `avatarStore.setMine(ref)` (`chatStore.ts:1086`), then a `pfp1:` marker is broadcast to
  **every Logos-transport conversation** — `(c.transport ?? 'logos') === 'logos'`, because
  mesh/ble peers can't fetch Storage — best-effort per convo, a failure on one does not
  abort the rest (`chatStore.ts:1089-1099`).
- Remove (`clearAvatar`) → `setMine(null)` + the same best-effort `pfp1:clear` broadcast to
  every Logos conversation (`chatStore.ts:1108-1121`).
- Inbound `pfp1:` on a live message → `setContactAvatar(sender, ref)` /
  `clearContactAvatar(sender)` (`chatStore.ts:2266-2281`); history is covered by a
  `foldPfps` pass in ChatScreen (`ChatScreen.tsx:1768-1779`). **My own avatar is never
  re-derived from history** — KV/`setMine` is authoritative so "Remove" sticks
  (`ChatScreen.tsx:1766-1767`).

---

## 7. The lock badge overlay (#344) — part of the component, not the identicon

`HexAvatar.tsx:135-162` (`withLock`), active only when `locked` is true. When `locked` is
false `withLock` returns the avatar **unchanged** — no extra wrapper view at all
(`HexAvatar.tsx:136-138`), so the unlocked render is byte-for-byte the plain avatar.

```
container: {width: size, height: size}    (relative, NO overflow:hidden)
badge: position absolute, bottom: -2, right: -2   // overhangs the avatar box
       width = height = badgeSize = round(size * 0.5)      (HexAvatar.tsx:139)
       borderRadius = badgeSize / 2         // circle
       backgroundColor = colors.accent      // #FF5000  (colors.ts:10)
       borderWidth = 1.5, borderColor = colors.canvas   // #0A0A0A
       alignItems/justifyContent = center
       LockIcon size = iconSize = round(size * 0.38)       (HexAvatar.tsx:140)
       LockIcon color = colors.onAccent     // #FFFFFF (colors.ts:13)
```

`withLock` wraps **both** render paths — the custom-avatar `<Image>` (`HexAvatar.tsx:165`)
and the identicon (`HexAvatar.tsx:186`).

Set for storage-off groups (`ConversationsScreen.tsx:110` `locked={locked}` and `:498`
`locked={rowMenu.isGroup && (storageOff[rowMenu.convoPk] ?? false)}`, `ChatScreen.tsx:1172`
`locked={isGroup && storageOff}`, `ForwardPicker.tsx:48`
`locked={item.isGroup && (storageOff[item.convoPk] ?? false)}`, `GroupInfoScreen.tsx:334`
`locked={storageOff}`).

---

## 8. Second consumer: the QR centre badge (`src/components/QrCard.tsx`)

Uses the *same* `identiconCells`, so any port should share the cell generator.
Geometry in QR-module units, where `total = moduleCount + 2*4` quiet modules
(`QrCard.tsx:17,57,63-71`):

```
backing = total * 0.26          // white outer tile side
b0      = (total - backing)/2
stroke  = backing * 0.08
tile    = backing - stroke      // dark tile side
t0      = (total - tile)/2
inner   = tile * 0.78           // identicon area (the padding rule here)
cell    = inner / 5
i0      = (total - inner)/2
```

- White outer rounded rect: `rx = ry = backing * 0.24` (`QrCard.tsx:105-107`), fill `colors.qrBg = #FFFFFF` (`colors.ts:27`).
- Dark tile: `rx = ry = tile * 0.22`, fill `colors.canvas = #0A0A0A` (`QrCard.tsx:142-144`).
- Cells: `x = i0 + c.x*cell`, `y = i0 + c.y*cell`, `w = h = cell + 0.02` (`QrCard.tsx:149-152`).
- "Badge present" is `badged = badgeSeed != null && badgeSeed.length > 0` (`QrCard.tsx:42`);
  it gates both the EC bump and the whole badge group, and `cells` is `[]` when unbadged
  (`QrCard.tsx:71`).
- Error correction is bumped `'M' → 'H'` when a badge is present (`QrCard.tsx:45`).
- `badgeKind` is typed `'contact' | 'group'` only, default `'contact'` (`QrCard.tsx:23,32`).
  Both resolve to LOGOS_RAMP, so a QR badge is **always orange** — mesh/ble badges are not
  reachable through this component.
- The badge is drawn INSIDE the same `<Svg>` as the modules, whose `viewBox` is
  `0 0 total (total + capUnits)` (`QrCard.tsx:82`); with a `caption` the viewBox grows by
  `capUnits = total * 0.18` **below** the code, which does not move the badge (it is
  centred on `total`, not on the viewBox height).
- A custom avatar photo replaces the cells when `badgeImageUri` is set, clipped to the same
  rounded tile with `preserveAspectRatio="xMidYMid slice"` (`QrCard.tsx:109-133`);
  used at `MyAddressScreen.tsx:148-152`, plain-seed at `AddressModal.tsx:140`.

---

## 9. Step-by-step pseudocode reimplementation

```
CONSTANTS
  N = 5
  GROUND       = "#0A0A0A"
  LOGOS_RAMP   = ["#B8420E","#FF5000","#FF7A33","#FFB27A","#FFE4D0"]
  MESH_RAMP    = ["#166534","#22C55E","#4ADE80","#86EFAC","#DCFCE7"]
  BLE_RAMP     = ["#0B5C8A","#0EA5E9","#38BDF8","#7DD3FC","#E0F5FF"]
  RAMP(kind)   = contact->LOGOS, group->LOGOS, mesh->MESH, ble->BLE
  PREFIX(kind) = contact->"c:", group->"g:", mesh->"m:", ble->"b:"

FUNCTION makeRng(seedString) -> closure returning double in [0,1)
  // all arithmetic on signed 32-bit ints, wrapping; >>> is logical shift
  h := int32(1779033703) XOR int32(utf16Length(seedString))
  FOR each utf16 code unit ch IN seedString:
      h := imul32(h XOR int32(ch), 0xCC9E2D51)     // 3432918353
      h := (h << 13) | (h >>>u 19)
  a := imul32(h XOR (h >>>u 13), 0xC2B2AE35)       // 3266489909
  a := (a XOR (a >>>u 16))                          // JS also >>>0; keep the bit pattern
  RETURN function():
      a := int32(a + 0x6D2B79F5)
      t := imul32(a XOR (a >>>u 15), 1 OR a)
      t := (int32(t + imul32(t XOR (t >>>u 7), 61 OR t))) XOR t
      RETURN uint32(t XOR (t >>>u 14)) / 4294967296.0

FUNCTION identiconCells(seed, kind) -> list of {x, y, fillHex}
  ramp  := RAMP(kind)
  r     := makeRng(PREFIX(kind) + seed)      // NOTE: prefix concatenated, seed NOT lowercased
  cells := []
  FOR x FROM 0 TO 2:                          // outer loop = column
    FOR y FROM 0 TO 4:                        // inner loop = row
      IF r() > 0.5 THEN CONTINUE              // roll 1: empty cell, roll 2 NOT consumed
      idx  := floor(r() * 5)                  // roll 2: colour
      fill := ramp[idx]
      xs   := (x == 2) ? [2] : [x, 4 - x]     // mirror: 0<->4, 1<->3, 2 centre
      FOR each xx IN xs: cells.append({x: xx, y: y, fill: fill})
  RETURN cells

FUNCTION renderHexAvatar(seed, kind, size, customAvatarImagePathOrNull, locked)
  // 1. custom avatar override
  IF customAvatarImagePathOrNull != null AND its blob is fully downloaded:
      draw image at (0,0,size,size), cornerRadius = size * 0.22, aspect fill
      GOTO lockBadge
  // 2. identicon
  draw rounded rect (0,0,size,size), radius = size * 0.22, fill = GROUND, clip to it
  cell := size / 5
  FOR each c IN identiconCells(seed, kind):
      draw axis-aligned rect
          x = c.x * cell,  y = c.y * cell
          w = cell + 0.5,  h = cell + 0.5     // seam guard; clipped by the rounded rect
          fill = c.fill, no stroke, no corner radius
  // 3. optional lock badge
lockBadge:
  IF locked:
      bs := round(size * 0.5)
      draw circle of diameter bs at bottom-right, offset (-2,-2) outside the avatar box
          fill = "#FF5000", border 1.5 px of "#0A0A0A"
      draw lock glyph centred, size = round(size * 0.38), colour "#FFFFFF"

CUSTOM-AVATAR RESOLUTION (feeding the override argument)
  key := lowercase(seed)
  IF myAddress != null AND key == lowercase(myAddress): ref := store.mine
  ELSE:                                                 ref := store.refs[key]  (may be absent)
  IF disableImage (storage-off group): ref := null
```

### Test vectors (generated by running the exact `HexAvatar.tsx` code, re-verified against it)

Grid rendering: `.` = empty (ground), digit = index into `LOGOS_RAMP`. Rows top→bottom,
columns left→right.

`identiconCells("0x1234abcd", "contact")` → RNG seed string `"c:0x1234abcd"`:

```
.0.0.
.....
44344
.....
2...2
```
cells: (0,2)#FFE4D0 (4,2)#FFE4D0 (0,4)#FF7A33 (4,4)#FF7A33 (1,0)#B8420E (3,0)#B8420E
(1,2)#FFE4D0 (3,2)#FFE4D0 (2,2)#FFB27A

`identiconCells("alice", "contact")` → RNG seed string `"c:alice"`:

```
11211
41.14
..2..
.000.
.1.1.
```
cells: (0,0)#FF5000 (4,0)#FF5000 (0,1)#FFE4D0 (4,1)#FFE4D0 (1,0)#FF5000 (3,0)#FF5000
(1,1)#FF5000 (3,1)#FF5000 (1,3)#B8420E (3,3)#B8420E (1,4)#FF5000 (3,4)#FF5000
(2,0)#FF7A33 (2,2)#FF7A33 (2,3)#B8420E

(Emission order in the list is the algorithm's own order — column-major, mirror pair
pushed together. Order only matters for draw-over, and cells never overlap except by the
+0.5 seam, so painting order is cosmetically irrelevant.)

---

## 10. Things that do NOT exist in the source (do not invent them)

- No circle/hexagon clipping anywhere — only `size * 0.22` rounded squares.
- No gap or inter-cell padding in the in-app avatar; no per-cell corner radius.
- No border/stroke around the avatar itself (only the QR badge has a white outer tile, and
  the lock badge has a 1.5 px ring).
- No light-theme variant — `src/theme/colors.ts` is a single dark palette.
- No ramp for a "self / me" kind; my own avatar is just `kind="contact"`.
- No dedicated group colour any more (`HexAvatar.tsx:10-11`); the azure ramp was reassigned
  to BLE in #243.
- No test file covering `identiconCells`. `__tests__/` holds ~44 suites, but
  `grep -rn "identiconCells\|HexAvatar\|Identicon" __tests__/` returns **nothing** — the
  closest neighbours are `pfp.test.ts` (marker codec + `foldPfps`) and `avatarReset.test.ts`
  (`avatarStore.reset`), neither of which exercises the pixel algorithm. So there is no
  golden-vector fixture in the repo to diff a port against; use §9's vectors instead.
