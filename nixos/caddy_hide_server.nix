{ lib, ... }:
with lib;
{
  # Strip the `Server` response header (Caddy's own and any upstream's) on
  # every Caddy virtual host. Kept as its own `header` directive so only it
  # is deferred, not other routes' header blocks (see hosts/lux/vota.nix).
  #
  # Imported by every host (nixosModules.default) as well as the lux
  # containers (hosts/lux/container-common.nix) and microvms
  # (hardware/microvm.nix), which don't get the host modules.
  options.services.caddy.virtualHosts = mkOption {
    type = types.attrsOf (types.submodule {
      config.extraConfig = mkAfter ''
        header -Server
      '';
    });
  };
}
