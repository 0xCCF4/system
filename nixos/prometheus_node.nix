{ config
, lib
, pkgs
, noxa
, ...
}:
with lib;
let
  exporters = config.services.prometheus.exporters;
  # the exporters' metrics (interfaces, mounts, versions, pools) only for the fleet
  ulaOnly = exporter: mkIf exporter.enable ''
    ip6 saddr ${noxa.ula.prefix} tcp dport ${toString exporter.port} accept
  '';
in
{
  config = {
    services.prometheus.exporters = {
      node = {
        enable = mkDefault false;
        openFirewall = mkDefault false;

        enabledCollectors = [
          "ethtool"
          "softirqs"
          "systemd"
          "tcpstat"
          "wifi"
        ];
      };

      zfs = {
        enable = mkDefault false;
        openFirewall = mkDefault false;
      };
    };

    networking.firewall.extraInputRules = mkMerge [ (ulaOnly exporters.node) (ulaOnly exporters.zfs) ];
  };
}
