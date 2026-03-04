{ config, lib, pkgs, noxa, ... }: with lib; {
  config = {
    services.prometheus.exporters = {
      node = {
        enable = mkDefault false;
        openFirewall = mkDefault true;

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
        openFirewall = mkDefault true;
      };
    };
  };
}
