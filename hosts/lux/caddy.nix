{ lib
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
      domain = config.mine.info.domain;

      powerdnsApiKeySecret =
        config.age.secrets.${
        noxa.lib.secrets.computeIdentifier {
          module = "powerdns";
          ident = "api-key";
          hosts = [ "lux" ];
        }
        };
    in
    {
      mine.services.caddyProxy.dns01 = {
        apiKeyEnvFile = "/run/caddy-secrets/powerdns.env";
      };

      containers.caddy = {
        autoStart = true;
        privateNetwork = true;
        hostAddress6 = luxAddr6For "fc00::/64" "caddy-veth-host";
        localAddress6 = luxAddr6For luxPublicNetwork6 "caddy";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.caddyData = {
          hostPath = "/persist/data/caddy";
          mountPoint = "/var/lib/caddy";
          isReadOnly = false;
        };
        bindMounts.powerdnsApiKey = {
          hostPath = powerdnsApiKeySecret.path;
          mountPoint = "/run/secrets/powerdns-api-key";
          isReadOnly = true;
        };

        config = { pkgs, lib, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; }) ];

          services.caddy = {
            enable = true;
            package = pkgs.caddy.withPlugins {
              plugins = [ "github.com/caddy-dns/powerdns@v1.0.2" ];
              hash = "sha256-8ky7G/5v+iKIiOWHm1x536EpEw+y1hDMioSSktr+f3A=";
            };
            globalConfig = ''
              email security@${domain}
            '';
          };

          systemd.services.caddy.serviceConfig.RuntimeDirectory = "caddy-secrets";
          systemd.services.caddy.serviceConfig.ExecStartPre = [
            "+${pkgs.writeShellScript "caddy-powerdns-env" ''
              echo "POWERDNS_API_KEY=$(cat /run/secrets/powerdns-api-key)" > /run/caddy-secrets/powerdns.env
              chown caddy:caddy /run/caddy-secrets/powerdns.env
              chmod 600 /run/caddy-secrets/powerdns.env
            ''}"
          ];

          networking.firewall.allowedTCPPorts = [
            80
            443
          ];
          networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3
        };
      };
    };
}
