{ lib
, self
, config
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

      hostAddress6 = luxAddr6For "fc00::/64" "caddy-veth-host";

      anubisEd25519KeyIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "anubis";
        ident = "ed25519-key";
        hosts = [ "lux" ];
      };
      anubisEd25519KeySecret = config.age.secrets.${anubisEd25519KeyIdentifier};

      # Every anubis-<routeName> systemd unit that needs the signing key
      # (see LoadCredential wiring below).
      anubisRouteNames = builtins.attrNames
        (filterAttrs (_: route: route.anubis.enable) config.mine.services.caddyProxy.routes);
    in
    {
      age.generators.hex64 = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -hex 32";

      noxa.secrets.def = [
        {
          ident = "ed25519-key";
          module = "anubis";
          hosts = [ "lux" ];
          generator.script = "hex64";
        }
      ];

      age.secrets.${anubisEd25519KeyIdentifier}.name = "anubis-ed25519-key";

      # wireguard routes (mine.services.caddyProxy.routes.*.wireguardNetworks) via its ULA
      mine.guestUla.containers = [ "caddy" ];

      # (caddy chowns it inside the container, LogsDirectory)
      systemd.tmpfiles.rules = [ "d /var/log/containers/caddy 0750 root root -" ];

      # ACME HTTP-01: Let's Encrypt validates from several, unpublished regions, also
      # outside the geo-block list. Port 80 only redirects to HTTPS (geo-blocked) and answers
      # ACME challenges, asserted in the container below.
      mine.services.geoBlock.exemptPorts.tcp = [ 80 ];

      containers.caddy = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "caddy";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.caddyData = {
          hostPath = "/persist/data/caddy";
          mountPoint = "/var/lib/caddy";
          isReadOnly = false;
        };

        # the access logs survive container restarts (/var/log is persisted)
        bindMounts.logs = {
          hostPath = "/var/log/containers/caddy";
          mountPoint = "/var/log/caddy";
          isReadOnly = false;
        };

        bindMounts.anubisEd25519Key = {
          hostPath = anubisEd25519KeySecret.path;
          mountPoint = "/run/secrets/anubis-ed25519-key";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [
            (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; })
            # port 80 is not geo-blocked: plain HTTP sites may only redirect or answer ACME
            # challenges (the HTTPS sites get caddy's automatic redirect)
            ({ config, lib, ... }: {
              assertions = lib.mapAttrsToList
                (name: vhost: {
                  assertion = !(lib.hasPrefix "http://" vhost.hostName)
                    || lib.hasInfix "redir https://" vhost.extraConfig
                    || lib.hasInfix "/.well-known/acme-challenge/" vhost.extraConfig;
                  message = "caddy: ${name} serves plain HTTP, port 80 is only for redirects to HTTPS and ACME challenges.";
                })
                config.services.caddy.virtualHosts;
            })
            # Bitwarden clients send their access token in the query (websocket), it does
            # not belong in the access logs (vhosts with an own logFormat keep it)
            ({ lib, ... }: {
              options.services.caddy.virtualHosts = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule ({ config, ... }: {
                  logFormat = lib.mkDefault ''
                    output file /var/log/caddy/access-${lib.replaceStrings [ "/" " " ] [ "_" "_" ] config.hostName}.log
                    format filter {
                      request>uri query {
                        replace access_token REDACTED
                      }
                    }
                  '';
                }));
              };
            })
          ];

          services.caddy = {
            enable = true;
            globalConfig = ''
              email security@${domain}
              acme_ca https://acme-v02.api.letsencrypt.org/directory
            '';
          };

          services.anubis.defaultOptions.settings.ED25519_PRIVATE_KEY_HEX_FILE =
            "%d/anubis-ed25519-key";

          systemd.services = genAttrs
            (map (routeName: "anubis-${routeName}") anubisRouteNames)
            (_: {
              serviceConfig.LoadCredential = "anubis-ed25519-key:/run/secrets/anubis-ed25519-key";
            });

          networking.firewall.allowedTCPPorts = [
            80
            443
          ];
          networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3
        };
      };
    };
}
