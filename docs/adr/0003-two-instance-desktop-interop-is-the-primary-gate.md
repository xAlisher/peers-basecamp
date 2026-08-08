# ADR 0003 — Two local instances are the primary interop gate

- **Status:** Accepted
- **Date:** 2026-08-09
- **Amends:** the build plan's Phase 0 step 3

## Context

The build plan asserts that same-host two-party testing is impossible:

> `delivery_module` binds a fixed port (≈TCP 60000) globally, so two delivery-using instances on one
> host collide regardless of XDG separation. The physical phone fleet running Peers Android is the
> second peer — this is the primary interop path. A same-host second instance is only for UI-shell
> smoke, not messaging.

Upstream `logos-chat-ui` 0.2.2 documents and automates the opposite, in
`docs/two-instance-exchange.md`:

> Two instances coexist on one host because each picks a random QtRO socket name and each delivery
> node picks its own listening ports; the script gives each its own session dir (`--user-dir`) and
> QML inspector port (`QML_INSPECTOR_PORT`).

and ships `doctests/exchange/run-exchange.mjs`, which drives **two live instances**, reads Alice's
address out of her window, pastes it into Bob's, exchanges messages both ways, and captures a
screenshot of each side. It exits non-zero if the round-trip does not complete — i.e. upstream uses
it as an end-to-end integration check.

The plan's claim is true of an older `delivery_module`; it is not true of the `v0.2.0` pin that
`chat_module` 0.2.2 rides. Combined with ADR 0004 (the phone runs a different core generation, so
phone interop is an open empirical question), making the phone the *primary* gate would make the
whole build depend on the least certain link.

## Decision

1. **Desktop⇄desktop, two local instances with separate `--user-dir`, is the primary interop gate**
   for every messaging feature. It is fast, headless, deterministic, reproducible in CI, and it
   actually tests our code.
2. **Verify the coexistence claim empirically before relying on it** (do not trust the doc):
   run two instances, confirm both reach Online, confirm each gets a distinct address, confirm a
   round-trip. Check `ss -tln` for the port situation and record what is actually observed.
3. **Borrow upstream's harness shape** (`doctests/exchange/`) for our own scripted exchange rather
   than writing a driver from scratch.
4. **Phone interop is a second, additional gate** with an honestly recorded result per ADR 0004 —
   valuable, attempted, but not a precondition for calling desktop features implemented and tested.

## Consequences

- Messaging, groups, media and interaction epics all become testable headlessly and in parallel,
  without the phone fleet in the loop.
- The interop matrix has two axes (desktop⇄desktop, desktop⇄phone) and reports both.
- If the empirical check in step 2 *fails* and the two instances really do collide, this ADR is
  superseded and the phone becomes the primary gate as the plan originally specified. The check is
  therefore run early, and its result is recorded either way.
