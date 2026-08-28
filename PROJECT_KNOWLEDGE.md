# PROJECT_KNOWLEDGE — Peers for Basecamp

How to build, run, test and debug this module. Read the ADRs in `docs/adr/` for *why* the
architecture is what it is; this file is the *how*.

---

## The stack, and what actually talks to what

```
  QML view  (qml/PeersView.qml + qml/Peers/*.qml)
     │  logos.module("peers_ui") → the QtRO replica
     ▼
  PeersUiBackend  (C++, src/)                     ← our code
     │  modules().chat_module.<method>()          ← typed client, generated from the lidl
     ▼
  chat_module 0.2.2   (Rust, upstream, interface: cdylib)
     │  logos-generic-chat / libchat @ 5c55c2ee   ← MLS
     ▼
  delivery_module v0.2.0  (Nim, upstream)  →  logos.test Waku fleet
```

**Pins are lockstep and deliberate.** `chat_module` v0.2.2 → `delivery_module` v0.2.0 →
`logos-module-builder` 0.2.6, following upstream `logos-chat-ui` 0.2.2. Do not bump one alone:
`chat_module`'s own flake documents that builder `master` breaks its providers, and a
delivery-version mismatch leaves the QtRO client hanging on a 20s timeout instead of failing loudly.

---

## Building

```bash
cd plugins/peers_ui
nix build .#packages.x86_64-linux.lgx-portable --accept-flake-config
```

**`--accept-flake-config` is not optional in practice.** It enables the Logos Attic cache
(`cache.nix.logos.co/public`). Without it nix ignores the flake's `extra-trusted-public-keys`,
every substitute is refused as unsigned, and the whole Rust + Nim core chain
(`chat_module`, `delivery_module`, `liblogosdelivery`) compiles from source — tens of minutes.

The symptom is unmistakable:

```
warning: ignoring substitute for '/nix/store/…' from 'https://cache.nix.logos.co/public',
         as it's not signed by any of the keys in 'trusted-public-keys'
```

Passing `--option extra-trusted-public-keys …` on the command line does **not** fix it (the daemon
does the substitution). Use `--accept-flake-config`, or add the key to `/etc/nix/nix.conf`.

Use `TMPDIR=/extra/tmp` on `wild` — the Rust builds are large.

### Package variants

| Attribute | What it is |
|---|---|
| `lgx-portable` | variant `linux-amd64` — **this is the installable one** |
| `lgx` | variant `linux-amd64-dev` — `lgpm` **rejects** it |
| `install-portable` | `lgpm install` of the portable lgx into a store path |
| `default` / `apps.default` | `logos-standalone-app` loading only this module + deps |

The `-dev` variant trap has cost hours before on other modules: a `-dev` build looks like "the
module broke / reverted" because Basecamp silently refuses to load it. Always `lgx-portable`.

### Manifest gate

```bash
tar xzOf result/*.lgx manifest.json | python3 -c "import json,sys;print(json.load(sys.stdin)['manifestVersion'])"
```

Must print `0.3.0`. An older builder produces `0.2.0`, which loads and then goes blank with no
errors. Builder 0.2.6 emits `0.3.0` — verified against upstream `logos-chat-ui`'s own build.

Note `.lgx` is a **gzipped tar**, not a zip. `unzip` fails on it.

---

## Running

### Standalone (fast dev loop)

```bash
cd plugins/peers_ui
nix run . --accept-flake-config -- --user-dir ~/.local/share/peers_a
```

`--user-dir` gives the instance its own session directory. This is what makes two instances on one
host possible (below).

### Two instances — the primary interop gate (ADR 0003)

Two instances coexist on one host: each picks a random QtRO socket name and each delivery node picks
its own listening ports. **Verified empirically** — two instances both reached Online with distinct
addresses, and `ss -tln` showed no fixed-port contention. The build plan's claim that
`delivery_module` binds a global TCP 60000 is **not true** of the v0.2.0 pin.

```bash
nix run . --accept-flake-config -- --user-dir ~/.local/share/peers_a   # window A
nix run . --accept-flake-config -- --user-dir ~/.local/share/peers_b   # window B
```

Upstream `logos-chat-ui` automates this in `doctests/exchange/run-exchange.mjs`, driving both
instances over the `logos-qt-mcp` inspector protocol. That harness is the model for ours.

### Installing into Basecamp

Install into **LogosBasecamp**, never LogosApp:

```bash
lgpm --modules-dir ~/.local/share/Logos/LogosBasecamp/modules \
     --ui-plugins-dir ~/.local/share/Logos/LogosBasecamp/plugins \
     --allow-unsigned install --file result/*.lgx
```

For isolated deployments, use `scripts/install-iso.sh`; do not manually delete package or QML-cache
paths. The installer validates both packages, builds a complete isolated-root candidate with a fresh
cache, and publishes packages plus cache through one same-parent atomic exchange.

For testing against a live Basecamp without disturbing it, use the `run-isolated` skill (per-session
`LOGOS_INSTANCE_ID` + absolute `XDG_*_HOME`). **Safety gate: never kill a process whose
`XDG_DATA_HOME` is not exactly your isolated `$ISO/data`.**

---

## Testing

### Pure-logic tests (no core, no UI, fast)

```bash
node tests/identicon-equivalence.mjs
```

Proves the QML identicon port is byte-identical to Peers Android by lifting the real
`identiconCells` implementation out of `src/components/HexAvatar.tsx` at run time and diffing both
over 8,000+ (seed, kind) pairs, plus symmetry/determinism/range invariants. It **exits 2 and says
so** when the Android checkout is absent, rather than passing silently. Point it at a checkout with
`PEERS_ANDROID_REPO=… ` or argv[1].

This lift-don't-copy approach is deliberate: if Android changes the algorithm, the test starts
failing instead of quietly comparing against a stale copy.

### Backend tests

```bash
ctest --test-dir build/ --output-on-failure
```

### Headless load proof

```bash
QT_QPA_PLATFORM=offscreen nix run . --accept-flake-config -- --user-dir /tmp/peers-smoke
```

Confirm the module actually loaded via the ui-host process table — `comm`/`exe` are the ld-linux
loader, so **match on argv**, not on the process name.

### Screenshot verification

```bash
Xvfb :98 -screen 0 1280x900x24 &
unset WAYLAND_DISPLAY
DISPLAY=:98 QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 nix run . --accept-flake-config
scrot -o preview.png
```

Then **read the PNG** — a screenshot you did not look at is not verification.

**`MultiEffect`/`ShaderEffect` render blank under the software backend.** This is not theoretical:
upstream `logos-chat-ui`'s own offscreen captures lose their New-chat icon, copy buttons and send
arrow for exactly this reason, and our first capture of it reproduced that. Our components draw
icons as vector paths precisely so the screenshot loop stays trustworthy (ADR 0005). If you ever
must render a shader-based component, drop `QT_QUICK_BACKEND=software` and use GL/llvmpipe.

---

## Gotchas that will cost you an evening

**The silent no-op.** In QML, bind `readonly property var backend: logos.module("peers_ui")`, call
SLOTs through `logos.watch(backend.method(args), okCb, errCb)`, and ready-gate on
`logos.isViewModuleReady("peers_ui")` + `onViewModuleReadyChanged`. Omit the `logos.module(...)`
line and every call becomes a no-op while the UI renders perfectly. `logos.callModule` does **not**
reach universal cores.

**Never do a synchronous module read from inside a module event callback.** `list_conversations`,
`get_messages` and `list_group_members` are synchronous QtRO calls; issuing one from inside an event
handler re-enters the replica's socket-read handler while its read notifier is disabled, so the
reply only lands after the ~20s call timeout and the UI thread stalls for that whole time. Defer to
the next event-loop turn (`deferToEventLoop`). Upstream hit this and documents it; we inherit the
same constraint.

**Subscribe to events before taking the initial snapshot**, or an event that fires in the gap is
lost and history goes missing until a reconnect that may never come.

**`LogosTextField` has no `onAccepted`** — attaching a handler for it hard-crashes the QML load. Use
`Keys.onReturnPressed`.

**QML items go 0px** inside a layout if you set a bare `height:`. Use `implicitHeight` or
`Layout.preferredHeight`, and never set `Layout.alignment` on a `fillWidth` item — it silently
disables the fill.

**`metadata.json` `icon` is repo-root-relative**, and the flake's git `src` only sees files that
have been `git add`-ed. A new icon that is not staged is invisible to the build.

**`peers_core` has no identity import** — see ADR 0004 before promising anything about adopting a
backup's address. (Phone interop itself is solved, by the forks — ADR 0007.)

**Killing `nix run` does not kill the app.** `logos-standalone-app-bin` forks a `logos_host_qt` per
module and they survive, holding the inspector port — so the next run silently drives the OLD build.
That reads as state surviving a wiped `--user-dir`, or as a flaky network. Launch under `setsid`,
kill the process group, preflight the port, and match on **argv**. In `pkill -f`, use the
`'[l]ike-this'` bracket trick or you match and kill your own shell.

---

## The forks — read before touching the core

Peers runs a **forked** chat core. `peers_ui` depends on **`peers_core`**
([xAlisher/peers-core](https://github.com/xAlisher/peers-core)), built on
[**`peers-libchat`**](https://github.com/xAlisher/peers-libchat) — NOT upstream `chat_module`.

Peers Android does not speak upstream's wire format: conversations are addressed by an opaque
`route_tag` rather than `hex(group_id)`, payloads are outer-encrypted, and the group context carries
`GROUP_SECRET` (0xFF02), which every member's leaf capabilities must advertise. An upstream-built
client is rejected before a conversation can form. See ADR 0007 and `docs/FORK-MAINTENANCE.md`.

**`peers_core` talks to Peers Android and NOT to stock Basecamp `chat_ui`.** Intended trade.

Delivery pins the same entry node the phone uses (`msg.logos.live`). That switches delivery to its
**flat** config shape, whose listening ports are FIXED — so two *pinned* instances cannot share a
host. Anything running two locally sets `PEERS_DELIVERY_NODE=""`.

---

## Reference sources

| What | Where |
|---|---|
| The core contract | `github.com/logos-co/logos-chat-module` → `rust-lib/chat_module.lidl` |
| The canonical consumer | `github.com/logos-co/logos-chat-ui` v0.2.2 — `.rep` + `ChatBackend.cpp` |
| Backend lifecycle idiom, screenshot loop | `~/basecamp/modules/receiver-basecamp/` |
| Peers design + feature source of truth | `~/projects/logos-chat-android/` |
| Platform recipes | `~/basecamp/basecamp-skills/skills/` — read `_index/` first |

**Peers design source of truth is `src/theme/colors.ts`, not the Android repo's `docs/theme.md`** —
the latter is stale and still documents an emerald `#10B981` accent. The real accent is orange
`#FF5000`.

---

## Gates

```bash
./scripts/check-all.sh      # identicon equivalence · parity matrix · qmldir guard
./scripts/run-exchange.sh                          # 1:1 round-trip (two instances)
TEST=tests/group.mjs        ./scripts/run-exchange.sh   # group create + add + messages
TEST=tests/interactions.mjs ./scripts/run-exchange.sh   # reply, reaction, pin, unpin
```

`check-all.sh` runs automatically on commit via `.githooks/pre-commit`
(`git config core.hooksPath .githooks`, already set in this clone; a fresh clone
must run it once).

The scenario runners each take a few minutes: two instances have to reach Online
on the live fleet, and the join step is genuinely flaky — exit code **2** means
"the invite never landed", which is distinct from **1**, "an assertion failed".
Re-run before investigating a 2.
