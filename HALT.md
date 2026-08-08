# HALT — `peers_ui` view fails to load; `capability_module` SIGSEGVs

> Tracked as [#57](https://github.com/xAlisher/peers-basecamp/issues/57).

**Date:** 2026-08-09 · **Blocks:** every UI epic (E1–E7) · **Does not block:** the pure-logic work

This is the one hard blocker from the overnight run. Everything else that could proceed did —
see `MORNING-REPORT.md`.

---

## Symptom

Launching the module standalone renders **"Failed to load UI plugin"** and the host log shows:

```
[info]     [logos] Module loaded: capability_module
[info]     [logos] Module loaded: delivery_module
[info]     [logos] Module loaded: chat_module
[critical] [logos] [capability_module] FATAL: module 'capability_module' crashed (signal 11).
[critical] [logos] Module process crashed: capability_module
```

Screenshot: `docs/screenshots/peers-ui-failed-load.png`.

The crash lands ~280 ms after the three core modules load. `chat_module` and `delivery_module`
themselves load fine.

## What has already been ruled out (do not redo this)

| Hypothesis | Test | Result |
|---|---|---|
| Our C++ backend is broken | Build | **Builds clean**, exit 0, `manifestVersion 0.3.0`, correct `linux-amd64` variant |
| It only fails under Xvfb/xcb | Ran offscreen too | **Same crash** — not display-related |
| The platform is simply broken here | Ran upstream `logos-chat-ui` standalone, same host, same flags, same `--user-dir` shape | **Upstream loads fine, no crash** — so it is ours |
| We pull in a module upstream doesn't | Compared `*-plugin-dir-modules` | **Identical sets**: `capability_module`, `chat_module`, `delivery_module` |
| `QtQuick.Shapes` is unavailable in the ui-host (our icons need it) | Minimal view importing `QtQuick.Shapes` + `Shape`/`ShapePath`/`PathSvg` | **Loads fine** — Shapes IS available |
| `.rep` class name must equal `codegen.backend_class` (upstream's do) | Renamed `PeersUi` → `PeersUiBackend`, rebuilt | **Still crashes.** Kept anyway: matching upstream is the safer convention |

## The decisive bisect

- **Minimal `PeersView.qml`** (a bare `Rectangle` + `Text`) → **no crash, plugin loads.**
- **Full `PeersView.qml`** → **crash, plugin fails to load.**

Same `.so`, same manifest, same module set — **only the QML differs**. So the fault is in our QML
or in what the QML causes the host to do, not in the backend or the platform.

Working hypothesis, consistent with the evidence: the minimal view never calls
`logos.module("peers_ui")`, so no QtRO replica and no capability token is ever requested. The full
view does, and `capability_module` dies servicing that request. That would make the segfault a
*symptom* of something malformed in the contract or the view, not the root cause.

## Exact next step

Bisect the view. It is mechanical and each step is one `nix build` + one offscreen run:

1. Start from the minimal view. Add **only** `readonly property var backend: logos.module("peers_ui")`
   and render one PROP (e.g. `backend.myAddress`). Run.
   - **If it crashes here**, the problem is the replica/contract itself, not the components. Then
     bisect `src/peers_ui.rep` by halving it — prime suspects, in order:
     - `PROP(QVariantList errors READONLY)` — the only non-primitive PROP; upstream has the same,
       but ours has no default value where every other PROP does.
     - `SIGNAL(error(QString message))` and `SLOT(void lock())` — generic names that may collide
       with something in the generated glue or QObject.
     - The `ENUM ChatStatus` combined with `PROP(ChatStatus chatStatus READONLY)` having no default.
   - **If it loads**, the contract is fine — continue to 2.
2. Add the components back one at a time in this order (cheapest to most suspect):
   `Theme` → `EmptyState` → `PeersIcon` → `HexAvatar` → `ConversationRow` → `MessageBubble` →
   `Composer`. The first one that crashes is the culprit.
   - Suspect in `Composer`: `TextArea` from `QtQuick.Controls` with `background: null`.
   - Suspect in `MessageBubble`/the view: `parent.parent.hasConversation` — a fragile lookup that
     resolves to `undefined` if the hierarchy differs from what I assumed.
   - Suspect in delegates: `required property var modelData` against a plain JS-array model.
3. Get the real QML error rather than inferring it. The ui-host swallows child stderr
   ([basecamp#163]); use the file-diag approach from the `delivery-getclient-hang-295` recipe, or
   attach to the `ui-host` process (match on **argv**, not `comm`/`exe` — those are the ld-linux
   loader) per `ui-qml-backend-segfault-debug`.

## Why this did not stop the rest of the run

Per the Phase 0 rule, work that does not depend on a loading view continued: the repo, the epics
and 48 issues, all six ground-truth specs, the ADRs, the proven identicon port, the content-marker
codec, the backend, and the full end-to-end verification of the underlying stack (a real
two-instance encrypted round-trip). See `MORNING-REPORT.md`.
