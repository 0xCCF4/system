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
    in
    {
      mine.services.caddyProxy.routes.caldav = {
        upstream = "[${config.containers.radicale.localAddress6}]:5232";
        wireguardNetworks.cloud-admin.hostname = "todos.${domain}";
      };

      containers.radicale = {
        autoStart = true;
        privateNetwork = true;
        hostAddress6 = luxAddr6For "fc00::/64" "radicale-veth-host";
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
          system.stateVersion = config.system.stateVersion;
          networking.firewall.enable = true;
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
