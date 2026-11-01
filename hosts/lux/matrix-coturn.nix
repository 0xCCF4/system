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

      # Relaying is for peers on the internet: no relay (SSRF) to internal, loopback, link-local
      # or the fleet's addresses, neither directly nor as IPv4-mapped or through NAT64
      # (64:ff9b::/96 is how mtx-co-v4 reaches IPv4 peers, so only its non-global part)
      net = noxa.lib.net;
      # coturn wants ranges ("first-last"), derived from the prefixes
      range4 = prefix: "${(net.decompose prefix).networkNoMask}-${net.broadcast prefix}";
      range6 = prefix: "${(net.decompose prefix).networkNoMask}-${net.lastHost prefix}";
      # not globally reachable IPv4 (as nixos/nat64.nix' nonGlobalIpv4)
      nonGlobal4 = [
        "0.0.0.0/8"
        "10.0.0.0/8"
        "100.64.0.0/10"
        "127.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.0.0.0/24"
        "192.168.0.0/16"
        "198.18.0.0/15"
        "224.0.0.0/4"
        "240.0.0.0/4"
      ];
      # Quotas: allocations per credential, all allocations (of the 1000 relay ports, the
      # rest stays in reserve), bandwidth per session in bytes/s (~5 Mbit/s, enough for video)
      quotas = ''
        user-quota=8
        total-quota=900
        max-bps=625000
      '';

      deniedPeers = "no-multicast-peers\n" + concatMapStrings (range: "denied-peer-ip=${range}\n") (
        map range4 nonGlobal4
        # the same through the NAT64 (64:ff9b::<IPv4>; nat64Address refuses non-global
        # IPv4 under the well-known prefix, RFC 6052 3.1, so composed here)
        ++ map (prefix: "64:ff9b::${(net.decompose prefix).networkNoMask}-64:ff9b::${net.broadcast prefix}") nonGlobal4
        ++ map range6 [
          "::/127" # unspecified, loopback
          "::ffff:0:0/96" # IPv4-mapped
          "64:ff9b:1::/48" # local-use NAT64
          "fc00::/7" # ULA, incl. the fleet's
          "fe80::/10" # link-local
          "ff00::/8" # multicast
          luxPublicNetwork6 # lux and its containers
        ]
      );

      mkCoturnContainer = { name, extraCoturnConfig ? "" }:
        let
          hostAddress6 = luxAddr6For "fc00::/64" "${name}-veth-host";
          localAddress6 = luxAddr6For luxPublicNetwork6 name;
        in
        {
          autoStart = config.mine.services.matrix.enable;
          privateNetwork = true;
          inherit hostAddress6 localAddress6;
          ephemeral = true;
          inherit specialArgs;

          bindMounts.turnSharedSecret = {
            hostPath = turnSharedSecret.path;
            mountPoint = "/run/secrets/turn-shared-secret";
            isReadOnly = true;
          };

          config = { pkgs, ... }: {
            imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; }) ];

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
              listening-ips = [ "::" ];
              relay-ips = [ localAddress6 ];
              no-cli = true; # telnet admin console, unused
              extraConfig = quotas + deniedPeers + extraCoturnConfig;
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
      containers.mtx-co-v4 = mkCoturnContainer {
        name = "mtx-co-v4";

        extraCoturnConfig = ''
          external-ip=${config.mine.info.public.ipv4}
        '';
      };

      containers.mtx-co-v6 = mkCoturnContainer {
        name = "mtx-co-v6";
      };
    };
}
