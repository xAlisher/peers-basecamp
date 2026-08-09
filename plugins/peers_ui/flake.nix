{
  description = "Peers for Basecamp — QML view + C++ backend over the Logos chat_module MLS core";

  # The Logos Attic cache. Without it the whole Rust/Nim core chain
  # (chat_module, delivery_module, liblogosdelivery) builds from source.
  # Build with `--accept-flake-config` so these are honoured.
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    # Follow peers_core's builder pin (0.2.6), so the logos-protocol/logos-qt-sdk
    # chain matches across both. The pin is deliberate — upstream's flake
    # documents that builder master breaks its providers (lidl-gen emits declared
    # records as typed Rust structs the providers aren't written against). ADR 0001.
    logos-module-builder.follows = "peers_core/logos-module-builder";

    # The MLS chat core we ride. NOT upstream chat_module: peers_core is built on
    # peers-libchat, so it speaks the same graph-hiding wire format as Peers
    # Android (opaque route_tag, sealed envelope, GROUP_SECRET 0xFF02 in the group
    # context). An upstream-built core cannot even be ADDED to a Peers
    # conversation — MLS rejects the add proposal for missing capabilities.
    # See ADR 0007 and docs/FORK-MAINTENANCE.md.
    peers_core.url = "github:xAlisher/peers-core";

    # Follow peers_core's delivery pin (v0.2.0) so both build against the same
    # delivery module. A mismatch here leaves the QtRO client hanging on a
    # version mismatch rather than failing loudly.
    logos-delivery-module.follows = "peers_core/logos-delivery-module";
  };

  outputs = inputs@{ logos-module-builder, logos-delivery-module, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = { delivery_module = logos-delivery-module; } // inputs;
    };
}
