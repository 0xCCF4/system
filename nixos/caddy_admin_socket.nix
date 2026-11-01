{ config, lib, ... }:
with lib;
{
  # Caddy's admin API (config changes at runtime, used by `caddy reload`) on a unix socket
  # only caddy itself (and root) can use, instead of 127.0.0.1:2019 open to every local
  # process (e.g. the other services in the jitsi container).
  #
  # Imported by every host (nixosModules.default) as well as the lux containers
  # (hosts/lux/container-common.nix) and microvms (hardware/microvm.nix), which don't get
  # the host modules.
  config = mkIf config.services.caddy.enable {
    services.caddy.globalConfig = mkBefore ''
      admin unix//run/caddy/admin.sock|0600
    '';
    systemd.services.caddy.serviceConfig.RuntimeDirectory = "caddy";
  };
}
