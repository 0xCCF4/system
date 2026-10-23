{ lib
, self
, config
, noxa
, luxAddr6For
, luxPublicNetwork6
, mailserver
, specialArgs
, ...
}:
with lib;
{
  config =
    let
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;
      fqdn = "mail.${domain}";

      hostAddress6 = luxAddr6For "fc00::/64" "mailserver-veth-host";
      localAddress6 = luxAddr6For luxPublicNetwork6 "mailserver";

      # Plaintext login passwords of the mail accounts (`<name>-password`
      # secrets), SNM hashes them for dovecot at start.
      passwordAccounts = [ "postmaster" "vaultwarden" ];
      passwordIdentifier = name: noxa.lib.secrets.computeIdentifier {
        module = "mailserver";
        ident = "${name}-password";
        hosts = [ "lux" ];
      };
      passwordMountPoint = name: "/run/secrets/mailserver-${name}-password";

      dkimKeyIdentifier = noxa.lib.secrets.computeIdentifier {
        module = "mailserver";
        ident = "dkim-key";
        hosts = [ "lux" ];
      };
      dkimPublicKeyFile = config.age.secrets.${dkimKeyIdentifier}.rekeyFile + ".pub";
      # e.g. `example-dkim` for example.org, the `s=` of every signature.
      dkimSelector = "${head (splitString "." domain)}-dkim";

      stateDirs = [ "state" "acme" "redis" "nixos" ];

      # The zone apex plus every subdomain in it (hosts/lux/powerdns.nix),
      # mail.<domain> included.
      mailSubdomains = config.mine.services.powerdns.mailSubdomains;
      mailDomains = [ domain ] ++ mailSubdomains;

      # Submission/IMAP are only reachable via cloud-admin: lux's own address
      # there, proxied into the container (see mail-proxy-* below). Peers
      # resolve mail.<domain> to it, so the certificate still matches.
      wgAddress = (noxa.lib.net.decompose (head config.noxa.wireguard.interfaces.cloud-admin.deviceAddresses)).addressNoMask;
      proxiedPorts = { imaps = 993; submissions = 465; };

      autoconfigXml = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <clientConfig version="1.1">
          <emailProvider id="${domain}">
        ${concatMapStrings (d: "    <domain>${d}</domain>\n") mailDomains}    <displayName>${domain}</displayName>
            <displayShortName>${domain}</displayShortName>
            <incomingServer type="imap">
              <hostname>${fqdn}</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
              <username>%EMAILADDRESS%</username>
            </incomingServer>
            <outgoingServer type="smtp">
              <hostname>${fqdn}</hostname>
              <port>465</port>
              <socketType>SSL</socketType>
              <authentication>password-cleartext</authentication>
              <username>%EMAILADDRESS%</username>
            </outgoingServer>
          </emailProvider>
        </clientConfig>
      '';
      autoconfigResponse = path: ''
        header ${path} Content-Type "application/xml; charset=utf-8"
        respond ${path} <<AUTOCONFIG_XML
        ${autoconfigXml}AUTOCONFIG_XML 200
      '';
    in
    {
      # Private key (PEM) is the secret, the base64 DER public key (DKIM `p=`)
      # goes to `<secret>.pub`, same as noxa's nix-store-key generator.
      age.generators.dkim-rsa = { pkgs, file, ... }: ''
        key=$(${pkgs.openssl}/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048)
        printf '%s\n' "$key" | ${pkgs.openssl}/bin/openssl pkey -pubout -outform DER \
          | ${pkgs.coreutils}/bin/base64 -w0 > ${escapeShellArg (file + ".pub")}
        printf '%s\n' "$key"
      '';

      noxa.secrets.def = map
        (name: {
          ident = "${name}-password";
          module = "mailserver";
          hosts = [ "lux" ];
          generator.script = "alnum";
        })
        passwordAccounts ++ [
        {
          ident = "dkim-key";
          module = "mailserver";
          hosts = [ "lux" ];
          generator.script = "dkim-rsa";
        }
      ];

      age.secrets = listToAttrs (map
        (name: nameValuePair (passwordIdentifier name) { name = "mailserver-${name}-password"; })
        passwordAccounts) // {
        ${dkimKeyIdentifier}.name = "mailserver-dkim-key";
      };

      mine.services.powerdns.dkimSelector = dkimSelector;
      mine.services.powerdns.dkimPublicKey =
        if pathExists dkimPublicKeyFile then removeSuffix "\n" (readFile dkimPublicKeyFile) else null;

      # nspawn refuses to start if a bind mount's source is missing.
      systemd.tmpfiles.rules = map (dir: "d /persist/data/mailserver/${dir} 0750 root root -") stateDirs;

      mine.services.geoBlock.exemptPorts.tcp = [ 25 ];

      containers.caddy.config.services.caddy.virtualHosts = {
        "http://${fqdn}".extraConfig = ''
          reverse_proxy /.well-known/acme-challenge/* [${localAddress6}]:80
          respond 404
        '';

        "autoconfig.${domain}".extraConfig = autoconfigResponse "/mail/config-v1.1.xml" + ''
          respond 404
        '';
        ${domain}.extraConfig = autoconfigResponse "/.well-known/autoconfig/mail/config-v1.1.xml";
      };

      networking.firewall.interfaces.cloud-admin.allowedTCPPorts = attrValues proxiedPorts;
      noxa.wireguard.interfaces.cloud-admin.dns.extraNames = [ fqdn ];
      systemd.sockets = mapAttrs'
        (name: port: nameValuePair "mail-proxy-${name}" {
          wantedBy = [ "sockets.target" ];
          listenStreams = [ "${wgAddress}:${toString port}" ];
          # cloud-admin may come up after sockets.target
          socketConfig.FreeBind = true;
        })
        proxiedPorts;
      systemd.services = mapAttrs'
        (name: port: nameValuePair "mail-proxy-${name}" {
          requires = [ "mail-proxy-${name}.socket" ];
          after = [ "mail-proxy-${name}.socket" ];
          serviceConfig = {
            ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd [${localAddress6}]:${toString port}";
            DynamicUser = true;
            PrivateTmp = true;
          };
        })
        proxiedPorts // {
        "container@mailserver".postStart = mkAfter ''
          systemctl --machine=mailserver start --no-block ${escapeShellArg "acme-order-renew-${fqdn}.service"} \
            || echo "could not trigger the ACME order in the mailserver container" >&2
        '';
      };

      containers.mailserver = {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress6 localAddress6;
        ephemeral = true;
        inherit specialArgs;

        bindMounts = {
          state = {
            hostPath = "/persist/data/mailserver/state";
            mountPoint = "/var/lib/mailserver";
            isReadOnly = false;
          };
          acme = {
            hostPath = "/persist/data/mailserver/acme";
            mountPoint = "/var/lib/acme";
            isReadOnly = false;
          };
          redis = {
            hostPath = "/persist/data/mailserver/redis";
            mountPoint = "/var/lib/redis-rspamd";
            isReadOnly = false;
          };
          nixos = {
            hostPath = "/persist/data/mailserver/nixos";
            mountPoint = "/var/lib/nixos";
            isReadOnly = false;
          };
        } // listToAttrs (map
          (name: nameValuePair "${name}Password" {
            hostPath = config.age.secrets.${passwordIdentifier name}.path;
            mountPoint = passwordMountPoint name;
            isReadOnly = true;
          })
          passwordAccounts) // {
          dkimKey = {
            hostPath = config.age.secrets.${dkimKeyIdentifier}.path;
            mountPoint = "/run/secrets/mailserver-dkim-key";
            isReadOnly = true;
          };
        };

        config = { pkgs, ... }: {
          imports = [
            mailserver.nixosModules.mailserver
            (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; })
          ];

          # lego's standalone HTTP-01 listener (see security.acme below).
          networking.firewall.allowedTCPPorts = [ 80 ];

          networking.nameservers = mkForce [ "::1" ];
          services.unbound = {
            enable = true;
            settings.server = {
              interface = [ "::1" ];
              access-control = [ "::1/128 allow" ];
              module-config = ''"dns64 validator iterator"'';
              dns64-prefix = "64:ff9b::/96";
              do-ip4 = false;
              do-nat64 = true;
              nat64-prefix = "64:ff9b::/96";
            };
          };

          security.acme = {
            acceptTerms = true;
            defaults.email = "security@${domain}";
            certs.${fqdn}.listenHTTP = ":80";
          };
          # No carrier until the host configured its veth end, see
          # container@mailserver's postStart above.
          systemd.services."acme-order-renew-${fqdn}".serviceConfig.ExecCondition =
            "${pkgs.gnugrep}/bin/grep -qx 1 /sys/class/net/eth0/carrier";

          services.postfix.settings.main.inet_protocols = "ipv6";

          # The bind-mounted secret is root-only; hand rspamd its own copy.
          systemd.services.rspamd.serviceConfig.LoadCredential =
            [ "dkim.key:/run/secrets/mailserver-dkim-key" ];

          mailserver = {
            enable = true;
            stateVersion = 5;
            inherit fqdn;
            domains = mailDomains;

            x509.useACMEHost = fqdn;

            storage.path = "/var/lib/mailserver/vmail";
            dkim.keyDirectory = "/var/lib/mailserver/dkim";
            # The agenix key (see dkim-rsa above) instead of generated ones.
            dkim.domains = genAttrs mailDomains (_: {
              selectors.${dkimSelector}.keyFile = "/run/credentials/rspamd.service/dkim.key";
            });

            # Replaced by the unbound instance above.
            localDnsResolver = false;

            accounts = {
              "postmaster@${domain}" = {
                passwordFile = passwordMountPoint "postmaster";
                aliases = [ "@${domain}" ] ++ map (d: "postmaster@${d}") mailSubdomains;
              };
              "info@vault.${domain}" = {
                passwordFile = passwordMountPoint "vaultwarden";
                sendOnly = true;
              };
            };
          };
        };
      };
    };
}
