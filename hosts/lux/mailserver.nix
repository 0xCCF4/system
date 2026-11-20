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
  # Host-level mirror of the mail-service-tag option.  The host has no
  # mailserver and no milter.  The option exists so that the auto-imported
  # private module (external/private/nixos/mailServiceTags.nix) can set the
  # service->tag mapping at host level.  The container is a separate eval.
  # It receives the value via `mailServiceTagServices` below and imports the
  # full module (mailServiceTag.nix) that builds the milter service.
  options.mine.services.mailServiceTag = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the mail-service-tag milter (container only).";
    };
    socket = lib.mkOption { type = lib.types.str; };
    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Write detailed milter decisions to the journal.";
    };
    services = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Recipient local-part to Subject-tag mapping, set in external/private.";
    };
  };

  config =
    let
      domain = self.lib.requireOption "mine.info.domain" config.mine.info.domain;
      fqdn = "mail.${domain}";

      hostAddress6 = luxAddr6For "fc00::/64" "mailserver-veth-host";
      localAddress6 = luxAddr6For luxPublicNetwork6 "mailserver";

      # Service alias -> tag mapping, set privately in external/private.  The
      # container (a separate eval) receives it as a plain value below.
      mailServiceTagServices = config.mine.services.mailServiceTag.services;

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

      stateDirs = [ "state" "acme" "redis" "nixos" "clamav" ];

      # The zone apex plus every subdomain in it (hosts/lux/powerdns.nix),
      # mail.<domain> included.
      mailSubdomains = config.mine.services.powerdns.mailSubdomains;
      mailDomains = [ domain ] ++ mailSubdomains;

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

      age.secrets = listToAttrs
        (map
          (name: nameValuePair (passwordIdentifier name) { name = "mailserver-${name}-password"; })
          passwordAccounts) // {
        ${dkimKeyIdentifier}.name = "mailserver-dkim-key";
      };

      mine.services.powerdns.dkimSelector = dkimSelector;
      mine.services.powerdns.dkimPublicKey =
        if pathExists dkimPublicKeyFile then removeSuffix "\n" (readFile dkimPublicKeyFile) else null;

      # nspawn refuses to start if a bind mount's source is missing.
      systemd.tmpfiles.rules = map
        (dir:
          if dir == "state"
          then "d /persist/data/mailserver/${dir} 0755 root root -"
          else "d /persist/data/mailserver/${dir} - - - -")
        stateDirs;

      mine.services.geoBlock.exemptPorts.tcp = [ 25 ];

      containers.caddy.config.services.caddy.virtualHosts = {
        "http://${fqdn}".extraConfig = ''
          reverse_proxy /.well-known/acme-challenge/* [${config.containers.mailserver.localAddress6}]:80
          respond 404
        '';

        "autoconfig.${domain}".extraConfig = autoconfigResponse "/mail/config-v1.1.xml" + ''
          respond 404
        '';
        ${domain}.extraConfig = autoconfigResponse "/.well-known/autoconfig/mail/config-v1.1.xml";
      };

      mine.guestUla.containers = [ "mailserver" ];
      noxa.wireguard.interfaces.cloud-admin.dns.extraHosts.${fqdn} = [ config.mine.guestUla.addresses.mailserver ];
      systemd.services."container@mailserver".postStart = mkAfter ''
        systemctl --machine=mailserver start --no-block ${escapeShellArg "acme-order-renew-${fqdn}.service"} \
          || echo "could not trigger the ACME order in the mailserver container" >&2
      '';

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
          clamav = {
            hostPath = "/persist/data/mailserver/clamav";
            mountPoint = "/var/lib/clamav";
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
            (import ../../modules/nixos/mine/mailReplyAlias.nix)
            (import ../../modules/nixos/mine/mailMilter.nix)
            (import ../../modules/nixos/mine/mailServiceTag.nix)
            mailserver.nixosModules.mailserver
            (import ./container-common.nix { inherit (config.system) stateVersion; inherit (config.time) timeZone; inherit hostAddress6; })
          ];

          # Aggregate all postfix milters into one ordered list (see
          # mailMilter.nix).  rspamd's milter is the plain (default) entry;
          # milters tagged mkBefore, here reply-alias, sort ahead of it.
          mine.services.mailMilter = {
            enable = true;
            milters = [ "unix:/run/rspamd/rspamd-milter.sock" ];
          };

          # Reply-as-alias: rewrite outbound replies to send from the alias the
          # original message was delivered to (only for the postmaster catch-all
          # account, and only for aliases it is authorised to send from).  The
          # message-id -> alias store lives inside the persisted state mount,
          # because the container root is ephemeral.
          mine.services.mailReplyAlias = {
            enable = true;
            statePath = "/var/lib/mailserver/milters";
            accounts.postmaster = {
              login = "postmaster@${domain}";
              primary = "postmaster@${domain}";
            };
          };

          # Tag inbound mail to a known service alias with its `[service]`
          # subject prefix.  Only messages that are not S/MIME or PGP signed
          # are tagged.  The service->tag mapping is private, set at host level
          # from external/private and passed in via mailServiceTagServices.
          mine.services.mailServiceTag = {
            enable = true;
            debug = true;
            services = mailServiceTagServices;
          };

          # lego's standalone HTTP-01 listener (see security.acme below).
          networking.firewall.allowedTCPPorts = [ 80 ];

          networking.nameservers = mkForce [ "::1" ];
          networking.resolvconf.extraOptions = [ "trust-ad" ];
          services.unbound = {
            enable = true;
            resolveLocalQueries = false;
            settings.server = {
              interface = [ "::1" ];
              access-control = [ "::1/128 allow" ];
              module-config = ''"dns64 validator iterator"'';
              dns64-prefix = "64:ff9b::/96";
              do-ip4 = false;
              do-nat64 = true;
              nat64-prefix = "64:ff9b::/96";
              hide-identity = true;
              hide-version = true;
              deny-any = true; # no ANY answers (mostly used for amplification)
              # DNS rebinding, but not 127.0.0.0/8: the DNS blocklists answer with 127.0.0.x
              # (an MX on loopback is refused by postfix itself)
              private-address = filter (address: address != "127.0.0.0/8") config.mine.services.unbound.privateAddresses;
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

          services.postfix.settings.main.mynetworks = [ ];
          services.postfix.settings.main.smtpd_relay_restrictions = lib.mkForce [
            "permit_sasl_authenticated"
            "reject_unauth_destination"
          ];
          services.postfix.setSendmail = false;

          # rspamd's url_redirector requests the URL shorteners found in mails (bit.ly
          # etc.) to resolve them: per-recipient tracking links would confirm to the
          # sender that the address is live and the mail arrived.
          services.rspamd.overrides."url_redirector.conf".text = "enabled = false;";

          # The bind-mounted secret is root-only; hand rspamd its own copy.
          systemd.services.rspamd.serviceConfig.LoadCredential =
            [ "dkim.key:/run/secrets/mailserver-dkim-key" ];

          # IPv4 senders arrive through Jool as 64:ff9b::<v4>. Hand rspamd the
          # embedded IPv4 address before any check runs, so SPF, RBLs and
          # greylisting see the real sender instead of the NAT64 address.
          services.rspamd.localLuaRules = pkgs.writeText "rspamd.local.lua" ''
            local rspamd_ip = require "rspamd_ip"
            local lua_util = require "lua_util"

            rspamd_config:register_symbol({
              name = 'NAT64_UNMAPPED',
              type = 'prefilter',
              priority = lua_util.symbols_priorities.top + 1,
              flags = 'empty,nostat',
              callback = function(task)
                local ip = task:get_from_ip()
                if not (ip and ip:is_valid() and ip:get_version() == 6) then return end
                if tostring(ip:apply_mask(96)) ~= '64:ff9b::' then return end
                local o = ip:to_table()
                task:set_from_ip(rspamd_ip.from_string(
                  string.format('%d.%d.%d.%d', o[13], o[14], o[15], o[16])))
              end,
            })
          '';

          # clamd exits without a signature database, and freshclam can't fetch
          # one before the host gives eth0 a carrier; keep both retrying.
          systemd.services.clamav-freshclam.serviceConfig = {
            Restart = "on-failure";
            RestartSec = "1min";
          };
          systemd.services.clamav-daemon.serviceConfig = {
            Restart = "on-failure";
            RestartSec = "1min";
            # clamav-daemon.socket lives in /run/clamav; without this every
            # clamd stop deletes the socket file while the socket unit listens on
            RuntimeDirectoryPreserve = "yes";
          };
          # SNM makes rspamd require clamd, so a missing database would take
          # spam filtering down with it; rspamd copes with clamd being away.
          systemd.services.rspamd.requires = mkForce [ "redis-rspamd.service" ];
          systemd.services.rspamd.wants = [ "clamav-daemon.service" ];

          mailserver = {
            enable = true;
            stateVersion = 5;
            inherit fqdn;
            domains = mailDomains;

            virusScanning = true;

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
                aliases = [ "@${domain}" ] ++ map (d: "@${d}") mailSubdomains;
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
