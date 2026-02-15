{ config, lib, pkgs, noxa, ... }: with lib; {
  config = {
    services.prometheus.exporters = {
      node = {
        enable = mkDefault true;
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
        enable = mkDefault true;
        openFirewall = mkDefault true;
      };
    };
  };
}
