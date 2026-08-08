# Peers (logos-chat-android) — Visual Design Token Spec

Ground truth extracted from source at `<logos-chat-android>`.
Every value below is cited — `path:line` where a stable line exists, otherwise
`path (styleName)` when the anchor is a StyleSheet key. Nothing here is inferred except
where explicitly labelled ("weight equivalent").

> **CRITICAL — `docs/theme.md` IS STALE. DO NOT USE IT.**
> `docs/theme.md:18-21` still documents the accent as emerald `#10B981` / `onAccent #000000`.
> The **source of truth is `src/theme/colors.ts`**, which is orange `#FF5000` / `onAccent #FFFFFF`.
> The code comment at `src/theme/colors.ts:13` explicitly says white "**never black**".
> Where this spec and `docs/theme.md` disagree, the code wins.

> **There is no file `src/theme.ts`.** The theme is the directory `src/theme/`:
> `colors.ts`, `typography.ts`, `spacing.ts`, `index.ts`.

---

## 1. Color tokens

All from `src/theme/colors.ts:2-29`. Literal hex, ready to hardcode.

| Token | Hex | Semantic role | Cite |
|---|---|---|---|
| `canvas` | `#0A0A0A` | App background, message area, system bars | colors.ts:3 |
| `pane` | `#111111` | Lists, input rows (composer background) | colors.ts:4 |
| `panel` | `#161616` | Headers, cards, dialogs, status bar | colors.ts:5 |
| `border` | `#2a2a2a` | ALL borders/separators (note: lowercase hex in source) | colors.ts:6 |
| `text` | `#FAFAFA` | Primary text | colors.ts:7 |
| `textDim` | `#6B7280` | Labels, secondary text | colors.ts:8 |
| `textFaint` | `#4B5563` | Timestamps, muted text, input placeholders | colors.ts:9 |
| **`accent`** | **`#FF5000`** | **Own bubble fill, buttons, FAB, branding (Logos orange)** | colors.ts:10 |
| `accentHover` | `#FF7A33` | Pressed/hover states (Paper ripple tint) | colors.ts:11 |
| `accentPressed` | `#CC4000` | Active press | colors.ts:12 |
| `onAccent` | `#FFFFFF` | Text on accent — white + semibold everywhere, **never black** | colors.ts:13 |
| `bubblePeer` | `#1F1F1F` | Received bubble fill (its text is `#FAFAFA`) | colors.ts:14 |
| `unread` | `#EF4444` | Unread badge, destructive/danger, error text | colors.ts:15 |
| `pulse` | `#F59E0B` | Amber startup pulse (node initializing/starting) | colors.ts:16 |
| `nodeOnline` | `#FF5000` | Node running — orange (brand; "no green anywhere") | colors.ts:18 |
| `nodeConnecting` | `#9CA3AF` | Node initializing/starting — **gray, deliberately NOT amber** | colors.ts:21 |
| `nodeOffline` | `#EF4444` | Node stopped/error — red | colors.ts:22 |
| `contact` | `#FF5000` | 1:1 contact glyph + attribution label | colors.ts:23 |
| `verified` | `#1D9BF0` | Verified-contact badge — blue seal, white check | colors.ts:24 |
| `errorFill` | `#5c1a1a` | Error toast fill, swipe-to-delete ribbon | colors.ts:25 |
| `errorBorder` | `#C62828` | Error toast / danger-card border | colors.ts:26 |
| `qrBg` | `#FFFFFF` | QR ground — ALWAYS white regardless of theme | colors.ts:27 |
| `qrFg` | `#000000` | QR modules — ALWAYS black | colors.ts:28 |

`colors.ts` also exports the helper **`nodeStatusColor(status)`** (colors.ts:34-43), the single
status→color mapping used by `NodeStatusIcon`/`Logo`:
`running → nodeOnline #FF5000` · `initializing | starting → nodeConnecting #9CA3AF` ·
everything else (`stopped | error`) `→ nodeOffline #EF4444`.
Note this is a **different** mapping from `StatusPill`'s own `dotColor` table (§5.11), which
uses amber `pulse` for initializing/starting. Both exist; do not merge them.

### 1.1 Non-token literal colors used in components

These are hardcoded in components, not in `colors.ts`. A QML port needs them.

| Constant | Hex / rgba | Role | Cite |
|---|---|---|---|
| `MESH_GREEN` | `#22C55E` | MeshCore transport (bubbles, tags, FAB, avatars) | src/screens/ChatScreen.tsx:155 |
| `LINK_BLUE` | `#4EA3FF` | Tappable URLs inside **peer** bubbles | src/screens/ChatScreen.tsx:158 |
| `BLE_BLUE` | `#0EA5E9` | Bluetooth-mesh transport | src/screens/ChatScreen.tsx:173 |
| `TRI_COLOR.offline` | `#EF4444` | Transport traffic light — red | src/components/tri.ts:18 |
| `TRI_COLOR.connecting` | `#EAB308` | Transport traffic light — yellow (breathing) | src/components/tri.ts:19 |
| `TRI_COLOR.online` | `#22C55E` | Transport traffic light — green | src/components/tri.ts:20 |
| `TRI_MUTED` | `#6B7280` | Offline **secondary** transport (mesh/BLE) — gray not red | src/components/tri.ts:26 |
| unverified strip fill | `#F59E0B22` | Amber @13% tint, unverified-contact strip | src/screens/ChatScreen.tsx:2763 |
| unverified strip border | `#F59E0B` | 1px bottom border of that strip | src/screens/ChatScreen.tsx:2764 |
| mesh peer bubble tint | `rgba(34,197,94,0.08)` | Peer bubble that rode the mesh | src/screens/ChatScreen.tsx:2807 |
| BLE peer bubble tint | `rgba(14,165,233,0.10)` | Peer bubble that rode BLE | src/screens/ChatScreen.tsx:2818 |
| mesh-banner alert fill | `rgba(239,68,68,0.12)` | Node-offline mesh banner | src/screens/ChatScreen.tsx:2901 |
| BLE row bar | `rgba(14,165,233,0.55)` | 3px left bar on a BLE conversation row | src/screens/ConversationsScreen.tsx:580 |
| BLE "via BLE mesh" tag | `rgba(56,189,248,0.9)` | Caption color | src/screens/ConversationsScreen.tsx:585 |
| my-reaction pill fill | `#2a1607` | Reaction pill you reacted with (dark orange) | src/screens/ChatScreen.tsx:3151 |
| media placeholder box | `rgba(0,0,0,0.18)` | Loading/error media box inside a bubble | src/screens/ChatScreen.tsx:3061 |
| play badge | `rgba(0,0,0,0.45)` | Circular play badge over video | src/screens/ChatScreen.tsx:3079 |
| video poster fallback | `rgba(0,0,0,0.35)` / `rgba(0,0,0,0.3)` | MediaSendBubble scrim / staged-video | src/components/MediaSendBubble.tsx (posterFallback, scrim); src/screens/ChatScreen.tsx:3010 |

Tri-state selection rule (`triColorFor`, tri.ts:30-33): `kind !== 'logos' && tri === 'offline'`
→ `TRI_MUTED`; otherwise `TRI_COLOR[tri]`. Only the primary Logos transport is allowed to go
red. State mapping (tri.ts:36-69): Logos `running→online`, `initializing|starting→connecting`,
else `offline`; MeshCore `connected→online`, `connecting→connecting`, else `offline`; BLE
`on→online`, `starting→connecting`, else `offline`.

### 1.2 Avatar identicon ramps (`src/components/HexAvatar.tsx:26-30`)

5-step dark→near-white ramps, one per transport:

- `LOGOS_RAMP` (contact **and** group): `['#B8420E', '#FF5000', '#FF7A33', '#FFB27A', '#FFE4D0']` — HexAvatar.tsx:26
- `MESH_RAMP`: `['#166534', '#22C55E', '#4ADE80', '#86EFAC', '#DCFCE7']` — HexAvatar.tsx:28
- `BLE_RAMP`: `['#0B5C8A', '#0EA5E9', '#38BDF8', '#7DD3FC', '#E0F5FF']` — HexAvatar.tsx:30

### 1.3 Scrim / backdrop opacity conventions

| Surface | Value | Cite |
|---|---|---|
| Paper MD3 `backdrop` | `rgba(0,0,0,0.6)` | src/theme/index.ts:54 |
| SideMenu backdrop | `rgba(0,0,0,0.6)` | src/components/SideMenu.tsx (styles.backdrop) |
| SpeedDial FAB backdrop | `rgba(0,0,0,0.6)` | src/components/SpeedDialFab.tsx:296 |
| InfoModal backdrop | `rgba(0,0,0,0.6)` | src/components/InfoModal.tsx (styles.root) |
| OverflowMenu backdrop | `rgba(0,0,0,0.5)` | src/components/OverflowMenu.tsx (styles.backdrop) |
| SettingsScreen warn backdrop | `rgba(0,0,0,0.7)` | src/screens/SettingsScreen.tsx:515 |
| Fullscreen image backdrop (chat) | `rgba(0,0,0,0.95)` | src/screens/ChatScreen.tsx:2797 |
| MediaViewer bottom bar | `rgba(0,0,0,0.6)` | src/components/MediaViewer.tsx (styles.bar) |
| MediaViewer close circle | `rgba(0,0,0,0.45)` | src/components/MediaViewer.tsx (styles.closeCircle) |

### 1.4 Paper MD3 mapping (only relevant if you mirror Material components)

`src/theme/index.ts:16-66` — `roundness: 2`, `dark: true`, built by spreading `MD3DarkTheme`.
Paper's font config is also overridden globally:
`fonts: configureFonts({config: {fontFamily: 'JetBrainsMono-Regular'}})` (index.ts:12-14, 20) —
i.e. every Paper component defaults to the mono regular face.

Full color remap (index.ts:24-64) — the point is that **no default Material color can leak**:
`background=canvas`, `surface=pane`, `surfaceVariant=panel`, `primary=accent`,
`onPrimary=onAccent`, `outline=border` & `outlineVariant=border`, `error=unread`,
`onSurface=text`, `onSurfaceVariant=textDim`, `onBackground=text`,
`primaryContainer=accentPressed`, `onPrimaryContainer=text`,
`secondary=accent`, `onSecondary=onAccent`, `secondaryContainer=panel`, `onSecondaryContainer=text`,
`tertiary=accentHover`, `onTertiary=onAccent`, `tertiaryContainer=panel`, `onTertiaryContainer=text`,
`errorContainer=errorFill`, `onError=text`, `onErrorContainer=unread`,
`inverseSurface=text`, `inverseOnSurface=canvas`, `inversePrimary=accentPressed`,
`shadow='#000000'`, `scrim='#000000'`, `backdrop='rgba(0,0,0,0.6)'`,
`surfaceDisabled='rgba(250,250,250,0.12)'`, `onSurfaceDisabled='rgba(250,250,250,0.38)'`,
elevation `level0='transparent'`, `level1=pane (#111111)`, `level2..5=panel (#161616)`.

React Navigation theme (`src/navigation/RootNavigator.tsx:70-81`): extends `DarkTheme` with
`primary=#FF5000`, `background=#0A0A0A`, `card=#161616`, `text=#FAFAFA`, `border=#2a2a2a`,
`notification=#EF4444`.

---

## 2. Typography

`src/theme/typography.ts` — **JetBrains Mono ONLY**, three bundled TTFs.

Families (typography.ts:5-9), loaded by exact family name:
- `regular` → `JetBrainsMono-Regular`
- `medium` → `JetBrainsMono-Medium`
- `bold` → `JetBrainsMono-Bold`

Font files verified present at `assets/fonts/` **and** `android/app/src/main/assets/fonts/`:
`JetBrainsMono-Bold.ttf`, `JetBrainsMono-Medium.ttf`, `JetBrainsMono-Regular.ttf`.

### 2.1 The scale (typography.ts:11-18)

`type` is declared `Record<string, TextStyle>` (typography.ts:11) — a plain map, not a closed
union; each entry contains **only** `fontFamily` + `fontSize`.
⚠️ The inline comment on `brand` (typography.ts:12) is STALE: it still says
`'> λ chat' header mark (accent color)`. The actual `brand` call sites render it in
`colors.text` `#FAFAFA` (Brand.tsx:23, ConversationsScreen.tsx:537), not the accent, and the
wordmark is "peers" (§5.14).

| Style | Family | Size (dp/sp) | Weight equivalent | Line height in the token | Use |
|---|---|---|---|---|---|
| `brand` | JetBrainsMono-**Bold** | 16 | 700 | *not set* | Brand mark / wordmark "peers" |
| `title` | JetBrainsMono-**Medium** | 16 | 500 | *not set* | Screen titles, conversation names, menu items, buttons |
| `body` | JetBrainsMono-Regular | 14 | 400 | *not set* | Messages, inputs |
| `label` | JetBrainsMono-Regular | 12 | 400 | *not set* | Labels, previews, status text |
| `caption` | JetBrainsMono-Regular | 10 | 400 | *not set* | Timestamps, badges, system lines |
| `code` | JetBrainsMono-Regular | 13 | 400 | *not set* | Bundle strings, IDs (selectable) |

**No `lineHeight` and no `fontWeight` is set in the token definitions.** Line heights are
applied per-site as overrides:

| lineHeight | Where | Cite |
|---|---|---|
| 20 | `infoIntro` body text; InfoModal `sectionBody` | ChatScreen.tsx:2847; InfoModal.tsx (sectionBody) |
| 18 | Chat header title (`title`); conversation-row title; Settings `helper`; warn body | ChatScreen.tsx:2883; ConversationsScreen.tsx:114; SettingsScreen.tsx:504, 531 |
| 14 | Chat header subtitle (`caption`); conversation-row preview (`label`) | ChatScreen.tsx:2884; ConversationsScreen.tsx:561 |
| 13 | Header last-seen line (`caption`) | ChatScreen.tsx:2886 |
| 34 | FAB "+" glyph (fontSize 32) | SpeedDialFab.tsx:311-312 |
| 30 | BubbleActionMenu "more" glyph (fontSize 28) | BubbleActionMenu.tsx (reactMoreText) |
| 17 | Checkbox checkmark (fontSize 15) | NewConversationScreen.tsx (checkmark) |
| 13 | Staged-image ✕ (fontSize 11) | ChatScreen.tsx:3008 |

### 2.2 Off-scale font sizes (hardcoded, must be reproduced)

| Size | Element | Cite |
|---|---|---|
| 32 | FAB "+" | SpeedDialFab.tsx:311 |
| 28 | BubbleActionMenu "more reactions" | BubbleActionMenu.tsx |
| 26 | PIN keypad digit (`type.title` overridden to 26) | PinPad.tsx (keyLabel) |
| 26 | BubbleActionMenu quick-reaction emoji | BubbleActionMenu.tsx (reactBtnText) |
| 22 | LockScreen title (`type.brand` overridden to 22) | LockScreen.tsx (title) |
| 16 | BubbleActionMenu 📌 pin glyph | BubbleActionMenu.tsx:292 (`pinGlyph`) |
| 15 | MediaViewer "loading" text | MediaViewer.tsx (loading) |
| 15 | Checkbox checkmark | NewConversationScreen.tsx:190 |
| 14 | Pin-**bar** 📌 glyph (composer-area pinned bar — **14, not 16**) | ChatScreen.tsx:3118 (`pinBarPin`) |
| 14 | Composer HQ quality toggle | ChatScreen.tsx:2985 |
| 14 | MediaViewer caption | MediaViewer.tsx (caption) |
| 13 | MediaViewer author row | MediaViewer.tsx (authorText) |
| 12 | MediaSendBubble upload percentage | MediaSendBubble.tsx (pct) |
| 11 | Staged-image remove ✕ | ChatScreen.tsx:3008 |
| 10 | Reaction pill emoji (deliberately ~3/4 size) | ChatScreen.tsx:3152 |

### 2.3 fontWeight usage (applied on top of the mono family)

`'700'` — ErrorToast close ✕ (ErrorToast.tsx:64), SwipeRow ribbon (SwipeRow.tsx:110),
composer HQ toggle (ChatScreen.tsx:2985), gif button (ChatScreen.tsx:3082),
MediaSendBubble pct (MediaSendBubble.tsx).
`'600'` — quote author (ChatScreen.tsx:3090), reply-banner author (ChatScreen.tsx:3105),
SystemLine action (SystemLine.tsx:61), BLE "nearby" (ConversationsScreen.tsx:587),
BubbleActionMenu more (BubbleActionMenu.tsx).
Other text properties: `letterSpacing: 0.5` on the HQ toggle (ChatScreen.tsx:2985) and gif
button (ChatScreen.tsx:3082); `letterSpacing: 1` + `textTransform: 'uppercase'` on side-menu
section labels (SideMenu.tsx:546-553 `sectionLabel`). `textTransform: 'uppercase'` **without**
letterSpacing is also the card-label pattern on the secondary screens —
`{...type.caption, color: colors.textFaint, textTransform: 'uppercase'}` (AboutScreen.tsx:273;
MeshConfigScreen.tsx:333; MeshCoreScreen.tsx:449). `fontStyle: 'italic'` on system-note previews
(ConversationsScreen.tsx:563); `textDecorationLine: 'underline'` on message links
(ChatScreen.tsx:3055).

---

## 3. Spacing, radii, layout

`src/theme/spacing.ts`.

### 3.1 Spacing scale (spacing.ts:2-8)
`xs = 4`, `sm = 8`, `md = 12`, `lg = 16`, `xl = 24`. No larger step exists; `spacing.xl * 2 = 48`
is used for the SideMenu top padding (SideMenu.tsx `panel`), and `spacing.xs + 2 = 6` for the
unread badge's horizontal padding (UnreadBadge.tsx:23).

### 3.2 Radii (spacing.ts:10-14)
- `bubble = 8`
- `card = 8`
- `pill = 999`

Derived/off-scale radii seen in components:
`radii.card - 2 = 6` for media inside a bubble (ChatScreen.tsx:3060, 514, 525, 556;
MediaSendBubble.tsx `media`); `6` for the speed-dial label pill (SpeedDialFab.tsx:331) and
the verify checkbox (NewConversationScreen.tsx); `8` for side-menu items (SideMenu.tsx `item`);
avatar corner radius is `size * 0.22` (HexAvatar.tsx:168, 191); circles use half-of-side
(FAB 28 of 56, send 24 of 48, mini-action 22 of 44, PIN key 38 of 76, status dot 4 of 8).

### 3.3 Layout constants (spacing.ts:16-21)
- `bubbleMaxWidthPct = '78%'`
- `conversationRowHeight = 64`
- `headerHeight = 56`
- `minTouchTarget = 44`

### 3.4 Border widths
`1` is the universal hairline (all cards, inputs, separators, pills). Exceptions:
- `2` — mesh/BLE bubble left edge (`borderLeftWidth` at ChatScreen.tsx:2806 and 2817; the
  adjacent 2805/2816 are the matching `borderLeftColor`), quote block left bar
  (ChatScreen.tsx:3085), reply-banner bar width 2 (ChatScreen.tsx:3103), mesh-banner alert
  bottom border (ChatScreen.tsx:2903).
- `1.5` — PIN dot (PinPad.tsx `dot`), verify checkbox (NewConversationScreen.tsx),
  avatar lock badge ring (HexAvatar.tsx:153), side-menu pencil badge ring (SideMenu.tsx).
- `3` — BLE conversation-row left bar width (ConversationsScreen.tsx:577).
- Separators are drawn as 1px `View`s of `colors.border`, not borders
  (ConversationsScreen.tsx:598; SettingsScreen.tsx:503 with `marginLeft: 16`;
  ContactsScreen.tsx `sep`; SideMenu.tsx `divider`).

### 3.5 Elevation / shadow
RN `elevation` only (no shadow color/offset/blur anywhere in these files):
- FAB: `elevation: 6` (SpeedDialFab.tsx:307)
- Speed-dial mini button: `elevation: 4` (SpeedDialFab.tsx:345)
- Reaction strip: `zIndex: 2, elevation: 2` (ChatScreen.tsx:3133-3134)
- LockScreen overlay: `zIndex: 100, elevation: 100` (LockScreen.tsx `root`)
- Splash overlay: `zIndex: 200, elevation: 200` (App.tsx:188-189)
- MediaViewer overlay: `zIndex: 1000, elevation: 1000` (MediaViewer.tsx `root`)
- Navigation header explicitly has **no** shadow: `headerShadowVisible: false`
  (RootNavigator.tsx:166)

### 3.6 Opacity conventions
| Opacity | Meaning | Cite |
|---|---|---|
| `0.85` | Pressed state on ActionButton | ActionButton.tsx:34 |
| `0.6` | Pressed state on Settings save button | SettingsScreen.tsx:500 |
| `0.4` | Disabled ActionButton | ActionButton.tsx:35 |
| `0.5` | Disabled primary button (NewConversation) | NewConversationScreen.tsx (btnDisabled) |
| `0.45` | Disabled "coming soon" speed-dial action | SpeedDialFab.tsx:326 |
| `0.55` | Pending (in-flight) message bubble | ChatScreen.tsx:2787 |
| `0.9` | Quote block inside a bubble | ChatScreen.tsx:3088 |
| `0.8` | "Tap to open in maps" sub-caption | ChatScreen.tsx:574 |
| `0.35 ↔ 1.0` | **Signature pulse**, 550 ms per leg, looped | StatusPill.tsx:54-63; PulseDot.tsx:22-23; NodeStatusIcon.tsx:27-28; TransportPill.tsx:43-44 |

### 3.7 Motion
- Pulse loop: `timing to 0.35 over 550ms` then `timing to 1.0 over 550ms`, `Animated.loop`.
  Used identically in StatusPill, PulseDot, NodeStatusIcon, TransportPill.
- Speed-dial open/close: `180 ms`, `Easing.out(Easing.cubic)`; "+" rotates `0deg → 45deg`;
  mini actions translate `translateY 12 → 0` with opacity `0 → 1` (SpeedDialFab.tsx:200-206,
  233-236, 152-158).
- Swipe-to-delete commit: `140 ms` slide-out; cancel = spring `bounciness: 0`; arm threshold
  = `min(rowWidth * 0.4, 120)`; haptics `Vibration.vibrate(18)` on arm, `(8)` on disarm
  (SwipeRow.tsx:32, 38, 54-64). Gesture claim requires `g.dx < -12 &&
  |g.dx| > |g.dy| * 1.5` (SwipeRow.tsx:43-44); the ribbon label flips
  `"delete"` → `"release to delete"` at the arm threshold (SwipeRow.tsx:87).
- Long-press delays: bubble `delayLongPress={350}` (ChatScreen.tsx:459); conversation row
  `delayLongPress={300}` (ConversationsScreen.tsx:103).

---

## 4. Dark / light handling

**Peers is DARK-ONLY. There is no light theme.** Confirmed by grep across `src/` and
`App.tsx`: **zero** occurrences of `useColorScheme`, `MD3LightTheme`, or React Navigation
`DefaultTheme`. Evidence:

- `paperTheme` is built from `MD3DarkTheme` with `dark: true` hardcoded — src/theme/index.ts:3, 17-18.
- Navigation theme extends `DarkTheme` only — src/navigation/RootNavigator.tsx:7, 71.
- `<StatusBar barStyle="light-content" backgroundColor={colors.canvas} />` — App.tsx:164.
- Android theme forces black bars with light icons on every device:
  `android:statusBarColor=@color/canvas`, `android:navigationBarColor=@color/canvas`,
  `android:windowLightStatusBar=false`, `android:windowLightNavigationBar=false`,
  `android:windowBackground=@color/canvas` — `android/app/src/main/res/values/styles.xml`.
- `android/app/src/main/res/values/colors.xml` defines `canvas = #0A0A0A` and
  `ic_launcher_background = #0A0A0A`.
- Caveat worth knowing: `AppTheme`'s **parent is `Theme.AppCompat.DayNight.NoActionBar`** —
  a day/night parent — but there is **no `values-night/` resource directory** in the project
  (`android/app/src/main/res/` holds only `drawable`, `mipmap-*`, `values`, `xml`), and every
  window/bar color above is pinned in the single `values/styles.xml`. So DayNight never
  actually switches anything. Do not read the parent name as "there is a light theme".
- The only theme-invariant exception is the QR code, which is *always* white-on-black
  regardless of anything (`colors.qrBg`/`qrFg`, QrCard.tsx:167).

**Canonical = dark.** A QML port should hardcode the dark palette and not build a light mode.

---

## 5. Component specs (literal values)

### 5.1 Message bubble — SENT (own)
`src/screens/ChatScreen.tsx:2777-2792, 419, 463, 580`

- Wrapper: `maxWidth: '78%'`, `gap: 2`, `alignSelf: flex-end`, `alignItems: flex-end` (2777, 2779)
- Fill: `#FF5000` (2786) · Radius: `8` on all corners (2781, no per-corner variation)
- Padding: horizontal `12`, vertical `8` (2782-2783)
- Text: `type.body` = JetBrainsMono-Regular 14, color `#FFFFFF` (`onAccent`) (line 580)
- Links inside own bubble: `#FFFFFF`, underlined (line 587 + 3055)
- Pending: whole bubble `opacity: 0.55` (2787); timestamp text reads `"sending…"` (626)
- Failed: `borderWidth: 1`, `borderColor: #EF4444` (2788); timestamp reads
  `"failed — tap to retry"` in `#EF4444` (624, 628)
- Media bubble: padding collapses to `2/2` with `overflow: hidden`; the image itself gets
  `borderRadius: 6` (2792, 525). While loading/failed it is a `mediaBox` placeholder sized to
  the final media dims, `rgba(0,0,0,0.18)`, `borderRadius 6` (3057-3062), holding either a
  spinner or `type.caption` copy: `'media expired'` / `'media unavailable'` /
  `'media disabled in this group'` (499, 541-545)
- Inline video: first frame paused + a centered `playOverlay` badge `56 × 56`,
  `borderRadius 28`, `rgba(0,0,0,0.45)`, `paddingLeft: 4` to optically center the triangle,
  containing `PlayIcon size={28} color="#fff"` (3073-3081, 517-518)
- Mesh variant: fill becomes `#22C55E` (2811). BLE variant: fill becomes `#0EA5E9` (2814).
- Spinner inside an own bubble: `ActivityIndicator color=#FFFFFF` (536)

### 5.2 Message bubble — RECEIVED (peer)
`src/screens/ChatScreen.tsx:2778, 2785, 580, 587`

- Wrapper: `alignSelf: flex-start`, `alignItems: flex-start` (2778)
- Fill: `#1F1F1F` (`bubblePeer`, colors.ts:14) · Radius `8` · same `12/8` padding
- Text: `type.body` 14, color `#FAFAFA` (580)
- Links: `#4EA3FF` underlined (587, 158)
- Mesh variant: `borderLeftWidth: 2`, `borderLeftColor: #22C55E`, background
  `rgba(34,197,94,0.08)` (2804-2808)
- BLE variant: `borderLeftWidth: 2`, `borderLeftColor: #0EA5E9`, background
  `rgba(14,165,233,0.10)` (2815-2819)
- Spinner inside a peer bubble: `ActivityIndicator color=#6B7280` (536)

### 5.3 Bubble sub-parts
- **Attribution row** (group sender line, ChatScreen.tsx:2848, 422-439): row, `gap: 4`,
  `marginBottom: 2`; a 16px HexAvatar; `type.caption` (10) with `flexShrink: 1` (2849),
  1 line. Two cases: **with** a label → label in `#FAFAFA` + a leading-space hex in `#6B7280`
  in the same `<Text>` (429-430); **without** a label → the hex itself becomes the white
  primary `#FAFAFA` (432-438). Optional `VerifiedBadge size={12}` (439).
  A relayed message replaces the attribution with `{label: relay.origin,
  hex: "· via <bridgeName>"}` (410-417).
- **Timestamp row** (2850-2851, 617-631): `type.caption` 10, `#4B5563`; `marginTop: 12` when
  reactions are present (3139). "via mesh" caption in `#22C55E`, "via BLE · " in `#0EA5E9`
  (2853-2854).
- **Quoted reply block** (3084-3091, 474-485): `borderLeftWidth: 2`, `paddingLeft: 8`,
  `marginBottom: 4`, `opacity: 0.9`; bar+author color = `#FFFFFF` on own / `#FF5000` on peer;
  author `type.caption` weight 600; snippet `type.caption` `#FFFFFF` (own) / `#6B7280` (peer).
- **Reaction pills** (3128-3153, 601-614): absolutely positioned `bottom: -11`, own → `right: 8`,
  peer → `left: 8`, `zIndex/elevation: 2`, `gap: 4`. Pill: `backgroundColor #161616`,
  `borderColor #2a2a2a`, `borderWidth 1`, `borderRadius 999`, `paddingHorizontal 8`,
  `paddingVertical 2`, inner `gap: 3`. Mine: `borderColor #FF5000`, `backgroundColor #2a1607`.
  Emoji `fontSize: 10`; count `type.caption` `#6B7280` — **rendered only when `count > 1`**
  (ChatScreen.tsx:611), so a single reaction is emoji-only. Tap toggles, long-press opens the
  reactor list (606-607).
- **System line** (SystemLine.tsx:48-61): full-width row, `gap 8`, `paddingHorizontal 16`,
  `paddingVertical 8`; two `flex:1` hairlines `height: 1` `#2a2a2a` flanking the text;
  text `type.caption` `#4B5563` centered; optional action `type.caption` `#FF5000` weight 600.
- **Message list**: `padding: 16`, `gap: 8`, inverted (ChatScreen.tsx:2772).

### 5.4 Conversation row
`src/screens/ConversationsScreen.tsx:551-598, 98-168`

- Row: `height: 64` (from `layout.conversationRowHeight`), `backgroundColor #111111` (`pane`),
  `flexDirection: row`, `alignItems: center`, `paddingHorizontal: 16`, `gap: 12` (551-558)
- Avatar: `HexAvatar size={32}` (line 110), `locked` when it's a storage-off group
- Body column `flex: 1` (`rowBody`, 559); title row `gap: 4` (`titleRow`, 550); preview row
  `gap: 8` (`previewRow`, 560)
- Title: `type.title` (JetBrainsMono-Medium 16), `#FAFAFA`, `flexShrink: 1`, `lineHeight: 18`,
  1 line (114)
- Verified badge: `size={14}` (118)
- Group meta: `GroupGlyph size={14} color=#4B5563` + count `type.caption` `#4B5563`,
  pushed right with `marginLeft: 'auto'`, `gap: 3` (123-124, 567-568)
- Mesh tag: `MeshIcon size={14} color=#22C55E` + name `type.caption` `#22C55E`,
  `maxWidth: 110` (132-135, 590-597)
- BLE row: 3px left bar `rgba(14,165,233,0.55)` inset `top/bottom: 8`, radius 2 on the right
  corners (572-581); "nearby" = `PulseDot color=#0EA5E9 pulsing size={6}` + text
  `type.caption` `#0EA5E9` weight 600 (144-146, 587); "via BLE mesh" `type.caption`
  `rgba(56,189,248,0.9)` (585)
- Preview line: `type.label` (12) `#6B7280`, `lineHeight: 14`, `flex: 1`, 1 line (561);
  system-note preview overrides to `#4B5563` + italic (563)
- Timestamp: `type.caption` (10) `#4B5563`, right-aligned by the preview's flex (565)
- Right column: `alignItems: flex-end`, `gap: 4`, holds the UnreadBadge (564)
- Separator between rows: `height: 1`, `#2a2a2a`, full-bleed (598, 462)
- List bottom padding: `88` (to clear the FAB) (549)
- Swipe-to-delete backdrop: whole row wrapper `#5c1a1a`; ribbon right-aligned with
  `paddingRight: 20`, label `type.label` `#EF4444` weight 700 (SwipeRow.tsx:97-111)

### 5.5 Composer
`src/screens/ChatScreen.tsx:2922-2951, 2954-2962, 3160-3169`

Single-line variant (`composer`, 2922-2931):
- `backgroundColor #111111` (`pane`), `borderTopWidth: 1`, `borderTopColor #2a2a2a`
- `padding: 12`, `flexDirection: row`, `alignItems: flex-end`, `gap: 12`, `minHeight: 60`

Two-line variant (`composerV`, 2954-2961):
- same fill/border, `paddingHorizontal: 12`, `paddingVertical: 8`, `gap: 8`;
  row 1 = `flexDirection: row`, `alignItems: flex-end`, `gap: 12` (2962)

Input (`input`, 2932-2943):
- `type.body` (JetBrainsMono-Regular 14), color `#FAFAFA`, `flex: 1`
- `backgroundColor #0A0A0A` (canvas — darker than the composer bar)
- `borderWidth: 1`, `borderColor #2a2a2a`, `borderRadius: 8`
- `paddingHorizontal: 12`, `paddingVertical: 8`, `maxHeight: 120`
- `placeholderTextColor = #4B5563` (2283)

Send button (`send`, 3160-3169):
- `backgroundColor #FF5000`, `width: 48`, `height: 48`, `borderRadius: 24` (perfect circle)
- Icon: `SendIcon` (Lucide `send` paper plane; Lucide `waypoints` in mesh mode),
  default `size 22`, `color = onAccent #FFFFFF`, stroke width 2, round caps (SendIcon.tsx:11-25)
- **The send button has NO busy/spinner state.** `ChatScreen.tsx` contains exactly four
  `ActivityIndicator`s — 536 (media inside a bubble), 1920 (the mesh-banner switch button),
  2156 (load-older footer), 2490 (attach-in-progress) — and none of them is in `styles.send`.

Attach button (`attach`, 2945-2951): `44 × 44`, `borderRadius: 8`.
Action row: `gap: 16`, `paddingLeft: 4`; each action `padding: 4` (3020-3021).
HQ quality toggle: `paddingHorizontal 8 / paddingVertical 6`, `fontSize 14`, weight 700,
`letterSpacing 0.5`, `#4B5563` off → `#FF5000` on (2984-2986).
Staged-image thumb: `64 × 64`, `borderRadius 8`, 1px `#2a2a2a`; remove ✕ is a `20 × 20`
circle (`borderRadius 10`) at `top:-6 / right:-6`, fill `#0A0A0A`, 1px `#2a2a2a`,
glyph 11/13 `#FAFAFA` (2987-3008).
Staged-location chip: row, `gap 8`, fill `#161616`, 1px `#2a2a2a`, `borderRadius 999`,
`paddingVertical 4 / paddingHorizontal 12`; text `type.label` `#FAFAFA`; clear glyph
`type.label` `#6B7280` (2964-2978).
Reply banner: row, `gap 8`, `paddingVertical 4 / paddingHorizontal 8`, `marginBottom 4`,
fill `#161616`, `borderRadius 8`; 2px full-height bar `#FF5000`; author `type.caption`
`#FF5000` weight 600; snippet `type.caption` `#6B7280` (3093-3106).
Recording bar: fill `#111111`, 1px top `#2a2a2a`, `paddingHorizontal 12 / paddingVertical 8`,
`gap 8`; rec dot `12 × 12` radius 6 `#EF4444`; controls row `gap: 12` (3040); waveform row
`alignSelf: stretch`, `height: 30`, `marginHorizontal: 8`, `gap: 2`, `overflow: hidden`, bars
`flex: 1`, `marginHorizontal: 0.5`, `borderRadius: 1.5` — bar height and color are set
**inline per amplitude level**, not in the stylesheet (3025-3051).
Elapsed time `type.body` `#FAFAFA` `marginLeft 8` (3026); rec caption `type.caption` `#4B5563`
(3027); cancel hit `paddingHorizontal 12` (3028).

Mesh banner (group threads, ChatScreen.tsx:2888-2904): row, `gap 12`,
`paddingHorizontal 12 / paddingVertical 8`, fill `#111111` (`pane`), `borderBottomWidth 1`
`#2a2a2a`. Variants: mesh-on → bottom border `#22C55E` (2898); node-offline alert → fill
`rgba(239,68,68,0.12)` + bottom border `#EF4444` at width **2** (2900-2904). Its (i) button
is a 44 × 44 touch target (2916-2921); its action button is in §5.9.

### 5.6 Screen header

Two distinct headers exist.

**(a) Native-stack header** (all screens except Conversations) —
`src/navigation/RootNavigator.tsx:162-167`:
- `headerStyle.backgroundColor = #161616` (`panel`)
- `headerTintColor = #FAFAFA`
- `headerTitleStyle = type.title` (JetBrainsMono-Medium 16) + `color #FAFAFA`
- `headerShadowVisible: false`
- screen `contentStyle.backgroundColor = #0A0A0A`
- Conversations sets `headerShown: false` (line 186) and draws its own.

**(b) Conversations custom header** — `src/screens/ConversationsScreen.tsx:517-547, 404-419`:
- `height: 56` (`layout.headerHeight`), `backgroundColor #161616`,
  `borderBottomWidth: 1`, `borderBottomColor #2a2a2a`
- `flexDirection: row`, `alignItems: center`, `justifyContent: space-between`,
  `paddingHorizontal: 16`
- Left: 32px HexAvatar (opens the side menu), `hitSlop: 12`
- Center: absolutely-positioned, non-interactive title layer, `type.brand`
  (JetBrainsMono-Bold 16) `#FAFAFA`
- Right slot: `minWidth: 50`, `height: 34`, right-aligned — holds the TransportPill
  (22px glyphs, `gap: 6`, `minHeight: 34`) (TransportPill.tsx:26, 114-120)

**(c) Chat header content** — `src/screens/ChatScreen.tsx:2863-2886`:
- Left cluster: row, `gap: 8`, `marginLeft: -8`, `maxWidth: 300`; back button `padding: 4`
- Title text: `type.title` `#FAFAFA` `lineHeight: 18`
- Subtitle: `type.caption` `#6B7280` `lineHeight: 14`
- Last-seen line: `type.caption` `#4B5563` `lineHeight: 13`
- Header action button target: `minWidth/minHeight = 44`

### 5.7 Empty states
- **Conversations** (ConversationsScreen.tsx:599-602, 420-435): container
  `flex:1, alignItems:center, justifyContent:center`; text `type.label` (12) `#6B7280`,
  `textAlign: center`, `maxWidth: 240`. All six literal strings (420-435) — the last is the
  default for `all`:
  - chats — `'no direct chats yet — add a contact with the + button'`
  - groups — `'no groups yet — create one with the + button'`
  - mesh-channels — `'no mesh channels yet — join one from the MeshCore page'`
  - mesh-dms — `'no mesh DMs yet — start one from the MeshCore page'`
  - ble-dms — `'no Bluetooth chats yet — meet a nearby peer from the Discovery page'`
  - default/all — `'no conversations — tap the + button to add a contact by address'`

  The header title comes from the same view key: `VIEW_TITLE` = `all→'All'`, `chats→'Chats'`,
  `groups→'Groups'`, `mesh-channels→'Channels'`, `mesh-dms→'Mesh DMs'`,
  `ble-dms→'Bluetooth DMs'` (ConversationsScreen.tsx:172-179).
  A non-empty row's preview falls back to `'new group'` / `'new conversation'` (line 160).
- **Contacts** (ContactsScreen.tsx): container adds `padding: 24`; text `type.label`
  `#6B7280` centered (no maxWidth).
- **Chat thread** (ChatScreen.tsx:2145-2147, 2773-2774): no illustration or copy — the
  empty list is just `flexGrow: 1` with a `flex: 1` spacer (inverted list keeps content bottom).

### 5.8 Loading states
- Spinner = RN `ActivityIndicator` (no custom spinner anywhere). Color convention:
  `colors.accent #FF5000` on a plain surface (LockScreen.tsx:120; SettingsScreen.tsx:416;
  TorBootstrapModal.tsx:32), `colors.onAccent #FFFFFF` when sitting on an accent-filled
  button/bubble (NewGroupScreen.tsx:151; MeshConfigScreen.tsx:307; MeshCoreScreen.tsx:295, 379;
  NewConversationScreen.tsx:127; ChatScreen.tsx:1920 — the mesh-banner switch button),
  `colors.textDim #6B7280` on a peer/dim surface (ChatScreen.tsx:536, 2156, 2490).
  Three of those four ChatScreen sites are ternaries — 536 is `own ? onAccent : textDim`,
  1920 is `meshMode ? textDim : onAccent`. Only **2490** passes `size="small"`; every other
  call site uses the RN default size.
- Load-older spinner in the thread: `paddingVertical: 12`, centered (ChatScreen.tsx:2776).
- App splash / pre-unlock cover: absolute fill, `backgroundColor #0A0A0A`, centered
  `Logo size={56} color=#FF5000 strokeWidth={2}`, `zIndex/elevation: 200` (App.tsx:171-193).

### 5.9 Button variants

**ActionButton — the shared primary/secondary pair** (`src/components/ActionButton.tsx:46-62`):
- Base: `minHeight: 48`, `borderRadius: 8`, `paddingHorizontal: 16`, centered both axes
- Label: `type.title` (JetBrainsMono-Medium 16) — **identical size for both variants**
- `primary`: `backgroundColor #FF5000`, label `#FFFFFF`
- `secondary`: `backgroundColor: transparent`, `borderWidth: 1`, `borderColor #FF5000`,
  label `#FF5000`
- Pressed: `opacity 0.85`; disabled: `opacity 0.4`

**FAB** (`src/components/SpeedDialFab.tsx:298-315`): `56 × 56`, `borderRadius: 28`,
`position: absolute`, `right: 16`, `bottom = safeAreaBottom + 16`, `elevation: 6`,
fill = section color (Logos `#FF5000` / mesh `#22C55E` / BLE `#0EA5E9`,
ConversationsScreen.tsx:184-187). Glyph "+" `#FFFFFF`, `fontSize: 32`, `lineHeight: 34`,
`includeFontPadding: false`, rotates to 45° when open.

**Speed-dial mini action** (SpeedDialFab.tsx:316-346): button `44 × 44`, `borderRadius: 22`,
fill `#161616`, 1px `#2a2a2a`, `elevation: 4`; label pill fill `#161616`, 1px `#2a2a2a`,
`borderRadius: 6`, `paddingHorizontal: 8 / paddingVertical: 4`, text `type.label` `#FAFAFA`;
row `gap: 8`, `hitSlop: 6` (line 165), right offset `16 + 6 = 22`; vertical stack position
`bottom = base + 56 + 12 + i * (44 + 12)` (line 264). The label pill **and** the icon are one
tap target (161-178). Disabled ("coming soon") actions get `opacity 0.45` and are inert.

**Compact secondary button** (SettingsScreen.tsx:492-501): `paddingVertical 8 /
paddingHorizontal 12`, `borderRadius 8`, 1px `#2a2a2a`, fill `#161616`, label `type.label`
`#FAFAFA`, pressed `opacity 0.6`. Text-only reset button: same padding, `type.label` `#6B7280`
(489-490).

**Filled start button** (NewConversationScreen.tsx): fill `#FF5000`, `borderRadius 8`,
`paddingHorizontal 24 / paddingVertical 8`, `minHeight 44`, `alignSelf: flex-start`,
disabled `opacity 0.5`.

**Modal done button** (InfoModal.tsx): fill `#FF5000`, `borderRadius 8`,
`paddingHorizontal 24`, `minHeight 44`.

**Destructive button**: fill `#EF4444` (SettingsScreen.tsx:534 `dangerFlex`;
LockScreen.tsx `dangerBtn`).

**Mesh banner button** (ChatScreen.tsx:2906-2914): `borderRadius 8`, `paddingHorizontal 12`,
`minHeight 36`; "go" fill `#22C55E`; "back" transparent with 1px `#2a2a2a`.

### 5.10 Input fields

Three shapes exist; they differ only by ground color.

| Variant | Ground | Border | Radius | Padding | Min height | Font | Cite |
|---|---|---|---|---|---|---|---|
| Composer input | `#0A0A0A` | 1px `#2a2a2a` | 8 | h12 / v8 | — (`maxHeight 120`) | `type.body` 14 `#FAFAFA` | ChatScreen.tsx:2932-2943 |
| Form input | `#111111` | 1px `#2a2a2a` | 8 | 12 all round | 44, `textAlignVertical: center` | `type.body` 14 `#FAFAFA` | NewConversationScreen.tsx:166-177 |
| Search field | `#111111` | 1px `#2a2a2a` | 8 | h12 | 40, `textAlignVertical: center` | `type.body` 14 `#FAFAFA` | ContactsScreen.tsx (search) |
| Multiline node URL | `#0A0A0A` | 1px `#2a2a2a` | 8 | 8 | 64, `textAlignVertical: top` | `type.label` 12, `fontFamily: 'monospace'` | SettingsScreen.tsx:469-481 |

`placeholderTextColor` is **always** `colors.textFaint` `#4B5563` — 19 call sites, e.g.
ChatScreen.tsx:2283, 2432; ContactsScreen.tsx:265; SettingsScreen.tsx:252;
NewConversationScreen.tsx:99; SideMenu.tsx:328. No `selectionColor`/`cursorColor` is ever set.

Inline editable name (SideMenu.tsx `headerNameInput`): `type.title` `#FAFAFA`,
`padding: 0`, `margin: 0` (no chrome).

Checkbox (NewConversationScreen.tsx): `24 × 24`, `borderRadius 6`, `borderWidth 1.5`,
`borderColor #2a2a2a`; checked → fill and border `#1D9BF0` (`verified`), checkmark
`#FFFFFF` `fontSize 15` `lineHeight 17`.

### 5.11 Badges / chips / pills

**UnreadBadge** (`src/components/UnreadBadge.tsx:17-31`):
`backgroundColor #EF4444`, `borderRadius 999`, `minWidth 20`, `height 20`,
`paddingHorizontal 6` (`spacing.xs + 2`), centered; text `type.caption` (10) `#FFFFFF`;
count capped at `"99+"` (line 12); renders `null` when `count <= 0`.

**StatusPill** (`src/components/StatusPill.tsx:81-102`):
row, `alignSelf: flex-start`, fill `#161616`, `borderWidth 1` `#2a2a2a`, `borderRadius 999`,
`paddingHorizontal 12`, `paddingVertical 4`, `gap 8`. Dot `8 × 8` `borderRadius 4`.
Dot+label share a color: `stopped → #4B5563`, `initializing|starting → #F59E0B` (pulsing),
`running → #FF5000`, `error → #EF4444` (20-26). Label = `type.label` (12); reads
`"running + mix"` when mix is on, otherwise the raw status string (line 47-48).
Mix override (41-46): when `running && mixEnabled && mixShort` the dot goes **amber `#F59E0B`
and pulses** even though the status is `running` — a healthy mix goes back to steady `#FF5000`.
So `pulsing = initializing || starting || mixWaiting`.

**TransportPill** (TransportPill.tsx:26, 113-120): no fill/border — just a row of 22px
SVG glyphs, `gap: 6`, `minHeight: 34`, `justifyContent: flex-end`; each glyph tinted by its
tri-state color and breathing when connecting.

**VerifiedBadge** (`src/components/VerifiedBadge.tsx:24-44`): SVG, default `size 15`,
9-lobed scalloped seal, bump radius `11.2`, valley radius `8.6`, center `(12,12)` in a
`0 0 24 24` box; fill `#1D9BF0`; white checkmark polyline `8.4,12.3 11,14.8 15.7,9.2`,
`strokeWidth 2`, round caps/joins. Used at `size 12` (bubble attribution, ChatScreen.tsx:439)
and `size 14` (conversation row / menu header, ConversationsScreen.tsx:118, 505).

**Contacts filter tabs / chips** (ContactsScreen.tsx): `paddingHorizontal 12 /
paddingVertical 4`, `borderRadius 8`, 1px `#2a2a2a`, text `type.label` `#6B7280`;
active → fill and border `#FF5000`, text `#FFFFFF`.

**Reaction pill**: see §5.3.

**Pinned-message bar** (ChatScreen.tsx:3108-3122): fill `#161616`, 1px bottom `#2a2a2a`,
`paddingHorizontal 16 / paddingVertical 8`, `gap 8`; 📌 `fontSize 14` (3118 — **14, not 16**;
the 16 belongs to BubbleActionMenu's `pinGlyph`); text column `flex: 1` `gap: 1`; label
`type.caption` `#FF5000`; message `type.label` `#FAFAFA`; clear glyph `type.title` `#6B7280`
with `paddingHorizontal 4`.

**Unverified trust strip** (ChatScreen.tsx:2759-2770): fill `#F59E0B22`, `borderBottomWidth 1`
`#F59E0B`, `paddingHorizontal 16 / paddingVertical 8`, `gap 12`; text `type.caption` `#FAFAFA`;
"verify" action `type.label` `#F59E0B`.

### 5.12 Cards, menus, modals, toast

**Card** (SettingsScreen.tsx:446-452; NewConversationScreen.tsx; InfoModal.tsx):
fill `#161616`, `borderWidth 1` `#2a2a2a`, `borderRadius 8`, `overflow: hidden`;
content padding `16` (settings rows) or `24` (modals). Danger card swaps the border to
`#C62828` (SettingsScreen.tsx:505-512).

**Settings row** (SettingsScreen.tsx:453-465): row, `space-between`, `gap 12`,
`padding 16`, `minHeight 52`; text column `flex: 1` `gap: 2`; label `type.title` `#FAFAFA`;
value `type.label` `#6B7280`; sub-line `type.caption` `#6B7280`;
section heading `type.label` `#FF5000` `marginTop 8` (445); helper `type.label` `#6B7280`
`lineHeight 18` `marginBottom 12` (504); separator 1px `#2a2a2a` inset `marginLeft: 16` (503);
screen content `padding 16` `gap 12` (444). The Network card takes its own `padding 16`
instead of row padding (`networkCard`, 468).

**Settings destructive-confirm modal** (SettingsScreen.tsx:513-534): backdrop
`rgba(0,0,0,0.7)` + `padding 16`, centered; card fill **`#0A0A0A` (canvas, not panel)**,
1px `#C62828`, `borderRadius 8`, `padding 24`, `gap 12`, `width '100%'`, `maxWidth 380`;
title `type.title` `#EF4444`; body `type.label` `#6B7280` `lineHeight 18`; actions row
`gap 12` `marginTop 8`, the destructive one `flex: 1` filled `#EF4444`.
(LockScreen's warn card is the same shape but fill `#161616`, `padding 16`, `gap 8`,
`maxWidth 360` — LockScreen.tsx:173-184.)

**OverflowMenu card** (OverflowMenu.tsx): fill `#161616`, 1px `#2a2a2a`, `borderRadius 8`,
`paddingVertical 4`, `minWidth 216`, `maxWidth 320`; row `minHeight 44`,
`paddingHorizontal 16 / paddingVertical 8`, `gap 12`; label `type.body` (14) `#FAFAFA`;
destructive label `#EF4444`; backdrop `rgba(0,0,0,0.5)`.

**SideMenu** (SideMenu.tsx): panel anchored left, fill `#161616`, `borderRightWidth 1`
`#2a2a2a`, `paddingTop 48`, `paddingHorizontal 12`, `gap 12`; backdrop `rgba(0,0,0,0.6)`;
item row `gap 16`, `paddingVertical 12 / paddingHorizontal 8`, `borderRadius 8`,
active fill `#111111`; item label `type.title` `#FAFAFA`; icon column `width 22`;
section label `type.label` `#4B5563` uppercase `letterSpacing 1`; divider 1px `#2a2a2a`
with `marginVertical 4`; header name `type.title` `#FAFAFA`, hex `type.label` `#6B7280`;
pencil badge `18 × 18` radius 9 fill `#FF5000` with a `1.5px #0A0A0A` ring at `bottom/right: -2`.

**InfoModal** (InfoModal.tsx): backdrop `rgba(0,0,0,0.6)` with `padding 24`; card fill
`#161616`, 1px `#2a2a2a`, `borderRadius 8`, `padding 24`, `gap 16`, `maxHeight '80%'`;
heading `type.title` `#FAFAFA`; section title `type.label` `#FF5000`; body `type.body`
`#6B7280` `lineHeight 20`.

**ErrorToast** (ErrorToast.tsx:36-70): bottom-anchored, `bottom: 24`, `marginHorizontal 16`;
fill `#5c1a1a`, 1px `#C62828`, `borderRadius 8`, `paddingHorizontal 16`,
`paddingTop 20` (`lg + xs`), `paddingBottom 12`; text `type.label` `#EF4444`;
close ✕ at `top: 4 / left: 4`, `paddingHorizontal 4`, `zIndex 1`, `hitSlop 12`,
`type.label` `#EF4444` weight 700. The outer wrapper is `pointerEvents="box-none"` so only
the toast itself is interactive; it renders `null` when `message == null`.
**Persistent — no auto-dismiss** (ErrorToast.tsx:2-3), contradicting the "4s auto-dismiss"
in `docs/theme.md:95`.

**PinPad** (PinPad.tsx): root `gap 24`; dots row `gap 12`, `marginBottom 16`; dot
`14 × 14` `borderRadius 7` `borderWidth 1.5` `borderColor #6B7280`; filled → fill+border
`#FF5000`; error → border `#EF4444`, transparent fill. Key `76 × 76` `borderRadius 38`,
fill `#161616`, 1px `#2a2a2a`; label `type.title` overridden to `fontSize 26` `#FAFAFA`;
pad width `3*76 + 2*12 = 252`, `justifyContent: space-between`, `rowGap 12`.
LockScreen: fill `#0A0A0A`, title `type.brand` overridden to `fontSize 22` `#FAFAFA`,
subtitle `type.label` `#6B7280` centered, `gap 24`, `padding 16`.

**QrCard** (QrCard.tsx): card fill **always `#FFFFFF`** (`colors.qrBg`, :167),
`borderRadius 8`, `overflow: hidden`, default `size 260`, quiet zone `QUIET_MODULES = 4`
(:17), error correction `'M'` — or `'H'` when a center badge occludes modules (:45).
The whole thing is one `<Svg>` whose viewBox is `total = moduleCount + 8` units wide, so all
badge geometry below is in **module units**, not px (:57-70):
- outer white tile `backing = total * 0.26`, origin `(total - backing)/2`,
  corner `rx/ry = backing * 0.24`, fill `qrBg` (:63-64, 100-108)
- white stroke thickness `stroke = backing * 0.08`; dark tile `tile = backing - stroke`
  (the stroke is what shows as the border), fill `colors.canvas #0A0A0A`,
  `rx/ry = tile * 0.22` (:65-67, 137-145)
- identicon area `inner = tile * 0.78`, `cell = inner / 5`, cells from the shared
  `identiconCells()` — same engine as HexAvatar (:68-71)
- a custom avatar photo (`badgeImageUri`) replaces the identicon, clipped to the same
  `tile * 0.22` rounded rect via a `ClipPath` (:109-133)
- optional caption band `capUnits = total * 0.18` tall appended under the QR inside the same
  Svg (so a captured PNG includes it), `fontSize = capUnits * 0.5`, `fontWeight="bold"`,
  `fontFamily="monospace"`, fill `qrFg #000000`; rendered height becomes
  `round(size * (total + capUnits) / total)` (:73-78, 88-95)

**MediaViewer** (MediaViewer.tsx): overlay `zIndex/elevation 1000`, page ground `#000`;
close circle `40 × 40` radius 20 `rgba(0,0,0,0.45)` at `top 44 / right 16`;
bottom bar `rgba(0,0,0,0.6)`, `paddingTop 12 / paddingBottom 28 / paddingHorizontal 16`,
`gap 10`; caption `#fff` `fontSize 14` centered; author label `#fff` `fontSize 13`,
hex `rgba(255,255,255,0.6)`; loading text `rgba(255,255,255,0.6)` `fontSize 15`;
author row `gap 8` with the label `flex: 1` `fontSize 13`; actions row `space-around`
`paddingTop 4`, each action hit `padding 14`. The root itself is
`backgroundColor: 'transparent'` — the per-page `black` style (`#000`) supplies the ground.

**MediaSendBubble** — the outgoing-upload bubble (MediaSendBubble.tsx:68-100):
row `justifyContent: flex-end`, `paddingHorizontal 12 / paddingVertical 4`; bubble fill
`#FF5000` (`accent`), `borderRadius 8`, `padding 4`; media square `borderRadius 6`
(`radii.card - 2`), `overflow: hidden`; video poster fallback + progress scrim both
`rgba(0,0,0,0.35)`; percentage text `#fff` `fontSize 12` weight `700`; caption/label
`type.caption` `#FFFFFF` (`onAccent`) centered, `paddingVertical 4`.

### 5.13 Avatars (HexAvatar)
`src/components/HexAvatar.tsx`

- Shape: square, `borderRadius = size * 0.22`, `overflow: hidden`, ground `#0A0A0A` (188-194)
- Grid: `AVATAR_N = 5` (line 61); cell = `size / 5`; each rect drawn `cell + 0.5` wide/tall
  so anti-aliasing leaves no seam (177-182)
- Symmetry: only columns 0..2 are decided; columns 0,1 mirror to 4,3 (79-91)
- PRNG: xmur3 hash → mulberry32, seeded with `PREFIX[kind] + seed` where
  `PREFIX = {contact:'c:', group:'g:', mesh:'m:', ble:'b:'}` (41-59, 77)
- Fill rule: skip the cell if `r() > 0.5`, else `ramp[floor(r() * 5)]` (82-85)
- Custom photo avatar: same `borderRadius = size * 0.22` (168)
- Lock badge overlay: `size * 0.5` circle at `bottom/right: -2`, fill `#FF5000`,
  `borderWidth 1.5` `#0A0A0A`, lock icon `size * 0.38` in `#FFFFFF` (139-159)
- Sizes in use: 16 (bubble attribution), 32 (conversation row, header, menu header),
  40 (default)

### 5.14 Brand mark
`src/components/Brand.tsx:11-24` — row, `gap 8`: `NodeStatusIcon size={26}` (the Logos glyph
tinted by node status) + the wordmark **"peers"** in `type.brand` (JetBrainsMono-Bold 16)
`#FAFAFA`. The old `> λ chat` mark described in `docs/theme.md:5` (and echoed at theme.md:40,
55, plus the stale `typography.ts:12` comment) **no longer exists** in code — Brand.tsx:3
records the rename explicitly.
Logo glyph itself: single fill path in a `0 0 32 32` viewBox with `transform="translate(6 3)"`,
sourced from logos.co favicon (Logo.tsx:18-25); defaults `size 24` / `color = colors.accent`;
`strokeWidth` is accepted but **ignored** (the mark is fill-based, Logo.tsx:11-12).
`NodeStatusIcon` wraps it: defaults `size 24`, `strokeWidth 2`, tint `nodeStatusColor(status)`,
and pulses `0.35 ↔ 1.0` while `initializing | starting` (NodeStatusIcon.tsx:11-41).

---

## 6. Things a QML author will look for and NOT find in this source

- **No light theme, no theme switching, no `useColorScheme`.** Dark is the only mode.
- **No shadow specs** — only integer `elevation`. If QML needs drop shadows, invent them.
- **No `lineHeight` in the type tokens** — only per-site overrides (listed in §2.1).
- **No `fontWeight` in the type tokens** — weight is carried by the font *family* name.
- **No per-corner bubble radii** (no "tail corner"); every bubble is a uniform 8px.
- **No delivery/read ticks** — status is only `pending` (opacity 0.55 + "sending…") or
  `failed` (red border + "failed — tap to retry"). `docs/theme.md:65-67` confirms this is
  intentional (the lib emits no delivery acks).
- **No `selectionColor` / `cursorColor`** on any TextInput.
- **No animation/duration token file** — durations are literals (550 / 180 / 140 ms).
- **No `spacing` value above 24** as a token.
