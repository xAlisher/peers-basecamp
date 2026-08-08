# ADR 0005 — Three-panel layout, and Peers parity beats the Logos design system

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

Peers Android is a stack of full-screen mobile screens reached by push navigation. Basecamp is a
desktop shell. The two have to be reconciled without losing Peers' identity.

Separately, the Logos design system (`import Logos.Theme/Controls/Icons`) is available natively in
the ui-host, but is documented as incomplete and buggy in several ways that bite exactly the controls
a chat client needs:

- `LogosTextField` has **no `onAccepted`** — attaching a handler for it hard-crashes the QML load.
- `LogosIconButton` with a data-URI SVG renders **blank** in the ui-host.
- There is **no gear/settings icon** in the set.
- `MultiEffect` / `ShaderEffect`-based components render **blank** under the software backend.
  Upstream `logos-chat-ui` hits this too: its own `docs/two-instance-exchange.md` notes that in
  offscreen captures "the New chat button, the copy buttons and the send arrow render as their bare
  backgrounds" because `LogosIcon` tints its asset through a `MultiEffect`.

Peers' visual identity is also simply *different* from the Logos DS default: a `#0A0A0A` canvas,
an `#FF5000` orange accent, flush square identicons, and white-on-orange own-message bubbles.

## Decision

### Layout — three panels

| Panel | Contents |
|---|---|
| **Left nav rail** | Chats / Contacts / Settings, plus your own `HexAvatar` and short address |
| **Middle list** | Conversations or contacts, with search and a "new" affordance |
| **Right main pane** | The active chat with composer, or a contact / group-info / settings detail |

Peers' stacked mobile screens collapse onto this as *list → right-pane detail*. Screens that are
modal on mobile and genuinely modal on desktop (QR scan, add member, new group, PIN entry) stay
dialogs. The lock screen is a full-window overlay, not a panel, because it must cover everything.

`~/basecamp/refs/status-desktop/` supplies the *layout skeleton* only. Peers supplies the *skin*.

### Skin — a custom component library, Peers wins conflicts

1. **Build `qml/components/` as a self-contained Peers-parity component set** — bubbles, conversation
   rows, composer, headers, empty/loading states, `HexAvatar`, buttons, inputs, chips, dialogs.
2. **Hardcode Peers' tokens in a local `Theme.qml` singleton.** Do not depend on `Theme.palette.*`
   matching Peers; it does not. The values come from `docs/DESIGN-SPEC.md`, whose source of truth is
   `src/theme/colors.ts` in the Android repo — **not** the app's own `docs/theme.md`, which is stale
   (it still documents an emerald `#10B981` accent; the real accent is orange `#FF5000`).
3. **Reach for the Logos DS only where it is already clean and correct** — a plain container, a
   layout primitive. Never bend a Peers visual to fit a DS control.
4. **Avoid `MultiEffect`/`ShaderEffect` in anything that must be screenshot-verified.** Icons are
   drawn as vector paths, not tinted rasters, so they render under the software backend. This is a
   correctness requirement for our own verification loop, not just a style preference.
5. **Icons are hand-ported Lucide vector paths** (`docs/ICONS.md`), matching the Android convention.
   **Never emoji-as-icon.** Emoji appear only as content, e.g. a reaction a user picked.
6. **Parity is judged against Peers screenshots**, never against the DS.

## Consequences

- More component code than leaning on the DS, and that is the intended trade: the DS's known-broken
  controls are the reason the custom set exists.
- The UI renders correctly under `QT_QUICK_BACKEND=software`, which keeps the headless screenshot
  loop trustworthy — a real advantage over upstream `logos-chat-ui`, whose offscreen captures lose
  their icons.
- A single `Theme.qml` means a future DS alignment is one file, not a sweep.
