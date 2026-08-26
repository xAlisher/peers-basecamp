# ADR 0009 — Tokenless cross-platform hosted media

- **Status:** Accepted for incremental implementation (2026-08-26)
- **Canonical architecture:** [Peers Android ADR 0004](https://github.com/xAlisher/peers/blob/feat/tokenless-media-grants/docs/adr/0004-tokenless-cross-platform-media.md)
- **Related:** Android epic [#532](https://github.com/xAlisher/peers/issues/532), gateway [#533](https://github.com/xAlisher/peers/issues/533), desktop [#65](https://github.com/xAlisher/peers-basecamp/issues/65)

## Decision

Desktop keeps the Android-compatible `store2:` marker, Padmé padding, and per-object AES-256-GCM encryption. A reusable `PEERS_STORAGE_TOKEN` is a temporary legacy migration input, never an LGX/install secret.

The common gateway evolves to:

1. capability-only `GET /data/<cid>?cap=<cap>`;
2. anonymous, short-lived, one-use, byte-bounded upload grants;
3. existing `<cid>:<cap>` upload responses.

This branch starts the first safe slice: when a valid per-blob capability is present, Desktop performs the fetch without requiring or transmitting a shared bearer. Capless legacy markers still require legacy authorization and otherwise fail closed.

## Desktop privacy boundary

Content confidentiality matches Android because storage sees only padded ciphertext: the AES key is distributed through MLS and never sent to storage. The read capability is also distributed through MLS but is necessarily presented to the gateway when fetching ciphertext. Network-metadata privacy does not yet match Android Private mode: absent a desktop Tor/Mix route, the gateway sees the desktop IP, timing, padded size, CID, capability, and request linkage. That gap must remain explicit; token removal alone does not make media anonymous.

Group limitations are protocol-level and shared by both clients: members who already obtained a key/cap cannot be made to forget it, remote deletion is best effort, and the same object must not be reused across conversations because CID reuse creates correlation.

## Upstream storage

Basecamp's upstream `storage_module` can upload/download CID-addressed data without giving this UI plugin a hosted bearer. It is a promising future transport, but adopting it only on desktop would break Android interoperability, and direct P2P storage changes IP/access-pattern exposure. It should be adopted cross-platform after Android packaging and private Mix routing are proven.
