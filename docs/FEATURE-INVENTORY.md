# Peers (logos-chat-android) — Complete Feature + Screen Inventory

Ground truth extracted by reading source at `<logos-chat-android>`
(verified against commit `a4c20c9`; a second adversarial pass re-checked every citation
and quoted string against the files, so line numbers are good to ±2 unless noted).
Every value below is cited as `path:line`. Paths are repo-relative.
Anything I could not find in source is called out explicitly as **NOT IN SOURCE**.

Purpose: turn this into GitHub epics/issues for a desktop QML port.
Epic buckets used: **E1** Core messaging · **E2** Groups · **E3** Contacts & identity ·
**E4** Media & reactions · **E5** Settings & security · **E6** Identity portability ·
**E7** Shell & layout.

---

## 0. App shell (entry point)

`App.tsx` is the root. It is NOT a route — it wraps the navigator.

| Element | Source |
|---|---|
| `GestureHandlerRootView` → `SafeAreaProvider` → `PaperProvider` → `StatusBar` → `RootNavigator` | `App.tsx:161-167` |
| `LockScreen` rendered as an overlay when `hasPin && !unlocked` | `App.tsx:88`, `App.tsx:168` |
| Splash cover (Logo, size 56, `colors.accent`, strokeWidth 2) until security verifiers loaded | `App.tsx:171-175` |
| Boot sequence: `settingsStore.load()` → `securityStore.load()` → `nodeStore.hydrateAddress()` → `avatarStore.hydrate()` → `nodeStore.autoStart()` → `restoreBleEngaged()` | `App.tsx:142-153` |
| Android 13+ `POST_NOTIFICATIONS` runtime request | `App.tsx:28-39`, called `App.tsx:122` |
| Auto-lock on background, grace `LOCK_ON_BACKGROUND_GRACE_MS = 15_000` ms | `App.tsx:80`, `App.tsx:98-119` |

**Epic:** E7 (shell) + E5 (auto-lock).

---

## 1. Navigation map

Stack: `createNativeStackNavigator<RootStackParamList>`, `initialRouteName="Conversations"` (`src/navigation/RootNavigator.tsx:31`, `:154`).

| Route | Params | Header title | Screen file | Registered at |
|---|---|---|---|---|
| `Conversations` | `undefined` | `headerShown: false` | `ConversationsScreen.tsx` | `RootNavigator.tsx:183-187` |
| `Chat` | `{convoPk:number; convoName:string; isGroup?:boolean; draft?:string}` | `route.params.convoName` (replaced by custom `headerLeft`) | `ChatScreen.tsx` | `RootNavigator.tsx:188-192`, types `navigation/types.ts:3` |
| `MyAddress` | `undefined` | `"My Address"` | `MyAddressScreen.tsx` | `RootNavigator.tsx:193-197` |
| `Scan` | `{mode?: 'newChat'\|'addMember'; groupConvoPk?:number} \| undefined` | `"Add Member"` if `mode==='addMember'`, else `"New Chat"` | `ScanScreen.tsx` | `RootNavigator.tsx:198-204`, types `types.ts:10` |
| `NewConversation` | `{address:string; label?:string}` | `"Add Contact"` | `NewConversationScreen.tsx` | `RootNavigator.tsx:205-209` |
| `NewGroup` | `undefined` | `"New Group"` | `NewGroupScreen.tsx` | `RootNavigator.tsx:210-214` |
| `GroupInfo` | `{convoPk:number}` | `"Group Info"` | `GroupInfoScreen.tsx` | `RootNavigator.tsx:215-219` |
| `AddMembers` | `{convoPk:number; postCreate?:boolean}` | `"Add Members"` | `AddMembersScreen.tsx` | `RootNavigator.tsx:220-224` |
| `Contacts` | `undefined` | `"Contacts"` | `ContactsScreen.tsx` | `RootNavigator.tsx:225-229` |
| `About` | `undefined` | `"About"` | `AboutScreen.tsx` | `RootNavigator.tsx:230-234` |
| `Settings` | `undefined` | `"Settings"` | `SettingsScreen.tsx` | `RootNavigator.tsx:235-239` |
| `MeshCore` | `undefined` | `"MeshCore"` | `MeshCoreScreen.tsx` | `RootNavigator.tsx:240-244` — **OUT OF SCOPE** |
| `MeshConfig` | `undefined` | `"Radio config"` | `MeshConfigScreen.tsx` | `RootNavigator.tsx:245-249` — **OUT OF SCOPE** |
| `Nearby` | `undefined` | `"Discovery"` | `NearbyScreen.tsx` | `RootNavigator.tsx:250-254` — **OUT OF SCOPE** |

`LockScreen.tsx` is a screen file but **not a stack route** — it is an absolute-fill overlay (`LockScreen.tsx:153-168`, mounted `App.tsx:168`).

### Navigator-level behaviours (E7)

- Nav state is persisted to native KV under key `'navState'`, debounced 500 ms (`RootNavigator.tsx:39-47`), restored before first render with a 1500 ms timeout fallback (`RootNavigator.tsx:97-112`).
- Deep link: `LogosChat.consumeLaunchConvo()` on nav-ready and on every foreground → navigates to `Chat` (`RootNavigator.tsx:53-68`, `:115-135`).
- On foreground also: `LogosChat.catchupNow()` and `chatStore.replayReaddRequests()` (`RootNavigator.tsx:121-131`).
- Every screen wrapped in `SwipeBackGesture` via `screenLayout` (`RootNavigator.tsx:159-161`) — Android has no native-stack swipe.
- `screenOptions`: header bg `colors.panel`, tint `colors.text`, title `type.title`, `headerShadowVisible:false`, content bg `colors.canvas`, `gestureEnabled:true`, `fullScreenGestureEnabled:true`, `freezeOnBlur:false` (`RootNavigator.tsx:162-182`).
- Nav theme = `DarkTheme` with `primary: colors.accent`, `background: colors.canvas`, `card: colors.panel`, `text: colors.text`, `border: colors.border`, `notification: colors.unread` (`RootNavigator.tsx:70-81`).

---

## 2. Design tokens (needed by every screen)

`src/theme/colors.ts:2-28`:
`canvas #0A0A0A` · `pane #111111` · `panel #161616` · `border #2a2a2a` · `text #FAFAFA` ·
`textDim #6B7280` · `textFaint #4B5563` · `accent #FF5000` · `accentHover #FF7A33` ·
`accentPressed #CC4000` · `onAccent #FFFFFF` · `bubblePeer #1F1F1F` · `unread #EF4444` ·
`pulse #F59E0B` · `nodeOnline #FF5000` · `nodeConnecting #9CA3AF` · `nodeOffline #EF4444` ·
`contact #FF5000` · `verified #1D9BF0` · `errorFill #5c1a1a` · `errorBorder #C62828` ·
`qrBg #FFFFFF` · `qrFg #000000`.

`src/theme/spacing.ts:3-9`: `xs 4, sm 8, md 12, lg 16, xl 24`.
`src/theme/spacing.ts:11-15` radii: `bubble 8, card 8, pill 999`.
`src/theme/spacing.ts:17-22` layout: `bubbleMaxWidthPct '78%'`, `conversationRowHeight 64`, `headerHeight 56`, `minTouchTarget 44`.

**Typography — `src/theme/typography.ts` (the app is MONOSPACE-ONLY; a port that
substitutes a UI sans font will not look like Peers).**
`fonts` (`:5-9`): `regular JetBrainsMono-Regular`, `medium JetBrainsMono-Medium`,
`bold JetBrainsMono-Bold` (bundled in `assets/fonts/`, loaded by exact family name).
`type` scale (`:11-18`): `brand {bold, 16}` (header mark, accent) · `title {medium, 16}`
(screen titles, conversation names) · `body {regular, 14}` (messages, inputs) ·
`label {regular, 12}` (labels, previews, status) · `caption {regular, 10}` (timestamps,
badges) · `code {regular, 13}` (addresses, IDs — selectable).
Screens override `fontSize` locally on the two hero titles: `LockScreen` title 22
(`LockScreen.tsx:170`) and `AboutScreen` name 24 (`AboutScreen.tsx:249`).

Non-token literals that appear in screens (transport colors — mesh/BLE are out of scope but the constants leak into in-scope files):
`MESH_GREEN '#22C55E'` (`ChatScreen.tsx:155`, `ConversationsScreen.tsx:49`, `GroupInfoScreen.tsx:28`, `ContactsScreen.tsx:39`),
`BLE_BLUE '#0EA5E9'` (`ChatScreen.tsx:173`, `ConversationsScreen.tsx:51`, `AddMembersScreen.tsx:48`),
`LINK_BLUE '#4EA3FF'` (`ChatScreen.tsx:158`).

Identicon ramps, `src/components/HexAvatar.tsx:26-30`:
`LOGOS_RAMP ['#B8420E','#FF5000','#FF7A33','#FFB27A','#FFE4D0']` (`:26`),
`MESH_RAMP ['#166534','#22C55E','#4ADE80','#86EFAC','#DCFCE7']` (`:28`),
`BLE_RAMP ['#0B5C8A','#0EA5E9','#38BDF8','#7DD3FC','#E0F5FF']` (`:30`).
Avatar = 5×5 left-right-symmetric grid of flush squares, seeded by peer address (1:1) or shared lib conversation id (group) (`HexAvatar.tsx:3-14`, seed resolver `avatarSeed()` `:205-215`, kind resolver `convoKind()` `:220-230`).

**The identicon algorithm is load-bearing — it must be ported 1:1 or two devices draw
different avatars for the same identity** (`HexAvatar.tsx:43-93`):
`rng(seed)` = xmur3 hash (`h = 1779033703 ^ len`, `Math.imul(h ^ charCode, 3432918353)`,
rotate 13) → mulberry32; it is seeded with `PREFIX[kind] + seed`, where
`PREFIX = {contact:'c:', group:'g:', mesh:'m:', ble:'b:'}` (`:41`) — so the same address
yields a different grid per kind. `AVATAR_N = 5` (`:61`). For `x` in 0..2 and `y` in 0..4:
draw `r()`; `> 0.5` → leave the cell empty (ground shows through), else fill with
`ramp[floor(r() * 5)]` and mirror column `x` to `AVATAR_N-1-x` (column 2 is the centre,
not mirrored) (`:80-91`). Cells render as `Rect`s of `size/5 + 0.5` (the +0.5 overlap
kills anti-aliasing seams), inside a `size*0.22`-radius box over `colors.canvas`
(`:173-199`). A custom avatar image (`pfp1:`) replaces the identicon entirely when
present, same corner radius (`:164-171`); `disableImage` forces the identicon (storage-off
groups), and `locked` overlays a bottom-right lock badge sized `0.5×`/icon `0.38×` in
`colors.accent` with a 1.5px `colors.canvas` ring (`:135-162`).

---

## 3. Screen-by-screen inventory

### 3.1 `ConversationsScreen` — route `Conversations` (root)
File: `src/screens/ConversationsScreen.tsx` (603 lines). **Epic: E7 + E1.**

**Purpose:** durable conversation list from SQLite, with side-menu filters and a context-aware FAB (`ConversationsScreen.tsx:1-3`).

**Layout / UI elements**
- Header, height `layout.headerHeight` (56), bg `colors.panel`, 1px bottom border (`:517-526`): left = my `HexAvatar` size 32 seeded by `myAddress` (opens SideMenu, `:408-413`); absolutely-centred title = `VIEW_TITLE[view]` (`:404-407`, map at `:172-179`); right slot `minWidth 50, height 34` holding `TransportPill` (`:416-418`, `:542-547`).
- Row: height 64 (`layout.conversationRowHeight`), bg `colors.pane`, `paddingHorizontal spacing.lg`, `gap spacing.md` (`:551-558`). Contents: `HexAvatar` size 32 (with `locked` badge when storage-off group), title (`type.title`, lineHeight 18), `VerifiedBadge` size 14, group glyph + member count, preview line + right-aligned time, `UnreadBadge` (`:98-169`).
- Time format: same day → `HH:MM`; otherwise `MM-DD` (`:53-68`).
- Preview falls back to `'new group'` / `'new conversation'` (`:160`); system-note previews render italic `colors.textFaint` (`:563`).
- Separator 1px `colors.border` (`:598`); list `paddingBottom: 88` (`:549`).
- Empty states, one per filter view (`:420-435`).
- `SwipeRow` wraps every row = swipe-left-to-delete, gesture-committed, haptic at arm threshold, no confirm dialog (`:442`, component `src/components/SwipeRow.tsx:1-6`).
- `SpeedDialFab` bottom-right (`:466-470`); Logos actions = `Contact` → `Scan`, `Group` → `NewGroup` (`:378-395`). FAB geometry: 56×56, radius 28, `right: spacing.lg`, `bottom = safe-area bottom inset + spacing.lg`, elevation 6, `+` glyph fontSize 32; mini action rows stack 44 + 12 apart above it, over a `rgba(0,0,0,0.6)` backdrop (`SpeedDialFab.tsx:232`, `:264`, `:274`, `:289-318`).
- `ErrorToast` (`:510`).
- The long-press row menu carries a header (avatar 32 + name + `VerifiedBadge` 14) above its items (`:491-508`).
- Every row is one composed TalkBack label from state via `conversationA11yLabel(convo, {locked, isBle})` — name + type + unread + key states, never the full address, no message preview (`:97`, `:104-107`). Rows/controls throughout the app carry `testID`s (`convo-<pk>`, `open-menu`, `row-menu`, `fab-contact`, `fab-group`); keep them if the port reuses the e2e suite.

**User actions**
1. Tap row → `navigation.navigate('Chat', {convoPk, convoName, isGroup})` (`:257-265`).
2. Long-press row (300 ms, `Vibration.vibrate(18)`) → `OverflowMenu` anchored at tap Y (`:269-273`, `:484-509`). Items: group → `Open` / `Group info` / `Delete conversation`(destructive); 1:1 → `Open` / `Delete conversation` (`:275-314`).
3. Swipe row left → delete (`:442`).
4. Tap avatar → SideMenu (`:408-413`).
5. Tap `TransportPill` → TransportsModal (**partly out of scope**, see §6).
6. FAB → Contact / Group.

**Backend calls:** `chatStore.refreshConversations()` on focus (`:316-320` → `LogosChat.listConversations()` `chatStore.ts:624`), `chatStore.remove(convoPk)` (`:248-255` → `LogosChat.deleteConversation` `chatStore.ts:1808`).

---

### 3.2 `ChatScreen` — route `Chat`
File: `src/screens/ChatScreen.tsx` (3170 lines — the biggest surface). **Epic: E1 (core), E4 (media/reactions), E2 (group affordances).**

**Purpose:** inverted message thread over durable SQLite history; peer bubbles left, own right; optimistic `pending` (dimmed); failed bubbles tap-to-retry; **no delivered ticks** (`ChatScreen.tsx:1-3`).

#### Header (custom `headerLeft`, `:1147-1314`)
- One left cluster: back chevron + `HexAvatar` size 28 + title column (`:1152-1195`), `marginLeft: -spacing.sm`, `maxWidth 300` (`:2863-2869`).
- Group: name + `"N members"` / `"1 member"` subtitle, hidden until roster hydrates (`:1186-1192`).
- 1:1 labelled: nickname + `VerifiedBadge` size 14, sub-line = `shortAddress` (`:1207-1231`).
- 1:1 unlabelled: short hex as primary (`:1234-1240`).
- Last-seen line from `formatLastSeen(convo.lastInboundAt, Date.now())` (`:1253-1264`).
- `headerRight` = ellipsis (size 22) → thread overflow menu (`:1293-1301`).
- Header hidden while the media viewer is open (`:893-898`).

#### Thread body
- `FlatList inverted`, rows are a merged, time-sorted union of `{kind:'msg'}`, `{kind:'sys'}`, `{kind:'media'}` (`:87-90`, `:1815-1835`).
- Control markers are never rendered as bubbles — filtered by `isFoldedMarker` (`:1820`).
- Older history: `onEndReached` at threshold 0.4 → `loadMoreMessages` (`:1453-1455`, `:2151-2152`); footer spinner while `loadingMore` (`:2153-2159`).
- Empty list uses a `flex:1` spacer so the composer can't collapse (`:2143-2147`, `:2773-2774`).

#### Bubble (`:330-634`)
- `bubbleWrap` maxWidth `78%`, gap 2 (`:2777`); radius 8; padding `spacing.md` × `spacing.sm` (`:2780-2784`).
- Own = `colors.accent` fill, peer = `colors.bubblePeer` (`:2785-2786`); pending opacity `0.55` (`:2787`); failed = 1px `colors.unread` border (`:2788`); image bubble = 2px frame, `overflow hidden` (`:2792`).
- Attribution row above incoming bubbles: `HexAvatar` size 16 + label (white) + hex (dim) + `VerifiedBadge` size 12 (`:422-441`).
- Time row shows `'sending…'` / `'failed — tap to retry'` / `HH:MM` (`:624-630`, formatter `:185-190`).
- Reaction pills at the bubble's lower corner, own=right/peer=left; tap yours = remove, tap another = add; long-press = who reacted (`:599-615`).
- Quoted-reply header with a coloured left bar, tap → jump to original (`:470-487`).
- Link runs: `linkify()` split, underlined; own bubble links `colors.onAccent`, peer links `#4EA3FF` (`:580-596`).
- Image bubble sizing: fit inside `IMG_MAX_W 230` × `IMG_MAX_H 300`, aspect preserved (`:143-152`).
- Media states: `loading` → `ActivityIndicator`; `expired` → `'media expired'`; `error` → `'media unavailable'` (`:529-549`).
- Video bubble: first frame paused + play badge; tap → fullscreen (`:508-521`).
- Voice bubble → `VoiceBubble` (`:560-565`). Location bubble → `📍 <lat,lng>` + "Tap to open in maps" (`:566-578`).
- Shared-contact card (`addr1:`) renders as an `AddressCard` with **Add** and **View** (`:2046-2063`).

#### Composer (`:2305-2492`)
- Two-line composer: growing `TextInput` (multiline, `maxHeight 120`, radius 8, `colors.canvas` bg) + circular Send; then an action-icon row (`:2426-2491`, styles `:2932-2943`).
- Action row buttons, all size 22, `colors.textDim`: photo (`composer-image`), camera (`composer-camera`), location (`composer-location`), `GIF` text button, video/film, mic (`:2461-2484`).
- Send button colour follows `deriveComposerState().sendColorKind` → mesh green / BLE blue / `colors.accent` / `colors.nodeConnecting` / `colors.nodeOffline` (`:1339-1348`); pulses (opacity 1 ↔ 0.45, 700 ms each way) while connecting (`:1351-1369`).
- Disabled send = `colors.border` fill (`:2439`).
- Reply banner with clear ✕ (`:2308-2327`).
- Staged image tray: horizontal scroll of removable thumbnails, cap `MAX_STAGED_IMAGES = 10` (`:169`, `:2339-2365`).
- **HQ toggle** next to the tray: dark gray off / orange on; disabled in a storage-off group (`:2366-2383`, state `:722-723`).
- Staged video: poster thumbnail + play badge + ✕ (`:2386-2410`).
- Staged location chip: pin icon + `formatLatLng` + ✕ (`:2411-2425`).
- Storage-off group hides GIF + video buttons and shows `Storage off — text & voice only` (`:2470-2489`).
- Draft persistence per conversation via `composerDraftStore` (`:762-766`), restored on mount (`:708-719`).

#### Voice recording bar (`:2246-2273`)
- Live waveform `RECORD` row: 48 bars (`REC_WAVE_BARS = 48`, `:258`), floor `0.12` (`:265`), max height 26 px (`:268`), amplitude fallback after 500 ms (`:261`), colours `<0.4 #22C55E`, `<0.7 #EAB308`, else `#FF7A33` (`:321`).
- Controls row: red dot, `M:SS / <cap>` timer, Cancel, Send (`:2251-2272`).
- Cap = `MAX_RECORDING_MS` from `src/native/Audio.ts`; auto-finalise on `maxDuration` event (`:1584-1586`).
- Minimum length to send: `rec.durationMs >= 800` else toast `'Too short'` (`:1631-1634`).
- Requires `RECORD_AUDIO` runtime permission (`:1594-1604`) and a running node (`:1608-1611`).

#### Thread overflow menu (`:1091-1145`)
- **Group:** `Add members` → `AddMembers`; `Group info` → `GroupInfo`; `Wipe group` (destructive); `Leave group` (destructive).
- **1:1:** `Add label`/`Edit label`; `Show address` (opens `AddressModal`); `Delete conversation` (destructive).

#### Confirm dialogs (exact copy is load-bearing)
- Delete conversation: title `'Delete conversation'`, body `'Delete this conversation and all its messages?'` (`:937`).
- Wipe group: `'Wipe group'` / `'Wipe this group from this device? All its messages will be deleted here. You will still receive new messages — wiping does not remove you from the group.'` (`:954-957`).
- Leave group: `'Leave group'` / `"Leave this group? Its messages are deleted from this device and it's hidden for good. The other members are told you left. You cannot rejoin unless someone re-invites you into a new group."` (`:979-982`).
- Delete message: `'Delete for me?'` / `'This removes the message from this device only. The other person still has their copy.'` (`:2579-2581`).

#### Banners / system UI
- Unverified trust strip for an unverified 1:1: `'⚠ Unverified — this identity isn’t confirmed. Verify out of band before sharing anything sensitive.'` (note: the source uses a **typographic** apostrophe in `isn’t`, `:1849`) + a `Verify` action that opens `LabelModal` for the peer; bg `#F59E0B22`, bottom border `#F59E0B` (`:1846-1864`, `:2759-2770`).
- Pinned-message bar: pin icon size 16 `colors.accent`, one-line preview (`📷 Photo` / `🎤 Voice message` / `📍 Location` / text), creator-only unpin ✕ (`:1934-1973`).
- Dead-group footer: `'Group ended when the app restarted'` system line (`:2162-2166`); creator gets `Restart group`, member gets `Ping creator` + explanatory hint; an (i) opens the "Restarting a group" `InfoModal` (`:2172-2245`, modal copy `:2707-2733`).
- Invited-wait `InfoModal` "Adding a member" (`:2735-2750`).
- System-line actions: `Re-invite` on `join-failed`; `Ask to be re-added` on `desynced` → `requestReadd` (`:2006-2038`).

**Backend calls (chatStore actions consumed, `:640-693`):** `loadMessages`, `loadMoreMessages`, `send`, `sendReaction`, `pinMessage`, `sendImage`, `sendGif`, `stageVideo`, `sendStagedVideo`, `stageImages`, `stageCameraPhoto`, `sendStagedImages`, `fetchLocation`, `sendLocationValue`, `sendVoice`, `retry`, `setActive`, `setNickname`, `setVerified`, `wipe`, `leaveGroup`, `setMemberStatus`, `remove`, `deleteMessage`, `startConversation`, `probeGroup`, `hydrateSystemLines`, `hydrateGroupStorage`, `recreateGroup`, `addMember`, `requestReadd`, `loadMembers`, `forwardMessage`.
Direct native: `LogosChat.groupCreator(convoPk)` for "Ping creator" (`:2209`), `Storage.downloadDecrypt(cid, key, cap, padded)` for "Save to phone" (`:2569`), `ImagePickerNative.saveImageToGallery` / `saveMediaToGallery` (`:2557`, `:2570`, `:862-867`), `MediaShare.shareFile(path, mime)` (`:886`).

---

### 3.3 `MyAddressScreen` — route `MyAddress`
File: `src/screens/MyAddressScreen.tsx` (311 lines). **Epic: E3.**

**Purpose:** show my stable hex account address as a QR + hex + Copy. There is deliberately **no Refresh** — the address is stable (`:1-4`).

**UI:** card (`colors.panel`, 1px border, radius 8, padding `spacing.xl`) with `QrCard size={260}`, badge seeded by `myAddress`, badge image = my custom avatar when available, caption `"peers.tech"` (`:141-155`). Below: selectable full hex in `type.code` (`:156-158`); a `Copy`/`Share` button row, each `flex:1`, minHeight 44 (`:159-178`, styles `:283-309`); an opt-in `Include my label in QR` `Switch` (only when a display name is set) with the caution `'Might be incompatible with other apps using Logos Messaging.'` (`:181-199`); a full-width bordered `Send` button → `ForwardPicker` (`:201-206`).
Waiting state text: `'reading address…'` when running else `'node starting…'` (`:133-136`). Hint at bottom (`:210-213`).

**Actions:** Copy (clipboard, label flips to `Copied` for 1600 ms, `:69-75`, `:163-169`); Share (`:89-124`) — captures the QR `<Svg>` to base64 PNG (`toDataURL`, no `data:` prefix) with a 4000 ms timeout and calls `LogosChat.shareIdentityImage(b64)`, falling back to RN `Share.share({message: payload, title: 'My address'})` where `payload` is the same string the QR encodes (`:120`); toggle label-in-QR; Send → pick a conversation → `chatStore.send(pk, encodeAddr(...))` then navigate into that Chat (`:216-239`).

**Backend calls:** `nodeStore.fetchAddress()` (`:63-67`), `LogosChat.shareIdentityImage` (`:113`), `chatStore.send` (`:221-227`).

---

### 3.4 `ScanScreen` — route `Scan`
File: `src/screens/ScanScreen.tsx` (303 lines). **Epic: E3.**

**Purpose:** scan or paste a peer's 64-hex address. Two modes: `newChat` (default) → `NewConversation`; `addMember` → `chatStore.addMember(groupConvoPk, addr)` then `goBack()` (`:1-5`, `:51-76`).

**UI:** full-bleed `react-native-vision-camera` preview with `useCodeScanner({codeTypes:['qr']})` (`:78-91`); overlay bracket box `BRACKET = 240` (`:35`) with four corners `CORNER 28` / `THICK 3` (`:231-232`), colour `colors.accent`, styles `:249-259`; caption `"scan a contact's address QR"` (`:132`); inline invalid message auto-clears after 2500 ms (`:104-110`); `Paste Address Instead` link (`:136-143`).
Paste card (always reachable): monospace multiline input `minHeight 72`, placeholder `'64-hex address…'`, `Use Address` primary + `Back to Camera` secondary (`:186-227`).
Permission-denied path lands directly on paste mode with rationale copy (`:93-102`, `:152-166`).

**Validation:** `parseAddressPayload()` accepts a bare address **or** a `peers:<addr>?label=…` URI, returns the address **verbatim without validating it**, and clamps a scanned label to `MAX_LABEL_LEN = 64` chars after `decodeURIComponent` (a QR is untrusted input); malformed percent-encoding drops the label and keeps the address (`:82-88`, `src/lib/addressPayload.ts:15-18`, `:41-70`).
`isAddress(s)` = `/^[0-9a-fA-F]{64}$/.test(s.trim())` — **case-INsensitive and trimming**, despite the doc comment saying "lowercase" (`src/native/LogosChat.ts:298-301`). Lowercasing is a separate step, `normalizeAddress()` (`:303-305`), which `accept()` applies before use (`ScanScreen.tsx:60`). A port that rejects uppercase hex would refuse valid QRs.
Valid scan → `Vibration.vibrate(60)`, and an `acceptedRef` latch makes accept idempotent so a repeating QR frame can't double-navigate (`:49`, `:55-59`).

**Backend calls:** `chatStore.addMember` in addMember mode (`:62`).

> Desktop note: camera QR scanning may not port. The paste path is the fallback that already exists in source.

---

### 3.5 `NewConversationScreen` — route `NewConversation`
File: `src/screens/NewConversationScreen.tsx` (201 lines). **Epic: E3.**

Confirm a scanned/pasted address, optionally label it, then create the 1:1 and open it (`:1-2`).

**UI:** address card with `HexAvatar` size 40 + selectable address (`:68-79`); `Node connecting…` note when not running (`:81-85`); label field (`autoFocus`, placeholder `'e.g. Alice'`) with helper `'Only you see this — it never leaves your device.'` (`:87-103`); **Verified checkbox**, 24×24, radius 6, 1.5px border, checked fill `colors.verified` (`:106-120`, `:180-190`) — explicitly unchecked by default because a QR can be scanned off a web page (`:104-105`, `:36`); primary `Add contact` button (`:121-133`); `Opening conversation…` busy line (`:134-138`).

**Backend:** `chatStore.startConversation(address, {nickname, verified})` (`:49-52` → `LogosChat.createConversation` `chatStore.ts:693`, `LogosChat.setVerified` `chatStore.ts:699`), then `navigation.replace('Chat', …)` (`:54-58`).

---

### 3.6 `NewGroupScreen` — route `NewGroup`
File: `src/screens/NewGroupScreen.tsx` (201 lines). **Epic: E2.**

**UI:** `Group name` (autoFocus) and `Description (optional)` (multiline, minHeight 72) laid directly on the page with white capitalized labels (`:86-111`); a **Media via Storage node** `Switch` (ON by default; local state is inverted `storageOff`) with an (i) → `StorageInfoModal` (`:115-144`); full-width `Create group` CTA, minHeight 48 (`:145-155`); busy line `'Creating group (MLS)…'` (`:156-160`); footer `'Next: invite members to the group.'` (`:161-163`).
Not-running banner shows `radioRefusal ?? 'Node not running — start it in settings first'` (`:79-83`).
`canCreate = running && !busy && name.trim().length > 0` (`:51`).

**Flow:** `createGroup(name, description)` (`chatStore.ts:707` → `LogosChat.createGroup`), then optional `setGroupStorage(convoPk, true)` broadcasting a `gcfg1:` marker (`:63-65`), then `navigation.replace('AddMembers', {convoPk, postCreate: true})` — `replace` so Back can't resubmit (`:66-69`).

---

### 3.7 `AddMembersScreen` — route `AddMembers`
File: `src/screens/AddMembersScreen.tsx` (458 lines). **Epic: E2.**

**Purpose + two entry points** documented at `:1-14`: from Group info → submit does `goBack()`; `postCreate: true` (straight off New Group) → submit `replace`s into the group's Chat and an extra `Skip for now` button appears.

**UI:** header (`colors.panel`, 1px bottom border) with `Add to <groupName>` (`:282-285`); paste row = 64-hex `TextInput` with an inline `Paste` link + a secondary `Add` button disabled until `isAddress(field)` (`:298-332`); `⧉ Scan QR` row → `Scan` in `addMember` mode (`:339-349`); checkbox list of known contacts (avatar 32, two-line label/hex, `VerifiedBadge` 14, checkbox 24×24 radius 6 border 2, checked fill `colors.accent`) (`:223-278`, `:438-448`); bottom-stuck footer with `Skip for now` (postCreate only) + `Add to group` (`:365-382`).
Empty list copy: `'No known contacts yet — paste or scan an address above.'` (`:358-362`).
Staged (pasted/scanned) addresses are prepended and auto-checked (`:139-149`).

**Submit** (`:159-217`): iterates every checked address calling `chatStore.addMember(convoPk, address)`; keeps going on failure and never claims success for a failed member; maps the "group from an earlier session" lib error (`/was not found|cannot be rebuilt|no load path/i`) to plain language (`:189-193`); failures land in `nodeStore.error` joined by `' · '` and, when **nothing** was added, the screen stays put so the user can retry (`:197-205`); on ≥1 success it toasts `'Member has been added'` / `'Members have been added'` (`:207-210`) and then `replace`s into Chat (postCreate) or `goBack()`s (`:211-215`).

**Backend calls:** `loadMembers` (`:94-96`), `addMember` (`:181`).

---

### 3.8 `GroupInfoScreen` — route `GroupInfo`
File: `src/screens/GroupInfoScreen.tsx` (567 lines). **Epic: E2.**

**UI:**
- Header block (`colors.panel`, bottom border): group `HexAvatar` size 48 seeded by `convo.libConvoId` with `locked` when storage-off (`:330-335`); tappable name → inline rename `TextInput` (`:337-357`); `N members` line (`:358-360`); `Tap the name to rename it on this device.` hint when the real name is unknown (`:375-379`).
- **Storage row**: creator sees a `Switch` (value = `!storageOff`) with an (i) → `StorageInfoModal`; non-creators see a read-only `Storage: off` row only when it is off (`:388-435`). Exact sublabels quoted at `:405-407`.
- Roster `FlatList`: avatar 32, label/hex two-line identity, `VerifiedBadge` 14, `You` for self (`:143-210`); self rows are non-pressable (`:150`). Empty: `'no members recorded on this device yet'` (`:443-447`).
- Footer: primary `Add members` → `AddMembers`, plus the caption `'adding sends an MLS Welcome; the member appears in their conversations list.'` (`:450-460`).

**Member menu** (tap or long-press with `Vibration.vibrate(18)`, anchored at tap Y — `:148-169`, items `:213-291`): `Add label`/`Edit label` · `Copy address` · `Send message` · `Map to mesh` (**out of scope**) · **creator-only** `Remove from group` (destructive) gated by `canRemoveMember({createdByMe, isSelf})` from `src/security/groupRemoval.ts` (`:258-262`). Removal confirm copy: `'Remove from group?'` / `"<name> will lose access to new messages. This can't be undone from their side — they'd need to be re-added."` (`:271-272`).

**Backend calls:** `loadMembers` (`:109` → `LogosChat.listGroupMembers` `chatStore.ts:879`), `hydrateGroupStorage` (`:111`), `removeMember` (`:279` → `LogosChat.removeGroupMember` `chatStore.ts:772`), `setNickname` (`:102`, `:317`), `setVerified` (`:317`), `setGroupStorage` (`:413`), `startConversation` (`:303`, `:318`).

---

### 3.9 `ContactsScreen` — route `Contacts`
File: `src/screens/ContactsScreen.tsx` (457 lines). **Epic: E3.**

**Purpose:** flat list of PEOPLE (distinct from conversations); source = `knownContacts()` = every 1:1 peer address + any address seen in group rosters (`:1-4`, `:54`).

**UI:** search field (`'Search contacts…'`, filters by label + hex, case-insensitive) (`:258-271`); **Labeled / Seen tabs** with counts, default `labeled`; "labeled" = has a label or is verified (`:63-72`, `:272-290`); rows = avatar 32 + label/hex + `VerifiedBadge` (`:170-246`); separator 1px with `marginLeft: spacing.lg` (`:454`).
Empty copy variants at `:250-255` and `:298-308` (`'no labeled contacts yet — label someone in Seen to keep them here'`, `'no one seen yet'`).

**Long-press menu** (300 ms, `Vibration.vibrate(18)`, anchored at tap Y, with an avatar+name header — `:174-181`, `:312-332`): `Send message` · `Add/Edit label` · `Show address` (→ `AddressModal`) · `Copy address` · `Map to mesh` (**out of scope**).

**Backend calls:** `setNickname` / `setVerified` / `startConversation` in `saveContactLabel` (`:85-102`); `chatStore.send(pk, encodeAddr(address,label))` when sharing a contact card (`:349-354`).

---

### 3.10 `SettingsScreen` — route `Settings`
File: `src/screens/SettingsScreen.tsx` (536 lines). **Epic: E5.**

Sections in render order (`:198-389`):

**Notifications** (5 `ToggleRow`s — label + sublabel + `Switch` with `trackColor {false: colors.border, true: colors.accent}`, `thumbColor colors.text`, `:87-93`):
| Row | Sublabel | Default | testID |
|---|---|---|---|
| Local notifications | `Alerts while the app is in the background` | `true` | `setting-notif-local` |
| In-app notifications | `Banners for other chats while the app is open` | `true` | `setting-notif-inapp` |
| Message sound | `Play a sound on a new message` | `true` | `setting-notif-sound` |
| Vibration | `Vibrate on a new message` | `true` | `setting-notif-vibrate` |
| Show message content | `Off keeps notifications generic (New message). The lock screen never shows content.` | `false` | `setting-notif-content` |
(rows `:203-241`; defaults `src/stores/settingsStore.ts:206-210`; KV keys `settingsStore.ts:100-103`.)

**Network** (`:244-287`): `Delivery node` monospace multiline input (minHeight 64) pre-filled with
`DEFAULT_NODE = '/dns4/msg.logos.live/tcp/30304/p2p/16Uiu2HAmNdX1s7wRhygyWKmYiUst84329TSz3byLEP6FjcoxDbH4'` (`:35-36`), KV key `'deliveryServiceNode'` (`:38`); `Use default` + `Save` buttons (`:258-272`); helper text (`:274-278`); link `How to run your own node ↗` → `https://github.com/xAlisher/peers/blob/main/docs/running-your-own-node.md` (`:279-287`). Save toasts `'Node saved — restart the app to apply'` (`:166`).

**Privacy** (Tor) — gated OFF by `TOR_TOGGLE_READY = false` (`:62-65`, `:291-308`). **OUT OF SCOPE** (§6).

**Security** (`:310-384`):
- `Set PIN` / `Change PIN` row, value `On`/`Off` → `PinFlowModal` mode `setMain` (`:312-317`).
- `Remove PIN` row (only when a PIN exists) → mode `removeMain` (`:318-327`).
- Two helper paragraphs, quoted verbatim at `:329-338` — including the honest scope statement that the PIN is a screen lock, not disk encryption.
- `Lock when app goes to background` toggle (default `false`), sublabel `'Ask for the PIN again when you return after a short while.'` (`:342-350`).
- `Set wipe PIN` / `Change wipe PIN` (duress) → `PinFlowModal` mode `setDuress` (`:353`); `Remove wipe PIN` bypasses the modal and calls `securityStore.removeDuressPin()`, toasting `'Wipe PIN removed'` (`:362`, `:179-182`); explanation copy at `:369-373`. Both this and the lock-on-background toggle above render only when a main PIN exists — one `{hasPin && …}` wraps them (`:340`).
- Danger zone card (`colors.errorBorder` border): `Reset identity and data` in `colors.unread` (`:377-384`) + helper (`:385-388`).
- Reset confirm `Modal`: title `'Reset identity and data?'`, body at `:409-413`, `Cancel` / `Reset` (`Reset` styled `backgroundColor: colors.unread`), `Resetting…` spinner state (`:401-437`).

**Backend calls:** `LogosChat.getSetting/setSetting` for the delivery node (`:156`, `:165`); `securityStore.wipeAndReset()` then `chatStore.refreshConversations()` (`:184-196`).

---

### 3.11 `LockScreen` — overlay (not a route)
File: `src/screens/LockScreen.tsx` (185 lines). **Epic: E5.**

**Purpose:** cold-launch PIN gate; correct PIN unlocks, duress PIN silently wipes + re-identifies and then unlocks indistinguishably, 3 wrong attempts reveal the "Create new identity" wipe (`:1-6`).

**UI:** absolute fill, `zIndex/elevation 100`, `colors.canvas`, centred, `gap spacing.xl` (`:152-168`); hero = my `HexAvatar` size 56 (or `Logo` 48, accent, strokeWidth 2, when no address), title `Enter PIN` (`type.brand`, fontSize 22, `:170`), subtitle = `'Unlock to continue'` by default, swapping to `'Too many attempts.'` (locked out) or `` `Incorrect PIN — N tries left` `` (`try`/`tries` pluralised) (`:100-116`); `PinPad` (`:141-146`); on lockout a warn card (`colors.errorBorder`) whose body names `MAX_PIN_ATTEMPTS` + a `Create new identity` button styled `colors.unread` (`:122-139`, styles `:174-184`). The explicit wipe button **does** show progress (`busy` → `'Preparing…'`) — only the duress path is covert (`:118-121`).
Wrong PIN: dots flash red for 500 ms then clear, attempt count preserved (`:86-92`).
Duress path deliberately shows **no spinner and no error**, and unlocks *first*, wiping behind the already-dismissed gate — a tell would betray it (`:67-84`).

**Security constants** (`src/security/pinSecurity.ts`): `PIN_LENGTH = 6` (`:207`), `PIN_ITERATIONS = 10_000` (`:232`), `MAX_PIN_ATTEMPTS = 3` (`:235`); `isValidPin` = exactly `PIN_LENGTH` ASCII digits (`:248-251`). Verifier = PBKDF2-HMAC-SHA256(pin, salt, iters) truncated to 32 bytes, serialised as `{v:1, iters, salt, hash}` (`:258-266`), compared with `constantTimeEqual` (`:268-275`) from `verifyPin` (`:278-282`); `parseVerifier` defaults a missing `iters` to `PIN_ITERATIONS` (`:285-296`). Salt = **16 bytes** (`SALT_BYTES`, `src/stores/securityStore.ts:25`) from `LogosChat.secureRandomHex(byteLen)` (`securityStore.ts:34`; native contract `src/native/LogosChat.ts:264-268`), with a JS fallback if the native call fails (`securityStore.ts:36-40`).
The attempt/duress decision itself is a pure function, `evaluateGateAttempt(gate, pin, inputs) → {outcome: 'unlock'|'duress'|'wrong'|'lockout', state}` (`LockScreen.tsx:62`) — port it as a unit, not as inline branching.

---

### 3.12 `AboutScreen` — route `About`
File: `src/screens/AboutScreen.tsx` (288 lines). **Epic: E6 (+E3 for identity display).**

**UI:** hero = my `HexAvatar` size 56 (fallback `Logo` 56), name `peers` (`type.brand`, fontSize 24), version row `v<name> (<code>)` + an `ALPHA` pill outlined in `colors.accent` (`:130-147`); blurb with per-transport colouring — Logos `colors.accent`, MeshCore `#22C55E`, Bluetooth mesh `#0EA5E9` (`:149-154`, `:262-264`); `this device` card with avatar 40 + short address (`:156-166`).

**Rows (each a bordered card, `linkRow` `:276-283`):**
1. `Add my identity to the home screen` → `LogosChat.pinIdentityShortcut()`; `'unsupported'` and throw both toast the MIUI guidance (`:109-125`, `:168-179`).
2. `Source & issues` → `https://github.com/xAlisher/peers` (`:25`, `:181-189`).
3. `Back up identity + chats` → `BackupPassphraseModal` → `LogosChat.exportChatData(passphrase)`; toast `'Encrypted backup saved'` / `'Backup failed'` (`:49-65`, `:193-207`). Helper copy at `:201-206` states the PIN is not included and the passphrase is unrecoverable.
4. `Restore from backup` → passphrase first (JS modal), then `ImagePicker.pickAndImportBackup(passphrase)`; on success resets + rehydrates `avatarStore` and calls `LogosChat.catchupNow()`; three outcomes handled via `restoreFailed` / `restoreSucceeded` from `src/lib/restoreOutcome.ts` — a retryable failure keeps the modal open (`:72-105`, `:211-223`).

**Backend:** `LogosChat.getAppVersion()` (`:34`), `pinIdentityShortcut` (`:110`), `exportChatData` (`:57`), `ImagePicker.pickAndImportBackup` (`:84`), `LogosChat.catchupNow` (`:94`).

Backup format facts: `exportChatData(passphrase)` = PBKDF2 → AES-GCM, passphrase min length 8, and the envelope also carries the 64-byte identity seed so restore keeps the same address (`src/native/LogosChat.ts:282-290`). `importChatData(uri, passphrase)` is **destructive** — replaces the identity, then reopens the node (`LogosChat.ts:286-290`).

---

### 3.13 `SideMenu` — overlay (not a route), the app's primary navigation surface
File: `src/components/SideMenu.tsx` (566 lines — the largest component). **Epic: E7 (+E3 for the identity header).**

Opened by tapping my avatar in the Conversations header; there is **no drawer-navigation
dependency** — it is a self-animated `Modal` (`SideMenu.tsx:1-5`). Everything the app has
that is not a conversation is reached from here, so a port without it has no route to
Contacts / Settings / About / My address.

- Panel width `min(320, 82% of window)`, slides in via `translateX` from `-panelW`, 200 ms `Easing`, over a dim backdrop `Animated.View` whose opacity follows the same driver; tap-outside closes (`:188`, `:246-248`, `:283-300`).
- Header (pinned, does not scroll): my `HexAvatar` (tap → avatar Change/Remove `OverflowMenu`, pencil badge 18×18 radius 9 `colors.accent` with a 1.5px `colors.canvas` ring — `:304-318`, `:514-528`); my **display name**, inline-editable `TextInput` (autoFocus, commit on blur/submit), placeholder/empty state `'Add label (optional)'` — local only, never broadcast (`:193-204`, `:320-345`); `shortAddress(myAddress)` beneath (`:346-348`); a `QrIcon` (24) → `MyAddress` (`:349-357`).
- Scrolling body (so Settings/About stay reachable on short screens), in order (`:361-468`):
  `All` (`:366-374`) · divider (`:376`) · section **Logos**: `Chats`, `Groups`, `Contacts` (`:379-402`) · divider · section **MeshCore**: `Channels`, `DMs`, `MeshCore` (`:406-429`) — **OUT OF SCOPE** · divider · section **Bluetooth mesh**: `Discovery`, `DMs` (`:435-451`) — **OUT OF SCOPE** · divider · `Settings`, `About` (`:454-467`).
  Filter items call `onSelectView(view)`; page items call their navigate handler; both close the menu (`pick()`).
- `MenuView = 'all'|'chats'|'groups'|'mesh-channels'|'mesh-dms'|'ble-dms'` (`:33-39`) — after the mesh/BLE strip, only the first three survive.
- Avatar remove confirm copy: `'Remove your avatar? Peers will see your identicon again.'` (`:230`).

### 3.14–3.16 Out-of-scope screens
`MeshCoreScreen` (508 lines), `MeshConfigScreen` (392 lines), `NearbyScreen` (350 lines) — see §6.

---

## 4. Cross-cutting features

### 4.1 Message interactions — **E1** (reply/copy/delete/forward), **E2** (pin), **E4** (reactions)

All per-message actions live behind a long-press on the bubble (`ChatScreen.tsx:5-8`, menu component `src/components/BubbleActionMenu.tsx`). Long-press delay 350 ms on bubbles (`ChatScreen.tsx:459`).

**Menu item order** (`BubbleActionMenu.tsx:111-235`):
1. Quick-reaction bar as the menu header: `REACTION_PALETTE = ['👍','❤️','😂','😮','😢','🙏']` (`src/messages/reactions.ts:117`) plus a `+` that opens the full `EmojiGridModal` (`BubbleActionMenu.tsx:239-267`); emoji font size 26, the `+` 28 (`:290-291`). Both close the menu first and fire the action on the next tick (`:246-249`, `:258-261`).
2. `Reply` — any message (`:120-127`).
3. `Add label` / `Edit label` — incoming only, when the address is known (`:128-134`).
4. `Copy address` — same gate (incoming + address known); copies and toasts `'Copied'` (`:135-140`, `:57-60`).
5. `Forward` — any message (`:142-148`).
6. `Save to gallery` — image messages (`:150-160`).
7. `Save to phone` — `store1:`/`store2:` media (gif/video) (`:161-169`).
8. `Open in maps` — location messages (`:170-184`).
9. `Copy message` / `Copy coordinates` — location copies `formatLatLng`, everything else copies the raw body (`:185-199`). **The guard is only `!isImage && !isVoice`** (inline `img1:`/`img1v:` and `voc1:`/`voc1v:`) — a `store1:`/`store2:` GIF or video therefore *does* get a `Copy message` row that copies the raw marker string. Port the behaviour as-is or fix it deliberately; do not assume media is excluded.
10. `Send message` — incoming, group threads only (a 1:1 already is that thread) (`:200-207`).
11. `Map to mesh` — **OUT OF SCOPE** (`:208-217`).
12. `Pin` / `Unpin` — only when the caller supplies `onPin`, i.e. group creator (`:218-227`; gating `ChatScreen.tsx:2536-2544`).
13. `Delete for me` — destructive, last, works on own and peer bubbles (`:228-235`).

**Reactions (E4).** A reaction is an ordinary message whose body is a `react1:` marker (`reactions.ts:1-6`).
- Marker: `react1:<+|-><emoji>:<key>` — `encodeReaction(op, emoji, key)` (`reactions.ts:44-47`), prefix `REACTION_PREFIX = 'react1:'` (`:35`).
- `parseReaction` (`:53-67`) splits on the **last** colon (emojis contain none, the key is trailing hex), rejects an op that isn't `+`/`-`, and rejects `lastIndexOf(':') < 2` or an empty emoji/key — replicate this, a naive first-colon split breaks.
- Message identity `messageKey(author, body)` = two-word FNV-1a over `` `${author} ${body}` `` → 16 lowercase hex chars (two 8-hex words, zero-padded); seeds `R1 = 0x811c9dc5`, `PRIME = 0x01000193`, second word seeded `R1 ^ 0x9e3779b9` and mixing `c + 0x9e`, all `Math.imul` + `>>> 0` (`reactions.ts:14-32`). Known v1 collision: same author + identical body twice shares a key (`:8-12`).
- Folding (`foldReactions(events, me)`, `reactions.ts:84-114`): chronological replay, `+` adds the reactor to a set, `-` removes; empty sets dropped; output = `Map<key, ReactionState[]>` with `{emoji, count: set.size, mine: set.has(me), reactors: [...set]}` (`:70-77`).
- Chat screen sorts markers ascending by `(at, msgPk)` before folding so a remove follows its add (`ChatScreen.tsx:1686-1698`).
- Long-press a reaction pill → `Alert.alert(`${emoji} · ${count}`, whoList)` (`ChatScreen.tsx:2100-2110`).

**Reply (E1).** Prefix `REPLY_PREFIX = 'reply1:'` (`src/messages/reply.ts:13`); `encodeReply(key, body)` (`:23`), `parseReply` (`:32`), `displayBody` strips the marker (`:45`). Composer shows a reply banner; tapping a quoted header calls `scrollToKey` which finds the row and `scrollToIndex({viewPosition: 0.5})` (`ChatScreen.tsx:1713-1723`). Quote preview maps media to `'Photo'` / `'Voice message'` / `'Location'` (`:160-167`).

**Pin (E2).** Prefix `PIN_PREFIX = 'pin1:'` (`src/messages/pins.ts:11`); `encodePin(op, key)` (`:20`); `foldPins` — newest wins, `'-'` clears (`:43`). v1: only the group creator may pin/unpin (`ChatScreen.tsx:2537-2544`, unpin also in the pin bar `:1960-1971`).

**Forward (E1).** `ForwardPicker` modal lists all conversations (`src/components/ForwardPicker.tsx:1-2`, `:22`). `chatStore.forwardMessage(content, toConvoPk)` re-uploads images/voice via `LogosChat.sendImageTo` / `sendVoiceTo` after `ImagePicker.readFileBase64`, and re-sends text/location through the normal send path; refuses media into a mesh chat (`chatStore.ts:1351-1382`). Toast `'Forwarded'` (`ChatScreen.tsx:2619`). Forwarding an `addr1:` card additionally navigates into the target chat (`:2620-2631`).

**Delete (E1).** `chatStore.deleteMessage(convoPk, msgPk)` → `LogosChat.deleteMessage(msgPk)` (`chatStore.ts:1798`) — local only, no remote unsend.

**Retry (E1).** Failed bubble tap → `chatStore.retry(convoPk, msgPk)` → `LogosChat.retryMessage` (`chatStore.ts:1536`).

**Folded control markers (E1, must exist for the port to not render junk).** `src/messages/markers.ts:21-33`: `react1:`, `pin1:`, `leave1:`, `pfp1:`, `gcfg1:`, `readd1:` are never bubbles. The file's header documents the exact bug that motivated centralising this (`markers.ts:6-13`).

### 4.2 Media send + view flows — **E4**

| Kind | Pick | Transport | Marker | Source |
|---|---|---|---|---|
| Photo (standard) | `ImagePicker.pickImages(2048, 2_000_000, MAX_ALBUM)` → staged | downscale to `1024 / 120_000` bytes then `LogosChat.sendImageTo` | inline `img1v:` / `img1:` | `chatStore.ts:1208`, `:1265-1272`; native doc `LogosChat.ts:152-162` |
| Photo (HQ) | same staging | `Storage.uploadEncrypted(path,'')` → `encodeMedia` | `store2:` | `chatStore.ts:1250-1262` |
| Camera photo | `ImagePicker.capturePhoto(2048, 2_000_000)` | as above | as above | `chatStore.ts:1231` |
| GIF | `ImagePicker.pickRawMedia(8_000_000, 'gif')` | `Storage.uploadEncrypted` | `store2:` | `chatStore.ts:1027`, `:1035` |
| Video | `ImagePicker.pickRawMedia(0, 'video')` → staged with poster | transcode then `Storage.uploadEncrypted(enc.path, id)`; progress bubble via `mediaSends` | `store2:` | `chatStore.ts:1136`, `:1174`; bubble `ChatScreen.tsx:1993-1995` |
| Voice note | `AudioRecorder.startRecording/stopRecording` | `LogosChat.sendVoiceTo(convoPk, mime, durationMs, waveformCsv, base64)` | `voc1v:` / `voc1:` | `chatStore.ts:1331-1339`; native `LogosChat.ts:163-170` |
| Location | `Location.getCurrent()` after `ACCESS_FINE_LOCATION` (`:1288`, `:1295`) | plain text send | `loc1:<lat>,<lng>[,<acc>]` via `buildLocation` (`src/native/locMsg.ts:8`, `:17-19`) | `chatStore.ts:1286-1318` |
| Avatar (pfp) | `ImagePicker.pickImage(256, 50_000)` (`:1061`) | `Storage.uploadEncrypted` (`:1071`) → broadcast to every **Logos** conversation (mesh/BLE peers can't fetch Storage) | `pfp1:` + `encodeMedia` (`src/messages/pfp.ts:15`, `:21-22`); removal broadcasts the sentinel `pfp1:clear` (`pfp.ts:18`, `:26`) | `chatStore.ts:1054-1101` |

Storage marker: `MEDIA_PREFIX = 'store1:'`, `MEDIA_PREFIX_V2 = 'store2:'` (`src/messages/media.ts:15`, `:21`). `Storage.uploadEncrypted(localPath, id) → {cid, key, cap}` and `Storage.downloadDecrypt(cid, key, cap, padded) → path` (`src/native/Storage.ts:13`, `:18`). `uploadEncrypted` **always** size-pads (Padmé buckets, `store2:`), so a locally-held ref must carry `padded: true` or my own avatar decodes corrupt — peers are fine because they re-parse the `store2:` marker (`chatStore.ts:1080-1084`).

**Media viewer (`src/components/MediaViewer.tsx:1-9`)** — one full-screen viewer for photos/GIFs/videos:
- Edge-to-edge Modal (`statusBarTranslucent`).
- Tap 1 opens on black with NO controls; a tap toggles a semi-transparent bottom bar (author + caption + download/share/forward/close) plus a top-right close circle.
- Pinch-zoom (bar hides while zoomed), swipe-down dismisses in both modes, swipe left/right pages across all conversation media.
- Built on `react-native-gesture-handler` + `reanimated`; pure helpers `clampScale`, `doubleTapScale`, `isAtFit`, `shouldDismiss` in `src/media/mediaGestures.ts` (`MediaViewer.tsx:36-41`).
- Ordered item list from `enumerateMedia` / `mediaIndexOf` (`src/media/mediaList.ts`, used `ChatScreen.tsx:830-839`).
- Save → gallery with the toast `'saved to gallery'` auto-clearing after 2500 ms (`ChatScreen.tsx:859-881`); Share → `MediaShare.shareFile(path, mime)` (`:882-889`).

**Per-group storage opt-out (E2/E4).** `gcfg1:` marker (`src/messages/groupcfg.ts:17`); set at creation (`NewGroupScreen.tsx:63-65`) or from Group info (`GroupInfoScreen.tsx:413`); folded newest-wins (`groupcfg.ts:52`, applied `ChatScreen.tsx:1787-1813`). When on: media bubbles render `'media disabled in this group'` and **never** fetch from Storage (`ChatScreen.tsx:488-501`, `:402-403`); GIF/video buttons hidden but inline photo + camera stay (`:2455-2481`). System lines announce transitions: `'Storage turned off — text & voice only'` / `'Storage turned on — media enabled'` (`:1806-1810`).

### 4.3 Contacts — **E3**

- **Add by paste:** `ScanScreen` paste card → `NewConversation` → `startConversation` (§3.4/§3.5).
- **Add by QR scan:** `ScanScreen` camera path (§3.4).
- **Shared contact card:** marker `ADDR_PREFIX = 'addr1:'`, `encodeAddr(address, label?)`, `parseAddr` (`src/messages/address.ts:10-27`). Rendered as an `AddressCard` in the thread for both directions with **Add** and **View** (`ChatScreen.tsx:2044-2063`); Add = reuse-or-create the 1:1 carrying the shared label, then open it (`:1066-1086`).
- **Send my address into a chat:** `MyAddressScreen` Send button → `ForwardPicker` (§3.3); **share a contact:** `ContactsScreen` `AddressModal` → `onForward` → `ForwardPicker` (`ContactsScreen.tsx:341-368`).
- **Labels + verification:** `LabelModal` everywhere (Chat header, bubble menu, Contacts, Group info); `saveLabelFor` reuses the 1:1 or creates the contact, then persists `setVerified` (`ChatScreen.tsx:1020-1040`).
- **Contact directory:** `knownContacts()` + `filterContacts()` from `chatStore` (`ContactsScreen.tsx:54`, `:61`).
- **My display name:** editable inline in the SideMenu header; local only, never broadcast (`src/components/SideMenu.tsx:191-204`, KV `settingsStore.ts:41`).
- **My avatar:** set/change/remove from the SideMenu avatar (pencil badge 18×18, radius 9, `colors.accent`, 1.5px `colors.canvas` border) (`SideMenu.tsx:306-318`, `:516-528`); remove confirm copy `'Remove your avatar? Peers will see your identicon again.'` (`SideMenu.tsx:230`).

### 4.4 My address + QR — **E3**
See §3.3. QR payload is the bare hex by default; the `peers:<addr>?label=…` form only when the label toggle is on (`MyAddressScreen.tsx:139-155`, `encodeAddressPayload` in `src/lib/addressPayload.ts`). `AddressModal` mirrors the same `QrCard` + centred identicon badge for a peer's address (`src/components/AddressModal.tsx:1-6`).

### 4.5 Group lifecycle — **E2**
Create (§3.6) → Add members (§3.7) → Info/roster/rename/remove-member (§3.8) → Wipe / Leave (§3.2).
- Leave is honest about being a consensus round, not instant (`ChatScreen.tsx:973-976`; native contract `LogosChat.ts:233-239`).
- Local-only leave for GroupV1 tombstones the lib id (`LogosChat.ts:240-245`, used `chatStore.ts:1776`).
- Dead groups (`groupLiveness`, `LogosChat.ts:246-247`): creator-only `Restart group` via `recreateGroup` (`LogosChat.ts:252-255`, `chatStore.ts:1730`); members get `Ping creator`, addressed to `LogosChat.groupCreator(convoPk)` with a roster fallback (`ChatScreen.tsx:2206-2232`).
- Re-add recovery: `readd1:` marker (`src/messages/readd.ts:14-26`), surfaced as the `Ask to be re-added` system-line action (`ChatScreen.tsx:2013-2037`), replayed on foreground via `LogosChat.pendingReadds(sinceMsgPk, limit)` (`LogosChat.ts:222-228`, `chatStore.ts:854`).
- Leave marker `leave1:` folds into an "X left" system line (`src/messages/leave.ts:14-29`, applied `ChatScreen.tsx:1754-1762`).
- Member removal boundary: affordance from `canRemoveMember`, enforcement in the native MLS layer which drops a Remove commit from anyone but the recorded creator; pre-#349 groups fail closed (`LogosChat.ts:181-188`, `GroupInfoScreen.tsx:253-262`).

### 4.6 Settings rows — **E5**
Full table in §3.10. Persisted through `LogosChat.getSetting/setSetting` KV (`settingsStore.ts:100-103`, `:41`, `:69`).

### 4.7 Security — **E5**
PIN app-lock, duress/wipe PIN, lock screen, lock-on-background, reset identity and data — see §3.10 and §3.11.
`securityStore.wipeAndReset()` → `LogosChat.wipeIdentityAndData()`, which shuts the node down, deletes identity seed + encrypted store + app DB + chat images, then reopens with a brand-new identity; it powers Reset, the duress PIN, and the 3-wrong-attempts wipe (`src/native/LogosChat.ts:269-275`).

### 4.8 Identity export / restore — **E6**
See §3.12. Note `MyAddressScreen.tsx:82-88` documents that a true QR **image** share needed a native method — the text/URI share was the fallback until `shareIdentityImage` landed (`LogosChat.ts:291-295`).

### 4.9 Shared components the screens above assume exist (`src/components/`, in-scope only)

The screen sections cite these by name; a port needs the same set of primitives or the
per-screen descriptions don't compose. Line counts are the Android source's, as a rough
size signal. (Mesh/BLE/Tor components are listed in §6 instead.)

| Component | Lines | What it is |
|---|---|---|
| `SideMenu.tsx` | 566 | The drawer — see §3.13 |
| `OverflowMenu.tsx` | 445 | THE popup-menu primitive: rows ≥44dp, panel fill, border, dim backdrop; `anchor="point"` + `anchorY` for long-press menus, or anchored under a header ellipsis. Also exports the menu icon set (`EllipsisIcon`, `TagIcon`, `PencilIcon`, `UserPlusIcon`, `UsersIcon`, `LogOutIcon`, `EraserIcon`, `TrashIcon`, `CopyIcon`, `PinIcon`, `ReplyIcon`, `ClipboardIcon`, `MessageCircleIcon`, `BackIcon`, `MeshIcon`, `:32-282`) and `MenuItem = {key, label, icon, onPress, destructive?, testID?}` (`:284-292`) |
| `MediaViewer.tsx` | 415 | Full-screen media viewer — see §4.2 |
| `SpeedDialFab.tsx` | 347 | FAB + expanding labelled mini-actions + backdrop; `FabAction = {key, label, testID, icon, onPress?, disabled?}` (`:116-123`) — `onPress` is optional so a "coming soon" row can be inert |
| `BubbleActionMenu.tsx` | 293 | Per-message long-press menu — see §4.1 |
| `AddressModal.tsx` | 263 | "Show address" for a peer: label title, badged QR, full hex, Copy, Forward |
| `HexAvatar.tsx` | 231 | Identicon / custom avatar — see §2 |
| `PinFlowModal.tsx` | 215 | The Settings PIN flows over `PinPad`. `PinFlowMode = 'setMain' \| 'setDuress' \| 'removeMain'` (`:15`) — `setMain` is new→confirm, or old→new→confirm when a PIN exists; `removeMain` verifies then clears. There is **no** `removeDuress` mode: removing the wipe PIN calls `securityStore.removeDuressPin()` directly (`SettingsScreen.tsx:143`, `:179-182`) |
| `LabelModal.tsx` | 178 | Set the local private label (+ verified) for a contact — one decision, one button |
| `QrCard.tsx` | 171 | Pure-JS `qrcode-generator` matrix → one `react-native-svg` path, always `qrBg`/`qrFg`, ~260dp with quiet zone, centred identicon (or avatar image) badge |
| `BackupPassphraseModal.tsx` | 156 | Passphrase twice + the plain-language "what's included / no recovery" copy, before export |
| `VoiceBubble.tsx` | 144 | Play/stop + recorded waveform + `mm:ss`, playback via the native audio module |
| `InfoModal.tsx` | 120 | Generic (i) explainer: title + sections + "Got it" (restart-group #191, invited-wait #192) |
| `PinPad.tsx` | 112 | 6 dots + an **own** numeric keypad (no soft keyboard — deterministic lock screen) |
| `SwipeRow.tsx` | 111 | Swipe-left-to-delete: red ribbon, haptic at the arm threshold, "release to delete", gesture-committed, no dialog; RN `PanResponder` (no gesture-handler) |
| `StorageInfoModal.tsx` | 106 | The (i) behind the per-group storage toggle |
| `StatusPill.tsx` | 102 | Node status pill: stopped → amber pulse (0.35↔1.0, 550 ms) → running → error; dot **and** label, never colour-only |
| `MediaSendBubble.tsx` | 101 | Video "sending" bubble: poster + circular progress ring + `compressing`/`sending` phase |
| `ForwardPicker.tsx` | 87 | Modal conversation picker (forward, share-a-contact, send-my-address) |
| `AddressCard.tsx` | 86 | In-thread `addr1:` card: identicon + shared name + short hex + Add/View |
| `EmojiGridModal.tsx` | 83 | Dependency-free curated emoji grid behind the quick-react `+` |
| `MediaVideo.tsx` | 77 | Native video surface: inline muted/looping preview, or fullscreen with controls/seek |
| `KeyboardAwareScreen.tsx` | 72 | The wrapper every input screen uses so a bottom field + its CTA clear the keyboard |
| `ErrorToast.tsx` | 70 | Bottom toast, `errorFill`/`errorBorder`, **persistent** with a manual ✕ (no auto-dismiss) |
| `SystemLine.tsx` | 62 | Centred non-message note inside a thread ("… joined", "Group ended …") |
| `ActionButton.tsx` | 62 | The one primary/secondary button pair (same height + font everywhere) |
| `VerifiedBadge.tsx` | 45 | Blue scalloped seal + white check; local, user-asserted, never broadcast |
| `SwipeBackGesture.tsx` | 43 | App-level edge-swipe-back (Android native-stack has none) |
| `PulseDot.tsx` | 43 | Pulsing status dot (same 0.35↔1.0 / 550 ms motion as `StatusPill`) |
| `NodeStatusIcon.tsx` | 43 | The chat logo tinted by node status |
| plus | — | `UnreadBadge` (red fill, white count, capped `99+`), `Logo`, `LockIcon`, `SendIcon`, `MediaIcons`/`MediaViewerIcons`, `QrIcon` |

---

## 5. Suggested epic assignment (roll-up)

| Feature | Epic |
|---|---|
| Conversation list, rows, swipe-delete, row menu, empty states | E1/E7 |
| Chat thread, bubbles, inverted list, pagination, retry, drafts | E1 |
| Composer (text, send-state colours, disabled state) | E1 |
| Reply, forward, copy, delete-for-me | E1 |
| Reactions (quick bar, emoji grid, pills, who-reacted) | E4 |
| Photo / camera / HQ / GIF / video / voice note / location send | E4 |
| Media viewer (zoom, page, save, share, forward) | E4 |
| Pin / unpin + pinned bar | E2 |
| Group create, add members, group info, rename, remove member, wipe, leave | E2 |
| Group storage opt-out (`gcfg1:`) | E2 |
| Dead-group restart / ping creator / re-add recovery | E2 |
| Add contact (paste + QR), NewConversation, verify checkbox | E3 |
| Contacts list, search, Labeled/Seen tabs, contact menu | E3 |
| Labels + verified badge everywhere | E3 |
| My address + QR + copy/share/send-to-chat | E3 |
| Shared contact card (`addr1:`) | E3 |
| Display name + custom avatar (`pfp1:`) | E3 |
| Notification settings (5 toggles) | E5 |
| Delivery-node setting | E5 |
| PIN, duress PIN, lock screen, lock-on-background, reset | E5 |
| Backup export (passphrase) | E6 |
| Restore from backup | E6 |
| Version / About / repo link / home-screen shortcut | E6/E7 |
| Navigator, nav-state persistence, deep link, swipe-back, theme tokens | E7 |
| SideMenu, header, FAB, overflow-menu primitive, error toast, system lines | E7 |

---

## 6. EXPLICITLY OUT OF SCOPE (Tor / private mode / BLE / Bluetooth / MeshCore / Nearby / mesh)

Drop all of the following from the desktop port.

**Whole screens**
- `src/screens/MeshCoreScreen.tsx` (508 lines) — pair/connect a MeshCore LoRa radio over BLE, self-info, broadcast label, channels/DMs (`:1-4`). Contains `PUBLIC_CHANNEL_KEY = '8b3387e9c5cdea6ac9e5edbaa115cd72'` (`:36`).
- `src/screens/MeshConfigScreen.tsx` (392 lines) — radio params, region presets `EU 868 / US 915 / AU/NZ 915 …` (`PRESETS`, `:26-30`).
- `src/screens/NearbyScreen.tsx` (350 lines) — BLE-mesh nearby peers, hop pages, all/contacts/verified filters (`:1-4`).
Routes to delete: `MeshCore`, `MeshConfig`, `Nearby` (`RootNavigator.tsx:240-254`; types `navigation/types.ts:30-35`).

**Stores / native modules**
`src/stores/meshStore.ts`, `src/stores/meshPresence.ts`, `src/stores/bleStore.ts`, `src/stores/bleState.ts`,
`src/native/MeshCore.ts`, `src/native/BleMesh.ts`, `src/native/bleFlood.ts`, `src/native/bleFrag.ts`, `src/native/bleIdentity.ts`, `src/native/Tor.ts`, `src/mesh/composerBudget.ts`.

**Components**
`MeshLogo.tsx`, `BleLogo.tsx`, `MeshInfoModal.tsx`, `MeshMapModal.tsx`, `TorBootstrapModal.tsx`, `ShieldLogo.tsx` (private-mode mark), and the mesh/BLE rows inside `TransportsModal.tsx` / `TransportPill.tsx` (`TransportsModal.tsx:1-13`).

**Features inside in-scope screens that must be stripped**
| Feature | Where |
|---|---|
| SideMenu `MeshCore` section (Channels / DMs / MeshCore) | `SideMenu.tsx:405-428` |
| SideMenu `Bluetooth mesh` section (Discovery / DMs) | `SideMenu.tsx:432-450` |
| Filter views `mesh-channels`, `mesh-dms`, `ble-dms` | `SideMenu.tsx:33-39`, `ConversationsScreen.tsx:240-246` |
| Context-aware FAB mesh/BLE branches + `FAB_COLOR.mesh/#22C55E`, `.ble/#0EA5E9` | `ConversationsScreen.tsx:184-188`, `:328-376` |
| Row `via BLE mesh` bar/caption + `nearby` pulse dot | `ConversationsScreen.tsx:109`, `:138-150`, `:569-587` |
| Row green mesh-mapped badge | `ConversationsScreen.tsx:127-137` |
| `TransportPill` mesh/BLE marks + `TransportsModal` mesh/BLE/Tor rows | `ConversationsScreen.tsx:416-418`; `TransportPill.tsx:1-10` |
| Chat mesh-mirror banner (`Add/Stop mesh mirroring`, `N/M mapped to mesh`) | `ChatScreen.tsx:1865-1932` |
| Chat `⋮` mesh entries + `About mesh mirroring` | `ChatScreen.tsx:1423-1449` |
| `viaMesh` / `viaBle` bubble tints + captions | `ChatScreen.tsx:377-381`, `:2802-2819`, `:622-623` |
| Header mesh presence (`📡 heard Xm ago`) + BLE `● nearby` | `ChatScreen.tsx:1265-1287` |
| Mesh-only composer: single line, LoRa byte budget (`composerBudget`) | `ChatScreen.tsx:2274-2304`, `:1381` |
| `Map to mesh` / `Change mesh identity` menu items + `MeshMapModal` | `BubbleActionMenu.tsx:208-217`, `ChatScreen.tsx:2635-2660`, `GroupInfoScreen.tsx:243-252`, `:479-503`, `ContactsScreen.tsx:162-167`, `:379-402` |
| Group info `N/M mapped to mesh` summary + roster mesh tags | `GroupInfoScreen.tsx:199-207`, `:361-374` |
| Contacts row mesh tag + mesh presence line | `ContactsScreen.tsx:211-242` |
| AddMembers BLE `nearby` cue + `via mesh · N of M nearby` header | `AddMembersScreen.tsx:265-296` |
| `radioRefusesGroupSetup` LoRa refusal on New Group / Add Members | `NewGroupScreen.tsx:45-50`, `AddMembersScreen.tsx:166-175` |
| Settings **Privacy → Route media over Tor** (already dead code: `TOR_TOGGLE_READY = false`) + `TorBootstrapModal` | `SettingsScreen.tsx:62-65`, `:111-135`, `:291-308`, `:393-398` |
| App boot `restoreBleEngaged()` + BLE-engage pref persistence | `App.tsx:50-72`, `:128-137`, `:153` |
| `HexAvatar` `mesh` / `ble` ramps, the `AvatarKind` union, its `RAMPS`/`PREFIX` entries, and the `'mesh'`/`'ble'` branches of `convoKind()` | `HexAvatar.tsx:27-30`, `:32-41`, `:224-229` |
| About blurb naming MeshCore / Bluetooth mesh | `AboutScreen.tsx:149-154` |
| Conversation `transport` field branching (`'logos' \| 'mesh' \| 'ble'`) | `ConversationsScreen.tsx:235-246`, `ChatScreen.tsx:899-900` |
| `chatStore` mesh actions: `openMeshChannel`, `startMeshDm`, `switchGroupToMesh`, `switchGroupToLogos`, `mapMeshIdentity`, `unmapMeshIdentity`, `setContactMeshMap`, `clearContactMeshMap` | `chatStore.ts:208-221`, `:361-363` |
| Native mesh verbs: `setMeshMap`, `clearMeshMap`, `listMeshMap`, `setMeshMirror`, `clearMeshMirror`, `groupForMeshChannel`, `upsertMeshChannel`, `upsertMeshDm`, `meshDmByPrefix`, `recordMeshMessage` | `LogosChat.ts:194-219` |
| Native BLE verbs: `encryptForConvo`, `ingestCiphertext`, `exportContact`, `importContact`, `createConversationOffline` | `LogosChat.ts:126-150` |
| `Storage.setTorRouting(enabled, socksPort)` | `src/native/Storage.ts:24` |

---

## 7. Notes, gaps, and things NOT in source

1. **`LockScreen` is not a stack route.** Any port that expects a "lock route" is wrong — it is an overlay above the mounted navigator (`App.tsx:167-168`).
2. **No "delivered" receipts anywhere.** Explicitly stated in `ChatScreen.tsx:3` ("NO 'delivered' ticks"). Statuses are only `pending` / `failed` / sent.
3. **No message editing.** No edit action exists in `BubbleActionMenu.tsx`.
4. **No remote unsend.** `Delete for me` is local only (`ChatScreen.tsx:2578-2581`).
5. **No typing indicators, no read receipts, no presence for Logos.** `ChatScreen.tsx:1253-1254` says last-seen comes from the last inbound message, "no heartbeat".
6. **No archive/mute/pin-conversation.** The row menu has only Open / Group info / Delete (`ConversationsScreen.tsx:275-314`).
7. **No search inside a conversation.** Search exists only on the Contacts screen (`ContactsScreen.tsx:258-271`).
8. **No theme switch / light mode.** `src/theme/colors.ts` is a single dark palette.
9. **No onboarding/welcome screen.** `initialRouteName` is `Conversations` (`RootNavigator.tsx:154`); the node auto-starts (`App.tsx:150`).
10. Voice-note cap `MAX_RECORDING_MS = 120_000` ms (`src/native/Audio.ts:11`) — rendered in the timer as `/ 2:00` (`ChatScreen.tsx:2255-2257`). Album pick cap `MAX_ALBUM = 10` (`src/stores/chatStore.ts:118`), matching the composer's `MAX_STAGED_IMAGES = 10` (`ChatScreen.tsx:169`).
11. `formatLastSeen(lastInboundAt, now)` (`src/stores/conversationView.ts:319-331`) returns `''` for `<=0`, then `'last seen just now'` (<60 s) → `'last seen Nm ago'` → `'last seen Nh ago'` → `'last seen Nd ago'` (<7 d) → `'last seen Nw ago'` (<5 w) → `'last seen a while ago'`.
12. `deriveComposerState` (`src/stores/groupState.ts:50-91`) is the pure, unit-tested source of `running/connecting/overMesh/meshLive/canSendBase/sendColorKind/logosDead/dead/canRevive`, consumed at `ChatScreen.tsx:1320-1330`. Body, with the mesh/BLE terms struck out for the port:
    - `running = nodeStatus === 'running'` (`:51`); `connecting = nodeStatus === 'initializing' || 'starting'` (`:52-53`).
    - `canSendBase = meshLive || running || bleReachable` (`:57`) → **`= running`** for the port.
    - `sendColorKind = bleReachable ? 'ble' : meshLive ? 'mesh' : running ? 'accent' : connecting ? 'connecting' : 'offline'` (`:63-71`) → **`running ? 'accent' : connecting ? 'connecting' : 'offline'`**, mapped to colours at `ChatScreen.tsx:1339-1348`.
    - `logosDead = isGroup && !isMesh && liveness === 'dead'`; `dead = logosDead && !meshLive` → **`dead = logosDead`**; `canRevive = logosDead && createdByMe` (`:75-78`).
    A pure MeshCore channel is never "dead" because it has no MLS side — irrelevant once mesh is dropped, but it explains the `!isMesh` term.
