{ lib
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
      domain = config.mine.info.domain;

      hostAddress6 = luxAddr6For "fc00::/64" "radicale-veth-host";
    in
    {
      mine.services.caddyProxy.routes.caldav = {
        upstream = "[${config.containers.radicale.localAddress6}]:5232";
        wireguardNetworks.cloud-admin.hostname = "todos.${domain}";
        public = {
          enable = true;
          domain = "todos.${domain}";
        };
      };

      containers.radicale = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "radicale";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/radicale";
          mountPoint = "/var/lib/radicale";
          isReadOnly = false;
        };

        bindMounts.usersFile = {
          hostPath = toString ../../external/private/hosts/lux-radicale-htpasswd;
          mountPoint = "/var/lib/radicale/users";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 5232 ];

          services.radicale = {
            enable = true;
            settings = {
              server.hosts = [ "[::]:5232" ];
              auth = {
                type = "htpasswd";
                htpasswd_filename = "/var/lib/radicale/users";
                htpasswd_encryption = "bcrypt";
              };
              storage.filesystem_folder = "/var/lib/radicale/collections";
            };
          };
        };
      };
    };
}
