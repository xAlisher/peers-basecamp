# ADR 0007 — Fork the chat core so Peers desktop and Peers Android are one network

- **Status:** Accepted — implemented and verified 2026-08-09
- **Supersedes:** the "ride upstream `chat_module`" half of [ADR 0001](0001-ride-upstream-chat-module-0-2-2.md)
- **Answers:** the blocker identified in [ADR 0004](0004-identity-import-and-phone-interop.md) and issue #59

## Context

Adding the desktop client's address on Peers Android 0.9.9 fails immediately:

```
create_conversation failed: generic: The capabilities of the add proposal are
insufficient for this group.
```

Two cheaper explanations were checked first and **ruled out by direct inspection**, not assumed:

- **Not the delivery network.** Both clients are Waku **cluster 2**, all 8 shards, same
  `/kym/1/<addr>/proto` content-topic namespace — read from the running instance's own delivery log.
  Android pins `msg.logos.live`, Basecamp uses the `logos.test` preset's `status.im` nodes, but
  that is an entry-node difference on one cluster, not two networks. (Pinning turned out not to be
  expressible in `delivery_module` v0.2.0 either — issue #60.)
- **Not the ciphersuite.** Shipped Android patches `CIPHER_SUITE` back to
  `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`; the libchat rev `chat_module` 0.2.2 rides
  (`5c55c2ee`) is **also** MLS_128 — upstream reverted its own XWING flip. They agree.

What remains is that **Peers' wire format is not upstream's**:

| | upstream libchat | Peers |
|---|---|---|
| Conversation addressing | `hex(group_id)`, in the clear | opaque **`route_tag`** from a per-conversation secret |
| Payload | MLS framing, unsealed | **outer-encrypted** (sealed envelope) |
| Group context | — | **`GROUP_SECRET` (0xFF02)**, random, epoch-stable |
| Leaf capabilities | `[ApplicationId, LastResort, 0xFF01]` | additionally **`0xFF02`** |

MLS requires every group-context extension to be advertised in each member's leaf capabilities, so
an upstream-built client cannot even be **added** to a Peers conversation — which is the error
above, exactly.

## Decision

**Build the desktop client from the same core the phone runs.**

1. **`xAlisher/peers-libchat`** — fork of `logos-messaging/libchat`. Branch `peers` carries the
   Peers delta (graph-hiding Phase 1/1b, the 0xFF02 capability, the MLS_128 hold, #349 creator
   credential, GroupV1 default) as commits on top of an upstream pin; branch `upstream-base` marks
   the pin. The Android FFI wrapper is vendored here so **one tree serves both the Android `.so`
   and the Basecamp core**.
2. **`xAlisher/peers-core`** — fork of `logos-co/logos-chat-module` 0.2.2 with its three libchat
   deps pointed at `peers-libchat`, and `chat_module` renamed to **`peers_core`** throughout
   (module, lidl, plugin, generated trait). The lidl contract and module logic are upstream's.
3. **`peers_ui` depends on `peers_core`**, not `chat_module`.

**The rename is deliberate.** `peers_core` is not a drop-in `chat_module` — it speaks a different
wire format, and sharing a name would invite someone to install it as one.

## Consequences

- **Stated plainly: `peers_core` interoperates with Peers Android and NOT with stock Basecamp
  `chat_ui`/`chat_module`.** That is the intended trade — the goal is one Peers network across
  phone and desktop, not compatibility with a client nobody is trying to reach.
- We now own a fork of an MLS library, which is a real maintenance obligation. It is structured to
  be **rebased forward** (pin newest upstream, keep the Peers patches) rather than to drift — the
  loop is in `docs/FORK-MAINTENANCE.md` and in the `peers-fork-strategy` Basecamp skill so agents
  find it before re-deriving any of this.
- Upstream `chat_module` remains installable alongside, since the module names no longer collide.

## Evidence

- The phone's patched libchat **compiles clean for x86_64-linux** — nothing in the delta was
  Android-only (it needed only the wrapper crate vendored).
- **`chat_module` 0.2.2 compiled against it unmodified**: 0 errors. Only the dependency pointers
  changed; no source changes were required for the API delta between `462a4884` and `5c55c2ee`.
- `peers_ui` builds against `peers_core`, and the desktop⇄desktop gate still passes end to end
  (1:1 round-trip, `scripts/run-exchange.sh`).

## Still open

The end-to-end desktop⇄Android exchange has **not yet been observed**. The capability rejection is
addressed by construction, but that is reasoning, not evidence — it is not proven until a message
crosses and renders on both ends. Tracked in #59.
