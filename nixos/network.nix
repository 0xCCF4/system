{ config
, lib
, noxa
, ...
}@inputs:
with lib;
{
  options.mine = with types; {
    links = mkOption {
      type = listOf (
        submodule (submod: {
          options.mac = mkOption {
            type = str;
            description = "The MAC address of the network interface.";
          };
          options.name = mkOption {
            type = str;
            description = "The name of the network interface.";
          };
        })
      );
      default = [ ];
      description = "Configure persistent network interface names based on MAC addresses.";
    };

    wanInterfaces = mkOption {
      type = listOf str;
      default = [ ];
      example = [ "wan" ];
      description = ''
        The host's interfaces towards untrusted networks: the internet, or a LAN uplink.
        The default of geo-blocking (`mine.services.geoBlock.externalInterfaces`), the ULA
        guard (`mine.ulaGuard.interfaces`), the martian guard (`mine.martianGuard.interfaces`)
        and the NAT64's masquerade (`mine.nat64.wanInterfaces`).
      '';
    };

    linkNetDevRulePrefix = mkOption {
      type = str;
      default = "50-link-";
      description = "Prefix for the systemd .link network device rule files created for mine.links.";
    };
  };

  config =
    let
      links = mkMerge (
        map
          (entry: {
            "${config.mine.linkNetDevRulePrefix}${entry.name}-${entry.mac}" = {
              matchConfig.PermanentMACAddress = entry.mac;
              linkConfig.Name = entry.name;
            };
          })
          config.mine.links
      );
    in
    {
      systemd.network.links = links;
      boot.initrd.systemd.network.links = links;
    };
}
