{ inputs
, options
, pkgs
, lib
, config
, noxa
, adblock
, ...
}:
with lib;
{
  options.mine.dns =
    with types;
    with noxa.lib.net.types;
    {
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
          "*.example[0-9].*" = [
            "127.0.0.1"
            "127.0.0.2"
          ];
        };
      };
      listenAddresses = mkOption {
        type = listOf str;
        default = [
          "127.0.0.60:54"
          "[::1]:54"
        ];
      };
      blocklist = {
        enable = mkOption {
          type = bool;
          default = true;
          description = "Block Steven Black's hosts list in dnscrypt-proxy.";
        };
        fakenews = mkEnableOption "the fakenews extension" // { default = true; };
        gambling = mkEnableOption "the gambling extension" // { default = true; };
        porn = mkEnableOption "the porn extension" // { default = true; };
        social = mkEnableOption "the social extension" // {
          default = !(config.mine.presets.isWorkstation or false);
        };
      };
      upstreamResolvers = mkOption {
        type = listOf str;
        readOnly = true;
        default = map
          (
            addr:
            let
              split = splitString ":" addr;
              noBrackets = map (s: lib.replaceStrings [ "[" "]" ] [ "" "" ] s) split;
              lastElement = last noBrackets;
              beforeElements = sublist 0 (length noBrackets - 1) noBrackets;
              before = concatStringsSep ":" beforeElements;
            in
            "${before}@${lastElement}"
          )
          config.mine.dns.listenAddresses;
        description = "The upstream DNS resolvers to use. Port is seperated by # instead of : .";
      };
    };

  config = mkIf config.mine.dns.enable (mkMerge [
    # only where impermanence is imported (not in the microVMs)
    (optionalAttrs (options ? environment.persistence) (
      let
        persistResolverCache = config.mine.persistence.enable && config.services.dnscrypt-proxy.enable;
      in
      {
        # keep the resolver list across reboots
        environment.persistence.${config.mine.persistence.cacheDirectory}.directories =
          mkIf persistResolverCache [
            { directory = "/var/cache/private/dnscrypt-proxy"; mode = "0700"; }
          ];
        systemd.tmpfiles.rules = mkIf persistResolverCache [ "d /var/cache/private 0700 root root -" ];
      }
    ))
    {

      networking = {
        networkmanager.dns = "systemd-resolved";
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

      services.dnscrypt-proxy =
        let
          ipv6 = true;
          # Not via /etc/hosts (the upstream nixosModule): its ~150k names end
          # up in every shell's hostname completion.
          blocklist = config.mine.dns.blocklist;
          extensions = filter (ext: blocklist.${ext}) [ "fakenews" "gambling" "porn" "social" ];
          hostsFile = "${adblock}/"
            + optionalString (extensions != [ ]) "alternates/${concatStringsSep "-" extensions}/"
            + "hosts";
          # `=name` is exact match
          blockedNames = pkgs.runCommand "dnscrypt-proxy-blocked-names" { } ''
            ${pkgs.gawk}/bin/awk '$1 == "0.0.0.0" && $2 != "0.0.0.0" { print "=" $2 }' ${hostsFile} > $out
          '';
        in
        {
          enable = mkDefault true;
          settings = {
            listen_addresses = config.mine.dns.listenAddresses;
            ipv6_servers = ipv6;
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
                provider = config.mine.dns.provider;
              in
              [ ]
              ++ (lists.optional (provider == "quad9") "quad9-dnscrypt-ip4-filter-pri")
              ++ (lists.optional (provider == "quad9" && ipv6) "quad9-dnscrypt-ip6-filter-pri");
            blocked_names = mkIf blocklist.enable { blocked_names_file = blockedNames; };
            cloaking_rules = pkgs.writeTextFile {
              name = "dnscrypt-proxy-cloaking-rules";
              text = builtins.concatStringsSep "\n" (
                mapAttrsToList
                  (
                    name: ips: concatStringsSep "\n" (map (ip: "${name} ${ip}") ips)
                  )
                  config.mine.dns.hosts
              );
            };
          };
        };
    }
  ]);
}
