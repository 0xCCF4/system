{ lib
, self
, config
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
    in
    {
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

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

          services.caddy = {
            enable = true;
            globalConfig = ''
              email security@${domain}
              acme_ca https://acme-v02.api.letsencrypt.org/directory
            '';
          };

          networking.firewall.allowedTCPPorts = [
            80
            443
          ];
          networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3
        };
      };
    };
}
