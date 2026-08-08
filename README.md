# Peers for Basecamp

A [Logos Basecamp](https://github.com/logos-co) desktop module that brings **Peers** — the
end-to-end-encrypted messenger shipped as an Android app at
[`logos-chat-android`](https://github.com/xAlisher/peers) — to the desktop as a native QML/C++
universal module, in a Status-desktop-style three-panel layout.

> **Status: in active autonomous development.** Nothing here is released. See
> [`MORNING-REPORT.md`](MORNING-REPORT.md) for the current build state, what is verified, and what is
> blocked.

## What it is

Peers for Basecamp rides the upstream Logos **`chat_module`** MLS chat core (v0.2.2) — the same
`libchat` lineage the Android app embeds — and renders it in the Peers design language: the orange
`#FF5000` accent, the flush 5×5 `HexAvatar` identicon, Lucide glyph iconography, and Peers' message,
roster and composer styling.

**In scope** — conversations, 1:1 and group chat, contacts (address paste / QR / shared card), media
(photo, GIF, video, voice note), reactions, reply / forward / pin / copy, avatars, settings, PIN
app-lock with a duress/wipe PIN, and reading a Peers-mobile encrypted backup.

**Out of scope, deliberately** — embedded Tor and "private mode", BLE/Bluetooth transport, and
MeshCore/Nearby mesh. Those are Android-only for now and their settings screens are omitted entirely.

## Architecture

```
peers-basecamp/
└─ plugins/peers_ui/          type: ui_qml, interface: universal
   ├─ flake.nix               mkLogosQmlModule; inputs: chat_module 0.2.2, delivery_module v0.2.0
   ├─ metadata.json           dependencies: [chat_module, delivery_module]
   ├─ src/peers_ui.rep        QtRO contract (PROP / SLOT / SIGNAL)
   ├─ src/*.{h,cpp}           C++ backend: chat_module client + content-marker codec + backup reader
   └─ qml/                    Peers-parity QML component library + three-panel shell
```

The core is consumed through the builder-generated typed client from
[`chat_module.lidl`](https://github.com/logos-co/logos-chat-module/blob/master/rust-lib/chat_module.lidl).
The contract carries **text only**, so Peers' rich content (media, reactions, replies, pins, avatars,
contact cards) is encoded as marker-prefixed payloads inside the message body, reusing the Android
app's existing marker grammar — see [ADR 0002](docs/adr/0002-rich-content-rides-the-message-body.md)
and [`docs/CONTENT-MARKERS.md`](docs/CONTENT-MARKERS.md).

## Key decisions

Architecture decisions, including the ones that revise the original build plan, are in
[`docs/adr/`](docs/adr/):

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-ride-upstream-chat-module-0-2-2.md) | Ride upstream `chat_module` **0.2.2** (Rust/lidl), not the stale C-FFI `liblogoschat` shape; model the module on `logos-chat-ui` 0.2.2 |
| [0002](docs/adr/0002-rich-content-rides-the-message-body.md) | Rich content rides marker-prefixed payloads inside the message body |
| [0003](docs/adr/0003-two-instance-desktop-interop-is-the-primary-gate.md) | Two local instances (separate `--user-dir`) are the primary interop gate |
| [0004](docs/adr/0004-identity-import-and-phone-interop.md) | Identity import and Android interop are **upstream-constrained**; scope adjusted honestly |
| [0005](docs/adr/0005-three-panel-layout-and-peers-skin.md) | Three-panel layout; Peers parity beats the Logos design system in every conflict |

## Documentation

- [`docs/DESIGN-SPEC.md`](docs/DESIGN-SPEC.md) — the authoritative Peers visual target (exact colors,
  type scale, spacing, radii, component styles), extracted from the Android source.
- [`docs/HEXAVATAR.md`](docs/HEXAVATAR.md) — the identicon algorithm, specified for a pixel-identical port.
- [`docs/CONTENT-MARKERS.md`](docs/CONTENT-MARKERS.md) — the message-body wire format for rich content.
- [`docs/BACKUP-FORMAT.md`](docs/BACKUP-FORMAT.md) — the `.peersenc` envelope, KDF, AEAD and payload schema.
- [`docs/PARITY.md`](docs/PARITY.md) — the living Android ↔ Basecamp feature parity matrix.
- [`docs/INTEROP.md`](docs/INTEROP.md) — the interop matrix and its screenshot evidence.
- [`PROJECT_KNOWLEDGE.md`](PROJECT_KNOWLEDGE.md) — how to build, run, test and debug this module.

## Building

```bash
cd plugins/peers_ui
nix build .#packages.x86_64-linux.lgx-portable --accept-flake-config
```

`--accept-flake-config` matters: it enables the Logos binary cache
(`cache.nix.logos.co/public`), without which the Rust core chain builds from source.

See [`PROJECT_KNOWLEDGE.md`](PROJECT_KNOWLEDGE.md) for the dev loop, headless test harness, isolated
Basecamp install, and the screenshot verification loop.

## Relationship to Peers Android

The Android app is the design and feature source of truth. `docs/PARITY.md` tracks drift between the
two clients and is checked by `scripts/check-parity.sh`, so divergence surfaces as a failure rather
than as quiet rot.

## Licence

Dual-licensed under [Apache 2.0](LICENSE-APACHE) and [MIT](LICENSE-MIT), matching the Logos modules.
