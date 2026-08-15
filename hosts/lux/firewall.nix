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
    (lib.mapAttrsToList (_: route: route.upstream) config.mine.services.caddyProxy.routes)
    ++ (lib.optional
      (
        config.mine.services.caddyProxy.dns01.apiUrl != null
      )
      config.mine.services.caddyProxy.dns01.apiUrl);

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
in
{
  # NOTE: this only defines the `forward` hook for container/proxy traffic.
  # Host-exposed services (SSH, the WireGuard listener) are filtered
  # separately by the standard networking.firewall module, which
  # handles the `input` hook.
  config = {
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
      ];
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
      ];
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

          # caddy -> backend containers (reverse-proxy upstreams, DNS-01 API)
          ${caddyContainersForwardRules}

          drop
        }

        chain fw-accept-dos {
          counter
          meter outside-traffic { ip6 saddr limit rate 10/second } accept
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

          # ip6 daddr ${config.containers.mailserver.localAddress6} tcp dport { 25, 465, 993, 80 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} tcp dport { 80, 443 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} udp dport 443 jump fw-accept-dos
          ip6 daddr ${config.containers.powerdns.localAddress6} tcp dport 53 jump fw-accept-dos
          ip6 daddr ${config.containers.powerdns.localAddress6} udp dport 53 jump fw-accept-dos

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
