{ lib
, self
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
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;

      hostAddress6 = luxAddr6For "fc00::/64" "powerdns-veth-host";

      ednsCookieSecretIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "powerdns";
        ident = "edns-cookie-secret";
        hosts = [ "lux" ];
      };

      ednsCookieSecret = config.age.secrets.${ednsCookieSecretIdentifier};

      tsigKeySecretIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "powerdns";
        ident = "tsig-key";
        hosts = [ "lux" ];
      };

      tsigKeySecret = config.age.secrets.${tsigKeySecretIdentifier};
      tsigKeyName = "${domain}.${config.mine.info.public.ipv4}";

      hetznerSecondariesV4 = [ "213.239.242.238" "213.133.100.103" "193.47.99.3" ];
      hetznerSecondariesV6 = [ "2a01:4f8:0:a101::a:1" "2a01:4f8:0:1::5ddc:2" "2001:67c:192c::add:a3" ];
      hetznerSecondaries = (map (ip: "64:ff9b::${ip}") hetznerSecondariesV4) ++ hetznerSecondariesV6;

      zoneRecords = with dns.lib.combinators; {
        TTL = 86400; # 24h
        SOA = {
          nameServer = "ns1.${domain}.";
          adminEmail = "security@${domain}";
          # Must increase (RFC 1982) whenever the zone changes, or secondaries
          # ignore our NOTIFYs and never re-pull via AXFR.
          # self.lastModified is the flake's last-commit/mtime epoch, so it's
          # deterministic and only ever moves forward.
          serial = self.lastModified / 60;
          refresh = 86400; # 24h
          retry = 14400; # 4h
          expire = 604800; # 7 days
          minimum = 3600; # 1h
        };
        A = [ config.mine.info.public.ipv4 ];
        AAAA = [ config.mine.info.public.ipv6 ];
        TXT = [ "v=spf1 mx include:_spf.strato.com -all" ];
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
          vault = {
            A = [ config.mine.info.public.ipv4 ];
            AAAA = [ config.containers.caddy.localAddress6 ];
          };
        } // {
          ${removeSuffix ".${domain}" config.mine.services.matrix.domains.turn} = {
            A = [ config.mine.info.public.ipv4 ];
            AAAA = [ config.containers.mtx-co-v6.localAddress6 ];
          };
        } // (
          # matrix./chat./admin./meet.<domain> (turn excluded, see above)
          mapAttrs'
            (_: fqdn: nameValuePair (removeSuffix ".${domain}" fqdn) {
              A = [ config.mine.info.public.ipv4 ];
              AAAA = [ config.containers.caddy.localAddress6 ];
            })
            (removeAttrs config.mine.services.matrix.domains [ "turn" ])
        );
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
        NS = [ "ns1.${domain}." "ns1.first-ns.de." "robotns2.second-ns.de." "robotns3.second-ns.com." ];
      };

      zoneFile = toString (dns.lib.evalZone domain zoneRecords);
      zoneFilePath = builtins.toFile "${domain}.zone" zoneFile;
    in
    {
      mine.services.geoBlock.exemptPorts.tcp = [ 53 ];
      mine.services.geoBlock.exemptPorts.udp = [ 53 ];

      # PowerDNS edns-cookie-secret must be exactly 32 hex chars (16 bytes);
      # agenix-rekey's built-in "hex" generator produces 48 (24 bytes).
      age.generators.hex32 = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -hex 16";
      # hmac-sha256 TSIG keys are base64-encoded 32-byte secrets (pdnsutil's own
      # expected format), not the hex the hex32 generator above produces.
      age.generators.base64_32 = { pkgs, ... }: "${pkgs.openssl}/bin/openssl rand -base64 32";

      noxa.secrets.def = [
        {
          ident = "edns-cookie-secret";
          module = "powerdns";
          hosts = [ "lux" ];
          generator.script = "hex32";
        }
        {
          ident = "tsig-key";
          module = "powerdns";
          hosts = [ "lux" ];
          generator.script = "base64_32";
        }
      ];

      # systemd-nspawn's --bind(-ro)= parses its argument as a colon-separated
      # tuple, remove the colons
      age.secrets.${ednsCookieSecretIdentifier}.name = "powerdns-edns-cookie-secret";
      age.secrets.${tsigKeySecretIdentifier}.name = "powerdns-tsig-key";

      containers.powerdns = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6;
        localAddress6 = luxAddr6For luxPublicNetwork6 "powerdns";
        ephemeral = true;
        inherit specialArgs;

        bindMounts.data = {
          hostPath = "/persist/data/powerdns";
          mountPoint = "/var/lib/powerdns";
          isReadOnly = false;
        };
        bindMounts.ednsCookieSecret = {
          hostPath = ednsCookieSecret.path;
          mountPoint = "/run/secrets/powerdns-edns-cookie-secret";
          isReadOnly = true;
        };
        bindMounts.tsigKeySecret = {
          hostPath = tsigKeySecret.path;
          mountPoint = "/run/secrets/powerdns-tsig-key";
          isReadOnly = true;
        };

        config = { pkgs, ... }: {
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit hostAddress6; }) ];

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

              # Avoid disclosing the exact PowerDNS version to CH TXT version.bind queries
              version-string=anonymous

              include-dir=/run/pdns/secrets

              allow-axfr-ips=${concatStringsSep "," hetznerSecondaries}
              also-notify=${concatStringsSep "," hetznerSecondaries}
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
            "+${pkgs.writeShellScript "pdns-edns-cookie-conf" ''
              mkdir -p /run/pdns/secrets
              echo "edns-cookie-secret=$(cat /run/secrets/powerdns-edns-cookie-secret)" > /run/pdns/secrets/edns-cookie-secret.conf
              chown pdns:pdns /run/pdns/secrets/edns-cookie-secret.conf
              chmod 600 /run/pdns/secrets/edns-cookie-secret.conf
            ''}"
            "+${pkgs.writeShellScript "pdns-tsig-key-import" ''
              ${pkgs.pdns}/bin/pdnsutil tsigkey import ${tsigKeyName} hmac-sha256 "$(cat /run/secrets/powerdns-tsig-key)"
              ${pkgs.pdns}/bin/pdnsutil tsigkey activate ${domain} ${tsigKeyName} primary
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
