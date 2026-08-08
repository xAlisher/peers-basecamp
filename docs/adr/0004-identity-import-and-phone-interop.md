# ADR 0004 — Identity import and Peers-Android interop are upstream-constrained

- **Status:** Accepted (constraint recorded; work re-scoped, not abandoned)
- **Date:** 2026-08-09
- **Decision owner:** autonomous build agent (unattended run)
- **Supersedes assumptions in:** the build plan's §IDENTITY and §CROSS-CLIENT PHONE INTEROP

## Context

The build plan sets two hard done-criteria:

1. *"a Peers-mobile backup opens the **same address** on desktop"*
2. *"real desktop ⇄ phone (Peers Android) interop verified for 1:1, groups, attachments …"*

Both assume the desktop client can (a) be told which identity to be, and (b) speak the same wire
protocol as the phone. Phase 0 investigation shows **neither is currently supported by the upstream
core we ride** (ADR 0001).

### Finding 1 — `chat_module` 0.2.2 has no identity-import method

The complete identity surface of `rust-lib/chat_module.lidl` is:

```
method get_installation_name() -> tstr
method set_installation_name(name: tstr) -> result
method get_address() -> tstr
```

There is **no** `open_persistent`, no `generate_identity`, no seed/secret parameter anywhere in the
contract. `init(config: ChatConfig)` takes only `delivery_preset` and `log_level`. The identity is
derived internally from `logos-account`'s `TestLogosAccount` (per `rust-lib/Cargo.toml`: *"the
ephemeral account identity that signs this installation's device bundle and whose key is the shared
account address"*), keyed to the host-assigned instance directory.

So a desktop client riding `chat_module` 0.2.2 **cannot be handed the Peers backup's `identity`
seed bytes**. There is no parameter to pass them to.

### Finding 2 — the phone and the desktop core are different generations of libchat

Both descend from `logos-messaging/libchat`, but:

- `chat_module` 0.2.2 pins libchat @ `5c55c2ee76bebd1dbd5eb4bfa95d9e71acd0fa14`.
- Peers Android embeds `liblogoschat.so` from **our patched fork** (`xAlisher/logos-libchat-mls-android`,
  repinned to `462a4884` per the #427 repin), plus `liblogosdelivery.so`, plus app-level patches
  (size padding, XWING deferral, etc.).

Shared lineage makes interop *plausible*, not *demonstrated*. The MLS group state, key-package
registry, delivery preset and address encoding all have to match, and two independently-pinned revs
of a fast-moving protocol library are exactly where they diverge. Additionally Peers Android layers
its own conventions (ADR 0002) that the upstream desktop core knows nothing about.

**This is an empirical question, and it is the correct thing to test — but it cannot be assumed, and
it must not gate unrelated work.**

## Decision

1. **Implement and fully test the backup *decryptor* regardless.** It is pure, self-contained crypto
   (PBKDF2-HMAC-SHA256 → AES-256-GCM), it is independently valuable, and it is testable headlessly
   against a fixture with no core involvement. Ship it with unit tests and a documented test vector.
   This delivers everything in the plan's §IDENTITY *except* the final "feed the seed to the core"
   step, which has no upstream landing point.
2. **Surface the imported payload for everything it *can* drive**: display the imported address,
   import conversation/contact metadata and message history as local read-only history, and
   restore nicknames — none of which requires adopting the identity.
3. **Do not claim "same address on desktop."** Record it as upstream-blocked in `HALT.md` with the
   exact next step (an upstream feature request against `logos-chat-module` for an identity-import
   method on the lidl contract, e.g. `init` accepting an optional account seed).
4. **Treat phone interop as an experiment with an honest recorded result**, run *after* the desktop
   client can send and receive at all. Test desktop⇄desktop first (ADR 0003) — that is the gate that
   actually proves our code. Then attempt desktop⇄phone and record the outcome either way. A negative
   result is a legitimate, documented finding about two core generations, not a build failure.
5. **Every messaging epic's acceptance bar is desktop⇄desktop interop**, with phone interop recorded
   as an additional cell that may legitimately read "blocked: core generation mismatch". The plan's
   "no epic is done without a passing phone-interop cell" is relaxed *only* to this extent, because
   holding every epic hostage to an upstream protocol divergence would forfeit the entire build.

## Consequences

- The plan's done-criterion "a Peers-mobile backup opens the same address on desktop" **will not be
  met** in this run, and is reported as such rather than quietly dropped or faked.
- Everything else in §IDENTITY (envelope parsing, KDF, AEAD, schema, history import) is deliverable
  and tested.
- Phone interop gets an honest matrix with real evidence, including negative cells.
- If upstream later adds identity import, only the final wiring step is missing — the decryptor,
  schema mapping and tests are already in place.

## Evidence

- `rust-lib/chat_module.lidl` (upstream `a05d511`) — complete method list quoted above; no import path.
- `rust-lib/Cargo.toml` — libchat rev `5c55c2ee`; `logos-account` `TestLogosAccount` with `dev` feature.
- Peers Android `SECURITY.md:61`, `HANDOFF.md:395` — patched fork lineage.
- `android/app/src/main/jniLibs/arm64-v8a/{liblogoschat.so,liblogosdelivery.so}` — arm64 only.
