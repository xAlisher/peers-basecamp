# Peers icon set — ground truth for the desktop QML port

Source of truth: `<logos-chat-android>`, read 2026-08-09.
Every value below is transcribed verbatim from the file+line cited. Nothing is inferred.

## 0. Structural facts (read these first)

- **There is NO icon barrel / index file.** `src/components/index.ts` does not exist
  (`ls src/components/index.ts` → "No such file or directory"). Every icon is imported
  from its own module path.
- **No icon font, no `react-native-vector-icons`.** Every glyph is drawn with
  `react-native-svg` primitives (`Svg`, `Path`, `Circle`, `Rect`, `Line`, `Polyline`).
  Stated explicitly at `src/components/QrIcon.tsx:1-2`, `src/components/SendIcon.tsx:1-2`,
  `src/components/OverflowMenu.tsx:6-7`. The only SVG dependency is
  `"react-native-svg": "^15.15.5"` (`package.json:26`).
- **File inventory.** `ls src/components/*Icon*.tsx` returns **10** files
  (`ImageIcon, InfoIcon, LockIcon, MediaIcons, MediaViewerIcons, NodeStatusIcon, QrIcon,
  SendIcon, TrashIcon, XIcon`); only 8 of those end in exactly `Icon.tsx` — `MediaIcons.tsx`
  and `MediaViewerIcons.tsx` are multi-icon modules, and `NodeStatusIcon.tsx` draws nothing
  itself (it is a tinted wrapper around `Logo`). Beyond those, **15 icons live inline inside
  `OverflowMenu.tsx`** (all exported), **10 inside `SideMenu.tsx`** (module-local, not
  exported), **4 inside `SpeedDialFab.tsx`** (all exported).
  Glyph-drawing count: 8 in the standalone files (`SendIcon` draws two different variants)
  + 5 in `MediaIcons` + 3 in `MediaViewerIcons` + 15 in `OverflowMenu` + 10 in `SideMenu`
  + 4 in `SpeedDialFab` = **45 drawings**, of which one pair is geometrically identical
  (`SendIcon` mesh variant ≡ `OverflowMenu`'s `MeshIcon`, different stroke width) — so
  **44 distinct shapes** — plus 4 brand/transport marks (`Logo`, `BleLogo`, `MeshLogo`,
  `ShieldLogo`) and 1 procedural badge (`VerifiedBadge`).
- **The complete set of files that import `react-native-svg`** (verified by grep, so nothing
  below is missed): the 10 `*Icon*` files, `BleLogo`, `Logo`, `MeshLogo`, `ShieldLogo`,
  `VerifiedBadge`, `OverflowMenu`, `SideMenu`, `SpeedDialFab`, `HexAvatar`, `QrCard`,
  `MediaSendBubble`, `AddressModal` (type-only), `MyAddressScreen` (type-only).
- **Almost every icon uses `viewBox="0 0 24 24"` with `fill="none"` on the root `<Svg>`.**
  The two exceptions are `Logo.tsx` (viewBox `0 0 32 32`) and `HexAvatar` / `MediaSendBubble`
  (no viewBox — pixel-sized `<Svg>`).
- **QML porting caveat:** many glyphs are NOT path data. They use `<Rect>`, `<Circle>`,
  `<Line>`, `<Polyline>`. In QML use `Rectangle`/`Shape` + `PathAngleArc`/`PathLine`, or
  convert. Each entry below flags "primitives" vs "path only".
- **House rule (from user memory + code comments): Lucide only, never emoji-as-icon.**
  Confirmed in `src/components/LockIcon.tsx:4` ("Lucide-only, never an emoji"),
  `src/components/MediaViewerIcons.tsx:2` ("Never emoji."), `src/components/OverflowMenu.tsx:184-185`
  ("icons are Lucide SVGs, never emoji-as-icon"). Emoji appear ONLY as *content*
  (reactions in `EmojiGridModal.tsx`, `BubbleActionMenu.tsx`, and the
  "📷 Photo" preview string at `src/screens/ChatScreen.tsx:1952`).

### Shared stroke constants

| Constant | Value | Source |
|---|---|---|
| `S` (menu glyph size) | `20` | `src/components/OverflowMenu.tsx:23` |
| `SW` (menu glyph stroke width) | `1.8` | `src/components/OverflowMenu.tsx:24` |
| SideMenu `Icon` box | `width={22} height={22} viewBox="0 0 24 24" fill="none"` | `src/components/SideMenu.tsx:44` |
| SideMenu `stroke()` helper | `strokeWidth: 1.8`, `strokeLinecap: 'round'` (+ extras) | `src/components/SideMenu.tsx:49-54` |
| TransportPill glyph size | `GLYPH = 22` | `src/components/TransportPill.tsx:26` |

### Color tokens referenced as icon defaults (`src/theme/colors.ts`)

| Token | Hex | Line |
|---|---|---|
| `canvas` | `#0A0A0A` | 3 |
| `pane` | `#111111` | 4 |
| `panel` | `#161616` | 5 |
| `border` | `#2a2a2a` | 6 |
| `text` | `#FAFAFA` | 7 |
| `textDim` | `#6B7280` | 8 |
| `textFaint` | `#4B5563` | 9 |
| `accent` | `#FF5000` | 10 |
| `accentHover` | `#FF7A33` | 11 |
| `accentPressed` | `#CC4000` | 12 |
| `onAccent` | `#FFFFFF` | 13 |
| `bubblePeer` | `#1F1F1F` | 14 |
| `unread` | `#EF4444` | 15 |
| `pulse` | `#F59E0B` | 16 |
| `nodeOnline` | `#FF5000` | 18 |
| `nodeConnecting` | `#9CA3AF` | 21 |
| `nodeOffline` | `#EF4444` | 22 |
| `contact` | `#FF5000` | 23 |
| `verified` | `#1D9BF0` | 24 |
| `errorFill` | `#5c1a1a` | 25 |
| `errorBorder` | `#C62828` | 26 |
| `qrBg` | `#FFFFFF` | 27 |
| `qrFg` | `#000000` | 28 |

Transport / tri-state colors used to tint icons (`src/components/tri.ts:17-26`):
`offline #EF4444`, `connecting #EAB308`, `online #22C55E`, `TRI_MUTED #6B7280`.
`triColorFor(tri, kind)` — mesh/ble offline → `TRI_MUTED`, otherwise the traffic light
(`src/components/tri.ts:30-33`).
Ad-hoc constants: `MESH_GREEN = '#22C55E'` (`src/screens/ChatScreen.tsx:155`,
`src/screens/ContactsScreen.tsx:39`, `src/screens/GroupInfoScreen.tsx:28`,
`src/screens/ConversationsScreen.tsx:49`, `src/components/MeshInfoModal.tsx:24`);
`BLE_BLUE = '#0EA5E9'` (`src/screens/ChatScreen.tsx:173`, `src/screens/AddMembersScreen.tsx:48`,
`src/screens/ConversationsScreen.tsx:51`);
`FAB_COLOR = {logos: colors.accent, mesh: '#22C55E', ble: '#0EA5E9'}`
(`src/screens/ConversationsScreen.tsx:184-188`).

---

## 1. Standalone icon files

### 1.1 `ImageIcon` — Lucide `image`
File: `src/components/ImageIcon.tsx` (lines 7-40). Composed of **primitives + 1 path.**

- Props/defaults: `size = 24`, `color = colors.text` (`#FAFAFA`), `strokeWidth = 2` (lines 8-10)
- Root: `viewBox="0 0 24 24" fill="none"` (line 17)
- `<Rect x=3 y=3 width=18 height=18 rx=2 ry=2 stroke={color} strokeWidth={strokeWidth} fill="none" />` (lines 18-28)
- `<Circle cx=9 cy=9 r=2 stroke={color} strokeWidth={strokeWidth} fill="none" />` (line 29)
- `<Path>` (lines 30-37), `strokeLinecap="round" strokeLinejoin="round" fill="none"`:
```
m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21
```
- Used: `src/screens/ChatScreen.tsx` — `<ImageIcon size={22} color={colors.textDim} />` (composer attach-image button, #197)

### 1.2 `InfoIcon` — Lucide `info`
File: `src/components/InfoIcon.tsx` (lines 7-29). **Primitives only — no path data.**

- Props/defaults: `size = 18`, `color = colors.textDim` (`#6B7280`) (lines 8-9)
- Root: `viewBox="0 0 24 24" fill="none"` (line 15)
- `<Circle cx=12 cy=12 r=10 stroke={color} strokeWidth={1.8} />` (line 16)
- `<Line x1=12 y1=11 x2=12 y2=16 stroke={color} strokeWidth={1.8} strokeLinecap="round" />` (lines 17-25)
- `<Circle cx=12 cy=8 r=1 fill={color} />` (line 26) — the dot is FILLED, not stroked
- Used: `src/components/InfoModal.tsx` (`size={24} color={colors.accent}`),
  `src/components/SystemLine.tsx` (`size={15} color={colors.textFaint}`),
  `src/screens/NewGroupScreen.tsx` (`size={15} color={colors.textFaint}`),
  `src/screens/GroupInfoScreen.tsx` (×2, `size={15} color={colors.textFaint}`),
  `src/screens/ChatScreen.tsx` (menu item `color={colors.textDim}`; `color={meshMode ? MESH_GREEN : colors.textDim}`; `size={22} color={colors.textDim}`)

### 1.3 `LockIcon` — Lucide `lock`
File: `src/components/LockIcon.tsx` (lines 9-28). **1 filled Rect + 1 stroked path.**

- Props/defaults: `size = 18`, `color = colors.text` (lines 10-11)
- Root: `viewBox="0 0 24 24" fill="none"` (line 17)
- `<Rect x=3 y=11 width=18 height=11 rx=2 ry=2 fill={color} />` (line 18) — body is SOLID FILL
- `<Path>` (lines 19-25), `strokeWidth={2} strokeLinecap="round" strokeLinejoin="round"`:
```
M7 11V7a5 5 0 0 1 10 0v4
```
- Used: `src/components/HexAvatar.tsx:158` — `<LockIcon size={iconSize} color={colors.onAccent} />`
  inside the storage-off badge (#344). Badge geometry: `badgeSize = round(size*0.5)`,
  `iconSize = round(size*0.38)`, circular, `backgroundColor: colors.accent`,
  `borderWidth: 1.5`, `borderColor: colors.canvas`, `bottom: -2, right: -2`
  (`src/components/HexAvatar.tsx:139-159`)

### 1.4 `QrIcon` — stylised QR (NOT a stock Lucide glyph)
File: `src/components/QrIcon.tsx` (lines 8-29). Comment at line 9-10 says it's hand-drawn
("three QR finder patterns … plus a scatter of modules — unmistakably 'QR' without a font
icon set"). `OverflowMenu.tsx:8` calls it "lucide `qr-code`", but the drawing is bespoke.

- Props/defaults: `size = 24`, `color = colors.accent` (`#FF5000`) (line 8)
- Root: `viewBox="0 0 24 24" fill="none"` (line 12)
- Top-left finder: `<Rect x=2 y=2 width=7 height=7 rx=1 stroke={color} strokeWidth={1.6} />` (line 14)
- Top-left pupil: `<Rect x=4.5 y=4.5 width=2 height=2 fill={color} />` (line 15)
- Top-right finder: `<Rect x=15 y=2 width=7 height=7 rx=1 stroke={color} strokeWidth={1.6} />` (line 17)
- Top-right pupil: `<Rect x=17.5 y=4.5 width=2 height=2 fill={color} />` (line 18)
- Bottom-left finder: `<Rect x=2 y=15 width=7 height=7 rx=1 stroke={color} strokeWidth={1.6} />` (line 20)
- Bottom-left pupil: `<Rect x=4.5 y=17.5 width=2 height=2 fill={color} />` (line 21)
- Data modules `<Path fill={color}>` (lines 23-26) — **fill, no stroke**:
```
M13 13h2v2h-2zM17 13h2v2h-2zM21 13h1v2h-1zM15 17h2v2h-2zM19 17h3v2h-3zM13 21h2v1h-2zM17 21h5v1h-5z
```
- Used: `src/components/SideMenu.tsx:355` (`size={24}`, default accent — the drawer header
  my-address affordance), `src/screens/ContactsScreen.tsx` (`size={20} color={colors.textDim}`),
  `src/screens/ChatScreen.tsx` (`size={20} color={colors.textDim}`)

### 1.5 `SendIcon` — Lucide `send` / Lucide `waypoints`
File: `src/components/SendIcon.tsx` (lines 11-50). Two variants selected by the `mesh` prop.

- Props/defaults: `size = 22`, `color = colors.onAccent` (`#FFFFFF`), `mesh = false` (lines 12-14)
- Shared stroke object (lines 20-25): `stroke: color, strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round'`
- Root (both variants): `viewBox="0 0 24 24" fill="none"` (lines 29, 42)

**`mesh={false}` → Lucide `send` (paper plane)**, 2 paths (lines 43-47):
```
M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z
```
```
m21.854 2.147-10.94 10.939
```

**`mesh={true}` → Lucide `waypoints`** — 4 circles + 3 paths, ALL sharing the same stroke
object (so the circles are stroked, `fill` inherited "none" from the root) (lines 30-36):
- `<Circle cx=12 cy=4.5 r=2.5 />`
- path: `m10.2 6.3-3.9 3.9`
- `<Circle cx=4.5 cy=12 r=2.5 />`
- path: `M7 12h10`
- `<Circle cx=19.5 cy=12 r=2.5 />`
- path: `m13.8 17.7 3.9-3.9`
- `<Circle cx=12 cy=19.5 r=2.5 />`

- Used: `src/screens/ChatScreen.tsx` — `<SendIcon mesh={false} color={colors.onAccent} />` (×2)
  and `<SendIcon mesh color={colors.onAccent} />` (the composer submit; variant honestly
  signals the transport, #171)

### 1.6 `TrashIcon` (standalone) — trash can, drawn as lines + paths
File: `src/components/TrashIcon.tsx` (lines 7-29). Note: a **second, different** `TrashIcon`
exists in `OverflowMenu.tsx` (§3.8) — they are NOT the same drawing. Both are exported and
both are used; keep both in the port.

- Props/defaults: `size = 22`, `color = colors.textDim` (line 7)
- Root: `viewBox="0 0 24 24" fill="none"` (line 9)
- Lid line: `<Line x1="4" y1="6" x2="20" y2="6" stroke={color} strokeWidth={1.8} strokeLinecap="round" />` (line 11)
- Handle `<Path>` (lines 12-17), `strokeWidth={1.8} strokeLinecap="round"`:
```
M9 6V4.5A1.5 1.5 0 0 1 10.5 3h3A1.5 1.5 0 0 1 15 4.5V6
```
- Can `<Path>` (lines 18-24), `strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"`:
```
M6 6l1 13a2 2 0 0 0 2 1.8h6a2 2 0 0 0 2-1.8L18 6
```
- `<Line x1="10" y1="10" x2="10" y2="17" strokeWidth={1.8} strokeLinecap="round" />` (line 25)
- `<Line x1="14" y1="10" x2="14" y2="17" strokeWidth={1.8} strokeLinecap="round" />` (line 26)
- Used: `src/screens/ChatScreen.tsx` (`size={20} color={colors.unread}`),
  `src/screens/ConversationsScreen.tsx` (×2, `size={20} color={colors.unread}`)

### 1.7 `XIcon` — Lucide `x`
File: `src/components/XIcon.tsx` (lines 7-14). **Two lines, no path data.**

- Props/defaults: `size = 22`, `color = colors.textDim` (line 7)
- Root: `viewBox="0 0 24 24" fill="none"` (line 9)
- `<Line x1="6" y1="6" x2="18" y2="18" stroke={color} strokeWidth={1.8} strokeLinecap="round" />` (line 10)
- `<Line x1="18" y1="6" x2="6" y2="18" stroke={color} strokeWidth={1.8} strokeLinecap="round" />` (line 11)
- Equivalent path data (my conversion, NOT in source): `M6 6 18 18 M18 6 6 18`
- Used: `src/components/MediaViewer.tsx` (`size={22} color="#fff"`),
  `src/components/AddressModal.tsx` (`size={22} color={colors.textDim}`),
  `src/components/StorageInfoModal.tsx` (`size={22} color={colors.textDim}`)

### 1.8 `NodeStatusIcon` — not a glyph; a tinted wrapper around `Logo`
File: `src/components/NodeStatusIcon.tsx` (lines 11-43).

- Props: `status: NodeStatus`, `size = 24`, `strokeWidth = 2` (lines 12-18)
- Renders `<Logo size={size} color={nodeStatusColor(status)} strokeWidth={strokeWidth} />`
  inside an `Animated.View` (lines 38-42)
- Pulse: when `status === 'initializing' || status === 'starting'` (line 20) it loops
  opacity `1 → 0.35 → 1.0`, each leg `duration: 550` ms (lines 24-33). Otherwise opacity is
  set to `1` (line 34).
- `nodeStatusColor` (`src/theme/colors.ts:34-44`): `running → #FF5000`,
  `initializing|starting → #9CA3AF`, default (`stopped|error`) → `#EF4444`.
  **Note the file header comment (lines 1-4) says green/amber/red, but the actual code
  returns orange/gray/red.** Trust the code.
- Used: `src/components/Brand.tsx:15` — `<NodeStatusIcon status={status} size={26} />`

---

## 2. Multi-icon modules

### 2.1 `MediaIcons.tsx` — composer action-row glyphs (#206)
File: `src/components/MediaIcons.tsx`. Shared props type `P = {size?: number; color?: string; strokeWidth?: number}` (line 7).
All roots are `viewBox="0 0 24 24" fill="none"`.

#### `CameraIcon` — Lucide `camera` (lines 9-22)
- Defaults `size = 24`, `color = colors.text`, `strokeWidth = 2` (line 9)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 12-18):
```
M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3Z
```
- `<Circle cx=12 cy=13 r=3 stroke={color} strokeWidth={strokeWidth} />` (line 19)
- Used: `src/screens/ChatScreen.tsx` — `<CameraIcon size={22} color={colors.textDim} />`

#### `LocationIcon` — Lucide `map-pin` (lines 24-37)
- Defaults `size = 24`, `color = colors.text`, `strokeWidth = 2` (line 24)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 27-33):
```
M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z
```
- `<Circle cx=12 cy=10 r=3 stroke={color} strokeWidth={strokeWidth} />` (line 34)
- Used: `src/screens/ChatScreen.tsx` — `<LocationIcon size={16} color={colors.accent} />`
  and `<LocationIcon size={22} color={colors.textDim} />`

#### `FilmIcon` — Lucide `film` (lines 40-53), for the Video composer button (#306)
**Primitives only — 1 Rect + 7 Lines, no path data.** All stroke `{color}` / `{strokeWidth}`.
- Defaults `size = 24`, `color = colors.text`, `strokeWidth = 2` (line 40)
- `<Rect x=3 y=3 width=18 height=18 rx=2 />` (line 43)
- `<Line x1=7 y1=3 x2=7 y2=21 />` (line 44)
- `<Line x1=17 y1=3 x2=17 y2=21 />` (line 45)
- `<Line x1=3 y1=12 x2=21 y2=12 />` (line 46)
- `<Line x1=3 y1=7.5 x2=7 y2=7.5 />` (line 47)
- `<Line x1=3 y1=16.5 x2=7 y2=16.5 />` (line 48)
- `<Line x1=17 y1=7.5 x2=21 y2=7.5 />` (line 49)
- `<Line x1=17 y1=16.5 x2=21 y2=16.5 />` (line 50)
- No linecap/linejoin set on any of them.
- Used: `src/screens/ChatScreen.tsx` — `<FilmIcon size={22} color={colors.textDim} />`

#### `PlayIcon` — Lucide `play`, FILLED (lines 56-62)
- Defaults `size = 24`, `color = '#fff'` (line 56) — note: hardcoded white default
- `<Path fill={color} />` — **no stroke at all** (line 59):
```
M7 4v16l13-8L7 4Z
```
- Used: `src/screens/ChatScreen.tsx` — `<PlayIcon size={28} color="#fff" />` (inline video
  play overlay) and `<PlayIcon size={18} color="#fff" />`

#### `MicIcon` — Lucide `mic` (lines 64-85)
- Defaults `size = 24`, `color = colors.text`, `strokeWidth = 2` (line 64)
- `<Rect x=9 y=2 width=6 height=12 rx=3 stroke={color} strokeWidth={strokeWidth} />` (lines 67-75)
- `<Path>` `strokeLinecap="round"` (only, no linejoin) (lines 76-81):
```
M19 10a7 7 0 0 1-14 0
```
- `<Line x1=12 y1=17 x2=12 y2=22 stroke={color} strokeWidth={strokeWidth} strokeLinecap="round" />` (line 82)
- Used: `src/screens/ChatScreen.tsx` — `<MicIcon size={22} color={colors.textDim} />`

### 2.2 `MediaViewerIcons.tsx` — full-screen media viewer actions (#479)
File: `src/components/MediaViewerIcons.tsx`. Shared `P` type at line 6. All roots
`viewBox="0 0 24 24" fill="none"`. All defaults: `size = 24`, `color = '#fff'`, `strokeWidth = 2`.

#### `DownloadIcon` — Lucide `download` (lines 9-37)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 12-18):
```
M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4
```
- `<Polyline points="7 10 12 15 17 10" strokeLinecap="round" strokeLinejoin="round" />` (lines 19-25)
  → equivalent path (my conversion): `M7 10 12 15 17 10`
- `<Line x1="12" y1="15" x2="12" y2="3" strokeLinecap="round" />` (lines 26-34)
- Used: `src/components/MediaViewer.tsx` — `<DownloadIcon size={26} color="#fff" />`

#### `ShareIcon` — Lucide `share` (lines 40-68)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 43-49):
```
M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8
```
- `<Polyline points="16 6 12 2 8 6" strokeLinecap="round" strokeLinejoin="round" />` (lines 50-56)
- `<Line x1="12" y1="2" x2="12" y2="15" strokeLinecap="round" />` (lines 57-65)
- Used: `src/components/MediaViewer.tsx` — `<ShareIcon size={26} color="#fff" />`

#### `ForwardIcon` — Lucide `forward` (lines 71-90)
- `<Polyline points="15 17 20 12 15 7" strokeLinecap="round" strokeLinejoin="round" />` (lines 74-80)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 81-87):
```
M4 18v-2a4 4 0 0 1 4-4h12
```
- Used: `src/components/MediaViewer.tsx` — `<ForwardIcon size={26} color="#fff" />`

---

## 3. Icons defined inline in `OverflowMenu.tsx`

File: `src/components/OverflowMenu.tsx` (445 lines). Header comment lines 6-9 explains why they
live here. `S = 20` (line 23), `SW = 1.8` (line 24). Shared `interface IconProps {size?: number;
color?: string}` (lines 26-29) — **no `strokeWidth` prop; stroke width is baked in.**
All roots `viewBox="0 0 24 24" fill="none"`. All 15 are `export function`s.
All default `size = S` (20) and `color = colors.textDim` unless noted.
**Caveat for a reimplementer: several doc-comments in this file sit above the WRONG function**
(line 114 "lucide `eraser`" sits above `LogOutIcon`; line 183 "lucide `clipboard`" sits above
`PinIcon`). Trust the function name and the geometry, not the adjacent comment.

### 3.1 `EllipsisIcon` — Lucide `ellipsis-vertical` (lines 32-40)
Default `size = 22`, `color = colors.text`. **Three FILLED circles, no stroke.**
- `<Circle cx=12 cy=5 r=1.7 fill={color} />` (line 35)
- `<Circle cx=12 cy=12 r=1.7 fill={color} />` (line 36)
- `<Circle cx=12 cy=19 r=1.7 fill={color} />` (line 37)
- Used: `src/screens/ChatScreen.tsx` — `<EllipsisIcon size={22} color={colors.text} />` (header menu trigger)

### 3.2 `TagIcon` — Lucide `tag` (lines 43-55)
- `<Path>` `strokeWidth={SW} strokeLinejoin="round"` — **no linecap** (lines 46-51):
```
M12.6 2.6A2 2 0 0 0 11.2 2H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2.4 2.4 0 0 0 3.4 0l6.6-6.6a2.4 2.4 0 0 0 0-3.4z
```
- `<Circle cx=7.5 cy=7.5 r=1.1 fill={color} />` (line 52) — filled hole
- Used: `src/screens/GroupInfoScreen.tsx`, `src/components/BubbleActionMenu.tsx`,
  `src/screens/ContactsScreen.tsx`, `src/screens/ChatScreen.tsx` — all `<TagIcon color={colors.textDim} />`

### 3.3 `PencilIcon` — Lucide `pencil` (lines 58-71)
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 61-67):
```
M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z
```
- `<Path>` same stroke props (line 68):
```
m15 5 4 4
```
- Used: `src/components/SideMenu.tsx:217` (`<PencilIcon color={colors.textDim} />` menu row)
  and `src/components/SideMenu.tsx:316` (`<PencilIcon size={11} color={colors.onAccent} />`
  inside the 18×18 avatar edit badge — see §6)

### 3.4 `UserPlusIcon` — Lucide `user-plus` (lines 74-89)
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 77-83):
```
M15 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2
```
- `<Circle cx=8.5 cy=7 r=4 stroke={color} strokeWidth={SW} />` (line 84)
- `<Line x1=19 y1=8 x2=19 y2=14 strokeWidth={SW} strokeLinecap="round" />` (line 85)
- `<Line x1=22 y1=11 x2=16 y2=11 strokeWidth={SW} strokeLinecap="round" />` (line 86)
- Used: `src/screens/ChatScreen.tsx` — `<UserPlusIcon color={colors.textDim} />`

### 3.5 `UsersIcon` — Lucide `users` (lines 92-112)
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 95-101):
```
M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2
```
- `<Circle cx=9 cy=7 r=4 stroke={color} strokeWidth={SW} />` (line 102)
- `<Path>` same stroke props (lines 103-109) — **two subpaths in one `d`**:
```
M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75
```
- Used: `src/screens/ConversationsScreen.tsx`, `src/screens/ChatScreen.tsx` — `<UsersIcon color={colors.textDim} />`

### 3.6 `LogOutIcon` — Lucide `log-out` (lines 116-123)
Default `size = 20` (not `S`), hardcoded `strokeWidth={1.8}`.
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (line 119):
```
M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4
```
- `<Path>` same (line 120):
```
m16 17 5-5-5-5M21 12H9
```
- Used: `src/screens/ChatScreen.tsx` — `<LogOutIcon color={colors.unread} />`

### 3.7 `EraserIcon` — Lucide `eraser` (lines 125-143)
- `<Path>` `strokeWidth={SW} strokeLinecap="round"` (lines 128-133):
```
M7 21h13
```
- `<Path>` `strokeWidth={SW} strokeLinejoin="round"` (no linecap) (lines 134-139):
```
M20.2 12.7 12 21H7.5l-4.2-4.2a2 2 0 0 1 0-2.8l8.5-8.5a2 2 0 0 1 2.8 0l5.6 5.6a2 2 0 0 1 0 2.6z
```
- `<Line x1=8 y1=8.5 x2=15.5 y2=16 strokeWidth={SW} strokeLinecap="round" />` (line 140)
- Used: `src/screens/ChatScreen.tsx` — `<EraserIcon color={colors.unread} />`

### 3.8 `TrashIcon` (OverflowMenu variant) — Lucide `trash-2` (lines 146-160)
**Different geometry from `src/components/TrashIcon.tsx` (§1.6).**
- `<Path d="M3 6h18" strokeWidth={SW} strokeLinecap="round" />` (line 149)
- `<Path>` `strokeWidth={SW} strokeLinejoin="round"` (lines 150-155):
```
M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2
```
- `<Line x1=10 y1=11 x2=10 y2=17 strokeWidth={SW} strokeLinecap="round" />` (line 156)
- `<Line x1=14 y1=11 x2=14 y2=17 strokeWidth={SW} strokeLinecap="round" />` (line 157)
- Used: `src/screens/GroupInfoScreen.tsx`, `src/components/BubbleActionMenu.tsx`,
  `src/components/SideMenu.tsx:225` — all `<TrashIcon color={colors.unread} />`

### 3.9 `CopyIcon` — Lucide `copy` (lines 163-181)
Note the path box exceeds the 24 viewBox on both ends (`y=22.5`, `y=1.5`) — transcribe as-is.
- `<Path>` `strokeWidth={SW} strokeLinejoin="round"` (lines 166-171):
```
M9 9h10a1.5 1.5 0 0 1 1.5 1.5V21A1.5 1.5 0 0 1 19 22.5H9A1.5 1.5 0 0 1 7.5 21V10.5A1.5 1.5 0 0 1 9 9z
```
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 172-178):
```
M4.5 15H4a1.5 1.5 0 0 1-1.5-1.5V3A1.5 1.5 0 0 1 4 1.5h10.5A1.5 1.5 0 0 1 16 3v.5
```
- Used: `src/screens/GroupInfoScreen.tsx`, `src/screens/ContactsScreen.tsx`,
  `src/components/BubbleActionMenu.tsx` (×3) — `<CopyIcon color={colors.textDim} />`

### 3.10 `PinIcon` — Lucide `pin` (lines 186-205)
Comment at 184-185: "#282: Lucide `pin` (lucide.dev) — monochrome, tintable. Replaces the 📌 emoji".
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 189-195):
```
M12 17v5
```
- `<Path>` same stroke props (lines 196-202):
```
M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z
```
- Used: `src/screens/ChatScreen.tsx` (`<PinIcon size={16} color={colors.accent} />`),
  `src/components/BubbleActionMenu.tsx` (`<PinIcon color={colors.textDim} />`)

### 3.11 `ReplyIcon` — Lucide `reply` / `corner-up-left` (lines 208-215)
- `<Path d="M9 17 4 12 9 7" strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round" />` (line 211)
- `<Path d="M20 18v-2a4 4 0 0 0-4-4H4" strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round" />` (line 212)
- Used: `src/components/BubbleActionMenu.tsx` — `<ReplyIcon color={colors.textDim} />`

### 3.12 `ClipboardIcon` — Lucide `clipboard` (lines 217-235)
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 220-226):
```
M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2
```
- `<Path>` `strokeWidth={SW} strokeLinejoin="round"` (no linecap) (lines 227-232):
```
M9 2h6a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z
```
- Used: `src/components/BubbleActionMenu.tsx` — `<ClipboardIcon color={colors.textDim} />`

### 3.13 `MessageCircleIcon` — Lucide `message-circle` (lines 238-250)
Single path; note the `d` starts at `M21 11.5` and ends `A8.4 8.4 0 0 1 21 11z` (the trace is
slightly non-closing in the source — copy verbatim).
- `<Path>` `strokeWidth={SW} strokeLinecap="round" strokeLinejoin="round"` (lines 241-247):
```
M21 11.5a8.4 8.4 0 0 1-9 8.4 8.9 8.9 0 0 1-3.8-.9L3 20.5l1.6-4.9A8.4 8.4 0 0 1 3.7 11 8.4 8.4 0 0 1 12 2.6h.5A8.4 8.4 0 0 1 21 11z
```
- Used: `src/screens/ContactsScreen.tsx`, `src/screens/ConversationsScreen.tsx` (×2),
  `src/screens/GroupInfoScreen.tsx`, `src/components/BubbleActionMenu.tsx` (×3) —
  `<MessageCircleIcon color={colors.textDim} />`

### 3.14 `BackIcon` — Lucide `chevron-left` (lines 253-265)
Default `size = 26`, `color = colors.text`, hardcoded `strokeWidth={2}`.
- `<Path>` `strokeLinecap="round" strokeLinejoin="round"` (lines 256-262):
```
m15 18-6-6 6-6
```
- Used: `src/screens/ChatScreen.tsx` — `<BackIcon color={colors.text} />`

### 3.15 `MeshIcon` (OverflowMenu) — Lucide `waypoints` (lines 268-281)
**Identical geometry to `SendIcon`'s mesh variant** (§1.5), but with `strokeWidth = SW (1.8)`.
Shared props object `p` at line 269: `{stroke: color, strokeWidth: SW, strokeLinecap: 'round', strokeLinejoin: 'round'}`.
- `<Circle cx=12 cy=4.5 r=2.5 {...p} />` (line 272)
- `<Path d="m10.2 6.3-3.9 3.9" {...p} />` (line 273)
- `<Circle cx=4.5 cy=12 r=2.5 {...p} />` (line 274)
- `<Path d="M7 12h10" {...p} />` (line 275)
- `<Circle cx=19.5 cy=12 r=2.5 {...p} />` (line 276)
- `<Path d="m13.8 17.7 3.9-3.9" {...p} />` (line 277)
- `<Circle cx=12 cy=19.5 r=2.5 {...p} />` (line 278)
- Used: `src/screens/ConversationsScreen.tsx` (`size={14} color={MESH_GREEN}`),
  `src/screens/GroupInfoScreen.tsx` (`size={16} color={MESH_GREEN}`, `color={colors.textDim}`,
  `size={14} color={mappedCount > 0 ? MESH_GREEN : colors.textFaint}`),
  `src/screens/ContactsScreen.tsx` (`color={colors.textDim}`, `size={16} color={MESH_GREEN}`),
  `src/components/BubbleActionMenu.tsx` (`color={colors.textDim}`),
  `src/screens/ChatScreen.tsx` (`size={12} color={MESH_GREEN}` ×2, `color={MESH_GREEN}` ×2)
- **Name collision:** `SideMenu.tsx` also defines a *different, local* `MeshIcon` (§4.7 — an
  antenna, not waypoints). They are separate glyphs sharing a name.

---

## 4. Icons defined inline in `SideMenu.tsx` (drawer nav glyphs)

File: `src/components/SideMenu.tsx`. All are wrapped in the local `Icon` component
(line 42-48): `<Svg width={22} height={22} viewBox="0 0 24 24" fill="none">`.
`stroke(color, extra)` (lines 49-54) yields `{stroke: color, strokeWidth: 1.8, strokeLinecap: 'round', ...extra}`.
All default `color = colors.text` (`#FAFAFA`); the drawer passes a per-row tint `c`.
**These are NOT exported** — they are module-local consts.

### 4.1 `AllIcon` — three horizontal bars (menu / list) (lines 55-61)
- `<Line x1="4" y1="7" x2="20" y2="7" />`
- `<Line x1="4" y1="12" x2="20" y2="12" />`
- `<Line x1="4" y1="17" x2="20" y2="17" />`
- Used: `src/components/SideMenu.tsx:368` — filter row "All"

### 4.2 `ChatsIcon` — chat bubble with a tail (lines 62-66)
- `<Path>` with `stroke(color, {strokeLinejoin: 'round'})` (line 64):
```
M4 5h16v11H9l-4 3.5V16H4z
```
- Used: `src/components/SideMenu.tsx:382` — filter row "Chats"

### 4.3 `GroupsIcon` — two-person group (lines 67-74)
- `<Circle cx="9" cy="9" r="3" />` (line 69)
- `<Path d="M3.5 19c0-3 2.5-5 5.5-5s5.5 2 5.5 5" />` (line 70)
- `<Path d="M16 6.2a3 3 0 0 1 0 5.6" />` (line 71)
- `<Path d="M17 14.2c2.4.5 3.5 2.2 3.5 4.8" />` (line 72)
- Used: `src/components/SideMenu.tsx:389` — filter row "Groups"

### 4.4 `ContactsIcon` — single person (lines 75-80)
- `<Circle cx="12" cy="8" r="3.5" />` (line 77)
- `<Path d="M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6" />` (line 78)
- Used: `src/components/SideMenu.tsx:396` — page row "Contacts"

### 4.5 `AboutIcon` — info circle (lines 81-87)
- `<Circle cx="12" cy="12" r="9" />` (line 83)
- `<Line x1="12" y1="11" x2="12" y2="16.5" />` (line 84)
- `<Rect x="11.1" y="7.3" width="1.8" height="1.8" rx="0.9" fill={color} />` (line 85) — the
  dot is a rounded FILLED square, not a circle
- Used: `src/components/SideMenu.tsx:462` — page row "About"

### 4.6 `SettingsIcon` — sliders (#232) (lines 89-96)
- `<Line x1="4" y1="8" x2="20" y2="8" />` (line 91)
- `<Circle cx="15" cy="8" r="2.2" />` (line 92) — stroked (uses `stroke()` spread)
- `<Line x1="4" y1="16" x2="20" y2="16" />` (line 93)
- `<Circle cx="9" cy="16" r="2.2" />` (line 94)
- Used: `src/components/SideMenu.tsx:456` — page row "Settings"

### 4.7 `MeshIcon` (SideMenu local) — radio/antenna (#166) (lines 98-105)
- `<Line x1="12" y1="12" x2="12" y2="21" />` (line 100) — the mast
- `<Circle cx="12" cy="10" r="1.6" fill={color} />` (line 101) — FILLED node
- `<Path d="M8.5 13.5a5 5 0 0 1 0-7M15.5 6.5a5 5 0 0 1 0 7" />` (line 102) — inner arcs
- `<Path d="M6 15.5a8 8 0 0 1 0-11M18 4.5a8 8 0 0 1 0 11" />` (line 103) — outer arcs
- Used: `src/components/SideMenu.tsx:423` — MeshCore section row

### 4.8 `ChannelsIcon` — hashtag (#167) (lines 107-114)
- `<Line x1="9" y1="4" x2="7" y2="20" />` (line 109)
- `<Line x1="17" y1="4" x2="15" y2="20" />` (line 110)
- `<Line x1="4" y1="9" x2="20" y2="9" />` (line 111)
- `<Line x1="4" y1="15" x2="20" y2="15" />` (line 112)
- Used: `src/components/SideMenu.tsx:409` — "Channels" row

### 4.9 `MeshDmIcon` — antenna inside a chat bubble (#167) (lines 116-122)
- `<Path d="M4 5h16v11H9l-4 3.5V16H4z" />` with `strokeLinejoin: 'round'` (line 118)
- `<Circle cx="12" cy="9" r="1.2" fill={color} />` (line 119)
- `<Path d="M9.5 11a3.5 3.5 0 0 1 0-4M14.5 7a3.5 3.5 0 0 1 0 4" />` (line 120)
- Used: `src/components/SideMenu.tsx:416` — mesh-DMs row

### 4.10 `BleDmIcon` — bluetooth rune inside a chat bubble (#245) (lines 124-132)
- `<Path d="M4 5h16v11H9l-4 3.5V16H4z" />` with `strokeLinejoin: 'round'` (line 126)
- `<Path>` with `stroke(color, {strokeLinejoin: 'round'})` (lines 127-130):
```
M10 7.5l4 3-2 1.5V6l2 1.5-4 3
```
- Used: `src/components/SideMenu.tsx:444` — BLE-DMs row

### 4.11 (SideMenu also renders) `BleLogo`
`src/components/SideMenu.tsx:438` — `icon={c => <BleLogo color={c} size={22} />}` for the
BLE section row. See §5.2.

---

## 5. Brand / transport marks

### 5.1 `Logo` — the OFFICIAL Logos glyph (fill-based, 32×32)
File: `src/components/Logo.tsx` (lines 8-29). Comment lines 1-3 & 18-19: "the single-glyph
symbol from logos.co, not the wordmark … source logos.co/favicon.svg. Authored for a 32×32
box with its own translate(6 3); keep both so it stays centered."

- Props: `size = 24`, `color = colors.accent`, `strokeWidth` **accepted but IGNORED** (line 12
  destructures it to `_strokeWidth`; comment line 11: "the Logos mark is fill-based (ignored)")
- Root: `<Svg width={size} height={size} viewBox="0 0 32 32" fill="none">` (line 21) —
  **the only 32×32 viewBox in the icon set**
- Single `<Path transform="translate(6 3)" fill={color}>` (lines 22-25). **Fill only, no stroke.**
  Verbatim `d` (line 25):

```
M14.6386 26C13.728 26 12.945 25.7854 12.2881 25.3549C11.6312 24.9244 11.1344 24.2467 10.7962 23.3233C10.5841 22.7003 10.4359 21.9368 10.3513 21.0328C10.2668 20.1302 10.2134 19.1833 10.1926 18.1948C10.1718 17.1842 10.1497 16.2061 10.1289 15.2592C10.1289 15.0017 10.0651 14.8716 9.93897 14.8716C9.83361 14.8716 9.72695 14.9575 9.62159 15.1292C9.21967 15.8822 8.74359 16.742 8.19208 17.7097C7.66268 18.6773 7.13328 19.645 6.60388 20.6127C6.07447 21.5804 5.5984 22.4518 5.17436 23.2257C4.77243 23.9788 4.48627 24.5264 4.31717 24.871C4.10515 25.3445 3.76696 25.6449 3.3013 25.7737C2.85644 25.9246 2.29582 25.9571 1.61814 25.8699C0.940452 25.7841 0.464381 25.5149 0.188624 25.0635C-0.107945 24.5901 -0.0546142 24.0958 0.347315 23.5795C0.623072 23.2348 1.01459 22.7198 1.52188 22.0317C2.03047 21.3216 2.6015 20.5269 3.23626 19.645C3.87102 18.7424 4.51749 17.8176 5.17306 16.8707C5.85075 15.9031 6.48551 14.9783 7.07865 14.0964C7.67178 13.1938 8.16867 12.4082 8.5706 11.7423C8.99464 11.0542 9.26909 10.5483 9.39657 10.2257C9.52404 9.92526 9.66062 9.591 9.8089 9.22551C9.95719 8.86003 10.0313 8.48414 10.0313 8.09655C10.0313 6.67754 9.89345 5.61231 9.61899 4.90345C9.36535 4.17249 9.01545 3.68864 8.5706 3.45193C8.14655 3.1944 7.68089 3.06433 7.1736 3.06433C6.79248 3.06433 6.38015 3.13977 5.9353 3.29065C5.51125 3.44152 5.2368 3.58069 5.10933 3.70945C4.87649 3.94617 4.65407 3.98909 4.44205 3.83822C4.23002 3.68734 4.16629 3.44022 4.25214 3.09685C4.48497 2.30085 4.90901 1.592 5.52296 0.967684C6.13951 0.322561 6.9967 0 8.09713 0C9.26129 0 10.1822 0.332967 10.8599 1.0002C11.5376 1.66743 12.0241 2.73137 12.3206 4.1933C12.6172 5.65523 12.7655 7.5906 12.7655 9.9994C12.7655 12.8374 12.8084 15.1071 12.893 16.8057C12.9775 18.5044 13.1154 19.7842 13.3053 20.6439C13.4952 21.4828 13.7606 22.0421 14.0987 22.3218C14.459 22.6014 14.9026 22.7406 15.432 22.7406C15.9614 22.7406 16.4167 22.6326 16.8615 22.418C17.3272 22.2034 17.7291 21.9238 18.0686 21.5791C18.2169 21.4074 18.386 21.3424 18.5772 21.3853C18.7671 21.4282 18.9154 21.5466 19.022 21.7404C19.1495 21.9121 19.1495 22.1384 19.022 22.418C18.5772 23.4078 17.9841 24.2571 17.2439 24.966C16.5246 25.654 15.6557 25.9987 14.6399 25.9987L14.6386 26Z
```

- Used (every call site passes `strokeWidth`, which the component discards):
  `src/screens/LockScreen.tsx:104` (`size={48} color={colors.accent} strokeWidth={2}`),
  `src/screens/AboutScreen.tsx:135` (`size={56} color={colors.accent} strokeWidth={2}`),
  `src/components/TransportPill.tsx:59` (`size={GLYPH}` = 22, `color={color} strokeWidth={2}`),
  `src/components/TransportsModal.tsx:140` (`size={24} color={TRI_COLOR[logosState]} strokeWidth={2}`),
  `src/components/NodeStatusIcon.tsx:40` (which `Brand.tsx` renders at `size={26}`)
- **Stale comments:** `Brand.tsx:1` and `NodeStatusIcon.tsx:1` both call the Logo
  "messages-square". That is no longer true — `Logo.tsx` draws the logos.co glyph.
  The messages-square shape survives only in the Android notification vectors (§7.2).

### 5.2 `BleLogo` — Lucide `bluetooth`
File: `src/components/BleLogo.tsx` (lines 10-31).
- Props: `size = 24`, `color = colors.text`, `strokeWidth = 1.9`
- Root: `viewBox="0 0 24 24" fill="none"` (line 20)
- Single `<Path>` `strokeLinecap="round" strokeLinejoin="round" fill="none"` (lines 21-28):
```
M7 7l10 10-5 5V2l5 5L7 17
```
- Used: `src/screens/NearbyScreen.tsx` (`size={40} color={colors.textFaint}`),
  `src/components/TransportsModal.tsx` (`size={24} color={triColorFor(bleState, 'ble')} strokeWidth={2}`),
  `src/components/TransportPill.tsx` (`size={GLYPH} color={color} strokeWidth={2}`),
  `src/components/SideMenu.tsx:438` (`color={c} size={22}`)

### 5.3 `MeshLogo` — MeshCore antenna (traced from meshcore.co.uk app icon; NOT Lucide)
File: `src/components/MeshLogo.tsx` (lines 11-38). Comment lines 2-4: "MeshCore publishes no
vector glyph (only a raster app icon + a wordmark), so this is a single-color SVG traced from
their app icon".
- Props: `size = 24`, `color = colors.text`, `strokeWidth = 1.9`
- Shared `arc` props (lines 20-25): `{stroke: color, strokeWidth, strokeLinecap: 'round', fill: 'none'}`
  — **no linejoin**
- Root: `viewBox="0 0 24 24" fill="none"` (line 27)
- `<Circle cx=12 cy=12 r=2 fill={color} />` (line 29) — FILLED center node
- Right waves (lines 31-32) — note the spaces inside the arc commands, copy verbatim:
```
M15.21 8.17 A 5 5 0 0 1 15.21 15.83
```
```
M17.16 4.63 A 9 9 0 0 1 17.16 19.37
```
- Left waves, mirrored (lines 34-35):
```
M8.79 15.83 A 5 5 0 0 1 8.79 8.17
```
```
M6.84 19.37 A 9 9 0 0 1 6.84 4.63
```
- Used: `src/components/TransportPill.tsx` (`size={GLYPH} color={color} strokeWidth={2}`),
  `src/components/MeshInfoModal.tsx` (`size={28} color={MESH_GREEN}`),
  `src/components/TransportsModal.tsx` (`size={24} color={triColorFor(...)} strokeWidth={2}`)

### 5.4 `ShieldLogo` — Lucide `shield-check` (private mode / Tor)
File: `src/components/ShieldLogo.tsx` (lines 11-40).
- Props: `size = 24`, `color = colors.text`, `strokeWidth = 1.9`
- Root: `viewBox="0 0 24 24" fill="none"` (line 21)
- `<Path>` `strokeLinecap="round" strokeLinejoin="round" fill="none"` (lines 22-29):
```
M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z
```
- `<Path>` same stroke props (lines 30-37):
```
m9 12 2 2 4-4
```
- Used: `src/components/TransportsModal.tsx` (`size={24} color={triColorFor(torTri, 'logos')} strokeWidth={2}`),
  `src/components/TransportPill.tsx` (`size={GLYPH} color={color} strokeWidth={2}`)

### 5.5 `VerifiedBadge` — PROCEDURAL, no literal path data
File: `src/components/VerifiedBadge.tsx` (lines 10-45). Not Lucide — a scalloped "seal/flower"
generated at runtime (#153).

- Props: `size = 15`, `color = colors.verified ?? '#1D9BF0'` (lines 25-26)
- Root: `viewBox="0 0 24 24" fill="none"` (line 33)
- The seal `d` is built by `sealPath(n, R, r, cx, cy)` (lines 10-22), invoked as
  `sealPath(9, 11.2, 8.6, 12, 12)` (line 31) — **9 bumps, bump radius 11.2, valley radius 8.6,
  centered at (12,12)**. Verbatim algorithm:
```ts
const pt = (radius: number, ang: number) =>
  `${(cx + radius * Math.cos(ang)).toFixed(2)} ${(cy + radius * Math.sin(ang)).toFixed(2)}`;
const step = (Math.PI * 2) / n;
let d = `M${pt(r, -Math.PI / 2)}`;
for (let i = 0; i < n; i++) {
  const a0 = -Math.PI / 2 + i * step;
  const bump = a0 + step / 2;
  const next = a0 + step;
  d += ` Q${pt(R, bump)} ${pt(r, next)}`;
}
return d + ' Z';
```
  i.e. start at the valley point at angle −90°, then `n` quadratic segments
  `Q <bump point at a0+step/2, radius R> <valley point at a0+step, radius r>`, then `Z`.
  Coordinates are formatted to 2 decimals.
- `<Path d={d} fill={color} />` (line 34) — filled, no stroke
- `<Polyline points="8.4,12.3 11,14.8 15.7,9.2" fill="none" stroke="#FFFFFF" strokeWidth={2}
  strokeLinecap="round" strokeLinejoin="round" />` (lines 35-42) — the check is **hardcoded
  white `#FFFFFF`**, not tinted
- Used at `size={14}`: `src/screens/NearbyScreen.tsx:219`, `src/screens/ContactsScreen.tsx` (×3),
  `src/screens/ConversationsScreen.tsx` (×2), `src/screens/GroupInfoScreen.tsx` (×2),
  `src/screens/AddMembersScreen.tsx` (×2), `src/screens/ChatScreen.tsx` (×2, lines 1213/1239);
  at `size={12}`: `src/screens/ChatScreen.tsx:439`; at `size={16}`:
  `src/components/AddressModal.tsx:123` (imported at line 14).
  **No call site uses the `size = 15` default.**

---

## 6. Icons defined inline in `SpeedDialFab.tsx`

File: `src/components/SpeedDialFab.tsx`. All roots `viewBox="0 0 24 24" fill="none"`,
all `strokeWidth={1.8}`, all default `size = 20`. **All exported.**

### 6.1 `ContactGlyph` — single-person (lines 18-36)
Default `color = colors.contact` (`#FF5000`).
- `<Circle cx={12} cy={8} r={3.5} stroke={color} strokeWidth={1.8} />` (line 27)
- `<Path>` `strokeLinecap="round"` (lines 28-33):
```
M5 20c0-3.6 3.1-6 7-6s7 2.4 7 6
```
- Used: `src/screens/ConversationsScreen.tsx` — `<ContactGlyph size={20} color={green} />`
  (green = `FAB_COLOR.mesh` = `#22C55E`) and `<ContactGlyph size={20} color={colors.contact} />`

### 6.2 `GroupGlyph` — two-person (lines 39-69)
Default `color = colors.accent`.
- `<Circle cx={9} cy={8} r={3} stroke={color} strokeWidth={1.8} />` (line 48)
- `<Path d="M2.5 19.5c0-3.1 2.9-5.2 6.5-5.2s6.5 2.1 6.5 5.2" strokeLinecap="round" />` (lines 49-54)
- `<Path d="M16.5 5.6a3 3 0 0 1 0 5.6" strokeLinecap="round" />` (lines 55-60)
- `<Path d="M17.5 14.4c2.7.5 4 2.4 4 5.1" strokeLinecap="round" />` (lines 61-66)
- Used: `src/screens/ConversationsScreen.tsx` — `size={14} color={colors.textFaint}` (row badge),
  `size={20} color={green}`, `size={20} color={colors.accent}`

### 6.3 `ChannelGlyph` — hashtag (#253) (lines 72-89)
Default `color = colors.accent`. Single path, four subpaths — note `M3 15h16` (x=3, asymmetric
with `M4 9h16`); transcribe as-is.
- `<Path>` `strokeWidth={1.8} strokeLinecap="round"` (lines 81-86):
```
M9 4L7 20M17 4l-2 16M4 9h16M3 15h16
```
- Used: `src/screens/ConversationsScreen.tsx` — `<ChannelGlyph size={20} color={green} />` (×2)

### 6.4 `BluetoothGlyph` — bluetooth rune (#253) (lines 92-110)
Default `color = colors.accent`. **Different coordinates from `BleLogo` (§5.2)** — this one is
inset; keep both.
- `<Path>` `strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round"` (lines 101-107):
```
M7 7.5L17 16l-5 4V4l5 4L7 16.5
```
- Used: `src/screens/ConversationsScreen.tsx` — `<BluetoothGlyph size={20} color={blue} />`
  (blue = `FAB_COLOR.ble` = `#0EA5E9`)

### 6.5 The FAB "+" itself is TEXT, not an icon
`src/components/SpeedDialFab.tsx:279-283` — an `Animated.Text` containing the literal `+`,
rotated `0deg → 45deg` (`anim.interpolate`, lines 233-236) to become an "×". Styles
(`fabPlus`, lines 309-315): `color: colors.onAccent`, `fontSize: 32`, `lineHeight: 34`,
`includeFontPadding: false`, `textAlign: 'center'`. FAB container (`fab`, lines 298-308):
`position: 'absolute'`, `right: spacing.lg`, `width: 56, height: 56, borderRadius: 28`,
`backgroundColor: colors.accent` (overridden inline at line 274 by the section `color` prop),
`alignItems/justifyContent: 'center'`, `elevation: 6`. Mini-action button (`miniBtn`,
lines 336-346): `44×44`, `borderRadius: 22`, `backgroundColor: colors.panel`,
`borderColor: colors.border`, `borderWidth: 1`, `elevation: 4`. Backdrop (lines 290-297):
`rgba(0,0,0,0.6)`. Disabled ("coming soon") mini-action: `opacity: 0.45` (line 326).
Open/close animation: `Animated.timing`, `duration: 180`, `easing: Easing.out(Easing.cubic)`,
`useNativeDriver: true` (lines 201-206).

---

## 7. The app / sidebar mark

There are **four distinct "Peers marks"** in this codebase. They are not the same drawing.

### 7.1 In-app brand mark (header) — `Brand.tsx`
`src/components/Brand.tsx:13-18`: a row of `<NodeStatusIcon status={status} size={26} />`
followed by the literal lowercase wordmark `peers` styled `{...type.brand, color: colors.text}`.
Row style: `flexDirection: 'row', alignItems: 'center', gap: spacing.sm` (line 22).
The mark itself is therefore the **logos.co glyph (§5.1)** tinted by node status
(orange `#FF5000` running / gray `#9CA3AF` pulsing while connecting / red `#EF4444` offline).

### 7.2 Android launcher icon — a PIXEL IDENTICON, not a logo
`android/app/src/main/res/values/colors.xml:4-7`, verbatim:
> `<!-- The launcher icon is a pixel identicon (HexAvatar engine, seeded from an identity address) on the identicon ground (#0A0A0A) so the logo reads as a real identicon. Per-identity dynamic version → #247. -->`
> `<color name="ic_launcher_background">#0A0A0A</color>`

- Adaptive icon (`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` and
  `ic_launcher_round.xml`, identical): `<background android:drawable="@color/ic_launcher_background" />`,
  `<foreground android:drawable="@mipmap/ic_launcher_foreground" />`.
- The foreground is a **raster PNG** per density
  (`mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png`); each of those five
  density folders ALSO holds legacy pre-API-26 rasters `ic_launcher.png` and
  `ic_launcher_round.png`. **There is no vector source and no generator script in the repo** —
  `scripts/` holds only `build-bridge.sh`, `desktop-peer`, `verify-native-provenance.sh`, and
  `grep -ril ic_launcher docs/` returns nothing.
  To reproduce it in QML you must re-run the identicon engine (§7.3), not port a path.

### 7.3 The identicon engine (`HexAvatar`) — the sidebar avatar & launcher-icon source
File: `src/components/HexAvatar.tsx`. This is the algorithm the launcher icon and every
avatar come from.

- Component props (lines 95-111): `seed: string` (required), `kind: AvatarKind` (required),
  `size = 40`, `disableImage = false` (#344 — skip the custom-avatar image branch so a
  storage-off group never triggers a Storage fetch), `locked = false` (#344 — overlay the
  lock badge of §1.3).
- `identiconCells(seed, kind)` and `AVATAR_N` are **exported and reused** by
  `src/components/QrCard.tsx:15` so the QR's centre badge draws the identical identicon (#118).
- Grid: `AVATAR_N = 5` (line 61) — a 5×5 **left-right-symmetric** grid of **flush squares**
  (no gaps, no cell rounding; header comment line 3).
- Ramps (lines 26-30), dark → near-white:
  - `LOGOS_RAMP = ['#B8420E', '#FF5000', '#FF7A33', '#FFB27A', '#FFE4D0']`
  - `MESH_RAMP  = ['#166534', '#22C55E', '#4ADE80', '#86EFAC', '#DCFCE7']`
  - `BLE_RAMP   = ['#0B5C8A', '#0EA5E9', '#38BDF8', '#7DD3FC', '#E0F5FF']`
- Kind → ramp (lines 35-40): `contact`→LOGOS, `group`→LOGOS, `mesh`→MESH, `ble`→BLE.
- Seed prefixes (line 41): `PREFIX = {contact: 'c:', group: 'g:', mesh: 'm:', ble: 'b:'}`.
- PRNG (lines 44-59) — **xmur3 hash → mulberry32**, verbatim:
```ts
function rng(seed: string): () => number {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  let a = Math.imul(h ^ (h >>> 13), 3266489909);
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
- Cell generation `identiconCells(seed, kind)` (lines 72-93), verbatim:
```ts
const ramp = RAMPS[kind];
const r = rng(PREFIX[kind] + seed);
const cells: IdenticonCell[] = [];
for (let x = 0; x < 3; x++) {
  for (let y = 0; y < AVATAR_N; y++) {
    if (r() > 0.5) { continue; }            // empty cell → shows the ground
    const fill = ramp[Math.floor(r() * ramp.length)];
    const xs = x === 2 ? [2] : [x, AVATAR_N - 1 - x];
    for (const xx of xs) { cells.push({x: xx, y, fill}); }
  }
}
```
  **Iteration order is x-outer (0,1,2), y-inner (0..4); the RNG is consumed once for the
  skip test and, only when not skipped, once more for the ramp index.** Column 2 is the
  mirror axis; columns 0,1 mirror to 4,3.
- Render (lines 173-198): `cell = size / AVATAR_N`; each `<Rect x={c.x*cell} y={c.y*cell}
  width={cell + 0.5} height={cell + 0.5} fill={c.fill} />` — **+0.5 overlap so anti-aliasing
  leaves no seam**. Wrapper `View`: `borderRadius: size * 0.22`, `overflow: 'hidden'`,
  `backgroundColor: colors.canvas` (`#0A0A0A`). The inner `<Svg width={size} height={size}>`
  has **no viewBox** (line 195).
- Custom-avatar override (#314, lines 164-171): when a stored `MediaRef` resolves, an
  `<Image>` is rendered instead with `borderRadius: size * 0.22`.
- Seed rules (lines 205-215): group → `libConvoId ?? 'pk'+convoPk`; 1:1 → `peerAddress ?? 'pk'+convoPk`.
- Kind rules (lines 220-231): `transport==='mesh'` → `'mesh'`; `'ble'` → `'ble'`; else
  `isGroup ? 'group' : 'contact'`.

### 7.4 Android notification small icons — Lucide `messages-square`
`android/app/src/main/res/drawable/ic_stat_chat.xml` and `.../ic_stat_lambda.xml` are
**byte-identical in path data**. Both: `android:width="24dp" android:height="24dp"
android:viewportWidth="24" android:viewportHeight="24" android:tint="#FFFFFFFF"`, two
`<path android:fillColor="#FFFFFFFF">` (fill, no stroke):
```
M14 9a2 2 0 0 1-2 2H6l-4 4V4c0-1.1.9-2 2-2h8a2 2 0 0 1 2 2Z
```
```
M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1
```
Comment (`ic_stat_chat.xml` lines 1-2): "must be a white-on-transparent silhouette (Android
tints it; any color here is ignored on API 21+). Lucide messages-square."

### 7.5 Sidebar (drawer) header composition
`src/components/SideMenu.tsx:303-357` (the `styles.header` `<View>`):
- `<HexAvatar seed={myAddress ?? 'me'} kind="contact" size={48} />` (line 314)
- overlaid edit badge `styles.pencilBadge` (lines 516-528): `position: 'absolute',
  bottom: -2, right: -2, width: 18, height: 18, borderRadius: 9,
  backgroundColor: colors.accent, borderWidth: 1.5, borderColor: colors.canvas,
  alignItems: 'center', justifyContent: 'center'` containing
  `<PencilIcon size={11} color={colors.onAccent} />` (line 316)
- right side: `<QrIcon size={24} />` (line 355, default accent tint)
- `styles.itemIcon: {width: 22, alignItems: 'center'}` (line 563) — every drawer row's icon
  column is 22 px wide.

---

## 8. Non-icon SVG (listed so the port doesn't mistake them for glyphs)

- `src/components/QrCard.tsx` — the QR code itself: `<Svg ref={svgRef} width={size} height={svgH}
  viewBox={\`0 0 ${total} ${vbH}\`}>` (line 82), `<Rect ... fill={colors.qrBg} />` (line 83),
  `<Path d={path} fill={colors.qrFg} />` (line 84), and an `<SvgText>` caption band
  (lines 86-95). `path` is generated QR module data, not a glyph.
  The centre badge (lines 97-150) has **two branches**: a custom-avatar photo, which is the
  only one that uses `<Defs><ClipPath id="qrBadge">` (lines 112-133); otherwise a dark
  `colors.canvas` tile plus `identiconCells(...)` rects drawn from `HexAvatar` (§7.3).
  Badge geometry in QR-module units (lines 64-71): `backing = total * 0.26`,
  `stroke = backing * 0.08`, `tile = backing - stroke`, `inner = tile * 0.78`,
  `cell = inner / AVATAR_N`, tile corner radius `tile * 0.22`. Error correction is raised to
  `'H'` when a badge is present, `'M'` otherwise (line 45).
- `src/components/MediaSendBubble.tsx:15-43` — a circular progress ring (`SIZE = 160`,
  `RING = 46`, `STROKE = 4`, lines 11-13): a track `<Circle stroke="rgba(255,255,255,0.35)" />`
  and a progress `<Circle stroke="#fff" strokeLinecap="round"
  strokeDasharray={\`${c} ${c}\`} strokeDashoffset={c * (1 - p)}
  transform={\`rotate(-90 ${RING/2} ${RING/2})\`} />` where `r = RING/2 - STROKE/2`
  and `c = 2 * Math.PI * r`.
- `src/screens/MyAddressScreen.tsx` and `src/components/AddressModal.tsx` import
  `react-native-svg` **as a type only** (`import type Svg from 'react-native-svg'`, lines 6 and 8)
  to hold a ref for `toDataURL` PNG capture — they define no glyphs.

---

## 9. Things that do NOT exist in the source (do not invent them)

- No `src/components/index.ts` icon barrel.
- No icon-font, no `lucide-react-native` dependency — every glyph is hand-transcribed inline.
- No vector source for the Android launcher foreground (PNG only, no SVG, no generator script).
- No `strokeWidth` effect on `Logo` (the prop is accepted and discarded).
- No `strokeLinejoin` on `MeshLogo` arcs, `MicIcon`'s arc, `EraserIcon`'s first path,
  `TrashIcon`(standalone) handle path, or `ChannelGlyph` — only `strokeLinecap="round"`.
- No dark/light theming for icons — the palette is a single dark theme (`src/theme/colors.ts`).
