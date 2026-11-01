{ config
, lib
, noxa
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
        ''iifname == "${network}" oifname == "ve-caddy" meta nfproto ipv6 accept''
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
  # concurrent TURN allocations per source prefix (a call needs one or two per client)
  turnFlowsPerSource = 16;

  # DENIC eG's own network (AS8763, announced prefixes per RIPEstat, 2026-10-31); IPv4
  # arrives through the NAT64 (64:ff9b::<IPv4>): 81.91.160.0/20 = 64:ff9b::515b:a000/116
  denicNetworks = [
    "2a02:568::/32"
    "${lib.removeSuffix "/96" config.mine.nat64.prefix}515b:a000/116"
  ];

  # Only MX traffic is public, submission/IMAP (465/993) are cloud-admin only
  # (via the container's ULA, see hosts/lux/mailserver.nix).
  mailserverPorts = [ 25 ];

  # public IPv4 ports, translated by the NAT64 to the containers (nixos/nat64.nix)
  forward = protocol: container: port: {
    inherit protocol port;
    address = config.containers.${container}.localAddress6;
  };
  portForwards = [
    (forward "TCP" "powerdns" 53)
    (forward "UDP" "powerdns" 53)
    (forward "TCP" "caddy" 80)
    (forward "TCP" "caddy" 443)
    (forward "UDP" "caddy" 443)
    (forward "TCP" "mtx-co-v4" 3478)
    (forward "UDP" "mtx-co-v4" 3478)
    (forward "UDP" "jitsi" 10000)
  ]
  ++ map (forward "UDP" "mtx-co-v4") coturnRelayPorts
  ++ map (forward "TCP" "mailserver") mailserverPorts;

  # each container sends only from its own addresses, IPv6 only
  containerSourceRules = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (name: container: ''
      iifname "ve-${name}" meta nfproto ipv4 drop
      iifname "ve-${name}" ip6 saddr != { ${lib.concatStringsSep ", " ([ container.localAddress6 ] ++ lib.optional (config.mine.guestUla.addresses ? ${name}) config.mine.guestUla.addresses.${name} ++ [ "fe80::/10" ])} } drop
    '')
    config.containers);
in
{
  # NOTE: this only defines the `forward` hook for container/proxy traffic.
  # Host-exposed services (SSH, the WireGuard listener) are filtered
  # separately by the standard networking.firewall module, which
  # handles the `input` chain.
  options.mine.firewall.dnsRateLimitExemptDenic = lib.mkEnableOption ''
    exempting DENIC's network (the .de registry's name server checks, predelegation/NAST,
    which come in bursts) from the rate limit of the public PowerDNS'';

  config = {
    # Shrink the kernel's ephemeral port range so it no longer overlaps the
    # coturn UDP relay range (forwarded to the NAT64)
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

    # IPv4 reaches the containers only through the NAT64, in its own network namespace, so
    # the translated traffic passes the forward chain below (as IPv6 from 64:ff9b::/96)
    mine.nat64 = {
      enable = true;
      # mailserver resolves to 64:ff9b::/96 (its own DNS64), coturn and the videobridge
      # send to their IPv4 peers first (ICE, relayed data); the others reach IPv4
      # through explicit rules below, if at all
      clients = [ "ve-mailserver" "ve-mtx-co-v4" "ve-jitsi" ];
      publicIpv4 = config.mine.info.public.ipv4;
      inherit portForwards;
    };

    # wan is the internet itself: private sources and lux's own prefix are spoofed there
    mine.martianGuard = {
      publicUplink = true;
      extraSources = [ luxPublicNetwork6 ];
    };

    networking.nftables.tables.lux-containers = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority mangle; policy accept;
          ${containerSourceRules}
        }
      '';
    };

    networking.nftables.enable = true;

    # SSH (and mosh) only over WireGuard from the fleet ULA prefix (lux.vlan), nothing
    # public; the initrd's SSH for the LUKS unlock (port 4444, before this firewall, and
    # Tor) stays reachable
    services.openssh.openFirewall = false;
    programs.mosh.openFirewall = false;
    # not just any packet on cloud-admin: the rules above also require a ULA source
    mine.ssh.trustedInterfaces = lib.mkForce [ ];
    networking.firewall.extraInputRules = ''
      iifname "cloud-admin" ip6 saddr ${noxa.ula.prefix} tcp dport { ${lib.concatMapStringsSep ", " toString config.services.openssh.ports} } accept
      iifname "cloud-admin" ip6 saddr ${noxa.ula.prefix} udp dport 60000-61000 accept
    '';

    networking.nftables.tables.lux-forward-traffic = {
      family = "inet";
      content = ''
        chain forward {
          type filter hook forward priority filter; policy drop;

          # drop invalid, and forward established connections
          ct state invalid drop
          ct state established,related accept

          # the NAT64 (nixos/nat64.nix), before the IPv4 drop of fw-outside-traffic
          ${config.mine.nat64.forwardRules}

          # Traffic coming from the public internet (IPv4 translated by the NAT64) ->
          # filtered per-service below
          iifname { "wan", "${config.mine.nat64.interface}" } jump fw-outside-traffic

          # wireguard -> caddy, containers are only reachable over IPv6 (their ULA)
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
          iifname == "ve-powerdns" oifname { "wan", "${config.mine.nat64.interface}" } ip6 daddr { ${lib.concatStringsSep ", " config.mine.services.powerdns.secondaries} } udp dport 53 accept

          # wireguard -> mailserver (submission/IMAP via its ULA)
          iifname == "cloud-admin" oifname == "ve-mailserver" ip6 daddr ${config.mine.guestUla.addresses.mailserver} tcp dport { 465, 993 } accept

          # synapse -> internet (push gateways, URL previews)
          iifname == "ve-mtx-syn" oifname == "wan" tcp dport { 80, 443 } accept

          # vaultwarden -> mailserver (submission)
          iifname == "ve-vaultwarden" oifname == "ve-mailserver" tcp dport 465 accept

          ${lib.optionalString (with config.mine.services.jitsi; restrictRoomCreation && matrixAuth.enable) ''
            # jitsi (prosody) -> synapse: checks Element's OpenID tokens (who may open rooms)
            iifname == "ve-jitsi" oifname == "ve-mtx-syn" ip6 daddr ${config.containers.mtx-syn.localAddress6} tcp dport 8008 accept
          ''}
          # allow wireguard network communication (IPv4 and IPv6), todo: allow all wireguard interfaces to talk to eachother
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

        # per /56 (an attacker's /48 is only 256 entries, it can't fill the set and lock out
        # new sources), IPv4 (NAT64, 64:ff9b::<IPv4>) per /24
        chain fw-accept-dos {
          counter
          ip6 saddr ${config.mine.nat64.prefix} update @outside-traffic { ip6 saddr and ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00 limit rate 10/second burst 50 packets } accept
          ip6 saddr ${config.mine.nat64.prefix} return
          update @outside-traffic { ip6 saddr and ffff:ffff:ffff:ff00:: limit rate 10/second burst 50 packets } accept
        }

        chain fw-accept-dos-dns {
          counter
          ${lib.optionalString config.mine.firewall.dnsRateLimitExemptDenic ''
            # DENIC's (.de registry) name server checks (predelegation/NAST) come in bursts
            ip6 saddr { ${lib.concatStringsSep ", " denicNetworks} } accept
          ''}
          ip6 saddr ${config.mine.nat64.prefix} update @outside-traffic-dns { ip6 saddr and ffff:ffff:ffff:ffff:ffff:ffff:ffff:ff00 limit rate 10/second burst 200 packets } accept
          ip6 saddr ${config.mine.nat64.prefix} return
          update @outside-traffic-dns { ip6 saddr and ffff:ffff:ffff:ff00:: limit rate 10/second burst 200 packets } accept
        }

        chain fw-accept {
          counter
          accept
        }

        chain fw-drop {
          drop
        }

        # concurrent flows (conntrack entries) per /56, IPv4 (NAT64) per address: CGNAT
        # users of one /24 would otherwise block each other
        set turn-sources {
          type ipv6_addr
          size 65535
          flags dynamic
        }

        chain fw-turn-limit {
          ip6 saddr ${config.mine.nat64.prefix} add @turn-sources { ip6 saddr ct count over ${toString turnFlowsPerSource} } jump fw-drop
          ip6 saddr ${config.mine.nat64.prefix} return
          add @turn-sources { ip6 saddr and ffff:ffff:ffff:ff00:: ct count over ${toString turnFlowsPerSource} } jump fw-drop
        }

        # traffic from the public internet -> internal containers
        chain fw-outside-traffic {
          # traffic not bound for us, sus...
          ip6 daddr != ${luxPublicNetwork6} jump fw-drop

          # only IPv6 is expected here, IPv4 arrives translated by the NAT64
          meta nfproto ipv4 jump fw-drop

          ip6 daddr ${config.containers.mailserver.localAddress6} tcp dport { 25, 80 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} tcp dport { 80, 443 } jump fw-accept-dos
          ip6 daddr ${config.containers.caddy.localAddress6} udp dport 443 jump fw-accept-dos
          ip6 daddr ${config.containers.powerdns.localAddress6} tcp dport 53 jump fw-accept-dos-dns
          ip6 daddr ${config.containers.powerdns.localAddress6} udp dport 53 jump fw-accept-dos-dns
          # TURN: at most turnFlowsPerSource open allocations (control flows) per source
          ip6 daddr { ${config.containers.mtx-co-v4.localAddress6}, ${config.containers.mtx-co-v6.localAddress6} } meta l4proto { tcp, udp } th dport 3478 jump fw-turn-limit
          # mtx-co-v4 itself is NAT64-only
          ip6 daddr ${config.containers.mtx-co-v4.localAddress6} tcp dport 3478 jump fw-accept-dos
          ip6 daddr ${config.containers.mtx-co-v4.localAddress6} udp dport 3478 jump fw-accept-dos
          ip6 daddr ${config.containers.mtx-co-v4.localAddress6} udp dport 49160-50159 jump fw-accept-dos
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
