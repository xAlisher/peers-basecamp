#!/usr/bin/env bash
# One-shot: create the epic + issue backlog for peers-basecamp.
# Idempotent-ish: skips creating an issue whose exact title already exists.
set -uo pipefail
REPO=xAlisher/peers-basecamp

existing=$(gh issue list -R "$REPO" --state all --limit 500 --json title --jq '.[].title')

have() { grep -Fxq "$1" <<<"$existing"; }

mklabel() {
  gh label create "$1" -R "$REPO" --color "$2" --description "$3" >/dev/null 2>&1 || true
}

mkissue() { # title, body, labels...
  local title="$1"; shift
  local body="$1"; shift
  if have "$title"; then echo "skip: $title"; return; fi
  local args=()
  for l in "$@"; do args+=(--label "$l"); done
  gh issue create -R "$REPO" --title "$title" --body "$body" "${args[@]}" >/dev/null \
    && echo "made: $title" || echo "FAIL: $title"
}

# ---------------------------------------------------------------- labels
mklabel epic                5319E7 "Epic — a group of issues"
mklabel E1-core-messaging   1D76DB "Core messaging"
mklabel E2-groups           0E8A16 "Groups"
mklabel E3-contacts         FBCA04 "Contacts & identity"
mklabel E4-media            D93F0B "Media & reactions"
mklabel E5-settings         B60205 "Settings & security"
mklabel E6-portability      006B75 "Identity portability"
mklabel E7-shell            C5DEF5 "Shell & layout"
mklabel infra               BFD4F2 "Build, test and tooling"
mklabel upstream-blocked    E99695 "Blocked on an upstream capability"
mklabel parity              FEF2C0 "Android parity tracking"

AC='

**Acceptance criteria**
'
GROUND='

Ground truth: see `docs/` (DESIGN-SPEC, CONTENT-MARKERS, HEXAVATAR, BACKUP-FORMAT) — all extracted
from the Peers Android source with `path:line` citations. Parity is judged against Peers, not the
Logos design system (ADR 0005).'

# ---------------------------------------------------------------- epics
mkissue "E1 — Core messaging" \
"Conversations list, 1:1 chat thread, composer, send/receive over \`chat_module\`, and send state.

Peers has **no delivered/read receipts** (\`ChatScreen.tsx:3\`) — statuses are only \`pending\` /
\`failed\` / sent. Do not invent ticks the app does not have.$GROUND" epic E1-core-messaging

mkissue "E2 — Groups" \
"Create group, add members, group info/roster, leave/wipe, pinned messages, group avatar.

\`chat_module\` 0.2.2 provides \`create_group_conversation(name, desc)\`, \`add_group_member\`,
\`list_group_members\` (committed first, then pending invites) and a \`members_changed\` event.
Leave/remove has **no core primitive** — scope it against what the contract actually allows.$GROUND" epic E2-groups

mkissue "E3 — Contacts & identity" \
"Contacts list + search, add by address paste, my address + QR, QR scan, shared contact card
(\`addr1:\`), display name + custom avatar (\`pfp1:\`), labels and the verified badge.$GROUND" epic E3-contacts

mkissue "E4 — Media & reactions" \
"The content-marker codec, then photo / GIF / video / voice note send+view, the media viewer, and
reactions.

All of this rides marker-prefixed payloads inside the message body — the core contract carries text
only (ADR 0002).$GROUND" epic E4-media

mkissue "E5 — Settings & security" \
"Settings panel (notification toggles, show-content, delivery node), PIN app-lock, duress/wipe PIN,
the lock-screen overlay, and reset identity + data.

The lock screen is an **overlay above the mounted navigator, not a route** (\`App.tsx:167-168\`).$GROUND" epic E5-settings

mkissue "E6 — Identity portability" \
"Read a Peers-mobile \`.peersenc\` backup, desktop export/restore, and the About screen.

**Partly upstream-blocked**: \`chat_module\` 0.2.2 exposes no identity-import method, so adopting the
backup's address on desktop is not currently possible (ADR 0004). Decryption, schema parsing and
history import all still ship and are tested.$GROUND" epic E6-portability

mkissue "E7 — Shell & layout" \
"The three-panel shell, nav rail, \`Theme.qml\` token singleton, \`HexAvatar\`, the Lucide icon set,
empty/loading states, the error toast, and the sidebar/app icon.

Peers is **dark-only** — \`src/theme/colors.ts\` is a single dark palette, there is no light mode.$GROUND" epic E7-shell

# ---------------------------------------------------------------- infra
mkissue "Scaffold plugins/peers_ui (flake, metadata, .rep, backend skeleton)" \
"Stand up the module per ADR 0001, modelled on \`logos-chat-ui\` 0.2.2.

- \`mkLogosQmlModule\`, inputs \`chat_module\` v0.2.2 + \`delivery_module\` v0.2.0, builder 0.2.6
- \`dependency_overrides\` for delivery's lidl, following upstream
- \`metadata.json\`: type \`ui_qml\`, interface \`universal\`, dependencies both cores
- \`src/peers_ui.rep\` contract + C++ backend skeleton$AC
- \`nix build .#packages.x86_64-linux.lgx-portable\` succeeds
- built \`manifest.json\` reports \`manifestVersion: 0.3.0\`
- the module loads headlessly under \`QT_QPA_PLATFORM=offscreen\`" infra

mkissue "Headless spine: prove identity, conversations, send/receive, groups with no UI" \
"Per the plan's Phase 1 discipline — the spine must be green headlessly before any UI is built.

Prove, with no UI: get address, list conversations, create 1:1, send a message, receive a message,
create a group, add a member, observe \`members_changed\`.$AC
- a ctest target covering the backend logic
- a headless script that drives the module and asserts each step
- output captured as evidence on this issue" infra

mkissue "Two-instance exchange harness (primary interop gate)" \
"Per ADR 0003. Borrow the shape of upstream \`logos-chat-ui\`'s \`doctests/exchange/\`.

**First: verify the coexistence claim empirically** — two instances with separate \`--user-dir\`,
both reach Online, distinct addresses, a real round-trip. Record what \`ss -tln\` actually shows.
If they collide, ADR 0003 is superseded and the phone becomes the primary gate.$AC
- a script that launches two instances, exchanges both directions, and exits non-zero on failure
- a screenshot of each side captured as evidence" infra

mkissue "Parity matrix + drift check script" \
"\`docs/PARITY.md\` as the living Android ↔ Basecamp feature matrix, plus
\`scripts/check-parity.sh\` that fails when a matrix row is missing, unstatused, or references a
feature that no longer exists.

This is an explicit deliverable, not an afterthought — the two clients must stay in sync as Android
evolves.$AC
- every in-scope feature from \`docs/feature-inventory\` has a row with a status
- the check script fails on a hand-broken matrix and passes on a good one
- wired into CI" infra parity

mkissue "Screenshot verification loop" \
"Xvfb + \`nix run\` + \`scrot\`, then read the PNG, per the \`qml-standalone-preview-loop\` recipe.

Note ADR 0005: avoid \`MultiEffect\`/\`ShaderEffect\` so the UI actually renders under
\`QT_QUICK_BACKEND=software\` — upstream \`logos-chat-ui\` loses its icons in offscreen captures for
exactly this reason.$AC
- a repeatable script producing a PNG of any given panel state
- captures committed under \`docs/screenshots/\` as epic evidence" infra

# ---------------------------------------------------------------- E7 shell
mkissue "Theme.qml — hardcode the Peers token set" \
"A local singleton carrying Peers' exact tokens. Source of truth is \`src/theme/colors.ts\`, **not**
the Android repo's \`docs/theme.md\`, which is stale (it documents an emerald \`#10B981\` accent; the
real accent is orange \`#FF5000\`).$AC
- every color, type step, spacing step and radius from \`docs/DESIGN-SPEC.md\` present
- no dependency on \`Theme.palette.*\` matching Peers" E7-shell

mkissue "HexAvatar — pixel-identical identicon component" \
"5x5 left-right-symmetric grid of flush squares, rounded-square container (radius = 22% of side) on
the \`#0A0A0A\` canvas, orange ramp \`#B8420E #FF5000 #FF7A33 #FFB27A #FFE4D0\`.

Full algorithm in \`docs/HEXAVATAR.md\`. Drop the \`mesh\`/\`ble\` ramps — out of scope.$AC
- same seed yields the same grid as the Android renderer
- unit test over known seeds
- custom avatar (\`pfp1:\`) overrides the identicon" E7-shell

mkissue "Lucide icon set as vector paths" \
"Hand-port the exact SVG path data from the Android \`*Icon.tsx\` components (transcribed in
\`docs/ICONS.md\`). Draw as vector paths, never as tinted rasters, so they survive the software
backend. **Never emoji-as-icon** — emoji are content only.$AC
- every icon used by an in-scope screen present
- renders under \`QT_QUICK_BACKEND=software\`" E7-shell

mkissue "Three-panel shell: nav rail, list panel, detail pane" \
"Left nav rail (Chats / Contacts / Settings + own avatar and short address), middle list, right
detail pane. Layout skeleton from \`status-desktop\`, skin from Peers (ADR 0005).$AC
- panels resize sanely; no 0px children (use \`implicitHeight\`/\`Layout.preferredHeight\`)
- screenshot matching the Peers reference" E7-shell

mkissue "Empty, loading and error states" \
"Peers' empty/loading treatments for the conversation list, contacts list and chat thread, plus the
error toast and system lines.$AC
- each state screenshot-verified against the Peers reference" E7-shell

mkissue "Sidebar/app icon" \
"\`qml/icons/Peers_sidebar.png\` (~64px) drawn to match the Peers mark, wired via \`metadata.json\`
\`icon\`. Note the icon path is repo-root-relative and the flake's git \`src\` only sees \`git add\`-ed
files.$AC
- icon appears correctly in the Basecamp sidebar" E7-shell

# ---------------------------------------------------------------- E1
mkissue "Conversation list panel" \
"Rows with avatar, display name, preview, timestamp; row menu (Open / Group info / Delete); empty
state. No archive/mute/pin-conversation — Peers has none.$AC
- rows render from \`list_conversations()\`
- live update on \`conversation_created\` / \`conversation_updated\` / \`conversation_deleted\`" E1-core-messaging

mkissue "Chat thread: message bubbles and day chips" \
"Sent vs received bubble styling (own bubbles are \`#FF5000\` fill with **white** text — never black),
day separator chips, correct ordering and pagination.$AC
- styling matches \`docs/DESIGN-SPEC.md\`
- screenshot matches the Peers reference" E1-core-messaging

mkissue "Composer" \
"Text input, send button with its state colours, disabled state, drafts per conversation.

**Do not attach \`onAccepted\` to \`LogosTextField\`** — it hard-crashes the QML load. Use
\`Keys.onReturnPressed\`.$AC
- Enter sends, Shift+Enter newlines
- draft survives switching conversation and back" E1-core-messaging

mkissue "Send / receive wiring" \
"Wire \`send_message\`, \`get_messages\`, and the \`message_received\` / \`message_sent\` events
through the backend to the QML model.

Bind \`readonly property var backend: logos.module(\"peers_ui\")\`, call SLOTs via
\`logos.watch(...)\`, and ready-gate on \`logos.isViewModuleReady\`. Forgetting the
\`logos.module(...)\` line makes every call a silent no-op while the UI renders fine.$AC
- headless send/receive green before any UI work
- two-instance round-trip passes" E1-core-messaging

mkissue "Send state: pending / failed / retry" \
"Peers has **no delivered or read receipts**. Show only \`pending\`, \`failed\` (with retry) and sent.
Per-message delivery state has no transport in the core contract (ADR 0002) — derive honestly from
send success plus \`delivery_state_changed\`, and do not present a receipt we cannot observe.$AC
- a failed send is retryable and says so
- nothing in the UI implies a read receipt" E1-core-messaging

mkissue "Reply / quote" \
"Quoted-message rendering and the reply affordance, encoded per \`docs/CONTENT-MARKERS.md\`.$AC
- a reply renders as a quote on the peer client
- an unrecognised reply marker degrades gracefully" E1-core-messaging

mkissue "Forward, copy, delete-for-me" \
"The remaining bubble actions. Delete is **local only** — Peers has no remote unsend, and no message
editing.$AC
- forward reuses the conversation picker
- delete removes locally and says it is local" E1-core-messaging

# ---------------------------------------------------------------- E2
mkissue "Create group" \
"\`create_group_conversation(name, desc)\` — shared name and description visible to every member,
distinct from the local-only nickname.$AC
- group appears on both sides with the same name
- two-instance verified" E2-groups

mkissue "Add members" \
"\`add_group_member(convo_id, peer_address)\`. The invite is committed and delivered asynchronously;
the peer observes the conversation once its instance has joined.$AC
- invited peer sees the conversation and the roster
- three-party group verified" E2-groups

mkissue "Group info / roster" \
"\`list_group_members\` — committed members first, then invites awaiting commit. Render pending
invites distinctly. A member another instance invited appears only once the group commits it.$AC
- pending vs committed visually distinct
- updates on \`members_changed\`" E2-groups

mkissue "Leave / wipe group" \
"Scope against the core contract — check what leave/remove primitives actually exist before
promising the Android behaviour. If there is no primitive, say so on this issue and implement the
honest subset (e.g. local delete via \`delete_conversation\`) rather than faking a leave.$AC
- behaviour documented accurately in \`docs/PARITY.md\`" E2-groups

mkissue "Pinned messages + pinned bar" \
"Pin/unpin and the pinned bar, encoded per \`docs/CONTENT-MARKERS.md\`.$AC
- pin renders on the peer client
- unpin clears it" E2-groups

# ---------------------------------------------------------------- E3
mkissue "Contacts list, search and tabs" \
"Contacts panel with search and the Labeled/Seen tabs, plus the contact row menu.$AC
- search filters live
- matches the Peers reference screenshot" E3-contacts

mkissue "Add contact by address paste" \
"Paste a peer address to open a conversation via \`create_conversation(peer_address)\`, which fetches
the peer's key package from the registry and sends the cryptographic invite.$AC
- invalid address rejected with a clear message
- two-instance verified" E3-contacts

mkissue "My address + QR card" \
"Show this installation's \`get_address()\`, its short form, copy/share affordances, and the QR card
with the identicon centre badge.$AC
- QR scans correctly from a phone
- copy puts the full address on the clipboard" E3-contacts

mkissue "QR scan on desktop" \
"Desktop has no rear camera, so scan from a webcam, an image file, or a screen region. Pick one
primary path, record the choice as an ADR, and make it work.$AC
- a Peers phone QR is decoded end to end" E3-contacts

mkissue "Shared contact card (addr1:)" \
"Send and receive a contact card using the existing \`addr1:\` marker grammar.$AC
- card sent from desktop renders on the phone-format parser
- tapping a received card offers to start a conversation" E3-contacts

mkissue "Display name + custom avatar (pfp1:)" \
"Set a display name and a custom avatar, broadcast via \`pfp1:\`, with \`pfp1:clear\` as the
un-broadcast. Custom avatar overrides the identicon.$AC
- round-trips through the marker codec
- clear reverts to the identicon" E3-contacts

# ---------------------------------------------------------------- E4
mkissue "Content-marker codec (foundational)" \
"A single encode/decode unit for every marker in \`docs/CONTENT-MARKERS.md\`. This is a **security
boundary**: payloads are attacker-controlled. Strict grammar, length limits, no unbounded
allocation, no path traversal from embedded filenames.

Blocks the rest of E4.$AC
- exhaustive unit tests including malformed, truncated and oversized inputs
- unrecognised markers degrade gracefully rather than showing raw marker text
- fuzz or property test over the parser" E4-media

mkissue "Photo send + view" \
"Send and render photos.$AC
- desktop-to-desktop round-trip renders the image on the peer
- screenshot evidence both sides" E4-media

mkissue "GIF send + view" \
"Animated GIF send and playback.$AC
- animates on the receiving client" E4-media

mkissue "Video send + view" \
"Video send with inline playback.$AC
- plays on the receiving client" E4-media

mkissue "Voice notes" \
"Record, send and play voice notes. Android caps recording at \`MAX_RECORDING_MS = 120000\` and shows
a \`/ 2:00\` timer — match it.$AC
- record, send, play back on the peer
- the 2:00 cap is enforced and shown" E4-media

mkissue "Media viewer" \
"Full-size viewer with zoom, paging between a conversation's media, save and share.$AC
- zoom and page work with mouse and keyboard" E4-media

mkissue "Reactions" \
"Quick reaction bar, emoji grid, reaction pills and who-reacted, encoded per
\`docs/CONTENT-MARKERS.md\`.$AC
- a reaction renders on the peer client
- pill counts aggregate correctly" E4-media

# ---------------------------------------------------------------- E5
mkissue "Settings panel" \
"Notification toggles, message sound, vibration and show-content. Drop every Tor / private-mode /
mesh / BLE row. Note there is **no light mode** to toggle.$AC
- settings persist across restart" E5-settings

mkissue "Delivery node setting" \
"Expose the delivery preset (\`ChatConfig.delivery_preset\`; empty means \`logos.test\`).$AC
- changing it takes effect on restart and is reported clearly" E5-settings

mkissue "PIN app-lock" \
"Set, change and clear a PIN; lock on background; unlock.$AC
- PIN is stored using a real KDF, never plaintext
- wrong PIN is rate-limited" E5-settings

mkissue "Duress / wipe PIN" \
"A second PIN that wipes identity and data instead of unlocking.

**Security-sensitive.** The wipe must be real and irreversible, must not be distinguishable from a
normal unlock by an observer, and must not be triggerable accidentally.$AC
- entering the duress PIN wipes and presents a clean first-run state
- tested on a disposable instance only" E5-settings

mkissue "Lock screen overlay" \
"A full-window overlay above everything — **not** a panel and **not** a route, matching Android
(\`App.tsx:167-168\`).$AC
- nothing behind it is readable or interactable
- screenshot evidence" E5-settings

mkissue "Reset identity and data" \
"Destructive reset with a real confirmation.$AC
- returns the client to a clean first-run state
- confirmation cannot be dismissed accidentally" E5-settings

# ---------------------------------------------------------------- E6
mkissue "Read a Peers .peersenc backup — decryptor + tests" \
"PBKDF2-HMAC-SHA256 (600000 iters, 16B salt) then AES-256-GCM (12B IV, 128b tag) over the envelope
described in \`docs/BACKUP-FORMAT.md\`.

Pure crypto — fully testable with no core involvement. Keep this on the main thread and review it
adversarially; do not accept unreviewed subagent output here.$AC
- decrypts a real Peers backup fixture
- a documented test vector in the repo
- wrong passphrase fails cleanly, never partially
- the fixture and any seed stay **out of git** (see \`.gitignore\`)" E6-portability

mkissue "Import backup payload: history, contacts, nicknames" \
"Map the decrypted \`conversations\`/\`messages\`/\`group_members\`/\`kv\` into local state as
read-only imported history, and show the imported address.$AC
- imported history renders
- import is clearly labelled as imported, not live" E6-portability

mkissue "Adopt the backup identity (same address) — UPSTREAM BLOCKED" \
"\`chat_module\` 0.2.2 exposes **no identity-import method**: the whole identity surface is
\`get_installation_name\` / \`set_installation_name\` / \`get_address\`, and \`init(ChatConfig)\` takes
only \`delivery_preset\` and \`log_level\`. The identity is derived internally from
\`logos-account\`'s \`TestLogosAccount\`, keyed to the host-assigned instance directory.

There is no parameter to pass the backup's seed to. See ADR 0004.

**Next step:** file an upstream request against \`logos-co/logos-chat-module\` for an identity-import
path on the lidl contract (e.g. \`init\` accepting an optional account seed). Once it lands, only the
final wiring is missing — the decryptor, schema mapping and tests are already done.$AC
- upstream issue filed and linked here
- \`docs/PARITY.md\` marks this blocked with the reason" E6-portability upstream-blocked

mkissue "Desktop backup export" \
"Write a \`.peersenc\` the Android app can read, using the identical envelope and KDF/AEAD
parameters.$AC
- a desktop-written backup is readable by the Android importer (or the divergence is documented)" E6-portability

mkissue "About panel" \
"Version, build, repo link. Strip the Android blurb's MeshCore/Bluetooth-mesh wording.$AC
- version matches the built module" E6-portability

# ---------------------------------------------------------------- interop
mkissue "Interop matrix: desktop-to-desktop" \
"Per ADR 0003, the primary gate. Verify each cell by observing **both** ends and reading both
screenshots — a message is not 'sent' until it renders on the other client.

Cells: 1:1 text both directions; group create + add + messages; photo, GIF, video, voice note both
directions; reply, reaction, pin, forward; offline catch-up.$AC
- a screenshot pair per cell committed under \`docs/screenshots/\`
- results tabulated in \`docs/INTEROP.md\`" infra

mkissue "Interop matrix: desktop-to-Peers-Android" \
"The second gate, with an honestly recorded result either way (ADR 0004).

The phone runs a **different libchat generation** (our patched fork @ \`462a4884\`) than
\`chat_module\` 0.2.2 (@ \`5c55c2ee\`), so compatibility is an open empirical question. A negative
result is a legitimate documented finding, not a build failure.

Fleet discipline: **never reset the Pixel** (\`install -r\` only, PIN 111111, verification only);
Samsung is the destructive-test device; never guess a PIN (3 wrong = wipe).$AC
- each attempted cell has a phone + desktop screenshot pair
- the outcome, including any protocol divergence, written up in \`docs/INTEROP.md\`" infra upstream-blocked

echo "done."
