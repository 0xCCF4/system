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
      matrixDomain = config.mine.services.matrix.domains.homeserver;
      chatDomain = config.mine.services.matrix.domains.chat;
      adminDomain = config.mine.services.matrix.domains.admin;

      hostAddress6 = luxAddr6For "fc00::/64" "matrix-web-veth-host";
      containerAddr = config.containers.matrix-web.localAddress6;
    in
    {
      mine.services.caddyProxy.routes = {
        elementWeb = {
          upstream = "[${containerAddr}]:80";
          public = {
            enable = true;
            domain = chatDomain;
          };
        };
        ketesa = {
          upstream = "[${containerAddr}]:80";
          public = {
            enable = true;
            domain = adminDomain;
          };
        };
      };

      containers.matrix-web = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "matrix-web";
        ephemeral = true;
        inherit specialArgs;
        # No persistent bindMounts -- both sites are static, purely
        # Nix-store-derived content, nothing user-generated to keep.

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 80 ];

          services.caddy = {
            enable = true;
            globalConfig = ''
              auto_https off
            '';

            virtualHosts.${chatDomain}.extraConfig = ''
              root * ${toString (pkgs.element-web.override {
                conf = {
                  default_server_config."m.homeserver" = {
                    base_url = "https://${matrixDomain}";
                    server_name = domain;
                  };
                  disable_custom_urls = true;
                  disable_guests = true;
                };
              })}
              file_server
            '';

            virtualHosts.${adminDomain}.extraConfig = ''
              root * ${toString pkgs.ketesa}
              file_server
            '';
          };
        };
      };
    };
}
