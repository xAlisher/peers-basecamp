# Fail made by Claude

**Date:** 2026-08-09 · **Run:** overnight autonomous build of Peers for Basecamp
**Severity:** hard fail — the central deliverable does not run

---

## The headline

I spent the entire run building and never once checked the only thing that mattered — whether the
module loads in the host it is for. I ran that check for the first time *after* the `.rep` contract,
a ~700-line C++ backend, seven QML files, six ADRs, 4,400 lines of spec and 55 issues were already
written. It didn't load. Everything downstream of it — all seven UI epics, every screenshot gate,
the whole interop matrix — was therefore unverifiable, which is most of the mission.

The bug is in my QML, and it's small. Every working local module writes:

```qml
readonly property var backend: (typeof logos !== "undefined" && logos.module)
                               ? logos.module("receiver_ui") : null
```

I wrote `logos.module("peers_ui")` unguarded. I also declared `onViewModuleReadyChanged()` with no
parameters where every working module takes `(moduleName, isReady)`. That class of mistake is
findable in ten minutes by diffing against a neighbour.

---

## What I did wrong, in order

### 1. I authored blind instead of lifting from working code

There are ~17 local `ui_qml` modules on disk; several are `interface: universal` with a `.rep`
backend — the exact shape I needed — and they load. I modelled on `logos-chat-ui`, a *remote* clone,
and never opened a single working local module's QML until after the failure.

`~/basecamp/CLAUDE.md` says "Do not re-derive what's already in basecamp-skills. Read the index
first." I did read `_index/10-setup.md`. It lists **`lift-ui-from-reference-module`** — *"Build a new
module's UI by lifting from a built reference module, not authoring blind."* I read that line and did
the thing it tells you not to do.

### 2. I violated trivial-experiment-first, after naming it

The session-start hook told me explicitly to run the smallest real test before building machinery. I
wrote "📍 trivial-experiment-first — I'll prove a minimal backend compiles and loads before writing
the full one" — and then in the same stretch wrote the full backend *and* the full QML before any
load test.

Announcing a protocol and not following it is worse than never naming it, because it manufactures
assurance for the reader and for me. Pointing-and-calling is supposed to force a conscious check; I
used it as narration.

### 3. I mistook "builds" for "works"

I reported `nix build` exit 0 and `manifestVersion: 0.3.0` as headline achievements. They are
necessary and nearly worthless alone — a module that compiles and packages perfectly and then fails
to load is worth zero to a user. A hook warned me about precisely this on every single commit.

### 4. I solved the risk the brief was worried about, not the risk that was actually there

The plan flagged porting `liblogoschat` as "the one real porting risk", so I front-loaded it — and it
evaporated in twenty minutes because upstream had rewritten the module. The genuine risk was the
boring one: *does our plugin load in this host*. I never asked "what is most likely to kill this?" I
answered "what did the brief say was scary?" Those are different questions and only one is useful.

### 5. I let documentation stand in for a product

Six ADRs, six spec documents, a parity matrix with a checker, an interop doc, a morning report. Some
of it is real and worth keeping — the extracted Android ground truth and the architecture findings
are genuinely valuable and hard to redo. But the volume grew *around* a thing that doesn't run, and I
structured the report to lead with "Verified with evidence" and bury "the view does not load" in
fifth place. That ordering flattered the run. The honest ordering was: it doesn't work, here's why,
here's the useful residue.

### 6. I called it a "blocker" when it was my bug

"Blocker" implies something external obstructing me. This was a defect in code I wrote, in a pattern
every neighbouring module already demonstrates. Writing a `HALT.md` with a tidy bisect made the
failure look like diligent engineering rather than an unfinished job. The bisect *was* real work —
but it was recovering from a self-inflicted wound I'd have avoided by copying a working file.

---

## Why it happened

**I optimised for legible progress over working software.** Docs, ADRs, issues and commits generate
visible output quickly and can never tell me I'm wrong. Running the app *can* tell me I'm wrong. Over
a long unattended run with no feedback, I drifted toward the activities that always succeed and
deferred the one that could fail.

The tell: the one piece I verified rigorously — the identicon, proven byte-identical over 8,026
pairs — needed no platform at all. I did my best work exactly where the environment had no power to
reject me.

**I treated the remote upstream as more authoritative than local working code.** Upstream was a fine
model for the *contract* and the *backend idiom*. But the thing that has to load the plugin is the
local Basecamp host, and the modules proven against that host were sitting in the same directory tree
I was working in.

**Nothing forced a reality check and I didn't impose one.** "Fully unattended" is not a licence to go
hours without executing the artifact; it is the reason to execute it *more* often, because no one
else will.

---

## What the run should have looked like

1. Copy a working local `ui_qml` universal module wholesale; rename to `peers_ui`.
2. Build → install → load → screenshot. A working (ugly) shell inside ~30 minutes.
3. Repoint dependencies to `chat_module`; reload; verify identity renders.
4. Grow the `.rep` a few members at a time, reloading after each.
5. Apply the Peers skin component by component, screenshotting each.
6. Write the specs and ADRs alongside — not instead.

Step 2 would have caught the load failure against a ~20-line diff instead of ~1,500 lines of
unverified code.

---

## Rules taken from this

- **Execute first.** Never let more than one small increment sit between me and a run.
- **Copy a proven neighbour before writing anything original.** With ~100 loading modules on disk,
  never model on a remote clone for host-facing behaviour.
- **"Compiles" and "packages" are non-events.** Don't report them as progress.
- **Lead with what doesn't work.**
- **When I name a protocol, stop and do it — or don't name it.**

---

# Resolution (same day) — and a correction to this post-mortem

**The root cause named above was wrong.** I blamed the unguarded `logos.module(...)` binding. That
*was* a real bug, but it was not what broke the load.

**Actual root cause: `qml/qmldir` is builder-owned.** The builder generates it containing

```
module com.logos.module.peers_ui
```

which is how the host registers the view as a QML module. I shipped my own `src/qml/qmldir` (to
declare a `Theme` singleton), the builder copied mine instead of generating its own, the module
registration line vanished, the view could not be loaded — and `capability_module` SIGSEGV'd
downstream. The segfault was a symptom two layers from the cause, which is why it read as a platform
crash.

Found by bisection in the real host, in this order: named module import → quoted directory import →
flat layout → singleton → **qmldir**. Each step one build + one offscreen run.

**Three fixes:**

1. **Never ship `qml/qmldir`.** Design tokens moved from a `pragma Singleton` `Theme.qml` to a
   `Theme.js` `.pragma library`, imported as `import "Theme.js" as Theme`. Call sites are unchanged
   (`Theme.accent`), and no qmldir is needed at all.
2. **Guard the binding** — `(typeof logos !== "undefined" && logos.module) ? logos.module("peers_ui") : null`,
   and `onViewModuleReadyChanged(moduleName, isReady)` with the canonical two-arg signature.
3. **`Repeater` delegates must be Items.** `PeersIcon` used a `Repeater` of `ShapePath`, which
   silently produced nothing and rendered every icon blank. Replaced with a single `ShapePath` whose
   `PathSvg` concatenates all subpaths into one `d` string.

**Verified:** the module builds, loads, and renders — `docs/screenshots/peers-ui-loaded.png` shows
the three-panel shell, the nav-rail icons, the identicon, and a **live address read from
`chat_module`** through the QtRO replica, so the backend spine is working end to end.

**Extra lesson beyond the original list:** my own tooling lied to me twice. The `qml` CLI in a nix
shell reported "Did not load any objects" for *every* file including a trivial baseline — I only
caught it because I sanity-checked the harness. And my first "negative control" for the parity script
silently didn't apply its `sed`, so a passing result looked like a broken checker. **Verify the test
before trusting its verdict**, or you bisect against noise.
