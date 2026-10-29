{ lib, noxa, ... }:
with lib;
with types;
with noxa.lib.net.types;
{
  options.mine.info.domain = mkOption {
    type = nullOr str;
    default = null;
    description = ''
      This host's primary domain name.
    '';
    example = "example.com";
  };

  options.mine.info.ipv6Salt = mkOption {
    type = nullOr str;
    default = null;
    description = ''
      Used to to salt ipv6 device ip address hashing.
    '';
  };

  options.mine.info.weatherCity = mkOption {
    type = nullOr str;
    default = null;
    description = ''
      Default city name for the waybar weather module (wttrbar), used when
      no per-session override has been set via `waybar-set-city`.
    '';
    example = "Berlin";
  };

  options.mine.info.public = {
    ipv4 = mkOption {
      type = nullOr ip4NoMask;
      default = null;
      description = ''
        This host's public IPv4 address.
      '';
      example = "192.0.2.10";
    };

    ipv4PrefixLength = mkOption {
      type = nullOr (ints.between 0 32);
      default = null;
      description = ''
        The prefix length of this host's public IPv4 network.
      '';
      example = 24;
    };

    ipv4Gateway = mkOption {
      type = nullOr ip4NoMask;
      default = null;
      description = ''
        The default gateway of this host's public IPv4 network.
      '';
      example = "192.0.2.1";
    };

    ipv6 = mkOption {
      type = nullOr ip6NoMask;
      default = null;
      description = ''
        This host's public IPv6 address.
      '';
    };
  };
}
