{ lib, noxa, ... }: with lib; with types; with noxa.lib.net.types; {
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

  options.mine.info.public = {
    ipv4 = mkOption {
      type = nullOr ip4NoMask;
      default = null;
      description = ''
        This host's public IPv4 address.
      '';
      example = "5.252.225.58";
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
