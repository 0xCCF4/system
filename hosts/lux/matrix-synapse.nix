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
      matrixDomain = config.mine.services.matrix.domains.homeserver;
      turnDomain = config.mine.services.matrix.domains.turn;

      hostAddress6 = luxAddr6For "fc00::/64" "matrix-synapse-veth-host";
      containerAddr = config.containers.matrix-synapse.localAddress6;

      # Prevents url_preview fetches from reaching
      # internal infrastructure (SSRF).
      urlPreviewIpBlacklist = [
        "0.0.0.0/8"
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "169.254.0.0/16"
        "::1/128"
        "::ffff:0:0/96" # IPv4-mapped IPv6 literals bypassing the v4 entries above
        "fe80::/10"
        "fc00::/7"
        luxPublicNetwork6
      ];

      secretIdent = ident: noxa.lib.secrets.computeIdentifier {
        module = "matrix";
        inherit ident;
        hosts = [ "lux" ];
      };

      secretNames = [
        "registration-shared-secret"
        "macaroon-secret-key"
        "form-secret"
        "turn-shared-secret"
      ];

      secretPath = ident: config.age.secrets.${secretIdent ident}.path;

      # In cotainer bind mount path of secret
      secretMountPath = ident: "/run/secrets/matrix-${ident}";
      secretRuntimePath = ident: "/run/matrix-synapse/secret-${ident}";
    in
    {
      noxa.secrets.def = map
        (ident: {
          inherit ident;
          module = "matrix";
          hosts = [ "lux" ];
          generator.script = "alnum";
        })
        secretNames;

      age.secrets = listToAttrs (
        map (ident: nameValuePair (secretIdent ident) { name = "matrix-${ident}"; }) secretNames
      );

      mine.services.caddyProxy.routes = {
        # Top level domain: only exists to carry the `.well-known/matrix/*`
        # delegation for server_name = "${domain}" while the actual homeserver
        # runs on matrixDomain.
        matrixWellKnown = {
          upstream = "[${containerAddr}]:8008";
          public = {
            enable = true;
            domain = domain;
          };
          matrixWellKnownClient.enable = true;
          matrixWellKnownClient.content = builtins.toJSON {
            "m.homeserver".base_url = "https://${matrixDomain}";
            "im.vector.riot.jitsi".preferredDomain = config.mine.services.matrix.domains.jitsi;
            "cc.etke.ketesa".restrictBaseUrl = "https://${matrixDomain}";
          };
        };

        matrixHomeserver = {
          upstream = "[${containerAddr}]:8008";
          public = {
            enable = true;
            domain = matrixDomain;
          };
        };
      };

      containers.matrix-synapse = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "matrix-synapse";
        ephemeral = true;
        inherit specialArgs;

        bindMounts = {
          data = {
            hostPath = "/persist/data/matrix/synapse";
            mountPoint = "/var/lib/matrix-synapse";
            isReadOnly = false;
          };
          postgresData = {
            hostPath = "/persist/data/matrix/postgres";
            mountPoint = "/var/lib/postgresql";
            isReadOnly = false;
          };
        } // listToAttrs (
          map
            (ident: nameValuePair "secret-${ident}" {
              hostPath = secretPath ident;
              mountPoint = secretMountPath ident;
              isReadOnly = true;
            })
            secretNames
        );

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 8008 ];

          services.postgresql = {
            enable = true;
            ensureDatabases = [ "matrix-synapse" ];
            ensureUsers = [
              {
                name = "matrix-synapse";
                ensureDBOwnership = true;
              }
            ];
          };

          systemd.services.matrix-synapse = {
            after = [ "postgresql.service" ];
            requires = [ "postgresql.service" ];
            serviceConfig.ExecStartPre = [
              "+${pkgs.writeShellScript "matrix-synapse-secrets" ''
                set -e
                ${concatStringsSep "\n" (map
                  (ident: ''
                    install -o matrix-synapse -g matrix-synapse -m 0400 \
                      ${secretMountPath ident} ${secretRuntimePath ident}
                  '')
                  secretNames)}
              ''}"
            ];
          };

          services.matrix-synapse = {
            enable = true;
            extraConfigFiles = [ ];

            settings = {
              server_name = domain;
              public_baseurl = "https://${matrixDomain}/";
              serve_server_wellknown = true;

              listeners = [
                {
                  port = 8008;
                  bind_addresses = [ "::" ];
                  type = "http";
                  tls = false;
                  x_forwarded = true;
                  resources = [
                    {
                      names = [ "client" "federation" ];
                      compress = false;
                    }
                  ];
                }
              ];

              database = {
                name = "psycopg2";
                args = {
                  user = "matrix-synapse";
                  database = "matrix-synapse";
                  host = "/run/postgresql";
                };
              };

              # Closed registration, gated by single-use tokens
              enable_registration = true;
              registration_requires_token = true;

              url_preview_enabled = true;
              url_preview_ip_range_blacklist = urlPreviewIpBlacklist;
              max_upload_size = "50M";

              turn_uris = [
                "turn:${turnDomain}:3478?transport=udp"
                "turn:${turnDomain}:3478?transport=tcp"
              ];
              turn_shared_secret_path = secretRuntimePath "turn-shared-secret";
              turn_user_lifetime = "1h";
              turn_allow_guests = false;

              registration_shared_secret_path = secretRuntimePath "registration-shared-secret";
              macaroon_secret_key_path = secretRuntimePath "macaroon-secret-key";
              form_secret_path = secretRuntimePath "form-secret";
            };
          };
        };
      };
    };
}
