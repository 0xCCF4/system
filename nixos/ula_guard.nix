{ config
, lib
, noxa
, ...
}:
with lib;
let
  cfg = config.mine.ulaGuard;
  interfaces = "{ ${concatMapStringsSep ", " (name: ''"${name}"'') cfg.interfaces} }";
  rules = ''
    iifname ${interfaces} ip6 daddr ${noxa.ula.prefix} reject with icmpx type admin-prohibited
    iifname ${interfaces} ip6 saddr ${noxa.ula.prefix} drop
  '';
in
{
  options.mine.ulaGuard.interfaces = with types; mkOption {
    type = listOf str;
    default = config.mine.wanInterfaces;
    defaultText = literalExpression "config.mine.wanInterfaces";
    example = [ "wan" ];
    description = ''
      Untrusted interfaces (internet, LAN) the fleet ULA network (`noxa.ula`) is internal to:
      traffic from them to the ULA prefix is rejected, traffic claiming to come from it is
      dropped (a loose reverse path check would let it pass, the ULA prefix is routed via
      WireGuard). Applies to the host itself and to forwarded traffic.
    '';
  };

  config = mkIf (cfg.interfaces != [ ]) {
    networking.nftables.enable = true;
    networking.nftables.tables.ula-guard = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority filter - 1; policy accept;
          ${rules}
        }

        chain forward {
          type filter hook forward priority filter - 1; policy accept;
          ${rules}
        }
      '';
    };
  };
}
