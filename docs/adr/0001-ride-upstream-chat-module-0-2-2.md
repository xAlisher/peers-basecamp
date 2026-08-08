# ADR 0001 — Ride upstream `chat_module` 0.2.2 (Rust/lidl), not the C-FFI `liblogoschat` shape

- **Status:** Accepted
- **Date:** 2026-08-09
- **Decision owner:** autonomous build agent (unattended run)

## Context

The build plan (`~/basecamp/plans/peers-basecamp-agent-prompt.md`) specifies riding the Basecamp
`chat_module` core, and describes its API as a **C FFI** surface:

> liblogoschat C FFI in `tests/stubs/lib/liblogoschat.h` (`chat_new/start/stop`,
> `set_event_callback`, `chat_list_conversations`, `chat_new_private_conversation`,
> `chat_send_message`, `chat_get_identity`, `chat_create_intro_bundle`; events
> `chatNewMessage/chatNewConversation/chatDeliveryAck`).

That description matches the **local reference clone** at `~/basecamp/refs/logos-chat-module/`,
which is pinned at commit `9b22b52` (2026-06-17), `metadata.json` version `1.0.0`,
`interface: "universal"`, with `external_libraries: [{name: "chat", build_command: "true"}]`.

**Upstream has since been rewritten.** `github.com/logos-co/logos-chat-module` HEAD (`a05d511`) is:

| | local ref (`9b22b52`, Jun 17) | upstream HEAD (`a05d511`) |
|---|---|---|
| version | `1.0.0` | `0.2.2` |
| `interface` | `universal` | `cdylib` |
| implementation | C++ over a prebuilt `liblogoschat.so` | **Rust** (`rust-lib/`, staticlib) |
| contract | `chat_module_plugin.h` (C++ header) | **`rust-lib/chat_module.lidl`** (Logos IDL) |
| `dependencies` | `[]` | `["delivery_module"]` |
| codegen | `impl_header` | `lidl` + `rust` crate |

The API named in the plan (`chat_new`, `chat_create_intro_bundle`, `chatDeliveryAck`, …) **does not
exist upstream**. The current contract is the lidl in `rust-lib/chat_module.lidl`.

Critically, both generations wrap the **same underlying core**. Upstream `chat_module` 0.2.2 depends on
`logos-generic-chat` / `libchat` / `logos-account` from `github.com/logos-messaging/libchat`
@ `5c55c2ee76bebd1dbd5eb4bfa95d9e71acd0fa14`. Peers Android embeds `liblogoschat.so` built from a
patched fork of that same `logos-messaging/libchat` repo. So the MLS semantics are a shared lineage —
see ADR 0004 for what that does and does not imply for interop.

Upstream also ships **`logos-chat-ui` 0.2.2** (`github.com/logos-co/logos-chat-ui`): a
`type: ui_qml`, `interface: universal` module with a `.rep` contract (`src/ChatBackend.rep`), a C++
`ChatBackend`, QtRO-replica list models, and QML views. It is the canonical, currently-maintained
consumer of `chat_module` 0.2.2 — exactly the module shape this project needs.

## Decision

1. **Target upstream `chat_module` v0.2.2** and its lidl contract as the core API. Treat
   `~/basecamp/refs/logos-chat-module/` as historical only; do not build against it.
2. **Model `plugins/peers_ui` on `logos-chat-ui` v0.2.2**, not on `receiver-basecamp`. Same flake
   shape (`mkLogosQmlModule`, `chat_module` + `delivery_module` inputs with `dependency_overrides`),
   same `.rep` + C++ backend + QtRO model pattern. `receiver-basecamp` remains a useful reference for
   the *backend lifecycle idiom* (`LogosUiPluginContext::onContextReady`, deferring work one turn) and
   for the screenshot/verification loop, but its `delivery_module`-consuming data path does not apply.
3. **Pin in lockstep**, following upstream's own convention: `chat_module` v0.2.2 →
   `delivery_module` v0.2.0 → `logos-module-builder` 0.2.6, with `logos-chat-ui`'s
   `dependency_overrides` trick for delivery's lidl.
4. **Author all QML fresh** in the Peers design language. `logos-chat-ui`'s QML is a *structural*
   reference for how the backend is consumed, never a skin to inherit (see ADR 0005).

## Consequences

**Good**
- No `liblogoschat` porting risk at all. The plan flagged this as "the one real porting risk"; it is
  moot. The whole chain (`chat_module` Rust → `delivery_module` → `chat_ui`) builds from the Logos
  binary cache on `x86_64-linux` — verified, exit 0.
- We inherit a maintained, documented, typed contract instead of a stub header.
- Upstream's `doctests/` give a working two-instance exchange harness to borrow (ADR 0003).

**Costs / constraints**
- The lidl contract is **text-only**. It has no attachment, reaction, reply, pin, or read-receipt
  primitives. Peers' rich content must be layered inside the message body — see ADR 0002.
- The contract exposes **no identity import/restore method**. This directly constrains the
  "adopt a Peers-mobile backup identity" goal — see ADR 0004.
- `interface: "cdylib"` means the core is not consumed via the old `universal` C++ `modules().x` shape
  the plan describes; the builder generates a typed client from the lidl instead.
- Pinning to `logos-module-builder` **0.2.6** (upstream's pin) rather than builder `main`. The plan's
  `manifestVersion: 0.3.0` gate must be re-checked against what 0.2.6 actually emits; if it emits
  `0.2.0`, matching upstream's released, working pin takes precedence over the plan's version number,
  because `chat_module` 0.2.2's own flake comment documents that builder `main` breaks its providers.

## Evidence

- `git clone github.com/logos-co/logos-chat-module` → `a05d511`, `metadata.json` as tabulated above.
- `rust-lib/Cargo.toml` → `logos-generic-chat`, `libchat`, `logos-account` @ `5c55c2ee`.
- `git clone github.com/logos-co/logos-chat-ui` → `4d74175` "build: prepare 0.2.2 against
  chat_module 0.2.2 / delivery_module v0.2.0".
- `nix build .#packages.x86_64-linux.default` on `logos-chat-ui` → **exit 0**, output
  `/nix/store/dsgkar97fbfswbsapja486gb1hs4ng8g-logos-chat_ui-module`.
- Peers Android native libs: `android/app/src/main/jniLibs/arm64-v8a/liblogoschat.so`,
  `liblogosdelivery.so`; `SECURITY.md:61` — "from a patched fork of logos-messaging/libchat".
