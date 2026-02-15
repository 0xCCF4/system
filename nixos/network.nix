{ config, lib, noxa, ... }@inputs: with lib; {
  options.mine = with types; {
    links = mkOption {
      type = listOf (submodule (submod: {
        options.mac = mkOption {
          type = str;
          description = "The MAC address of the network interface.";
        };
        options.name = mkOption {
          type = str;
          description = "The name of the network interface.";
        };
      }));
      default = [ ];
      description = "Configure persistent network interface names based on MAC addresses.";
    };

    linkNetDevRulePrefix = mkOption {
      type = str;
      default = "50-link-";
      description = "Prefix for the systemd .link network device rule files created for mine.links.";
    };
  };

  config = {
    systemd.network.links = mkMerge (map
      (entry: {
        "${config.mine.linkNetDevRulePrefix}${entry.name}" = {
          matchConfig.PermanentMACAddress = entry.mac;
          linkConfig.Name = entry.name;
        };
      })
      config.mine.links);
  };
}
