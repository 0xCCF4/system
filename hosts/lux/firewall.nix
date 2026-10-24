{ config
, lib
, luxPublicNetwork6
, ...
}:
let
  # Wireguard networks any enabled caddyProxy route is exposed on; the container
  # is always named "caddy" (see nixos/service_caddy_proxy.nix), so its host-side
  # veth is always "ve-caddy".
  caddyWireguardNetworks = lib.unique (
    lib.concatMap
      (
        route: lib.attrNames (lib.filterAttrs (_: netCfg: netCfg.enable) route.wireguardNetworks)
      )
      (lib.attrValues config.mine.services.caddyProxy.routes)
  );

  caddyWireguardForwardRules = lib.concatStringsSep "\n  " (
    lib.concatMap
      (network: [
        ''iifname == "${network}" oifname == "ve-caddy" accept''
      ])
      caddyWireguardNetworks
  );

  # Caddy <-> upstream URLs of containers
  caddyOutboundTargets =
    lib.mapAttrsToList (_: route: route.upstream) config.mine.services.caddyProxy.routes;

  # Caddy <-> container interfaces
  caddyContainerTargets = lib.unique (
    lib.filter (name: name != null) (
      map
        (
          str:
          lib.findFirst (name: lib.hasInfix config.containers.${name}.localAddress6 str) null (
            lib.attrNames config.containers
          )
        )
        caddyOutboundTargets
    )
  );

  caddyContainersForwardRules = lib.concatStringsSep "\n  " (
    map (name: ''iifname == "ve-caddy" oifname == "ve-${name}" accept'') caddyContainerTargets
  );

  coturnRelayPorts = lib.range 49160 50159;

  # Only MX traffic is public, submission/IMAP (465/993) are cloud-admin only
  # (relayed on the host, see hosts/lux/mailserver.nix).
  mailserverPorts = [ 25 ];
  mailserverBib = map
    (port: {
      protocol = "TCP";
      "ipv4 address" = "${config.mine.info.public.ipv4}#${toString port}";
      "ipv6 address" = "${config.containers.mailserver.localAddress6}#${toString port}";
    })
    mailserverPorts;

  joolEphemeralPorts = "61001-65535";
  coturnRelayBib = map
    (port: {
      protocol = "UDP";
      "ipv4 address" = "${config.mine.info.public.ipv4}#${toString port}";
      "ipv6 address" = "${config.containers.mtx-co-v4.localAddress6}#${toString port}";
    })
    coturnRelayPorts;
in
{
  # NOTE: this only defines the `forward` hook for container/proxy traffic.
  # Host-exposed services (SSH, the WireGuard listener) are filtered
  # separately by the standard networking.firewall module, which
  # handles the `input` chain.
  config = {
    # Shrink the kernel's ephemeral port range so it no longer overlaps the
    # coturn UDP relay range
    boot.kernel.sysctl."net.ipv4.ip_local_port_range" =
      "32768 ${toString (lib.head coturnRelayPorts - 1)}";

    # Answer ND IPv6 packets
    services.ndppd.enable = true;
    services.ndppd.proxies.wan.rules = lib.genAttrs
      (map (name: "${config.containers.${name}.localAddress6}/128") (lib.attrNames config.containers))
      (_: { method = "static"; });

    # Containers resolve DNS through the host
    services.resolved.settings.Resolve.DNSStubListenerExtra =
      map (name: config.containers.${name}.hostAddress6) (lib.attrNames config.containers);

    networking.firewall.interfaces = lib.genAttrs
      (map (name: "ve-${name}") (lib.attrNames config.containers))
      (_: {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 53 ];
      });

    networking.jool.enable = true;
    networking.jool.nat64.default = {
      bib = [
        {
          protocol = "TCP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#53";
          "ipv6 address" = "${config.containers.powerdns.localAddress6}#53";
        }
        {
          protocol = "UDP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#53";
          "ipv6 address" = "${config.containers.powerdns.localAddress6}#53";
        }
        {
          protocol = "TCP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#80";
          "ipv6 address" = "${config.containers.caddy.localAddress6}#80";
        }
        {
          protocol = "TCP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#443";
          "ipv6 address" = "${config.containers.caddy.localAddress6}#443";
        }
        {
          protocol = "UDP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#443";
          "ipv6 address" = "${config.containers.caddy.localAddress6}#443";
        }
        {
          protocol = "TCP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#3478";
          "ipv6 address" = "${config.containers.mtx-co-v4.localAddress6}#3478";
        }
        {
          protocol = "UDP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#3478";
          "ipv6 address" = "${config.containers.mtx-co-v4.localAddress6}#3478";
        }
        {
          protocol = "UDP";
          "ipv4 address" = "${config.mine.info.public.ipv4}#10000";
          "ipv6 address" = "${config.containers.jitsi.localAddress6}#10000";
        }
      ] ++ coturnRelayBib ++ mailserverBib;
      pool4 = [
        {
          protocol = "TCP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "53";
        }
        {
          protocol = "UDP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "53";
        }
        {
          protocol = "TCP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "80";
        }
        {
          protocol = "TCP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "443";
        }
        {
          protocol = "UDP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "443";
        }
        {
          protocol = "TCP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "3478";
        }
        {
          protocol = "UDP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "3478";
        }
        {
          protocol = "UDP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "49160-50159";
        }
        {
          protocol = "UDP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = "10000";
        }
      ] ++ map
        (port: {
          protocol = "TCP";
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = toString port;
        })
        mailserverPorts
      ++ map
        (protocol: {
          inherit protocol;
          prefix = "${config.mine.info.public.ipv4}/32";
          "port range" = joolEphemeralPorts;
        })
        [ "TCP" "UDP" ];
    };

    networking.nftables.enable = true;

    networking.nftables.tables.lux-forward-traffic = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority filter; policy drop;

          # drop invalid, and forward established connections
          ct state invalid drop
          ct state established,related accept

          # Traffic coming from the public internet -> filtered per-service below
          iifname == "wan" jump fw-outside-traffic

          # wireguard -> caddy
          ${caddyWireguardForwardRules}

          # caddy -> backend containers (reverse-proxy upstreams)
          ${caddyContainersForwardRules}

          # caddy -> internet (ACME, its own dnscrypt-proxy upstream, etc.)
          iifname == "ve-caddy" oifname == "wan" accept

          # caddy -> mailserver (HTTP-01 challenges arriving over IPv4)
          iifname == "ve-caddy" oifname == "ve-mailserver" tcp dport 80 accept

          # mailserver -> internet (outbound SMTP, unbound recursion, ACME)
          iifname == "ve-mailserver" oifname == "wan" accept

          # powerdns -> secondaries (NOTIFY), including the NAT64 ones
          iifname == "ve-powerdns" oifname == "wan" ip6 daddr { ${lib.concatStringsSep ", " config.mine.services.powerdns.secondaries} } udp dport 53 accept

          # vaultwarden -> mailserver (submission)
          iifname == "ve-vaultwarden" oifname == "ve-mailserver" tcp dport 465 accept

          # allow wireguard network communication, todo: allow all wireguard interfaces to talk to eachother
          iifname == "cloud-admin" oifname == "cloud-admin" accept

          drop
        }

        set outside-traffic {
          type ipv6_addr
          size 65535
          flags dynamic, timeout
          timeout 1m
        }

        set outside-traffic-dns {
          type ipv6_addr
          size 65535
          flags dynamic, timeout
          timeout 1m
        }

        chain fw-accept-dos {
          counter # /64 prefix
          update @outside-traffic { ip6 saddr and ffff:ffff:ffff:ffff:: limit rate 10/second burst 50 packets } accept
        }

        chain fw-accept-dos-dns {
          counter # /64 prefix
          update @outside-traffic-dns { ip6 saddr and ffff:ffff:ffff:ffff:: limit rate 10/second burst 200 packets } accept
        }

        chain fw-accept {
          counter
          accept
        }

        chain fw-drop {
          drop
        }

        # traffic from the public internet -> internal containers
        chain fw-outside-traffic {
          # traffic not bound for us, sus...
          ip6 daddr != ${luxPublicNetwork6} jump fw-drop

          # only ipv6 is expected inbound here; NAT64-translated ipv4 exits via jool on a different path
          meta nfproto ipv4 jump fw-drop

          ip6 daddr ${config.containers.mailserver.localAddress6} tcp dport { 25, 80 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} tcp dport { 80, 443 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} udp dport 443 jump fw-accept-dos
          ip6 daddr ${config.containers.powerdns.localAddress6} tcp dport 53 jump fw-accept-dos-dns
          ip6 daddr ${config.containers.powerdns.localAddress6} udp dport 53 jump fw-accept-dos-dns
          # mtx-co-v4 itself is NAT64-only
          ip6 daddr ${config.containers.mtx-co-v6.localAddress6} tcp dport 3478 jump fw-accept-dos
          ip6 daddr ${config.containers.mtx-co-v6.localAddress6} udp dport 3478 jump fw-accept-dos
          ip6 daddr ${config.containers.mtx-co-v6.localAddress6} udp dport 49160-50159 jump fw-accept-dos
          ip6 daddr ${config.containers.jitsi.localAddress6} udp dport 10000 jump fw-accept

          # Essential ICMPv6
          icmpv6 type packet-too-big accept
          icmpv6 type { destination-unreachable, time-exceeded, parameter-problem } accept

          # Echo
          # icmpv6 type { echo-request, echo-reply } accept

          jump fw-drop
        }
      '';
    };
  };
}
