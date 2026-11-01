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
  # the fleet ULA is only routed internally (WireGuard, containers), towards an untrusted
  # interface it can only be a leak (missing route, pushed/hijacked route): log, drop
  outRules = ''
    oifname ${interfaces} ip6 daddr ${noxa.ula.prefix} limit rate 6/minute burst 5 packets log prefix "ula-guard leak: " level warn
    oifname ${interfaces} ip6 daddr ${noxa.ula.prefix} drop
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
      WireGuard), and traffic to the ULA prefix leaving through them is logged and dropped.
      Applies to the host itself and to forwarded traffic.
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

        chain output {
          type filter hook output priority filter - 1; policy accept;
          ${outRules}
        }

        chain forward {
          type filter hook forward priority filter - 1; policy accept;
          ${rules}
          ${outRules}
        }
      '';
    };
  };
}
