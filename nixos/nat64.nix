{ config
, lib
, pkgs
, ...
}:
with lib;
let
  cfg = config.mine.nat64;
  set = items: "{ ${concatMapStringsSep ", " (item: ''"${item}"'') items} }";

  # Jool runs in its own network namespace, so the translated traffic passes the host's
  # forward chain in both directions like any other traffic:
  #   clients <-> nat64 (IPv6), nat64 <-> wanInterfaces (IPv4, masqueraded)
  # Jool in the host's namespace would translate in prerouting, before the forward chain.
  netns = "nat64";
  # the veth: cfg.interface on the host, jool inside the namespace
  innerInterface = "jool";
  hostLinkLocal = "fe80::1";
  innerLinkLocal = "fe80::2";
  # the IPv4 link, the end of 100.64.0.0/10 (shared address space, unlikely to be in use)
  ipv4Host = "100.127.255.253";
  ipv4 = "100.127.255.254";
  # pool4 must not intersect the namespace's ephemeral ports (Jool refuses), the namespace
  # opens no sockets of its own yet, so they shrink to the top 1024 ports
  ephemeralPorts = { start = 64512; end = 65535; };

  forwardedPorts = protocol: unique (map (forward: forward.port) (filter (forward: forward.protocol == protocol) cfg.portForwards));
  # consecutive ports as ranges, e.g. [ 1 2 3 5 ] -> [ "1-3" "5" ]
  portRanges = ports: map
    (range: if range.start == range.end then toString range.start else "${toString range.start}-${toString range.end}")
    (foldl'
      (ranges: port:
        if ranges != [ ] && (last ranges).end + 1 == port
        then init ranges ++ [ (last ranges // { end = port; }) ]
        else ranges ++ [{ start = port; end = port; }])
      [ ]
      (sort lessThan ports));
  # not globally reachable IPv4 (RFC 6890), the well-known prefix must not reach them
  # (RFC 6052 3.1), e.g. the private networks behind the uplink
  nonGlobalIpv4 = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.0.0.0/24"
    "192.0.2.0/24"
    "192.168.0.0/16"
    "198.18.0.0/15"
    "198.51.100.0/24"
    "203.0.113.0/24"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];
  dnatRule = protocol:
    let
      ports = forwardedPorts protocol;
    in
    optionalString (ports != [ ]) ''
      iifname ${set cfg.wanInterfaces} ${optionalString (cfg.publicIpv4 != null) "ip daddr ${cfg.publicIpv4} "}${toLower protocol} dport { ${concatStringsSep ", " (portRanges ports)} } dnat to ${ipv4}
    '';
in
{
  options.mine.nat64 = with types; {
    enable = mkEnableOption "a NAT64 (Jool) for IPv6 only clients, in its own network namespace";

    prefix = mkOption {
      type = str;
      readOnly = true;
      default = "64:ff9b::/96";
      description = "The NAT64 prefix (RFC 6052 well-known prefix).";
    };

    interface = mkOption {
      type = str;
      readOnly = true;
      default = "nat64";
      description = "The host side of the veth into the NAT64's namespace.";
    };

    clients = mkOption {
      type = listOf str;
      default = [ ];
      example = [ "ve-mailserver" ];
      description = "Interfaces whose traffic may use the NAT64, see `forwardRules`.";
    };

    wanInterfaces = mkOption {
      type = listOf str;
      default = config.mine.wanInterfaces;
      defaultText = literalExpression "config.mine.wanInterfaces";
      example = [ "wan" ];
      description = "The host's interfaces towards the IPv4 internet, the NAT64 is masqueraded to them.";
    };

    publicIpv4 = mkOption {
      type = nullOr str;
      default = null;
      description = "The IPv4 address the port forwards arrive on (any address of `wanInterfaces` if null).";
    };

    portForwards = mkOption {
      default = [ ];
      description = ''
        Inbound IPv4 ports translated to an IPv6 address (static Jool BIB entries). They
        leave the namespace as new IPv6 connections from `64:ff9b::<client>`, the host's
        forward chain decides whether they reach the target.
      '';
      type = listOf (submodule {
        options = {
          protocol = mkOption {
            type = enum [ "TCP" "UDP" ];
            description = "Transport protocol.";
          };
          port = mkOption {
            type = port;
            description = "Port, the same on both sides.";
          };
          address = mkOption {
            type = str;
            description = "The IPv6 address of the target.";
          };
        };
      });
    };

    forwardRules = mkOption {
      type = lines;
      readOnly = true;
      default = optionalString cfg.enable (optionalString (cfg.clients != [ ]) ''
        # NAT64: IPv6 from the clients, only the replies back
        iifname ${set cfg.clients} oifname "${cfg.interface}" accept
        iifname "${cfg.interface}" oifname ${set cfg.clients} ct state established,related accept
      '' + ''
        # NAT64: IPv4 to the internet (only global addresses), only the replies back, and
        # the port forwards (DNAT)
        iifname "${cfg.interface}" ip daddr { ${concatStringsSep ", " nonGlobalIpv4} } drop
        iifname "${cfg.interface}" oifname ${set cfg.wanInterfaces} meta nfproto ipv4 accept
        iifname ${set cfg.wanInterfaces} oifname "${cfg.interface}" ct state established,related accept
        iifname ${set cfg.wanInterfaces} oifname "${cfg.interface}" ct status dnat accept
      '');
      description = ''
        nftables rules for the host's forward chain (with a drop policy). The IPv6
        connections of the port forwards (`iifname "${cfg.interface}"` towards the targets) are
        left to the host's own rules.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.wanInterfaces != [ ];
        message = "mine.nat64.wanInterfaces must be set.";
      }
      {
        assertion = all (forward: forward.port < ephemeralPorts.start) cfg.portForwards;
        message = "mine.nat64.portForwards: ports must be below ${toString ephemeralPorts.start} (the NAT64 namespace's ephemeral ports, outside of pool4).";
      }
      {
        assertion = attrNames config.networking.jool.nat64 == [ "nat64" ] && config.networking.jool.siit == { };
        message = "mine.nat64: no other Jool instances, in the host's namespace they translate before the forward chain filters.";
      }
    ];

    systemd.services.nat64-netns = {
      description = "Network namespace of the NAT64";
      wantedBy = [ "multi-user.target" ];
      before = [ "network.target" ];
      path = [ pkgs.iproute2 pkgs.procps ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # (deleting the namespace deletes the veth)
      script = ''
        ip netns delete ${netns} 2>/dev/null || true
        ip netns add ${netns}
        ip link add ${cfg.interface} type veth peer name ${innerInterface} netns ${netns}
        ip -n ${netns} link set lo up
        ip -n ${netns} link set ${innerInterface} up
        ip -n ${netns} address add ${innerLinkLocal}/64 dev ${innerInterface} nodad
        ip -n ${netns} address add ${ipv4}/30 dev ${innerInterface}
        ip -n ${netns} route add default via ${ipv4Host}
        ip -n ${netns} -6 route add default via ${hostLinkLocal} dev ${innerInterface}
        ip netns exec ${netns} sysctl -w net.ipv4.conf.all.forwarding=1 net.ipv6.conf.all.forwarding=1 \
          net.ipv4.conf.all.send_redirects=0 net.ipv4.conf.${innerInterface}.send_redirects=0 \
          net.ipv6.conf.${innerInterface}.accept_ra=0 \
          "net.ipv4.ip_local_port_range=${toString ephemeralPorts.start} ${toString ephemeralPorts.end}"
      '' + optionalString (!config.systemd.network.enable) ''
        # the host side (by networkd if enabled)
        sysctl -w net.ipv6.conf.${cfg.interface}.addr_gen_mode=1
        ip link set ${cfg.interface} up
        ip address add ${hostLinkLocal}/64 dev ${cfg.interface} nodad
        ip address add ${ipv4Host}/30 dev ${cfg.interface}
        ip -6 route add ${cfg.prefix} via ${innerLinkLocal} dev ${cfg.interface}
      '';
      postStop = "ip netns delete ${netns}";
    };

    # (no DHCP / IPv4LL on the veth)
    networking.dhcpcd.denyInterfaces = [ cfg.interface ];

    systemd.network.networks."20-nat64" = mkIf config.systemd.network.enable {
      matchConfig.Name = cfg.interface;
      networkConfig.LinkLocalAddressing = "no";
      addresses = [
        { Address = "${hostLinkLocal}/64"; }
        { Address = "${ipv4Host}/30"; }
      ];
      routes = [
        {
          Destination = cfg.prefix;
          Gateway = innerLinkLocal;
        }
      ];
    };

    networking.jool = {
      enable = true;
      nat64.nat64 = {
        # the namespace has no services, so all of its ports
        pool4 = map
          (protocol: {
            inherit protocol;
            prefix = "${ipv4}/32";
            "port range" = "1-${toString (ephemeralPorts.start - 1)}";
          }) [ "TCP" "UDP" "ICMP" ];
        bib = map
          (forward: {
            inherit (forward) protocol;
            "ipv4 address" = "${ipv4}#${toString forward.port}";
            "ipv6 address" = "${forward.address}#${toString forward.port}";
          })
          cfg.portForwards;
      };
    };
    systemd.services.jool-nat64-nat64 = {
      bindsTo = [ "nat64-netns.service" ];
      after = [ "nat64-netns.service" ];
      serviceConfig.NetworkNamespacePath = "/run/netns/${netns}";
    };

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = mkDefault true;
      "net.ipv6.conf.all.forwarding" = mkDefault true;
    };

    networking.nftables.enable = true;
    # 64:ff9b::/96 sources are the NAT64's translations: from anywhere else they are
    # spoofed, and the replies would reflect through the NAT64 to the IPv4 address
    networking.nftables.tables.nat64-guard = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority mangle - 1; policy accept;
          iifname != "${cfg.interface}" ip6 saddr { ${cfg.prefix}, 64:ff9b:1::/48 } drop
        }
      '';
    };

    networking.nftables.tables.nat64 = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ${dnatRule "TCP"}
          ${dnatRule "UDP"}
        }

        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          ip saddr ${ipv4} oifname ${set cfg.wanInterfaces} masquerade
        }
      '';
    };
  };
}
