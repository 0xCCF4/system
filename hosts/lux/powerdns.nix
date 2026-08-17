{ lib
, config
, noxa
, specialArgs
, dns
, luxAddr6For
, luxPublicNetwork6
, ...
}:
with lib;
{
  config =
    let
      domain = config.mine.info.domain;

      powerdnsApiKeyIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "powerdns";
        ident = "api-key";
        hosts = [ "lux" ];
      };

      powerdnsApiKeySecret = config.age.secrets.${powerdnsApiKeyIdentifier};

      zoneRecords = with dns.lib.combinators; {
        SOA = {
          nameServer = "ns1.${domain}.";
          adminEmail = "security@${domain}";
          serial = 1;
        };
        A = [ config.mine.info.public.ipv4 ];
        AAAA = [ config.mine.info.public.ipv6 ];
        subdomains = {
          mail = {
            AAAA = [ config.containers.mailserver.localAddress6 ];
            A = [ config.mine.info.public.ipv4 ];
          };
          ns1 = {
            A = [ config.mine.info.public.ipv4 ];
            AAAA = [ config.containers.powerdns.localAddress6 ];
          };
          todos = {
            A = [ config.mine.info.public.ipv4 ];
            AAAA = [ config.containers.caddy.localAddress6 ];
          };
        };
        MX = [
          {
            preference = 10;
            exchange = "mail.${domain}.";
          } # self-hosted, primary
          {
            preference = 20;
            exchange = "smtpin.rzone.de.";
          } # STRATO, fallback
        ];
        NS = [ "ns1.${domain}." "sns.serverkompetenz.de." ];
      };

      zoneFile = toString (dns.lib.evalZone domain zoneRecords);
      zoneFilePath = builtins.toFile "${domain}.zone" zoneFile;
    in
    {
      noxa.secrets.def = [
        {
          ident = "api-key";
          module = "powerdns";
          hosts = [ "lux" ];
          generator.script = "alnum";
        }
      ];

      # systemd-nspawn's --bind(-ro)= parses its argument as a colon-separated
      # tuple, remove the colons
      age.secrets.${powerdnsApiKeyIdentifier}.name = "powerdns-api-key";

      mine.services.caddyProxy.dns01 = {
        apiUrl = "http://[${config.containers.powerdns.localAddress6}]:8081";
      };

      containers.powerdns = {
        autoStart = true;
        privateNetwork = true;
        hostAddress6 = luxAddr6For "fc00::/64" "powerdns-veth-host";
        localAddress6 = luxAddr6For luxPublicNetwork6 "powerdns";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/powerdns";
          mountPoint = "/var/lib/powerdns";
          isReadOnly = false;
        };
        bindMounts.apiKey = {
          hostPath = powerdnsApiKeySecret.path;
          mountPoint = "/run/secrets/powerdns-api-key";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; }) ];

          networking.firewall.allowedTCPPorts = [ 53 ];
          networking.firewall.allowedUDPPorts = [ 53 ];

          environment.systemPackages = [ pkgs.pdns ];

          environment.etc."powerdns/zones/${domain}.zone".source = zoneFilePath;
          environment.etc."powerdns/named.conf".text = ''
            zone "${domain}" {
              type master;
              file "/etc/powerdns/zones/${domain}.zone";
            };
          '';

          services.powerdns = {
            enable = true;
            extraConfig = ''
              launch=bind
              bind-config=/etc/powerdns/named.conf
              bind-dnssec-db=/var/lib/powerdns/dnssec.sqlite3

              # IPv6-only
              local-address=::

              api=yes
              webserver=yes
              webserver-address=::
              webserver-port=8081
              # Only caddy calls this (DNS-01 challenges)
              webserver-allow-from=${config.containers.caddy.localAddress6}/128
              include-dir=/run/pdns/secrets

              # Strato's secondary DNS
              allow-axfr-ips=64:ff9b::81.169.148.38
              also-notify=64:ff9b::81.169.148.38
            '';
          };

          systemd.services.pdns.serviceConfig.ExecStartPre = [
            "+${pkgs.writeShellScript "pdns-init-dnssec-db" ''
              mkdir -p /run/pdns/secrets
              # SQLite needs write access to the *directory* (to create
              # journal/WAL files), not just the db file itself, or pdns_server
              # (running as user pdns) fails with "attempt to write a
              # readonly database" even though the file is chowned below.
              chown pdns:pdns /var/lib/powerdns
              db=/var/lib/powerdns/dnssec.sqlite3
              if [ ! -f "$db" ]; then
                ${pkgs.pdns}/bin/pdnsutil create-bind-db "$db"
                chown pdns:pdns "$db"
              fi
            ''}"
            "+${pkgs.writeShellScript "pdns-api-key-conf" ''
              mkdir -p /run/pdns/secrets
              echo "api-key=$(cat /run/secrets/powerdns-api-key)" > /run/pdns/secrets/api-key.conf
              chown pdns:pdns /run/pdns/secrets/api-key.conf
              chmod 600 /run/pdns/secrets/api-key.conf
            ''}"
          ];

          # One-time manual step: after first deploy,
          # `pdnsutil secure-zone <domain>` inside this container to generate DNSSEC
          # keys and start signing, then publish the resulting DS record at the
          # registrar. `pdnsutil` ships with the powerdns package.
        };
      };
    };
}
