{ lib
, self
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
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;
      matrixDomain = config.mine.services.matrix.domains.homeserver;
      turnDomain = config.mine.services.matrix.domains.turn;
      federationEnabled = config.mine.services.matrix.enableFederation;

      hostAddress6 = luxAddr6For "fc00::/64" "mtx-syn-veth-host";
      containerAddr = config.containers.mtx-syn.localAddress6;

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
        "64:ff9b::/96" # RFC6052 NAT64 well-known prefix bypassing the v4 entries above (this host NAT64s egress via Jool)
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

      containers.mtx-syn = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "mtx-syn";
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
                      names = [ "client" ] ++ optional federationEnabled "federation";
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
            } // optionalAttrs (!federationEnabled) {
              # Belt-and-suspenders: even with "federation" dropped from the
              # listener's resources above (which stops serving the federation
              # API), also refuse any outbound federation attempt this server
              # might make itself, while it's still being set up and tested.
              federation_domain_whitelist = [ ];
            };
          };
        };
      };
    };
}
