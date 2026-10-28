{ config
, lib
, pkgs
, noxa
, ...
}:
with lib;
let
  cfg = config.mine.guestUla;
  hostName = config.networking.hostName;

  # <guest>.<host><network domain> -> ULA, e.g. caddy.lux.vlan
  ulaHosts = network: mapAttrs'
    (name: address: nameValuePair "${name}.${hostName}${config.noxa.wireguard.interfaces.${network}.dns.domain}" [ address ])
    cfg.addresses;

  # <container>.<host><publicDomain> -> public address, e.g. caddy.lux.wan
  publicContainers = filterAttrs
    (name: container: container.localAddress6 != null && !(noxa.lib.net.laysWithinSubnet container.localAddress6 "fc00::/7"))
    config.containers;
  publicHosts = mapAttrs'
    (name: container: nameValuePair "${name}.${hostName}${cfg.publicDomain}" [ (noxa.lib.net.decompose container.localAddress6).addressNoMask ])
    publicContainers;
in
{
  options.mine.guestUla = with types; {
    containers = mkOption {
      type = listOf str;
      default = [ ];
      description = ''
        NixOS containers (with `privateNetwork`) that get an additional address out of the
        fleet ULA prefix (`noxa.ula`) on their existing veth, e.g. to be reachable over
        WireGuard without exposing them publicly. The peers of `advertiseOn` resolve
        `<container>.<host><network domain>` to it.
      '';
    };

    microvms = mkOption {
      type = listOf str;
      default = attrNames config.mine.vm.guests;
      defaultText = literalExpression "attrNames config.mine.vm.guests";
      description = ''
        MicroVMs that get an address out of the fleet ULA prefix, their only address
        (see nixos/microvm/networking.nix).
      '';
    };

    advertiseOn = mkOption {
      type = listOf str;
      default = [ ];
      example = [ "cloud-admin" ];
      description = "WireGuard networks whose peers route `network` through this host.";
    };

    publicDomain = mkOption {
      type = str;
      default = ".wan";
      description = ''
        Top-level domain of the names the WireGuard peers (`advertiseOn`) resolve to the public
        addresses of this host's containers, `<container>.<host><publicDomain>`.
      '';
    };

    network = mkOption {
      type = str;
      readOnly = true;
      default = noxa.ula.subnetFor "guests-${hostName}";
      defaultText = literalExpression ''noxa.ula.subnetFor "guests-<hostName>"'';
      description = "The /64 the guest addresses of this host are taken from.";
    };

    hostAddress = mkOption {
      type = str;
      readOnly = true;
      default = (noxa.lib.net.decompose cfg.network).networkNoMask + "1";
      defaultText = literalExpression "<network>::1";
      description = "The host's own address in `network`, the next hop of the microVMs.";
    };

    dnsAddress = mkOption {
      type = str;
      readOnly = true;
      default = (noxa.lib.net.decompose cfg.network).networkNoMask + "53";
      defaultText = literalExpression "<network>::53";
      description = "The address of the host's DNS resolver for the guests in `network`, only used by it.";
    };

    addresses = mkOption {
      type = attrsOf str;
      readOnly = true;
      default = genAttrs (cfg.containers ++ cfg.microvms) (name: noxa.ula.addressFor cfg.network name);
      defaultText = literalExpression "<hashed address in network per guest>";
      description = "The ULA address of each guest, without mask.";
    };
  };

  config = mkIf (cfg.containers != [ ] || cfg.microvms != [ ]) {
    assertions = [
      {
        assertion = noxa.ula.prefix != null;
        message = "mine.guestUla requires noxa.ula.prefix to be set.";
      }
      {
        assertion = !(elem cfg.network (attrValues noxa.ula.subnets));
        message = "mine.guestUla.network ${cfg.network} collides with a subnet in noxa.ula.subnets, change noxa.ula.salt.";
      }
      {
        assertion = length (unique (cfg.containers ++ cfg.microvms)) == length (cfg.containers ++ cfg.microvms);
        message = "mine.guestUla: container and microVM names must be unique.";
      }
      {
        assertion = allUnique ([ cfg.hostAddress cfg.dnsAddress ] ++ attrValues cfg.addresses);
        message = "mine.guestUla: two guests (or a guest and the host) got the same address, rename one of them.";
      }
    ];

    # containers: the address on the existing veth, the default route via hostAddress6
    # also carries the replies
    containers = genAttrs cfg.containers (name: {
      config.networking.interfaces.eth0.ipv6.addresses = [
        {
          address = cfg.addresses.${name};
          prefixLength = 128;
        }
      ];
    });

    systemd.services = genAttrs (map (name: "container@${name}") cfg.containers) (unit:
      let
        name = removePrefix "container@" unit;
      in
      {
        postStart = mkAfter ''
          ${pkgs.iproute2}/bin/ip -6 route replace ${cfg.addresses.${name}}/128 dev ve-${name}
        '';
      });

    noxa.wireguard.interfaces = genAttrs cfg.advertiseOn (network: {
      advertise.routes = [ cfg.network ];
      dns.extraHosts = ulaHosts network // publicHosts;
    });

    # the same names on this host, the WireGuard dns entries only reach the other peers
    mine.dns.hosts = mkMerge (map ulaHosts cfg.advertiseOn ++ [ publicHosts ]);
  };
}
