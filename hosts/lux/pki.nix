{ lib
, self
, config
, noxa
, pkgs
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
      hostAddress6 = luxAddr6For "fc00::/64" "pki-veth-host";

      pkiDir = ../../pki;
      rootCertPath = pkiDir + "/root-ca.pem";
      ocspCertPath = pkiDir + "/ocsp-responder-cert.pem";
      caConfigPath = pkiDir + "/ca-config.json";
      ledgerPath = ../../external/private/secrets/pki/issued-certs.json;
      crlPath = pkiDir + "/crl.pem";

      hasBootstrap =
        builtins.pathExists rootCertPath && builtins.pathExists ocspCertPath;

      caConfig = recursiveUpdate
        (builtins.fromJSON (builtins.readFile caConfigPath))
        {
          signing.default = {
            crl_url = "https://pki.${domain}/crl.pem";
            ocsp_url = "https://pki.${domain}/ocsp";
            issuer_urls = [ "https://pki.${domain}/root-ca.pem" ];
          };
        };
      caConfigFile = pkgs.writeText "pki-ca-config.json" (builtins.toJSON caConfig);

      ledgerFile =
        if builtins.pathExists ledgerPath
        then ledgerPath
        else pkgs.writeText "empty-issued-certs.json" (builtins.toJSON { certs = { }; });

      crlFile =
        if builtins.pathExists crlPath
        then crlPath
        else pkgs.writeText "empty-crl.pem" "";

      ocspKeyIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "pki";
        ident = "ocsp-responder-key";
        hosts = [ "lux" ];
      };
      ocspKeySecret = config.age.secrets.${ocspKeyIdentifier};

      pkiPackage = self.packages.${pkgs.system}.pki;

      certDbData = pkgs.runCommand "pki-certstore" { nativeBuildInputs = [ pkiPackage ]; } ''
        mkdir -p $out
        pki sync-db --ledger ${ledgerFile} --db $out/certstore.db --db-config $out/db.json
      '';
    in
    {
      noxa.secrets.def = [
        {
          ident = "ocsp-responder-key";
          module = "pki";
          hosts = [ "lux" ];
        }
      ];

      age.secrets.${ocspKeyIdentifier}.name = "pki-ocsp-responder-key";

      mine.services.caddyProxy.routes = optionalAttrs hasBootstrap {
        pki = {
          upstream = "[${config.containers.pki.localAddress6}]:8080";
          public = {
            enable = true;
            domain = "pki.${domain}";
          };
        };
      };

      containers.pki = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "pki";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/pki";
          mountPoint = "/var/lib/pki";
          isReadOnly = false;
        };
        bindMounts.ocspKey = {
          hostPath = ocspKeySecret.path;
          mountPoint = "/run/secrets/pki-ocsp-responder-key";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 8080 ];

          environment.systemPackages = [ pkgs.cfssl ];

          environment.etc = mkIf hasBootstrap {
            "pki/root-ca.pem".source = rootCertPath;
            "pki/ocsp-responder-cert.pem".source = ocspCertPath;
            "pki/crl.pem".source = crlFile;
          };

          systemd.services.pki-db-install = mkIf hasBootstrap {
            description = "Install the Nix-derived cfssl cert-store DB and refresh OCSP responses";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              install -m 0644 ${certDbData}/certstore.db /var/lib/pki/certstore.db
              install -m 0644 ${certDbData}/db.json /var/lib/pki/db.json
              ${pkgs.cfssl}/bin/cfssl ocsprefresh \
                -ca /etc/pki/root-ca.pem \
                -responder /etc/pki/ocsp-responder-cert.pem \
                -responder-key /run/secrets/pki-ocsp-responder-key \
                -db-config /var/lib/pki/db.json
            '';
          };

          systemd.services.cfssl-ocspserve = mkIf hasBootstrap {
            description = "cfssl OCSP responder";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" "pki-db-install.service" ];
            requires = [ "pki-db-install.service" ];
            serviceConfig = {
              ExecStart = ''
                ${pkgs.cfssl}/bin/cfssl ocspserve -address 127.0.0.1 -port 8889 \
                  -db-config /var/lib/pki/db.json \
                  -loglevel 1
              '';
              Restart = "always";
            };
          };

          systemd.timers.cfssl-ocsprefresh = mkIf hasBootstrap {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "1h";
              OnUnitActiveSec = "1h";
            };
          };
          systemd.services.cfssl-ocsprefresh = mkIf hasBootstrap {
            description = "Refresh pre-signed OCSP responses";
            after = [ "pki-db-install.service" ];
            requires = [ "pki-db-install.service" ];
            serviceConfig.Type = "oneshot";
            script = ''
              ${pkgs.cfssl}/bin/cfssl ocsprefresh \
                -ca /etc/pki/root-ca.pem \
                -responder /etc/pki/ocsp-responder-cert.pem \
                -responder-key /run/secrets/pki-ocsp-responder-key \
                -db-config /var/lib/pki/db.json
            '';
          };

          services.caddy = mkIf hasBootstrap {
            enable = true;
            virtualHosts.":8080" = {
              extraConfig = ''
                handle /ocsp* {
                  reverse_proxy 127.0.0.1:8889
                }
                handle {
                  root * /etc/pki
                  file_server
                }
              '';
            };
          };
        };
      };
    };
}
