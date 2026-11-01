{ config
, lib
, ...
}:
with lib;
let
  cfg = config.mine.wireguardLeakGuard;

  # interface -> the prefixes routed into it (the AllowedIPs of its peers), from
  # both backends noxa uses (networking.wireguard, networking.wg-quick)
  tunnelPrefixes =
    mapAttrs (_: iface: concatMap (peer: peer.allowedIPs) iface.peers) config.networking.wireguard.interfaces
    // mapAttrs (_: iface: concatMap (peer: peer.allowedIPs) iface.peers) config.networking.wg-quick.interfaces;

  # prefix -> the tunnels it may leave through; default routes aren't a split tunnel
  prefixTunnels = filterAttrs (prefix: _: !elem prefix [ "0.0.0.0/0" "::/0" ])
    (zipAttrsWith (_: tunnels: unique tunnels)
      (concatLists (mapAttrsToList (iface: prefixes: map (prefix: { ${prefix} = iface; }) prefixes) tunnelPrefixes)));

  set = items: "{ ${concatMapStringsSep ", " (item: ''"${item}"'') items} }";
  rule = prefix: tunnels:
    let
      family = if hasInfix ":" prefix then "ip6" else "ip";
    in
    ''
      ${family} daddr ${prefix} oifname != ${set tunnels} limit rate 6/minute burst 5 packets log prefix "wg-leak-guard: " level warn
      ${family} daddr ${prefix} oifname != ${set tunnels} drop
    '';
  rules = concatStrings (mapAttrsToList rule prefixTunnels);
  # ... and traffic from them may only arrive through it (spoofed tunnel addresses)
  inRule = prefix: tunnels:
    let
      family = if hasInfix ":" prefix then "ip6" else "ip";
    in
    ''
      ${family} saddr ${prefix} iifname != ${set tunnels} limit rate 6/minute burst 5 packets log prefix "wg-leak-guard in: " level warn
      ${family} saddr ${prefix} iifname != ${set tunnels} drop
    '';
  inRules = concatStrings (mapAttrsToList inRule prefixTunnels);
in
{
  options.mine.wireguardLeakGuard.enable = with types; mkOption {
    type = bool;
    # like the ULA guard: only hosts on untrusted networks (doesn't switch others to nftables)
    default = config.mine.wanInterfaces != [ ];
    defaultText = literalExpression "config.mine.wanInterfaces != [ ]";
    description = ''
      Traffic to the prefixes routed through a WireGuard tunnel (its peers' AllowedIPs) may
      only leave through that tunnel, and traffic from them may only arrive through it;
      anything else is logged and dropped. Against routes
      pushed by an untrusted network (DHCP option 121, "TunnelVision" CVE-2024-3661), an
      untrusted network claiming the prefix as on-link ("TunnelCrack" LocalNet), or a tunnel
      that is down while its routes are gone: the traffic is dropped instead of leaking in
      clear text. Applies to the host itself and to forwarded traffic.
    '';
  };

  # only on the option: the peers (via noxa) must not decide whether nftables is on
  config = mkIf cfg.enable {
    networking.nftables.enable = true;
    networking.nftables.tables.wireguard-leak-guard = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority raw; policy accept;
          ${inRules}
        }

        chain output {
          type filter hook output priority filter - 1; policy accept;
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
