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
      matrixDomain = config.mine.services.matrix.domains.homeserver;

      turnSharedSecretIdent = noxa.lib.secrets.computeIdentifier {
        module = "matrix";
        ident = "turn-shared-secret";
        hosts = [ "lux" ];
      };
      turnSharedSecret = config.age.secrets.${turnSharedSecretIdent};

      mkCoturnContainer = { name, extraCoturnConfig ? "" }:
        let
          hostAddress6 = luxAddr6For "fc00::/64" "${name}-veth-host";
        in
        {
          autoStart = true;
          privateNetwork = true;
          inherit hostAddress6;
          localAddress6 = luxAddr6For luxPublicNetwork6 name;
          ephemeral = true;
          inherit specialArgs;

          bindMounts.turnSharedSecret = {
            hostPath = turnSharedSecret.path;
            mountPoint = "/run/secrets/turn-shared-secret";
            isReadOnly = true;
          };

          config = { pkgs, ... }: {
            imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

            networking.firewall.allowedTCPPorts = [ 3478 ];
            networking.firewall.allowedUDPPorts = [ 3478 ];
            networking.firewall.allowedUDPPortRanges = [{ from = 49160; to = 50159; }];

            services.coturn = {
              enable = true;
              realm = matrixDomain;
              use-auth-secret = true;
              static-auth-secret-file = "/run/turnserver/static-auth-secret";
              min-port = 49160;
              max-port = 50159;
              no-tcp-relay = true; # UDP only
              no-tls = true;
              no-dtls = true;
              extraConfig = extraCoturnConfig;
            };

            systemd.services.coturn.serviceConfig.ExecStartPre = mkBefore [
              "+${pkgs.writeShellScript "coturn-secret" ''
                install -o turnserver -g turnserver -m 0400 \
                  /run/secrets/turn-shared-secret /run/turnserver/static-auth-secret
              ''}"
            ];
          };
        };
    in
    {
      containers.matrix-coturn-v4 = mkCoturnContainer {
        name = "matrix-coturn-v4";
        
        extraCoturnConfig = ''
          external-ip=${config.mine.info.public.ipv4}
        '';
      };

      containers.matrix-coturn-v6 = mkCoturnContainer {
        name = "matrix-coturn-v6";
      };
    };
}
