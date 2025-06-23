{ inputs
, pkgs
, lib
, config
, ...
}:
with lib;
{
  options.mine.dns = with types; {
    provider = mkOption {
      type = enum [ "quad9" ];
      default = "quad9";
      description = "The DNS provider to use.";
    };
  };

  config = {
    networking = {
      nameservers = [ "127.0.0.1" "::1" ];
      dhcpcd.extraConfig = "nohook resolv.conf";
      networkmanager.dns = "none";
    };

    services.dnscrypt-proxy2 = {
      enable = mkDefault true;
      settings = {
        ipv6_servers = mkDefault true;
        require_dnssec = mkDefault true;
        sources.public-resolvers = {
          urls = [
            "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
            "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
          ];
          cache_file = "/var/cache/dnscrypt-proxy/public-resolvers.md";
          minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
        };
        server_names =
          let
            ipv6 = config.services.dnscrypt-proxy2.settings.ipv6_servers.content;
            provider = config.mine.dns.provider;
          in
          [ ]
          ++ (lists.optional (provider == "quad9") "quad9-doh-ip4-port443-filter-pri")
          ++ (lists.optional (provider == "quad9" && ipv6) "quad9-doh-ip6-port443-filter-pri")
        ;
      };
    };
  };
}
