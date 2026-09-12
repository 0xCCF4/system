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

        bindMounts.anubisEd25519Key = {
          hostPath = anubisEd25519KeySecret.path;
          mountPoint = "/run/secrets/anubis-ed25519-key";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

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
