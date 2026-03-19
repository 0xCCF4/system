{ lib, config, ... }: with lib; {
  options = with types; {
    wireguard = mkOption {
      type = attrsOf (submodule {
        options = {
          dns.enable = mkOption {
            type = bool;
            default = true;
            description = "Add a dns entry for this host.";
          };
          dns.domain = mkOption {
            type = str;
            default = config.mine.dns.wireguard.domain;
            description = "The top-level domain to use for dns entries for this interface.";
          };
        };
      });
    };
  };

  config = {
    nodes = mkMerge (flatten (mapAttrsToList
      (name: network:
        mapAttrsToList
          (member: memberConfig: {
            "${member}" = {
              configuration.noxa.wireguard.interfaces."${name}" = {
                dns.enable = mkDefault network.dns.enable;
                dns.domain = mkDefault network.dns.domain;
              };
            };
          })
          network.members
      )
      config.wireguard));
  };
}
