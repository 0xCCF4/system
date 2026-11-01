{ config
, lib
, options
, pkgs
, noxa
, ...
}:
with lib;
with builtins;
let
  cfg = config.mine.vm;
  ula = config.mine.guestUla;

  nat64Prefix = config.mine.nat64.prefix;

  # The resolver of the microVMs: a microVM (mine.vm.dnsGuest), or the host (ula.dnsAddress)
  dnsGuest = cfg.dnsGuest;
  resolverAddress = if dnsGuest == null then ula.dnsAddress else ula.addresses.${dnsGuest};
  dnsClientTaps = map (name: cfg.guests.${name}.tap) (filter (name: name != dnsGuest) (attrNames cfg.guests));
  set = items: "{ ${concatMapStringsSep ", " (item: ''"${item}"'') items} }";

  # special members of mine.vm.networks
  internetMember = "<internet>";
  hostMember = "<host>";
  ulaMember = "<ula>";
  specialMembers = [ internetMember hostMember ulaMember ];
  guestMembers = network: filter (member: !elem member specialMembers) network.members;
  sharesNetworkWith = special: name: any
    (network: elem special network.members && elem name network.members)
    (attrValues cfg.networks);

  # The NAT64 of the <internet> members (nixos/nat64.nix, in its own network namespace)
  hasInternet = sharesNetworkWith internetMember;
  internetTaps = map (name: cfg.guests.${name}.tap) (filter hasInternet (attrNames cfg.guests));
  nat64 = config.mine.nat64;

  # All chains have policy drop: traffic of other interfaces is accepted (and left to the
  # host's other tables), every tap only passes what its rules accept
  taps = set (mapAttrsToList (_: guest: guest.tap) cfg.guests);
  notFromGuests = ''
    # not a microVM: not filtered here
    iifname != ${taps} accept
  '';
  notToGuests = ''
    # not a microVM: not filtered here
    oifname != ${taps} accept
  '';

  # Accept everything not from VMs, then, drop all non ULA source traffic
  # From here, traffic originating from VM is ip6 and has its ULA as origin.
  preroutingRules = notFromGuests + concatStringsSep "\n" (mapAttrsToList
    (name: guest: ''
      # ${name}: IPv6 only, connections only from its own ULA, link-local and multicast
      # addresses only for ICMPv6 (neighbor discovery, MLD)
      iifname "${guest.tap}" meta nfproto ipv4 drop
      iifname "${guest.tap}" ip6 saddr != { ${ula.addresses.${name}}, fe80::/10 } drop
      iifname "${guest.tap}" meta l4proto != ipv6-icmp ip6 saddr != ${ula.addresses.${name}} drop
      iifname "${guest.tap}" meta l4proto != ipv6-icmp ip6 daddr { fe80::/10, ff00::/8 } drop
      iifname "${guest.tap}" accept
    '')
    cfg.guests);

  # Accept non VM traffic, allow VM traffic only if <host> in network
  # Always allow DNS in to host
  inputRules = notFromGuests + concatStringsSep "\n" (mapAttrsToList
    (name: guest:
      if sharesNetworkWith hostMember name then ''
        # ${name}: access to the host (<host>)
        iifname "${guest.tap}" accept
        # policy drop
      '' else ''
        # ${name}: no access to the host
        iifname "${guest.tap}" icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-solicit, packet-too-big, destination-unreachable } accept
        ${optionalString (dnsGuest == null) ''iifname "${guest.tap}" ip6 daddr ${ula.dnsAddress} meta l4proto { tcp, udp } th dport 53 accept''}
        # policy drop
      '')
    cfg.guests);

  # taps of the microVMs sharing a network with a microVM
  networkPeerTaps = name: map (member: cfg.guests.${member}.tap) (remove name (unique (concatMap
    (network: optionals (elem name network.members) (guestMembers network))
    (attrValues cfg.networks))));

  # VMs may be/reach only the members of their networks
  forwardChainRules = ''
    # not a microVM: not filtered here
    iifname != ${taps} oifname != ${taps} accept
  '' + concatStringsSep "\n" (mapAttrsToList
    (name: guest:
      let
        peers = networkPeerTaps name;
      in
      optionalString (peers != [ ]) ''
        # ${name}: its networks
        iifname "${guest.tap}" oifname ${set peers} accept
      '' + optionalString (hasInternet name) ''
        # ${name}: to the internet through the NAT64 (<internet>), and only the replies
        iifname "${guest.tap}" oifname "${nat64.interface}" accept
        iifname "${nat64.interface}" oifname "${guest.tap}" ct state established,related accept
      '' + optionalString (dnsGuest != null && name != dnsGuest) ''
        # ${name}: DNS to the resolver microVM (mine.vm.dnsGuest), and its answers
        iifname "${guest.tap}" oifname "${cfg.guests.${dnsGuest}.tap}" ip6 daddr ${resolverAddress} meta l4proto { tcp, udp } th dport 53 accept
        iifname "${cfg.guests.${dnsGuest}.tap}" oifname "${guest.tap}" ip6 saddr ${resolverAddress} meta l4proto { tcp, udp } th sport 53 ct state established accept
      '' + optionalString (sharesNetworkWith ulaMember name) ''
        # ${name}: from the other ULA hosts (<ula>), and the replies
        oifname "${guest.tap}" ip6 saddr ${noxa.ula.prefix} accept
        iifname "${guest.tap}" ip6 daddr ${noxa.ula.prefix} accept
      '')
    cfg.guests);

  # Accept non VM traffic, allow VM traffic only if <host> in network
  outputRules = notToGuests + concatStringsSep "\n" (mapAttrsToList
    (name: guest: ''
      # ${name}: IPv6 only, connections only between the ULAs, link-local and multicast
      # addresses only for ICMPv6 (neighbor discovery, MLD)
      oifname "${guest.tap}" meta nfproto ipv4 drop
    '' + (if sharesNetworkWith hostMember name then ''
      # ${name}: the host may reach it (<host>)
      oifname "${guest.tap}" accept
    '' else ''
      # ${name}: not reachable from the host
      # answers to the DNS queries of the microVM
      oifname "${guest.tap}" meta l4proto != ipv6-icmp ip6 saddr != { ${ula.hostAddress}${optionalString (dnsGuest == null) ", ${ula.dnsAddress}"} } drop
      oifname "${guest.tap}" meta l4proto != ipv6-icmp ip6 daddr != ${ula.addresses.${name}} drop
      ${optionalString (dnsGuest == null) ''oifname "${guest.tap}" ip6 saddr ${ula.dnsAddress} meta l4proto { tcp, udp } th sport 53 ct state established accept''}
      oifname "${guest.tap}" icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, packet-too-big, destination-unreachable, time-exceeded, parameter-problem } accept
    ''))
    cfg.guests);
in
{
  options.mine.vm = with types; {
    guests = mkOption {
      default = { };
      description = ''
        MicroVMs with networking. Every microVM gets its own tap interface on the host
        (`tap-<name>`), routed by the host: the guest is IPv6 only and gets its address
        out of the fleet ULA prefix (`mine.guestUla`).
      '';
      type = attrsOf (submodule ({ name, ... }: {
        options = {
          tap = mkOption {
            type = str;
            readOnly = true;
            default = "tap-${name}";
            description = "Name of the tap interface on the host.";
          };

          mac = mkOption {
            type = str;
            readOnly = true;
            # derived from the name only, so it is stable
            default =
              let
                hash = hashString "sha256" "microvm-mac:${name}";
              in
              "02:7a:${concatMapStringsSep ":" (i: substring (i * 2) 2 hash) (range 0 3)}";
            description = "MAC address of the microVM's interface.";
          };
        };
      }));
    };

    networks = mkOption {
      default = { };
      description = ''
        Groups of microVMs (`mine.vm.guests`) that may reach each other, in both directions.
        microVMs that share no network are isolated from each other, and nothing else is
        forwarded to or from them. The special members grant additional access:
        - `<internet>`: the members may open connections to the internet, through the
          host's NAT64 in its own network namespace (IPv4 masqueraded to
          `mine.wanInterfaces`), and a CLAT inside them for IPv4 literals.
        - `<ula>`: the members and every address of the fleet ULA prefix (`noxa.ula.prefix`),
          e.g. the WireGuard peers and all other microVMs, may reach each other (subject to
          the host's forward chain).
        - `<host>`: the members and the host may reach each other (the host's services
          subject to its firewall). Without it only the host's DNS resolver for the
          microVMs is reachable, and the host opens no connections to the members.
      '';
      type = attrsOf (submodule {
        options.members = mkOption {
          type = listOf str;
          default = [ ];
          example = [ "vm1" "vm2" "<internet>" ];
          description = "The microVMs of this network, and the special members `<internet>`, `<host>` and `<ula>`.";
        };
      });
    };

    dnsGuest = mkOption {
      type = nullOr str;
      default = null;
      example = "dns";
      description = ''
        The microVM (of `guests`, with `<internet>`) that resolves names for the other
        microVMs, on its ULA, port 53 (only reachable from them). Without it, the host runs
        the resolver on `mine.guestUla.dnsAddress` (unbound, forwarding to its dnscrypt-proxy).
        The microVM configures its upstream itself, its unbound gets the other microVMs'
        network as allowed clients.
      '';
    };

    guestInterface = mkOption {
      type = str;
      default = "uplink";
      description = "Name of the network interface inside the microVMs.";
    };

    forwardRules = mkOption {
      type = lines;
      readOnly = true;
      default = concatStringsSep "\n"
        (mapAttrsToList
          (name: network:
            let
              taps = map (member: cfg.guests.${member}.tap) (guestMembers network);
            in
            optionalString (length taps > 1) ''
              # microVM network ${name}
              iifname ${set taps} oifname ${set taps} accept
            '')
          cfg.networks)
      + optionalString (dnsGuest != null && dnsClientTaps != [ ]) ''

        # DNS of the microVMs to their resolver microVM (mine.vm.dnsGuest)
        iifname ${set dnsClientTaps} oifname "${cfg.guests.${dnsGuest}.tap}" ip6 daddr ${resolverAddress} meta l4proto { tcp, udp } th dport 53 accept
      '';
      description = ''
        nftables rules allowing the traffic between the microVMs of each network, and their
        DNS to the resolver microVM (`dnsGuest`), to be included in the host's forward chain
        (with a drop policy), next to `mine.nat64.forwardRules`.
      '';
    };
  };

  config = mkIf (cfg.guests != { }) ({
    warnings = map
      (name: "mine.vm.networks: ${name} has <ula> but not <host>, <ula> implies <host>.")
      (filter (name: sharesNetworkWith ulaMember name && !sharesNetworkWith hostMember name) (attrNames cfg.guests));

    assertions = [
      {
        assertion = all (name: hasAttr name (config.microvm.vms or { })) (attrNames cfg.guests);
        message = "mine.vm.guests: ${toJSON (filter (name: !hasAttr name (config.microvm.vms or { })) (attrNames cfg.guests))} are not declared in microvm.vms.";
      }
      {
        assertion = all (network: all (member: hasAttr member cfg.guests) (guestMembers network)) (attrValues cfg.networks);
        message = "mine.vm.networks: every member must be declared in mine.vm.guests (or be one of ${toJSON specialMembers}).";
      }
      {
        assertion = all (guest: stringLength guest.tap <= 15) (attrValues cfg.guests);
        message = "mine.vm.guests: tap interface names must be at most 15 characters, shorten the microVM names to at most 11.";
      }
      {
        assertion = nat64.wanInterfaces == [ ] -> all (name: !sharesNetworkWith internetMember name) (attrNames cfg.guests);
        message = "mine.vm.networks: <internet> needs mine.wanInterfaces (or mine.nat64.wanInterfaces).";
      }
      {
        # Jool in the host's namespace translates in prerouting, before the forward chain
        assertion = attrNames config.networking.jool.nat64 == optional nat64.enable "nat64" && config.networking.jool.siit == { };
        message = "mine.vm.guests: no other Jool instances than mine.nat64 on a host with microVMs, they would translate the microVMs' traffic before the forward chain filters it.";
      }
      {
        assertion = dnsGuest != null -> (hasAttr dnsGuest cfg.guests && hasInternet dnsGuest);
        message = "mine.vm.dnsGuest: ${toString dnsGuest} must be one of mine.vm.guests and a member of a network with <internet> (its upstream).";
      }
      {
        assertion = allUnique (map (guest: guest.mac) (attrValues cfg.guests));
        message = "mine.vm.guests: two microVMs got the same MAC address, rename one of them.";
      }
    ];

    # host side of each tap: next hop of the guest, route to the guest's address
    systemd.network = {
      enable = true;
      networks = mapAttrs'
        (name: guest: nameValuePair "20-microvm-${name}" {
          matchConfig.Name = guest.tap;
          addresses = [
            { Address = "${ula.hostAddress}/128"; }
          ]
          # the DNS resolver of the microVMs, unless a microVM is (mine.vm.dnsGuest)
          ++ optional (dnsGuest == null) { Address = "${ula.dnsAddress}/128"; };
          routes = [{ Destination = "${ula.addresses.${name}}/128"; }];
        })
        cfg.guests;
    };

    # (nixos/nat64.nix sets it too with mkDefault, sysctls must have one definition)
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = mkOverride 999 true;

    # the other microVMs after their resolver microVM (wants: started along, but they don't
    # fail with it); only the order of the QEMU processes, see infra-host-ttl below
    systemd.services = optionalAttrs (dnsGuest != null) (listToAttrs (map
      (name: nameValuePair "microvm@${name}" {
        overrideStrategy = "asDropin";
        after = [ "microvm@${dnsGuest}.service" ];
        wants = [ "microvm@${dnsGuest}.service" ];
      })
      (filter (name: name != dnsGuest) (attrNames cfg.guests))));

    # the NAT64 of the <internet> members
    mine.nat64 = mkIf (internetTaps != [ ]) {
      enable = true;
      clients = internetTaps;
    };

    # the resolver of the microVMs (DNS64 happens inside them), on the host unless a
    # microVM is (mine.vm.dnsGuest)
    services.unbound.settings.server = mkIf (dnsGuest == null) {
      interface = [ ula.dnsAddress ];
      access-control = [ "${ula.network} allow" ];
      # the address is configured on the taps by networkd, possibly after unbound started
      ip-freebind = true;
    };
    networking.firewall.interfaces = mkIf (dnsGuest == null) (mapAttrs'
      (name: guest: nameValuePair guest.tap {
        allowedUDPPorts = [ 53 ];
        allowedTCPPorts = [ 53 ];
      })
      cfg.guests);

    networking.nftables.enable = true;
    networking.nftables.tables.microvm-guests-arp = {
      family = "arp";
      content = ''
        chain input {
          type filter hook input priority filter; policy accept;
          iifname ${taps} drop
        }

        chain output {
          type filter hook output priority filter; policy accept;
          oifname ${taps} drop
        }
      '';
    };

    networking.nftables.tables.microvm-guests = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority mangle; policy drop;
          ${preroutingRules}
        }

        chain input {
          type filter hook input priority filter - 1; policy drop;
          ${inputRules}
        }

        chain forward {
          type filter hook forward priority filter - 1; policy drop;
          ${forwardChainRules}
        }

        chain output {
          type filter hook output priority filter - 1; policy drop;
          ${outputRules}
        }
      '';
    };
  } // optionalAttrs (options ? microvm) {
    # (microvm.vms only exists with the microvm host module)
    microvm.vms = mapAttrs
      (name: guest: {
        config = {
          microvm.interfaces = [
            {
              type = "tap";
              id = guest.tap;
              inherit (guest) mac;
              tap.vhost = true;
            }
          ];

          systemd.network.links."10-${cfg.guestInterface}" = {
            matchConfig.PermanentMACAddress = guest.mac;
            linkConfig.Name = cfg.guestInterface;
          };

          networking.interfaces.${cfg.guestInterface}.ipv6 = {
            addresses = [
              {
                address = ula.addresses.${name};
                prefixLength = 128;
              }
            ];
            routes = [
              {
                address = ula.hostAddress;
                prefixLength = 128;
              }
            ];
          };
          networking.defaultGateway6 = {
            address = ula.hostAddress;
            interface = cfg.guestInterface;
          };

          # IPv6 only with a ULA: every name resolves to its NAT64 address, resolution
          # itself is forwarded to the host
          networking.nameservers = mkForce [ "::1" ];
          # no name resolution by multicast on the link (only the host is on it)
          services.resolved.settings.Resolve = {
            LLMNR = false;
            MulticastDNS = false;
          };

          # 464XLAT with <internet>: the IPv4 of applications (e.g. literal addresses) is
          # translated to IPv6 inside the VM (CLAT), from its own address (clatd's default
          # clat-v6-addr=shared), the host's NAT64 translates it back
          services.clatd = mkIf (hasInternet name) {
            enable = true;
            settings = {
              plat-dev = cfg.guestInterface;
              plat-prefix = nat64Prefix;
              # the VM never has native IPv4: no 10s wait for it before starting
              v4-conncheck-enable = false;
            };
          };
          # clatd takes the source address of `ip -6 route get <PLAT prefix>`: early in the
          # boot there is none yet (falls back to ::1, which tayga refuses), so wait for it
          # (at most 30s), and retry should it fail anyway
          systemd.services.clatd = mkIf (hasInternet name) {
            path = [ pkgs.iproute2 pkgs.gnugrep ];
            preStart = ''
              for _ in $(seq 60); do
                ip -6 route get ${removeSuffix "/96" nat64Prefix} 2>/dev/null | grep -q " src ${ula.addresses.${name}} " && exit 0
                sleep 0.5
              done
              echo "no route with source ${ula.addresses.${name}} towards the NAT64 prefix yet, starting anyway"
            '';
            serviceConfig = {
              Restart = "on-failure";
              RestartSec = "5s";
            };
          };
          services.unbound = {
            enable = true;
            resolveLocalQueries = false;
            settings = {
              server = {
                # the resolver microVM brings its own setup (loopback, upstream), here only
                # what makes it the resolver of the others
                interface = if name == dnsGuest then [ ula.addresses.${name} ] else [ "::1" ];
                access-control = if name == dnsGuest then [ "${ula.network} allow" ] else [ "::1/128 allow" ];
                module-config = ''"dns64 iterator"'';
                # a resolver microVM still starting is retried after a minute, not after
                # unbound's default 15 minutes
                infra-host-ttl = mkIf (dnsGuest != null && name != dnsGuest) 60;
                dns64-prefix = nat64Prefix;
                dns64-synthall = true;
              };
              # the resolver microVM has its own upstream (and serves the others)
              forward-zone = mkIf (name != dnsGuest) [
                {
                  name = ".";
                  forward-addr = [ resolverAddress ];
                }
              ];
            };
          };
        };
      })
      cfg.guests;
  });
}
