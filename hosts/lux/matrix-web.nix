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
      matrixDomain = config.mine.services.matrix.domains.homeserver;
      chatDomain = config.mine.services.matrix.domains.chat;
      adminDomain = config.mine.services.matrix.domains.admin;
      jitsiDomain = config.mine.services.matrix.domains.jitsi;

      hostAddress6 = luxAddr6For "fc00::/64" "mtx-web-veth-host";
      containerAddr = config.containers.mtx-web.localAddress6;
    in
    {
      mine.services.caddyProxy.routes = {
        elementWeb = {
          upstream = "[${containerAddr}]:80";
          public = {
            enable = true;
            domain = chatDomain;
          };
          anubis.enable = true;
        };
        # Synapse admin UI: only over cloud-admin (vhost bound to caddy's ULA). The same
        # vhost proxies the client and admin API to Synapse, so the UI never needs the
        # public homeserver domain, whose /_synapse/admin is closed (matrix-synapse.nix).
        ketesa = {
          upstream = "[${containerAddr}]:80";
          wireguardNetworks.cloud-admin.hostname = adminDomain;
          extraConfig = ''
            reverse_proxy /_matrix/* /_synapse/* [${config.containers.mtx-syn.localAddress6}]:8008
          '';
        };
      };

      containers.mtx-web = {
        autoStart = config.mine.services.matrix.enable;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "mtx-web";
        ephemeral = true;
        inherit specialArgs;
        # No persistent bindMounts -- both sites are static, purely
        # Nix-store-derived content, nothing user-generated to keep.

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 80 ];

          services.caddy = {
            enable = true;
            globalConfig = ''
              auto_https off
            '';

            virtualHosts."http://${chatDomain}".extraConfig = ''
              root * ${toString (pkgs.element-web.override {
                conf = {
                  default_server_config."m.homeserver" = {
                    base_url = "https://${matrixDomain}";
                    server_name = domain;
                  };
                  disable_custom_urls = true;
                  disable_guests = true;
                  jitsi.preferred_domain = jitsiDomain;
                  element_call.disable = true;
                };
              })}
              file_server
            '';

            virtualHosts."http://${adminDomain}".extraConfig = ''
              root * ${toString (pkgs.ketesa.withConfig {
                restrictBaseUrl = "https://${adminDomain}";
              })}
              file_server
            '';
          };
        };
      };
    };
}
