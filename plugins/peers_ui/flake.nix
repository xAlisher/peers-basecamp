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
    # Follow chat_module's own builder pin (0.2.6), so the
    # logos-protocol/logos-qt-sdk chain matches across both. chat_module's flake
    # documents that builder master breaks its providers (lidl-gen emits declared
    # records as typed Rust structs its providers aren't written against), so the
    # pin is deliberate — see ADR 0001.
    logos-module-builder.follows = "chat_module/logos-module-builder";

    # The MLS chat core we ride (ADR 0001). Pinned to the v0.2.2 release tag,
    # matching what upstream logos-chat-ui 0.2.2 is released against, so the
    # module built here is the release the package manager resolves.
    chat_module.url = "github:logos-co/logos-chat-module/v0.2.2";

    # Follow chat_module's delivery pin (v0.2.0) so both build against the same
    # delivery module. A mismatch here leaves the QtRO client hanging on a
    # version mismatch rather than failing loudly.
    logos-delivery-module.follows = "chat_module/logos-delivery-module";
  };

  outputs = inputs@{ logos-module-builder, logos-delivery-module, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = { delivery_module = logos-delivery-module; } // inputs;
    };
}
