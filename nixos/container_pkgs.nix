{ lib
, pkgs
, ...
}:
with lib;
{
  # NixOS containers evaluate their own nixpkgs instance by default. Reusing the host's
  # (recommended by containers.<name>.nixpkgs) saves that instantiation per container and
  # gives the containers the host's overlays and nixpkgs.config. Consequently a container
  # must not set nixpkgs.config itself; set it on the host instead.
  options.containers = mkOption {
    type = types.attrsOf (types.submodule {
      config.config.nixpkgs.pkgs = mkDefault pkgs;
    });
  };
}
