# Fork maintenance — pin newest upstream, keep the Peers patches

Peers runs a forked chat core (ADR 0007). Two repos, both built to be **rebased forward** rather
than left to drift:

| repo | branch | contents |
|---|---|---|
| [`peers-libchat`](https://github.com/xAlisher/peers-libchat) | `peers` | the Peers delta as commits on an upstream pin |
| | `upstream-base` | marks which upstream rev the delta sits on |
| [`peers-core`](https://github.com/xAlisher/peers-core) | `main` | `logos-chat-module` built on `peers-libchat`, renamed `peers_core` |

## Adopting a newer upstream

```bash
# 1. rebase the Peers delta onto the new upstream rev
git clone https://github.com/xAlisher/peers-libchat && cd peers-libchat
git remote add upstream https://github.com/logos-messaging/libchat
git fetch upstream
git rebase --onto <new-upstream-rev> upstream-base peers
git branch -f upstream-base <new-upstream-rev>

# 2. prove BOTH targets still build — a rebase that compiles for one proves nothing for the other
cargo check -p logos-generic-chat                     # x86_64, the Basecamp side
#   + the Android .so via logos-libchat-mls-android/scripts/build-android-arm64.sh

# 3. peers-core: bump the three `rev = …` pins in rust-lib/Cargo.toml, then
nix run .#generate --accept-flake-config
cd rust-lib && cargo generate-lockfile          # REQUIRED, or the nix build fails offline
nix build .#packages.x86_64-linux.default --accept-flake-config

# 4. peers_ui
nix flake lock --update-input peers_core
nix build .#packages.x86_64-linux.lgx-portable --accept-flake-config
./scripts/check-all.sh && ./scripts/run-all-scenarios.sh
```

## Traps that already cost time

- **`nix flake update <input>` may silently not advance the lock.** Verify:
  `jq -r '.nodes.peers_core.locked.rev' flake.lock` — and prefer
  `nix flake lock --update-input peers_core`. A stale lock means you test the *old* core while
  believing you tested the new one.
- **Regenerate `Cargo.lock` after any dependency change**, or the nix build fails offline with
  `failed to load source for dependency` / `can't checkout … you are in the offline mode`.
- **Renaming the lidl module renames the generated trait too** (`ChatModule` → `PeersCoreModule`).
  A case-insensitive rename of the module name alone leaves `impl ChatModule` behind.
- **Read the fork patch, not just the upstream const.** The XWING question looked like a mismatch
  from the constants alone; the fork patches the value back, so both sides actually agree.

## What must stay true

The Peers delta exists to keep the desktop and the phone on **one wire format**. Before landing any
change to it, ask whether the phone still parses what the desktop emits — the failure mode is not a
compile error, it is a client that connects, forms no conversation, and reports
`the capabilities of the add proposal are insufficient for this group`.

## Delivery entry node

`peers_core` takes `ChatConfig.delivery_node` (a multiaddr) and pins it, so the desktop enters the
cluster through the same node as Peers Android (`msg.logos.live`). `peers_ui` sets it by default.

It works by switching to delivery's **flat** config shape — bare `WakuNodeConf` keys, no
`mode`/`messagingOverrides` wrappers. The layered shape accepts no entry-node key at all, and mixing
the two is rejected. `preset` is valid flat too, so the network is kept.

**Cost:** the flat parser uses FIXED listening ports, so two *pinned* instances cannot share a host.
Anything running two locally (`scripts/run-exchange.sh`) sets `PEERS_DELIVERY_NODE=""` to get the
layered shape back.
