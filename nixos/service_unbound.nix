{ pkgs, lib, config, ... }: with lib; {
  options = with types; {
    mine.services.unbound = {
      enable = mkOption {
        type = bool;
        default = false;
        description = "Whether to enable unbound as public facing DNS resolver.";
      };
      openFirewall = mkOption {
        type = bool;
        default = true;
        description = "Whether to open firewall for DNS traffic.";
      };
    };
  };

  config = mkIf config.mine.services.unbound.enable {
    networking.firewall.allowedTCPPorts = mkIf config.mine.services.unbound.openFirewall [ config.services.unbound.settings.server.port ];
    networking.firewall.allowedUDPPorts = mkIf config.mine.services.unbound.openFirewall [ config.services.unbound.settings.server.port ];
    services.unbound = {
      enable = mkDefault true;
      settings = {
        # https://gist.github.com/MatthewVance/4842e0ad8305a09e87b95787e656243d
        server = {
          # General settings
          interface = [ "0.0.0.0" ];
          port = 53;
          do-ip4 = true;
          do-ip6 = true;

          cache-min-ttl = 60;
          cache-max-ttl = 86400;

          edns-buffer-size = 1472;
          rrset-roundrobin = true;

          # Access controls
          access-control = [
            "127.0.0.1 allow"
            "0.0.0.0/0 allow"
            "fe80::/10 allow"
            "::/0 refuse"
          ];

          # Privacy settings
          aggressive-nsec = true;
          delay-close = 1000;
          do-not-query-localhost = false; # DNScrypt will do the job
          neg-cache-size = "4M";
          qname-minimisation = true;

          # Security
          harden-algo-downgrade = true;
          harden-large-queries = true;
          harden-referral-path = false;
          harden-short-bufsize = true;
          hide-identity = true;
          hide-version = true;
          identity = "DNS";
          private-address = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "169.254.0.0/16"
            "fd00::/8"
            "fe80::/10"
            "::ffff:0:0/96"
          ];
          private-domain = [
            "lan."
            "vlan."
          ];
          domain-insecure = [ "lan." "vlan." ];
          ratelimit = 1000;
          unwanted-reply-threshold = 10000;
          val-clean-additional = true;

          # Performance
          prefetch = true;
          prefetch-key = true;
          minimal-responses = true;
          serve-expired = true;
          so-reuseport = true;

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
