{ config
, lib
, options
, ...
}:
with lib;
{
  # Every microVM is its own NixOS evaluation; the NixOS manual (options.json over all
  # option declarations) is one of the most expensive parts of it and nobody reads it there.
  config = optionalAttrs (options ? microvm) {
    microvm.vms = genAttrs config.mine.microvm.names (_: {
      config.documentation.nixos.enable = mkDefault false;
    });
  };
}
