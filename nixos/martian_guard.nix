{ config
, lib
, noxa
, ...
}:
with lib;
let
  cfg = config.mine.martianGuard;
  interfaces = "{ ${concatMapStringsSep ", " (name: ''"${name}"'') cfg.interfaces} }";
  isIpv6 = hasInfix ":";

  # sources never valid on any link (IANA special-purpose registries, RFC 6890; RFC 1122)
  martians4 = [
    "0.0.0.0/8" # this network (except DHCP requests, see below)
    "127.0.0.0/8" # loopback
    "192.0.2.0/24" # documentation (RFC 5737)
    "198.51.100.0/24"
    "203.0.113.0/24"
    "198.18.0.0/15" # benchmarking (RFC 2544)
    "224.0.0.0/4" # multicast, never a source
    "240.0.0.0/4" # reserved, and the limited broadcast
  ];
  martians6 = [
    "::1/128" # loopback
    "::ffff:0:0/96" # IPv4-mapped (RFC 4291)
    "64:ff9b::/96" # NAT64 (RFC 6052, RFC 8215), only from the host's own NAT64
    "64:ff9b:1::/48"
    "100::/64" # discard-only (RFC 6666)
    "2001:db8::/32" # documentation (RFC 3849, RFC 9637)
    "3fff::/20"
    "2002::/16" # 6to4, deprecated (RFC 7526)
    "fec0::/10" # site-local, deprecated (RFC 3879)
    "ff00::/8" # multicast, never a source
  ];
  # valid on a LAN, not from the internet
  private4 = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10" "169.254.0.0/16" ];
  private6 = [ "fc00::/7" ];

  sources4 = martians4 ++ optionals cfg.publicUplink private4 ++ filter (source: !isIpv6 source) cfg.extraSources;
  # the fleet ULA prefix is internal (WireGuard), see also nixos/ula_guard.nix
  sources6 = martians6 ++ optionals cfg.publicUplink private6 ++ optional (noxa.ula.prefix != null) noxa.ula.prefix
    ++ filter isIpv6 cfg.extraSources;
in
{
  options.mine.martianGuard = with types; {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Drop martian packets (impossible source addresses) arriving on `interfaces`.";
    };

    interfaces = mkOption {
      type = listOf str;
      default = config.mine.wanInterfaces;
      defaultText = literalExpression "config.mine.wanInterfaces";
      description = "The interfaces towards untrusted networks.";
    };

    publicUplink = mkOption {
      type = bool;
      default = false;
      description = ''
        Whether `interfaces` face the internet directly: private sources (RFC 1918, shared
        address space, IPv4 link-local, ULA) are martians too. Not for a LAN uplink.
      '';
    };

    extraSources = mkOption {
      type = listOf str;
      default = [ ];
      example = [ "2001:db8:1::/64" ];
      description = "More sources to drop on `interfaces`, e.g. the host's own prefix (anti-spoofing).";
    };
  };

  # before conntrack (priority raw), applies to the host itself and to forwarded traffic
  config = mkIf (cfg.enable && cfg.interfaces != [ ]) {
    networking.nftables.enable = true;
    networking.nftables.tables.martian-guard = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority raw; policy accept;
          # DHCP requests come from 0.0.0.0
          iifname ${interfaces} ip saddr 0.0.0.0 udp sport 68 udp dport 67 accept
          iifname ${interfaces} ip saddr { ${concatStringsSep ", " sources4} } drop
          # :: only for duplicate address detection and MLD
          iifname ${interfaces} ip6 saddr :: meta l4proto != ipv6-icmp drop
          iifname ${interfaces} ip6 saddr { ${concatStringsSep ", " sources6} } drop
        }
      '';
    };
  };
}
