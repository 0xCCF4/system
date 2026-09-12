{ lib
, config
, specialArgs
, luxAddr6For
, luxPublicNetwork6
, ...
}:
with lib;
{
  options.mine.services.jitsi.waitingRoomEnabled = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether guest (non-Matrix) call participants must be approved by a
      moderator before joining, vs. anyone with the call link joining
      immediately.
    '';
  };

  config =
    let
      hostConfig = config;

      jitsiDomain = config.mine.services.matrix.domains.jitsi;
      jvbPort = 10000;

      hostAddress6 = luxAddr6For "fc00::/64" "jitsi-veth-host";
      containerAddr = config.containers.jitsi.localAddress6;

      waitingRoomEnabled = config.mine.services.jitsi.waitingRoomEnabled;
    in
    {
      mine.services.caddyProxy.routes.jitsi = {
        upstream = "[${containerAddr}]:80";
        public = {
          enable = true;
          domain = jitsiDomain;
        };
      };

      containers.jitsi = {
        autoStart = config.mine.services.matrix.enable;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "jitsi";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/jitsi";
          mountPoint = "/var/lib/jitsi-meet";
          isReadOnly = false;
        };

        config = { config, ... }: {
          imports = [ (import ./container-common.nix { inherit (hostConfig.system) stateVersion; inherit hostAddress6; }) ];

          # jitsi-meet is nixpkgs-flagged insecure because its bundled JS
          # ships an in-call E2EE feature depending on deprecated
          # Olm library
          nixpkgs.config.allowInsecurePredicate = pkg: builtins.elem (lib.getName pkg) [ "jitsi-meet" ];

          networking.firewall.allowedTCPPorts = [ 80 ];
          networking.firewall.allowedUDPPorts = [ jvbPort ];

          services.jitsi-meet = {
            enable = true;
            hostName = jitsiDomain;

            nginx.enable = false;
            caddy.enable = true;

            secureDomain.enable = waitingRoomEnabled;

            videobridge.enable = true;
          };

          services.caddy.globalConfig = ''
            auto_https off
          '';

          services.caddy.virtualHosts."http://${jitsiDomain}".extraConfig =
            config.services.caddy.virtualHosts.${jitsiDomain}.extraConfig;

          # For dual stack support
          services.jitsi-videobridge = {
            openFirewall = false; # already opened above
            nat = {
              localAddress = containerAddr;
              publicAddress = hostConfig.mine.info.public.ipv4;
            };
          };
        };
      };
    };
}
