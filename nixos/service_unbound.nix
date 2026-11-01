{ pkgs
, lib
, config
, ...
}:
with lib;
{
  options = with types; {
    mine.services.unbound = {
      enable = mkOption {
        type = bool;
        default = false;
        description = ''
          Whether to enable unbound as the host's resolver, also for the local network
          (`lanInterfaces`, `lanNetworks`); everyone else is refused (unbound's default).
        '';
      };
      lanInterfaces = mkOption {
        type = listOf str;
        default = [ ];
        example = [ "lanLeft" ];
        description = ''
          Interfaces DNS (53) is open on for the local network. Nowhere else: no open resolver
          on the uplink, the hotspot, or for the WireGuard peers.
        '';
      };
      lanNetworks = mkOption {
        type = listOf str;
        default = [ ];
        example = [ "192.168.0.0/24" ];
        description = "Source networks allowed to query (besides loopback and link-local).";
      };
    };
  };

  config = mkIf config.mine.services.unbound.enable {
    networking.firewall.interfaces = genAttrs config.mine.services.unbound.lanInterfaces (_: {
      allowedTCPPorts = [ config.services.unbound.settings.server.port ];
      allowedUDPPorts = [ config.services.unbound.settings.server.port ];
    });
    services.unbound = {
      enable = mkDefault true;
      settings = {
        # https://gist.github.com/MatthewVance/4842e0ad8305a09e87b95787e656243d
        server = {
          # General settings
          # loopback and the LAN interfaces (by name: unbound binds their addresses), never
          # a wildcard; other modules add their addresses (e.g. the microVMs' resolver)
          interface = [ "127.0.0.1" "::1" ] ++ config.mine.services.unbound.lanInterfaces;
          port = 53;
          do-ip4 = true;
          do-ip6 = true;

          # (no cache-min-ttl: dnscrypt-proxy already keeps answers at least 60s)
          cache-max-ttl = 86400; # 24 hours

          # Access controls
          access-control = [
            "127.0.0.1 allow"
            "::1 allow"
          ]
          ++ map (network: "${network} allow") config.mine.services.unbound.lanNetworks;

          # Privacy settings
          aggressive-nsec = true;
          delay-close = 1000;
          do-not-query-localhost = false; # DNScrypt will do the job
          neg-cache-size = "4M";
          qname-minimisation = true;

          # Security
          harden-large-queries = true;
          harden-referral-path = false;
          hide-identity = true;
          hide-version = true;
          identity = "DNS";
          # DNS rebinding: answers from upstream pointing at non-global addresses are
          # dropped (as nixos/nat64.nix' nonGlobalIpv4, which DNS64 would else synthesize)
          private-address = [
            "0.0.0.0/8"
            "10.0.0.0/8"
            "100.64.0.0/10"
            "127.0.0.0/8"
            "169.254.0.0/16"
            "172.16.0.0/12"
            "192.0.0.0/24"
            "192.168.0.0/16"
            "198.18.0.0/15"
            "224.0.0.0/4"
            "240.0.0.0/4"
            "::/128"
            "::1/128"
            "fc00::/7"
            "fe80::/10"
            "::ffff:0:0/96"
          ];
          private-domain = [
            "lan."
            "vlan."
          ];
          domain-insecure = [
            "lan."
            "vlan."
          ];
          # per client, answers beyond it get no reply (a compromised client can't flood it)
          ip-ratelimit = 200;
          # reaching it wipes the cache (anti-poisoning), the documented value
          unwanted-reply-threshold = 10000000;
          val-clean-additional = true;

          # Performance
          prefetch = true;
          prefetch-key = true;
          serve-expired = true;

          # Log
          # log-queries = true;
          # log-replies = true;
          # log-local-actions = true;
          # log-servfail = true;
          # verbosity = 3;
        };
        remote-control.control-enable = false;
        forward-zone = [
          {
            name = ".";
            forward-tls-upstream = false; # Protected DNS
            forward-addr = config.mine.dns.upstreamResolvers;
          }
        ];
      };
    };
  };
}
