{ lib, self, config, luxPublicNetwork6, ... }: with lib; {
  imports = [
    ../../hardware/netcup.nix
    ./net.nix
    ./mailserver.nix
    ./caddy.nix
    ./radicale.nix
    ./powerdns.nix
  ] ++ self.lib.optionalsIfExist [
    ../../external/private/hosts/lux.nix
  ];

  config = {
    # General settings
    networking.hostName = "lux";
    mine.presets.primary = "server";
    networking.hostId = "9a5839bd";

    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;
    boot.kernelModules = [ "veth" "kvm" ];

    mine.admins = [ "mx" ];

    # SSH
    services.openssh = {
      enable = true;
      ports = [ 5555 22 ];
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        GatewayPorts = "yes";
      };
    };

    mine.persistence.enable = true;

    mine.autoUpdate.enable = true;
    mine.autoUpdate.schedule = "daily";
    mine.autoUpdate.inputs = [ "nixpkgs" "nixpkgs-stable" ];

    # Remote unlock luks via ssh+tor
    mine.boot.remoteUnlock = true;
    boot.initrd.network.ssh.port = 4444;
    mine.boot.tor.enable = true;
    mine.boot.tor.ports = [
      {
        port = 22;
        bindPort = config.boot.initrd.network.ssh.port;
      }
    ];

    networking.jool.enable = true;
    networking.jool.nat64.default = {
      bib = [
        { protocol = "TCP"; "ipv4 address" = "${config.mine.info.public.ipv4}#53"; "ipv6 address" = "${config.containers.powerdns.localAddress6}#53"; }
        { protocol = "UDP"; "ipv4 address" = "${config.mine.info.public.ipv4}#53"; "ipv6 address" = "${config.containers.powerdns.localAddress6}#53"; }
      ];
      pool4 = [
        { protocol = "TCP"; prefix = "${config.mine.info.public.ipv4}/32"; "port range" = "53"; }
        { protocol = "UDP"; prefix = "${config.mine.info.public.ipv4}/32"; "port range" = "53"; }
      ];
    };

    networking.nftables.enable = true;

    networking.nftables.tables.lux-public-allowlist = {
      family = "ip6";
      content = ''
        chain forward {
          type filter hook forward priority filter; policy accept;

          iifname != "lan" return
          ip6 daddr != ${luxPublicNetwork6} return

          # ip6 daddr ${config.containers.mailserver.localAddress6} tcp dport { 25, 465, 993, 80 } accept
          ip6 daddr ${config.containers.caddy.localAddress6} tcp dport { 80, 443 } accept
          ip6 daddr ${config.containers.caddy.localAddress6} udp dport 443 accept
          ip6 daddr ${config.containers.powerdns.localAddress6} tcp dport 53 accept
          ip6 daddr ${config.containers.powerdns.localAddress6} udp dport 53 accept

          # Allow established/related traffic
          # ct state established,related accept
          # ct state invalid drop

          # Essential ICMPv6
          icmpv6 type packet-too-big accept
          icmpv6 type { destination-unreachable, time-exceeded, parameter-problem } accept

          # Echo (optional but useful)
          icmpv6 type { echo-request, echo-reply } accept

          drop
        }
      '';
    };
  };
}
