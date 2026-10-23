{ lib
, self
, config
, vota
, noxa
, specialArgs
, luxAddr6For
, luxPublicNetwork6
, ...
}:
with lib;
{
  config =
    let
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;
      pollDomain = "poll.${domain}";

      hostAddress6 = luxAddr6For "fc00::/64" "vota-veth-host";
      votaPort = 8080;

      caddyLocalAddress6 = config.containers.caddy.localAddress6;

      # Shared with mx's workstations (defined in users/mx.nix), where
      # home/vota.nix uses it as the client's default Admin Token.
      adminTokenIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "vota";
        ident = "mx-admin-token";
      };
      adminTokenSecret = config.age.secrets.${adminTokenIdentifier};

      tokenRegexp = ''"(/|%2[Ff])b(/|%2[Ff])[^/?&#%]*" "''${1}b''${2}REDACTED"'';
    in
    {
      # systemd-nspawn's --bind(-ro)= parses its argument as a colon-separated
      # tuple, remove the colons (see hosts/lux/powerdns.nix for precedent).
      age.secrets.${adminTokenIdentifier}.name = "vota-admin-token";

      mine.services.caddyProxy.routes.vota = {
        upstream = "[${config.containers.vota.localAddress6}]:${toString votaPort}";
        public = {
          enable = true;
          domain = pollDomain;
        };
        anubis = {
          enable = true;
          onlyPaths = [ "/b/*" ];
        };
        # The module's defaults would override Vota's own, stricter
        # `Referrer-Policy: no-referrer` (Caddy defers the whole header block
        # because of `-Server`), so set only HSTS and `-Server` below.
        hardenHeaders.enable = false;
      };

      containers.caddy.config = {
        services.caddy = {
          virtualHosts.${pollDomain} = {
            extraConfig = ''
              header {
                Strict-Transport-Security "max-age=31536000"
                -Server
              }
            '';
            
            logFormat = ''
              output file /var/log/caddy/access-${pollDomain}.log {
                mode 0600
              }
              format filter {
                request>uri regexp ${tokenRegexp}
                request>headers>Referer delete
                resp_headers>Location regexp ${tokenRegexp}
              }
            '';
          };

          virtualHosts."http://${pollDomain}" = {
            logFormat = null;
            extraConfig = ''
              redir https://{host}{uri} 308
            '';
          };

          logFormat = ''
            level ERROR
            format filter {
              request>uri regexp ${tokenRegexp}
            }
          '';
        };

        services.anubis.instances.vota.settings.SLOG_LEVEL = "ERROR";
      };

      systemd.tmpfiles.rules = [ "d /persist/data/vota 0700 root root -" ];

      containers.vota = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "vota";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/vota";
          mountPoint = "/var/lib/private/vota";
          isReadOnly = false;
        };

        bindMounts.adminToken = {
          hostPath = adminTokenSecret.path;
          mountPoint = "/run/secrets/vota-admin-token";
          isReadOnly = true;
        };

        config = { ... }: {
          imports = [
            (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; })
            vota.nixosModules.vota
          ];

          networking.firewall.allowedTCPPorts = [ votaPort ];

          services.vota = {
            enable = true;
            adminTokenFiles = [ "/run/secrets/vota-admin-token" ];
            settings = {
              public_base_url = "https://${pollDomain}/";
              
              bind_address = "::";
              port = votaPort;
              trusted_proxies = [ "${caddyLocalAddress6}/128" ];
            };
          };
        };
      };
    };
}
