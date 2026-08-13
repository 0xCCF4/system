{ lib, config, noxa, specialArgs, luxAddr6For, luxPublicNetwork6, ... }: with lib; {
  config =
    let
      domain = config.mine.info.domain;

      powerdnsApiKeySecret = config.age.secrets.${
      noxa.lib.secrets.computeIdentifier { module = "powerdns"; ident = "api-key"; hosts = [ "lux" ]; }
      };
    in
    {
      # The powerdns:api-key secret is declared in hosts/lux/powerdns.nix

      mine.services.caddyProxy.dns01 = {
        apiUrl = "http://[${config.containers.powerdns.localAddress6}]:8081";
        apiKeyEnvFile = "/run/caddy-secrets/powerdns.env";
      };

      mine.services.caddyProxy.routes.caldav = {
        # Radicale's real, routed IPv6 address
        upstream = "[${config.containers.radicale.localAddress6}]:5232";
        wireguardNetworks.cloud-admin.hostname = "todos.${domain}";
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
          system.stateVersion = config.system.stateVersion;
          networking.firewall.enable = true;

          services.caddy = {
            enable = true;
            package = pkgs.caddy.withPlugins {
              plugins = [ "github.com/caddy-dns/powerdns@v1.0.2" ];
              hash = lib.fakeHash;
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

          networking.firewall.allowedTCPPorts = [ 80 443 ];
          networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3
        };
      };
    };
}
