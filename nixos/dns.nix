{ inputs
, pkgs
, lib
, config
, noxa
, adblock
, ...
}:
with lib;
{
  imports = [
    adblock.nixosModule
  ];

  options.mine.dns = with types; with noxa.lib.net.types; {
    enable = mkOption {
      type = bool;
      default = true;
      description = "Whether to enable the custom DNS configuration.";
    };
    provider = mkOption {
      type = enum [ "quad9" ];
      default = "quad9";
      description = "The DNS provider to use.";
    };
    hosts = mkOption {
      type = attrsOf (listOf ipNoMask);
      default = { };
      description = "Custom host entries to add to /etc/hosts.";
      example = {
        "*.example[0-9].*" = [ "127.0.0.1" "127.0.0.2" ];
      };
    };
    listenAddresses = mkOption {
      type = listOf str;
      default = [ "127.0.0.60:54" "[::60]:54" ];
    };
    upstreamResolvers = mkOption {
      type = listOf str;
      readOnly = true;
      default = map
        (addr:
          let
            split = splitString ":" addr;
            noBrackets = map (s: lib.replaceStrings [ "[" "]" ] [ "" "" ] s) split;
            lastElement = last noBrackets;
            beforeElements = sublist 0 (length noBrackets - 1) noBrackets;
            before = concatStringsSep ":" beforeElements;
          in
          "${before}#${lastElement}")
        config.mine.dns.listenAddresses;
      description = "The upstream DNS resolvers to use. Port is seperated by # instead of : .";
    };
  };

  config = mkIf config.mine.dns.enable {
    networking = {
      networkmanager.dns = "systemd-resolved";
      stevenBlackHosts = {
        enable = mkDefault true;

        blockFakenews = mkDefault true;
        blockPorn = mkDefault true;
        blockSocial = mkDefault (if (config.mine.presets.isWorkstation or false) then false else true);
        blockGambling = mkDefault true;
      };
    };
    services.resolved = {
      enable = mkDefault true;
      settings.Resolve = {
        DNS = config.mine.dns.listenAddresses;
        FallbackDNS = config.mine.dns.listenAddresses;
        Domains = [ "~." ];
        LLMNR = false;
      };
      dnsDelegates.default.Delegate = {
        DNS = config.mine.dns.listenAddresses;
        Domains = [ "~." ];
        DefaultRoute = true;
      };
    };

    services.dnscrypt-proxy = {
      enable = mkDefault true;
      settings = {
        listen_addresses = config.mine.dns.listenAddresses;
        ipv6_servers = true;
        require_dnssec = true;
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
            ipv6 = config.services.dnscrypt-proxy.settings.ipv6_servers;
            provider = config.mine.dns.provider;
          in
          [ ]
          ++ (lists.optional (provider == "quad9") "quad9-dnscrypt-ip4-filter-pri")
          ++ (lists.optional (provider == "quad9" && ipv6) "quad9-dnscrypt-ip6-filter-pri")
        ;
        cloaking_rules = pkgs.writeTextFile {
          name = "dnscrypt-proxy-cloaking-rules";
          text = builtins.concatStringsSep "\n"
            (mapAttrsToList
              (name: ips: concatStringsSep "\n" (map (ip: "${name} ${ip}") ips))
              config.mine.dns.hosts);
        };
      };
    };
  };
}
