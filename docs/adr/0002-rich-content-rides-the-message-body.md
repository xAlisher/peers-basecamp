# ADR 0002 — Rich content rides marker-prefixed payloads inside the message body

- **Status:** Accepted
- **Date:** 2026-08-09

## Context

Peers requires media (photo/GIF/video/voice note), reactions, reply/quote, forward, pin, custom
avatars and shared contact cards. The core contract we ride (ADR 0001) carries **only text**:

```
type Message { from_self: bool, content: tstr, timestamp_ms: int, ? sender: tstr }
method send_message(convo_id: tstr, content: tstr) -> result
event message_received(convo_id: tstr, content: tstr, timestamp_ms: int, sender: tstr)
```

There is no attachment, reaction, reply-to, or pin primitive anywhere in
`rust-lib/chat_module.lidl`. Nor is there a per-message delivery/read receipt — only a
conversation-wide `delivery_state_changed(delivery_state, detail)` event.

Peers Android already solved this problem the same way, and its markers are the de-facto wire
format that a parity client must speak: `pfp1:` for custom avatars (with `pfp1:clear` as the
un-broadcast), `addr1:` for shared contact cards, and a `store2` marker for stored media
references. Inventing a *different* encoding would guarantee non-interop with the phone even in the
cases where the cores otherwise agree.

## Decision

1. **Encode all rich content as marker-prefixed payloads inside `content`**, reusing Peers Android's
   existing marker grammar verbatim wherever one exists. The extracted ground truth lives in
   `docs/CONTENT-MARKERS.md`; that document, derived from the Android source, is the wire spec.
2. **Never invent a marker where Peers already has one.** Where Peers has no marker for something we
   need (e.g. a pin or a reaction that Android implements purely locally), define a new one in the
   same style, document it in `docs/CONTENT-MARKERS.md`, and mark it clearly as
   **desktop-originated** so the divergence is visible and can be pushed back to Android for parity.
3. **Unrecognised markers degrade gracefully.** A receiver that does not know a marker must render
   something sane rather than raw marker text or an empty bubble. This is a hard requirement, because
   the phone and desktop will inevitably run different marker vocabularies during rollout.
4. **Parse defensively.** Marker payloads arrive from the network and are attacker-controlled. Length
   limits, strict grammar, no unbounded allocation, and no path traversal from any embedded filename.
   Treat every field as hostile.
5. **Keep the codec in one place** — a single encode/decode unit with exhaustive unit tests, including
   malformed, truncated, and oversized inputs. No marker string literals scattered through QML.

## Consequences

- Full Peers feature parity is reachable without any change to the upstream core.
- Message bodies carry structured data, so anything that renders raw `content` (including upstream
  `logos-chat-ui`, and any future client) will show marker text for our rich messages. Acceptable and
  expected; it is the same tradeoff Peers Android already makes.
- The codec is a security boundary and is tested as one.
- Per-message delivery/read state has no transport. It is derived locally from
  `delivery_state_changed` plus send success, and is presented honestly (conversation-level
  connectivity, not a per-message read receipt we cannot actually observe).
