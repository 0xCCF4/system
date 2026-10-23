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
  options.mine.services.powerdns.mailSubdomains = mkOption {
    type = types.listOf types.str;
    default = [];
    description = "Subdomains that should be included as mail domains.";
  };

  options.mine.services.powerdns.secondaries = mkOption {
    type = types.listOf types.str;
    readOnly = true;
    default =
      let
        v4 = [ "198.51.100.1" "198.51.100.2" "198.51.100.3" ];
        v6 = [ "2001:db8:53::1" "2001:db8:53::2" "2001:db8:53::3" ];
      in
      (map (ip: "64:ff9b::${ip}") v4) ++ v6;
    description = ''
      IPv6 addresses of the Secondary secondaries (the IPv4 ones via NAT64),
      allowed to AXFR and NOTIFYed. hosts/lux/firewall.nix lets the NOTIFYs out.
    '';
  };

  options.mine.services.powerdns.dkimSelector = mkOption {
    type = types.str;
    description = "DKIM selector of dkimPublicKey. Set by hosts/lux/mailserver.nix.";
  };

  options.mine.services.powerdns.dkimPublicKey = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = ''
      Base64 DKIM public key (selector dkimSelector) published for the apex and
      every mail subdomain. Set by hosts/lux/mailserver.nix; null until its
      agenix secret was generated.
    '';
  };

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

      secondarySecondaries = config.mine.services.powerdns.secondaries;

      MX = [
        {
          preference = 10;
          exchange = "mail.${domain}.";
        } # self-hosted, primary
        {
          preference = 20;
          exchange = "mx.example.com.";
        } # MAILBACKUP, fallback
      ];

      # Mail relayed through MAILBACKUP (see the SPF include) is DKIM-signed with
      # MAILBACKUP's selectors, so point them at the keys MAILBACKUP publishes. With
      # an aligned DKIM pass, DMARC passes even when SPF breaks on forwarding.
      mailbackupDkimSelectors = [ "mailbackup-dkim-0002" "mailbackup-dkim-0003" ];
      mailbackupDkim = listToAttrs (map
        (selector: nameValuePair "${selector}._domainkey" {
          CNAME = [ "${selector}._domainkey.example.com." ];
        })
        mailbackupDkimSelectors);

      dkimPublicKey = config.mine.services.powerdns.dkimPublicKey;
      DKIM = optional (dkimPublicKey != null) {
        selector = config.mine.services.powerdns.dkimSelector;
        p = dkimPublicKey;
      };

      zoneRecords = with dns.lib.combinators; {
        TTL = 86400; # 24h
        SOA = {
          nameServer = "ns1.${domain}.";
          adminEmail = "security@${domain}";
          # Placeholder, the real serial is filled in at pdns start by
          # pdns-zone-serial (see below).
          serial = 0;
          refresh = 86400; # 24h
          retry = 14400; # 4h
          expire = 604800; # 7 days
          minimum = 3600; # 1h
        };
        A = [ config.mine.info.public.ipv4 ];
        AAAA = [ config.containers.caddy.localAddress6 ];
        TXT = [ "v=spf1 mx include:_spf.example.com -all" ];
        # Every subdomain is a mail domain too, with the same MX as the apex.
        subdomains = mapAttrs (_: records:
          records // {
            inherit MX DKIM;
            TXT = [ "v=spf1 include:${domain} -all" ];
          }
        ) ({
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
          poll = {
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
        )) // {
          autoconfig = {
            A = [ config.mine.info.public.ipv4 ];
            AAAA = [ config.containers.caddy.localAddress6 ];
          };
        } // mailbackupDkim;
        inherit MX DKIM;
        # Monitor-only for now: receivers report but don't act. Subdomains
        # without their own _dmarc record fall back to this one.
        DMARC = [
          {
            p = "none";
            rua = "mailto:postmaster+dmarc@${domain}";
          }
        ];
        NS = [ "ns1.${domain}." "ns1.example.net." "ns2.example.net." "ns3.example.net." ];
      };

      zoneFile = toString (dns.lib.evalZone domain zoneRecords);
      zoneFilePath = builtins.toFile "${domain}.zone" zoneFile;
    in
    {
      mine.services.geoBlock.exemptPorts.tcp = [ 53 ];
      mine.services.geoBlock.exemptPorts.udp = [ 53 ];

      mine.services.powerdns.mailSubdomains = map (sub: "${sub}.${domain}")
        (attrNames (removeAttrs zoneRecords.subdomains ([ "autoconfig" ] ++ attrNames mailbackupDkim)));

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
          imports = [ (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; }) ];

          networking.firewall.allowedTCPPorts = [ 53 ];
          networking.firewall.allowedUDPPorts = [ 53 ];

          environment.systemPackages = [ pkgs.pdns ];

          environment.etc."powerdns/named.conf".text = ''
            zone "${domain}" {
              type master;
              file "/run/pdns/zones/${domain}.zone";
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

              primary=yes
              allow-axfr-ips=${concatStringsSep "," secondarySecondaries}
              also-notify=${concatStringsSep "," secondarySecondaries}
            '';
          };

          systemd.services.pdns.serviceConfig.ExecStartPre = [
            "+${pkgs.writeShellScript "pdns-zone-serial" ''
              set -eu
              state=/var/lib/powerdns/zone-serial-${domain}
              hash=$(${pkgs.coreutils}/bin/sha256sum ${zoneFilePath} | ${pkgs.coreutils}/bin/cut -d' ' -f1)
              oldHash= oldSerial=0
              [ -f "$state" ] && read -r oldHash oldSerial < "$state"
              serial=$oldSerial
              if [ "$hash" != "$oldHash" ]; then
                serial=$(( oldSerial + 1 ))
                echo "$hash $serial" > "$state.tmp"
                mv "$state.tmp" "$state"
              fi
              mkdir -p /run/pdns/zones
              ${pkgs.gnused}/bin/sed -E \
                's/^(${escapeRegex domain}\. IN SOA [^(]*\()0 /\1'"$serial"' /' \
                ${zoneFilePath} > /run/pdns/zones/${domain}.zone
              ${pkgs.gnugrep}/bin/grep -q "(''${serial} " /run/pdns/zones/${domain}.zone
              chmod 0644 /run/pdns/zones/${domain}.zone
            ''}"
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
