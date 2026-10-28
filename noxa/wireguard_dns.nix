{ lib, ... }: with lib;
{
  # Applied to the member hosts by nixos/wireguard_dns.nix
  options.noxa.wireguard = with types; mkOption {
    type = attrsOf (submodule {
      options = {
        dns.enable = mkOption {
          type = bool;
          default = true;
          description = "Add a dns entry for this host.";
        };
        dns.domain = mkOption {
          type = nullOr str;
          default = null;
          description = "The top-level domain to use for dns entries for this interface. Defaults to mine.dns.wireguard.domain of each host.";
        };
      };
    });
  };
}
